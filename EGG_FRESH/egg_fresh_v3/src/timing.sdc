# ==============================================================
# Timing Constraints — AS7263 NIR Sensor Logger
# Board  : Tang Nano 20K (GW2AR-18 QN88)
# Tool   : Gowin EDA (SDC format)
# ==============================================================

# ---- Primary clock: sys_clk = 27MHz ----
# Period = 1/27MHz = 37.037ns
create_clock -name sys_clk -period 37.037 -waveform {0 18.518} [get_ports {sys_clk}]

# ---- I/O timing (relative to sys_clk) ----
# UART TX output — relaxed, async to PC
set_output_delay -clock sys_clk -max 5 [get_ports {uart_tx}]
set_output_delay -clock sys_clk -min 0 [get_ports {uart_tx}]

# I2C SCL/SDA — open-drain, max delay thoải mái ở 100kHz
set_output_delay -clock sys_clk -max 5 [get_ports {scl}]
set_output_delay -clock sys_clk -max 5 [get_ports {sda}]
set_input_delay  -clock sys_clk -max 5 [get_ports {sda}]

# Reset và LEDs — không cần timing chặt
set_false_path -from [get_ports {rst}]
set_false_path -to   [get_ports {led[*]}]

# PR1014 là P&R warning, không thể tắt bằng SDC
# Ở 27MHz warning này không ảnh hưởng chức năng — có thể bỏ qua
