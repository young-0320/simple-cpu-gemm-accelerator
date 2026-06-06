`timescale 1ns / 1ps
`include "gemm_define.vh" 

module gemm_mmio_reg (
    input  wire        clk,
    input  wire        rst_n,

    // [수정됨] 글루 로직과 동일하게 3비트로 맞춤
    input  wire [2:0]  addr,      
    input  wire [31:0] wdata,     
    input  wire        wen,       
    input  wire        ren,       
    output reg  [31:0] rdata,     

    // ----------------------------------------------------
    // Output to Coprocessor (FSM & Datapath)
    // ----------------------------------------------------
    output reg  [31:0] gemm_a_base,
    output reg  [31:0] gemm_b_base,
    output reg  [31:0] gemm_c_base,
    output reg  [31:0] gemm_m,
    output reg  [31:0] gemm_n,
    output reg  [31:0] gemm_k,
    
    output wire        start_pulse, 
    output wire        clear_pulse, 
    
    // ----------------------------------------------------
    // Input from Coprocessor (Status)
    // ----------------------------------------------------
    input  wire        npu_busy,
    input  wire        npu_done,
    input  wire        npu_error
);

    reg status_busy;
    reg status_done;
    reg status_error;
    
    wire valid_m = (gemm_m >= `GEMM_DIM_MIN) && (gemm_m <= `GEMM_DIM_MAX);
    wire valid_n = (gemm_n >= `GEMM_DIM_MIN) && (gemm_n <= `GEMM_DIM_MAX);
    wire valid_k = (gemm_k >= `GEMM_DIM_MIN) && (gemm_k <= `GEMM_DIM_MAX);
    wire invalid_size = !(valid_m && valid_n && valid_k);

    // [수정됨] 8'h18 대신 3비트 매크로(`GEMM_OFF_CTRL) 사용
    assign start_pulse = (wen && (addr == `GEMM_OFF_CTRL) && wdata[`GEMM_CTRL_START_BIT]);
    assign clear_pulse = (wen && (addr == `GEMM_OFF_CTRL) && wdata[`GEMM_CTRL_CLEAR_DONE_BIT]);

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            gemm_a_base <= 32'd0;
            gemm_b_base <= 32'd0;
            gemm_c_base <= 32'd0;
            gemm_m      <= 32'd0;
            gemm_n      <= 32'd0;
            gemm_k      <= 32'd0;
        end else if (wen && wen) begin 
            // [수정됨] 8'h00 대신 3비트 매크로 사용
            case (addr)
                `GEMM_OFF_A_BASE: gemm_a_base <= wdata;
                `GEMM_OFF_B_BASE: gemm_b_base <= wdata;
                `GEMM_OFF_C_BASE: gemm_c_base <= wdata;
                `GEMM_OFF_M     : gemm_m      <= wdata;
                `GEMM_OFF_N     : gemm_n      <= wdata;
                `GEMM_OFF_K     : gemm_k      <= wdata;
                default: ; 
            endcase
        end
    end

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            status_busy  <= 1'b0;
            status_done  <= 1'b0;
            status_error <= 1'b0;
        end else begin
            if (start_pulse) begin
                if (invalid_size) begin
                    status_done  <= 1'b1;
                    status_error <= 1'b1;
                end else begin
                    status_busy  <= 1'b1;
                    status_done  <= 1'b0;
                    status_error <= 1'b0;
                end
            end 
            else if (npu_done || npu_error) begin
                status_busy  <= 1'b0;
                status_done  <= npu_done;
                status_error <= npu_error;
            end
            else if (clear_pulse) begin
                status_done  <= 1'b0;
                status_error <= 1'b0;
            end
        end
    end

    always @(*) begin
        rdata = 32'd0;
        if (ren) begin
            case (addr)
                `GEMM_OFF_A_BASE: rdata = gemm_a_base;
                `GEMM_OFF_B_BASE: rdata = gemm_b_base;
                `GEMM_OFF_C_BASE: rdata = gemm_c_base;
                `GEMM_OFF_M     : rdata = gemm_m;
                `GEMM_OFF_N     : rdata = gemm_n;
                `GEMM_OFF_K     : rdata = gemm_k;
                `GEMM_OFF_STATUS: begin
                    rdata[`GEMM_ST_BUSY_BIT]    = status_busy;
                    rdata[`GEMM_ST_DONE_BIT]    = status_done;
                    rdata[`GEMM_ST_ERROR_BIT]   = status_error;
                    rdata[`GEMM_ST_INVSIZE_BIT] = invalid_size;
                end
                default: rdata = 32'd0;
            endcase
        end
    end
endmodule