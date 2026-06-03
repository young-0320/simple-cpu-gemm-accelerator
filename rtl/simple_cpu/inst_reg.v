`timescale 1ns / 1ps

module inst_reg (
    input  wire        clk,
    input  wire        reset,    // 동기 리셋
    input  wire        ir_we,    // 명령어 레지스터 쓰기 활성화 (FSM/Decoder 제어)
    input  wire [31:0] instr_in, // BRAM에서 읽어온 32비트 명령어 데이터
    output reg  [31:0] instr_out // 저장된 명령어 (Decoder로 전달됨)
);

    // 철저한 동기식 리셋을 적용한 32비트 레지스터 로직
    always @(posedge clk) begin
        if (reset) begin
            // 리셋 시 초기화
            instr_out <= 32'hB0000000; 
        end
        else if (ir_we) begin
            instr_out <= instr_in;
        end
    end

endmodule