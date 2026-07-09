// Mirrors rtl/gemm_accelerator/gemm_define.vh (register map, status bits,
// dimension range). Kept in sync by hand -- if gemm_define.vh changes,
// update this file to match. Nothing currently includes this header: the
// C++ harnesses in this directory (tb_gemm_controller_fsm.cpp,
// tb_gemm_local_buffer.cpp, tb_gemm_mmio_reg.cpp, tb_gemm_system_regress.cpp,
// tb_gemm_system_top.cpp, tb_wave_system.cpp) have no build script (see
// sim/README.md), so this is prepared for whenever one of them is revived
// rather than retrofitted into unbuildable files today.
#ifndef GEMM_REGS_H
#define GEMM_REGS_H

// MMIO register offsets (addr[2:0])
#define GEMM_OFF_A_BASE 0
#define GEMM_OFF_B_BASE 1
#define GEMM_OFF_C_BASE 2
#define GEMM_OFF_M      3
#define GEMM_OFF_N      4
#define GEMM_OFF_K      5
#define GEMM_OFF_CTRL   6
#define GEMM_OFF_STATUS 7

// Absolute MMIO addresses (GEMM_MMIO_BASE 0xFF0 + offset above), for
// harnesses that address the CPU's unified memory bus directly instead of
// going through a separate mmio_sel/mmio_off pair.
#define GEMM_A_BASE_ADDR 0xFF0
#define GEMM_B_BASE_ADDR 0xFF1
#define GEMM_C_BASE_ADDR 0xFF2
#define GEMM_M_ADDR      0xFF3
#define GEMM_N_ADDR      0xFF4
#define GEMM_K_ADDR      0xFF5
#define GEMM_CTRL_ADDR   0xFF6
#define GEMM_STATUS_ADDR 0xFF7

// CTRL write bits
#define GEMM_CTRL_START_BIT      0
#define GEMM_CTRL_CLEAR_DONE_BIT 1

// STATUS read bits
#define GEMM_ST_BUSY_BIT    0
#define GEMM_ST_DONE_BIT    1
#define GEMM_ST_ERROR_BIT   2
#define GEMM_ST_INVSIZE_BIT 3

// Dimension support range (baseline: 1 <= M,N,K <= 4)
#define GEMM_DIM_MIN 1
#define GEMM_DIM_MAX 4

#endif // GEMM_REGS_H
