# TD 6.2 batch build for V25 knowledge quiz interaction, edge detection, watchdog and audio meters.
cd [file dirname [file normalize [info script]]]
file mkdir v25_build
if {[catch {
    import_device eagle_s20.db -package EG4S20BG256
    open_project V25_QUIZ_INTERACTION.al -single_run
    elaborate -top anlogic_topic1_hdmi_media_top
    read_adc ../user_source/constraints_source/pin.adc
    read_adc ../user_source/constraints_source/my_pin.adc
    read_sdc ../user_source/constraints_source/timing.sdc
    read_sdc -ip rfifo_32_32_512 ../user_source/hdl_source/IP/afifo_32_16_256.tcl
    read_sdc -ip wfifo_32_32_512 ../user_source/hdl_source/IP/afifo_16_32_256.tcl
    optimize_rtl
    report_area -file v25_build/V25_rtl.area
    optimize_gate -packarea v25_build/V25_gate.area
    legalize_phy_inst
    export_db v25_build/V25_gate.db
    place
    route
    report_area -io_info -file v25_build/V25_phy.area
    update_timing -mode final
    report_timing_status -file v25_build/V25_phy.ts
    report_timing_summary -file v25_build/V25_pr.timing
    report_timing_exception -file v25_build/V25_exception.timing
    flow_status -file v25_build/V25_flow.status
    export_db v25_build/V25_pr.db
    bitgen -bit v25_build/V25_QUIZ_INTERACTION.bit
} result]} {
    puts "V25_BUILD_FAILED: $result"
    exit 1
}
puts "V25_BUILD_PASS"
exit
