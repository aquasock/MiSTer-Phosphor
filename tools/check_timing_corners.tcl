# Run from an isolated, fully fitted Phosphor project directory:
# quartus_sta -t tools/check_timing_corners.tcl
# Read-only analysis: does not alter project constraints or fitted logic.
package require ::quartus::project
package require ::quartus::sta

project_open Phosphor
create_timing_netlist
read_sdc
update_timing_netlist

set out timing_corners
file mkdir $out
report_clocks -file "$out/clocks.rpt"
check_timing -file "$out/check_timing.rpt"
report_ucp -file "$out/unconstrained_paths.rpt"

set corners [get_available_operating_conditions -all]
if {[get_collection_size $corners] < 1} {error "No operating conditions found"}
set index [open "$out/corners.tsv" w]
puts $index "directory\tmodel\tvoltage_mv\ttemperature_c"
set count 0
foreach_in_collection corner $corners {
    set model [get_operating_conditions_info $corner -model]
    set voltage [get_operating_conditions_info $corner -voltage]
    set temperature [get_operating_conditions_info $corner -temperature]
    set name "corner$count"
    puts $index "$name\t$model\t$voltage\t$temperature"
    flush $index
    file mkdir "$out/$name"
    set_operating_conditions $corner
    update_timing_netlist
    foreach kind {setup hold recovery removal mpw} {
        create_timing_summary -$kind -file "$out/$name/${kind}_summary.rpt"
        if {$kind eq "mpw"} {
            report_min_pulse_width -nworst 20 -detail full_path \
                -file "$out/$name/${kind}_paths.rpt"
        } else {
            report_timing -$kind -npaths 20 -nworst 5 -detail full_path \
                -show_routing -file "$out/$name/${kind}_paths.rpt"
        }
    }
    puts "RASTER_CORNER_REPORTED $name $model ${voltage}mV ${temperature}C"
    incr count
}
close $index
delete_timing_netlist
project_close
puts "RASTER_TIMING_REPORTS_COMPLETE $count"
# Successful Tcl execution means reports were produced, not timing closure.
# Inspect all summaries, unconstrained paths and warnings before sign-off.
