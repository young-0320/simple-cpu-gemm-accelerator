#include "Vtb_gemm_top_wrap.h"
#include "verilated.h"
#include <cstdio>
#include <cstdint>

static Vtb_gemm_top_wrap* dut;
static void tick(){ dut->clk=0; dut->eval(); dut->clk=1; dut->eval(); }
static void mem_write(int a,uint32_t d){ dut->bd_we=1;dut->bd_addr=a;dut->bd_wdata=d;tick();dut->bd_we=0;dut->eval(); }
static void mmio_write(int off,uint32_t d){
    dut->mmio_sel=1;dut->mmio_we=1;dut->mmio_off=off;dut->mmio_wdata=d;tick();
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

// measure busy-cycle count for one transaction
static int measure(int M,int N,int K,int8_t*A,int8_t*B){
    int Ab=0x100,Bb=0x140,Cb=0x180;
    dut->reset=1; dut->mmio_sel=0; dut->mmio_we=0; dut->bd_we=0;
    tick();tick(); dut->reset=0; tick();
    for(int i=0;i<M;i++){int8_t l[4]={0,0,0,0};
        for(int c=0;c<K;c++)l[c]=A[i*K+c]; mem_write(Ab+i,pack4(l[0],l[1],l[2],l[3]));}
    for(int k=0;k<K;k++){int8_t l[4]={0,0,0,0};
        for(int c=0;c<N;c++)l[c]=B[k*N+c]; mem_write(Bb+k,pack4(l[0],l[1],l[2],l[3]));}
    mmio_write(0,Ab);mmio_write(1,Bb);mmio_write(2,Cb);
    mmio_write(3,M);mmio_write(4,N);mmio_write(5,K);
    mmio_write(6,0x1); // start

    // count cycles until done
    int cyc=0;
    while(cyc<5000){ if(mmio_status()&0x2) break; tick(); cyc++; }
    mmio_write(6,0x2);
    return cyc;
}

int main(int argc,char**argv){
    Verilated::commandArgs(argc,argv);
    dut=new Vtb_gemm_top_wrap;
    dut->mmio_sel=0;dut->mmio_we=0;dut->bd_we=0;dut->reset=0;dut->eval();

    printf("size      cycles(busy->done)\n");
    int sizes[][3]={{4,4,4},{4,4,1},{2,2,2},{1,4,4},{3,3,3},{4,1,4}};
    for(auto&s:sizes){
        int M=s[0],N=s[1],K=s[2];
        int8_t A[16],B[16];
        for(int x=0;x<16;x++){A[x]=(int8_t)(x+1);B[x]=(int8_t)(x+1);}
        int c=measure(M,N,K,A,B);
        printf("  %dx%dx%d   %d\n",M,N,K,c);
    }
    delete dut; return 0;
}
