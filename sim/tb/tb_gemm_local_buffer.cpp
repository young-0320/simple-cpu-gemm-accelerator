#include "Vgemm_local_buffer.h"
#include "verilated.h"
#include <cstdio>
#include <cstdint>

static Vgemm_local_buffer* dut;
static int errors = 0;
#define CHECK(cond, msg, ...) do { \
    if (!(cond)) { printf("  [FAIL] " msg "\n", ##__VA_ARGS__); errors++; } \
    else         { printf("  [ ok ] " msg "\n", ##__VA_ARGS__); } \
} while(0)

static void tick() {
    dut->clk = 0; dut->eval();
    dut->clk = 1; dut->eval();
}

static void a_write(int addr, uint8_t data) {
    dut->a_we = 1; dut->a_waddr = addr; dut->a_wdata = data;
    tick();
    dut->a_we = 0; dut->eval();
}
static void b_write(int addr, uint8_t data) {
    dut->b_we = 1; dut->b_waddr = addr; dut->b_wdata = data;
    tick();
    dut->b_we = 0; dut->eval();
}
static void c_write(int addr, uint32_t data) {
    dut->c_we = 1; dut->c_waddr = addr; dut->c_wdata = data;
    tick();
    dut->c_we = 0; dut->eval();
}
static uint8_t a_read(int addr) { dut->a_raddr = addr; dut->eval(); return dut->a_rdata; }
static uint8_t b_read(int addr) { dut->b_raddr = addr; dut->eval(); return dut->b_rdata; }
static uint32_t c_read(int addr){ dut->c_raddr = addr; dut->eval(); return dut->c_rdata; }

int main(int argc, char** argv) {
    Verilated::commandArgs(argc, argv);
    dut = new Vgemm_local_buffer;
    dut->a_we=0; dut->b_we=0; dut->c_we=0; dut->c_clear=0;
    dut->eval();

    printf("== Test 1: a_buf / b_buf write + combinational read ==\n");
    for (int i = 0; i < 16; i++) { a_write(i, (uint8_t)(i*3+1)); b_write(i, (uint8_t)(0xF0 - i)); }
    bool a_ok = true, b_ok = true;
    for (int i = 0; i < 16; i++) {
        if (a_read(i) != (uint8_t)(i*3+1)) a_ok = false;
        if (b_read(i) != (uint8_t)(0xF0 - i)) b_ok = false;
    }
    CHECK(a_ok, "a_buf all 16 entries read back correctly");
    CHECK(b_ok, "b_buf all 16 entries read back correctly");

    printf("== Test 2: signed int8 bit pattern preserved (e.g. -1 = 0xFF) ==\n");
    a_write(5, 0xFF); // -1
    a_write(6, 0x80); // -128
    CHECK(a_read(5) == 0xFF, "a_buf[5] = 0xFF (-1) preserved (got 0x%X)", a_read(5));
    CHECK(a_read(6) == 0x80, "a_buf[6] = 0x80 (-128) preserved (got 0x%X)", a_read(6));

    printf("== Test 3: c_buf int32 write + read ==\n");
    c_write(0, 0x12345678);
    c_write(15, 0xFFFFFFFF); // -1 as int32
    CHECK(c_read(0) == 0x12345678u, "c_buf[0] = 0x12345678 (got 0x%X)", c_read(0));
    CHECK(c_read(15) == 0xFFFFFFFFu, "c_buf[15] = 0xFFFFFFFF (got 0x%X)", c_read(15));

    printf("== Test 4: c_clear zeroes all of c_buf in one cycle ==\n");
    for (int i = 0; i < 16; i++) c_write(i, 0xAAAA0000 + i);
    dut->c_clear = 1; tick(); dut->c_clear = 0; dut->eval();
    bool cleared = true;
    for (int i = 0; i < 16; i++) if (c_read(i) != 0) cleared = false;
    CHECK(cleared, "all c_buf entries == 0 after c_clear");

    printf("== Test 5: independent read ports (a/b/c same cycle) ==\n");
    a_write(2, 0x2A); b_write(7, 0x5B); c_write(9, 0xDEADBEEF);
    dut->a_raddr = 2; dut->b_raddr = 7; dut->c_raddr = 9; dut->eval();
    CHECK(dut->a_rdata == 0x2A, "simultaneous a_rdata (got 0x%X)", dut->a_rdata);
    CHECK(dut->b_rdata == 0x5B, "simultaneous b_rdata (got 0x%X)", dut->b_rdata);
    CHECK(dut->c_rdata == 0xDEADBEEFu, "simultaneous c_rdata (got 0x%X)", dut->c_rdata);

    printf("\n==== %s : %d error(s) ====\n", errors ? "TESTS FAILED" : "ALL PASS", errors);
    delete dut;
    return errors ? 1 : 0;
}
