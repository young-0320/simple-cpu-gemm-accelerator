`timescale 1ns / 1ps
`include "gemm_define.vh"

// =======================================================
// gemm_controller_fsm
//   Sequences the accelerator: IDLE -> LOAD -> COMPUTE -> STORE -> DONE
//   - On start_pulse, validates M/N/K in [1,4].
//     Invalid -> no memory access, report done+error+invalid_size.
//   - Drives enable to LSU (load/store) and MAC, waits for *_done
//     handshake. Datapath-internal timing is hidden from the FSM,
//     so baseline(1-MAC) and extension(4-MAC) share this FSM.
// =======================================================
module gemm_controller_fsm (
    input  wire        clk,
    input  wire        reset,

    // ---- from MMIO ----
    input  wire        start_pulse,
    input  wire        clear_pulse,
    input  wire [2:0]  m_dim,
    input  wire [2:0]  n_dim,
    input  wire [2:0]  k_dim,

    // ---- to MMIO (status sources) ----
    output reg         busy,
    output reg         set_done,
    output reg         set_error,
    output reg         set_invsize,

    // ---- handshake with LSU (load A/B) ----
    output reg         lsu_load_en,
    input  wire        lsu_load_done,

    // ---- handshake with MAC datapath (compute) ----
    output reg         mac_en,
    input  wire        mac_done,

    // ---- handshake with LSU (store C) ----
    output reg         lsu_store_en,
    input  wire        lsu_store_done,

    // ---- debug ----
    output wire [2:0]  state_debug
);

    reg [2:0] state, next_state;

    assign state_debug = state;

    // dimension validity: 1 <= d <= 4
    function valid_dim(input [2:0] d);
        valid_dim = (d >= `GEMM_DIM_MIN) && (d <= `GEMM_DIM_MAX);
    endfunction
    wire dims_ok = valid_dim(m_dim) & valid_dim(n_dim) & valid_dim(k_dim);

    // -------------------------------------------------------
    // State register
    // -------------------------------------------------------
    always @(posedge clk) begin
        if (reset) state <= `GEMM_S_IDLE;
        else       state <= next_state;
    end

    // -------------------------------------------------------
    // Next-state logic
    // -------------------------------------------------------
    always @(*) begin
        next_state = state;
        case (state)
            `GEMM_S_IDLE: begin
                if (start_pulse)
                    next_state = dims_ok ? `GEMM_S_LOAD : `GEMM_S_DONE;
            end
            `GEMM_S_LOAD:    if (lsu_load_done)  next_state = `GEMM_S_COMPUTE;
            `GEMM_S_COMPUTE: if (mac_done)       next_state = `GEMM_S_STORE;
            `GEMM_S_STORE:   if (lsu_store_done) next_state = `GEMM_S_DONE;
            `GEMM_S_DONE:    if (clear_pulse)    next_state = `GEMM_S_IDLE;
            default:         next_state = `GEMM_S_IDLE;
        endcase
    end

    // -------------------------------------------------------
    // Output logic (Moore-ish, with start-time validation pulse)
    // -------------------------------------------------------
    always @(*) begin
        // defaults
        busy         = 1'b0;
        set_done     = 1'b0;
        set_error    = 1'b0;
        set_invsize  = 1'b0;
        lsu_load_en  = 1'b0;
        mac_en       = 1'b0;
        lsu_store_en = 1'b0;

        case (state)
            `GEMM_S_IDLE: begin
                // invalid dimensions: latch flags at the start cycle,
                // transition straight to DONE without memory access
                if (start_pulse && !dims_ok) begin
                    set_done    = 1'b1;
                    set_error   = 1'b1;
                    set_invsize = 1'b1;
                end
            end
            `GEMM_S_LOAD: begin
                busy        = 1'b1;
                lsu_load_en = 1'b1;
            end
            `GEMM_S_COMPUTE: begin
                busy   = 1'b1;
                mac_en = 1'b1;
            end
            `GEMM_S_STORE: begin
                busy         = 1'b1;
                lsu_store_en = 1'b1;
            end
            `GEMM_S_DONE: begin
                // valid completion latches done once (on entry)
                // detect entry: previous state finished store
                set_done = 1'b1;  // harmless re-assert; mmio latches sticky
            end
            default: ;
        endcase
    end

endmodule
