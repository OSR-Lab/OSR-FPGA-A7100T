# =============================================================
# sm4.xdc - Artix-7 xc7a100tfgg484-2 Constraints File
# Based on TOE_X7CA100T.pdf schematic
# =============================================================

# --- Clock: board 50MHz oscillator X2 via R3(0R) to FPGA pin R4 (Bank34) ---
# PLL converts 50MHz -> 8MHz internally
set_property PACKAGE_PIN R4 [get_ports clk_50m_ext]
set_property IOSTANDARD LVCMOS33 [get_ports clk_50m_ext]
create_clock -period 20.000 -name clk_50m_ext [get_ports clk_50m_ext]

# --- Reset: KEY8 button, pulled up to 3.3V, active low when pressed ---
set_property PACKAGE_PIN Y22 [get_ports rst]
set_property IOSTANDARD LVCMOS33 [get_ports rst]

# --- UART interface (via FT232HL USB-to-UART chip) ---
# FTDI_BD0_TX: FT232 transmit -> FPGA receive (rx)
set_property PACKAGE_PIN E18 [get_ports rx]
set_property IOSTANDARD LVCMOS33 [get_ports rx]

# FTDI_BD1_RX: FPGA transmit -> FT232 receive (tx)
set_property PACKAGE_PIN F14 [get_ports tx]
set_property IOSTANDARD LVCMOS33 [get_ports tx]

# --- Status outputs (connected to LEDs, BANK16, 3.3V) ---
# busy -> LED1
set_property PACKAGE_PIN A13 [get_ports busy]
set_property IOSTANDARD LVCMOS33 [get_ports busy]

# key_exp_trigger -> LED2
set_property PACKAGE_PIN A14 [get_ports key_exp_trigger]
set_property IOSTANDARD LVCMOS33 [get_ports key_exp_trigger]

# enc_start_trigger -> LED4
set_property PACKAGE_PIN A16 [get_ports enc_start_trigger]
set_property IOSTANDARD LVCMOS33 [get_ports enc_start_trigger]

# wr_en -> LED5
set_property PACKAGE_PIN A18 [get_ports wr_en]
set_property IOSTANDARD LVCMOS33 [get_ports wr_en]

# enc_only_trigger -> AB20 (encryption-only trigger for power trace capture)
set_property PACKAGE_PIN AB20 [get_ports enc_only_trigger]
set_property IOSTANDARD LVCMOS33 [get_ports enc_only_trigger]

############## NET - IOSTANDARD ##################
set_property CFGBVS VCCO [current_design]
set_property CONFIG_VOLTAGE 3.3 [current_design]
#############SPI Configurate Setting##################
set_property BITSTREAM.CONFIG.SPI_BUSWIDTH 4 [current_design]
set_property CONFIG_MODE SPIx4 [current_design]
set_property BITSTREAM.CONFIG.CONFIGRATE 50 [current_design]
