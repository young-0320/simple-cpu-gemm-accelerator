#include "Vtb_lsu_wrap.h"
#include "verilated.h"
#include <cstdio>
#include <cstdint>
#include <cstdlib>

static Vtb_lsu_wrap* dut;
static int errors = 0;

static void tick() {
    dut->clk = 0; dut->eval();
    dut->clk = 1; dut->eval();
}

static void mem_write(int addr, uint32_t data) {
    dut->bd_we = 1; dut->bd_addr = addr; dut->bd_wdata = data;
    tick();
    dut->bd_we = 0; dut->eval();
}
static uint8_t chk_a(int idx){ dut->chk_a_raddr=idx; dut->eval(); return dut->chk_a_rdata; }
static uint8_t chk_b(int idx){ dut->chk_b_raddr=idx; dut->eval(); return dut->chk_b_rdata; }

// pack 4 signed int8 into one word, lane0=[7:0]..lane3=[31:24]
static uint32_t pack4(int8_t l0,int8_t l1,int8_t l2,int8_t l3){
    return ((uint32_t)(uint8_t)l0)
         | ((uint32_t)(uint8_t)l1<<8)
         | ((uint32_t)(uint8_t)l2<<16)
         | ((uint32_t)(uint8_t)l3<<24);
}

static bool run_load(int M,int N,int K,int8_t* A,int8_t* B,int Abase,int Bbase,bool verbose){
    dut->reset=1; dut->load_en=0; dut->store_en=0; tick(); tick();
    dut->reset=0; tick();

    // write packed A
    // row-major word-aligned: A row i -> word (K lanes); B row k -> word (N lanes)
    for(int i=0;i<M;i++){
        int8_t l[4]={0,0,0,0};
        for(int c=0;c<K;c++) l[c]=A[i*K+c];
        mem_write(Abase+i, pack4(l[0],l[1],l[2],l[3]));
    }
    for(int k=0;k<K;k++){
        int8_t l[4]={0,0,0,0};
        for(int c=0;c<N;c++) l[c]=B[k*N+c];
        mem_write(Bbase+k, pack4(l[0],l[1],l[2],l[3]));
    }

    dut->m_dim=M; dut->n_dim=N; dut->k_dim=K;
    dut->a_base=Abase; dut->b_base=Bbase; dut->c_base=0x300;

    dut->load_en=1; dut->eval();
    int guard=0;
    while(!dut->load_done && guard<300){ tick(); guard++; }
    bool done=dut->load_done;
    tick(); dut->load_en=0; dut->eval(); tick();
    if(!done){ printf("  [FAIL] %dx%dx%d LOAD never done\n",M,N,K); return false; }

    bool ok=true;
    for(int e=0;e<M*K;e++){ uint8_t g=(uint8_t)A[e]; uint8_t got=chk_a(e);
        if(got!=g){ ok=false; if(verbose) printf("    a_buf[%d] got 0x%X exp 0x%X\n",e,got,g);} }
    for(int e=0;e<K*N;e++){ uint8_t g=(uint8_t)B[e]; uint8_t got=chk_b(e);
        if(got!=g){ ok=false; if(verbose) printf("    b_buf[%d] got 0x%X exp 0x%X\n",e,got,g);} }
    return ok;
}

int main(int argc,char**argv){
    Verilated::commandArgs(argc,argv);
    dut=new Vtb_lsu_wrap;
    dut->bd_we=0; dut->load_en=0; dut->store_en=0; dut->reset=0;
    dut->eval();
    srand(0x1234);

    printf("== Directed: 2x2x2 simple ==\n");
    { int8_t A[4]={1,2,3,4}, B[4]={5,6,7,8};
      bool ok=run_load(2,2,2,A,B,0x100,0x200,true);
      if(ok) printf("  [ ok ] 2x2x2 unpack correct\n"); else {printf("  [FAIL]\n"); errors++;} }

    printf("== Directed: negative lanes 1x4x... (4 lanes in one word) ==\n");
    { int8_t A[4]={-1,-128,127,-50}, B[4]={1,1,1,1};
      bool ok=run_load(1,4,4,A,B,0x100,0x200,true); // M*K=4 (1 word), K*N=16
      if(ok) printf("  [ ok ] negative int8 lanes unpack correct\n"); else {printf("  [FAIL]\n"); errors++;} }

    printf("== Randomized LOAD sweep: all M,N,K in [1,4], 4 trials each ==\n");
    int total=0,passed=0;
    for(int M=1;M<=4;M++)for(int N=1;N<=4;N++)for(int K=1;K<=4;K++)for(int t=0;t<4;t++){
        int8_t A[16],B[16];
        for(int x=0;x<M*K;x++)A[x]=(int8_t)(rand()&0xFF);
        for(int x=0;x<K*N;x++)B[x]=(int8_t)(rand()&0xFF);
        bool ok=run_load(M,N,K,A,B,0x100,0x200,false);
        total++; if(ok)passed++; else printf("  [FAIL] random %dx%dx%d t%d\n",M,N,K,t);
    }
    printf("  LOAD random: %d/%d passed\n",passed,total);
    if(passed!=total) errors+=(total-passed); else printf("  [ ok ] all %d LOAD cases correct\n",total);

    printf("\n==== %s : %d error(s) ====\n", errors?"TESTS FAILED":"ALL PASS", errors);
    delete dut; return errors?1:0;
}
