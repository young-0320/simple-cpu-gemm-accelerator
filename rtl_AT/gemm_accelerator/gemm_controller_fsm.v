`timescale 1ns / 1ps

module gemm_controller_fsm (
    input  wire        clk,
    input  wire        rst_n,

    // CPU - MMIO 상위 커맨드 포트 바인딩
    input  wire        start_pulse,
    input  wire        clear_pulse,
    input  wire [31:0] gemm_m,
    input  wire [31:0] gemm_n,
    input  wire [31:0] gemm_k,
    
    // CPU 가독용 전용 상태 레지스터 시그널 라인
    output reg         status_busy,
    output reg         status_done,
    output reg         status_error,
    output reg         status_invalid_size,

    // 내부 서브 컴포넌트 하이웨이 인에이블 신호선
    output reg         lsu_load_w_en,
    output reg         lsu_load_b_en,
    output reg         mac_en,
    output reg         store_en,
    output reg         c_clear,
    
    // 내부 하드웨어 제어 카운터 링 변수
    output reg  [31:0] cnt_m,
    output reg  [31:0] cnt_n,
    output reg  [31:0] cnt_k,
    output reg  [1:0]  load_sub_cnt,     // 비전치 행렬 수집용 서브 카운터 (0~3)

    output wire [2:0] state_debug
);

    // 스펙 문서 명시 공식 상태 벡터 코드 매핑
    localparam IDLE    = 3'd0;
    localparam LOAD_REQ    = 3'd1;
    localparam LOAD_WAIT   = 3'd2;
    localparam COMPUTE = 3'd3;
    localparam STORE   = 3'd4;
    localparam DONE    = 3'd5;

    reg [2:0] state;
    assign state_debug = state;

    // 범위 검사 로직 완벽 보수 완료 (`&&` 연산자로 분리 교정)
    wire valid_m = (gemm_m >= 32'd1) && (gemm_m <= 32'd4);
    wire valid_n = (gemm_n >= 32'd1) && (gemm_n <= 32'd4);
    wire valid_k = (gemm_k >= 32'd1) && (gemm_k <= 32'd4);
    wire invalid_size = !(valid_m && valid_n && valid_k);

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state               <= IDLE;
            cnt_m               <= 32'd0;
            cnt_n               <= 32'd0;
            cnt_k               <= 32'd0;
            load_sub_cnt        <= 2'd0;
            status_invalid_size <= 1'b0;
            status_error        <= 1'b0;
            c_clear             <= 1'b0;
        end else begin
            case (state)
                IDLE: begin
                    cnt_m        <= 32'd0;
                    cnt_n        <= 32'd0;
                    cnt_k        <= 32'd0;
                    load_sub_cnt <= 2'd0;
                    c_clear      <= 1'b0;
                    if (start_pulse) begin
                        if (invalid_size) begin
                            state               <= DONE;
                            status_invalid_size <= 1'b1;
                            status_error        <= 1'b1; // 예외 스펙 처리
                        end else begin
                            state   <= LOAD_REQ;
                            c_clear <= 1'b1; // 연산 집적 코어 초기화 진입
                        end
                    end
                end
                
                LOAD_REQ: begin
                    c_clear <= 1'b0;
                    state <= LOAD_WAIT;
                end
                
                LOAD_WAIT: begin
                    // 성능 감소를 감수하더라도 지정한 수집 한계(K 또는 최대 4개)까지 순차 반복 처리
                    if ((load_sub_cnt + 1 >= gemm_k) || (load_sub_cnt == 2'd3)) begin
                        state        <= COMPUTE;
                        load_sub_cnt <= 2'd0; // 서브 기어 원위치 복귀
                    end else begin
                        state <= LOAD_REQ;
                        load_sub_cnt <= load_sub_cnt + 2'd1; // 한 행씩 점프 가동
                    end
                end

                COMPUTE: begin
                    // K-차원 병렬로 한 번에 4개씩 털어냈으므로 연산 즉시 내적 종결 처리 가능
                    if (cnt_k + 4 >= gemm_k) begin
                        state <= STORE;
                        cnt_k <= 32'd0;
                    end else begin
                        state <= LOAD_REQ;
                        cnt_k <= cnt_k + 4;
                    end
                end

                STORE: begin
                    // 단일 원소 순차 백라이트 복귀 제어 (Unpacked format)
                    if (cnt_n + 1 == gemm_n) begin
                        cnt_n <= 32'd0;
                        if (cnt_m + 1 == gemm_m) begin
                            state <= DONE;
                        end else begin
                            state   <= LOAD_REQ;
                            cnt_m   <= cnt_m + 1;
                            c_clear <= 1'b1; // 다음 좌표 진입 전 초기화 명령 하달
                        end
                    end else begin
                        state <= LOAD_REQ; // Unpacked이므로 1클럭당 1개 원소 순차 처리 유지
                        cnt_n <= cnt_n + 1;
                        c_clear <= 1'b1;
                    end
                end

                DONE: begin
                    if (clear_pulse)
                    state <= IDLE;
                end
                
                default: state <= IDLE;
            endcase
        end
    end

    // 출력 인에이블 로직 조율 매핑 테이블
    always @(*) begin
        status_busy   = 1'b1;
        status_done   = 1'b0;
        lsu_load_w_en = 1'b0;
        lsu_load_b_en = 1'b0;
        mac_en        = 1'b0;
        store_en      = 1'b0;

        case (state)
            IDLE:    begin status_busy = 1'b0; end
            LOAD_REQ: begin end
            LOAD_WAIT: begin 
                lsu_load_w_en = (load_sub_cnt == 2'd0); 
                lsu_load_b_en = 1'b1;
            end 
            COMPUTE: begin mac_en = 1'b1; end
            STORE:   begin store_en = 1'b1; end
            DONE:    begin status_busy = 1'b0; status_done = 1'b1; end
        endcase
    end

endmodule