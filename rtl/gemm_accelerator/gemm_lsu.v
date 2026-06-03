`timescale 1ns / 1ps
`include "gemm_define.vh"

// =======================================================
// gemm_lsu  (Load/Store Unit) -- ROW-MAJOR WORD-ALIGNED layout
//
//   Storage convention (row starts on a fresh word):
//     A (MxK): row i  -> mem[A_BASE + i] = pack( A[i][0..K-1] )
//     B (KxN): row k  -> mem[B_BASE + k] = pack( B[k][0..N-1] )
//     C (MxN): C[i][j]-> mem[C_BASE + i*N + j]  (int32, unpacked)
//   pack lanes: lane0=[7:0], lane1=[15:8], lane2=[23:16], lane3=[31:24]
//   Unused lanes in a row word are padding (ignored on load).
//
//   This makes addressing trivial (one word per row) and lines up B
//   rows for the 4-MAC extension (one word read = B[k][0..N-1]).
//
//   Memory timing: synchronous read. mem_addr registered at edge T,
//   mem_rdata valid at edge T+1 (one wait state after addr change).
//
//   LOAD per matrix: for each row r:
//     ADR  : mem_addr = base + r        (issue read)
//     LAT  : capture word
//     WR0..: write that row's valid lanes into buffer, one lane/cycle
//   STORE: drive c_raddr -> next cycle c_rdata valid -> write word.
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

    output reg  [11:0] mem_addr,
    input  wire [31:0] mem_rdata,
    output reg  [31:0] mem_wdata,
    output reg         mem_we,

    output reg         a_we,
    output reg  [3:0]  a_waddr,
    output reg  [7:0]  a_wdata,
    output reg         b_we,
    output reg  [3:0]  b_waddr,
    output reg  [7:0]  b_wdata,

    output reg  [3:0]  c_raddr,
    input  wire [31:0] c_rdata
);

    wire [4:0] c_elems = m_dim * n_dim;

    // =======================================================
    // LOAD: row-by-row. For matrix A there are M rows of K lanes.
    //       For matrix B there are K rows of N lanes.
    // =======================================================
    localparam LS_IDLE = 4'd0,
               LS_AADR = 4'd1,
               LS_ALAT = 4'd2,
               LS_AWR  = 4'd3,
               LS_BADR = 4'd4,
               LS_BLAT = 4'd5,
               LS_BWR  = 4'd6,
               LS_DONE = 4'd7;

    reg [3:0]  ls;
    reg [2:0]  row;        // current row (i for A, k for B)
    reg [2:0]  col;        // lane within the row (0..len-1)
    reg [31:0] word_reg;

    // lane extract for current col
    wire [7:0] lane_byte = word_reg[ {col[1:0], 3'b000} +: 8 ];
    // buffer element index = row*width + col
    //   A width = K, B width = N
    wire [3:0] a_eidx = row*k_dim + col;
    wire [3:0] b_eidx = row*n_dim + col;

    // STORE
    localparam SS_IDLE = 2'd0,
               SS_WR   = 2'd1,
               SS_DONE = 2'd2;
    reg [1:0]  ss;
    reg [4:0]  selem;

    always @(posedge clk) begin
        if (reset) begin
            ls <= LS_IDLE; row <= 0; col <= 0; word_reg <= 0;
            a_we<=0; b_we<=0; a_waddr<=0; b_waddr<=0; a_wdata<=0; b_wdata<=0;
            load_done <= 0;
            ss <= SS_IDLE; selem <= 0; store_done <= 0;
            mem_addr <= 0; mem_wdata <= 0; mem_we <= 0; c_raddr <= 0;
        end
        else begin
            a_we <= 0; b_we <= 0; mem_we <= 0;
            load_done <= 0; store_done <= 0;

            // ---------------- LOAD FSM ----------------
            case (ls)
                LS_IDLE: begin
                    if (load_en) begin
                        row <= 0; col <= 0;
                        mem_addr <= a_base;       // A row 0
                        ls <= LS_AADR;
                    end
                end

                LS_AADR: ls <= LS_ALAT;           // wait state for sync read
                LS_ALAT: begin
                    word_reg <= mem_rdata;
                    col <= 0;
                    ls <= LS_AWR;
                end
                LS_AWR: begin
                    a_we    <= 1'b1;
                    a_waddr <= a_eidx;
                    a_wdata <= lane_byte;

                    if (col == k_dim - 1) begin
                        // row finished
                        if (row == m_dim - 1) begin
                            // A done -> start B
                            row <= 0; col <= 0;
                            mem_addr <= b_base;
                            ls <= LS_BADR;
                        end else begin
                            row <= row + 1;
                            mem_addr <= a_base + (row + 1);
                            ls <= LS_AADR;
                        end
                    end else begin
                        col <= col + 1;
                        ls <= LS_AWR;
                    end
                end

                LS_BADR: ls <= LS_BLAT;
                LS_BLAT: begin
                    word_reg <= mem_rdata;
                    col <= 0;
                    ls <= LS_BWR;
                end
                LS_BWR: begin
                    b_we    <= 1'b1;
                    b_waddr <= b_eidx;
                    b_wdata <= lane_byte;

                    if (col == n_dim - 1) begin
                        if (row == k_dim - 1) begin
                            ls <= LS_DONE;
                        end else begin
                            row <= row + 1;
                            mem_addr <= b_base + (row + 1);
                            ls <= LS_BADR;
                        end
                    end else begin
                        col <= col + 1;
                        ls <= LS_BWR;
                    end
                end

                LS_DONE: begin
                    load_done <= 1'b1;
                    if (!load_en) ls <= LS_IDLE;
                end

                default: ls <= LS_IDLE;
            endcase

            // ---------------- STORE FSM (unchanged: C is unpacked) ----
            case (ss)
                SS_IDLE: begin
                    if (store_en) begin
                        selem <= 0; c_raddr <= 0;
                        ss <= SS_WR;
                    end
                end
                SS_WR: begin
                    mem_addr  <= c_base + selem;
                    mem_wdata <= c_rdata;
                    mem_we    <= 1'b1;
                    if (selem == c_elems - 1) begin
                        ss <= SS_DONE;
                    end else begin
                        selem   <= selem + 1;
                        c_raddr <= selem + 1;
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
