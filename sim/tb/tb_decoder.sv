`timescale 1ns / 1ps
`include "define.vh"

// =======================================================
// tb_decoder : simple_cpu decoder unit smoke test (self-checking)
//   build/run via run_all.py, or by hand:
//     $ verilator --binary --timing -Wall -Wno-fatal \
//       -Irtl_v2/simple_cpu --Mdir sim/build/tb_decoder \
//       sim/tb/tb_decoder.sv rtl_v2/simple_cpu/decoder.v --top-module tb_decoder
//     ./sim/build/tb_decoder/Vtb_decoder
// =======================================================
module tb_decoder;

    reg  [31:0] instruction;
    wire is_load, is_store, is_alu_mem, is_alu_imm, is_ext_imm;
    wire is_jump, is_in, is_out;
    wire [2:0]  alu_ctrl;
    wire        zero_we;
    wire [1:0]  jump_type;
    wire [27:0] imm;
    wire [11:0] addr;
    wire [3:0]  port;

    integer errors = 0;

    decoder dut (
        .instruction(instruction),
        .is_load(is_load), .is_store(is_store),
        .is_alu_mem(is_alu_mem), .is_alu_imm(is_alu_imm),
        .is_ext_imm(is_ext_imm), .is_jump(is_jump),
        .is_in(is_in), .is_out(is_out),
        .alu_ctrl(alu_ctrl), .zero_we(zero_we), .jump_type(jump_type),
        .imm(imm), .addr(addr), .port(port)
    );

    // exp_class = {load, store, alu_mem, alu_imm, ext_imm, jump, in, out}
    task check(input [31:0] inst, input [7:0] exp_class,
               input [2:0] exp_ctrl, input exp_zero_we, input [1:0] exp_jt);
        begin
            instruction = inst;
            #1;
            if ({is_load, is_store, is_alu_mem, is_alu_imm,
                 is_ext_imm, is_jump, is_in, is_out} !== exp_class ||
                alu_ctrl !== exp_ctrl || zero_we !== exp_zero_we ||
                jump_type !== exp_jt) begin
                errors = errors + 1;
                $display("[FAIL] inst=%08h class=%b ctrl=%0d zwe=%b jt=%0d (expected %b/%0d/%b/%0d)",
                         inst, {is_load, is_store, is_alu_mem, is_alu_imm,
                                is_ext_imm, is_jump, is_in, is_out},
                         alu_ctrl, zero_we, jump_type,
                         exp_class, exp_ctrl, exp_zero_we, exp_jt);
            end
        end
    endtask

    initial begin
        //                                          l_s_am_ai_ei_j_i_o
        check({`OP_LOAD,  28'h0000123}, 8'b10000000, `ALU_PASS, 1'b0, `JMP_UNCOND);
        check({`OP_STORE, 28'h0000123}, 8'b01000000, `ALU_PASS, 1'b0, `JMP_UNCOND);
        check({`OP_ADD,   28'h0000123}, 8'b00100000, `ALU_ADD,  1'b1, `JMP_UNCOND);
        check({`OP_SUB,   28'h0000123}, 8'b00100000, `ALU_SUB,  1'b1, `JMP_UNCOND);
        check({`OP_CMP,   28'h0000123}, 8'b00100000, `ALU_CMP,  1'b1, `JMP_UNCOND);
        check({`OP_LOADI, 28'h1234567}, 8'b00010000, `ALU_PASS, 1'b0, `JMP_UNCOND);
        check({`OP_ADDI,  28'h1234567}, 8'b00010000, `ALU_ADD,  1'b1, `JMP_UNCOND);
        check({`OP_CMPI,  28'h1234567}, 8'b00010000, `ALU_CMP,  1'b1, `JMP_UNCOND);
        check({`OP_JMP,   28'h0000042}, 8'b00000100, `ALU_PASS, 1'b0, `JMP_UNCOND);
        check({`OP_JZ,    28'h0000042}, 8'b00000100, `ALU_PASS, 1'b0, `JMP_JZ);
        check({`OP_JNZ,   28'h0000042}, 8'b00000100, `ALU_PASS, 1'b0, `JMP_JNZ);
        check({`OP_OUT,   28'h0000005}, 8'b00000001, `ALU_PASS, 1'b0, `JMP_UNCOND);
        check({`OP_IN,    28'h0000005}, 8'b00000010, `ALU_PASS, 1'b0, `JMP_UNCOND);
        // EXT: SHL/SHR are imm-shift class, AND is memory-operand class
        check({`OP_EXT, `EXT_SHL, 24'h000004}, 8'b00001000, `ALU_SHL, 1'b1, `JMP_UNCOND);
        check({`OP_EXT, `EXT_SHR, 24'h000004}, 8'b00001000, `ALU_SHR, 1'b1, `JMP_UNCOND);
        check({`OP_EXT, `EXT_AND, 24'h000123}, 8'b00100000, `ALU_AND, 1'b1, `JMP_UNCOND);
        // NOP / reserved / unknown EXT funct: everything deasserted
        check({`OP_NOP,   28'h0000000}, 8'b00000000, `ALU_PASS, 1'b0, `JMP_UNCOND);
        check({`OP_RESV1, 28'h0000000}, 8'b00000000, `ALU_PASS, 1'b0, `JMP_UNCOND);
        check({`OP_EXT,   4'b1111, 24'h0}, 8'b00000000, `ALU_PASS, 1'b0, `JMP_UNCOND);

        // operand extraction is a plain slice of the last instruction
        instruction = {`OP_LOAD, 28'hABCDEF5};
        #1;
        if (imm !== 28'hABCDEF5 || addr !== 12'hEF5 || port !== 4'h5) begin
            errors = errors + 1;
            $display("[FAIL] operand slice: imm=%07h addr=%03h port=%01h", imm, addr, port);
        end

        if (errors != 0)
            $fatal(1, "tb_decoder: %0d case(s) FAILED", errors);
        $display("tb_decoder: ALL PASS");
        $finish;
    end

endmodule
