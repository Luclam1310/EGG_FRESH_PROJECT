/********************************************************
* Title    : UART Tx
* Board    : Tang Nano 20K (27MHz / 115200 baud)
* FIFO     : nandland FIFO (WIDTH=8, DEPTH=256)
*
* Baud rate: 27_000_000 / 234 = 115200
* FIFO depth 256 bytes — đủ cho 1 dòng output AS7263
********************************************************/
module uart_tx (
    input   wire            i_clk,
    input   wire            i_res_n,
    input   wire            i_wen,      // write enable từ as7263_driver
    input   wire    [7:0]   i_data,     // data byte từ as7263_driver
    output  wire            o_full,     // FIFO full → as7263_driver dừng ghi
    output  wire            o_tx        // UART serial output
);

    // ---- FIFO signals ----
    wire            w_fifo_full;
    wire            w_fifo_empty;
    wire            w_fifo_rd_dv;
    wire    [7:0]   w_fifo_rdata;
    reg             r_fifo_ren;

    // AF/AE level: dùng giá trị mặc định (không cần almost flags)
    wire [$clog2(256)-1:0] w_af_level = 8'd200;
    wire [$clog2(256)-1:0] w_ae_level = 8'd1;

    fifo #(
        .WIDTH ( 8   ),
        .DEPTH ( 256 )
    ) u_fifo (
        .i_Rst_L    ( i_res_n       ),
        .i_Clk      ( i_clk         ),
        // Write port
        .i_Wr_DV    ( i_wen              ),
        .i_Wr_Data  ( i_data        ),
        .i_AF_Level ( w_af_level    ),
        .o_AF_Flag  (               ),   // không dùng
        .o_Full     ( w_fifo_full   ),
        // Read port
        .i_Rd_En    ( r_fifo_ren            ),
        .o_Rd_DV    ( w_fifo_rd_dv  ),
        .o_Rd_Data  ( w_fifo_rdata  ),
        .i_AE_Level ( w_ae_level    ),
        .o_AE_Flag  (               ),   // không dùng
        .o_Empty    ( w_fifo_empty  )
    );

    assign o_full = w_fifo_full;

    // ---- Baud rate: 27MHz / 234 = 115200 ----
    reg     [7:0]   r_baud_cnt;
    reg             r_tx_busy;
    wire            w_baud_pls = (r_baud_cnt == 8'd233);

    always @(posedge i_clk or negedge i_res_n) begin
        if (~i_res_n)
            r_baud_cnt <= 8'd0;
        else if (~r_tx_busy || w_baud_pls)
            r_baud_cnt <= 8'd0;
        else
            r_baud_cnt <= r_baud_cnt + 8'd1;
    end

    // ---- Bit counter & FIFO read control ----
    reg     [3:0]   r_bit_cnt;
    reg     [7:0]   r_tx_data;   // latch data khi đọc từ FIFO

    always @(posedge i_clk or negedge i_res_n) begin
        if (~i_res_n) begin
            r_bit_cnt  <= 4'd0;
            r_tx_busy  <= 1'b0;
            r_fifo_ren <= 1'b0;
            r_tx_data  <= 8'd0;
        end else begin
            if (~r_tx_busy) begin
                if (~w_fifo_empty) begin
                    r_bit_cnt  <= 4'd0;
                    r_tx_busy  <= 1'b1;
                    r_fifo_ren <= 1'b1;   // pulse đọc 1 byte từ FIFO
                end
            end else begin
                r_fifo_ren <= 1'b0;
                // Latch data khi FIFO xác nhận read valid
                if (w_fifo_rd_dv)
                    r_tx_data <= w_fifo_rdata;
                if (w_baud_pls) begin
                    r_bit_cnt <= r_bit_cnt + 4'd1;
                    if (r_bit_cnt == 4'd10)
                        r_tx_busy <= 1'b0;
                end
            end
        end
    end

    // ---- Shift register & serial output ----
    reg             r_uart_tx;
    reg     [9:0]   r_tx_shift;   // {STOP, DATA[7:0], START}

    always @(posedge i_clk or negedge i_res_n) begin
        if (~i_res_n) begin
            r_uart_tx  <= 1'b1;
            r_tx_shift <= 10'd0;
        end else if (~r_tx_busy) begin
            r_uart_tx  <= 1'b1;
            r_tx_shift <= 10'd0;
        end else if (w_baud_pls) begin
            if (r_tx_shift == 10'd0) begin
                r_uart_tx  <= 1'b1;
                r_tx_shift <= {1'b1, r_tx_data, 1'b0};
            end else begin
                r_uart_tx  <= r_tx_shift[0];
                r_tx_shift <= {1'b0, r_tx_shift[9:1]};
            end
        end
    end

    assign o_tx = r_uart_tx;

endmodule
