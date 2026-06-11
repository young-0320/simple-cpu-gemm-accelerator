`timescale 1ns / 1ps

module step1_gemm_accelerator_top_mode4 (
    input  wire        clk,
    input  wire        reset,
    input  wire        mmio_sel,
    input  wire        mmio_we,
    input  wire [2:0]  mmio_off,
    input  wire [31:0] mmio_wdata,
    output wire [31:0] mmio_rdata,
    output wire [11:0] mem_addr_a,
    input  wire [31:0] mem_rdata_a,
    output wire [31:0] mem_wdata,
    output wire        mem_we,
    output wire [11:0] mem_addr_b,
    input  wire [31:0] mem_rdata_b,
    output wire        busy,
    output wire [2:0]  state_debug
);
    gemm_accelerator_top #(
        .MAC_MODE(4)
    ) u_gemm (
        .clk(clk),
        .reset(reset),
        .mmio_sel(mmio_sel),
        .mmio_we(mmio_we),
        .mmio_off(mmio_off),
        .mmio_wdata(mmio_wdata),
        .mmio_rdata(mmio_rdata),
        .mem_addr_a(mem_addr_a),
        .mem_rdata_a(mem_rdata_a),
        .mem_wdata(mem_wdata),
        .mem_we(mem_we),
        .mem_addr_b(mem_addr_b),
        .mem_rdata_b(mem_rdata_b),
        .busy(busy),
        .state_debug(state_debug)
    );
endmodule
