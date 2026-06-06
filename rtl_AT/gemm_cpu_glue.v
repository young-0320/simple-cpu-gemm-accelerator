//1
`timescale 1ns / 1ps

module gemm_cpu_glue (
    input  wire        clk,
    input  wire        rst_n,

    // ---- CPU Memory Port (Master Interface) ----
    input  wire [11:0] cpu_addr,       // 시스템 주소 공간에 맞게 비트 수 조정 (예: 16-bit)
    input  wire [31:0] cpu_wdata,
    input  wire        cpu_we,
    input  wire        cpu_re,         // 명확한 타이밍 매칭을 위한 Read Enable 추가
    output wire [31:0] cpu_rdata,
    output wire        cpu_run,        // CPU를 멈추기 위한 Freeze 제어 신호

    // ---- GEMM Accelerator Top Interface ----
    output wire [2:0]  mmio_off,  // 가속기 내부 u_mmio 매핑용 8비트 오프셋
    output wire [31:0] mmio_wdata,
    output wire        mmio_we,
    output wire        mmio_sel,
    input  wire [31:0] mmio_rdata,
    input  wire        gemm_busy,      // 가속기 내부 status_busy 신호 연동 필요

    // 가속기 Top 내부 LSU가 외부 BRAM을 제어하기 위해 내뱉는 포트들 연동
    input  wire [11:0] lsu_addr,
    input  wire [31:0] lsu_wdata,
    input  wire        lsu_we,


    //BRAM port

    output  wire        bram_we_a,
    output  wire [31:0] bram_addr_a,
    output  wire [31:0] bram_wdata_a,
    input wire [31:0] bram_rdata_a,

    // output  wire        bram_we_b,
    output  wire [31:0] bram_addr_b,
    input wire [31:0] bram_rdata_b
    // output  wire [31:0] bram_wdata_b
);

    // 내부 MMIO 주소 맵 데코더 범위 지정 (시스템 메모리 맵 스펙에 맞춰 수정 가능)
    localparam MMIO_BASE = 12'hFF0;
    localparam MMIO_LAST = 12'hFF7;

    // CPU 주소가 가속기 제어용 MMIO 레지스터 영역을 가리키는지 확인
    wire cpu_is_mmio = (cpu_addr >= MMIO_BASE) && (cpu_addr <= MMIO_LAST);
    
    // -------------------------------------------------------
    // 1. CPU Freeze 중재 로직
    // -------------------------------------------------------
    // 가속기가 연산 중(busy)일 때는 CPU를 일시정지시켜 BRAM 버스 충돌을 원천 차단합니다.
    assign cpu_run = ~gemm_busy;

    // -------------------------------------------------------
    // 2. MMIO 버스 제어선 라우팅
    // -------------------------------------------------------
    assign mmio_off  = cpu_addr[2:0]; 
    assign mmio_wdata = cpu_wdata;
    assign mmio_we   = cpu_is_mmio & cpu_we;
    assign mmio_sel   = cpu_is_mmio & cpu_re;

    // -------------------------------------------------------
    // 3. 실재하는 Dual-Port BRAM 멀티플렉싱
    // -------------------------------------------------------
    // [Port A 중재]
    // busy 상태: 가속기 LSU 주소 연결
    // idle 상태: CPU가 주소 버스 장악 (단, MMIO 접근 시에는 BRAM 쓰기를 비활성화하여 오작동 방지)
    assign bram_addr_a  = gemm_busy ? lsu_addr  : cpu_addr;
    assign bram_wdata_a = gemm_busy ? lsu_wdata : cpu_wdata;
    assign bram_we_a    = gemm_busy ? lsu_we
                                  : (cpu_we & ~cpu_is_mmio);
    
    // BRAM이 뱉어낸 실제 읽기 데이터는 항상 가속기 LSU 입력단으로 바로 바이패스
    // assign gemm_bram_rdata_a = real_bram_rdata_a;

    // [Port B 중재]
    // 가속기가 연산 시에만 병렬로 데이터를 긁어가는 전용 통로이므로 CPU 제어선과 섞지 않고 직결합니다.
    assign bram_addr_b  = bram_addr_b;
    assign bram_we_b   = 1'b0; 
    assign bram_wdata_b = 32'd0;
    
    // assign bram_rdata_b = real_bram_rdata_b;

    // -------------------------------------------------------
    // 4. CPU Read Data 반환 및 동기식 Latency 보정
    // -------------------------------------------------------
    // BRAM은 동기식 읽기(1-Cycle Latency)이므로, 조합회로인 MMIO 레지스터 읽기 신호도
    // 1클럭 지연시켜 주어야 CPU가 데이터를 샘플링하는 타이밍과 정확히 맞아떨어집니다.
    reg mmio_sel_d;
    reg [31:0] mmio_rdata_d;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            mmio_sel_d <= 1'b0;
        end else if (cpu_run) begin
            mmio_sel_d <= cpu_is_mmio;
            mmio_rdata_d <= mmio_rdata;
        end
    end

    // 이전 클럭에 MMIO를 요청했다면 가속기의 레지스터 출력값 선택, 아니라면 BRAM Port A 출력값 선택
    assign cpu_rdata = mmio_sel_d ? mmio_rdata_d : bram_rdata_a;

endmodule