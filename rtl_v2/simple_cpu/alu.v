`timescale 1ns / 1ps
`include "define.vh"

module alu (
    input  wire [31:0] acc_in,
    input  wire [31:0] operand_in,
    input  wire [2:0]  alu_ctrl,

    output reg  [31:0] alu_result,
    output reg         zero_result
);

    always @(*) begin
        alu_result  = acc_in;
        zero_result = 1'b0;

        case (alu_ctrl)
            `ALU_ADD: begin
                alu_result  = acc_in + operand_in;
                zero_result = (alu_result == 32'd0);
            end

            `ALU_SUB: begin
                alu_result  = acc_in - operand_in;
                zero_result = (alu_result == 32'd0);
            end

            `ALU_CMP: begin
                alu_result  = acc_in;
                zero_result = (acc_in == operand_in);
            end

            `ALU_PASS: begin
                alu_result  = operand_in;
                zero_result = (operand_in == 32'd0);
            end

            `ALU_SHL: begin
                alu_result  = acc_in << operand_in[4:0];
                zero_result = (alu_result == 32'd0);
            end

            `ALU_SHR: begin
                alu_result  = acc_in >> operand_in[4:0];
                zero_result = (alu_result == 32'd0);
            end

            `ALU_AND: begin
                alu_result  = acc_in & operand_in;
                zero_result = (alu_result == 32'd0);
            end

            default: begin
                alu_result  = acc_in;
                zero_result = 1'b0;
            end
        endcase
    end

endmodule