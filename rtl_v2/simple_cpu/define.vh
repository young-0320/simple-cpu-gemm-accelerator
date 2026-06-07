`ifndef _DEFINE_VH_
`define _DEFINE_VH_



// =======================================================
// 시스템 클럭 주파수 (필요 시 여기서만 수정)
`define CLK_FREQ       10_000_000  // 10MHz
// =======================================================
// 디바운스 목표 시간 (20ms)
`define DEBOUNCE_MS    20
// 카운트 최대값 자동 계산 (주파수 * 시간 / 1000)
`define DEBOUNCE_LIMIT ((`CLK_FREQ / 1000) * `DEBOUNCE_MS)


// =======================================================
// 1. Instruction Opcodes (4-bit)
// =======================================================
`define OP_LOAD     4'b0000
`define OP_STORE    4'b0001
`define OP_ADD      4'b0010
`define OP_SUB      4'b0011
`define OP_CMP      4'b0100
`define OP_LOADI    4'b0101
`define OP_ADDI     4'b0110
`define OP_CMPI     4'b0111
`define OP_JMP      4'b1000
`define OP_JZ       4'b1001
`define OP_JNZ      4'b1010
`define OP_NOP      4'b1011
`define OP_OUT      4'b1100
`define OP_IN       4'b1101
`define OP_RESV1    4'b1110
`define OP_EXT      4'b1111

// =======================================================
// 2. CPU FSM States (2-bit)
// =======================================================
`define ST_FETCH    2'b00
`define ST_DECODE   2'b01
`define ST_EXECUTE  2'b10
`define ST_INCREMENT 2'b11

// =======================================================
// 3. IN Port Map (operand[3:0] in IN instruction)
// =======================================================
`define IN_PORT_NUM     4'd0    // 숫자 입력값 (in_port[3:0])
`define IN_PORT_BTN_IN  4'd1    // 입력 확정 버튼 (in_port[4])
`define IN_PORT_BTN_CFM 4'd2    // 전체 확정 버튼 (in_port[5])
`define IN_PORT_BTN_CAN 4'd3    // 취소 버튼 (in_port[6])
`define IN_PORT_BTN_PW  4'd4    // 비밀번호 변경 (in_port[7])
`define IN_PORT_MST_KEY 4'd5    // 마스터키 (in_port[8])

// =======================================================
// 4. OUT Port State Codes (4-bit, OUT instruction)
// =======================================================
`define OUT_STATE_CLOSED 4'b0000 // 닫힘 / 정상 상태
`define OUT_STATE_OPEN   4'b1000 // 열림
`define OUT_STATE_FAIL1  4'b0100 // 1회 오답
`define OUT_STATE_FAIL2  4'b0010 // 2회 오답
`define OUT_STATE_FAIL3  4'b0001 // 3회 오답 + 잠금

// =======================================================
// 5. ALU Control Codes (Internal Routing)
// =======================================================
`define ALU_ADD     3'd0
`define ALU_SUB     3'd1
`define ALU_CMP     3'd2
`define ALU_PASS    3'd3
`define ALU_SHL     3'd4
`define ALU_SHR     3'd5
`define ALU_AND     3'd6

// =======================================================
// 6. Branch/Jump Types (Internal Routing)
// =======================================================
`define JMP_UNCOND  2'd0  // 무조건 점프 (JMP)
`define JMP_JZ      2'd1  // 조건 점프 (JZ)
`define JMP_JNZ     2'd2  // 조건 점프 (JNZ)

// =======================================================
// 7. Extended Function Codes for OP_EXT / A-type
// opcode 1111일 때만 사용
// =======================================================
`define EXT_SHL     4'b0000
`define EXT_SHR     4'b0001
`define EXT_AND     4'b0010

`endif // _DEFINE_VH_