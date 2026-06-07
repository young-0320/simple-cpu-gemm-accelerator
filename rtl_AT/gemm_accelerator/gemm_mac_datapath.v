`timescale 1ns / 1ps

module gemm_mac_datapath (
    input  wire [31:0] gemm_k,     // 스펙 문서 명칭 반영
    input  wire [31:0] cnt_k,
    
    // 로컬 버퍼로부터 입력받는 Packed 데이터
    input  wire [31:0] a_buf,      // A[i][k..k+3] 4개 원소
    input  wire [31:0] b_buf,      // B[k..k+3][j] 수집 완료된 4개 원소
    input  wire [31:0] c_buf,      // 기존 signed int32 누산 값
    
    // 업데이트된 누산 결과
    output wire [31:0] c_out
);

    // Signed int8 형식으로 언팩
    wire signed [7:0] a_val0 = a_buf[7:0];
    wire signed [7:0] a_val1 = a_buf[15:8];
    wire signed [7:0] a_val2 = a_buf[23:16];
    wire signed [7:0] a_val3 = a_buf[31:24];

    wire signed [7:0] b_val0 = b_buf[7:0];
    wire signed [7:0] b_val1 = b_buf[15:8];
    wire signed [7:0] b_val2 = b_buf[23:16];
    wire signed [7:0] b_val3 = b_buf[31:24];

    // 1단계: 병렬 곱셈 (Product type: signed int16)
    wire signed [15:0] prod0 = a_val0 * b_val0;
    wire signed [15:0] prod1 = a_val1 * b_val1;
    wire signed [15:0] prod2 = a_val2 * b_val2;
    wire signed [15:0] prod3 = a_val3 * b_val3;

    // 유효 차원 마스킹 조건 (K가 4보다 작을 때 유효한 레인만 덧셈에 참여시킴)
    wire msk0 = (cnt_k + 0 < gemm_k);
    wire msk1 = (cnt_k + 1 < gemm_k);
    wire msk2 = (cnt_k + 2 < gemm_k);
    wire msk3 = (cnt_k + 3 < gemm_k);

    wire signed [15:0] msk_prod0 = msk0 ? prod0 : 16'sd0;
    wire signed [15:0] msk_prod1 = msk1 ? prod1 : 16'sd0;
    wire signed [15:0] msk_prod2 = msk2 ? prod2 : 16'sd0;
    wire signed [15:0] msk_prod3 = msk3 ? prod3 : 16'sd0;

    // 2단계: 가산기 트리 (Adder Tree) 연산
    wire signed [16:0] sum_stage1_0 = msk_prod0 + msk_prod1;
    wire signed [16:0] sum_stage1_1 = msk_prod2 + msk_prod3;
    // 17비트 중간합을 int32 누산 경로로 더하므로 부호 확장을 명시한다.
    wire signed [31:0] sum_stage1_0_acc = {{15{sum_stage1_0[16]}}, sum_stage1_0};
    wire signed [31:0] sum_stage1_1_acc = {{15{sum_stage1_1[16]}}, sum_stage1_1};
    wire signed [31:0] tree_sum         = sum_stage1_0_acc + sum_stage1_1_acc;

    // 3단계: 기존 c_buf 결과와 누산 (Accumulator type: signed int32)
    assign c_out = c_buf + tree_sum;

endmodule
