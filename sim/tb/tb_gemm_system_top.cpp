#include "Vgemm_system_top.h"
#include "Vgemm_system_top___024root.h"
#include "verilated.h"
#include <cstdio>
#include <cstdint>

static Vgemm_system_top* dut;

static void tick() {
    dut->clk = 0; dut->eval();
    dut->clk = 1; dut->eval();
}

// access internal BRAM model to read back C results
static uint32_t peek_mem(int addr) {
    return dut->rootp->gemm_system_top__DOT__mem[addr];
}

int main(int argc, char** argv) {
    Verilated::commandArgs(argc, argv);
    dut = new Vgemm_system_top;

    dut->clk = 0; dut->reset = 1; dut->in_port = 0;
    dut->eval();
    tick(); tick(); tick();
    dut->reset = 0;

    // run the CPU program; it sets up GEMM, starts, polls done, halts.
    // Give it plenty of cycles (CPU is multi-cycle per instruction +
    // GEMM compute). 2x2x2 is tiny; 4000 cycles is ample.
    int out_seen = 0;
    for (int c = 0; c < 4000; c++) {
        tick();
        if (dut->out_port == 0x8) { out_seen = c; break; }
    }

    printf("== CPU+GEMM integration: 2x2x2 ==\n");
    if (out_seen) printf("  CPU signaled completion (out_port=0x8) at cycle %d\n", out_seen);
    else          printf("  [warn] completion signal not observed within budget\n");

    // expected C = A*B, A=[[1,2],[3,4]] B=[[5,6],[7,8]]
    //   C[0][0]=1*5+2*7=19  C[0][1]=1*6+2*8=22
    //   C[1][0]=3*5+4*7=43  C[1][1]=3*6+4*8=50
    int32_t exp[4] = {19, 22, 43, 50};
    int errors = 0;
    for (int i = 0; i < 4; i++) {
        int32_t got = (int32_t)peek_mem(0x120 + i);
        bool ok = (got == exp[i]);
        printf("  C[%d] @0x%X = %d (expect %d) %s\n",
               i, 0x120+i, got, exp[i], ok ? "[ ok ]" : "[FAIL]");
        if (!ok) errors++;
    }

    printf("\n==== %s : %d error(s) ====\n", errors ? "TESTS FAILED" : "ALL PASS", errors);
    delete dut;
    return errors ? 1 : 0;
}
