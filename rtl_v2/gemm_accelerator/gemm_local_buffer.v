`timescale 1ns / 1ps
`include "gemm_define.vh"

// =======================================================
// gemm_local_buffer
//   Register-array tile storage for up to 4x4 GEMM.
//     a_buf, b_buf : signed int8  x 16   (written by LSU, read by MAC)
//     c_buf        : signed int32 x 16   (written by MAC, read by LSU)
//   Reads are combinational (same-cycle), writes are clock-synchronous.
//   c_buf supports a clear (zeroing) before COMPUTE so the MAC can
//   accumulate from zero.
//
//   Index convention (row-major, computed by LSU/MAC):
//     A_index = i*K + k    B_index = k*N + j    C_index = i*N + j
// =======================================================
module gemm_local_buffer (
    input  wire        clk,

    // ---- A buffer : write (LSU) ----
    input  wire        a_we,
    input  wire [3:0]  a_waddr,
    input  wire [7:0]  a_wdata,   // signed int8
    // ---- A buffer : read (MAC) ----
    input  wire [3:0]  a_raddr,
    output wire [7:0]  a_rdata,

    // ---- B buffer : write (LSU) ----
    input  wire        b_we,
    input  wire [3:0]  b_waddr,
    input  wire [7:0]  b_wdata,   // signed int8
    // ---- B buffer : read (MAC, 1-MAC single port) ----
    input  wire [3:0]  b_raddr,
    output wire [7:0]  b_rdata,
    // ---- B buffer : row read (4-MAC, reads B[k][0..3] at once) ----
    //   Given row k and width N, returns the 4 column elements of that
    //   row: b_row{0..3} = b_buf[k*N + 0..3]. Unused columns read junk
    //   but the MAC ignores lanes >= N.
    input  wire [2:0]  b_row_k,     // which row k
    input  wire [2:0]  b_row_n,     // N (row width) for index calc
    output wire [7:0]  b_row0,
    output wire [7:0]  b_row1,
    output wire [7:0]  b_row2,
    output wire [7:0]  b_row3,
    // ---- A/B K-column read (adder-tree mode): 4 elements along K ----
    //   a_col{0..3} = A[i][k..k+3] = a_buf[i*K + (k+0..3)]
    //   b_col{0..3} = B[k..k+3][j] = b_buf[(k+0..3)*N + j]
    input  wire [2:0]  at_i,        // current row i of A / output row
    input  wire [2:0]  at_j,        // current col j of B / output col
    input  wire [2:0]  at_k,        // base k (advances by 4)
    input  wire [2:0]  at_kdim,     // K
    input  wire [2:0]  at_ndim,     // N
    output wire [7:0]  a_col0,
    output wire [7:0]  a_col1,
    output wire [7:0]  a_col2,
    output wire [7:0]  a_col3,
    output wire [7:0]  b_col0,
    output wire [7:0]  b_col1,
    output wire [7:0]  b_col2,
    output wire [7:0]  b_col3,

    // ---- C buffer : clear-all (before COMPUTE) ----
    input  wire        c_clear,
    // ---- C buffer : write (MAC) ----
    input  wire        c_we,
    input  wire [3:0]  c_waddr,
    input  wire [31:0] c_wdata,   // signed int32
    // ---- C buffer : read (LSU during STORE) ----
    input  wire [3:0]  c_raddr,
    output wire [31:0] c_rdata
);

    reg [7:0]  a_buf [0:`GEMM_MAX_ELEM-1];
    reg [7:0]  b_buf [0:`GEMM_MAX_ELEM-1];
    reg [31:0] c_buf [0:`GEMM_MAX_ELEM-1];

    integer idx;

    // -------------------------------------------------------
    // A / B write
    // -------------------------------------------------------
    always @(posedge clk) begin
        if (a_we) a_buf[a_waddr] <= a_wdata;
        if (b_we) b_buf[b_waddr] <= b_wdata;
    end

    // -------------------------------------------------------
    // C clear / write  (clear has priority; they never overlap in
    // normal FSM flow, but priority keeps behavior well-defined)
    // -------------------------------------------------------
    always @(posedge clk) begin
        if (c_clear) begin
            for (idx = 0; idx < `GEMM_MAX_ELEM; idx = idx + 1)
                c_buf[idx] <= 32'd0;
        end
        else if (c_we) begin
            c_buf[c_waddr] <= c_wdata;
        end
    end

    // -------------------------------------------------------
    // Combinational reads
    // -------------------------------------------------------
    assign a_rdata = a_buf[a_raddr];
    assign b_rdata = b_buf[b_raddr];
    assign c_rdata = c_buf[c_raddr];

    // 4-MAC row read: B[k][0..3] = b_buf[k*N + col]
    wire [3:0] brow_base = b_row_k * b_row_n;
    assign b_row0 = b_buf[brow_base + 3'd0];
    assign b_row1 = b_buf[brow_base + 3'd1];
    assign b_row2 = b_buf[brow_base + 3'd2];
    assign b_row3 = b_buf[brow_base + 3'd3];

    // adder-tree K-column read:
    //   A[i][k+n] = a_buf[i*K + k + n]
    //   B[k+n][j] = b_buf[(k+n)*N + j]
    // widen intermediates to 6-bit to avoid 3-bit multiply/add overflow;
    // only [3:0] indexes the 16-entry buffers, so [5:4] are intentionally
    // unused headroom.
    /* verilator lint_off UNUSEDSIGNAL */
    wire [5:0] a_kbase = {3'd0,at_i}*{3'd0,at_kdim} + {3'd0,at_k};   // i*K + k
    wire [5:0] bk0 = ({3'd0,at_k} + 6'd0)*{3'd0,at_ndim} + {3'd0,at_j};
    wire [5:0] bk1 = ({3'd0,at_k} + 6'd1)*{3'd0,at_ndim} + {3'd0,at_j};
    wire [5:0] bk2 = ({3'd0,at_k} + 6'd2)*{3'd0,at_ndim} + {3'd0,at_j};
    wire [5:0] bk3 = ({3'd0,at_k} + 6'd3)*{3'd0,at_ndim} + {3'd0,at_j};
    /* verilator lint_on UNUSEDSIGNAL */
    assign a_col0 = a_buf[a_kbase[3:0] + 4'd0];
    assign a_col1 = a_buf[a_kbase[3:0] + 4'd1];
    assign a_col2 = a_buf[a_kbase[3:0] + 4'd2];
    assign a_col3 = a_buf[a_kbase[3:0] + 4'd3];
    assign b_col0 = b_buf[bk0[3:0]];
    assign b_col1 = b_buf[bk1[3:0]];
    assign b_col2 = b_buf[bk2[3:0]];
    assign b_col3 = b_buf[bk3[3:0]];

endmodule
