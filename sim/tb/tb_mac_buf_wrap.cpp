#include "Vtb_mac_buf_wrap.h"
#include "verilated.h"
#include <cstdio>
#include <cstdint>
#include <cstdlib>
#include <vector>

static Vtb_mac_buf_wrap* dut;
static int errors = 0;

static void tick() {
    dut->clk = 0; dut->eval();
    dut->clk = 1; dut->eval();
}

// Golden GEMM: C[i][j] = sum_k A[i][k]*B[k][j], all signed.
static void golden(const int8_t* A, const int8_t* B, int32_t* C,
                   int M, int N, int K) {
    for (int i = 0; i < M; i++)
        for (int j = 0; j < N; j++) {
            int32_t acc = 0;
            for (int k = 0; k < K; k++)
                acc += (int32_t)A[i*K+k] * (int32_t)B[k*N+j];
            C[i*N+j] = acc;
        }
}

static void preload_A(int idx, int8_t v) {
    dut->pre_a_we = 1; dut->pre_a_waddr = idx; dut->pre_a_wdata = (uint8_t)v;
    tick(); dut->pre_a_we = 0; dut->eval();
}
static void preload_B(int idx, int8_t v) {
    dut->pre_b_we = 1; dut->pre_b_waddr = idx; dut->pre_b_wdata = (uint8_t)v;
    tick(); dut->pre_b_we = 0; dut->eval();
}
static int32_t read_C(int idx) {
    dut->c_raddr_tb = idx; dut->eval();
    return (int32_t)dut->c_rdata_tb;
}

// run one GEMM, return true if matches golden
static bool run_case(int M, int N, int K, int8_t* A, int8_t* B, bool verbose) {
    // reset MAC
    dut->reset = 1; dut->mac_en = 0; tick(); tick();
    dut->reset = 0; tick();

    // preload tiles
    for (int x = 0; x < M*K; x++) preload_A(x, A[x]);
    for (int x = 0; x < K*N; x++) preload_B(x, B[x]);

    // run compute
    dut->m_dim = M; dut->n_dim = N; dut->k_dim = K;
    dut->mac_en = 1; dut->eval();
    int guard = 0;
    while (!dut->mac_done && guard < 200) { tick(); guard++; }
    bool done = dut->mac_done;
    // hold a cycle then drop mac_en
    tick();
    dut->mac_en = 0; dut->eval();
    tick();

    if (!done) { printf("  [FAIL] %dx%dx%d: mac_done never asserted\n", M,N,K); return false; }

    int32_t gold[16];
    golden(A, B, gold, M, N, K);
    bool ok = true;
    for (int i = 0; i < M; i++)
        for (int j = 0; j < N; j++) {
            int32_t got = read_C(i*N+j);
            if (got != gold[i*N+j]) {
                ok = false;
                if (verbose)
                    printf("    C[%d][%d] got %d, expected %d\n", i, j, got, gold[i*N+j]);
            }
        }
    return ok;
}

int main(int argc, char** argv) {
    Verilated::commandArgs(argc, argv);
    dut = new Vtb_mac_buf_wrap;
    dut->pre_a_we=0; dut->pre_b_we=0; dut->mac_en=0; dut->reset=0;
    dut->eval();
    srand(0xC0FFEE);

    printf("== Directed: identity-ish 2x2 ==\n");
    {
        int8_t A[4] = {1,2,3,4};
        int8_t B[4] = {1,0,0,1};
        bool ok = run_case(2,2,2,A,B,true);
        if (ok) printf("  [ ok ] 2x2 * I = A\n"); else { printf("  [FAIL] 2x2 identity\n"); errors++; }
    }

    printf("== Directed: negative values 2x2x2 ==\n");
    {
        int8_t A[4] = {-1,-2,3,-4};
        int8_t B[4] = {5,-6,-7,8};
        bool ok = run_case(2,2,2,A,B,true);
        if (ok) printf("  [ ok ] signed negative product correct\n"); else { printf("  [FAIL] signed negative\n"); errors++; }
    }

    printf("== Directed: extreme -128 * -128 accumulation 1x1x4 ==\n");
    {
        int8_t A[4] = {-128,-128,-128,-128};
        int8_t B[4] = {-128,-128,-128,-128};
        // expect 4 * (16384) = 65536
        bool ok = run_case(1,1,4,A,B,true);
        if (ok) printf("  [ ok ] -128*-128*4 = 65536 (int32 ok)\n"); else { printf("  [FAIL] extreme accumulate\n"); errors++; }
    }

    printf("== Randomized sweep: all M,N,K in [1,4], rand int8, 5 trials each ==\n");
    int total = 0, passed = 0;
    for (int M = 1; M <= 4; M++)
    for (int N = 1; N <= 4; N++)
    for (int K = 1; K <= 4; K++)
    for (int t = 0; t < 5; t++) {
        int8_t A[16], B[16];
        for (int x = 0; x < M*K; x++) A[x] = (int8_t)(rand() & 0xFF);
        for (int x = 0; x < K*N; x++) B[x] = (int8_t)(rand() & 0xFF);
        bool ok = run_case(M,N,K,A,B,false);
        total++; if (ok) passed++;
        else printf("  [FAIL] random %dx%dx%d trial %d\n", M,N,K,t);
    }
    printf("  random: %d/%d passed\n", passed, total);
    if (passed != total) errors += (total - passed);
    else printf("  [ ok ] all %d random cases match golden\n", total);

    printf("\n==== %s : %d error(s) ====\n", errors ? "TESTS FAILED" : "ALL PASS", errors);
    delete dut;
    return errors ? 1 : 0;
}
