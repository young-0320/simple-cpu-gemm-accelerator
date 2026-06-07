`timescale 1ns / 1ps
`include "gemm_define.vh"

// =======================================================
// gemm_mac_datapath  (1-MAC serial baseline, accumulator-register form)
//   For each output element C[i][j]:
//       acc = 0
//       for k in 0..K-1:  acc += A[i*K+k] * B[k*N+j]   (1 product/cycle)
//       c_buf[i*N+j] = acc                              (single write)
//   Accumulation lives in an internal register, so there is no
//   read-after-write hazard against the buffer. c_buf is written once
//   per output element. Total product cycles still = M*N*K.
// =======================================================
module gemm_mac_datapath (
    input  wire        clk,
    input  wire        reset,

    input  wire        mac_en,
    input  wire [2:0]  m_dim,
    input  wire [2:0]  n_dim,
    input  wire [2:0]  k_dim,

    output wire [3:0]  a_raddr,
    input  wire [7:0]  a_rdata,
    output wire [3:0]  b_raddr,
    input  wire [7:0]  b_rdata,

    output reg         c_clear,
    output reg         c_we,
    output reg  [3:0]  c_waddr,
    output reg  [31:0] c_wdata,
    output wire [3:0]  c_raddr,
    input  wire [31:0] c_rdata,

    output reg         mac_done
);

    localparam P_IDLE  = 2'd0,
               P_CLEAR = 2'd1,
               P_ITER  = 2'd2,
               P_FIN   = 2'd3;

    reg [1:0]  phase;
    reg [2:0]  i, j, k;
    reg signed [31:0] acc;

    wire [3:0] a_idx = i*k_dim + k;
    wire [3:0] b_idx = k*n_dim + j;
    assign a_raddr = a_idx;
    assign b_raddr = b_idx;
    assign c_raddr = 4'd0;

    wire signed [7:0]  a_s = a_rdata;
    wire signed [7:0]  b_s = b_rdata;
    wire signed [15:0] prod = a_s * b_s;

    // prod는 int8 곱의 int16 결과이고, 누산기는 int32이다.
    // 부호 확장을 명시해 Verilator WIDTHEXPAND 경고와 해석 여지를 없앤다.
    wire signed [31:0] prod_acc = {{16{prod[15]}}, prod};
    // 1-MAC 누산기 구조에서는 C buffer read data를 사용하지 않는다.
    // unused_* 더미 소비로 의도적 미사용임을 Verilator에 명시한다.
    wire unused_c_rdata = &c_rdata;

    wire k_last = (k == k_dim - 1);
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
            c_clear  <= 0;
            c_we     <= 0;
            mac_done <= 0;

            case (phase)
                P_IDLE: begin
                    if (mac_en) begin
                        c_clear <= 1'b1;
                        i <= 0; j <= 0; k <= 0;
                        acc <= 0;
                        phase <= P_CLEAR;
                    end
                end

                P_CLEAR: begin
                    phase <= P_ITER;
                end

                P_ITER: begin
                    acc <= acc + prod_acc;

                    if (k_last) begin
                        c_we    <= 1'b1;
                        c_waddr <= i*n_dim + j;
                        c_wdata <= acc + prod_acc;

                        acc <= 0;
                        k   <= 0;
                        if (j_last) begin
                            j <= 0;
                            if (i_last) begin
                                phase <= P_FIN;
                            end else begin
                                i <= i + 1;
                            end
                        end else begin
                            j <= j + 1;
                        end
                    end
                    else begin
                        k <= k + 1;
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
