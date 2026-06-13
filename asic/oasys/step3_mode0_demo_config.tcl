namespace eval config {
    global input
    set input(system_verilog)                 {true}
    set input(verilog_files)                  {/mnt/NewHDD/home/ddl2026/ddl2026_2021104248/simple-cpu-gemm-accelerator/asic/demo_mem256/gemm_system_top.v /mnt/NewHDD/home/ddl2026/ddl2026_2021104248/simple-cpu-gemm-accelerator/rtl_v2/gemm_accelerator/gemm_mmio_reg.v /mnt/NewHDD/home/ddl2026/ddl2026_2021104248/simple-cpu-gemm-accelerator/rtl_v2/gemm_accelerator/gemm_mac_datapath.v /mnt/NewHDD/home/ddl2026/ddl2026_2021104248/simple-cpu-gemm-accelerator/rtl_v2/gemm_accelerator/gemm_mac_datapath_at.v /mnt/NewHDD/home/ddl2026/ddl2026_2021104248/simple-cpu-gemm-accelerator/rtl_v2/gemm_accelerator/gemm_mac_datapath4.v /mnt/NewHDD/home/ddl2026/ddl2026_2021104248/simple-cpu-gemm-accelerator/rtl_v2/gemm_accelerator/gemm_lsu.v /mnt/NewHDD/home/ddl2026/ddl2026_2021104248/simple-cpu-gemm-accelerator/rtl_v2/gemm_accelerator/gemm_local_buffer.v /mnt/NewHDD/home/ddl2026/ddl2026_2021104248/simple-cpu-gemm-accelerator/rtl_v2/gemm_accelerator/gemm_controller_fsm.v /mnt/NewHDD/home/ddl2026/ddl2026_2021104248/simple-cpu-gemm-accelerator/rtl_v2/gemm_accelerator/gemm_accelerator_top.v /mnt/NewHDD/home/ddl2026/ddl2026_2021104248/simple-cpu-gemm-accelerator/rtl_v2/simple_cpu/top_cpu.v /mnt/NewHDD/home/ddl2026/ddl2026_2021104248/simple-cpu-gemm-accelerator/rtl_v2/simple_cpu/pc.v /mnt/NewHDD/home/ddl2026/ddl2026_2021104248/simple-cpu-gemm-accelerator/rtl_v2/simple_cpu/inst_reg.v /mnt/NewHDD/home/ddl2026/ddl2026_2021104248/simple-cpu-gemm-accelerator/rtl_v2/simple_cpu/decoder.v /mnt/NewHDD/home/ddl2026/ddl2026_2021104248/simple-cpu-gemm-accelerator/rtl_v2/simple_cpu/cpu_fsm.v /mnt/NewHDD/home/ddl2026/ddl2026_2021104248/simple-cpu-gemm-accelerator/rtl_v2/simple_cpu/alu.v /mnt/NewHDD/home/ddl2026/ddl2026_2021104248/simple-cpu-gemm-accelerator/rtl_v2/simple_cpu/accumulator.v /mnt/NewHDD/home/ddl2026/ddl2026_2021104248/simple-cpu-gemm-accelerator/rtl_v2/gemm_cpu_glue.v /mnt/NewHDD/home/ddl2026/ddl2026_2021104248/simple-cpu-gemm-accelerator/asic/oasys/step3_system_top_mode4.v /mnt/NewHDD/home/ddl2026/ddl2026_2021104248/simple-cpu-gemm-accelerator/asic/oasys/step3_system_top_mode1.v /mnt/NewHDD/home/ddl2026/ddl2026_2021104248/simple-cpu-gemm-accelerator/asic/oasys/step3_system_top_mode0.v}
    set input(verilog_dirs)                   {/mnt/NewHDD/home/ddl2026/ddl2026_2021104248/simple-cpu-gemm-accelerator/rtl_v2/gemm_accelerator /mnt/NewHDD/home/ddl2026/ddl2026_2021104248/simple-cpu-gemm-accelerator/rtl_v2/simple_cpu}
    set input(verilog_defs)                   {}
    set input(top_module)                     {step3_system_top_mode0}
    set input(lib_files)                      {{default {/mnt/NewHDD/home/vlsiadmin/TannerEDA/TannerTools_v2021.2/Process/Generic_250nm/Generic_250nm_LogicGates/Liberty/TANNER_TT_2P50V_25C.lib}}}
    set input(target_library)                 {default}
    set input(lef_files)                      {/mnt/NewHDD/home/vlsiadmin/TannerEDA/TannerTools_v2021.2/Process/Generic_250nm/Generic_250nm_LogicGates/Generic250nm_StdCells.lef}
    set input(tech_file)                      {/mnt/NewHDD/home/vlsiadmin/TannerEDA/TannerTools_v2021.2/Process/Generic_250nm/Generic_250nm_LogicGates/Generic250nm_tech.lef}
    set input(sdc_files)                      {/mnt/NewHDD/home/ddl2026/ddl2026_2021104248/simple-cpu-gemm-accelerator/asic/oasys/clk.sdc}
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
