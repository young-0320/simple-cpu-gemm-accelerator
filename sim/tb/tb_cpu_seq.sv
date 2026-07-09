`timescale 1ns / 1ps
`include "define.vh"

// =======================================================
// tb_cpu_seq : simple_cpu sequential-module unit smoke test
//   covers pc / inst_reg / accumulator / cpu_fsm in one TB
//   (all four are small clocked registers/counters that share
//   the same reset + enable/hold behaviour).
//   build/run via run_all.py, or by hand:
//     $ verilator --binary --timing -Wall -Wno-fatal \
//       -Irtl_v2/simple_cpu --Mdir sim/build/tb_cpu_seq \
//       sim/tb/tb_cpu_seq.sv rtl_v2/simple_cpu/pc.v \
//       rtl_v2/simple_cpu/inst_reg.v rtl_v2/simple_cpu/accumulator.v \
//       rtl_v2/simple_cpu/cpu_fsm.v --top-module tb_cpu_seq
//     ./sim/build/tb_cpu_seq/Vtb_cpu_seq
// =======================================================
module tb_cpu_seq;

    reg clk = 1'b0;
    always #5 clk <= ~clk;

    reg reset = 1'b1;

    integer errors = 0;

    task check(input [31:0] got, input [31:0] exp, input string what);
        begin
            if (got !== exp) begin
                errors = errors + 1;
                $display("[FAIL] %0s: got %08h, expected %08h", what, got, exp);
            end
        end
    endtask

    // ---- DUTs -------------------------------------------------
    reg         pc_ce = 1'b1, pc_write = 1'b0;
    reg  [11:0] pc_next = 12'd0;
    wire [11:0] pc_out;
    pc u_pc (.clk(clk), .reset(reset), .clk_enable(pc_ce),
             .pc_write(pc_write), .pc_next(pc_next), .pc_out(pc_out));

    reg         ir_we = 1'b0;
    reg  [31:0] instr_in = 32'd0;
    wire [31:0] instr_out;
    inst_reg u_ir (.clk(clk), .reset(reset), .ir_we(ir_we),
                   .instr_in(instr_in), .instr_out(instr_out));

    reg         acc_we = 1'b0;
    reg  [31:0] acc_in = 32'd0;
    wire [31:0] acc_out;
    accumulator u_acc (.clk(clk), .reset(reset), .acc_we(acc_we),
                       .acc_in(acc_in), .acc_out(acc_out));

    reg         fsm_ce = 1'b1;
    wire [1:0]  fsm_state;
    cpu_fsm u_fsm (.clk(clk), .reset(reset), .clk_enable(fsm_ce),
                   .state(fsm_state));

    // ---- test sequence ---------------------------------------
    initial begin
        // sync reset for 2 cycles
        @(posedge clk); @(posedge clk); #1;
        check({20'd0, pc_out}, 32'd0,          "pc reset value");
        check(instr_out, 32'hB000_0000,        "inst_reg reset value (NOP)");
        check(acc_out,   32'd0,                "accumulator reset value");
        check({30'd0, fsm_state}, {30'd0, `ST_FETCH}, "cpu_fsm reset state");
        reset = 1'b0;

        // pc: write when enabled, hold when pc_write=0, freeze when clk_enable=0
        pc_write = 1'b1; pc_next = 12'h123;
        @(posedge clk); #1; check({20'd0, pc_out}, 32'h123, "pc write");
        pc_write = 1'b0; pc_next = 12'hFFF;
        @(posedge clk); #1; check({20'd0, pc_out}, 32'h123, "pc hold (pc_write=0)");
        pc_write = 1'b1; pc_ce = 1'b0;
        @(posedge clk); #1; check({20'd0, pc_out}, 32'h123, "pc freeze (clk_enable=0)");
        pc_ce = 1'b1;
        @(posedge clk); #1; check({20'd0, pc_out}, 32'hFFF, "pc resumes after freeze");

        // inst_reg: write / hold
        ir_we = 1'b1; instr_in = 32'hDEAD_BEEF;
        @(posedge clk); #1; check(instr_out, 32'hDEAD_BEEF, "inst_reg write");
        ir_we = 1'b0; instr_in = 32'h1234_5678;
        @(posedge clk); #1; check(instr_out, 32'hDEAD_BEEF, "inst_reg hold (ir_we=0)");

        // accumulator: write / hold
        acc_we = 1'b1; acc_in = 32'hCAFE_0001;
        @(posedge clk); #1; check(acc_out, 32'hCAFE_0001, "accumulator write");
        acc_we = 1'b0; acc_in = 32'd0;
        @(posedge clk); #1; check(acc_out, 32'hCAFE_0001, "accumulator hold (acc_we=0)");

        // cpu_fsm: FETCH -> DECODE -> EXECUTE -> INCREMENT -> FETCH,
        // and freeze in place while clk_enable=0 (GEMM freeze protocol)
        @(posedge clk); #1; // fsm has been free-running; just follow from here
        begin : fsm_walk
            reg [1:0] s;
            s = fsm_state;
            @(posedge clk); #1;
            check({30'd0, fsm_state}, {30'd0, s + 2'd1}, "cpu_fsm advances (+1 mod 4)");
            fsm_ce = 1'b0; s = fsm_state;
            @(posedge clk); @(posedge clk); #1;
            check({30'd0, fsm_state}, {30'd0, s}, "cpu_fsm freeze (clk_enable=0)");
            fsm_ce = 1'b1;
            @(posedge clk); #1;
            check({30'd0, fsm_state}, {30'd0, s + 2'd1}, "cpu_fsm resumes after freeze");
        end
        // full 4-state loop returns to the same state
        begin : fsm_loop
            reg [1:0] s;
            s = fsm_state;
            repeat (4) @(posedge clk); #1;
            check({30'd0, fsm_state}, {30'd0, s}, "cpu_fsm 4-cycle loop");
        end

        if (errors != 0)
            $fatal(1, "tb_cpu_seq: %0d case(s) FAILED", errors);
        $display("tb_cpu_seq: ALL PASS");
        $finish;
    end

endmodule
