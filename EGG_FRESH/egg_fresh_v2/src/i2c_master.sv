/*************************************************************
 * i2c_byte.sv  — I2C Master cho AS7263
 * Tang Nano 20K — 27 MHz, CLK_DIV=67 → 99.3kHz
 *
 * Cả WRITE lẫn READ đều gửi physical register address:
 *
 *  WRITE: START | [ADDR_W] ACK | [i_reg] ACK | [i_data] ACK | STOP
 *  READ:  START | [ADDR_W] ACK | [i_reg] ACK | RESTART
 *               | [ADDR_R] ACK | [byte]  NACK | STOP
 *
 * AS7263 physical registers:
 *   i_reg=0x00 → STATUS_REG (read)
 *   i_reg=0x01 → WRITE_REG  (write vaddr or vdata)
 *   i_reg=0x02 → READ_REG   (read virtual data)
 *
 * Interface:
 *   i_start  : pulse 1 cycle để bắt đầu
 *   i_rw     : 0=WRITE, 1=READ
 *   i_reg    : physical register addr (0x00/0x01/0x02)
 *   i_data   : byte ghi (khi i_rw=0)
 *   o_data   : byte đọc (valid khi o_done=1)
 *   o_done   : pulse 1 cycle khi transaction hoàn thành
 *   o_busy   : HIGH trong suốt transaction
 *************************************************************/
