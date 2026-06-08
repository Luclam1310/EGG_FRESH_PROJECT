/********************************************************
* Title    : AS7263 NIR Sensor → UART Logger
* Board    : Tang Nano 20K (GW2AR-18 QN88, 27MHz)
* Sensor   : AS7263 (I2C addr 0x49)
*
* Chức năng:
*   1. Power-on: đọc HW_VERSION → gửi "HW:XX\r\n" qua UART
*   2. Cấu hình CONTROL = 0x12 (bank mode 2, gain 2x)
*   3. Mỗi 1 giây: đọc 6 kênh NIR (R,S,T,U,V,W)
*   4. Gửi qua UART: "R:XXXX S:XXXX T:XXXX\r\n"
*
* LED status:
*   LED_R (PIN 15) = ON (LOW) khi đang đọc sensor
*   LED_G (PIN 16) = flash khi UART đang gửi data
*   LED_B (PIN 17) = 1Hz heartbeat — code đang chạy!
*
* Pin mapping:
*   sys_clk = PIN 4   (27MHz)
*   rst     = PIN 88  (S1, nhấn=HIGH)
*   scl     = PIN 49  (I2C SCL, cần 4.7kΩ pullup lên 3.3V)
*   sda     = PIN 48  (I2C SDA, cần 4.7kΩ pullup lên 3.3V)
*   uart_tx = PIN 69  (→ PC qua BL616)
*   led[0]  = PIN 15  (LED R)
*   led[1]  = PIN 16  (LED G)
*   led[2]  = PIN 17  (LED B)
********************************************************/
module top (
    input   wire    sys_clk,    // PIN 4 — 27MHz
    input   wire    rst,        // PIN 88 — S1, nhấn=HIGH → reset

    // I2C (cần 4.7kΩ pullup lên 3.3V)
    inout   wire    scl,        // PIN 49
    inout   wire    sda,        // PIN 48

    // UART
    output  wire    uart_tx,    // PIN 69

    // LEDs (active LOW)
    output  wire    [2:0] led   // PIN 15/16/17
);

    wire rst_n = ~rst;  // S1 active HIGH → rst_n active LOW

    // ---- AS7263 Driver ----
    wire            w_uart_wen;
    wire    [7:0]   w_uart_wdata;
    wire            w_led_busy;

    as7263_driver u_as7263 (
        .i_clk      ( sys_clk    ),
        .i_rst_n    ( rst_n      ),
        .o_scl      ( scl        ),
        .io_sda     ( sda        ),
        .o_wen      ( w_uart_wen ),
        .o_wdata    ( w_uart_wdata ),
        .o_led_busy ( w_led_busy )
    );

    // ---- UART TX (with FIFO) ----
    wire w_uart_tx;
    wire w_fifo_full;
    uart_tx u_uart (
        .i_clk   ( sys_clk    ),
        .i_res_n ( rst_n      ),
        .i_wen   ( w_uart_wen ),
        .i_data  ( w_uart_wdata ),
        .o_full  ( w_fifo_full ),
        .o_tx    ( w_uart_tx  )
    );
    assign uart_tx = w_uart_tx;

    // ---- LED Controller ----
    led u_led (
        .i_clk      ( sys_clk    ),
        .i_res_n    ( rst_n      ),
        .i_uart_tx  ( w_uart_tx  ),
        .i_led_busy ( w_led_busy ),
        .o_led_r    ( led[0]     ),
        .o_led_g    ( led[1]     ),
        .o_led_b    ( led[2]     )
    );

endmodule
