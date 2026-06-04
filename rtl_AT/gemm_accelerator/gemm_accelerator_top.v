//adder_tree with synchronous memory 1
`timescale 1ns / 1ps

module gemm_accelerator_top (
    input  wire        clk,
    input  wire        rst_n,
    
    output wire        gemm_busy,
    // ====================================================
    // CPU Bus Interface (MMIO - 32-bit Memory Mapped I/O)
    // ====================================================
    input  wire [2:0]  cpu_addr,
    input  wire [31:0] cpu_wdata,
    input  wire        cpu_wen,
    input  wire        cpu_ren,
    output wire [31:0] cpu_rdata,

    // ====================================================
    // External Data Memory Interface (Dual-Port BRAM)
    // ====================================================
    // Port A (A 행렬 읽기 및 C 행렬 쓰기 전용)
    output wire [31:0] bram_addr_a,
    output wire        bram_wen,
    output wire [31:0] bram_wdata,
    input  wire [31:0] bram_rdata_a,
    
    // Port B (B 행렬 수집 읽기 전용)
    output wire [31:0] bram_addr_b,
    input  wire [31:0] bram_rdata_b
);

    // ====================================================
    // 내부 연결용 와이어 (Internal Wires) 선언
    // ====================================================
    
    // 1. MMIO -> FSM, LSU (레지스터 설정값 및 제어)
    wire [31:0] gemm_a_base, gemm_b_base, gemm_c_base;
    wire [31:0] gemm_m, gemm_n, gemm_k;
    wire        start_pulse;
    wire        clear_pulse; // (MMIO 내부에서 sticky 상태 클리어에 사용)

    // 2. FSM -> MMIO (상태 보고)
    wire        status_busy;
    wire        status_done;
    wire        status_error;
    wire        status_invalid_size;

    // 3. FSM -> LSU & Buffer & Datapath (제어 신호 및 카운터)
    wire        lsu_load_w_en;
    wire        lsu_load_b_en;
    wire        mac_en;
    wire        store_en;
    wire        c_clear;
    wire [31:0] cnt_m, cnt_n, cnt_k;
    wire [1:0]  load_sub_cnt;

    // 4. LSU -> Buffer (데이터 라우팅 및 Packing 인에이블)
    wire [31:0] lsu_w_data_out;
    wire [7:0]  lsu_b_byte_out;
    wire [3:0]  lsu_b_buf_byte_en;

    // 5. Buffer <-> Datapath (연산 데이터 교환)
    wire [31:0] a_buf, b_buf, c_buf;
    wire [31:0] c_datapath_out;

    assign gemm_busy = status_busy;
    
    // ====================================================
    // 1. MMIO Register Block 인스턴스화
    // ====================================================
    gemm_mmio_reg u_mmio (
        .clk            (clk),
        .rst_n          (rst_n),
        
        .addr           (cpu_addr),
        .wdata          (cpu_wdata),
        .wen            (cpu_wen),
        .ren            (cpu_ren),
        .rdata          (cpu_rdata),
        
        .gemm_a_base    (gemm_a_base),
        .gemm_b_base    (gemm_b_base),
        .gemm_c_base    (gemm_c_base),
        .gemm_m         (gemm_m),
        .gemm_n         (gemm_n),
        .gemm_k         (gemm_k),
        
        .start_pulse    (start_pulse),
        .clear_pulse    (clear_pulse),
        
        // FSM의 상세 에러를 MMIO의 에러 핀으로 OR 결합하여 전달
        .npu_busy       (status_busy),
        .npu_done       (status_done),
        .npu_error      (status_error | status_invalid_size) 
    );

    // ====================================================
    // 2. Controller FSM 인스턴스화
    // ====================================================
    gemm_controller_fsm u_fsm (
        .clk                 (clk),
        .rst_n               (rst_n),
        
        .start_pulse         (start_pulse),
        .gemm_m              (gemm_m),
        .gemm_n              (gemm_n),
        .gemm_k              (gemm_k),
        
        .status_busy         (status_busy),
        .status_done         (status_done),
        .status_error        (status_error),
        .status_invalid_size (status_invalid_size),
        
        .lsu_load_w_en       (lsu_load_w_en),
        .lsu_load_b_en       (lsu_load_b_en),
        .mac_en              (mac_en),
        .store_en            (store_en),
        .c_clear             (c_clear),
        
        .cnt_m               (cnt_m),
        .cnt_n               (cnt_n),
        .cnt_k               (cnt_k),
        .load_sub_cnt        (load_sub_cnt)
    );

    // ====================================================
    // 3. Load/Store Unit (LSU) 인스턴스화
    // ====================================================
    gemm_lsu u_lsu (
        .gemm_a_base    (gemm_a_base),
        .gemm_b_base    (gemm_b_base),
        .gemm_c_base    (gemm_c_base),
        .gemm_n         (gemm_n),
        .gemm_k         (gemm_k),
        .gemm_m         (gemm_m),
        
        .lsu_load_w_en  (lsu_load_w_en),
        .lsu_load_b_en  (lsu_load_b_en),
        .store_en       (store_en),
        .cnt_m          (cnt_m),
        .cnt_n          (cnt_n),
        .cnt_k          (cnt_k),
        .load_sub_cnt   (load_sub_cnt),
        
        .bram_addr_a    (bram_addr_a),
        .bram_addr_b    (bram_addr_b),
        .bram_wen       (bram_wen),
        .bram_wdata     (bram_wdata),
        .bram_rdata_a   (bram_rdata_a),
        .bram_rdata_b   (bram_rdata_b),
        
        .w_data_out     (lsu_w_data_out),
        .b_byte_out     (lsu_b_byte_out),
        .b_buf_byte_en  (lsu_b_buf_byte_en),
        .c_buf_data     (c_buf) // Buffer에서 꺼내서 BRAM으로 쓸 데이터
    );

    // ====================================================
    // 4. Local Buffer (로컬 버퍼) 인스턴스화
    // ====================================================
    gemm_local_buffer u_buffer (
        .clk            (clk),
        .rst_n          (rst_n),
        
        .load_w_en      (lsu_load_w_en),
        .w_data_in      (lsu_w_data_out),
        
        .b_buf_byte_en  (lsu_b_buf_byte_en),
        .b_data_byte_in (lsu_b_byte_out),
        
        .c_acc_en       (mac_en),
        .c_clear        (c_clear),
        .c_data_in      (c_datapath_out), // Datapath 계산 결과
        
        .a_buf          (a_buf),
        .b_buf          (b_buf),
        .c_buf          (c_buf)
    );

    // ====================================================
    // 5. MAC Datapath (가산기 트리 내적 코어) 인스턴스화
    // ====================================================
    gemm_mac_datapath u_datapath (
        .gemm_k         (gemm_k),
        .cnt_k          (cnt_k),
        
        .a_buf          (a_buf),
        .b_buf          (b_buf),
        .c_buf          (c_buf), // 누산을 위한 기존 값 입력
        
        .c_out          (c_datapath_out)
    );
    

    
endmodule