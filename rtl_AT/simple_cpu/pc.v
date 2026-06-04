`timescale 1ns / 1ps

module pc (
    input  wire        clk,
    input  wire        reset,
    input  wire        clk_enable,

    input  wire        pc_write,     // PC 갱신 허용 신호
    input  wire [11:0] pc_next,      // 다음 PC 값

    output reg  [11:0] pc_out        // 현재 PC 값
);

    always @(posedge clk) begin
        if (reset) begin
            pc_out <= 12'd0;
        end
        else if (clk_enable && pc_write) begin
            pc_out <= pc_next;
        end
    end

endmodule