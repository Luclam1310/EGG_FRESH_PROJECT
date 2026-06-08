/*************************************************************
 * as7263_driver.sv  — viết lại hoàn toàn
 * Tang Nano 20K — 27 MHz
 * Sensor: AS7263 NIR (I2C 7-bit addr 0x49)
 *
 * Dùng i2c_byte.sv (custom):
 *   i_rw=0 (WRITE): START|ADDR_W|ACK|i_reg|ACK|i_data|ACK|STOP
 *   i_rw=1 (READ):  START|ADDR_W|ACK|i_reg|ACK|RST|ADDR_R|ACK|data|NACK|STOP
 *
 * ══════════════════════════════════════════════════════════
 * AS7263 Virtual Register Protocol:
 *
 *   Physical registers:
 *     0x00 = STATUS_REG (read-only): bit0=RX_VALID, bit1=TX_VALID
 *     0x01 = WRITE_REG  (write):     ghi virtual addr | vdata vào đây
 *     0x02 = READ_REG   (read-only): đọc kết quả virtual read
 *
 *   Ghi virtual reg [vaddr] = [vdata]:
 *     1. READ  phys 0x00 → chờ status[1]=0 (TX_VALID=0)
 *     2. WRITE phys 0x01 ← (vaddr | 0x80)
 *     3. READ  phys 0x00 → chờ status[1]=0
 *     4. WRITE phys 0x01 ← vdata
 *
 *   Đọc virtual reg [vaddr]:
 *     1. READ  phys 0x00 → chờ status[1]=0
 *     2. WRITE phys 0x01 ← vaddr (MSB=0)
 *     3. READ  phys 0x00 → chờ status[0]=1 (RX_VALID=1)
 *     4. READ  phys 0x02 → kết quả
 *************************************************************/
