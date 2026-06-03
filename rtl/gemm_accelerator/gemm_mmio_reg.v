`timescale 1ns / 1ps
`include "gemm_define.vh"

// =======================================================
// gemm_mmio_reg
//   CPU<->GEMM control/status register block.
//   Address decoding (is this the 0xFF0 region?) is done by the
//   TOP module. This block only sees a select + 3-bit offset, so it
//   is reusable and address-independent.
//
//   - Write path : CPU writes A/B/C base, M/N/K, CTRL via STORE
//   - Read  path : CPU reads STATUS via LOAD (combinational mmio_rdata)
//   - Sticky flags (done/error/invalid_size) held until clear_done
// =======================================================
module gemm_mmio_reg (
    input  wire        clk,
    input  wire        reset,

    // ---- CPU side (driven by TOP after address decode) ----
    input  wire        mmio_sel,    // this access targets the MMIO block
    input  wire        mmio_we,     // write enable (STORE)
    input  wire [2:0]  mmio_off,    // register offset = cpu_addr[2:0]
    input  wire [31:0] mmio_wdata,  // STORE data (= ACC)
    output reg  [31:0] mmio_rdata,  // LOAD data  (-> ACC)

    // ---- to Controller FSM ----
    output wire [11:0] a_base,
    output wire [11:0] b_base,
    output wire [11:0] c_base,
    output wire [2:0]  m_dim,
    output wire [2:0]  n_dim,
    output wire [2:0]  k_dim,
    output wire        start_pulse,   // 1-cycle pulse when CTRL.start written
    output wire        clear_pulse,   // 1-cycle pulse when CTRL.clear_done written

    // ---- from Controller FSM (status sources) ----
    input  wire        fsm_busy,
    input  wire        fsm_set_done,    // FSM asserts to latch done
    input  wire        fsm_set_error,   // FSM asserts to latch error
    input  wire        fsm_set_invsize  // FSM asserts to latch invalid_size
);

    // -------------------------------------------------------
    // Operand / dimension registers
    // -------------------------------------------------------
    reg [11:0] r_a_base, r_b_base, r_c_base;
    reg [2:0]  r_m, r_n, r_k;

    assign a_base = r_a_base;
    assign b_base = r_b_base;
    assign c_base = r_c_base;
    assign m_dim  = r_m;
    assign n_dim  = r_n;
    assign k_dim  = r_k;

    // -------------------------------------------------------
    // Sticky status flags
    // -------------------------------------------------------
    reg s_done, s_error, s_invsize;

    // -------------------------------------------------------
    // CTRL write -> 1-cycle pulses
    //   A write to CTRL with bit0=1 => start_pulse
    //                    with bit1=1 => clear_pulse
    // -------------------------------------------------------
    wire ctrl_write = mmio_sel & mmio_we & (mmio_off == `GEMM_OFF_CTRL);
    assign start_pulse = ctrl_write & mmio_wdata[`GEMM_CTRL_START_BIT];
    assign clear_pulse = ctrl_write & mmio_wdata[`GEMM_CTRL_CLEAR_DONE_BIT];

    // -------------------------------------------------------
    // Register write logic
    // -------------------------------------------------------
    always @(posedge clk) begin
        if (reset) begin
            r_a_base <= 12'd0; r_b_base <= 12'd0; r_c_base <= 12'd0;
            r_m <= 3'd0; r_n <= 3'd0; r_k <= 3'd0;
        end
        else if (mmio_sel & mmio_we) begin
            case (mmio_off)
                `GEMM_OFF_A_BASE: r_a_base <= mmio_wdata[11:0];
                `GEMM_OFF_B_BASE: r_b_base <= mmio_wdata[11:0];
                `GEMM_OFF_C_BASE: r_c_base <= mmio_wdata[11:0];
                `GEMM_OFF_M:      r_m <= mmio_wdata[2:0];
                `GEMM_OFF_N:      r_n <= mmio_wdata[2:0];
                `GEMM_OFF_K:      r_k <= mmio_wdata[2:0];
                default: ; // CTRL handled via pulses; STATUS is read-only
            endcase
        end
    end

    // -------------------------------------------------------
    // Sticky status flag logic
    //   set by FSM, cleared by CTRL.clear_done
    // -------------------------------------------------------
    always @(posedge clk) begin
        if (reset) begin
            s_done <= 1'b0; s_error <= 1'b0; s_invsize <= 1'b0;
        end
        else if (clear_pulse) begin
            s_done <= 1'b0; s_error <= 1'b0; s_invsize <= 1'b0;
        end
        else begin
            if (fsm_set_done)    s_done    <= 1'b1;
            if (fsm_set_error)   s_error   <= 1'b1;
            if (fsm_set_invsize) s_invsize <= 1'b1;
        end
    end

    // -------------------------------------------------------
    // STATUS read (combinational)
    //   Always readable, even while busy (separate path from BRAM port)
    // -------------------------------------------------------
    wire [31:0] status_word;
    assign status_word = { 28'd0,
                           s_invsize,
                           s_error,
                           s_done,
                           fsm_busy };

    always @(*) begin
        mmio_rdata = 32'd0;
        if (mmio_sel && (mmio_off == `GEMM_OFF_STATUS))
            mmio_rdata = status_word;
    end

endmodule
