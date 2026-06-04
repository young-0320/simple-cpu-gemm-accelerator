//adder_tree + cpu + bram 1
`timescale 1ns / 1ps
`include "define.vh"
`include "gemm_define.vh"

module gemm_system_top #(
    parameter MAC_MODE = 4
) (
    input  wire        clk,
    input  wire        reset,

    input  wire [8:0]  in_port,
    output wire [3:0]  out_port,

    output wire [11:0] pc_debug,
    output wire [31:0] acc_debug,
    output wire        gemm_busy_debug,
    output wire [2:0]  gemm_state_debug
);
    // ---- CPU memory port ----
    wire [11:0] cpu_addr;
    wire [31:0] cpu_wdata;
    wire        cpu_we;
    wire [31:0] cpu_rdata;
    wire        cpu_run;          

    // ---- Glue <-> GEMM MMIO 연결선 ----
    wire [2:0]  gemm_cpu_addr;
    wire [31:0] gemm_cpu_wdata;
    wire        gemm_cpu_wen;
    wire        gemm_cpu_ren;
    wire [31:0] gemm_cpu_rdata;
    wire        gemm_busy;

    // ---- GEMM LSU <-> Glue 연결선 ----
    wire [31:0] gemm_bram_addr_a;
    wire        gemm_bram_wen_a;
    wire [31:0] gemm_bram_wdata_a;
    wire [31:0] gemm_bram_rdata_a;

    wire [31:0] gemm_bram_addr_b;
    wire [31:0] gemm_bram_rdata_b;

    // ---- Real Dual-Port BRAM 연결선 ----
    wire [31:0] real_bram_addr_a;
    wire        real_bram_wen_a;
    wire [31:0] real_bram_wdata_a;
    wire [31:0] real_bram_rdata_a;

    wire [31:0] real_bram_addr_b;
    wire        real_bram_wen_b;
    wire [31:0] real_bram_wdata_b;
    wire [31:0] real_bram_rdata_b;

    assign gemm_busy_debug = gemm_busy;

    // =======================================================
    // 1. CPU (수정 없음)
    // =======================================================
    reg cpu_run_r;
    always @(posedge clk) begin
        if (reset) cpu_run_r <= 1'b1;
        else       cpu_run_r <= cpu_run;
    end

    top_cpu u_cpu (
        .clk(clk), .reset(reset),
        .clk_enable(cpu_run_r),
        .bram_rdata(cpu_rdata),
        .bram_addr(cpu_addr),
        .bram_wdata(cpu_wdata),
        .bram_we(cpu_we),
        .in_port(in_port),
        .out_port(out_port),
        .pc_debug(pc_debug),
        .acc_debug(acc_debug),
        .zero_flag_debug(),
        .state_debug()
    );

    // =======================================================
    // 2. Glue Logic (최신 듀얼 포트 규격 반영)
    // =======================================================
    // 주의: 기존 top_cpu의 주소는 12비트이므로 시스템 주소 규격에 맞게 16비트로 확장 인가
    gemm_cpu_glue u_glue (
        .clk(clk),
        .rst_n(~reset),
        
        // CPU 측
        .cpu_addr({4'd0, cpu_addr}), 
        .cpu_wdata(cpu_wdata),
        .cpu_we(cpu_we),
        .cpu_re(1'b1),               // 단순화를 위해 상시 Read 활성화
        .cpu_rdata(cpu_rdata),
        .cpu_run(cpu_run),
        
        // 가속기 제어/상태 측
        .gemm_cpu_addr(gemm_cpu_addr),
        .gemm_cpu_wdata(gemm_cpu_wdata),
        .gemm_cpu_wen(gemm_cpu_wen),
        .gemm_cpu_ren(gemm_cpu_ren),
        .gemm_cpu_rdata(gemm_cpu_rdata),
        .gemm_busy(gemm_busy),
        
        // 가속기 LSU 측
        .gemm_bram_addr_a(gemm_bram_addr_a),
        .gemm_bram_wen_a(gemm_bram_wen_a),
        .gemm_bram_wdata_a(gemm_bram_wdata_a),
        .gemm_bram_rdata_a(gemm_bram_rdata_a),
        
        .gemm_bram_addr_b(gemm_bram_addr_b),
        .gemm_bram_rdata_b(gemm_bram_rdata_b),
        
        // 물리적 BRAM 측
        .real_bram_addr_a(real_bram_addr_a),
        .real_bram_wen_a(real_bram_wen_a),
        .real_bram_wdata_a(real_bram_wdata_a),
        .real_bram_rdata_a(real_bram_rdata_a),
        
        .real_bram_addr_b(real_bram_addr_b),
        .real_bram_wen_b(real_bram_wen_b),
        .real_bram_wdata_b(real_bram_wdata_b),
        .real_bram_rdata_b(real_bram_rdata_b)
    );

    // =======================================================
    // 3. GEMM Accelerator Top (최신 규격)
    // =======================================================
    gemm_accelerator_top u_gemm (
        .clk(clk), 
        .rst_n(~reset),
        
        // Glue와 연결되는 MMIO
        .cpu_addr(gemm_cpu_addr),
        .cpu_wdata(gemm_cpu_wdata),
        .cpu_wen(gemm_cpu_wen),
        .cpu_ren(gemm_cpu_ren),
        .cpu_rdata(gemm_cpu_rdata),
        
        .gemm_busy(gemm_busy), // Top에서 끌어올린 상태 핀
        
        // Glue와 연결되는 BRAM Port A
        .bram_addr_a(gemm_bram_addr_a),
        .bram_wen(gemm_bram_wen_a),
        .bram_wdata(gemm_bram_wdata_a),
        .bram_rdata_a(gemm_bram_rdata_a),
        
        // Glue와 연결되는 BRAM Port B
        .bram_addr_b(gemm_bram_addr_b),
        .bram_rdata_b(gemm_bram_rdata_b)
    );

    // =======================================================
    // 4. Dual-Port BRAM (동기식 Behavioral 모델)
    // =======================================================
    reg [31:0] mem [0:4095];
    reg [31:0] bram_rdata_a_r;
    reg [31:0] bram_rdata_b_r;
    
    // 바이트 단위 주소를 워드 인덱스로 변환 (>> 2)
    wire [11:0] word_addr_a = real_bram_addr_a[11:0];
    wire [11:0] word_addr_b = real_bram_addr_b[11:0];

    always @(posedge clk) begin
        // Port A (읽기/쓰기)
        if (real_bram_wen_a) begin
            mem[word_addr_a] <= real_bram_wdata_a;
        end
        bram_rdata_a_r <= mem[word_addr_a];
        
        // Port B (읽기 전용 - B행렬 수집용)
        bram_rdata_b_r <= mem[word_addr_b];
    end
    
    assign real_bram_rdata_a = bram_rdata_a_r;
    assign real_bram_rdata_b = bram_rdata_b_r;

`ifdef GEMM_MEM_INIT
    initial $readmemh(`GEMM_MEM_INIT, mem);
`endif

endmodule