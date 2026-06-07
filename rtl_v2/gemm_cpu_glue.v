`timescale 1ns / 1ps
`include "gemm_define.vh"

// =======================================================
// gemm_cpu_glue  (dual-port BRAM)
//   Integration layer between the (unmodified) single-port CPU and a
//   dual-port BRAM shared with the GEMM accelerator.
//
//   Arbitration: STALL-FREE via CPU freeze.
//     While GEMM is busy, the CPU is frozen (cpu_run=0). The LSU then
//     owns BOTH BRAM ports exclusively (A: read A/write C, B: read B).
//     When idle, the CPU owns Port A (instruction fetch + data); the
//     CPU has only one memory port, so Port B is unused while idle.
//
//   MMIO:
//     STORE to 0xFF0..0xFF7 -> write GEMM register (BRAM not written)
//     LOAD  from 0xFF7      -> cpu_rdata = GEMM status (not BRAM)
// =======================================================
module gemm_cpu_glue (
    input  wire        clk,

    // ---- CPU memory port (single port, unmodified top_cpu) ----
    input  wire [11:0] cpu_addr,
    input  wire [31:0] cpu_wdata,
    input  wire        cpu_we,
    output wire [31:0] cpu_rdata,

    // ---- CPU run/freeze control ----
    output wire        cpu_run,

    // ---- GEMM status/handshake ----
    input  wire        gemm_busy,
    input  wire [31:0] mmio_rdata,
    output wire        mmio_sel,
    output wire        mmio_we,
    output wire [2:0]  mmio_off,
    output wire [31:0] mmio_wdata,

    // ---- GEMM LSU dual-port memory (owns BRAM while busy) ----
    input  wire [11:0] lsu_addr_a,
    input  wire [31:0] lsu_wdata,
    input  wire        lsu_we,
    input  wire [11:0] lsu_addr_b,

    // ---- real dual-port BRAM ----
    output wire [11:0] bram_addr_a,
    output wire [31:0] bram_wdata_a,
    output wire        bram_we_a,
    input  wire [31:0] bram_rdata_a,
    output wire [11:0] bram_addr_b
    // (Port B read data goes BRAM->GEMM directly in system_top; glue
    //  only routes the Port B address, so no bram_rdata_b input here.)
);

    // -------------------------------------------------------
    // Address decode: is the CPU addressing the MMIO block?
    // -------------------------------------------------------
    wire cpu_is_mmio = (cpu_addr >= `GEMM_MMIO_BASE) &&
                       (cpu_addr <= `GEMM_MMIO_LAST);

    // -------------------------------------------------------
    // CPU freeze while accelerator busy (stall-free arbitration)
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
    // BRAM Port A ownership
    //   busy : LSU port A (read A / write C)
    //   idle : CPU (fetch + data); MMIO accesses must NOT hit BRAM
    // -------------------------------------------------------
    assign bram_addr_a  = gemm_busy ? lsu_addr_a : cpu_addr;
    assign bram_wdata_a = gemm_busy ? lsu_wdata  : cpu_wdata;
    assign bram_we_a    = gemm_busy ? lsu_we
                                    : (cpu_we & ~cpu_is_mmio);

    // -------------------------------------------------------
    // BRAM Port B
    //   busy : LSU port B (read B). idle : unused (CPU has no 2nd port)
    // -------------------------------------------------------
    assign bram_addr_b = gemm_busy ? lsu_addr_b : 12'd0;

    // -------------------------------------------------------
    // Read data back to CPU (Port A only; CPU is single-port)
    //   MMIO read aligned to BRAM's 1-cycle sync-read latency.
    // -------------------------------------------------------
    reg        mmio_sel_d;
    reg [31:0] mmio_rdata_d;
    always @(posedge clk) begin
        mmio_sel_d   <= cpu_is_mmio;
        mmio_rdata_d <= mmio_rdata;
    end

    assign cpu_rdata = mmio_sel_d ? mmio_rdata_d : bram_rdata_a;

endmodule
