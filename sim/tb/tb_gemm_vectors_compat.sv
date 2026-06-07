`timescale 1ns / 1ps
`include "gemm_define.vh"

// =======================================================
// tb_gemm_vectors_compat
//   Compatibility transaction replay testbench. The flow is split into
//   named transaction, generator, driver, monitor, and scoreboard blocks
//   for transaction-level verification.
//
//   When +RESULT_DIR=<path> is provided, the bench also emits:
//     - case_results.tsv
//     - failure_details.tsv
//     - run.log
// =======================================================
module tb_gemm_vectors_compat #(
    parameter int MAC_MODE = 4,
    parameter int MEMORY_WORDS = 4096,
    parameter int DONE_TIMEOUT_CYCLES = 5000,
    parameter int MAX_FAILURE_DETAILS = 16
);

    /* verilator lint_off DECLFILENAME */
    /* verilator lint_off UNUSEDSIGNAL */
    class gemm_txn;
        bit          is_last;
        int          txn_id;
        string       case_name;
        string       init_mem_name;
        string       expected_mem_name;
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
        int          cycles;
        int          busy_cycles;
        int          idle_cycles;
        int          load_cycles;
        int          compute_cycles;
        int          store_cycles;
        int          done_cycles;
        int          mem_read_cycles;
        int          mem_write_cycles;
        int          port_a_read_cycles;
        int          port_b_read_cycles;
        int          port_a_write_cycles;
        int          dual_read_cycles;
        int          mem_write_count;
        bit          timeout;
        bit          missing_init_mem;
        bit          missing_expected_mem;
        bit          ran_dut;
    endclass
    /* verilator lint_on UNUSEDSIGNAL */
    /* verilator lint_on DECLFILENAME */

    mailbox #(gemm_txn) gen2drv;
    mailbox #(gemm_obs) mon2sb;
    mailbox #(int)      sb_ack;

    string vector_dir;
    string cases_path;
    string result_dir;
    string run_id;
    string vector_set;
    string dumpfile_path;

    bit result_files_enabled;
    int case_results_fd;
    int failure_details_fd;
    int run_log_fd;

    logic clk = 1'b0;
    logic reset;

    logic        mmio_sel;
    logic        mmio_we;
    logic [2:0]  mmio_off;
    logic [31:0] mmio_wdata;
    logic [31:0] mmio_rdata;

    logic [11:0] mem_addr_a;
    logic [11:0] mem_addr_b;
    logic [31:0] mem_rdata_a;
    logic [31:0] mem_rdata_b;
    logic [31:0] mem_wdata;
    logic        mem_en;
    logic [11:0] unused_mem_addr;
    logic        unused_mem_we;
    wire         unused_single_port = &{unused_mem_addr, unused_mem_we};

    logic        busy;
    logic [2:0]  state_debug;

    logic [31:0] mem [0:MEMORY_WORDS-1];
    logic [31:0] expected_mem [0:MEMORY_WORDS-1];

    logic activity_count_clear;
    logic activity_count_enable;
    int activity_cycles;
    int activity_busy_cycles;
    int activity_idle_cycles;
    int activity_load_cycles;
    int activity_compute_cycles;
    int activity_store_cycles;
    int activity_done_cycles;
    int activity_mem_read_cycles;
    int activity_mem_write_cycles;
    int activity_port_a_read_cycles;
    int activity_port_b_read_cycles;
    int activity_port_a_write_cycles;
    int activity_dual_read_cycles;
    int activity_mem_writes;

    int total_cases;
    int passed_cases;
    int total_errors;

    always #5 clk <= ~clk;

    gemm_accelerator_top #(
        .MAC_MODE(MAC_MODE),
        .MEMORY_PORTS(2)
    ) dut (
        .clk(clk),
        .reset(reset),
        .mmio_sel(mmio_sel),
        .mmio_we(mmio_we),
        .mmio_off(mmio_off),
        .mmio_wdata(mmio_wdata),
        .mmio_rdata(mmio_rdata),
        .mem_addr(unused_mem_addr),
        .mem_rdata(32'd0),
        .mem_we(unused_mem_we),
        .mem_addr_a(mem_addr_a),
        .mem_rdata_a(mem_rdata_a),
        .mem_en(mem_en),
        .mem_wdata(mem_wdata),
        .mem_addr_b(mem_addr_b),
        .mem_rdata_b(mem_rdata_b),
        .busy(busy),
        .state_debug(state_debug)
    );

    always_ff @(posedge clk) begin
        if (mem_en) begin
            mem[mem_addr_a] <= mem_wdata;
        end
        mem_rdata_a <= mem[mem_addr_a];
        mem_rdata_b <= mem[mem_addr_b];

        if (activity_count_clear) begin
            activity_cycles <= 0;
            activity_busy_cycles <= 0;
            activity_idle_cycles <= 0;
            activity_load_cycles <= 0;
            activity_compute_cycles <= 0;
            activity_store_cycles <= 0;
            activity_done_cycles <= 0;
            activity_mem_read_cycles <= 0;
            activity_mem_write_cycles <= 0;
            activity_port_a_read_cycles <= 0;
            activity_port_b_read_cycles <= 0;
            activity_port_a_write_cycles <= 0;
            activity_dual_read_cycles <= 0;
            activity_mem_writes <= 0;
        end
        else if (activity_count_enable) begin
            activity_cycles <= activity_cycles + 1;
            if (busy) begin
                activity_busy_cycles <= activity_busy_cycles + 1;
            end
            case (state_debug)
                `GEMM_S_IDLE:    activity_idle_cycles <= activity_idle_cycles + 1;
                `GEMM_S_LOAD:    activity_load_cycles <= activity_load_cycles + 1;
                `GEMM_S_COMPUTE: activity_compute_cycles <= activity_compute_cycles + 1;
                `GEMM_S_STORE:   activity_store_cycles <= activity_store_cycles + 1;
                `GEMM_S_DONE:    activity_done_cycles <= activity_done_cycles + 1;
                default: ;
            endcase
            if (state_debug == `GEMM_S_LOAD && !mem_en) begin
                activity_mem_read_cycles <= activity_mem_read_cycles + 1;
                activity_port_a_read_cycles <= activity_port_a_read_cycles + 1;
                activity_port_b_read_cycles <= activity_port_b_read_cycles + 1;
                activity_dual_read_cycles <= activity_dual_read_cycles + 1;
            end
            if (mem_en) begin
                activity_mem_write_cycles <= activity_mem_write_cycles + 1;
                activity_port_a_write_cycles <= activity_port_a_write_cycles + 1;
                activity_mem_writes <= activity_mem_writes + 1;
            end
        end
    end

    function automatic bit txn_dims_valid(input gemm_txn tx);
        begin
            txn_dims_valid = (tx.m_dim >= `GEMM_DIM_MIN) && (tx.m_dim <= `GEMM_DIM_MAX) &&
                             (tx.n_dim >= `GEMM_DIM_MIN) && (tx.n_dim <= `GEMM_DIM_MAX) &&
                             (tx.k_dim >= `GEMM_DIM_MIN) && (tx.k_dim <= `GEMM_DIM_MAX);
        end
    endfunction

    function automatic bit file_exists(input string path);
        int fd;
        begin
            fd = $fopen(path, "r");
            if (fd == 0) begin
                file_exists = 1'b0;
            end
            else begin
                $fclose(fd);
                file_exists = 1'b1;
            end
        end
    endfunction

    task automatic log_line(input string line);
        begin
            $display("%s", line);
            if (result_files_enabled) begin
                $fdisplay(run_log_fd, "%s", line);
            end
        end
    endtask

    task automatic open_result_files();
        begin
            result_files_enabled = 1'b0;
            if ($value$plusargs("RESULT_DIR=%s", result_dir)) begin
                result_files_enabled = 1'b1;

                case_results_fd = $fopen({result_dir, "/case_results.tsv"}, "w");
                failure_details_fd = $fopen({result_dir, "/failure_details.tsv"}, "w");
                run_log_fd = $fopen({result_dir, "/run.log"}, "w");
                if (case_results_fd == 0 || failure_details_fd == 0 || run_log_fd == 0) begin
                    $fatal(1, "failed to open result files in RESULT_DIR=%s", result_dir);
                end

                $fdisplay(case_results_fd,
                          "txn_id\ttxn_name\tvector_set\tinit_mem\texpected_mem\tm\tn\tk\ta_base\tb_base\tc_base\texpected_status\tactual_status\tdone\terror\tinvalid_size\tcycles\tbusy_cycles\tidle_cycles\tload_cycles\tcompute_cycles\tstore_cycles\tdone_cycles\tmem_read_cycles\tmem_write_cycles\tport_a_read_cycles\tport_b_read_cycles\tport_a_write_cycles\tdual_read_cycles\tmem_write_count\tc_compare_count\tc_mismatch_count\ttimeout\tresult\tfail_reason");
                $fdisplay(failure_details_fd,
                          "txn_id\ttxn_name\tfailure_type\tlocation\texpected\tactual\tcycle\tdetail");
            end
        end
    endtask

    task automatic close_result_files();
        begin
            if (result_files_enabled) begin
                $fclose(case_results_fd);
                $fclose(failure_details_fd);
                $fclose(run_log_fd);
            end
        end
    endtask

    task automatic write_failure_detail(
        input gemm_txn tx,
        input string failure_type,
        input string location,
        input string expected,
        input string actual,
        input int cycle,
        input string detail
    );
        begin
            if (result_files_enabled) begin
                $fdisplay(failure_details_fd, "%0d\t%s\t%s\t%s\t%s\t%s\t%0d\t%s",
                          tx.txn_id, tx.case_name, failure_type, location,
                          expected, actual, cycle, detail);
            end
        end
    endtask

    task automatic write_case_result(
        input gemm_obs obs,
        input int c_compare_count,
        input int c_mismatch_count,
        input string result,
        input string fail_reason
    );
        int done_bit;
        int error_bit;
        int invalid_size_bit;
        begin
            if (result_files_enabled) begin
                done_bit = obs.status[`GEMM_ST_DONE_BIT] ? 1 : 0;
                error_bit = obs.status[`GEMM_ST_ERROR_BIT] ? 1 : 0;
                invalid_size_bit = obs.status[`GEMM_ST_INVSIZE_BIT] ? 1 : 0;

                $fdisplay(case_results_fd,
                          "%0d\t%s\t%s\t%s\t%s\t%0d\t%0d\t%0d\t0x%08h\t0x%08h\t0x%08h\t0x%08h\t0x%08h\t%0d\t%0d\t%0d\t%0d\t%0d\t%0d\t%0d\t%0d\t%0d\t%0d\t%0d\t%0d\t%0d\t%0d\t%0d\t%0d\t%0d\t%0d\t%0d\t%0d\t%s\t%s",
                          obs.tx.txn_id,
                          obs.tx.case_name,
                          vector_set,
                          obs.tx.init_mem_name,
                          obs.tx.expected_mem_name,
                          obs.tx.m_dim,
                          obs.tx.n_dim,
                          obs.tx.k_dim,
                          obs.tx.a_base,
                          obs.tx.b_base,
                          obs.tx.c_base,
                          obs.tx.exp_status,
                          obs.status,
                          done_bit,
                          error_bit,
                          invalid_size_bit,
                          obs.cycles,
                          obs.busy_cycles,
                          obs.idle_cycles,
                          obs.load_cycles,
                          obs.compute_cycles,
                          obs.store_cycles,
                          obs.done_cycles,
                          obs.mem_read_cycles,
                          obs.mem_write_cycles,
                          obs.port_a_read_cycles,
                          obs.port_b_read_cycles,
                          obs.port_a_write_cycles,
                          obs.dual_read_cycles,
                          obs.mem_write_count,
                          c_compare_count,
                          c_mismatch_count,
                          obs.timeout ? 1 : 0,
                          result,
                          fail_reason);
            end
        end
    endtask

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

    task automatic mmio_write_counted_start(input logic [31:0] data);
        begin
            @(negedge clk);
            activity_count_enable = 1'b1;
            mmio_sel = 1'b1;
            mmio_we = 1'b1;
            mmio_off = `GEMM_OFF_CTRL;
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

    task automatic clear_activity_counters();
        begin
            @(negedge clk);
            activity_count_enable = 1'b0;
            activity_count_clear = 1'b1;
            @(posedge clk);
            @(negedge clk);
            activity_count_clear = 1'b0;
        end
    endtask

    task automatic stop_activity_counters(
        output int cycles,
        output int busy_cycles,
        output int idle_cycles,
        output int load_cycles,
        output int compute_cycles,
        output int store_cycles,
        output int done_cycles,
        output int mem_read_cycles,
        output int mem_write_cycles,
        output int port_a_read_cycles,
        output int port_b_read_cycles,
        output int port_a_write_cycles,
        output int dual_read_cycles,
        output int mem_write_count
    );
        begin
            @(negedge clk);
            activity_count_enable = 1'b0;
            cycles = activity_cycles;
            busy_cycles = activity_busy_cycles;
            idle_cycles = activity_idle_cycles;
            load_cycles = activity_load_cycles;
            compute_cycles = activity_compute_cycles;
            store_cycles = activity_store_cycles;
            done_cycles = activity_done_cycles;
            mem_read_cycles = activity_mem_read_cycles;
            mem_write_cycles = activity_mem_write_cycles;
            port_a_read_cycles = activity_port_a_read_cycles;
            port_b_read_cycles = activity_port_b_read_cycles;
            port_a_write_cycles = activity_port_a_write_cycles;
            dual_read_cycles = activity_dual_read_cycles;
            mem_write_count = activity_mem_writes;
        end
    endtask

    task automatic check_addr_12bit(
        input gemm_txn tx,
        input string label,
        input logic [31:0] addr,
        input int cycle,
        output int case_errors
    );
        begin
            case_errors = 0;
            if (addr[31:12] != 20'd0) begin
                log_line($sformatf("[FAIL] %s %s address has nonzero high bits: 0x%08h",
                                   tx.case_name, label, addr));
                write_failure_detail(tx, "OUT_OF_RANGE_ADDRESS", label,
                                     "12-bit address", $sformatf("0x%08h", addr),
                                     cycle, "base address has nonzero high bits");
                case_errors++;
            end
        end
    endtask

    task automatic compare_c_memory(
        input gemm_txn tx,
        input int cycle,
        output int compare_count,
        output int mismatch_count,
        output int range_errors
    );
        int row;
        int col;
        int idx;
        int unsigned mem_index;
        int detail_count;
        logic [31:0] c_addr;
        begin
            compare_count = 0;
            mismatch_count = 0;
            range_errors = 0;
            detail_count = 0;

            if (!txn_dims_valid(tx)) begin
                return;
            end

            for (row = 0; row < tx.m_dim; row++) begin
                for (col = 0; col < tx.n_dim; col++) begin
                    idx = row * tx.n_dim + col;
                    c_addr = tx.c_base + idx;
                    mem_index = int'(c_addr[11:0]);
                    if (c_addr[31:12] != 20'd0 || mem_index >= MEMORY_WORDS) begin
                        log_line($sformatf("[FAIL] %s C[%0d][%0d] address out of range: 0x%08h",
                                           tx.case_name, row, col, c_addr));
                        if (detail_count < MAX_FAILURE_DETAILS) begin
                            write_failure_detail(tx, "OUT_OF_RANGE_ADDRESS",
                                                 $sformatf("C[%0d][%0d]", row, col),
                                                 "valid data memory address",
                                                 $sformatf("0x%08h", c_addr),
                                                 cycle, "C result address is outside memory");
                        end
                        detail_count++;
                        range_errors++;
                    end
                    else begin
                        compare_count++;
                        if (mem[mem_index] !== expected_mem[mem_index]) begin
                            if (detail_count < MAX_FAILURE_DETAILS) begin
                                log_line($sformatf("[FAIL] %s C[%0d][%0d] addr=0x%03h got=0x%08h expected=0x%08h",
                                                   tx.case_name, row, col, mem_index,
                                                   mem[mem_index], expected_mem[mem_index]));
                                write_failure_detail(tx, "C_MISMATCH",
                                                     $sformatf("C[%0d][%0d] addr=0x%03h", row, col, mem_index),
                                                     $sformatf("0x%08h", expected_mem[mem_index]),
                                                     $sformatf("0x%08h", mem[mem_index]),
                                                     cycle, "result memory mismatch");
                            end
                            detail_count++;
                            mismatch_count++;
                        end
                    end
                end
            end

            if (mismatch_count != 0) begin
                log_line($sformatf("[FAIL] %s C mismatch count=%0d", tx.case_name, mismatch_count));
            end
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
        int txn_id;
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

            txn_id = 0;
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
                tx.txn_id = txn_id;
                tx.case_name = case_name;
                tx.init_mem_name = init_mem_name;
                tx.expected_mem_name = expected_mem_name;
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
                txn_id++;
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

                obs = new();
                obs.is_last = 1'b0;
                obs.tx = tx;
                obs.status = 32'd0;
                obs.monitor_errors = 0;
                obs.cycles = 0;
                obs.busy_cycles = 0;
                obs.idle_cycles = 0;
                obs.load_cycles = 0;
                obs.compute_cycles = 0;
                obs.store_cycles = 0;
                obs.done_cycles = 0;
                obs.mem_read_cycles = 0;
                obs.mem_write_cycles = 0;
                obs.port_a_read_cycles = 0;
                obs.port_b_read_cycles = 0;
                obs.port_a_write_cycles = 0;
                obs.dual_read_cycles = 0;
                obs.mem_write_count = 0;
                obs.timeout = 1'b0;
                obs.missing_init_mem = !file_exists(tx.init_mem_path);
                obs.missing_expected_mem = !file_exists(tx.expected_mem_path);
                obs.ran_dut = 1'b0;

                if (obs.missing_init_mem || obs.missing_expected_mem) begin
                    mon2sb.put(obs);
                end
                else begin
                    $readmemh(tx.init_mem_path, mem);
                    $readmemh(tx.expected_mem_path, expected_mem);
                    reset_dut();

                    mmio_write(`GEMM_OFF_A_BASE, tx.a_base);
                    mmio_write(`GEMM_OFF_B_BASE, tx.b_base);
                    mmio_write(`GEMM_OFF_C_BASE, tx.c_base);
                    mmio_write(`GEMM_OFF_M, tx.m_dim);
                    mmio_write(`GEMM_OFF_N, tx.n_dim);
                    mmio_write(`GEMM_OFF_K, tx.k_dim);

                    clear_activity_counters();
                    obs.ran_dut = 1'b1;
                    mmio_write_counted_start(32'h0000_0001);

                    monitor_transaction(tx, obs.status, obs.timeout, obs.monitor_errors);
                    stop_activity_counters(obs.cycles,
                                           obs.busy_cycles,
                                           obs.idle_cycles,
                                           obs.load_cycles,
                                           obs.compute_cycles,
                                           obs.store_cycles,
                                           obs.done_cycles,
                                           obs.mem_read_cycles,
                                           obs.mem_write_cycles,
                                           obs.port_a_read_cycles,
                                           obs.port_b_read_cycles,
                                           obs.port_a_write_cycles,
                                           obs.dual_read_cycles,
                                           obs.mem_write_count);

                    mon2sb.put(obs);
                end

                sb_ack.get(ack_value);
                if (ack_value != 1) begin
                    $fatal(1, "unexpected scoreboard acknowledgement value: %0d", ack_value);
                end
                if (obs.ran_dut) begin
                    mmio_write(`GEMM_OFF_CTRL, 32'h0000_0002);
                end
            end
        end
    endtask

    // Monitor: observe completion through STATUS, not internal state.
    task automatic monitor_transaction(
        input gemm_txn tx,
        output logic [31:0] status,
        output bit timeout,
        output int monitor_errors
    );
        int cycles;
        begin
            monitor_errors = 0;
            timeout = 1'b0;
            status = 32'd0;
            for (cycles = 0; cycles < DONE_TIMEOUT_CYCLES; cycles++) begin
                mmio_read(`GEMM_OFF_STATUS, status);
                if (status[`GEMM_ST_DONE_BIT]) begin
                    return;
                end
                @(posedge clk);
            end

            log_line($sformatf("[FAIL] %s timed out: status=0x%08h busy=%0b state=%0d",
                               tx.case_name, status, busy, state_debug));
            timeout = 1'b1;
            monitor_errors++;
        end
    endtask

    // Scoreboard: compare observed status and memory against golden outputs.
    task automatic scoreboard();
        gemm_obs obs;
        int case_errors;
        int local_errors;
        int c_compare_count;
        int c_mismatch_count;
        int range_errors;
        string fail_reason;
        string result_text;
        begin
            forever begin
                mon2sb.get(obs);
                if (obs.is_last) begin
                    break;
                end

                case_errors = 0;
                c_compare_count = 0;
                c_mismatch_count = 0;
                fail_reason = "";

                if (obs.missing_init_mem) begin
                    write_failure_detail(obs.tx, "MISSING_INIT_MEM", obs.tx.init_mem_name,
                                         "readable file", obs.tx.init_mem_path,
                                         obs.cycles, "initial memory image is missing");
                    case_errors++;
                    fail_reason = "MISSING_INIT_MEM";
                end

                if (obs.missing_expected_mem) begin
                    write_failure_detail(obs.tx, "MISSING_EXPECTED_MEM", obs.tx.expected_mem_name,
                                         "readable file", obs.tx.expected_mem_path,
                                         obs.cycles, "expected memory image is missing");
                    case_errors++;
                    if (fail_reason.len() == 0) begin
                        fail_reason = "MISSING_EXPECTED_MEM";
                    end
                end

                if (!obs.missing_init_mem && !obs.missing_expected_mem) begin
                    if (obs.timeout) begin
                        write_failure_detail(obs.tx, "TIMEOUT", "status.done",
                                             "1", "0", obs.cycles,
                                             "DUT did not finish before timeout");
                        case_errors++;
                        if (fail_reason.len() == 0) begin
                            fail_reason = "TIMEOUT";
                        end
                    end

                    check_addr_12bit(obs.tx, "A_BASE", obs.tx.a_base, obs.cycles, local_errors);
                    case_errors += local_errors;
                    if (local_errors != 0 && fail_reason.len() == 0) begin
                        fail_reason = "OUT_OF_RANGE_ADDRESS";
                    end
                    check_addr_12bit(obs.tx, "B_BASE", obs.tx.b_base, obs.cycles, local_errors);
                    case_errors += local_errors;
                    if (local_errors != 0 && fail_reason.len() == 0) begin
                        fail_reason = "OUT_OF_RANGE_ADDRESS";
                    end
                    check_addr_12bit(obs.tx, "C_BASE", obs.tx.c_base, obs.cycles, local_errors);
                    case_errors += local_errors;
                    if (local_errors != 0 && fail_reason.len() == 0) begin
                        fail_reason = "OUT_OF_RANGE_ADDRESS";
                    end

                    if (obs.status !== obs.tx.exp_status) begin
                        log_line($sformatf("[FAIL] %s status got=0x%08h expected=0x%08h",
                                           obs.tx.case_name, obs.status, obs.tx.exp_status));
                        write_failure_detail(obs.tx, "STATUS_MISMATCH", "status",
                                             $sformatf("0x%08h", obs.tx.exp_status),
                                             $sformatf("0x%08h", obs.status),
                                             obs.cycles, "status bits differ");
                        case_errors++;
                        if (fail_reason.len() == 0) begin
                            fail_reason = "STATUS_MISMATCH";
                        end
                    end

                    if (!txn_dims_valid(obs.tx) && obs.mem_write_count != 0) begin
                        log_line($sformatf("[FAIL] %s invalid transaction wrote memory: mem_write_count=%0d",
                                           obs.tx.case_name, obs.mem_write_count));
                        write_failure_detail(obs.tx, "MEM_WRITE_ON_INVALID", "mem_we",
                                             "0", $sformatf("%0d", obs.mem_write_count),
                                             obs.cycles, "invalid transaction caused memory write");
                        case_errors++;
                        if (fail_reason.len() == 0) begin
                            fail_reason = "MEM_WRITE_ON_INVALID";
                        end
                    end

                    if (!obs.timeout) begin
                        compare_c_memory(obs.tx, obs.cycles, c_compare_count, c_mismatch_count, range_errors);
                        case_errors += range_errors;
                        if (range_errors != 0 && fail_reason.len() == 0) begin
                            fail_reason = "OUT_OF_RANGE_ADDRESS";
                        end
                        case_errors += c_mismatch_count;
                        if (c_mismatch_count != 0 && fail_reason.len() == 0) begin
                            fail_reason = "C_MISMATCH";
                        end
                    end
                end

                result_text = (case_errors == 0) ? "PASS" : "FAIL";
                write_case_result(obs, c_compare_count, c_mismatch_count, result_text, fail_reason);

                total_cases++;
                if (case_errors == 0) begin
                    passed_cases++;
                    log_line($sformatf("[TXN %0d] %s PASS cycles=%0d load=%0d compute=%0d store=%0d dual_reads=%0d mem_writes=%0d c_mismatch=%0d",
                                       obs.tx.txn_id, obs.tx.case_name,
                                       obs.cycles, obs.load_cycles, obs.compute_cycles,
                                       obs.store_cycles, obs.dual_read_cycles, obs.mem_write_count, c_mismatch_count));
                end
                else begin
                    total_errors += case_errors;
                    log_line($sformatf("[TXN %0d] %s FAIL reason=%s errors=%0d cycles=%0d load=%0d compute=%0d store=%0d dual_reads=%0d mem_writes=%0d c_mismatch=%0d",
                                       obs.tx.txn_id, obs.tx.case_name, fail_reason,
                                       case_errors, obs.cycles, obs.load_cycles,
                                       obs.compute_cycles, obs.store_cycles,
                                       obs.dual_read_cycles, obs.mem_write_count, c_mismatch_count));
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
        mem_rdata_a = 32'd0;
        mem_rdata_b = 32'd0;
        activity_count_clear = 1'b0;
        activity_count_enable = 1'b0;
        activity_cycles = 0;
        activity_busy_cycles = 0;
        activity_idle_cycles = 0;
        activity_load_cycles = 0;
        activity_compute_cycles = 0;
        activity_store_cycles = 0;
        activity_done_cycles = 0;
        activity_mem_read_cycles = 0;
        activity_mem_write_cycles = 0;
        activity_port_a_read_cycles = 0;
        activity_port_b_read_cycles = 0;
        activity_port_a_write_cycles = 0;
        activity_dual_read_cycles = 0;
        activity_mem_writes = 0;
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
        if (!$value$plusargs("VECTOR_SET=%s", vector_set)) begin
            vector_set = "unknown";
        end
        if (!$value$plusargs("RUN_ID=%s", run_id)) begin
            run_id = "manual";
        end

        open_result_files();

        if (!$value$plusargs("DUMPFILE=%s", dumpfile_path)) begin
            if (result_files_enabled) begin
                dumpfile_path = {result_dir, "/tb_gemm_vectors_compat.fst"};
            end
            else begin
                dumpfile_path = "tb_gemm_vectors_compat.fst";
            end
        end
        $dumpfile(dumpfile_path);
        $dumpvars(0, tb_gemm_vectors_compat);

        log_line("== GEMM compatibility transaction replay ==");
        log_line($sformatf("  run_id:     %s", run_id));
        log_line($sformatf("  vector_set: %s", vector_set));
        log_line($sformatf("  vector_dir: %s", vector_dir));
        log_line($sformatf("  cases:      %s", cases_path));
        log_line($sformatf("  MAC_MODE:   %0d", MAC_MODE));

        fork
            generator();
            driver();
            scoreboard();
        join

        log_line($sformatf("[SUMMARY] total=%0d pass=%0d fail=%0d errors=%0d",
                           total_cases, passed_cases,
                           total_cases - passed_cases, total_errors));
        $display("==== %s : %0d/%0d transaction(s), %0d error(s) ====",
                 (total_errors == 0) ? "ALL PASS" : "TESTS FAILED",
                 passed_cases, total_cases, total_errors);

        close_result_files();

        if (total_cases == 0) begin
            $fatal(1, "no vector cases were run");
        end
        if (total_errors != 0) begin
            $fatal(1, "GEMM compatibility vector replay failed");
        end
        $finish;
    end

endmodule
