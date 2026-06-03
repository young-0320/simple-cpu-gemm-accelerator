`timescale 1ns / 1ps
`include "define.vh"
`include "gemm_define.vh"

// =======================================================
// gemm_system_top
//   Unmodified top_cpu + gemm_cpu_glue + gemm_accelerator_top + BRAM.
//   CPU/GEMM integration for sim and synthesis.
//
//   Arbitration: stall-free CPU-freeze. While GEMM is busy the CPU is
//   halted via clk_enable=0; the LSU owns BRAM exclusively. The CPU
//   resumes when busy clears and reads the done status.
//
//   Memory map (4K word space):
//     0x000..       : program code + A/B/C matrix data region
//     0xFF0..0xFF7  : GEMM MMIO registers
//
//   BRAM here is a behavioral model (synchronous read). On the board
//   it is replaced by the Block Memory Generator IP.
// =======================================================
module gemm_system_top #(
    parameter MAC_MODE = 4
) (
    input  wire        clk,
    input  wire        reset,

    input  wire [8:0]  in_port,
    output wire [3:0]  out_port,

    output wire [11:0] pc_debug,
    output wire [31:0] acc_debug,
    output wire        gemm_busy_debug,
    output wire [2:0]  gemm_state_debug
);

    // ---- CPU memory port ----
    wire [11:0] cpu_addr;
    wire [31:0] cpu_wdata;
    wire        cpu_we;
    wire [31:0] cpu_rdata;
    wire        cpu_run;          // from glue: high when CPU may run

    // ---- glue <-> GEMM ----
    wire        mmio_sel, mmio_we;
    wire [2:0]  mmio_off;
    wire [31:0] mmio_wdata, mmio_rdata;
    wire        gemm_busy;

    // ---- GEMM LSU memory port ----
    wire [11:0] lsu_addr;
    wire [31:0] lsu_wdata;
    wire        lsu_we;

    // ---- real BRAM port ----
    wire [11:0] bram_addr;
    wire [31:0] bram_wdata;
    wire        bram_we;
    wire [31:0] bram_rdata;

    assign gemm_busy_debug = gemm_busy;

    // =======================================================
    // CPU (unmodified). clk_enable gated by registered cpu_run.
    //   Registering breaks the combinational path busy->clk_enable->
    //   cpu_we->mmio->busy that the tool flags as a loop. A one-cycle
    //   delay on freeze/resume is harmless: the CPU is only paused
    //   during the long GEMM busy window.
    // =======================================================
    reg cpu_run_r;
    always @(posedge clk) begin
        if (reset) cpu_run_r <= 1'b1;
        else       cpu_run_r <= cpu_run;
    end

    top_cpu u_cpu (
        .clk(clk), .reset(reset),
        .clk_enable(cpu_run_r),
        .bram_rdata(cpu_rdata),
        .bram_addr(cpu_addr),
        .bram_wdata(cpu_wdata),
        .bram_we(cpu_we),
        .in_port(in_port),
        .out_port(out_port),
        .pc_debug(pc_debug),
        .acc_debug(acc_debug),
        .zero_flag_debug(),
        .state_debug()
    );

    // =======================================================
    // Glue (address decode, MMIO routing, CPU-freeze arbitration)
    // =======================================================
    gemm_cpu_glue u_glue (
        .clk(clk),
        .cpu_addr(cpu_addr), .cpu_wdata(cpu_wdata),
        .cpu_we(cpu_we), .cpu_rdata(cpu_rdata),
        .cpu_run(cpu_run),
        .gemm_busy(gemm_busy), .mmio_rdata(mmio_rdata),
        .mmio_sel(mmio_sel), .mmio_we(mmio_we),
        .mmio_off(mmio_off), .mmio_wdata(mmio_wdata),
        .lsu_addr(lsu_addr), .lsu_wdata(lsu_wdata), .lsu_we(lsu_we),
        .bram_addr(bram_addr), .bram_wdata(bram_wdata),
        .bram_we(bram_we), .bram_rdata(bram_rdata)
    );

    // =======================================================
    // GEMM accelerator
    // =======================================================
    gemm_accelerator_top #(
        .MAC_MODE(MAC_MODE)
    ) u_gemm (
        .clk(clk), .reset(reset),
        .mmio_sel(mmio_sel), .mmio_we(mmio_we),
        .mmio_off(mmio_off), .mmio_wdata(mmio_wdata),
        .mmio_rdata(mmio_rdata),
        .mem_addr(lsu_addr), .mem_rdata(bram_rdata),
        .mem_wdata(lsu_wdata), .mem_we(lsu_we),
        .busy(gemm_busy),
        .state_debug(gemm_state_debug)
    );

    // =======================================================
    // BRAM (behavioral model, synchronous read)
    // =======================================================
    reg [31:0] mem [0:4095];
    reg [31:0] bram_rdata_r;
    always @(posedge clk) begin
        if (bram_we) mem[bram_addr] <= bram_wdata;
        bram_rdata_r <= mem[bram_addr];
    end
    assign bram_rdata = bram_rdata_r;

`ifdef GEMM_MEM_INIT
    initial $readmemh(`GEMM_MEM_INIT, mem);
`endif

endmodule