module i2c_master #(
    parameter [15:0] CLK_DIV = 16'd67
)(
    input  wire       i_clk,
    input  wire       i_rst_n,
    input  wire       i_start,
    input  wire       i_rw,
    input  wire [7:0] i_reg,
    input  wire [7:0] i_data,
    input  wire [6:0] i_addr,
    output reg        o_busy,
    output reg        o_done,
    output reg [7:0]  o_data,
    output reg        o_ack_ok,
    output reg        o_scl,
    inout  wire       io_sda
);
    // SDA open-drain: drive=1 → pin LOW; drive=0 → pin Z (pullup=HIGH)
    reg r_sda_drive;
    assign io_sda = r_sda_drive ? 1'b0 : 1'bz;
    wire w_sda = io_sda;

    // Baud tick: 1 pulse every (CLK_DIV+1) cycles
    reg [15:0] r_div;
    reg        r_tick;
    always @(posedge i_clk or negedge i_rst_n) begin
        if (!i_rst_n) begin r_div<=0; r_tick<=0; end
        else if (r_div==CLK_DIV) begin r_div<=0; r_tick<=1; end
        else                     begin r_div<=r_div+1; r_tick<=0; end
    end

    // States
    localparam [4:0]
        S_IDLE    = 0,  S_START   = 1,  S_ADDR_W  = 2,  S_ACK_AW  = 3,
        S_REG_W   = 4,  S_ACK_RW  = 5,  S_DATA_W  = 6,  S_ACK_DW  = 7,
        S_REG_R   = 8,  S_ACK_RR  = 9,  S_RESTART = 10, S_ADDR_R  = 11,
        S_ACK_AR  = 12, S_DATA_R  = 13, S_NACK    = 14, S_STOP    = 15,
        S_DONE    = 16;

    reg [4:0]  r_st;
    reg [1:0]  r_ph;     // quarter-period 0..3
    reg [2:0]  r_bc;     // bit counter 7..0
    reg [7:0]  r_shift;
    reg [7:0]  r_rxbuf;
    reg        r_rw;
    reg [7:0]  r_reg;
    reg [7:0]  r_data;
    reg [6:0]  r_addr;

    // Helper task macro — shift out MSB first
    // Sets SDA from shift[7], then SCL=1, then SCL=0, then shift left
    // Returns to same state until r_bc==0

    always @(posedge i_clk or negedge i_rst_n) begin
        if (!i_rst_n) begin
            r_st<=S_IDLE; r_ph<=0; r_bc<=7;
            r_shift<=0; r_rxbuf<=0; r_rw<=0; r_reg<=0; r_data<=0; r_addr<=0;
            o_busy<=0; o_done<=0; o_data<=0; o_ack_ok<=0;
            o_scl<=1; r_sda_drive<=0;
        end else begin
            o_done <= 0;
            case (r_st)

            //----------------------------------------------------
            S_IDLE: begin
                o_scl<=1; r_sda_drive<=0; o_busy<=0;
                if (i_start) begin
                    r_rw<=i_rw; r_reg<=i_reg; r_data<=i_data; r_addr<=i_addr;
                    o_busy<=1; r_ph<=0; r_st<=S_START;
                end
            end

            //----------------------------------------------------
            // START: hold SCL=1, pull SDA low → then SCL low
            S_START: if (r_tick) case (r_ph)
                0: begin o_scl<=1; r_sda_drive<=0; r_ph<=1; end   // SDA=1 SCL=1
                1: begin           r_sda_drive<=1; r_ph<=2; end   // SDA=0 (START)
                2: begin o_scl<=0;                r_ph<=3; end   // SCL=0
                3: begin
                    r_shift<={r_addr,1'b0}; // ADDR + W
                    r_bc<=7; r_ph<=0; r_st<=S_ADDR_W;
                end
            endcase

            //----------------------------------------------------
            // Generic: shift out r_shift MSB first (8 bits)
            // Used by ADDR_W, REG_W, DATA_W, REG_R, ADDR_R
            S_ADDR_W,
            S_REG_W,
            S_DATA_W,
            S_REG_R,
            S_ADDR_R: if (r_tick) case (r_ph)
                0: begin
                    o_scl<=0;
                    r_sda_drive <= ~r_shift[7]; // bit=0→drive LOW, bit=1→release HIGH
                    r_ph<=1;
                end
                1: begin o_scl<=1; r_ph<=2; end
                2: begin           r_ph<=3; end  // hold high (slave samples here)
                3: begin
                    o_scl<=0;
                    r_shift<={r_shift[6:0],1'b0};
                    if (r_bc==0) begin
                        r_ph<=0;
                        // Branch to next state based on current
                        case (r_st)
                            S_ADDR_W: r_st<=S_ACK_AW;
                            S_REG_W:  r_st<=(r_rw==0) ? S_ACK_RW : S_ACK_RR;
                            S_DATA_W: r_st<=S_ACK_DW;
                            S_REG_R:  r_st<=S_ACK_RR;
                            S_ADDR_R: r_st<=S_ACK_AR;
                            default:  r_st<=S_STOP;
                        endcase
                    end else begin
                        r_bc<=r_bc-1; r_ph<=0;
                    end
                end
            endcase

            //----------------------------------------------------
            // ACK_AW: after ADDR_W — release SDA, read ACK, go to REG
            S_ACK_AW: if (r_tick) case (r_ph)
                0: begin o_scl<=0; r_sda_drive<=0; r_ph<=1; end
                1: begin o_scl<=1; r_ph<=2; end
                2: begin o_ack_ok<=(w_sda==0); r_ph<=3; end
                3: begin
                    o_scl<=0; r_ph<=0;
                    // Both READ and WRITE need to send physical reg addr next
                    r_shift<=r_reg; r_bc<=7;
                    r_st<=(r_rw==0) ? S_REG_W : S_REG_R;
                end
            endcase

            //----------------------------------------------------
            // ACK_RW: after REG_W (write mode) — release SDA, then send data
            S_ACK_RW: if (r_tick) case (r_ph)
                0: begin o_scl<=0; r_sda_drive<=0; r_ph<=1; end
                1: begin o_scl<=1; r_ph<=2; end
                2: begin r_ph<=3; end
                3: begin o_scl<=0; r_ph<=0; r_shift<=r_data; r_bc<=7; r_st<=S_DATA_W; end
            endcase

            //----------------------------------------------------
            // ACK_RR: after REG_R (read mode) — go to RESTART
            S_ACK_RR: if (r_tick) case (r_ph)
                0: begin o_scl<=0; r_sda_drive<=0; r_ph<=1; end
                1: begin o_scl<=1; r_ph<=2; end
                2: begin r_ph<=3; end
                3: begin o_scl<=0; r_ph<=0; r_st<=S_RESTART; end
            endcase

            //----------------------------------------------------
            // ACK_DW: after DATA_W — read slave ACK, then STOP
            S_ACK_DW: if (r_tick) case (r_ph)
                0: begin o_scl<=0; r_sda_drive<=0; r_ph<=1; end
                1: begin o_scl<=1; r_ph<=2; end
                2: begin r_ph<=3; end
                3: begin o_scl<=0; r_ph<=0; r_st<=S_STOP; end
            endcase

            //----------------------------------------------------
            // RESTART: SDA goes H then L while SCL=H
            S_RESTART: if (r_tick) case (r_ph)
                0: begin o_scl<=0; r_sda_drive<=0; r_ph<=1; end  // SDA=1
                1: begin o_scl<=1; r_ph<=2; end
                2: begin r_sda_drive<=1; r_ph<=3; end  // SDA=0 = RESTART
                3: begin
                    o_scl<=0;
                    r_shift<={r_addr,1'b1}; // ADDR + R
                    r_bc<=7; r_ph<=0; r_st<=S_ADDR_R;
                end
            endcase

            //----------------------------------------------------
            // ACK_AR: after ADDR_R — release SDA, read ACK, receive data
            S_ACK_AR: if (r_tick) case (r_ph)
                0: begin o_scl<=0; r_sda_drive<=0; r_ph<=1; end
                1: begin o_scl<=1; r_ph<=2; end
                2: begin r_ph<=3; end
                3: begin o_scl<=0; r_rxbuf<=0; r_bc<=7; r_ph<=0; r_st<=S_DATA_R; end
            endcase

            //----------------------------------------------------
            // DATA_R: receive 8 bits (MSB first, sample on SCL rising)
            S_DATA_R: if (r_tick) case (r_ph)
                0: begin o_scl<=0; r_sda_drive<=0; r_ph<=1; end // release SDA
                1: begin o_scl<=1; r_ph<=2; end
                2: begin r_rxbuf<={r_rxbuf[6:0],w_sda}; r_ph<=3; end // sample
                3: begin
                    o_scl<=0;
                    if (r_bc==0) begin r_ph<=0; r_st<=S_NACK; end
                    else begin r_bc<=r_bc-1; r_ph<=0; end
                end
            endcase

            //----------------------------------------------------
            // NACK: master sends 1 (release SDA=HIGH) then SCL pulse
            S_NACK: if (r_tick) case (r_ph)
                0: begin o_scl<=0; r_sda_drive<=0; r_ph<=1; end // SDA=1=NACK
                1: begin o_scl<=1; r_ph<=2; end
                2: begin r_ph<=3; end
                3: begin o_scl<=0; r_ph<=0; r_st<=S_STOP; end
            endcase

            //----------------------------------------------------
            // STOP: SDA goes L then H while SCL=H
            S_STOP: if (r_tick) case (r_ph)
                0: begin o_scl<=0; r_sda_drive<=1; r_ph<=1; end  // SDA=0
                1: begin o_scl<=1; r_ph<=2; end
                2: begin r_sda_drive<=0; r_ph<=3; end  // SDA=1 = STOP
                3: begin r_ph<=0; r_st<=S_DONE; end
            endcase

            //----------------------------------------------------
            S_DONE: begin
                o_data<=r_rxbuf; o_done<=1; o_busy<=0; r_st<=S_IDLE;
            end

            default: r_st<=S_IDLE;
            endcase
        end
    end
endmodule