`timescale 1ns / 1ps
`include "gemm_define.vh"

// =======================================================
// gemm_lsu  (Load/Store Unit) -- DUAL-PORT, row-aligned layout
//
//   Two memory ports let A and B load in parallel:
//     Port A: read A rows + write C  (read/write)
//     Port B: read B rows            (read only)
//
//   Storage convention (row-aligned, one row per word):
//     A (MxK): row i  -> mem[A_BASE + i] = pack(A[i][0..K-1])
//     B (KxN): row k  -> mem[B_BASE + k] = pack(B[k][0..N-1])
//     C (MxN): C[i][j]-> mem[C_BASE + i*N + j]  (int32, unpacked)
//   pack lanes: lane0=[7:0], lane1=[15:8], lane2=[23:16], lane3=[31:24]
//
//   Memory timing: synchronous read on both ports. addr registered at
//   edge T, rdata valid at edge T+1 (one wait state after addr change).
//
//   LOAD: A has M rows, B has K rows. Both ports walk rows in lockstep
//   until each finishes its own row count; lanes are written into the
//   buffers one per cycle. Because A and B advance together, total LOAD
//   time tracks max(M, K) rows instead of M + K.
//
//   STORE: Port A writes C, one int32 element per word, from C_BASE.
// =======================================================
module gemm_lsu (
    input  wire        clk,
    input  wire        reset,

    input  wire [2:0]  m_dim,
    input  wire [2:0]  n_dim,
    input  wire [2:0]  k_dim,
    input  wire [11:0] a_base,
    input  wire [11:0] b_base,
    input  wire [11:0] c_base,

    input  wire        load_en,
    output reg         load_done,
    input  wire        store_en,
    output reg         store_done,

    // ---- Port A: read A / write C ----
    output reg  [11:0] mem_addr_a,
    input  wire [31:0] mem_rdata_a,
    output reg  [31:0] mem_wdata,
    output reg         mem_we,
    // ---- Port B: read B ----
    output reg  [11:0] mem_addr_b,
    input  wire [31:0] mem_rdata_b,

    // ---- A/B buffer write ----
    output reg         a_we,
    output reg  [3:0]  a_waddr,
    output reg  [7:0]  a_wdata,
    output reg         b_we,
    output reg  [3:0]  b_waddr,
    output reg  [7:0]  b_wdata,

    // ---- C buffer read (during STORE) ----
    output reg  [3:0]  c_raddr,
    input  wire [31:0] c_rdata
);

    wire [4:0] c_elems = m_dim * n_dim;

    // =======================================================
    // LOAD: parallel A (port A) and B (port B)
    //   Each port independently walks its rows. A row = one word read,
    //   then K (for A) or N (for B) lanes written one per cycle.
    //   Phases per port:
    //     ADR  : drive address for current row
    //     LAT  : capture word (sync-read wait already covered by ADR->LAT)
    //     WR   : write valid lanes into the buffer, one per cycle
    //   A port also handles C store after load (separate STORE FSM).
    // =======================================================
    localparam PA_IDLE = 3'd0, PA_ADR = 3'd1, PA_LAT = 3'd2, PA_WR = 3'd3, PA_DONE = 3'd4;
    localparam PB_IDLE = 3'd0, PB_ADR = 3'd1, PB_LAT = 3'd2, PB_WR = 3'd3, PB_DONE = 3'd4;

    reg [2:0] pa, pb;
    reg [2:0] a_row, a_col;       // A: row i (0..M-1), col within row (0..K-1)
    reg [2:0] b_row, b_col;       // B: row k (0..K-1), col within row (0..N-1)
    reg [31:0] a_word, b_word;

    wire [7:0] a_lane = a_word[ {a_col[1:0], 3'b000} +: 8 ];
    wire [7:0] b_lane = b_word[ {b_col[1:0], 3'b000} +: 8 ];
    wire [3:0] a_eidx = a_row*k_dim + a_col;
    wire [3:0] b_eidx = b_row*n_dim + b_col;

    wire b_load_done = (pb == PB_DONE);

    // =======================================================
    // STORE (port A): C unpacked, one element per word
    // =======================================================
    localparam SS_IDLE = 2'd0, SS_WR = 2'd1, SS_DONE = 2'd2;
    reg [1:0]  ss;
    reg [4:0]  selem;

    always @(posedge clk) begin
        if (reset) begin
            pa <= PA_IDLE; pb <= PB_IDLE;
            a_row <= 0; a_col <= 0; b_row <= 0; b_col <= 0;
            a_word <= 0; b_word <= 0;
            a_we <= 0; b_we <= 0; a_waddr <= 0; b_waddr <= 0;
            a_wdata <= 0; b_wdata <= 0;
            load_done <= 0;
            ss <= SS_IDLE; selem <= 0; store_done <= 0;
            mem_addr_a <= 0; mem_addr_b <= 0; mem_wdata <= 0; mem_we <= 0;
            c_raddr <= 0;
        end
        else begin
            a_we <= 0; b_we <= 0; mem_we <= 0;
            load_done <= 0; store_done <= 0;

            // ---------------- LOAD: Port A (A matrix) ----------------
            case (pa)
                PA_IDLE: begin
                    if (load_en) begin
                        a_row <= 0; a_col <= 0;
                        mem_addr_a <= a_base;       // A row 0
                        pa <= PA_ADR;
                    end
                end
                PA_ADR: pa <= PA_LAT;               // sync-read wait
                PA_LAT: begin
                    a_word <= mem_rdata_a;
                    a_col <= 0;
                    pa <= PA_WR;
                end
                PA_WR: begin
                    a_we    <= 1'b1;
                    a_waddr <= a_eidx;
                    a_wdata <= a_lane;
                    if (a_col == k_dim - 1) begin
                        if (a_row == m_dim - 1) begin
                            pa <= PA_DONE;
                        end else begin
                            a_row <= a_row + 1;
                            mem_addr_a <= a_base + {9'd0, (a_row + 3'd1)};
                            pa <= PA_ADR;
                        end
                    end else begin
                        a_col <= a_col + 1;
                        pa <= PA_WR;
                    end
                end
                PA_DONE: begin
                    // wait until both ports finished, then signal load_done
                    if (b_load_done) begin
                        load_done <= 1'b1;
                        if (!load_en) pa <= PA_IDLE;
                    end
                end
                default: pa <= PA_IDLE;
            endcase

            // ---------------- LOAD: Port B (B matrix) ----------------
            case (pb)
                PB_IDLE: begin
                    if (load_en) begin
                        b_row <= 0; b_col <= 0;
                        mem_addr_b <= b_base;       // B row 0
                        pb <= PB_ADR;
                    end
                end
                PB_ADR: pb <= PB_LAT;
                PB_LAT: begin
                    b_word <= mem_rdata_b;
                    b_col <= 0;
                    pb <= PB_WR;
                end
                PB_WR: begin
                    b_we    <= 1'b1;
                    b_waddr <= b_eidx;
                    b_wdata <= b_lane;
                    if (b_col == n_dim - 1) begin
                        if (b_row == k_dim - 1) begin
                            pb <= PB_DONE;
                        end else begin
                            b_row <= b_row + 1;
                            mem_addr_b <= b_base + {9'd0, (b_row + 3'd1)};
                            pb <= PB_ADR;
                        end
                    end else begin
                        b_col <= b_col + 1;
                        pb <= PB_WR;
                    end
                end
                PB_DONE: begin
                    if (!load_en) pb <= PB_IDLE;
                end
                default: pb <= PB_IDLE;
            endcase

            // ---------------- STORE (port A) ----------------
            case (ss)
                SS_IDLE: begin
                    if (store_en) begin
                        selem <= 0; c_raddr <= 0;
                        ss <= SS_WR;
                    end
                end
                SS_WR: begin
                    mem_addr_a <= c_base + {7'd0, selem};
                    mem_wdata  <= c_rdata;
                    mem_we     <= 1'b1;
                    if (selem == c_elems - 1) begin
                        ss <= SS_DONE;
                    end else begin
                        selem   <= selem + 1;
                        c_raddr <= selem[3:0] + 4'd1;
                        ss <= SS_WR;
                    end
                end
                SS_DONE: begin
                    store_done <= 1'b1;
                    if (!store_en) ss <= SS_IDLE;
                end
                default: ss <= SS_IDLE;
            endcase
        end
    end

endmodule
