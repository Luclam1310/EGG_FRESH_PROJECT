/********************************************************
* File   : as7263_driver.sv
* Board  : Tang Nano 20K (27MHz)
* Sensor : AS7263 NIR (I2C addr 0x49)
* I2C    : i2c_as7263.v (custom, không có sub-addr byte)
*
* AS7263 Virtual Register Protocol:
*   STATUS_REG = 0x00: bit0=RX_VALID, bit1=TX_VALID
*   WRITE_REG  = 0x01: ghi virtual addr hoặc data
*   READ_REG   = 0x02: đọc virtual data
*
*   Tất cả đều là 1-byte transaction thuần:
*     Đọc STATUS:  READ  → nhận STATUS byte
*     Ghi WRITE:   WRITE → gửi data byte
*     Đọc READ:    READ  → nhận data byte
*
*   WRITE virtual reg X = V:
*     1. READ  → STATUS, chờ TX_VALID(bit1)=0
*     2. WRITE → X|0x80  (set virtual addr, MSB=1 = write)
*     3. READ  → STATUS, chờ TX_VALID(bit1)=0
*     4. WRITE → V
*
*   READ virtual reg X:
*     1. READ  → STATUS, chờ TX_VALID(bit1)=0
*     2. WRITE → X       (set virtual addr, MSB=0 = read)
*     3. READ  → STATUS, chờ RX_VALID(bit0)=1
*     4. READ  → data
********************************************************/
module as7263_driver (
    input   wire        i_clk,
    input   wire        i_res_n,
    inout   wire        o_scl,
    inout   wire        io_sda,
    output  reg         o_wen,
    output  reg  [7:0]  o_wdata,
    output  reg         o_led_busy
);

    //----------------------------------------------------------
    // i2c_as7263 instance
    //----------------------------------------------------------
    reg  [1:0] r_cmd;
    reg  [7:0] r_tx;
    wire [7:0] w_rx;
    reg        r_start;
    wire       w_done;
    wire       w_busy;

    i2c_as7263 u_i2c (
        .clk     ( i_clk   ),
        .rst_n   ( i_res_n ),
        .cmd     ( r_cmd   ),
        .tx_data ( r_tx    ),
        .rx_data ( w_rx    ),
        .start   ( r_start ),
        .done    ( w_done  ),
        .busy    ( w_busy  ),
        .scl     ( o_scl   ),
        .sda     ( io_sda  )
    );

    //----------------------------------------------------------
    // Hex formatter
    //----------------------------------------------------------
    function [7:0] hexchr;
        input [3:0] n;
        hexchr = (n<10) ? (8'h30+{4'd0,n}) : (8'h37+{4'd0,n});
    endfunction

    //----------------------------------------------------------
    // Power-on delay 1s
    //----------------------------------------------------------
    reg [24:0] r_pon;
    wire w_pon_done = (r_pon == 25'd26_999_999);
    always @(posedge i_clk or negedge i_res_n) begin
        if (!i_res_n) r_pon <= 0;
        else if (!w_pon_done) r_pon <= r_pon + 1;
    end

    //----------------------------------------------------------
    // 1-second loop timer
    //----------------------------------------------------------
    reg [24:0] r_1s;
    wire w_1s = (r_1s == 25'd26_999_999);
    always @(posedge i_clk or negedge i_res_n) begin
        if (!i_res_n) r_1s <= 0;
        else if (w_1s) r_1s <= 0;
        else r_1s <= r_1s + 1;
    end

    //----------------------------------------------------------
    // FSM
    //----------------------------------------------------------
    localparam [5:0]
        // Power-on
        ST_PON      = 0,
        // Virtual WRITE 4 steps
        ST_VW1      = 1,  // read STATUS chờ TX_VALID=0
        ST_VW2      = 2,  // write addr|0x80
        ST_VW3      = 3,  // read STATUS chờ TX_VALID=0
        ST_VW4      = 4,  // write data
        // Virtual READ 4 steps
        ST_VR1      = 5,  // read STATUS chờ TX_VALID=0
        ST_VR2      = 6,  // write addr
        ST_VR3      = 7,  // read STATUS chờ RX_VALID=1
        ST_VR4      = 8,  // read data
        // Init
        ST_CTRL     = 10, // ghi CONTROL
        ST_INT      = 11, // ghi INT_T
        ST_LED      = 12, // ghi LED_CTRL
        ST_VER      = 13, // đọc HW_VERSION
        ST_PRHW     = 14, // print HW:XX
        // Loop
        ST_WAIT     = 15,
        ST_CHRD     = 16, // đọc channel
        ST_CHSV     = 17, // lưu channel
        ST_PRINT    = 18;

    reg [5:0]  r_st;
    reg [5:0]  r_ret;    // return state sau VW/VR
    reg [7:0]  r_vaddr;  // virtual register address
    reg [7:0]  r_vdata;  // virtual register write data
    reg [7:0]  r_vres;   // virtual register read result

    reg [3:0]  r_chi;           // channel index 0..11
    reg [7:0]  r_ch [0:11];
    reg [5:0]  r_step;
    reg [7:0]  r_hwver;

    integer k;
    always @(posedge i_clk or negedge i_res_n) begin
        if (!i_res_n) begin
            r_st<=ST_PON; r_ret<=ST_PON;
            r_cmd<=0; r_tx<=0; r_start<=0;
            r_vaddr<=0; r_vdata<=0; r_vres<=0;
            r_chi<=0; r_step<=0; r_hwver<=0;
            o_wen<=0; o_wdata<=0; o_led_busy<=0;
            for (k=0;k<12;k=k+1) r_ch[k]<=0;
        end else begin
            r_start <= 0;
            o_wen   <= 0;

            case (r_st)

            //--------------------------------------------------
            // POWER-ON DELAY
            //--------------------------------------------------
            ST_PON: begin
                o_led_busy <= 1;
                if (w_pon_done) r_st <= ST_CTRL;
            end

            //==================================================
            // VIRTUAL WRITE sub-sequence
            // Ghi virtual reg r_vaddr = r_vdata
            // Sau khi xong → r_ret
            //==================================================

            // Step 1: READ → STATUS, chờ TX_VALID(bit1)=0
            ST_VW1: begin
                if (!w_busy && !r_start) begin
                    r_cmd<=2; r_start<=1;  // READ
                end
                if (w_done) begin
                    if (w_rx[1]==0) r_st<=ST_VW2; // TX_VALID=0 → OK
                    // TX_VALID=1 → poll lại
                end
            end

            // Step 2: WRITE → addr|0x80
            ST_VW2: begin
                if (!w_busy && !r_start) begin
                    r_cmd<=1; r_tx<=(r_vaddr|8'h80); r_start<=1;
                end
                if (w_done) r_st<=ST_VW3;
            end

            // Step 3: READ → STATUS, chờ TX_VALID(bit1)=0
            ST_VW3: begin
                if (!w_busy && !r_start) begin
                    r_cmd<=2; r_start<=1;
                end
                if (w_done) begin
                    if (w_rx[1]==0) r_st<=ST_VW4;
                end
            end

            // Step 4: WRITE → data
            ST_VW4: begin
                if (!w_busy && !r_start) begin
                    r_cmd<=1; r_tx<=r_vdata; r_start<=1;
                end
                if (w_done) r_st<=r_ret;
            end

            //==================================================
            // VIRTUAL READ sub-sequence
            // Đọc virtual reg r_vaddr → r_vres
            // Sau khi xong → r_ret
            //==================================================

            // Step 1: READ → STATUS, chờ TX_VALID(bit1)=0
            ST_VR1: begin
                if (!w_busy && !r_start) begin
                    r_cmd<=2; r_start<=1;
                end
                if (w_done) begin
                    if (w_rx[1]==0) r_st<=ST_VR2;
                end
            end

            // Step 2: WRITE → addr (MSB=0 = read request)
            ST_VR2: begin
                if (!w_busy && !r_start) begin
                    r_cmd<=1; r_tx<=r_vaddr; r_start<=1;
                end
                if (w_done) r_st<=ST_VR3;
            end

            // Step 3: READ → STATUS, chờ RX_VALID(bit0)=1
            ST_VR3: begin
                if (!w_busy && !r_start) begin
                    r_cmd<=2; r_start<=1;
                end
                if (w_done) begin
                    if (w_rx[0]==1) r_st<=ST_VR4; // RX_VALID=1 → data sẵn sàng
                    // RX_VALID=0 → poll lại
                end
            end

            // Step 4: READ → data từ AS7263
            ST_VR4: begin
                if (!w_busy && !r_start) begin
                    r_cmd<=2; r_start<=1;
                end
                if (w_done) begin
                    r_vres <= w_rx;
                    r_st   <= r_ret;
                end
            end

            //==================================================
            // MAIN SEQUENCE
            //==================================================

            // Ghi CONTROL (0x04) = 0x08
            // bit3-2=10 → Mode2: đo tất cả 6 kênh liên tục
            // bit6-4=000 → Gain 1x
            ST_CTRL: begin
                r_vaddr<=8'h04; r_vdata<=8'h08;
                r_ret<=ST_INT; r_st<=ST_VW1;
            end

            // Ghi INT_T (0x05) = 0xFF (integration ~700ms)
            ST_INT: begin
                r_vaddr<=8'h05; r_vdata<=8'hFF;
                r_ret<=ST_LED; r_st<=ST_VW1;
            end

            // Ghi LED_CTRL (0x07) = 0x09
            // bit0=1: LED_DRV ON (NIR), bit3=1: LED_IND ON (trắng)
            ST_LED: begin
                r_vaddr<=8'h07; r_vdata<=8'h09;
                r_ret<=ST_VER; r_st<=ST_VW1;
            end

            // Đọc HW_VERSION (0x00) → kỳ vọng 0x3F
            ST_VER: begin
                r_vaddr<=8'h00;
                r_ret<=ST_PRHW; r_st<=ST_VR1;
            end

            // Gửi "HW:XX\r\n"
            ST_PRHW: begin
                if (r_step==0) r_hwver<=r_vres;
                case (r_step)
                    0: begin o_wdata<=8'h48; o_wen<=1; end // H
                    1: begin o_wdata<=8'h57; o_wen<=1; end // W
                    2: begin o_wdata<=8'h3A; o_wen<=1; end // :
                    3: begin o_wdata<=hexchr(r_hwver[7:4]); o_wen<=1; end
                    4: begin o_wdata<=hexchr(r_hwver[3:0]); o_wen<=1; end
                    5: begin o_wdata<=8'h0D; o_wen<=1; end // CR
                    6: begin o_wdata<=8'h0A; o_wen<=1; end // LF
                    7: begin r_step<=0; r_st<=ST_WAIT; end
                endcase
                if (r_step<7) r_step<=r_step+1;
            end

            // Chờ 1 giây
            ST_WAIT: begin
                o_led_busy<=0;
                if (w_1s) begin
                    r_chi<=0; o_led_busy<=1; r_st<=ST_CHRD;
                end
            end

            // Đọc channel byte r_chi (virtual addr 0x08+chi)
            ST_CHRD: begin
                if (r_chi<12) begin
                    r_vaddr<=8'h08+{4'd0,r_chi};
                    r_ret<=ST_CHSV; r_st<=ST_VR1;
                end else begin
                    r_step<=0; r_st<=ST_PRINT;
                end
            end

            // Lưu kết quả, tăng index, đọc tiếp
            ST_CHSV: begin
                r_ch[r_chi]<=r_vres;
                r_chi<=r_chi+1;
                r_st<=ST_CHRD;
            end

            // Gửi "R:XXYY S:XXYY T:XXYY U:XXYY V:XXYY W:XXYY\r\n"
            ST_PRINT: begin
                case (r_step)
                    0:  begin o_wdata<=8'h52; o_wen<=1; end // R
                    1:  begin o_wdata<=8'h3A; o_wen<=1; end // :
                    2:  begin o_wdata<=hexchr(r_ch[0][7:4]); o_wen<=1; end
                    3:  begin o_wdata<=hexchr(r_ch[0][3:0]); o_wen<=1; end
                    4:  begin o_wdata<=hexchr(r_ch[1][7:4]); o_wen<=1; end
                    5:  begin o_wdata<=hexchr(r_ch[1][3:0]); o_wen<=1; end
                    6:  begin o_wdata<=8'h20; o_wen<=1; end
                    7:  begin o_wdata<=8'h53; o_wen<=1; end // S
                    8:  begin o_wdata<=8'h3A; o_wen<=1; end
                    9:  begin o_wdata<=hexchr(r_ch[2][7:4]); o_wen<=1; end
                    10: begin o_wdata<=hexchr(r_ch[2][3:0]); o_wen<=1; end
                    11: begin o_wdata<=hexchr(r_ch[3][7:4]); o_wen<=1; end
                    12: begin o_wdata<=hexchr(r_ch[3][3:0]); o_wen<=1; end
                    13: begin o_wdata<=8'h20; o_wen<=1; end
                    14: begin o_wdata<=8'h54; o_wen<=1; end // T
                    15: begin o_wdata<=8'h3A; o_wen<=1; end
                    16: begin o_wdata<=hexchr(r_ch[4][7:4]); o_wen<=1; end
                    17: begin o_wdata<=hexchr(r_ch[4][3:0]); o_wen<=1; end
                    18: begin o_wdata<=hexchr(r_ch[5][7:4]); o_wen<=1; end
                    19: begin o_wdata<=hexchr(r_ch[5][3:0]); o_wen<=1; end
                    20: begin o_wdata<=8'h20; o_wen<=1; end
                    21: begin o_wdata<=8'h55; o_wen<=1; end // U
                    22: begin o_wdata<=8'h3A; o_wen<=1; end
                    23: begin o_wdata<=hexchr(r_ch[6][7:4]); o_wen<=1; end
                    24: begin o_wdata<=hexchr(r_ch[6][3:0]); o_wen<=1; end
                    25: begin o_wdata<=hexchr(r_ch[7][7:4]); o_wen<=1; end
                    26: begin o_wdata<=hexchr(r_ch[7][3:0]); o_wen<=1; end
                    27: begin o_wdata<=8'h20; o_wen<=1; end
                    28: begin o_wdata<=8'h56; o_wen<=1; end // V
                    29: begin o_wdata<=8'h3A; o_wen<=1; end
                    30: begin o_wdata<=hexchr(r_ch[8][7:4]); o_wen<=1; end
                    31: begin o_wdata<=hexchr(r_ch[8][3:0]); o_wen<=1; end
                    32: begin o_wdata<=hexchr(r_ch[9][7:4]); o_wen<=1; end
                    33: begin o_wdata<=hexchr(r_ch[9][3:0]); o_wen<=1; end
                    34: begin o_wdata<=8'h20; o_wen<=1; end
                    35: begin o_wdata<=8'h57; o_wen<=1; end // W
                    36: begin o_wdata<=8'h3A; o_wen<=1; end
                    37: begin o_wdata<=hexchr(r_ch[10][7:4]); o_wen<=1; end
                    38: begin o_wdata<=hexchr(r_ch[10][3:0]); o_wen<=1; end
                    39: begin o_wdata<=hexchr(r_ch[11][7:4]); o_wen<=1; end
                    40: begin o_wdata<=hexchr(r_ch[11][3:0]); o_wen<=1; end
                    41: begin o_wdata<=8'h0D; o_wen<=1; end // CR
                    42: begin o_wdata<=8'h0A; o_wen<=1; end // LF
                    43: begin r_step<=0; r_st<=ST_WAIT; end
                endcase
                if (r_step<43) r_step<=r_step+1;
            end

            default: r_st<=ST_PON;
            endcase
        end
    end
endmodule
