`timescale 1ns / 1ps

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
        .MAC_MODE(4)
    ) u_system (
        .clk(clk),
        .reset(reset),
        .in_port(in_port),
        .out_port(out_port),
        .pc_debug(pc_debug),
        .acc_debug(acc_debug),
        .gemm_busy_debug(gemm_busy_debug),
        .gemm_state_debug(gemm_state_debug)
    );
endmodule
