#include "Vgemm_system_top.h"
#include "Vgemm_system_top___024root.h"
#include "verilated.h"
#include <cstdio>
#include <cstdint>
#include <cstdlib>
#include <vector>

static Vgemm_system_top* dut;
static int errors = 0;

static void tick() {
    dut->clk = 0; dut->eval();
    dut->clk = 1; dut->eval();
}

// ---- direct access to behavioral BRAM ----
static void poke_mem(int addr, uint32_t v) {
    dut->rootp->gemm_system_top__DOT__mem[addr] = v;
}
static uint32_t peek_mem(int addr) {
    return dut->rootp->gemm_system_top__DOT__mem[addr];
}

// ---- instruction encoders (match assembler.py / decoder.v) ----
static uint32_t LOADI(uint32_t imm){ return (0x5u<<28) | (imm & 0x0FFFFFFF); }
static uint32_t STORE(uint32_t addr){ return (0x1u<<28) | (addr & 0xFFF); }
static uint32_t LOAD (uint32_t addr){ return (0x0u<<28) | (addr & 0xFFF); }
static uint32_t CMPI (uint32_t imm){ return (0x7u<<28) | (imm & 0x0FFFFFFF); }
static uint32_t JZ   (uint32_t addr){ return (0x9u<<28) | (addr & 0xFFF); }
static uint32_t JMP  (uint32_t addr){ return (0x8u<<28) | (addr & 0xFFF); }
static uint32_t OUTp (uint32_t port){ return (0xCu<<28) | (port & 0xF); }

// MMIO offsets
enum { A_BASE=0xFF0,B_BASE=0xFF1,C_BASE=0xFF2,GM=0xFF3,GN=0xFF4,GK=0xFF5,CTRL=0xFF6,STAT=0xFF7 };

// build the GEMM-call program at address 0; returns program length
static int build_program(int Ab,int Bb,int Cb,int M,int N,int K) {
    std::vector<uint32_t> p;
    p.push_back(LOADI(Ab)); p.push_back(STORE(A_BASE));
    p.push_back(LOADI(Bb)); p.push_back(STORE(B_BASE));
    p.push_back(LOADI(Cb)); p.push_back(STORE(C_BASE));
    p.push_back(LOADI(M));  p.push_back(STORE(GM));
    p.push_back(LOADI(N));  p.push_back(STORE(GN));
    p.push_back(LOADI(K));  p.push_back(STORE(GK));
    p.push_back(LOADI(1));  p.push_back(STORE(CTRL));   // start
    int poll = p.size();                                // POLL label
    p.push_back(LOAD(STAT));                            // ACC = status
    p.push_back(CMPI(0x2));                             // done only?
    int jz_idx = p.size();
    p.push_back(JZ(0));                                 // -> FINISH (patch)
    p.push_back(JMP(poll));                             // loop
    int finish = p.size();
    p[jz_idx] = JZ(finish);                             // patch FINISH addr
    p.push_back(LOADI(2)); p.push_back(STORE(CTRL));    // clear_done
    p.push_back(LOADI(8)); p.push_back(OUTp(0));        // signal done
    int halt = p.size();
    p.push_back(JMP(halt));                             // spin

    for (size_t i = 0; i < p.size(); i++) poke_mem(i, p[i]);
    return p.size();
}

static uint32_t pack4(int8_t l0,int8_t l1,int8_t l2,int8_t l3){
    return ((uint32_t)(uint8_t)l0)|((uint32_t)(uint8_t)l1<<8)
         |((uint32_t)(uint8_t)l2<<16)|((uint32_t)(uint8_t)l3<<24);
}
static void golden(const int8_t*A,const int8_t*B,int32_t*C,int M,int N,int K){
    for(int i=0;i<M;i++)for(int j=0;j<N;j++){int32_t a=0;
        for(int k=0;k<K;k++)a+=(int32_t)A[i*K+k]*(int32_t)B[k*N+j];
        C[i*N+j]=a;}
}

