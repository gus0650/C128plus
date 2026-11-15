# Print the slowest setup and hold paths of the compiled C128plus project.
# Run with: quartus_sta -t .github/timing_report.tcl
project_open C128plus -revision C128plus
create_timing_netlist
read_sdc
update_timing_netlist
foreach corner [get_available_operating_conditions] {
    set_operating_conditions $corner
    update_timing_netlist
    puts "==== $corner: setup ===="
    report_timing -setup -npaths 10 -detail summary -stdout
    puts "==== $corner: hold ===="
    report_timing -hold -npaths 5 -detail summary -stdout
}
delete_timing_netlist
project_close
