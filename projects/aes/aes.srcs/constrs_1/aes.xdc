# =============================================================
# aes.xdc - constraint file for the AES-128 project
# Target device: Artix-7 xc7a100tfgg484-2
# Target board: TOE_X7CA100T evaluation board
# Reference schematic: TOE_X7CA100T.pdf
# =============================================================

# ===== Global configuration =====
# CFGBVS: configuration bank voltage selection, VCCO means the I/O bank supply voltage
# CONFIG_VOLTAGE: configuration interface voltage 3.3V (matches the board)
############## NET - IOSTANDARD ##################
set_property CFGBVS VCCO [current_design]
set_property CONFIG_VOLTAGE 3.3 [current_design]

# ===== SPI Flash configuration =====
# On-board flash: mt25ql128 (16MB), supports Quad SPI
# SPI_BUSWIDTH 4: use a 4-bit SPI data bus (SPIx4) to speed up configuration loading
# CONFIG_MODE SPIx4: the FPGA loads its configuration from SPI Flash in quad mode at power-up
# CONFIGRATE 50: SPI configuration clock frequency 50MHz
#############SPI Configurate Setting##################
set_property BITSTREAM.CONFIG.SPI_BUSWIDTH 4 [current_design]
set_property CONFIG_MODE SPIx4 [current_design]
set_property BITSTREAM.CONFIG.CONFIGRATE 50 [current_design]

# ===== Clock =====
# On-board 50MHz crystal X2 (YXC OT322550MJBA4SL) -> through R3 (0R) -> FPGA pin R4
# R4 = IO_L12N_T1_MRCC_34, in Bank34, an MRCC (multi-region clock) pin,
# so it can drive the global clock network and is suitable as the main clock input
set_property PACKAGE_PIN R4 [get_ports clk_50m_ext]
set_property IOSTANDARD LVCMOS33 [get_ports clk_50m_ext]
create_clock -period 20.000 -name clk_50m_ext [get_ports clk_50m_ext]
# The 8MHz PLL output clock is derived automatically by Vivado, so no manual create_generated_clock is needed

# ===== Reset =====
# KEY8 button -> Y22, pulled up to 3.3V, reads low when pressed (active low reset)
set_property PACKAGE_PIN Y22 [get_ports rst]
set_property IOSTANDARD LVCMOS33 [get_ports rst]

# ===== UART serial port (FT232HL USB-to-serial chip) =====
# The board provides USB-to-UART through the FT232HL (U4), connected to USB port (3)
# Note: the FT232 TX is connected to the FPGA RX (cross-connected)
#
# FTDI_BD0_TX (FT232 transmit) -> FPGA receive (rx): U4 ADBUS0 -> E18
set_property PACKAGE_PIN E18 [get_ports rx]
set_property IOSTANDARD LVCMOS33 [get_ports rx]

# FTDI_BD1_RX (FT232 receive) <- FPGA transmit (tx): F14 -> U4 ADBUS1
set_property PACKAGE_PIN F14 [get_ports tx]
set_property IOSTANDARD LVCMOS33 [get_ports tx]

# ===== Status LEDs (Bank16, LVCMOS33) =====
# LED1 (busy): solid on after reset completes, indicating the system is running
set_property PACKAGE_PIN A13 [get_ports busy]
set_property IOSTANDARD LVCMOS33 [get_ports busy]

# LED2 (key_exp_trigger): blinks while UART data is received
set_property PACKAGE_PIN A14 [get_ports key_exp_trigger]
set_property IOSTANDARD LVCMOS33 [get_ports key_exp_trigger]

# LED4 (enc_start_trigger): on during AES computation (key expansion included)
set_property PACKAGE_PIN A16 [get_ports enc_start_trigger]
set_property IOSTANDARD LVCMOS33 [get_ports enc_start_trigger]

# LED5 (wr_en): blinks while UART data is transmitted
set_property PACKAGE_PIN A18 [get_ports wr_en]
set_property IOSTANDARD LVCMOS33 [get_ports wr_en]

# ===== Encryption trigger output (for power analysis) =====
# enc_only_trigger -> AB20: driven high only during AES encryption (excluding key expansion)
# Can be connected to an oscilloscope or power acquisition device as the trigger for power traces
set_property PACKAGE_PIN AB20 [get_ports enc_only_trigger]
set_property IOSTANDARD LVCMOS33 [get_ports enc_only_trigger]
