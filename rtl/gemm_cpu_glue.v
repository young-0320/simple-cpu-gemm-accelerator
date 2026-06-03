`timescale 1ns / 1ps
`include "gemm_define.vh"

// =======================================================
// gemm_cpu_glue
//   Integration layer between the (unmodified) CPU's single memory
//   port and three targets: real BRAM, GEMM MMIO registers, GEMM LSU.
//
//   Arbitration strategy: STALL-FREE via CPU freeze.
//     While GEMM is busy, the CPU is frozen (cpu_run=0 -> clk_enable=0).
//     The LSU then owns the BRAM port exclusively and never stalls.
//     When GEMM finishes (busy=0), the CPU resumes and reads done.
//     Because the CPU is halted, instruction fetch and data accesses
//     never contend with the LSU — no stall logic anywhere.
//
//   MMIO:
//     STORE to 0xFF0..0xFF7 -> write GEMM register (BRAM not written)
//     LOAD  from 0xFF7      -> cpu_rdata = GEMM status (not BRAM)
//
//   The CPU never knows whether it read BRAM or GEMM status.
// =======================================================
module gemm_cpu_glue (
    input  wire        clk,

    // ---- CPU memory port (from unmodified top_cpu) ----
    input  wire [11:0] cpu_addr,
    input  wire [31:0] cpu_wdata,
    input  wire        cpu_we,
    output wire [31:0] cpu_rdata,

    // ---- CPU run/freeze control ----
    output wire        cpu_run,        // drives top_cpu.clk_enable

    // ---- GEMM status/handshake ----
    input  wire        gemm_busy,
    input  wire [31:0] mmio_rdata,
    output wire        mmio_sel,
    output wire        mmio_we,
    output wire [2:0]  mmio_off,
    output wire [31:0] mmio_wdata,

    // ---- GEMM LSU memory port (owns BRAM while busy) ----
    input  wire [11:0] lsu_addr,
    input  wire [31:0] lsu_wdata,
    input  wire        lsu_we,

    // ---- real BRAM port ----
    output wire [11:0] bram_addr,
    output wire [31:0] bram_wdata,
    output wire        bram_we,
    input  wire [31:0] bram_rdata
);

    // -------------------------------------------------------
    // Address decode: is the CPU addressing the MMIO block?
    // -------------------------------------------------------
    wire cpu_is_mmio = (cpu_addr >= `GEMM_MMIO_BASE) &&
                       (cpu_addr <= `GEMM_MMIO_LAST);

    // -------------------------------------------------------
    // CPU freeze: halt the CPU while the accelerator is busy.
    //   This is the stall-free arbitration scheme: the CPU is paused,
    //   so it issues no BRAM cycles; the LSU has the port to itself.
    // -------------------------------------------------------
    assign cpu_run = ~gemm_busy;

    // -------------------------------------------------------
    // MMIO routing
    // -------------------------------------------------------
    assign mmio_sel   = cpu_is_mmio;
    assign mmio_we    = cpu_is_mmio & cpu_we;
    assign mmio_off   = cpu_addr[2:0];
    assign mmio_wdata = cpu_wdata;

    // -------------------------------------------------------
    // BRAM port ownership
    //   busy : LSU owns the port (CPU is frozen, issues nothing)
    //   idle : CPU owns it; MMIO accesses must NOT hit BRAM
    // -------------------------------------------------------
    assign bram_addr  = gemm_busy ? lsu_addr  : cpu_addr;
    assign bram_wdata = gemm_busy ? lsu_wdata : cpu_wdata;
    assign bram_we    = gemm_busy ? lsu_we
                                  : (cpu_we & ~cpu_is_mmio);

    // -------------------------------------------------------
    // Read data back to CPU
    //   The CPU samples LOAD data one cycle after presenting the
    //   address (BRAM is synchronous-read). MMIO is combinational, so
    //   to line up with the CPU's sampling edge we register the MMIO
    //   select and status by one cycle, matching BRAM latency exactly.
    // -------------------------------------------------------
    reg        mmio_sel_d;
    reg [31:0] mmio_rdata_d;
    always @(posedge clk) begin
        mmio_sel_d   <= cpu_is_mmio;
        mmio_rdata_d <= mmio_rdata;
    end

    assign cpu_rdata = mmio_sel_d ? mmio_rdata_d : bram_rdata;

endmodule
