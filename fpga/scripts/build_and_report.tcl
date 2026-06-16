#==========================================================================
# build_and_report.tcl
#   One sweep point: (re)build the zybo_top Vivado project for a given
#   MAC_MODE, swap in a clock-period-swept copy of Zybo-Z7.xdc, run
#   synthesis + implementation, and dump timing/utilization/power reports.
#
# Usage:
#   vivado -mode batch -nojournal -nolog -source fpga/scripts/build_and_report.tcl \
#       -tclargs <mac_mode> <period_ns> [<label>]
#
#   mac_mode  : 1 or 4 (gemm_accelerator_top MAC_MODE parameter)
#   period_ns : clk period in ns, overrides Zybo-Z7.xdc create_clock -period
#   label     : optional file-name-safe tag for reports (default p<period_ns>ns)
#
# Must be run with cwd at the repo root.
#==========================================================================

set MAC_MODE  [lindex $argv 0]
set PERIOD_NS [lindex $argv 1]
if {[llength $argv] >= 3} {
    set RUN_LABEL [lindex $argv 2]
} else {
    set RUN_LABEL "p${PERIOD_NS}ns"
}

set REPO_ROOT  [file normalize [pwd]]
set PART_NAME  "xc7z020clg400-1"
set PROJ_NAME  "gemm_fpga_mode${MAC_MODE}"
set PROJ_DIR   "$REPO_ROOT/fpga/vivado/$PROJ_NAME"
set REPORT_DIR "$REPO_ROOT/fpga/reports/mode${MAC_MODE}"
set MEM_INIT   "$REPO_ROOT/fpga/vivado/gemm_call_full.hex"
set BASE_XDC   "$REPO_ROOT/fpga/Zybo-Z7.xdc"
set SWEEP_XDC  "$REPO_ROOT/fpga/vivado/sweep_mode${MAC_MODE}_${RUN_LABEL}.xdc"

file mkdir $REPORT_DIR

if {![file exists $MEM_INIT]} {
    error "GEMM_MEM_INIT hex not found at $MEM_INIT -- run sw/tools/build_mem_image.py first (see fpga/README.md)"
}

# --- generate the swept XDC: only the create_clock period/waveform changes ---
set half [expr {$PERIOD_NS / 2.0}]
set fin [open $BASE_XDC r]
set xdc_text [read $fin]
close $fin
set xdc_text [regsub -- {-period [0-9.]+} $xdc_text "-period $PERIOD_NS"]
set xdc_text [regsub -- {-waveform \{[^\}]*\}} $xdc_text "-waveform {0 $half}"]
set fout [open $SWEEP_XDC w]
puts $fout $xdc_text
close $fout

# --- create project on first use, otherwise reopen it ---
if {![file exists "$PROJ_DIR/$PROJ_NAME.xpr"]} {
    create_project $PROJ_NAME $PROJ_DIR -part $PART_NAME -force

    set src_files {
        rtl_v2/gemm_accelerator/gemm_mmio_reg.v
        rtl_v2/gemm_accelerator/gemm_controller_fsm.v
        rtl_v2/gemm_accelerator/gemm_local_buffer.v
        rtl_v2/gemm_accelerator/gemm_lsu.v
        rtl_v2/gemm_accelerator/gemm_mac_datapath.v
        rtl_v2/gemm_accelerator/gemm_mac_datapath4.v
        rtl_v2/gemm_accelerator/gemm_mac_datapath_at.v
        rtl_v2/gemm_accelerator/gemm_accelerator_top.v
        rtl_v2/simple_cpu/pc.v
        rtl_v2/simple_cpu/inst_reg.v
        rtl_v2/simple_cpu/decoder.v
        rtl_v2/simple_cpu/alu.v
        rtl_v2/simple_cpu/accumulator.v
        rtl_v2/simple_cpu/cpu_fsm.v
        rtl_v2/simple_cpu/top_cpu.v
        rtl_v2/gemm_cpu_glue.v
        rtl_v2/gemm_system_top.v
        rtl_v2/zybo_top.v
    }
    set abs_src {}
    foreach f $src_files { lappend abs_src "$REPO_ROOT/$f" }
    add_files -norecurse $abs_src

    set_property top zybo_top [current_fileset]
    set_property include_dirs [list "$REPO_ROOT/rtl_v2/gemm_accelerator" "$REPO_ROOT/rtl_v2/simple_cpu"] [current_fileset]
} else {
    open_project "$PROJ_DIR/$PROJ_NAME.xpr"
}

set_property verilog_define [list "GEMM_MEM_INIT=\"$MEM_INIT\""] [current_fileset]
set_property generic [list "MAC_MODE=$MAC_MODE"] [current_fileset]

# --- swap constraint file for this sweep point ---
set existing_xdc [get_files -quiet -of_objects [get_filesets constrs_1]]
if {[llength $existing_xdc] > 0} {
    remove_files -fileset constrs_1 $existing_xdc
}
add_files -fileset constrs_1 -norecurse $SWEEP_XDC

# --- synth + impl (managed runs, reset so generic/constraint changes apply) ---
reset_run synth_1
launch_runs synth_1 -jobs 4
wait_on_run synth_1
if {[get_property PROGRESS [get_runs synth_1]] != "100%"} {
    error "synth_1 did not complete (mode=$MAC_MODE period=$PERIOD_NS): [get_property STATUS [get_runs synth_1]]"
}

reset_run impl_1
launch_runs impl_1 -jobs 4 -to_step route_design
wait_on_run impl_1
if {[get_property PROGRESS [get_runs impl_1]] != "100%"} {
    error "impl_1 did not complete (mode=$MAC_MODE period=$PERIOD_NS): [get_property STATUS [get_runs impl_1]]"
}

open_run impl_1

report_timing_summary -delay_type max -max_paths 5 -file "$REPORT_DIR/${RUN_LABEL}_timing_summary.rpt"
report_utilization -file "$REPORT_DIR/${RUN_LABEL}_utilization.rpt"
report_power -file "$REPORT_DIR/${RUN_LABEL}_power.rpt"

set wns [get_property STATS.WNS [get_runs impl_1]]
set tns [get_property STATS.TNS [get_runs impl_1]]
set whs [get_property STATS.WHS [get_runs impl_1]]

puts "SWEEP_RESULT mode=$MAC_MODE period_ns=$PERIOD_NS label=$RUN_LABEL wns=$wns tns=$tns whs=$whs"
