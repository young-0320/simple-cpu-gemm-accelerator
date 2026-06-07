`timescale 1ns / 1ps
`include "gemm_define.vh"

// =======================================================
// gemm_mac_datapath_at  (Adder-Tree, K-parallel)
//   For each output element C[i][j], sum the K-dimension dot product
//   four terms at a time using a parallel multiply + adder tree:
//
//     for each (i,j):
//        acc = 0
//        for k in steps of 4:
//           p0..3 = A[i][k+0..3] * B[k+0..3][j]   (masked if k+n >= K)
//           acc  += (p0+p1) + (p2+p3)             (adder tree)
//        C[i][j] = acc
//
//   Same external handshake as the other datapaths (mac_en/mac_done,
//   c_clear/c_we/c_waddr/c_wdata). Reads A/B via the buffer's K-column
//   port (at_i/at_j/at_k -> a_col0..3, b_col0..3), so the row-aligned
//   memory layout is reused unchanged.
//
//   compute cycles ~ M*N*ceil(K/4) accumulate steps (+ overhead).
// =======================================================
module gemm_mac_datapath_at (
    input  wire        clk,
    input  wire        reset,

    input  wire        mac_en,
    input  wire [2:0]  m_dim,
    input  wire [2:0]  n_dim,
    input  wire [2:0]  k_dim,

    // buffer K-column read interface
    output wire [2:0]  at_i,
    output wire [2:0]  at_j,
    output wire [2:0]  at_k,
    output wire [2:0]  at_kdim,
    output wire [2:0]  at_ndim,
    input  wire [7:0]  a_col0, a_col1, a_col2, a_col3,
    input  wire [7:0]  b_col0, b_col1, b_col2, b_col3,

    // C buffer write
    output reg         c_clear,
    output reg         c_we,
    output reg  [3:0]  c_waddr,
    output reg  [31:0] c_wdata,

    output reg         mac_done
);

    localparam P_IDLE  = 3'd0,
               P_CLEAR = 3'd1,
               P_ITER  = 3'd2,   // accumulate 4 K-terms for current (i,j)
               P_WB    = 3'd3,   // register C[i][j] write
               P_WB2   = 3'd4,   // let the buffer write commit, advance
               P_FIN   = 3'd5;

    reg [2:0] phase;
    reg [2:0] i, j, k;
    reg signed [31:0] acc;

    assign at_i = i;
    assign at_j = j;
    assign at_k = k;
    assign at_kdim = k_dim;
    assign at_ndim = n_dim;

    // signed unpack
    wire signed [7:0] a0 = a_col0, a1 = a_col1, a2 = a_col2, a3 = a_col3;
    wire signed [7:0] b0 = b_col0, b1 = b_col1, b2 = b_col2, b3 = b_col3;

    // parallel products (int8*int8 -> 32-bit signed)
    wire signed [31:0] p0 = a0 * b0;
    wire signed [31:0] p1 = a1 * b1;
    wire signed [31:0] p2 = a2 * b2;
    wire signed [31:0] p3 = a3 * b3;

    // K-dimension masking: only k+n < K participates
    wire m0 = (k + 3'd0 < k_dim);
    wire m1 = (k + 3'd1 < k_dim);
    wire m2 = (k + 3'd2 < k_dim);
    wire m3 = (k + 3'd3 < k_dim);
    wire signed [31:0] mp0 = m0 ? p0 : 32'sd0;
    wire signed [31:0] mp1 = m1 ? p1 : 32'sd0;
    wire signed [31:0] mp2 = m2 ? p2 : 32'sd0;
    wire signed [31:0] mp3 = m3 ? p3 : 32'sd0;

    // adder tree
    wire signed [31:0] tree_sum = (mp0 + mp1) + (mp2 + mp3);

    // last K-step for this (i,j)?
    wire k_last = (k + 3'd4 >= k_dim);
    wire j_last = (j == n_dim - 1);
    wire i_last = (i == m_dim - 1);

    always @(posedge clk) begin
        if (reset) begin
            phase <= P_IDLE;
            i <= 0; j <= 0; k <= 0; acc <= 0;
            c_clear <= 0; c_we <= 0; c_waddr <= 0; c_wdata <= 0;
            mac_done <= 0;
        end
        else begin
            c_clear <= 0; c_we <= 0; mac_done <= 0;

            case (phase)
                P_IDLE: begin
                    if (mac_en) begin
                        c_clear <= 1'b1;
                        i <= 0; j <= 0; k <= 0; acc <= 0;
                        phase <= P_CLEAR;
                    end
                end

                P_CLEAR: phase <= P_ITER;

                P_ITER: begin
                    acc <= acc + tree_sum;
                    if (k_last) begin
                        phase <= P_WB;
                    end else begin
                        k <= k + 3'd4;
                    end
                end

                P_WB: begin
                    // write completed C[i][j]. c_we/c_waddr/c_wdata are
                    // registered here and take effect next cycle; we then
                    // pass through P_WB2 to guarantee the buffer write
                    // commits before advancing (esp. the final element).
                    c_we    <= 1'b1;
                    c_waddr <= i*n_dim + j;
                    c_wdata <= acc;
                    phase   <= P_WB2;
                end

                P_WB2: begin
                    // write now committing; set up next (i,j) or finish
                    acc <= 0;
                    k <= 0;
                    if (j_last) begin
                        j <= 0;
                        if (i_last) phase <= P_FIN;
                        else begin i <= i + 1; phase <= P_ITER; end
                    end else begin
                        j <= j + 1;
                        phase <= P_ITER;
                    end
                end

                P_FIN: begin
                    mac_done <= 1'b1;
                    if (!mac_en) phase <= P_IDLE;
                end

                default: phase <= P_IDLE;
            endcase
        end
    end

endmodule
