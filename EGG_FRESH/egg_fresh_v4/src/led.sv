/********************************************************
* Title    : LED Controller for AS7263 project
* Board    : Tang Nano 20K (LEDs active LOW)
*
* LED meaning:
*   R (led[0]) = active LOW — ON khi đang đọc sensor (busy)
*   G (led[1]) = active LOW — flash khi UART đang gửi data
*   B (led[2]) = active LOW — heartbeat blink 1Hz (code đang chạy)
*
* Điều kiện "code đang chạy": LED nhấp nháy 1Hz
* → nhìn vào board thấy LED nhấp nháy = FPGA đã nạp OK
********************************************************/
module led (
    input   wire    i_clk,          // 27MHz
    input   wire    i_res_n,
    input   wire    i_uart_tx,      // UART TX line (active khi gửi)
    input   wire    i_led_busy,     // HIGH khi đang đọc sensor
    output  wire    o_led_r,        // RED   — active LOW
    output  wire    o_led_g,        // GREEN — active LOW
    output  wire    o_led_b         // BLUE  — active LOW
);

    // ---- Heartbeat: 1Hz blink (27_000_000 / 2 = 13_500_000) ----
    reg [23:0] r_hb_cnt;
    reg        r_heartbeat;
    always @(posedge i_clk or negedge i_res_n) begin
        if (~i_res_n) begin
            r_hb_cnt   <= 24'd0;
            r_heartbeat <= 1'b0;
        end else begin
            if (r_hb_cnt == 24'd13_499_999) begin
                r_hb_cnt    <= 24'd0;
                r_heartbeat <= ~r_heartbeat;
            end else begin
                r_hb_cnt <= r_hb_cnt + 24'd1;
            end
        end
    end

    // ---- Green flash: latch when uart_tx active, decay slowly ----
    reg [19:0] r_green_cnt;
    reg        r_green_on;
    always @(posedge i_clk or negedge i_res_n) begin
        if (~i_res_n) begin
            r_green_cnt <= 20'd0;
            r_green_on  <= 1'b0;
        end else begin
            if (~i_uart_tx) begin   // UART TX goes LOW = sending
                r_green_cnt <= 20'd999_999;   // hold ~37ms
                r_green_on  <= 1'b1;
            end else if (r_green_cnt > 20'd0) begin
                r_green_cnt <= r_green_cnt - 20'd1;
            end else begin
                r_green_on  <= 1'b0;
            end
        end
    end

    // ---- LED assignments (active LOW on Tang Nano 20K) ----
    assign o_led_r = ~i_led_busy;    // ON when reading sensor
    assign o_led_g = ~r_green_on;    // ON when UART transmitting
    assign o_led_b = ~r_heartbeat;   // 1Hz blink = code running OK

endmodule
