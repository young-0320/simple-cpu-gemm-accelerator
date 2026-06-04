`timescale 1ns / 1ps

module gemm_local_buffer (
    input  wire        clk,
    input  wire        rst_n,

    // 적재 통제 제어 신호
    input  wire        load_w_en,       // A packed word 적재 활성화
    input  wire [31:0] w_data_in,       // BRAM에서 온 32-bit packed A
    
    input  wire [3:0]  b_buf_byte_en,   // 수집용 바이트 인에이블 신호 (LSU 통제)
    input  wire [7:0]  b_data_byte_in,  // 비전치 행렬 B에서 추출된 순수 1바이트 데이터
    
    input  wire        c_acc_en,        // COMPUTE 완료 시 누산값 갱신
    input  wire        c_clear,         // 새로운 C 원소 진입 시 0 초기화
    input  wire [31:0] c_data_in,       // Datapath의 누산 출력 결과

    // 시스템 출력 포트
    output reg  [31:0] a_buf,
    output reg  [31:0] b_buf,
    output reg  [31:0] c_buf
);

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            a_buf <= 32'd0;
            b_buf <= 32'd0;
            c_buf <= 32'd0;
        end else begin
            // A 행렬 Word 단위 통째 적재
            if (load_w_en) a_buf <= w_data_in;
            
            // B 행렬 순차적 바이트 결합 적재 (Gathering 기법)
            if (b_buf_byte_en[0]) b_buf[7:0]   <= b_data_byte_in;
            if (b_buf_byte_en[1]) b_buf[15:8]  <= b_data_byte_in;
            if (b_buf_byte_en[2]) b_buf[23:16] <= b_data_byte_in;
            if (b_buf_byte_en[3]) b_buf[31:24] <= b_data_byte_in;

            // C 행렬 누산기 제어
            if (c_clear) begin
                c_buf <= 32'd0;
            end else if (c_acc_en) begin
                c_buf <= c_data_in;
            end
        end
    end

endmodule