/********************************************************
* Title    : UART Tx (FIXED)
* Board    : Tang Nano 20K (27MHz / 115200 baud)
* FIFO     : nandland FIFO (WIDTH=8, DEPTH=256)
*
* Baud rate: 27_000_000 / 234 = 115384 ≈ 115200
*
* BUG FIX: shift register có off-by-one 1 baud period.
*
* Lỗi cũ:
*   Khi r_tx_shift == 0 tại w_baud_pls:
*     → xuất r_uart_tx = 1 (idle), load r_tx_shift = {1, data, 0}
*     → chu kỳ baud TIẾP THEO mới xuất bit START (0)
*     → receiver thấy idle thêm 1 baud → frame lệch 1 bit
*     → 0x30 ('0') bị giải mã thành 0x81 → ra "8181..."
*
* Fix: Dùng state machine rõ ràng với các state:
*   IDLE → LOAD → START(1 baud) → DATA[0..7](8 baud) → STOP(1 baud) → IDLE
*   Load data từ FIFO ở IDLE, xuất START bit ngay chu kỳ đầu tiên.
********************************************************/
module uart_tx (
    input   wire            i_clk,
    input   wire            i_res_n,
    input   wire            i_wen,
    input   wire    [7:0]   i_data,
    output  wire            o_full,
    output  wire            o_tx
);

    // ---- FIFO ----
    wire            w_fifo_full;
    wire            w_fifo_empty;
    wire            w_fifo_rd_dv;
    wire    [7:0]   w_fifo_rdata;
    reg             r_fifo_ren;

    wire [7:0] w_af_level = 8'd200;
    wire [7:0] w_ae_level = 8'd1;

    fifo #(
        .WIDTH ( 8   ),
        .DEPTH ( 256 )
    ) u_fifo (
        .i_Rst_L    ( i_res_n    ),
        .i_Clk      ( i_clk      ),
        .i_Wr_DV    ( i_wen      ),
        .i_Wr_Data  ( i_data     ),
        .i_AF_Level ( w_af_level ),
        .o_AF_Flag  (            ),
        .o_Full     ( w_fifo_full),
        .i_Rd_En    ( r_fifo_ren ),
        .o_Rd_DV    ( w_fifo_rd_dv ),
        .o_Rd_Data  ( w_fifo_rdata ),
        .i_AE_Level ( w_ae_level ),
        .o_AE_Flag  (            ),
        .o_Empty    ( w_fifo_empty)
    );

    assign o_full = w_fifo_full;

    // ---- Baud rate: 27MHz / 234 ≈ 115200 ----
    localparam BAUD_DIV = 9'd233;  // count 0..233 = 234 cycles

    reg [8:0]  r_baud_cnt;
    wire       w_baud_pls = (r_baud_cnt == BAUD_DIV);

    always @(posedge i_clk or negedge i_res_n) begin
        if (~i_res_n)
            r_baud_cnt <= 0;
        else if (w_baud_pls)
            r_baud_cnt <= 0;
        else
            r_baud_cnt <= r_baud_cnt + 1;
    end

    // ---- TX State Machine ----
    // state: 0=IDLE, 1=START, 2-9=DATA[0..7], 10=STOP
    localparam ST_IDLE  = 4'd0;
    localparam ST_START = 4'd1;
    localparam ST_STOP  = 4'd10;

    reg [3:0]  r_state;
    reg [7:0]  r_tx_data;   // latched byte
    reg        r_uart_tx;
    reg        r_fifo_ren_d; // delayed 1 cycle để FIFO output ổn định

    always @(posedge i_clk or negedge i_res_n) begin
        if (~i_res_n) begin
            r_state    <= ST_IDLE;
            r_tx_data  <= 8'h00;
            r_uart_tx  <= 1'b1;
            r_fifo_ren <= 1'b0;
            r_fifo_ren_d <= 1'b0;
        end else begin
            r_fifo_ren   <= 1'b0;
            r_fifo_ren_d <= r_fifo_ren;

            // Latch data khi FIFO read valid
            if (w_fifo_rd_dv)
                r_tx_data <= w_fifo_rdata;

            case (r_state)

            ST_IDLE: begin
                r_uart_tx <= 1'b1;  // idle = HIGH
                if (~w_fifo_empty) begin
                    // Phát lệnh đọc FIFO, chờ 1 cycle (r_fifo_ren_d)
                    r_fifo_ren <= 1'b1;
                    r_state    <= 4'd11;  // chờ FIFO
                end
            end

            // State 11: chờ FIFO output ổn định (1 cycle)
            4'd11: begin
                r_uart_tx <= 1'b1;
                r_state   <= ST_START;  // baud counter đang chạy tự do, đồng bộ với nó
            end

            // START bit = 0
            ST_START: begin
                if (w_baud_pls) begin
                    r_uart_tx <= 1'b0;      // xuất START bit
                    r_state   <= 4'd2;      // → DATA[0]
                end
            end

            // DATA[0..7]: r_state = 2..9 → bit index = r_state - 2
            4'd2,4'd3,4'd4,4'd5,4'd6,4'd7,4'd8,4'd9: begin
                if (w_baud_pls) begin
                    r_uart_tx <= r_tx_data[r_state - 4'd2];  // LSB first
                    if (r_state == 4'd9)
                        r_state <= ST_STOP;
                    else
                        r_state <= r_state + 1;
                end
            end

            // STOP bit = 1
            ST_STOP: begin
                if (w_baud_pls) begin
                    r_uart_tx <= 1'b1;
                    r_state   <= ST_IDLE;
                end
            end

            default: r_state <= ST_IDLE;
            endcase
        end
    end

    assign o_tx = r_uart_tx;

endmodule
