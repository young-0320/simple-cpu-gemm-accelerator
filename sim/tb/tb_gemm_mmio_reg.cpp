#include "Vgemm_mmio_reg.h"
#include "verilated.h"
#include <cstdio>
#include <cstdlib>

static Vgemm_mmio_reg* dut;
static vluint64_t main_time = 0;

static int errors = 0;
#define CHECK(cond, msg, ...) do { \
    if (!(cond)) { printf("  [FAIL] " msg "\n", ##__VA_ARGS__); errors++; } \
    else         { printf("  [ ok ] " msg "\n", ##__VA_ARGS__); } \
} while(0)

static void tick() {
    dut->clk = 0; dut->eval(); main_time++;
    dut->clk = 1; dut->eval(); main_time++;
}

// CPU write to an MMIO register offset
static void mmio_write(int off, uint32_t data) {
    dut->mmio_sel = 1; dut->mmio_we = 1;
    dut->mmio_off = off; dut->mmio_wdata = data;
    tick();
    dut->mmio_sel = 0; dut->mmio_we = 0;
    dut->eval();
}

// CPU read of STATUS (combinational)
static uint32_t mmio_read_status() {
    dut->mmio_sel = 1; dut->mmio_we = 0;
    dut->mmio_off = 7; // STATUS
    dut->eval();
    uint32_t v = dut->mmio_rdata;
    dut->mmio_sel = 0;
    dut->eval();
    return v;
}

int main(int argc, char** argv) {
    Verilated::commandArgs(argc, argv);
    dut = new Vgemm_mmio_reg;

    // reset
    dut->reset = 1; dut->mmio_sel = 0; dut->mmio_we = 0;
    dut->fsm_busy = 0; dut->fsm_set_done = 0;
    dut->fsm_set_error = 0; dut->fsm_set_invsize = 0;
    tick(); tick();
    dut->reset = 0; tick();

    printf("== Test 1: base/dim register writes ==\n");
    mmio_write(0, 0x100);  // A_BASE
    mmio_write(1, 0x200);  // B_BASE
    mmio_write(2, 0x300);  // C_BASE
    mmio_write(3, 4);      // M
    mmio_write(4, 3);      // N
    mmio_write(5, 2);      // K
    CHECK(dut->a_base == 0x100, "A_BASE = 0x100 (got 0x%X)", dut->a_base);
    CHECK(dut->b_base == 0x200, "B_BASE = 0x200 (got 0x%X)", dut->b_base);
    CHECK(dut->c_base == 0x300, "C_BASE = 0x300 (got 0x%X)", dut->c_base);
    CHECK(dut->m_dim == 4, "M = 4 (got %d)", dut->m_dim);
    CHECK(dut->n_dim == 3, "N = 3 (got %d)", dut->n_dim);
    CHECK(dut->k_dim == 2, "K = 2 (got %d)", dut->k_dim);

    printf("== Test 2: CTRL.start makes 1-cycle pulse ==\n");
    // drive CTRL write with start bit, observe start_pulse during that cycle
    dut->mmio_sel = 1; dut->mmio_we = 1;
    dut->mmio_off = 6; dut->mmio_wdata = 0x1; // start
    dut->eval();
    CHECK(dut->start_pulse == 1, "start_pulse asserted during CTRL.start write");
    tick();
    dut->mmio_sel = 0; dut->mmio_we = 0; dut->eval();
    CHECK(dut->start_pulse == 0, "start_pulse deasserted next cycle");

    printf("== Test 3: STATUS reflects busy ==\n");
    dut->fsm_busy = 1; dut->eval();
    uint32_t st = mmio_read_status();
    CHECK((st & 0x1) == 1, "STATUS.busy = 1 (status=0x%X)", st);
    dut->fsm_busy = 0; dut->eval();

    printf("== Test 4: sticky done/error/invsize set & hold ==\n");
    // pulse fsm_set_done + error
    dut->fsm_set_done = 1; dut->fsm_set_error = 1; tick();
    dut->fsm_set_done = 0; dut->fsm_set_error = 0; tick();
    st = mmio_read_status();
    CHECK((st & 0x2) == 0x2, "STATUS.done sticky held (status=0x%X)", st);
    CHECK((st & 0x4) == 0x4, "STATUS.error sticky held (status=0x%X)", st);
    // hold across several cycles without clear
    tick(); tick();
    st = mmio_read_status();
    CHECK((st & 0x2) == 0x2, "STATUS.done still held after idle cycles");

    printf("== Test 5: invsize sticky ==\n");
    dut->fsm_set_invsize = 1; tick();
    dut->fsm_set_invsize = 0; tick();
    st = mmio_read_status();
    CHECK((st & 0x8) == 0x8, "STATUS.invalid_size sticky held (status=0x%X)", st);

    printf("== Test 6: CTRL.clear_done clears sticky flags ==\n");
    mmio_write(6, 0x2); // clear_done
    st = mmio_read_status();
    CHECK((st & 0x2) == 0, "done cleared (status=0x%X)", st);
    CHECK((st & 0x4) == 0, "error cleared (status=0x%X)", st);
    CHECK((st & 0x8) == 0, "invalid_size cleared (status=0x%X)", st);

    printf("\n==== %s : %d error(s) ====\n", errors ? "TESTS FAILED" : "ALL PASS", errors);
    delete dut;
    return errors ? 1 : 0;
}
