`timescale 1ns / 1ps

module accumulator (
    input wire clk,
    input wire reset,         // 동기 리셋
    input wire acc_we,        // ACC 쓰기 활성화 (Decoder/FSM에서 생성)
    input wire [31:0] acc_in, // ALU 출력, BRAM 데이터 등 여러 소스에서 MUX를 거쳐 들어온 값
    output reg [31:0] acc_out // 현재 ACC 저장값 (ALU 입력, BRAM 쓰기 데이터 등으로 연결됨)
);

    always @(posedge clk) begin
        if (reset) begin
            acc_out <= 32'd0;
        end else if (acc_we) begin
            acc_out <= acc_in;
        end
    end

endmodule