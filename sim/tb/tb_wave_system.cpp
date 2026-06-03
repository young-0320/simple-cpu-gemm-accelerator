// =======================================================
// tb_wave_system.cpp
//   Runs ONE full CPU-driven GEMM transaction on gemm_system_top and
//   dumps a VCD waveform (wave_system.vcd) for viewing in GTKWave.
//
//   Build (with tracing):
//     verilator --trace -GMAC_MODE=4 ... --cc gemm_system_top.v \
//        --exe tb_wave_system.cpp --top-module gemm_system_top
//   Then open in x2go desktop:
//     gtkwave wave_system.vcd
//
//   Useful signals to add in GTKWave (drag from the hierarchy):
//     u_cpu  : pc_debug, acc_debug, state(_debug)   -> CPU execution
//     u_glue : cpu_run, mmio_sel, mmio_we, mmio_off -> arbitration/MMIO
//     u_gemm : busy, state_debug                    -> GEMM FSM phase
//              u_gemm.u_lsu.mem_addr / mem_we        -> memory traffic
// =======================================================
#include "Vgemm_system_top.h"
#include "Vgemm_system_top___024root.h"
#include "verilated.h"
#include "verilated_vcd_c.h"
#include <cstdio>
#include <cstdint>

static Vgemm_system_top* dut;
static VerilatedVcdC*    tfp;
static vluint64_t        ts = 0;

static void tick() {
    dut->clk = 0; dut->eval(); tfp->dump(ts++);
    dut->clk = 1; dut->eval(); tfp->dump(ts++);
}

static void poke_mem(int a, uint32_t v){ dut->rootp->gemm_system_top__DOT__mem[a] = v; }
static uint32_t peek_mem(int a){ return dut->rootp->gemm_system_top__DOT__mem[a]; }

// instruction encoders (match decoder.v / assembler.py)
static uint32_t LOADI(uint32_t i){ return (0x5u<<28)|(i&0x0FFFFFFF); }
static uint32_t STORE(uint32_t a){ return (0x1u<<28)|(a&0xFFF); }
static uint32_t LOAD (uint32_t a){ return (0x0u<<28)|(a&0xFFF); }
static uint32_t CMPI (uint32_t i){ return (0x7u<<28)|(i&0x0FFFFFFF); }
static uint32_t JZ   (uint32_t a){ return (0x9u<<28)|(a&0xFFF); }
static uint32_t JMP  (uint32_t a){ return (0x8u<<28)|(a&0xFFF); }
static uint32_t OUTp (uint32_t p){ return (0xCu<<28)|(p&0xF); }

enum { A_BASE=0xFF0,B_BASE=0xFF1,C_BASE=0xFF2,GM=0xFF3,GN=0xFF4,GK=0xFF5,CTRL=0xFF6,STAT=0xFF7 };

static void build_program(int Ab,int Bb,int Cb,int M,int N,int K){
    uint32_t p[40]; int n=0;
    p[n++]=LOADI(Ab); p[n++]=STORE(A_BASE);
    p[n++]=LOADI(Bb); p[n++]=STORE(B_BASE);
    p[n++]=LOADI(Cb); p[n++]=STORE(C_BASE);
    p[n++]=LOADI(M);  p[n++]=STORE(GM);
    p[n++]=LOADI(N);  p[n++]=STORE(GN);
    p[n++]=LOADI(K);  p[n++]=STORE(GK);
    p[n++]=LOADI(1);  p[n++]=STORE(CTRL);
    int poll=n;
    p[n++]=LOAD(STAT); p[n++]=CMPI(0x2);
    int jz=n; p[n++]=JZ(0); p[n++]=JMP(poll);
    int fin=n; p[jz]=JZ(fin);
    p[n++]=LOADI(2); p[n++]=STORE(CTRL);
    p[n++]=LOADI(8); p[n++]=OUTp(0);
    int halt=n; p[n++]=JMP(halt);
    for(int i=0;i<n;i++) poke_mem(i,p[i]);
}
static uint32_t pack4(int8_t a,int8_t b,int8_t c,int8_t d){
    return ((uint32_t)(uint8_t)a)|((uint32_t)(uint8_t)b<<8)
         |((uint32_t)(uint8_t)c<<16)|((uint32_t)(uint8_t)d<<24);
}

int main(int argc,char**argv){
    Verilated::commandArgs(argc,argv);
    Verilated::traceEverOn(true);
    dut = new Vgemm_system_top;
    tfp = new VerilatedVcdC;
    dut->trace(tfp, 99);
    tfp->open("wave_system.vcd");

    dut->reset=1; dut->in_port=0; dut->eval();
    tick(); tick(); tick();
    dut->reset=0;

    // 2x2x2 transaction (small, easy to read in the waveform)
    int M=2,N=2,K=2, Ab=0x100,Bb=0x140,Cb=0x180;
    int8_t A[4]={1,2,3,4}, B[4]={5,6,7,8};
    for(int i=0;i<4;i++) poke_mem(0x100+i,0);
    build_program(Ab,Bb,Cb,M,N,K);
    for(int i=0;i<M;i++){int8_t l[4]={0,0,0,0};
        for(int c=0;c<K;c++)l[c]=A[i*K+c]; poke_mem(Ab+i,pack4(l[0],l[1],l[2],l[3]));}
    for(int k=0;k<K;k++){int8_t l[4]={0,0,0,0};
        for(int c=0;c<N;c++)l[c]=B[k*N+c]; poke_mem(Bb+k,pack4(l[0],l[1],l[2],l[3]));}

    int done_cyc=0;
    for(int c=0;c<4000;c++){ tick(); if(dut->out_port==0x8){done_cyc=c;break;} }
    // a few extra cycles so the tail is visible
    for(int c=0;c<20;c++) tick();

    int32_t exp[4]={19,22,43,50}; int bad=0;
    for(int i=0;i<4;i++) if((int32_t)peek_mem(Cb+i)!=exp[i]) bad++;

    printf("wave dump done. completion cycle=%d, C %s\n",
           done_cyc, bad? "MISMATCH":"correct (19,22,43,50)");
    printf("VCD written to wave_system.vcd  ->  open with: gtkwave wave_system.vcd\n");

    tfp->close();
    delete dut;
    return 0;
}
