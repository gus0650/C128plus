derive_pll_clocks
derive_clock_uncertainty

# The reconfigurable video PLL has no stable phase relationship to the
# system/framework clocks. Keep the main core PLL outputs related, but cut
# transfers to and from the independent video domain.
set core_video_clocks [get_clocks {emu|video_switch|pll_video|pll_video_inst|altera_pll_i|*|divclk}]

if {[get_collection_size $core_video_clocks] != 0} {
   set_clock_groups -asynchronous \
      -group $core_video_clocks \
      -group [get_clocks {emu|pll|pll_inst|altera_pll_i|*|divclk}] \
      -group [get_clocks {pll_hdmi|pll_hdmi_inst|altera_pll_i|*[0].*|divclk}] \
      -group [get_clocks {pll_audio|pll_audio_inst|altera_pll_i|*[0].*|divclk}] \
      -group [get_clocks {spi_sck}] \
      -group [get_clocks {hdmi_sck}] \
      -group [get_clocks {*|h2f_user0_clk}] \
      -group [get_clocks {FPGA_CLK1_50}] \
      -group [get_clocks {FPGA_CLK2_50}] \
      -group [get_clocks {FPGA_CLK3_50}]
} elseif {[info exists ::quartus(nameofexecutable)] &&
          $::quartus(nameofexecutable) eq "quartus_sta"} {
   error "The reconfigurable core video clock was not found"
}

set_false_path -from {emu|fpga64|reset}

set_false_path -from {emu|fpga64|Keyboard|*}
set_false_path -to   {emu|fpga64|Keyboard|*}
