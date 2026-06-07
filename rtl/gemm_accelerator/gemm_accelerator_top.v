`timescale 1ns / 1ps
`include "gemm_define.vh"

// =======================================================
// gemm_accelerator_top
//   5 sub-blocks + buffer-port mux between LSU (LOAD/STORE) and MAC
//   (COMPUTE). Parameterized compute datapath:
//     MAC_MODE = 1 : 1-MAC serial   (baseline)
//     MAC_MODE = 4 : 4-MAC row-parallel (extension)
//   FSM / LSU / MMIO / buffer are shared; only the MAC instance and
//   its buffer wiring differ.
// =======================================================
module gemm_accelerator_top #(
    parameter MAC_MODE = 1
) (
    input  wire        clk,
    input  wire        reset,

    input  wire        mmio_sel,
    input  wire        mmio_we,
    input  wire [2:0]  mmio_off,
    input  wire [31:0] mmio_wdata,
    output wire [31:0] mmio_rdata,

    output wire [11:0] mem_addr,
    input  wire [31:0] mem_rdata,
    output wire [31:0] mem_wdata,
    output wire        mem_we,

    output wire        busy,
    output wire [2:0]  state_debug
);

    // ---- MMIO <-> FSM ----
    wire [11:0] a_base, b_base, c_base;
    wire [2:0]  m_dim, n_dim, k_dim;
    wire        dim_oor;
    wire        start_pulse, clear_pulse;
    wire        set_done, set_error, set_invsize;

    // ---- FSM <-> LSU / MAC ----
    wire        lsu_load_en, lsu_load_done;
    wire        lsu_store_en, lsu_store_done;
    wire        mac_en, mac_done;

    // ---- buffer write (LSU during LOAD) ----
    wire        lsu_a_we, lsu_b_we;
    wire [3:0]  lsu_a_waddr, lsu_b_waddr;
    wire [7:0]  lsu_a_wdata, lsu_b_wdata;

    // ---- buffer read ----
    wire [3:0]  mac_a_raddr;
    wire [7:0]  buf_a_rdata, buf_b_rdata;
    wire [3:0]  mac_b_raddr;             // 1-MAC single B read
    wire [2:0]  mac_b_row_k;
    wire [2:0]  mac_b_row_n;
    wire [7:0]  buf_brow0, buf_brow1, buf_brow2, buf_brow3;

    // ---- C ----
    wire        mac_c_clear, mac_c_we;
    wire [3:0]  mac_c_waddr, mac_c_raddr;
    wire [31:0] mac_c_wdata;
    wire [3:0]  lsu_c_raddr;
    wire [31:0] buf_c_rdata;

    wire [3:0]  buf_a_raddr = mac_a_raddr;
    wire [3:0]  buf_b_raddr = mac_b_raddr;
    wire [3:0]  buf_c_raddr = mac_en ? mac_c_raddr : lsu_c_raddr;

    // =======================================================
    gemm_mmio_reg u_mmio (
        .clk(clk), .reset(reset),
        .mmio_sel(mmio_sel), .mmio_we(mmio_we),
        .mmio_off(mmio_off), .mmio_wdata(mmio_wdata), .mmio_rdata(mmio_rdata),
        .a_base(a_base), .b_base(b_base), .c_base(c_base),
        .m_dim(m_dim), .n_dim(n_dim), .k_dim(k_dim),
        .dim_oor(dim_oor),
        .start_pulse(start_pulse), .clear_pulse(clear_pulse),
        .fsm_busy(busy),
        .fsm_set_done(set_done), .fsm_set_error(set_error),
        .fsm_set_invsize(set_invsize)
    );

    gemm_controller_fsm u_fsm (
        .clk(clk), .reset(reset),
        .start_pulse(start_pulse), .clear_pulse(clear_pulse),
        .m_dim(m_dim), .n_dim(n_dim), .k_dim(k_dim),
        .dim_oor(dim_oor),
        .busy(busy),
        .set_done(set_done), .set_error(set_error), .set_invsize(set_invsize),
        .lsu_load_en(lsu_load_en), .lsu_load_done(lsu_load_done),
        .mac_en(mac_en), .mac_done(mac_done),
        .lsu_store_en(lsu_store_en), .lsu_store_done(lsu_store_done),
        .state_debug(state_debug)
    );

    gemm_local_buffer u_buf (
        .clk(clk),
        .a_we(lsu_a_we), .a_waddr(lsu_a_waddr), .a_wdata(lsu_a_wdata),
        .a_raddr(buf_a_raddr), .a_rdata(buf_a_rdata),
        .b_we(lsu_b_we), .b_waddr(lsu_b_waddr), .b_wdata(lsu_b_wdata),
        .b_raddr(buf_b_raddr), .b_rdata(buf_b_rdata),
        .b_row_k(mac_b_row_k), .b_row_n(mac_b_row_n),
        .b_row0(buf_brow0), .b_row1(buf_brow1),
        .b_row2(buf_brow2), .b_row3(buf_brow3),
        .c_clear(mac_c_clear),
        .c_we(mac_c_we), .c_waddr(mac_c_waddr), .c_wdata(mac_c_wdata),
        .c_raddr(buf_c_raddr), .c_rdata(buf_c_rdata)
    );

    gemm_lsu u_lsu (
        .clk(clk), .reset(reset),
        .m_dim(m_dim), .n_dim(n_dim), .k_dim(k_dim),
        .a_base(a_base), .b_base(b_base), .c_base(c_base),
        .load_en(lsu_load_en), .load_done(lsu_load_done),
        .store_en(lsu_store_en), .store_done(lsu_store_done),
        .mem_addr(mem_addr), .mem_rdata(mem_rdata),
        .mem_wdata(mem_wdata), .mem_we(mem_we),
        .a_we(lsu_a_we), .a_waddr(lsu_a_waddr), .a_wdata(lsu_a_wdata),
        .b_we(lsu_b_we), .b_waddr(lsu_b_waddr), .b_wdata(lsu_b_wdata),
        .c_raddr(lsu_c_raddr), .c_rdata(buf_c_rdata)
    );

    // =======================================================
    // Compute datapath: pick 1-MAC or 4-MAC
    // =======================================================
    generate
    if (MAC_MODE == 4) begin : g_mac4
        // 1-MAC single B read port unused
        assign mac_b_raddr = 4'd0;
        // MAC_MODE=4는 B를 row read port로 읽으므로 single B read data는 구조적으로 미사용이다.
        // unused_* 더미 소비로 의도적 미사용임을 Verilator에 명시한다.
        wire unused_buf_b_rdata = &buf_b_rdata;

        gemm_mac_datapath4 u_mac (
            .clk(clk), .reset(reset),
            .mac_en(mac_en),
            .m_dim(m_dim), .n_dim(n_dim), .k_dim(k_dim),
            .a_raddr(mac_a_raddr), .a_rdata(buf_a_rdata),
            .b_row_k(mac_b_row_k), .b_row_n(mac_b_row_n),
            .b_row0(buf_brow0), .b_row1(buf_brow1),
            .b_row2(buf_brow2), .b_row3(buf_brow3),
            .c_clear(mac_c_clear), .c_we(mac_c_we),
            .c_waddr(mac_c_waddr), .c_wdata(mac_c_wdata),
            .mac_done(mac_done)
        );
        // 4-MAC does not use c_raddr (accumulate in registers)
        assign mac_c_raddr = 4'd0;
    end
    else begin : g_mac1
        // 4-MAC row read port unused
        assign mac_b_row_k = 3'd0;
        assign mac_b_row_n = 3'd0;
        // MAC_MODE=1은 B를 single read port로 읽으므로 row read data는 구조적으로 미사용이다.
        // unused_* 더미 소비로 의도적 미사용임을 Verilator에 명시한다.
        wire unused_buf_brow = &{buf_brow0, buf_brow1, buf_brow2, buf_brow3};

        gemm_mac_datapath u_mac (
            .clk(clk), .reset(reset),
            .mac_en(mac_en),
            .m_dim(m_dim), .n_dim(n_dim), .k_dim(k_dim),
            .a_raddr(mac_a_raddr), .a_rdata(buf_a_rdata),
            .b_raddr(mac_b_raddr), .b_rdata(buf_b_rdata),
            .c_clear(mac_c_clear), .c_we(mac_c_we),
            .c_waddr(mac_c_waddr), .c_wdata(mac_c_wdata),
            .c_raddr(mac_c_raddr), .c_rdata(buf_c_rdata),
            .mac_done(mac_done)
        );
    end
    endgenerate

endmodule
