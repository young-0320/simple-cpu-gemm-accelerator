// =======================================================
// tb_dim_edge.cpp
//   Regression for the dimension-truncation bug:
//   M/N/K were stored as 3 bits, so 9 (1001) aliased to 1 and slipped
//   past the validity check. With 4-bit storage, any value outside
//   [1,4] must report invalid_size and must NOT run a compute.
//
//   Drives the GEMM MMIO directly (tb_gemm_top_wrap), no CPU needed.
// =======================================================
#include "Vtb_gemm_top_wrap.h"
#include "verilated.h"
#include <cstdio>
#include <cstdint>

static Vtb_gemm_top_wrap* dut;
static void tick(){ dut->clk=0; dut->eval(); dut->clk=1; dut->eval(); }
static void mem_write(int a,uint32_t d){ dut->bd_we=1;dut->bd_addr=a;dut->bd_wdata=d;tick();dut->bd_we=0;dut->eval(); }
static uint32_t mem_read(int a){ dut->bd_raddr=a; dut->eval(); return dut->bd_rdata; }
static void mmio_write(int off,uint32_t d){
    dut->mmio_sel=1;dut->mmio_we=1;dut->mmio_off=off;dut->mmio_wdata=d;tick();
    dut->mmio_sel=0;dut->mmio_we=0;dut->eval();
}
static uint32_t mmio_status(){
    dut->mmio_sel=1;dut->mmio_we=0;dut->mmio_off=7;dut->eval();
    uint32_t v=dut->mmio_rdata; dut->mmio_sel=0; dut->eval(); return v;
}

static int errors=0;
#define CHECK(c,msg,...) do{ if(!(c)){printf("  [FAIL] " msg "\n",##__VA_ARGS__);errors++;} \
                             else{printf("  [ ok ] " msg "\n",##__VA_ARGS__);} }while(0)

// run a transaction with given M,N,K; return status seen at done.
// also writes a sentinel into C region first to detect spurious compute.
static uint32_t run_dims(int M,int N,int K){
    int Ab=0x100,Bb=0x140,Cb=0x180;
    dut->reset=1; dut->mmio_sel=0; dut->mmio_we=0; dut->bd_we=0;
    tick();tick(); dut->reset=0; tick();

    // sentinel in C region (if compute wrongly runs, it gets overwritten)
    for(int i=0;i<16;i++) mem_write(Cb+i, 0xDEAD0000+i);
    // some A/B data
    for(int i=0;i<8;i++){ mem_write(Ab+i,0x01010101); mem_write(Bb+i,0x01010101); }

    mmio_write(0,Ab);mmio_write(1,Bb);mmio_write(2,Cb);
    mmio_write(3,M);mmio_write(4,N);mmio_write(5,K);
    mmio_write(6,0x1); // start

    int guard=0; while(guard<3000){ if(mmio_status()&0x2) break; tick(); guard++; }
    uint32_t st=mmio_status();
    mmio_write(6,0x2); // clear
    return st;
}

// did C region stay untouched (no compute happened)?
static bool c_untouched(){
    int Cb=0x180;
    for(int i=0;i<16;i++) if(mem_read(Cb+i)!=(uint32_t)(0xDEAD0000+i)) return false;
    return true;
}

int main(int argc,char**argv){
    Verilated::commandArgs(argc,argv);
    dut=new Vtb_gemm_top_wrap;
    dut->mmio_sel=0;dut->mmio_we=0;dut->bd_we=0;dut->reset=0;dut->eval();

    printf("== valid dims (1..4) should NOT be invalid_size ==\n");
    int valids[][3]={{1,1,1},{4,4,4},{2,3,4},{4,1,2}};
    for(auto&d:valids){
        uint32_t st=run_dims(d[0],d[1],d[2]);
        bool inv=st&0x8;
        CHECK(!inv,"M=%d N=%d K=%d not flagged invalid (status=0x%X)",d[0],d[1],d[2],st);
    }

    printf("== the reported bug: M/N/K = 5..15 MUST be invalid_size & no compute ==\n");
    // includes 8(1000->0 alias), 9(1001->1 alias), 10,11,12(->4 alias!) etc.
    int bads[][3]={{9,2,2},{2,9,2},{2,2,9},{10,3,3},{11,1,1},{12,4,4},{5,5,5},{8,8,8},{15,15,15}};
    for(auto&d:bads){
        uint32_t st=run_dims(d[0],d[1],d[2]);
        bool done=st&0x2, inv=st&0x8;
        bool clean=c_untouched();
        CHECK(done && inv, "M=%d N=%d K=%d -> invalid_size set (status=0x%X)",d[0],d[1],d[2],st);
        CHECK(clean, "M=%d N=%d K=%d -> no compute (C region untouched)",d[0],d[1],d[2]);
    }

    printf("\n==== %s : %d error(s) ====\n", errors?"TESTS FAILED":"ALL PASS", errors);
    delete dut; return errors?1:0;
}
