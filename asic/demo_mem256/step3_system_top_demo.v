`timescale 1ns / 1ps

// =======================================================
// step3 full-system top wrappers, 256-word BRAM variant (P&R demo).
//   Identical to asic/oasys/step3_system_top_mode{0,1,4}.v except the
//   underlying gemm_system_top is instantiated with MEM_DEPTH=256/ADDR_W=8.
//   No logic lives here, so there is nothing to drift out of sync with
//   rtl_v2/gemm_system_top.v (which these thin wrappers reuse directly).
// =======================================================

module step3_system_top_mode0 (
    input  wire        clk,
    input  wire        reset,
    input  wire [8:0]  in_port,
    output wire [3:0]  out_port,
    output wire [11:0] pc_debug,
    output wire [31:0] acc_debug,
    output wire        gemm_busy_debug,
    output wire [2:0]  gemm_state_debug
);
    gemm_system_top #(
        .MAC_MODE(0), .MEM_DEPTH(256), .ADDR_W(8)
    ) u_system (
        .clk(clk), .reset(reset),
        .in_port(in_port), .out_port(out_port),
        .pc_debug(pc_debug), .acc_debug(acc_debug),
        .gemm_busy_debug(gemm_busy_debug),
        .gemm_state_debug(gemm_state_debug)
    );
endmodule

module step3_system_top_mode1 (
    input  wire        clk,
    input  wire        reset,
    input  wire [8:0]  in_port,
    output wire [3:0]  out_port,
    output wire [11:0] pc_debug,
    output wire [31:0] acc_debug,
    output wire        gemm_busy_debug,
    output wire [2:0]  gemm_state_debug
);
    gemm_system_top #(
        .MAC_MODE(1), .MEM_DEPTH(256), .ADDR_W(8)
    ) u_system (
        .clk(clk), .reset(reset),
        .in_port(in_port), .out_port(out_port),
        .pc_debug(pc_debug), .acc_debug(acc_debug),
        .gemm_busy_debug(gemm_busy_debug),
        .gemm_state_debug(gemm_state_debug)
    );
endmodule

module step3_system_top_mode4 (
    input  wire        clk,
    input  wire        reset,
    input  wire [8:0]  in_port,
    output wire [3:0]  out_port,
    output wire [11:0] pc_debug,
    output wire [31:0] acc_debug,
    output wire        gemm_busy_debug,
    output wire [2:0]  gemm_state_debug
);
    gemm_system_top #(
        .MAC_MODE(4), .MEM_DEPTH(256), .ADDR_W(8)
    ) u_system (
        .clk(clk), .reset(reset),
        .in_port(in_port), .out_port(out_port),
        .pc_debug(pc_debug), .acc_debug(acc_debug),
        .gemm_busy_debug(gemm_busy_debug),
        .gemm_state_debug(gemm_state_debug)
    );
endmodule
