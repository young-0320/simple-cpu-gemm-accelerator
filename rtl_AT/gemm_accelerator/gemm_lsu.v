`timescale 1ns / 1ps

module gemm_lsu (
    input  wire [31:0] gemm_a_base, gemm_b_base, gemm_c_base,
    input  wire [31:0] gemm_m, gemm_n, gemm_k,
    
    input  wire        lsu_load_w_en, lsu_load_b_en, store_en,
    input  wire [31:0] cnt_m, cnt_n, cnt_k,
    input  wire [1:0]  load_sub_cnt,

    output reg  [31:0] bram_addr_a, bram_addr_b,
    output reg         bram_wen,
    output wire [31:0] bram_wdata,
    input  wire [31:0] bram_rdata_a, bram_rdata_b,

    output wire [31:0] w_data_out,      
    output reg  [7:0]  b_byte_out,
    output reg  [3:0]  b_buf_byte_en,
    input  wire [31:0] c_buf_data
);

    // 핵심: K와 N 차원의 길이를 무조건 4의 배수(Word 단위)로 올림(Ceiling) 처리
    // 예: K=3이면 1 Word 할당, K=5면 2 Word 할당
    wire [31:0] k_words = (gemm_k + 3) >> 2;
    wire [31:0] n_words = (gemm_n + 3) >> 2;

    // 1. 패딩이 적용된 행렬 A 주소 해석기
    // cnt_k는 무조건 0, 4, 8로 뛰므로, 행 오프셋만 정확히 맞추면 항상 Lane 0부터 시작합니다!
    wire [31:0] a_word_offset = (cnt_m * k_words) + (cnt_k >> 2);
    wire [31:0] addr_a = gemm_a_base + (a_word_offset << 2);

    // 2. 패딩이 적용된 행렬 B 주소 및 레인 해체기
    wire [31:0] k_row         = cnt_k + load_sub_cnt;
    wire [31:0] b_word_offset = (k_row * n_words) + (cnt_n >> 2);
    wire [1:0]  b_lane        = cnt_n[1:0]; // N열에 대한 레인 추출은 유지
    wire [31:0] addr_b = gemm_b_base + b_word_offset;

    // 3. 행렬 C 주소 연산기
    wire [31:0] addr_c = gemm_c_base + (((cnt_m * gemm_n) + cnt_n) << 2);

    always @(*) begin
        bram_addr_a   = 32'd0;
        bram_addr_b   = 32'd0;
        bram_wen      = 1'b0;
        b_buf_byte_en = 4'b0000;

        if (store_en) begin
            bram_addr_a = addr_c;
            bram_wen    = 1'b1;
        end else begin
            bram_addr_a = addr_a;
            bram_addr_b = addr_b;
            
            // [수정] FSM이 LOAD_WAIT 상태(데이터 유효 시점)일 때만 Byte Enable 켬
            if (lsu_load_b_en && (k_row < gemm_k)) begin
                b_buf_byte_en[load_sub_cnt] = 1'b1;
            end
        end
    end

    assign bram_wdata = c_buf_data;
    
    assign w_data_out = bram_rdata_a;

    always @(*) begin
        case (b_lane)
            2'd0: b_byte_out = bram_rdata_b[7:0];
            2'd1: b_byte_out = bram_rdata_b[15:8];
            2'd2: b_byte_out = bram_rdata_b[23:16];
            2'd3: b_byte_out = bram_rdata_b[31:24];
        endcase
    end

endmodule