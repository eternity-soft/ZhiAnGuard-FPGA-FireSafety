# TD 6.2 batch build for V27 all-in-one fire safety promotion
cd [file dirname [file normalize [info script]]]
file mkdir v27_build
if {[catch {
    import_device eagle_s20.db -package EG4S20BG256
    open_project V27_FIRE_ALL_IN_ONE.al -single_run
    elaborate -top anlogic_topic1_hdmi_media_top
    read_adc ../user_source/constraints_source/pin.adc
    read_adc ../user_source/constraints_source/my_pin.adc
    read_sdc ../user_source/constraints_source/timing.sdc
    read_sdc -ip rfifo_32_32_512 ../user_source/hdl_source/IP/afifo_32_16_256.tcl
    read_sdc -ip wfifo_32_32_512 ../user_source/hdl_source/IP/afifo_16_32_256.tcl
    optimize_rtl
    report_area -file v27_build/V27_rtl.area
    optimize_gate -packarea v27_build/V27_gate.area
    legalize_phy_inst
    export_db v27_build/V27_gate.db
    place
    if {[catch {route} r1]} {
        puts "Initial route had conflict: $r1; resolving with route -incremental..."
        route -incremental
    }
    report_area -io_info -file v27_build/V27_phy.area
    update_timing -mode final
    report_timing_status -file v27_build/V27_phy.ts
    report_timing_summary -file v27_build/V27_pr.timing
    report_timing_exception -file v27_build/V27_exception.timing
    flow_status -file v27_build/V27_flow.status
    export_db v27_build/V27_pr.db
    bitgen -bit v27_build/V27_FIRE_ALL_IN_ONE.bit
} result]} {
    puts "V27_BUILD_FAILED: $result"
    exit 1
}
puts "V27_BUILD_PASS"
exit