// run one full CPU-driven GEMM; returns 0 ok, 1 mismatch, 2 no completion
static int run_case(int M,int N,int K,int8_t*A,int8_t*B,bool verbose){
    int Ab=0x100,Bb=0x140,Cb=0x180;

    // reset
    dut->reset=1; dut->in_port=0; tick(); tick(); tick(); dut->reset=0;

    // clear data region
    for(int i=0x100;i<0x1A0;i++) poke_mem(i,0);
    // program + data
    build_program(Ab,Bb,Cb,M,N,K);
    for(int i=0;i<M;i++){int8_t l[4]={0,0,0,0};
        for(int c=0;c<K;c++)l[c]=A[i*K+c];
        poke_mem(Ab+i,pack4(l[0],l[1],l[2],l[3]));}
    for(int k=0;k<K;k++){int8_t l[4]={0,0,0,0};
        for(int c=0;c<N;c++)l[c]=B[k*N+c];
        poke_mem(Bb+k,pack4(l[0],l[1],l[2],l[3]));}

    // run until completion signal or budget
    int done_cyc=0;
    for(int c=0;c<8000;c++){ tick(); if(dut->out_port==0x8){done_cyc=c;break;} }
    if(!done_cyc){ if(verbose)printf("    no completion\n"); return 2; }

    int32_t g[16]; golden(A,B,g,M,N,K);
    int bad=0;
    for(int i=0;i<M;i++)for(int j=0;j<N;j++){
        int32_t got=(int32_t)peek_mem(Cb+i*N+j);
        if(got!=g[i*N+j]){bad++; if(verbose)printf("    C[%d][%d] got %d exp %d\n",i,j,got,g[i*N+j]);}
    }
    return bad?1:0;
}

int main(int argc,char**argv){
    Verilated::commandArgs(argc,argv);
    dut=new Vgemm_system_top;
    dut->reset=0; dut->in_port=0; dut->eval();
    srand(0x5A17);

    printf("== CPU-driven 2x2x2 (directed) ==\n");
    { int8_t A[4]={1,2,3,4},B[4]={5,6,7,8};
      int r=run_case(2,2,2,A,B,true);
      if(r==0)printf("  [ ok ] C=[19,22,43,50]\n"); else {printf("  [FAIL] code %d\n",r);errors++;} }

    printf("== CPU-driven 4x4x4 (directed, negatives) ==\n");
    { int8_t A[16],B[16];
      for(int i=0;i<16;i++){A[i]=(int8_t)(i-8); B[i]=(int8_t)(5-i);}
      int r=run_case(4,4,4,A,B,true);
      if(r==0)printf("  [ ok ] 4x4x4 signed\n"); else {printf("  [FAIL] code %d\n",r);errors++;} }

    printf("== CPU-driven randomized sweep (subset of sizes, rand int8) ==\n");
    int total=0,passed=0;
    // full 64 sizes x several trials is slow through the CPU; sample sizes
    int sizes[][3]={{1,1,1},{1,2,3},{2,2,2},{2,3,4},{3,3,3},{3,4,2},{4,4,4},{4,1,4},{1,4,4},{4,4,1}};
    for(auto&s:sizes){
        for(int t=0;t<3;t++){
            int M=s[0],N=s[1],K=s[2];
            int8_t A[16],B[16];
            for(int x=0;x<M*K;x++)A[x]=(int8_t)(rand()&0xFF);
            for(int x=0;x<K*N;x++)B[x]=(int8_t)(rand()&0xFF);
            int r=run_case(M,N,K,A,B,false);
            total++; if(r==0)passed++; else printf("  [FAIL] %dx%dx%d t%d code %d\n",M,N,K,t,r);
        }
    }
    printf("  CPU-driven random: %d/%d passed\n",passed,total);
    if(passed!=total)errors+=(total-passed); else printf("  [ ok ] all %d CPU-driven cases match golden\n",total);

    printf("\n==== %s : %d error(s) ====\n", errors?"TESTS FAILED":"ALL PASS", errors);
    delete dut; return errors?1:0;
}
