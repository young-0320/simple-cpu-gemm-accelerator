#include "Vtb_gemm_top_wrap.h"
#include "verilated.h"
#include <cstdio>
#include <cstdint>
#include <cstdlib>

static Vtb_gemm_top_wrap* dut;
static int errors = 0;

static void tick(){ dut->clk=0; dut->eval(); dut->clk=1; dut->eval(); }

static void mem_write(int a,uint32_t d){ dut->bd_we=1;dut->bd_addr=a;dut->bd_wdata=d;tick();dut->bd_we=0;dut->eval(); }
static uint32_t mem_read(int a){ dut->bd_raddr=a; dut->eval(); return dut->bd_rdata; }

static void mmio_write(int off,uint32_t d){
    dut->mmio_sel=1;dut->mmio_we=1;dut->mmio_off=off;dut->mmio_wdata=d;
    tick();
    dut->mmio_sel=0;dut->mmio_we=0;dut->eval();
}
static uint32_t mmio_status(){
    dut->mmio_sel=1;dut->mmio_we=0;dut->mmio_off=7;dut->eval();
    uint32_t v=dut->mmio_rdata; dut->mmio_sel=0; dut->eval(); return v;
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

// returns: 0=ok, 1=mismatch, 2=timeout
static int run_txn(int M,int N,int K,int8_t*A,int8_t*B,
                   int Ab,int Bb,int Cb,bool verbose){
    dut->reset=1; dut->mmio_sel=0; dut->mmio_we=0; dut->bd_we=0;
    tick();tick(); dut->reset=0; tick();

    // load packed A/B into memory
    for(int i=0;i<M;i++){int8_t l[4]={0,0,0,0};
        for(int c=0;c<K;c++)l[c]=A[i*K+c];
        mem_write(Ab+i,pack4(l[0],l[1],l[2],l[3]));}
    for(int k=0;k<K;k++){int8_t l[4]={0,0,0,0};
        for(int c=0;c<N;c++)l[c]=B[k*N+c];
        mem_write(Bb+k,pack4(l[0],l[1],l[2],l[3]));}

    // program registers
    mmio_write(0, Ab);   // A_BASE
    mmio_write(1, Bb);   // B_BASE
    mmio_write(2, Cb);   // C_BASE
    mmio_write(3, M);
    mmio_write(4, N);
    mmio_write(5, K);
    // start
    mmio_write(6, 0x1);

    // poll done
    int guard=0;
    while(guard<2000){
        uint32_t st=mmio_status();
        if(st & 0x2) break;   // done
        tick(); guard++;
    }
    uint32_t st=mmio_status();
    if(!(st&0x2)){ if(verbose)printf("    timeout, status=0x%X\n",st); return 2; }
    if(st&0x4){ if(verbose)printf("    error flag set unexpectedly, status=0x%X\n",st); return 1; }

    // check C in memory
    int32_t gold[16]; golden(A,B,gold,M,N,K);
    int bad=0;
    for(int i=0;i<M;i++)for(int j=0;j<N;j++){
        int32_t got=(int32_t)mem_read(Cb+i*N+j);
        if(got!=gold[i*N+j]){ bad++;
            if(verbose)printf("    C[%d][%d] got %d exp %d\n",i,j,got,gold[i*N+j]);}
    }
    // clear_done
    mmio_write(6,0x2);
    return bad?1:0;
}

int main(int argc,char**argv){
    Verilated::commandArgs(argc,argv);
    dut=new Vtb_gemm_top_wrap;
    dut->mmio_sel=0;dut->mmio_we=0;dut->bd_we=0;dut->reset=0;dut->eval();
    srand(0xBEEF);

    printf("== Directed: 2x2x2 ==\n");
    { int8_t A[4]={1,2,3,4}, B[4]={5,6,7,8};
      int r=run_txn(2,2,2,A,B,0x100,0x110,0x120,true);
      if(r==0)printf("  [ ok ] 2x2x2 end-to-end\n"); else {printf("  [FAIL] code %d\n",r);errors++;} }

    printf("== Directed: negatives 3x3x3 ==\n");
    { int8_t A[9],B[9];
      for(int i=0;i<9;i++){A[i]=(int8_t)(-5+i);B[i]=(int8_t)(7-i);}
      int r=run_txn(3,3,3,A,B,0x100,0x110,0x120,true);
      if(r==0)printf("  [ ok ] 3x3x3 signed end-to-end\n"); else {printf("  [FAIL] code %d\n",r);errors++;} }

    printf("== Invalid size test: K=5 -> error flag, no compute ==\n");
    { int8_t A[4]={1,1,1,1},B[4]={1,1,1,1};
      dut->reset=1;tick();tick();dut->reset=0;tick();
      mmio_write(3,2);mmio_write(4,2);mmio_write(5,5); // K=5 invalid
      mmio_write(6,0x1); // start
      tick();tick();
      uint32_t st=mmio_status();
      bool done=st&0x2, err=st&0x4, inv=st&0x8;
      if(done&&err&&inv)printf("  [ ok ] invalid_size reported (status=0x%X)\n",st);
      else {printf("  [FAIL] invalid handling status=0x%X\n",st);errors++;}
      mmio_write(6,0x2);
    }

    printf("== Randomized end-to-end: all M,N,K in [1,4], 3 trials each ==\n");
    int total=0,passed=0;
    for(int M=1;M<=4;M++)for(int N=1;N<=4;N++)for(int K=1;K<=4;K++)for(int t=0;t<3;t++){
        int8_t A[16],B[16];
        for(int x=0;x<M*K;x++)A[x]=(int8_t)(rand()&0xFF);
        for(int x=0;x<K*N;x++)B[x]=(int8_t)(rand()&0xFF);
        int r=run_txn(M,N,K,A,B,0x100,0x140,0x180,false);
        total++; if(r==0)passed++;
        else printf("  [FAIL] %dx%dx%d t%d code %d\n",M,N,K,t,r);
    }
    printf("  end-to-end random: %d/%d passed\n",passed,total);
    if(passed!=total)errors+=(total-passed);
    else printf("  [ ok ] all %d full transactions match golden\n",total);

    printf("\n==== %s : %d error(s) ====\n", errors?"TESTS FAILED":"ALL PASS", errors);
    delete dut; return errors?1:0;
}
