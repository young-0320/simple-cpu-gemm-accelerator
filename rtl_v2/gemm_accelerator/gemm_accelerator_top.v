`timescale 1ns / 1ps
`include "gemm_define.vh"

// =======================================================
// gemm_accelerator_top
//   5 sub-blocks + buffer-port mux between LSU (LOAD/STORE) and MAC
//   (COMPUTE). Parameterized compute datapath:
//     MAC_MODE = 0 : adder-tree (AT)    (K direction)
//     MAC_MODE = 1 : 1-MAC serial       (baseline)
//     MAC_MODE = 4 : 4-MAC row-parallel (N direction)
//     MAC_MODE = 8 : (reserved for future 8-MAC)
//   FSM / LSU / MMIO / buffer are shared; only the MAC instance and
//   its buffer wiring differ. Memory is dual-port (A read / C write on
//   port A, B read on port B).
// =======================================================
module gemm_accelerator_top #(
    parameter MAC_MODE = 1   // 0=adder-tree, 1=1-MAC, 4=4-MAC (8=future)
) (
    input  wire        clk,
    input  wire        reset,

    input  wire        mmio_sel,
    input  wire        mmio_we,
    input  wire [2:0]  mmio_off,
    input  wire [31:0] mmio_wdata,
    output wire [31:0] mmio_rdata,

    // ---- external memory: dual port ----
    //   Port A: read A / write C   Port B: read B
    output wire [11:0] mem_addr_a,
    input  wire [31:0] mem_rdata_a,
    output wire [31:0] mem_wdata,
    output wire        mem_we,
    output wire [11:0] mem_addr_b,
    input  wire [31:0] mem_rdata_b,

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
    /* verilator lint_off UNUSEDSIGNAL */
    // buf_a_rdata: unused in AT build (reads via K-column port).
    wire [7:0]  buf_a_rdata;
    // buf_b_rdata is consumed only in the 1-MAC build (g_mac1). In the
    // 4-MAC build, B is read via the row-read port, so this net has no
    // reader and the unused warning is expected/benign.
    wire [7:0]  buf_b_rdata;
    /* verilator lint_on UNUSEDSIGNAL */
    wire [3:0]  mac_b_raddr;             // 1-MAC single B read
    wire [2:0]  mac_b_row_k;
    wire [2:0]  mac_b_row_n;
    /* verilator lint_off UNUSEDSIGNAL */
    // 4-MAC row-read outputs; consumed only in the 4-MAC build (g_mac4).
    // In the 1-MAC build these have no reader (B uses the single port).
    wire [7:0]  buf_brow0, buf_brow1, buf_brow2, buf_brow3;
    /* verilator lint_on UNUSEDSIGNAL */

    // ---- adder-tree (AT) K-column read wires ----
    wire [2:0]  mac_at_i, mac_at_j, mac_at_k, mac_at_kdim, mac_at_ndim;
    /* verilator lint_off UNUSEDSIGNAL */
    // AT K-column outputs; consumed only in the AT build (g_at).
    wire [7:0]  buf_acol0, buf_acol1, buf_acol2, buf_acol3;
    wire [7:0]  buf_bcol0, buf_bcol1, buf_bcol2, buf_bcol3;
    /* verilator lint_on UNUSEDSIGNAL */

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
        .at_i(mac_at_i), .at_j(mac_at_j), .at_k(mac_at_k),
        .at_kdim(mac_at_kdim), .at_ndim(mac_at_ndim),
        .a_col0(buf_acol0), .a_col1(buf_acol1),
        .a_col2(buf_acol2), .a_col3(buf_acol3),
        .b_col0(buf_bcol0), .b_col1(buf_bcol1),
        .b_col2(buf_bcol2), .b_col3(buf_bcol3),
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
        .mem_addr_a(mem_addr_a), .mem_rdata_a(mem_rdata_a),
        .mem_wdata(mem_wdata), .mem_we(mem_we),
        .mem_addr_b(mem_addr_b), .mem_rdata_b(mem_rdata_b),
        .a_we(lsu_a_we), .a_waddr(lsu_a_waddr), .a_wdata(lsu_a_wdata),
        .b_we(lsu_b_we), .b_waddr(lsu_b_waddr), .b_wdata(lsu_b_wdata),
        .c_raddr(lsu_c_raddr), .c_rdata(buf_c_rdata)
    );

    // =======================================================
    // Compute datapath: pick AT / 1-MAC / 4-MAC
    //   MAC_MODE = 0 : adder-tree (AT)    (K direction)
    //            = 1 : 1-MAC serial       (baseline)
    //            = 4 : 4-MAC row-parallel (N direction)
    //            = 8 : (reserved for future 8-MAC)
    // =======================================================
    generate
    if (MAC_MODE == 0) begin : g_at
        // unused ports for AT mode
        assign mac_a_raddr = 4'd0;
        assign mac_b_raddr = 4'd0;
        assign mac_b_row_k = 3'd0;
        assign mac_b_row_n = 3'd0;
        assign mac_c_raddr = 4'd0;

        gemm_mac_datapath_at u_mac (
            .clk(clk), .reset(reset),
            .mac_en(mac_en),
            .m_dim(m_dim), .n_dim(n_dim), .k_dim(k_dim),
            .at_i(mac_at_i), .at_j(mac_at_j), .at_k(mac_at_k),
            .at_kdim(mac_at_kdim), .at_ndim(mac_at_ndim),
            .a_col0(buf_acol0), .a_col1(buf_acol1),
            .a_col2(buf_acol2), .a_col3(buf_acol3),
            .b_col0(buf_bcol0), .b_col1(buf_bcol1),
            .b_col2(buf_bcol2), .b_col3(buf_bcol3),
            .c_clear(mac_c_clear), .c_we(mac_c_we),
            .c_waddr(mac_c_waddr), .c_wdata(mac_c_wdata),
            .mac_done(mac_done)
        );
    end
    else if (MAC_MODE == 4) begin : g_mac4
        assign mac_b_raddr = 4'd0;
        // AT K-column port unused
        assign mac_at_i = 3'd0; assign mac_at_j = 3'd0; assign mac_at_k = 3'd0;
        assign mac_at_kdim = 3'd0; assign mac_at_ndim = 3'd0;

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
        assign mac_c_raddr = 4'd0;
    end
    else begin : g_mac1   // MAC_MODE == 1 (default)
        assign mac_b_row_k = 3'd0;
        assign mac_b_row_n = 3'd0;
        // AT K-column port unused
        assign mac_at_i = 3'd0; assign mac_at_j = 3'd0; assign mac_at_k = 3'd0;
        assign mac_at_kdim = 3'd0; assign mac_at_ndim = 3'd0;

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
