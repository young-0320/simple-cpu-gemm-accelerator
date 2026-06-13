; GEMM call driver (2x2x2)
; A_BASE=0x20 B_BASE=0x50 C_BASE=0x80, M=N=K=2
ORG 0
        LOADI 0x20
        STORE 0xFF0
        LOADI 0x50
        STORE 0xFF1
        LOADI 0x80
        STORE 0xFF2
        LOADI 0x2
        STORE 0xFF3
        LOADI 0x2
        STORE 0xFF4
        LOADI 0x2
        STORE 0xFF5
        LOADI 0x1
        STORE 0xFF6
POLL:
        LOAD 0xFF7
        CMPI 0x2
        JZ FINISH
        JMP POLL
FINISH:
        LOADI 0x2
        STORE 0xFF6
        LOADI 0x8
        OUT 0x0
HALT:
        JMP HALT
