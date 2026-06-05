`timescale 1ns / 1ps
`include "gemm_define.vh"

// =======================================================
// tb_gemm_vectors_structured
//   Refactored variant of tb_gemm_vectors.sv.
//   It preserves the same vector replay behavior, but separates
//   the flow into named transaction, generator, driver, monitor,
//   and scoreboard blocks for transaction-level verification.
// =======================================================
module tb_gemm_vectors_structured #(
    parameter int MAC_MODE = 4,
    parameter int MEMORY_WORDS = 4096,
    parameter int DONE_TIMEOUT_CYCLES = 5000
);

    /* verilator lint_off DECLFILENAME */
    /* verilator lint_off UNUSEDSIGNAL */
    class gemm_txn;
        bit          is_last;
        string       case_name;
        string       init_mem_path;
        string       expected_mem_path;
        logic [31:0] a_base;
        logic [31:0] b_base;
        logic [31:0] c_base;
        int          m_dim;
        int          n_dim;
        int          k_dim;
        logic [31:0] exp_status;
    endclass

    class gemm_obs;
        bit          is_last;
        gemm_txn     tx;
        logic [31:0] status;
        int          monitor_errors;
    endclass
    /* verilator lint_on UNUSEDSIGNAL */
    /* verilator lint_on DECLFILENAME */

    mailbox #(gemm_txn) gen2drv;
    mailbox #(gemm_obs) mon2sb;
    mailbox #(int)      sb_ack;

    string vector_dir;
    string cases_path;

    logic clk = 1'b0;
    logic reset;

    logic        mmio_sel;
    logic        mmio_we;
    logic [2:0]  mmio_off;
    logic [31:0] mmio_wdata;
    logic [31:0] mmio_rdata;

    logic [11:0] mem_addr;
    logic [31:0] mem_rdata;
    logic [31:0] mem_wdata;
    logic        mem_we;

    logic        busy;
    logic [2:0]  state_debug;

    logic [31:0] mem [0:MEMORY_WORDS-1];
    logic [31:0] expected_mem [0:MEMORY_WORDS-1];

    int total_cases;
    int passed_cases;
    int total_errors;

    always #5 clk <= ~clk;

    gemm_accelerator_top #(
        .MAC_MODE(MAC_MODE)
    ) dut (
        .clk(clk),
        .reset(reset),
        .mmio_sel(mmio_sel),
        .mmio_we(mmio_we),
        .mmio_off(mmio_off),
        .mmio_wdata(mmio_wdata),
        .mmio_rdata(mmio_rdata),
        .mem_addr(mem_addr),
        .mem_rdata(mem_rdata),
        .mem_wdata(mem_wdata),
        .mem_we(mem_we),
        .busy(busy),
        .state_debug(state_debug)
    );

    always_ff @(posedge clk) begin
        if (mem_we) begin
            mem[mem_addr] <= mem_wdata;
        end
        mem_rdata <= mem[mem_addr];
    end

    task automatic reset_dut();
        begin
            reset = 1'b1;
            mmio_sel = 1'b0;
            mmio_we = 1'b0;
            mmio_off = 3'd0;
            mmio_wdata = 32'd0;
            repeat (3) @(posedge clk);
            reset = 1'b0;
            repeat (1) @(posedge clk);
        end
    endtask

    // MMIO bus driver primitives.
    task automatic mmio_write(input logic [2:0] off, input logic [31:0] data);
        begin
            @(negedge clk);
            mmio_sel = 1'b1;
            mmio_we = 1'b1;
            mmio_off = off;
            mmio_wdata = data;
            @(posedge clk);
            @(negedge clk);
            mmio_sel = 1'b0;
            mmio_we = 1'b0;
            mmio_off = 3'd0;
            mmio_wdata = 32'd0;
        end
    endtask

    task automatic mmio_read(input logic [2:0] off, output logic [31:0] data);
        begin
            @(negedge clk);
            mmio_sel = 1'b1;
            mmio_we = 1'b0;
            mmio_off = off;
            mmio_wdata = 32'd0;
            @(posedge clk);
            data = mmio_rdata;
            @(negedge clk);
            mmio_sel = 1'b0;
            mmio_off = 3'd0;
        end
    endtask

    task automatic check_addr_12bit(input string case_name, input string label, input logic [31:0] addr, output int case_errors);
        begin
            case_errors = 0;
            if (addr[31:12] != 20'd0) begin
                $display("[FAIL] %s %s address has nonzero high bits: 0x%08h",
                         case_name, label, addr);
                case_errors++;
            end
        end
    endtask

    task automatic check_memory(input string case_name, output int case_errors);
        int addr;
        int mismatch_count;
        begin
            case_errors = 0;
            mismatch_count = 0;
            for (addr = 0; addr < MEMORY_WORDS; addr++) begin
                if (mem[addr] !== expected_mem[addr]) begin
                    if (mismatch_count < 8) begin
                        $display("[FAIL] %s mem[0x%03h] got=0x%08h expected=0x%08h",
                                 case_name, addr[11:0], mem[addr], expected_mem[addr]);
                    end
                    mismatch_count++;
                end
            end

            if (mismatch_count != 0) begin
                $display("[FAIL] %s memory mismatch count=%0d", case_name, mismatch_count);
                case_errors += mismatch_count;
            end
        end
    endtask

    task automatic require_readmem_file(input string case_name, input string label, input string path);
        int fd;
        begin
            fd = $fopen(path, "r");
            if (fd == 0) begin
                $fatal(1, "%s missing %s memory image: %s", case_name, label, path);
            end
            $fclose(fd);
        end
    endtask

    // Generator: read cases.tsv and publish one GEMM transaction per row.
    task automatic generator();
        string header_line;
        string case_name;
        string init_mem_name;
        string expected_mem_name;
        logic [31:0] a_base;
        logic [31:0] b_base;
        logic [31:0] c_base;
        logic [31:0] exp_status;
        int m_dim;
        int n_dim;
        int k_dim;
        int cases_fd;
        int scan_count;
        int fgets_result;
        gemm_txn tx;
        begin
            cases_fd = $fopen(cases_path, "r");
            if (cases_fd == 0) begin
                $fatal(1, "failed to open cases table: %s", cases_path);
            end

            fgets_result = $fgets(header_line, cases_fd);
            if (fgets_result == 0) begin
                $fatal(1, "empty cases table: %s", cases_path);
            end
            if (header_line.len() == 0) begin
                $fatal(1, "missing cases table header: %s", cases_path);
            end

            forever begin
                scan_count = $fscanf(cases_fd, "%s %s %s %h %h %h %d %d %d %h",
                                     case_name, init_mem_name, expected_mem_name,
                                     a_base, b_base, c_base,
                                     m_dim, n_dim, k_dim, exp_status);
                if (scan_count == -1) begin
                    break;
                end
                if (scan_count == 0) begin
                    fgets_result = $fgets(header_line, cases_fd);
                    if (fgets_result == 0 || $feof(cases_fd)) begin
                        break;
                    end
                    continue;
                end
                if (scan_count != 10) begin
                    $fatal(1, "malformed cases row in %s: parsed %0d fields", cases_path, scan_count);
                end

                tx = new();
                tx.is_last = 1'b0;
                tx.case_name = case_name;
                tx.init_mem_path = {vector_dir, "/", init_mem_name};
                tx.expected_mem_path = {vector_dir, "/", expected_mem_name};
                tx.a_base = a_base;
                tx.b_base = b_base;
                tx.c_base = c_base;
                tx.m_dim = m_dim;
                tx.n_dim = n_dim;
                tx.k_dim = k_dim;
                tx.exp_status = exp_status;
                gen2drv.put(tx);
            end

            $fclose(cases_fd);

            tx = new();
            tx.is_last = 1'b1;
            gen2drv.put(tx);
        end
    endtask

    // Driver: translate each transaction into the GEMM MMIO protocol.
    task automatic driver();
        gemm_txn tx;
        gemm_obs obs;
        int ack_value;
        begin
            forever begin
                gen2drv.get(tx);
                if (tx.is_last) begin
                    obs = new();
                    obs.is_last = 1'b1;
                    mon2sb.put(obs);
                    break;
                end

                require_readmem_file(tx.case_name, "initial", tx.init_mem_path);
                require_readmem_file(tx.case_name, "expected", tx.expected_mem_path);
                $readmemh(tx.init_mem_path, mem);
                $readmemh(tx.expected_mem_path, expected_mem);
                reset_dut();

                mmio_write(`GEMM_OFF_A_BASE, tx.a_base);
                mmio_write(`GEMM_OFF_B_BASE, tx.b_base);
                mmio_write(`GEMM_OFF_C_BASE, tx.c_base);
                mmio_write(`GEMM_OFF_M, tx.m_dim);
                mmio_write(`GEMM_OFF_N, tx.n_dim);
                mmio_write(`GEMM_OFF_K, tx.k_dim);
                mmio_write(`GEMM_OFF_CTRL, 32'h0000_0001);

                obs = new();
                obs.is_last = 1'b0;
                obs.tx = tx;
                monitor_transaction(tx, obs.status, obs.monitor_errors);
                mon2sb.put(obs);

                sb_ack.get(ack_value);
                if (ack_value != 1) begin
                    $fatal(1, "unexpected scoreboard acknowledgement value: %0d", ack_value);
                end
                mmio_write(`GEMM_OFF_CTRL, 32'h0000_0002);
            end
        end
    endtask

    // Monitor: observe completion through STATUS, not internal state.
    task automatic monitor_transaction(input gemm_txn tx, output logic [31:0] status, output int monitor_errors);
        int cycles;
        begin
            monitor_errors = 0;
            status = 32'd0;
            for (cycles = 0; cycles < DONE_TIMEOUT_CYCLES; cycles++) begin
                mmio_read(`GEMM_OFF_STATUS, status);
                if (status[`GEMM_ST_DONE_BIT]) begin
                    return;
                end
                @(posedge clk);
            end

            $display("[FAIL] %s timed out: status=0x%08h busy=%0b state=%0d",
                     tx.case_name, status, busy, state_debug);
            monitor_errors++;
        end
    endtask

    // Scoreboard: compare observed status and memory against golden outputs.
    task automatic scoreboard();
        gemm_obs obs;
        int case_errors;
        int local_errors;
        begin
            forever begin
                mon2sb.get(obs);
                if (obs.is_last) begin
                    break;
                end

                case_errors = obs.monitor_errors;

                check_addr_12bit(obs.tx.case_name, "A_BASE", obs.tx.a_base, local_errors);
                case_errors += local_errors;
                check_addr_12bit(obs.tx.case_name, "B_BASE", obs.tx.b_base, local_errors);
                case_errors += local_errors;
                check_addr_12bit(obs.tx.case_name, "C_BASE", obs.tx.c_base, local_errors);
                case_errors += local_errors;

                if (obs.status !== obs.tx.exp_status) begin
                    $display("[FAIL] %s status got=0x%08h expected=0x%08h",
                             obs.tx.case_name, obs.status, obs.tx.exp_status);
                    case_errors++;
                end

                check_memory(obs.tx.case_name, local_errors);
                case_errors += local_errors;

                total_cases++;
                if (case_errors == 0) begin
                    passed_cases++;
                    $display("[ ok ] %s", obs.tx.case_name);
                end
                else begin
                    total_errors += case_errors;
                    $display("[FAIL] %s errors=%0d", obs.tx.case_name, case_errors);
                end

                sb_ack.put(1);
            end
        end
    endtask

    initial begin
        reset = 1'b1;
        mmio_sel = 1'b0;
        mmio_we = 1'b0;
        mmio_off = 3'd0;
        mmio_wdata = 32'd0;
        mem_rdata = 32'd0;
        total_cases = 0;
        passed_cases = 0;
        total_errors = 0;

        gen2drv = new();
        mon2sb = new();
        sb_ack = new();

        if (!$value$plusargs("VECTOR_DIR=%s", vector_dir)) begin
            vector_dir = "sim/vectors/directed_case";
        end
        if (!$value$plusargs("CASES=%s", cases_path)) begin
            cases_path = {vector_dir, "/cases.tsv"};
        end

        $dumpfile("tb_gemm_vectors_structured.fst");
        $dumpvars(0, tb_gemm_vectors_structured);

        $display("== GEMM structured transaction replay ==");
        $display("  vector_dir: %s", vector_dir);
        $display("  cases:      %s", cases_path);
        $display("  MAC_MODE:   %0d", MAC_MODE);

        fork
            generator();
            driver();
            scoreboard();
        join

        $display("==== %s : %0d/%0d case(s), %0d error(s) ====",
                 (total_errors == 0) ? "ALL PASS" : "TESTS FAILED",
                 passed_cases, total_cases, total_errors);

        if (total_cases == 0) begin
            $fatal(1, "no vector cases were run");
        end
        if (total_errors != 0) begin
            $fatal(1, "GEMM structured vector replay failed");
        end
        $finish;
    end

endmodule
