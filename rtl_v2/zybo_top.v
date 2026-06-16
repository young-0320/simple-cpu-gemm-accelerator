`timescale 1ns / 1ps
`include "define.vh"
`include "gemm_define.vh"

// =======================================================
// zybo_top
//   FPGA-only top wrapper around gemm_system_top for Zybo Z7-20 bring-up.
//   in_port is the simple_cpu's original 9-bit human-input port; gemm_call.asm
//   never reads it, so it is tied to 0 here instead of wasting board pins.
//   Debug buses stay internal: FPGA step3 only needs Vivado timing/power
//   reports, not on-board result inspection (already covered by Verilator
//   transaction tests).
// =======================================================
module zybo_top #(
    parameter MAC_MODE = 4
) (
    input  wire        clk,
    input  wire        reset,
    output wire [3:0]  led
);

    gemm_system_top #(
        .MAC_MODE(MAC_MODE)
    ) u_system (
        .clk             (clk),
        .reset           (reset),
        .in_port         (9'd0),
        .out_port        (led),
        .pc_debug        (),
        .acc_debug       (),
        .gemm_busy_debug (),
        .gemm_state_debug()
    );

endmodule
