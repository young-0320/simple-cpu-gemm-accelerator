#include "Vgemm_controller_fsm.h"
#include "verilated.h"
#include <cstdio>

static Vgemm_controller_fsm* dut;
static int errors = 0;
#define CHECK(cond, msg, ...) do { \
    if (!(cond)) { printf("  [FAIL] " msg "\n", ##__VA_ARGS__); errors++; } \
    else         { printf("  [ ok ] " msg "\n", ##__VA_ARGS__); } \
} while(0)

// FSM state encodings
enum { S_IDLE=0, S_LOAD=1, S_COMPUTE=2, S_STORE=3, S_DONE=4 };

// stub latency counters
static int load_cnt = -1, mac_cnt = -1, store_cnt = -1;

static void eval_stubs() {
    // When FSM raises an enable, start a small countdown, then pulse done.
    dut->lsu_load_done = 0;
    dut->mac_done = 0;
    dut->lsu_store_done = 0;

    if (dut->lsu_load_en) {
        if (load_cnt < 0) load_cnt = 3;        // load takes 3 cycles
    } else load_cnt = -1;
    if (dut->mac_en) {
        if (mac_cnt < 0) mac_cnt = 5;          // compute takes 5 cycles
    } else mac_cnt = -1;
    if (dut->lsu_store_en) {
        if (store_cnt < 0) store_cnt = 2;      // store takes 2 cycles
    } else store_cnt = -1;

    if (load_cnt == 0)  dut->lsu_load_done = 1;
    if (mac_cnt == 0)   dut->mac_done = 1;
    if (store_cnt == 0) dut->lsu_store_done = 1;
}

static void tick() {
    eval_stubs();
    dut->clk = 0; dut->eval();
    dut->clk = 1; dut->eval();
    if (load_cnt  > 0) load_cnt--;
    if (mac_cnt   > 0) mac_cnt--;
    if (store_cnt > 0) store_cnt--;
    eval_stubs();
    dut->eval();
}

static void set_dims(int m, int n, int k) {
    dut->m_dim = m; dut->n_dim = n; dut->k_dim = k;
}

int main(int argc, char** argv) {
    Verilated::commandArgs(argc, argv);
    dut = new Vgemm_controller_fsm;

    dut->reset = 1; dut->start_pulse = 0; dut->clear_pulse = 0;
    set_dims(0,0,0);
    dut->lsu_load_done = 0; dut->mac_done = 0; dut->lsu_store_done = 0;
    tick(); tick();
    dut->reset = 0; tick();
    CHECK(dut->state_debug == S_IDLE, "reset -> IDLE (got %d)", dut->state_debug);

    printf("== Test 1: valid 4x4x4 full sequence ==\n");
    set_dims(4,4,4);
    dut->start_pulse = 1; dut->eval(); tick();
    dut->start_pulse = 0;
    CHECK(dut->state_debug == S_LOAD, "IDLE -> LOAD on valid start (got %d)", dut->state_debug);
    CHECK(dut->busy == 1, "busy=1 in LOAD");

    // run until DONE, bounded
    int guard = 0; bool saw_compute=false, saw_store=false;
    while (dut->state_debug != S_DONE && guard < 50) {
        if (dut->state_debug == S_COMPUTE) saw_compute = true;
        if (dut->state_debug == S_STORE)   saw_store = true;
        tick(); guard++;
    }
    CHECK(saw_compute, "passed through COMPUTE");
    CHECK(saw_store,   "passed through STORE");
    CHECK(dut->state_debug == S_DONE, "reached DONE (got %d)", dut->state_debug);
    CHECK(dut->busy == 0, "busy=0 in DONE");
    CHECK(dut->set_done == 1, "set_done asserted in DONE");
    CHECK(dut->set_error == 0, "set_error=0 on valid completion");

    printf("== Test 2: clear_done returns to IDLE ==\n");
    dut->clear_pulse = 1; dut->eval(); tick();
    dut->clear_pulse = 0; tick();
    CHECK(dut->state_debug == S_IDLE, "DONE -> IDLE after clear (got %d)", dut->state_debug);

    printf("== Test 3: invalid dim (K=5) -> immediate error, no memory ==\n");
    set_dims(2,2,5);
    bool load_en_seen = false;
    dut->start_pulse = 1; dut->eval();
    // during the start cycle, error flags should assert and no load enable
    CHECK(dut->set_invsize == 1, "invalid_size asserted at start");
    CHECK(dut->set_error == 1, "error asserted at start");
    CHECK(dut->set_done == 1, "done asserted at start");
    if (dut->lsu_load_en) load_en_seen = true;
    tick();
    dut->start_pulse = 0;
    if (dut->lsu_load_en) load_en_seen = true;
    CHECK(dut->state_debug == S_DONE, "invalid -> DONE directly (got %d)", dut->state_debug);
    CHECK(!load_en_seen, "no LSU load enable for invalid dims");
    // recover
    dut->clear_pulse = 1; dut->eval(); tick(); dut->clear_pulse = 0; tick();

    printf("== Test 4: invalid dim (M=0) -> error ==\n");
    set_dims(0,3,3);
    dut->start_pulse = 1; dut->eval();
    CHECK(dut->set_invsize == 1, "invalid_size asserted for M=0");
    tick(); dut->start_pulse = 0;
    CHECK(dut->state_debug == S_DONE, "M=0 -> DONE (got %d)", dut->state_debug);
    dut->clear_pulse = 1; dut->eval(); tick(); dut->clear_pulse = 0; tick();

    printf("== Test 5: minimal valid 1x1x1 ==\n");
    set_dims(1,1,1);
    dut->start_pulse = 1; dut->eval(); tick(); dut->start_pulse = 0;
    CHECK(dut->state_debug == S_LOAD, "1x1x1 valid -> LOAD (got %d)", dut->state_debug);
    guard = 0;
    while (dut->state_debug != S_DONE && guard < 50) { tick(); guard++; }
    CHECK(dut->state_debug == S_DONE, "1x1x1 reached DONE");
    CHECK(dut->set_error == 0, "1x1x1 no error");

    printf("\n==== %s : %d error(s) ====\n", errors ? "TESTS FAILED" : "ALL PASS", errors);
    delete dut;
    return errors ? 1 : 0;
}
