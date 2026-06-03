`timescale 1ns / 1ps
`include "gemm_define.vh"

// =======================================================
// gemm_mac_datapath4  (4-MAC row-parallel)
//   Computes one full output ROW per inner loop: for a fixed i, the
//   four column accumulators advance together over k.
//
//     for each row i (0..M-1):
//        acc0..3 = 0
//        for k in 0..K-1:
//           a = A[i][k]                       (shared by all 4 MACs)
//           acc0 += a * B[k][0]
//           acc1 += a * B[k][1]
//           acc2 += a * B[k][2]
//           acc3 += a * B[k][3]
//        write C[i][0..N-1] = acc0..(N-1)
//
//   compute cycles ~ M*K (vs M*N*K for 1-MAC). Lanes >= N are computed
//   but never written back, so they are harmless.
//
//   Buffer ports used during COMPUTE:
//     a_raddr        -> A[i][k]
//     b_row_k/b_row_n-> B[k][0..3] via the 4-wide row read port
//     c_we/c_waddr   -> write one C element per cycle in the writeback
// =======================================================
module gemm_mac_datapath4 (
    input  wire        clk,
    input  wire        reset,

    input  wire        mac_en,
    input  wire [2:0]  m_dim,
    input  wire [2:0]  n_dim,
    input  wire [2:0]  k_dim,

    // A single read
    output wire [3:0]  a_raddr,
    input  wire [7:0]  a_rdata,
    // B row read (4 columns at once)
    output wire [2:0]  b_row_k,
    output wire [2:0]  b_row_n,
    input  wire [7:0]  b_row0,
    input  wire [7:0]  b_row1,
    input  wire [7:0]  b_row2,
    input  wire [7:0]  b_row3,

    // C buffer access
    output reg         c_clear,
    output reg         c_we,
    output reg  [3:0]  c_waddr,
    output reg  [31:0] c_wdata,

    output reg         mac_done
);

    localparam P_IDLE  = 3'd0,
               P_CLEAR = 3'd1,
               P_ITER  = 3'd2,   // accumulate over k for current row i
               P_WB    = 3'd3,   // write back C[i][0..N-1]
               P_FIN   = 3'd4;

    reg [2:0] phase;
    reg [2:0] i, k;
    reg [2:0] wb_col;            // writeback column counter

    reg signed [31:0] acc0, acc1, acc2, acc3;

    // current A index = i*K + k
    assign a_raddr = i*k_dim + k;
    // B row k, width N
    assign b_row_k = k;
    assign b_row_n = n_dim;

    wire signed [7:0] a_s  = a_rdata;
    wire signed [7:0] b0_s = b_row0;
    wire signed [7:0] b1_s = b_row1;
    wire signed [7:0] b2_s = b_row2;
    wire signed [7:0] b3_s = b_row3;

    wire signed [15:0] p0 = a_s * b0_s;
    wire signed [15:0] p1 = a_s * b1_s;
    wire signed [15:0] p2 = a_s * b2_s;
    wire signed [15:0] p3 = a_s * b3_s;

    wire k_last = (k == k_dim - 1);

    // pick the accumulator for the current writeback column
    reg signed [31:0] wb_val;
    always @(*) begin
        case (wb_col)
            3'd0:    wb_val = acc0;
            3'd1:    wb_val = acc1;
            3'd2:    wb_val = acc2;
            default: wb_val = acc3;
        endcase
    end

    always @(posedge clk) begin
        if (reset) begin
            phase <= P_IDLE;
            i <= 0; k <= 0; wb_col <= 0;
            acc0 <= 0; acc1 <= 0; acc2 <= 0; acc3 <= 0;
            c_clear <= 0; c_we <= 0; c_waddr <= 0; c_wdata <= 0;
            mac_done <= 0;
        end
        else begin
            c_clear <= 0; c_we <= 0; mac_done <= 0;

            case (phase)
                P_IDLE: begin
                    if (mac_en) begin
                        c_clear <= 1'b1;
                        i <= 0; k <= 0;
                        acc0<=0; acc1<=0; acc2<=0; acc3<=0;
                        phase <= P_CLEAR;
                    end
                end

                P_CLEAR: begin
                    phase <= P_ITER;
                end

                P_ITER: begin
                    // accumulate this k into all four columns
                    acc0 <= acc0 + $signed(p0);
                    acc1 <= acc1 + $signed(p1);
                    acc2 <= acc2 + $signed(p2);
                    acc3 <= acc3 + $signed(p3);

                    if (k_last) begin
                        // row i complete -> writeback
                        wb_col <= 0;
                        phase  <= P_WB;
                    end else begin
                        k <= k + 1;
                    end
                end

                P_WB: begin
                    // write C[i][wb_col] = acc(wb_col), for wb_col 0..N-1
                    c_we    <= 1'b1;
                    c_waddr <= i*n_dim + wb_col;
                    c_wdata <= wb_val;

                    if (wb_col == n_dim - 1) begin
                        // row done; reset accs, advance i
                        acc0<=0; acc1<=0; acc2<=0; acc3<=0;
                        k <= 0;
                        if (i == m_dim - 1) begin
                            phase <= P_FIN;
                        end else begin
                            i <= i + 1;
                            phase <= P_ITER;
                        end
                    end else begin
                        wb_col <= wb_col + 1;
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
