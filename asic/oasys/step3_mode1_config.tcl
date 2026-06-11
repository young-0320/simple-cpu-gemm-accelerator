namespace eval config {
    global input
    set REPO_ROOT {/mnt/NewHDD/home/ddl2026/ddl2026_2023104135/ddl2026_folder/simple-cpu-gemm-accelerator}

    # =========================================================
    # step3 mode1
    set STEP       {step3}
    set TOP_MODULE {step3_system_top_mode1}
    # =========================================================

    set FILELIST "$REPO_ROOT/asic/oasys/$STEP.f"
    set fp [open $FILELIST r]
    set input(verilog_files) {}

    foreach line [split [string trim [read $fp]] "\n"] {
        lappend input(verilog_files) "$REPO_ROOT/$line"
    }

    close $fp

    set input(system_verilog)                 {true}
    set input(verilog_dirs)                   [list "$REPO_ROOT/rtl_v2/gemm_accelerator" "$REPO_ROOT/rtl_v2/simple_cpu"]
    set input(verilog_defs)                   {}
    set input(top_module)                     $TOP_MODULE

    set input(lib_files)                      {{default {/mnt/NewHDD/home/vlsiadmin/TannerEDA/TannerTools_v2021.2/Process/Generic_250nm/Generic_250nm_LogicGates/Liberty/TANNER_TT_2P50V_25C.lib}}}
    set input(target_library)                 {default}
    set input(lef_files)                      {/mnt/NewHDD/home/vlsiadmin/TannerEDA/TannerTools_v2021.2/Process/Generic_250nm/Generic_250nm_LogicGates/Generic250nm_StdCells.lef}
    set input(tech_file)                      {/mnt/NewHDD/home/vlsiadmin/TannerEDA/TannerTools_v2021.2/Process/Generic_250nm/Generic_250nm_LogicGates/Generic250nm_tech.lef}

    set input(sdc_files)                      [list "$REPO_ROOT/asic/oasys/clk.sdc"]
    set input(def_files)                      {}
    set input(power_files)                    {}
    set input(vcd_file)                       {}
    set input(vcd_scope)                      {}
    set input(sa_probability)                 {}
    set input(sa_togg_perc)                   {}
    set input(sa_togg_rate)                   {}

    set input(clock_gating_minimum_bitwidth)  {4}
    set input(clock_gating_sequential_cell)   {none}
    set input(clock_gating_control_point)     {}
    set input(clock_gating_control_port)      {}
    set input(clock_gating_observation_point) {false}

    set input(comb_vt_target_library)         {default}
    set input(high_vt_target_library)         {default}
    set input(flow_synthesize)                {true}
    set input(synthesize_map_to_scan)         {false}
    set input(synthesize_gate_clock)          {false}
    set input(flow_optimize)                  {true}
    set input(optimize_leakage)               {false}
    set input(optimize_area)                  {false}
    set input(flow_refine)                    {false}
    set input(pre_synthesize)                 {}
    set input(pre_optimize)                   {}
}