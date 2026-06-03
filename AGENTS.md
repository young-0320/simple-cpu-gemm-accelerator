## 1. Think Before Coding

**Don't assume. Don't hide confusion. Surface tradeoffs.**

Before implementing:

- State your assumptions explicitly. If uncertain, ask.
- If multiple interpretations exist, present them - don't pick silently.
- If a simpler approach exists, say so. Push back when warranted.
- If something is unclear, stop. Name what's confusing. Ask.

## 2. Simplicity First

**Minimum code that solves the problem. Nothing speculative.**

- No features beyond what was asked.
- No abstractions for single-use code.
- No "flexibility" or "configurability" that wasn't requested.
- No error handling for impossible scenarios.
- If you write 200 lines and it could be 50, rewrite it.

Ask yourself: "Would a senior engineer say this is overcomplicated?" If yes, simplify.

## 3. Surgical Changes

**Touch only what you must. Clean up only your own mess.**

When editing existing code:

- Don't "improve" adjacent code, comments, or formatting.
- Don't refactor things that aren't broken.
- Match existing style, even if you'd do it differently.
- If you notice unrelated dead code, mention it - don't delete it.

When your changes create orphans:

- Remove imports/variables/functions that YOUR changes made unused.
- Don't remove pre-existing dead code unless asked.

The test: Every changed line should trace directly to the user's request.

## 4. Goal-Driven Execution

**Define success criteria. Loop until verified.**

Transform tasks into verifiable goals:

- "Add validation" → "Write tests for invalid inputs, then make them pass"
- "Fix the bug" → "Write a test that reproduces it, then make it pass"
- "Refactor X" → "Ensure tests pass before and after"

For multi-step tasks, state a brief plan:

```
1. [Step] → verify: [check]
2. [Step] → verify: [check]
3. [Step] → verify: [check]
```

Strong success criteria let you loop independently. Weak criteria ("make it work") require constant clarification.

---

## Project Context

This project is a Digital Systems Design project that extends a previously built Simple CPU with an MMIO-controlled int8 GEMM co-processor. The target demonstration includes transactional verification with Verilator, synthesis analysis with Oasys/Nitro, and FPGA validation on Zybo Z7-20.

The project has four major work areas:

- Simple CPU improvement and integration
- GEMM accelerator design
- External data memory design
- Reference/golden model and Verilator-based verification

The expected development order is GEMM first, then CPU integration, then memory integration. When starting work, assume the current focus is the GEMM accelerator unless the user says otherwise.

## Source-of-Truth Documents

Do not read every document by default. Open only the document that owns the contract you are touching:

- `docs/spec/gemm_accelerator.md`: GEMM accelerator architecture, FSM, local buffers, MAC datapath, transaction flow, and verification approach.
- `docs/spec/interface_cpu_gemm.md`: CPU-facing MMIO register contract, control/status bits, and transaction protocol.
- `docs/spec/interface_gemm_memory.md`: GEMM-to-memory read/write behavior, packed A/B load, unpacking, and C writeback.
- `docs/spec/data_memory.md`: external memory word addressing, A/B packing layout, signed int8 lane mapping, zero padding, row-major layout, and C int32 layout.
- `docs/spec/simple_cpu.md`: CPU responsibility and what the CPU must not do during GEMM transactions.
- `docs/project2.md`: project-level assignment requirements.

If a behavior appears in multiple places, prefer the document listed above as the owner of that contract. Avoid redefining memory layout or protocol rules in unrelated files.

## Current Baseline Contract

The baseline operation is `C = A x B`.

- Matrix shapes: `A` is `M x K`, `B` is `K x N`, `C` is `M x N`.
- Supported dimensions: `1 <= M,N,K <= 4`.
- Input element type: signed int8.
- Product type: signed int16.
- Accumulator and output type: signed int32.
- A/B memory format: packed, four signed int8 lanes per 32-bit word.
- C memory format: unpacked, one signed int32 value per 32-bit word.
- Memory addresses are word addresses, not byte addresses.
- Baseline compute datapath: 1-MAC serial.

Invalid dimensions must not start memory access. They should terminate the transaction with `done=1`, `error=1`, and `invalid_size=1`.

## Verification Direction

Verification should be transaction-level. Tests should drive the same MMIO protocol that the CPU uses and check observable status registers and external memory contents. Do not force internal FSM state or use local buffer contents as the final pass/fail condition.

The verification owner should start with a Python reference/golden model before writing the Verilator testbench. That model should cover:

- signed int8 interpretation
- A/B packing and unpacking
- row-major indexing
- int32 GEMM accumulation
- C memory writeback layout
- valid and invalid dimension behavior
- expected status bits and expected memory contents per transaction

Random tests should be constrained by the same transaction structure: choose valid or invalid dimensions, generate A/B values, choose non-overlapping base addresses, write A/B into external memory layout, start GEMM through MMIO, poll `done`, then compare status and C memory against the golden model.

## Module Boundaries

The CPU only configures GEMM through MMIO, starts a transaction, polls status, and optionally reads C after completion. The CPU does not perform MAC operations, A/B unpacking, or C writeback.

The GEMM accelerator owns A/B load, local buffering, MAC accumulation, and C store during a transaction. While GEMM is busy, the CPU should not perform normal data memory accesses; it should only poll GEMM MMIO status.

The MMIO Register Block is the CPU-facing boundary. It is acceptable for the verification owner to implement or test this block if the scope stays limited to register storage, start/clear pulse generation, and status readback. Controller sequencing, LSU behavior, and MAC datapath should remain separate GEMM design responsibilities unless explicitly assigned.
