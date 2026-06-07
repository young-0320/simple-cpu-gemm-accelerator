`timescale 1ns / 1ps
`include "define.vh"

module top_cpu (
    input  wire        clk,
    input  wire        reset,
    input  wire        clk_enable,

    // BRAM interface
    input  wire [31:0] bram_rdata,
    output reg  [11:0] bram_addr,
    output wire [31:0] bram_wdata,
    output reg         bram_we,

    // input port
    input  wire [8:0]  in_port,

    // output port
    output reg  [3:0]  out_port,

    // debug
    output wire [11:0] pc_debug,
    output wire [31:0] acc_debug,
    output wire        zero_flag_debug,
    output wire [1:0]  state_debug
);

    // =======================================================
    // Internal signals
    // =======================================================

    wire [1:0]  state;

    wire [11:0] pc_out;
    reg  [11:0] pc_next;
    wire        pc_write;

    wire [31:0] instr_out;
    wire        ir_we;

    wire [31:0] acc_out;
    reg  [31:0] acc_in;
    reg         acc_we;

    reg         zero_flag;

    wire        is_load;
    wire        is_store;
    wire        is_alu_mem;
    wire        is_alu_imm;
    wire        is_ext_imm;
    wire        is_jump;
    wire        is_in;
    wire        is_out;

    wire [2:0]  alu_ctrl;
    wire        zero_we;
    wire [1:0]  jump_type;

    wire [27:0] imm;
    wire [11:0] addr;
    wire [3:0]  port;

    wire [31:0] alu_operand;
    wire [31:0] alu_result;
    wire        alu_zero_result;

    reg  [31:0] selected_input;

    // =======================================================
    // FSM
    // =======================================================

    cpu_fsm u_cpu_fsm (
        .clk        (clk),
        .reset      (reset),
        .clk_enable (clk_enable),
        .state      (state)
    );

    // =======================================================
    // PC
    // =======================================================

    assign pc_write = (state == `ST_INCREMENT);

    pc u_pc (
        .clk        (clk),
        .reset      (reset),
        .clk_enable (clk_enable),
        .pc_write   (pc_write),
        .pc_next    (pc_next),
        .pc_out     (pc_out)
    );

    // =======================================================
    // Instruction Register
    // =======================================================

    assign ir_we = clk_enable && (state == `ST_DECODE);

    inst_reg u_inst_reg (
        .clk       (clk),
        .reset     (reset),
        .ir_we     (ir_we),
        .instr_in  (bram_rdata),
        .instr_out (instr_out)
    );

    // =======================================================
    // Decoder
    // =======================================================

    decoder u_decoder (
        .instruction (instr_out),

        .is_load     (is_load),
        .is_store    (is_store),
        .is_alu_mem  (is_alu_mem),
        .is_alu_imm  (is_alu_imm),
        .is_ext_imm  (is_ext_imm),
        .is_jump     (is_jump),
        .is_in       (is_in),
        .is_out      (is_out),

        .alu_ctrl    (alu_ctrl),
        .zero_we     (zero_we),

        .jump_type   (jump_type),

        .imm         (imm),
        .addr        (addr),
        .port        (port)
    );

    // =======================================================
    // Accumulator
    // =======================================================

    accumulator u_accumulator (
        .clk     (clk),
        .reset   (reset),
        .acc_we  (acc_we),
        .acc_in  (acc_in),
        .acc_out (acc_out)
    );

    // =======================================================
    // ALU
    // =======================================================

    assign alu_operand = is_alu_imm ? {4'b0000, imm}  :
                         is_ext_imm ? {20'b0, addr}    :
                                      bram_rdata;

    alu u_alu (
        .acc_in      (acc_out),
        .operand_in  (alu_operand),
        .alu_ctrl    (alu_ctrl),
        .alu_result  (alu_result),
        .zero_result (alu_zero_result)
    );

    // =======================================================
    // BRAM write data
    // =======================================================

    assign bram_wdata = acc_out;

    // =======================================================
    // BRAM address / write enable control
    // =======================================================

    always @(*) begin
        bram_addr = pc_out;
        bram_we   = 1'b0;

        case (state)
            `ST_FETCH: begin
                bram_addr = pc_out;
                bram_we   = 1'b0;
            end

            `ST_EXECUTE: begin
                if (is_load || is_store || is_alu_mem) begin
                    bram_addr = addr;
                end
                else begin
                    bram_addr = pc_out;
                end

                if (is_store) begin
                    bram_we = clk_enable;
                end
                else begin
                    bram_we = 1'b0;
                end
            end

            default: begin
                bram_addr = pc_out;
                bram_we   = 1'b0;
            end
        endcase
    end

    // =======================================================
    // IN port select
    // =======================================================

    always @(*) begin
        selected_input = 32'd0;

        case (port)
            `IN_PORT_NUM:     selected_input = {28'd0, in_port[3:0]};
            `IN_PORT_BTN_IN:  selected_input = {31'd0, in_port[4]};
            `IN_PORT_BTN_CFM: selected_input = {31'd0, in_port[5]};
            `IN_PORT_BTN_CAN: selected_input = {31'd0, in_port[6]};
            `IN_PORT_BTN_PW:  selected_input = {31'd0, in_port[7]};
            `IN_PORT_MST_KEY: selected_input = {31'd0, in_port[8]};
            default:          selected_input = 32'd0;
        endcase
    end

    // =======================================================
    // ACC input / ACC write enable
    // =======================================================

    always @(*) begin
        acc_in = acc_out;
        acc_we = 1'b0;

        if (clk_enable && (state == `ST_INCREMENT)) begin
            if (is_load) begin
                acc_in = bram_rdata;
                acc_we = 1'b1;
            end
            else if (is_in) begin
                acc_in = selected_input;
                acc_we = 1'b1;
            end
            else if (is_alu_imm || is_alu_mem || is_ext_imm) begin
                if (alu_ctrl != `ALU_CMP) begin
                    acc_in = alu_result;
                    acc_we = 1'b1;
                end
            end
        end
    end

    // =======================================================
    // ZERO_FLAG / OUT_PORT update
    // =======================================================

    always @(posedge clk) begin
        if (reset) begin
            zero_flag <= 1'b0;
            out_port  <= `OUT_STATE_CLOSED;
        end
        else if (clk_enable && (state == `ST_INCREMENT)) begin
            if (zero_we) begin
                zero_flag <= alu_zero_result;
            end

            if (is_out) begin
                out_port <= acc_out[3:0];
            end
        end
    end

    // =======================================================
    // PC next logic
    // =======================================================

    always @(*) begin
        pc_next = pc_out + 12'd1;

        if (is_jump) begin
            case (jump_type)
                `JMP_UNCOND: begin
                    pc_next = addr;
                end

                `JMP_JZ: begin
                    if (zero_flag) begin
                        pc_next = addr;
                    end
                    else begin
                        pc_next = pc_out + 12'd1;
                    end
                end

                `JMP_JNZ: begin
                    if (!zero_flag) begin
                        pc_next = addr;
                    end
                    else begin
                        pc_next = pc_out + 12'd1;
                    end
                end

                default: begin
                    pc_next = pc_out + 12'd1;
                end
            endcase
        end
    end

    // =======================================================
    // Debug outputs
    // =======================================================

    assign pc_debug        = pc_out;
    assign acc_debug       = acc_out;
    assign zero_flag_debug = zero_flag;
    assign state_debug     = state;

endmodule