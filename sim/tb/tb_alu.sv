`timescale 1ns / 1ps
`include "define.vh"

// =======================================================
// tb_alu : simple_cpu ALU unit smoke test (self-checking)
//   build/run via run_all.py, or by hand:
//     $ verilator --binary --timing -Wall -Wno-fatal \
//       -Irtl_v2/simple_cpu --Mdir sim/build/tb_alu \
//       sim/tb/tb_alu.sv rtl_v2/simple_cpu/alu.v --top-module tb_alu
//     ./sim/build/tb_alu/Vtb_alu
// =======================================================
module tb_alu;

    reg  [31:0] acc_in;
    reg  [31:0] operand_in;
    reg  [2:0]  alu_ctrl;
    wire [31:0] alu_result;
    wire        zero_result;

    integer errors = 0;

    alu dut (
        .acc_in(acc_in), .operand_in(operand_in), .alu_ctrl(alu_ctrl),
        .alu_result(alu_result), .zero_result(zero_result)
    );

    task check(input [2:0] ctrl, input [31:0] a, input [31:0] b,
               input [31:0] exp_result, input exp_zero);
        begin
            alu_ctrl = ctrl; acc_in = a; operand_in = b;
            #1;
            if (alu_result !== exp_result || zero_result !== exp_zero) begin
                errors = errors + 1;
                $display("[FAIL] ctrl=%0d acc=%0d op=%0d -> result=%0d zero=%b (expected %0d/%b)",
                         ctrl, a, b, alu_result, zero_result, exp_result, exp_zero);
            end
        end
    endtask

    initial begin
        // ADD: plain, wrap-around to zero
        check(`ALU_ADD, 32'd3,          32'd4,          32'd7,          1'b0);
        check(`ALU_ADD, 32'hFFFF_FFFF,  32'd1,          32'd0,          1'b1);
        // SUB: plain, down to zero
        check(`ALU_SUB, 32'd10,         32'd3,          32'd7,          1'b0);
        check(`ALU_SUB, 32'd5,          32'd5,          32'd0,          1'b1);
        // CMP: result passes acc through, zero = (acc == operand)
        check(`ALU_CMP, 32'd9,          32'd9,          32'd9,          1'b1);
        check(`ALU_CMP, 32'd9,          32'd8,          32'd9,          1'b0);
        // PASS: result = operand, zero = (operand == 0)
        check(`ALU_PASS, 32'd123,       32'd0,          32'd0,          1'b1);
        check(`ALU_PASS, 32'd123,       32'd55,         32'd55,         1'b0);
        // SHL/SHR: shift amount is operand[4:0]
        check(`ALU_SHL, 32'h0000_00F0,  32'd4,          32'h0000_0F00,  1'b0);
        check(`ALU_SHL, 32'h8000_0000,  32'd1,          32'd0,          1'b1);
        check(`ALU_SHR, 32'h0000_00F0,  32'd4,          32'h0000_000F,  1'b0);
        check(`ALU_SHR, 32'd1,          32'd1,          32'd0,          1'b1);
        // shift amount uses only [4:0]: 33 -> 1
        check(`ALU_SHL, 32'd1,          32'd33,         32'd2,          1'b0);
        // AND: plain, to zero
        check(`ALU_AND, 32'h0F0F_0F0F,  32'h00FF_00FF,  32'h000F_000F,  1'b0);
        check(`ALU_AND, 32'hAAAA_AAAA,  32'h5555_5555,  32'd0,          1'b1);
        // undefined ctrl (7): acc passthrough, zero stays 0
        check(3'd7,     32'd42,         32'd0,          32'd42,         1'b0);

        if (errors != 0)
            $fatal(1, "tb_alu: %0d case(s) FAILED", errors);
        $display("tb_alu: ALL PASS");
        $finish;
    end

endmodule
