`ifndef _GEMM_DEFINE_VH_
`define _GEMM_DEFINE_VH_

// =======================================================
// Data / Address widths  (data_memory.md)
// =======================================================
`define GEMM_DATA_W   32
`define GEMM_ADDR_W   12

// =======================================================
// MMIO Register Map  (word addresses)
//   0xFF0 ~ 0xFF7 : GEMM control/status block
// =======================================================
`define GEMM_MMIO_BASE   12'hFF0
`define GEMM_MMIO_LAST   12'hFF7

// register offsets (addr[2:0])
`define GEMM_OFF_A_BASE  3'd0   // 0xFF0  W
`define GEMM_OFF_B_BASE  3'd1   // 0xFF1  W
`define GEMM_OFF_C_BASE  3'd2   // 0xFF2  W
`define GEMM_OFF_M       3'd3   // 0xFF3  W
`define GEMM_OFF_N       3'd4   // 0xFF4  W
`define GEMM_OFF_K       3'd5   // 0xFF5  W
`define GEMM_OFF_CTRL    3'd6   // 0xFF6  W
`define GEMM_OFF_STATUS  3'd7   // 0xFF7  R

// CTRL write-bits  (interface_cpu_gemm.md)
`define GEMM_CTRL_START_BIT       0
`define GEMM_CTRL_CLEAR_DONE_BIT  1

// STATUS read-bits
`define GEMM_ST_BUSY_BIT      0
`define GEMM_ST_DONE_BIT      1
`define GEMM_ST_ERROR_BIT     2
`define GEMM_ST_INVSIZE_BIT   3

// =======================================================
// Controller FSM states
// =======================================================
`define GEMM_S_IDLE      3'd0
`define GEMM_S_LOAD      3'd1
`define GEMM_S_COMPUTE   3'd2
`define GEMM_S_STORE     3'd3
`define GEMM_S_DONE      3'd4

// =======================================================
// Dimension support range  (baseline: 1 <= M,N,K <= 4)
// =======================================================
`define GEMM_DIM_MIN  3'd1
`define GEMM_DIM_MAX  3'd4

// max tile element count (4x4)
`define GEMM_MAX_ELEM  16

`endif // _GEMM_DEFINE_VH_
