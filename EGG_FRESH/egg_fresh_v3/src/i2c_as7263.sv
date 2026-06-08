/********************************************************
* File   : i2c_as7263.v
* Board  : Tang Nano 20K (27MHz)
*
* I2C master đặc biệt cho AS7263:
* AS7263 KHÔNG dùng sub-address byte, chỉ dùng:
*   WRITE: START [0x49|W] [data] STOP
*   READ:  START [0x49|R] [byte] NACK STOP
*
* Interface:
*   cmd=1 → WRITE 1 byte (tx_data)
*   cmd=2 → READ  1 byte (→ rx_data)
*   start : pulse HIGH 1 clock để bắt đầu
*   done  : pulse HIGH 1 clock khi xong
*   busy  : HIGH khi đang chạy
*
* Clock: 27MHz / 68 = ~397kHz tick, 4 ticks/bit → ~99kHz I2C
********************************************************/
module i2c_as7263 (
    input   wire        clk,
    input   wire        rst_n,
    input   wire [1:0]  cmd,      // 1=write, 2=read
    input   wire [7:0]  tx_data,
    output  reg  [7:0]  rx_data,
    input   wire        start,
    output  reg         done,
    output  reg         busy,
    inout   wire        scl,
    inout   wire        sda
);
    localparam ADDR = 7'h49;
    localparam DIV  = 6'd67;

    // Baud tick ~99kHz
    reg [5:0] r_div;
    reg       r_tick;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin r_div<=0; r_tick<=0; end
        else if (r_div==DIV) begin r_div<=0; r_tick<=1; end
        else begin r_div<=r_div+1; r_tick<=0; end
    end

    // Open-drain outputs
    reg r_scl_lo, r_sda_lo;
    assign scl = r_scl_lo ? 1'b0 : 1'bz;
    assign sda = r_sda_lo ? 1'b0 : 1'bz;

    // FSM
    localparam [3:0]
        S_IDLE  = 0,
        S_START = 1,   // START condition
        S_ADDR  = 2,   // 8 bits address+rw
        S_AACK  = 3,   // ACK after address
        S_WDATA = 4,   // 8 bits write data
        S_WACK  = 5,   // ACK after write
        S_RDATA = 6,   // 8 bits read data
        S_NACK  = 7,   // NACK after read
        S_STOP  = 8,   // STOP condition
        S_DONE  = 9;

    reg [3:0] r_st;
    reg [1:0] r_ph;    // phase 0-3 per bit
    reg [3:0] r_bit;   // bit index 7..0
    reg [7:0] r_shift;
    reg [1:0] r_cmd;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            r_st<=S_IDLE; r_ph<=0; r_bit<=7;
            r_scl_lo<=0; r_sda_lo<=0;
            r_shift<=0; r_cmd<=0;
            done<=0; busy<=0; rx_data<=0;
        end else begin
            done <= 0;
            if (r_tick) case (r_st)

            S_IDLE: begin
                r_scl_lo<=0; r_sda_lo<=0; busy<=0;
                if (start && cmd!=0) begin
                    r_cmd<=cmd; busy<=1;
                    r_ph<=0; r_st<=S_START;
                end
            end

            // START: SDA low while SCL high
            S_START: case (r_ph)
                0: begin r_sda_lo<=0; r_scl_lo<=0; r_ph<=1; end // ensure SDA,SCL high
                1: begin r_sda_lo<=1; r_ph<=2; end               // SDA low
                2: begin r_scl_lo<=1; r_ph<=3; end               // SCL low
                3: begin
                    // load addr byte: ADDR[6:0] + R/W bit
                    r_shift <= (r_cmd==2) ? {ADDR,1'b1} : {ADDR,1'b0};
                    r_bit<=7; r_ph<=0; r_st<=S_ADDR;
                end
            endcase

            // Send 8-bit addr
            S_ADDR: case (r_ph)
                0: begin r_sda_lo<=~r_shift[7]; r_ph<=1; end // setup bit
                1: begin r_scl_lo<=0; r_ph<=2; end            // SCL high
                2: begin r_ph<=3; end                          // hold
                3: begin
                    r_scl_lo<=1; r_shift<={r_shift[6:0],1'b0};
                    r_ph<=0;
                    if (r_bit==0) r_st<=S_AACK;
                    else r_bit<=r_bit-1;
                end
            endcase

            // Receive ACK after addr
            S_AACK: case (r_ph)
                0: begin r_sda_lo<=0; r_ph<=1; end  // release SDA
                1: begin r_scl_lo<=0; r_ph<=2; end  // SCL high
                2: begin r_ph<=3; end                // sample (ignore ack)
                3: begin
                    r_scl_lo<=1; r_ph<=0;
                    if (r_cmd==1) begin
                        // WRITE: send data byte
                        r_shift<=tx_data; r_bit<=7; r_st<=S_WDATA;
                    end else begin
                        // READ: receive data byte
                        r_bit<=7; r_st<=S_RDATA;
                    end
                end
            endcase

            // Send 8-bit write data
            S_WDATA: case (r_ph)
                0: begin r_sda_lo<=~r_shift[7]; r_ph<=1; end
                1: begin r_scl_lo<=0; r_ph<=2; end
                2: begin r_ph<=3; end
                3: begin
                    r_scl_lo<=1; r_shift<={r_shift[6:0],1'b0};
                    r_ph<=0;
                    if (r_bit==0) r_st<=S_WACK;
                    else r_bit<=r_bit-1;
                end
            endcase

            // Receive ACK after write data
            S_WACK: case (r_ph)
                0: begin r_sda_lo<=0; r_ph<=1; end
                1: begin r_scl_lo<=0; r_ph<=2; end
                2: begin r_ph<=3; end
                3: begin r_scl_lo<=1; r_ph<=0; r_st<=S_STOP; end
            endcase

            // Receive 8-bit read data
            S_RDATA: case (r_ph)
                0: begin r_sda_lo<=0; r_ph<=1; end  // release SDA
                1: begin r_scl_lo<=0; r_ph<=2; end  // SCL high
                2: begin
                    r_shift<={r_shift[6:0], sda};   // sample
                    r_ph<=3;
                end
                3: begin
                    r_scl_lo<=1; r_ph<=0;
                    if (r_bit==0) begin
                        rx_data<=r_shift; r_st<=S_NACK;
                    end else r_bit<=r_bit-1;
                end
            endcase

            // Send NACK (master stops reading)
            S_NACK: case (r_ph)
                0: begin r_sda_lo<=0; r_ph<=1; end  // SDA high = NACK
                1: begin r_scl_lo<=0; r_ph<=2; end
                2: begin r_ph<=3; end
                3: begin r_scl_lo<=1; r_ph<=0; r_st<=S_STOP; end
            endcase

            // STOP: SDA high while SCL high
            S_STOP: case (r_ph)
                0: begin r_sda_lo<=1; r_scl_lo<=1; r_ph<=1; end // SDA low, SCL low
                1: begin r_scl_lo<=0; r_ph<=2; end               // SCL high
                2: begin r_sda_lo<=0; r_ph<=3; end               // SDA high = STOP
                3: begin r_ph<=0; r_st<=S_DONE; end
            endcase

            S_DONE: begin
                done<=1; busy<=0; r_st<=S_IDLE;
            end

            default: r_st<=S_IDLE;
            endcase
        end
    end
endmodule