module as7263_driver (
    input  wire       i_clk,
    input  wire       i_rst_n,
    output wire       o_scl,
    inout  wire       io_sda,
    output reg        o_wen,
    output reg [7:0]  o_wdata,
    output reg        o_led_busy,
    // --- THÊM 4 DÒNG NÀY VÀO ĐÂY ---
    output reg        o_ai_start,   // Lệnh bắt đầu chạy AI
    input  wire       i_ai_done,    // AI báo đã xong
    input  wire [7:0] i_ai_score,   // Kết quả AI trả về
    output reg [15:0] o_ch_raw [0:5] // 6 kênh NIR gửi sang AI
);
    localparam [6:0] ADDR = 7'h49;

    // ---- i2c_byte ----
    reg        r_start;
    reg        r_rw;
    reg  [7:0] r_reg;
    reg  [7:0] r_wdat;
    wire [7:0] w_rdat;
    wire       w_done;
    wire       w_busy;

    i2c_master #(.CLK_DIV(16'd67)) u_i2c (
        .i_clk   (i_clk),   .i_rst_n (i_rst_n),
        .i_start (r_start), .i_rw    (r_rw),
        .i_reg   (r_reg),   .i_data  (r_wdat),
        .i_addr  (ADDR),
        .o_busy  (w_busy),  .o_done  (w_done),
        .o_data  (w_rdat),  .o_ack_ok(),
        .o_scl   (o_scl),   .io_sda  (io_sda)
    );

    // ---- Hex char ----
    function automatic [7:0] hc;
        input [3:0] n;
        hc = (n<10) ? (8'h30+{4'd0,n}) : (8'h37+{4'd0,n});
    endfunction

    // ---- Power-on 200ms delay (AS7263 boot time) ----
    reg [22:0] r_pon;
    wire w_pon = (r_pon == 23'd5_399_999);
    always @(posedge i_clk or negedge i_rst_n)
        if (!i_rst_n) r_pon<=0; else if (!w_pon) r_pon<=r_pon+1;

    // ---- 1-second tick ----
    reg [24:0] r_1s;
    wire w_1s = (r_1s == 25'd26_999_999);
    always @(posedge i_clk or negedge i_rst_n)
        if (!i_rst_n) r_1s<=0; else if(w_1s) r_1s<=0; else r_1s<=r_1s+1;

    // ════════════════════════════════════════════════
    // FSM states
    // Pattern cho mỗi I2C transaction:
    //   ST_xxx_GO  : set r_start=1 (chỉ khi !w_busy)
    //   ST_xxx_WAIT: chờ w_done
    // ════════════════════════════════════════════════
    localparam [6:0]
        ST_PON=0,
        // virtual WRITE
        ST_VW1_GO=1,  ST_VW1_W=2,   // READ status, chờ TX_VALID=0
        ST_VW2_GO=3,  ST_VW2_W=4,   // WRITE vaddr|0x80
        ST_VW3_GO=5,  ST_VW3_W=6,   // READ status, chờ TX_VALID=0
        ST_VW4_GO=7,  ST_VW4_W=8,   // WRITE vdata
        // virtual READ
        ST_VR1_GO=10, ST_VR1_W=11,  // READ status, chờ TX_VALID=0
        ST_VR2_GO=12, ST_VR2_W=13,  // WRITE vaddr
        ST_VR3_GO=14, ST_VR3_W=15,  // READ status, chờ RX_VALID=1
        ST_VR4_GO=16, ST_VR4_W=17,  // READ phys 0x02
        // init
        ST_CTRL=20, ST_INT=21, ST_LEDCTRL=22, ST_VER=23, ST_PRHW=24,
        // loop
        ST_WAIT=30, ST_CHRD=31, ST_CHSV=32, ST_PRINT=33,

        ST_AI_WAIT=34; // <--- THÊM DÒNG NÀY

    reg [6:0] r_st, r_ret;
    reg [7:0] r_vaddr, r_vdata, r_vres;
    reg [3:0] r_chi;
    reg [7:0] r_ch[0:11];
    reg [5:0] r_step;
    reg [7:0] r_hwver;
    integer k;

    always @(posedge i_clk or negedge i_rst_n) begin
        if (!i_rst_n) begin
            r_st<=ST_PON; r_ret<=ST_PON;
            r_vaddr<=0; r_vdata<=0; r_vres<=0;
            r_chi<=0; r_step<=0; r_hwver<=0;
            r_start<=0; r_rw<=0; r_reg<=0; r_wdat<=0;
            o_wen<=0; o_wdata<=0; o_led_busy<=0;
            for(k=0;k<12;k=k+1) r_ch[k]<=0;
        end else begin
            r_start<=0; o_wen<=0;  // default clear every cycle

            case (r_st)

            //────────────────────────────────────────────
            ST_PON: begin
                o_led_busy<=1;
                if (w_pon) r_st<=ST_CTRL;
            end

            //════════════════════════════════════════════
            // VIRTUAL WRITE sub-routine
            // Pre: r_vaddr, r_vdata set; r_ret = return state
            //════════════════════════════════════════════

            ST_VW1_GO: begin  // READ phys 0x00 = STATUS
                if (!w_busy) begin
                    r_rw<=1; r_reg<=8'h00; r_start<=1; r_st<=ST_VW1_W;
                end
            end
            ST_VW1_W: begin
                if (w_done) begin
                    if (w_rdat[1]==0) r_st<=ST_VW2_GO;  // TX_VALID=0 → OK
                    else              r_st<=ST_VW1_GO;  // still busy → poll
                end
            end

            ST_VW2_GO: begin  // WRITE phys 0x01 = (vaddr|0x80)
                if (!w_busy) begin
                    r_rw<=0; r_reg<=8'h01; r_wdat<=(r_vaddr|8'h80); r_start<=1;
                    r_st<=ST_VW2_W;
                end
            end
            ST_VW2_W: if (w_done) r_st<=ST_VW3_GO;

            ST_VW3_GO: begin  // READ phys 0x00 = STATUS
                if (!w_busy) begin
                    r_rw<=1; r_reg<=8'h00; r_start<=1; r_st<=ST_VW3_W;
                end
            end
            ST_VW3_W: begin
                if (w_done) begin
                    if (w_rdat[1]==0) r_st<=ST_VW4_GO;
                    else              r_st<=ST_VW3_GO;
                end
            end

            ST_VW4_GO: begin  // WRITE phys 0x01 = vdata
                if (!w_busy) begin
                    r_rw<=0; r_reg<=8'h01; r_wdat<=r_vdata; r_start<=1;
                    r_st<=ST_VW4_W;
                end
            end
            ST_VW4_W: if (w_done) r_st<=r_ret;  // virtual WRITE done

            //════════════════════════════════════════════
            // VIRTUAL READ sub-routine
            // Pre: r_vaddr set; r_ret = return state
            // Post: r_vres = result
            //════════════════════════════════════════════

            ST_VR1_GO: begin  // READ phys 0x00 = STATUS
                if (!w_busy) begin
                    r_rw<=1; r_reg<=8'h00; r_start<=1; r_st<=ST_VR1_W;
                end
            end
            ST_VR1_W: begin
                if (w_done) begin
                    if (w_rdat[1]==0) r_st<=ST_VR2_GO;
                    else              r_st<=ST_VR1_GO;
                end
            end

            ST_VR2_GO: begin  // WRITE phys 0x01 = vaddr (MSB=0)
                if (!w_busy) begin
                    r_rw<=0; r_reg<=8'h01; r_wdat<=r_vaddr; r_start<=1;
                    r_st<=ST_VR2_W;
                end
            end
            ST_VR2_W: if (w_done) r_st<=ST_VR3_GO;

            ST_VR3_GO: begin  // READ phys 0x00 = STATUS
                if (!w_busy) begin
                    r_rw<=1; r_reg<=8'h00; r_start<=1; r_st<=ST_VR3_W;
                end
            end
            ST_VR3_W: begin
                if (w_done) begin
                    if (w_rdat[0]==1) r_st<=ST_VR4_GO;  // RX_VALID=1
                    else              r_st<=ST_VR3_GO;  // poll
                end
            end

            ST_VR4_GO: begin  // READ phys 0x02 = READ_REG
                if (!w_busy) begin
                    r_rw<=1; r_reg<=8'h02; r_start<=1; r_st<=ST_VR4_W;
                end
            end
            ST_VR4_W: begin
                if (w_done) begin
                    r_vres<=w_rdat;
                    r_st<=r_ret;
                end
            end

            //════════════════════════════════════════════
            // INIT SEQUENCE
            //════════════════════════════════════════════

            // CONTROL (virtual 0x04):
            //   bit[1:0]=11 → BANK mode 3 (all 6 channels continuously)
            //   bit[4:3]=00 → Gain 1x
            //   bit[5]  =0  → INT disable
            //   = 0b0000_1100 = 0x0C ... wait
            //
            // AS7263 CONTROL register bits (datasheet):
            //   [1:0] BANK:  00=Mode0, 01=Mode1, 10=Mode2, 11=Mode3(all continuous)
            //   [2]   GAIN0 }
            //   [3]   GAIN1 } 00=1x, 01=3.7x, 10=16x, 11=64x
            //   [4]   INT   : interrupt enable
            //   [5]   DATA_RDY (read-only)
            //   [7:6] RST, reserved
            //   → BANK=3, GAIN=1x, INT=0: 0b0000_0011 = 0x03
            ST_CTRL: begin
                r_vaddr<=8'h04; r_vdata<=8'h03;  // BANK=3(all continuous), GAIN=1x
                r_ret<=ST_INT; r_st<=ST_VW1_GO;
            end

            // INT_T (virtual 0x05) = integration time
            //   value × 2.8ms per step, 0xFF = ~714ms
            ST_INT: begin
                r_vaddr<=8'h05; r_vdata<=8'hFF;
                r_ret<=ST_LEDCTRL; r_st<=ST_VW1_GO;
            end

            // LED_CTRL (virtual 0x07):
            //   bit[0]=1: LED_DRV on (NIR drive LED)
            //   bit[3]=1: LED_IND on (white indicator LED)
            //   bits[2:1]=00: LED_DRV current 12.5mA
            //   bits[5:4]=00: LED_IND current 1mA
            ST_LEDCTRL: begin
                r_vaddr<=8'h07; r_vdata<=8'h09;
                r_ret<=ST_VER; r_st<=ST_VW1_GO;
            end

            // HW_VERSION (virtual 0x00) → expected 0x3F
            ST_VER: begin
                r_vaddr<=8'h00;
                r_ret<=ST_PRHW; r_st<=ST_VR1_GO;
            end

            // Print "HW:XX\r\n"
            ST_PRHW: begin
                if (r_step==0) r_hwver<=r_vres;
                case (r_step)
                    0: begin o_wdata<=8'h48; o_wen<=1; end  // H
                    1: begin o_wdata<=8'h57; o_wen<=1; end  // W
                    2: begin o_wdata<=8'h3A; o_wen<=1; end  // :
                    3: begin o_wdata<=hc(r_hwver[7:4]); o_wen<=1; end
                    4: begin o_wdata<=hc(r_hwver[3:0]); o_wen<=1; end
                    5: begin o_wdata<=8'h0D; o_wen<=1; end  // CR
                    6: begin o_wdata<=8'h0A; o_wen<=1; end  // LF
                    7: begin r_step<=0; r_st<=ST_WAIT; end
                endcase
                if (r_step<7) r_step<=r_step+1;
            end

            //════════════════════════════════════════════
            // MEASUREMENT LOOP
            //════════════════════════════════════════════

            ST_WAIT: begin
                o_led_busy<=0;
                if (w_1s) begin r_chi<=0; o_led_busy<=1; r_st<=ST_CHRD; end
            end

            // Virtual regs 0x08..0x13 = 6 channels × 2 bytes (Hi, Lo)
            //   R_Hi=0x08 R_Lo=0x09  S_Hi=0x0A S_Lo=0x0B
            //   T_Hi=0x0C T_Lo=0x0D  U_Hi=0x0E U_Lo=0x0F
            //   V_Hi=0x10 V_Lo=0x11  W_Hi=0x12 W_Lo=0x13
            ST_CHRD: begin
                if (r_chi<12) begin
                    r_vaddr<=(8'h08+{4'd0,r_chi});
                    r_ret<=ST_CHSV; r_st<=ST_VR1_GO;
                end else begin
                    r_step<=0; r_st<=ST_PRINT;
                    // --- SỬA DÒNG NÀY ---
                    o_ai_start <= 1;        // Kích hoạt AI
                    r_st       <= ST_AI_WAIT; // Nhảy sang đợi AI thay vì in luôn
                end
            end

            ST_CHSV: begin
                r_ch[r_chi]<=r_vres;
                // --- THÊM LOGIC GHÉP 16-BIT ---
                if (r_chi[0] == 1) begin // Sau khi đọc xong byte Thấp (Lo)
                    o_ch_raw[r_chi >> 1] <= {r_ch[r_chi-1], r_vres};
                end
                r_chi<=r_chi+1; r_st<=ST_CHRD;
            end
            
            // --- CHÈN CẢ ĐOẠN NÀY VÀO TRƯỚC ST_PRINT ---
            ST_AI_WAIT: begin
                o_ai_start <= 0; // Tắt lệnh start sau 1 chu kỳ
                if (i_ai_done) begin
                    r_step <= 0;
                    r_st   <= ST_PRINT; // AI xong thì mới đi in kết quả
                end
            end
            // In chuỗi kết quả: "R:XXXX S:XXXX T:XXXX U:XXXX V:XXXX W:XXXX | AI:XX\r\n"
            ST_PRINT: begin
                case (r_step)
                    // Kênh R (r_ch[0], r_ch[1])
                    0:  begin o_wdata <= "R"; o_wen <= 1; end
                    1:  begin o_wdata <= ":"; o_wen <= 1; end
                    2:  begin o_wdata <= hc(r_ch[0][7:4]); o_wen <= 1; end
                    3:  begin o_wdata <= hc(r_ch[0][3:0]); o_wen <= 1; end
                    4:  begin o_wdata <= hc(r_ch[1][7:4]); o_wen <= 1; end
                    5:  begin o_wdata <= hc(r_ch[1][3:0]); o_wen <= 1; end
                    6:  begin o_wdata <= " "; o_wen <= 1; end

                    // Kênh S (r_ch[2], r_ch[3])
                    7:  begin o_wdata <= "S"; o_wen <= 1; end
                    8:  begin o_wdata <= ":"; o_wen <= 1; end
                    9:  begin o_wdata <= hc(r_ch[2][7:4]); o_wen <= 1; end
                    10: begin o_wdata <= hc(r_ch[2][3:0]); o_wen <= 1; end
                    11: begin o_wdata <= hc(r_ch[3][7:4]); o_wen <= 1; end
                    12: begin o_wdata <= hc(r_ch[3][3:0]); o_wen <= 1; end
                    13: begin o_wdata <= " "; o_wen <= 1; end

                    // Kênh T (r_ch[4], r_ch[5])
                    14: begin o_wdata <= "T"; o_wen <= 1; end
                    15: begin o_wdata <= ":"; o_wen <= 1; end
                    16: begin o_wdata <= hc(r_ch[4][7:4]); o_wen <= 1; end
                    17: begin o_wdata <= hc(r_ch[4][3:0]); o_wen <= 1; end
                    18: begin o_wdata <= hc(r_ch[5][7:4]); o_wen <= 1; end
                    19: begin o_wdata <= hc(r_ch[5][3:0]); o_wen <= 1; end
                    20: begin o_wdata <= " "; o_wen <= 1; end

                    // Kênh U (r_ch[6], r_ch[7])
                    21: begin o_wdata <= "U"; o_wen <= 1; end
                    22: begin o_wdata <= ":"; o_wen <= 1; end
                    23: begin o_wdata <= hc(r_ch[6][7:4]); o_wen <= 1; end
                    24: begin o_wdata <= hc(r_ch[6][3:0]); o_wen <= 1; end
                    25: begin o_wdata <= hc(r_ch[7][7:4]); o_wen <= 1; end
                    26: begin o_wdata <= hc(r_ch[7][3:0]); o_wen <= 1; end
                    27: begin o_wdata <= " "; o_wen <= 1; end

                    // Kênh V (r_ch[8], r_ch[9])
                    28: begin o_wdata <= "V"; o_wen <= 1; end
                    29: begin o_wdata <= ":"; o_wen <= 1; end
                    30: begin o_wdata <= hc(r_ch[8][7:4]); o_wen <= 1; end
                    31: begin o_wdata <= hc(r_ch[8][3:0]); o_wen <= 1; end
                    32: begin o_wdata <= hc(r_ch[9][7:4]); o_wen <= 1; end
                    33: begin o_wdata <= hc(r_ch[9][3:0]); o_wen <= 1; end
                    34: begin o_wdata <= " "; o_wen <= 1; end

                    // Kênh W (r_ch[10], r_ch[11])
                    35: begin o_wdata <= "W"; o_wen <= 1; end
                    36: begin o_wdata <= ":"; o_wen <= 1; end
                    37: begin o_wdata <= hc(r_ch[10][7:4]); o_wen <= 1; end
                    38: begin o_wdata <= hc(r_ch[10][3:0]); o_wen <= 1; end
                    39: begin o_wdata <= hc(r_ch[11][7:4]); o_wen <= 1; end
                    40: begin o_wdata <= hc(r_ch[11][3:0]); o_wen <= 1; end
                    
                    // Khoảng cách và phân cách: " | "
                    41: begin o_wdata <= " "; o_wen <= 1; end
                    42: begin o_wdata <= "|"; o_wen <= 1; end
                    43: begin o_wdata <= " "; o_wen <= 1; end
                    44: begin o_wdata <= "D"; o_wen <= 1; end
                    45: begin o_wdata <= "A"; o_wen <= 1; end
                    46: begin o_wdata <= "Y"; o_wen <= 1; end
                    47: begin o_wdata <= ":"; o_wen <= 1; end

                    // IN SỐ NGÀY
                    48: begin o_wdata <= 8'h30 + (i_ai_score / 10); o_wen <= 1; end 
                    49: begin o_wdata <= 8'h30 + (i_ai_score % 10); o_wen <= 1; end 
                    50: begin o_wdata <= " "; o_wen <= 1; end
                    51: begin o_wdata <= "-"; o_wen <= 1; end
                    52: begin o_wdata <= " "; o_wen <= 1; end
                    53: begin 
                        if (i_ai_score <= 10) 
                            o_wdata <= 8'h46; // Chữ 'F' (Fresh)
                        else                  
                            o_wdata <= 8'h42; // Chữ 'B' (Bad/Cũ) - Dùng B cho rõ hơn O
                        o_wen <= 1; 
                    end
                    54: begin o_wdata <= 8'h0D; o_wen <= 1; end 
                    55: begin o_wdata <= 8'h0A; o_wen <= 1; end 
                    56: begin r_step <= 0; r_st <= ST_WAIT; end
                endcase

                if (r_step < 56) r_step <= r_step + 1;
            end

            default: r_st<=ST_PON;
            endcase
        end
    end
endmodule