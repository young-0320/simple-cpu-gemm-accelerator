`timescale 1ns / 1ps
`include "define.vh"
`include "gemm_define.vh"

// =======================================================
// tb_gemm_system_v2
//   CPU-driven system-level verification for rtl_v2.
//   The bench preloads the shared system memory, lets top_cpu issue the
//   GEMM MMIO sequence, then checks C memory against a local golden model.
// =======================================================
/* verilator lint_off UNUSEDSIGNAL */
module tb_gemm_system_v2 #(
    parameter int MAC_MODE = 4,
    parameter int MEMORY_WORDS = 4096,
    parameter int DONE_TIMEOUT_CYCLES = 12000,
    parameter int MAX_FAILURE_DETAILS = 16
);

    localparam logic [31:0] DATA_BASE_START = 32'h0000_0100;
    localparam logic [31:0] CASE_BASE_STRIDE = 32'h0000_0040;
    localparam logic [31:0] B_BASE_OFFSET = 32'h0000_0010;
    localparam logic [31:0] C_BASE_OFFSET = 32'h0000_0020;
    localparam logic [31:0] STATUS_DONE = 32'h0000_0002;
    localparam logic [31:0] STATUS_INVALID_DIM = 32'h0000_000E;
    localparam logic [31:0] C_SENTINEL = 32'hDEAD_BEEF;
    localparam logic [11:0] CPU_STATUS_OUT_PC = 12'd19;
    localparam logic [11:0] CPU_DONE_PC = 12'd23;

    localparam logic [11:0] MMIO_A_BASE = 12'hFF0;
    localparam logic [11:0] MMIO_B_BASE = 12'hFF1;
    localparam logic [11:0] MMIO_C_BASE = 12'hFF2;
    localparam logic [11:0] MMIO_M      = 12'hFF3;
    localparam logic [11:0] MMIO_N      = 12'hFF4;
    localparam logic [11:0] MMIO_K      = 12'hFF5;
    localparam logic [11:0] MMIO_CTRL   = 12'hFF6;
    localparam logic [11:0] MMIO_STATUS = 12'hFF7;

    logic clk = 1'b0;
    logic reset;
    logic [8:0] in_port;
    wire [3:0] out_port;
    wire [11:0] pc_debug;
    wire [31:0] acc_debug;
    wire gemm_busy_debug;
    wire [2:0] gemm_state_debug;

    string result_dir;
    string run_id;
    string dumpfile_path;
    bit result_files_enabled;
    int case_results_fd;
    int failure_details_fd;
    int run_log_fd;

    logic signed [7:0] a_values [0:15];
    logic signed [7:0] b_values [0:15];
    logic signed [31:0] golden_values [0:15];
    logic [31:0] a_base_addr;
    logic [31:0] b_base_addr;
    logic [31:0] c_base_addr;
    logic [31:0] expected_status;
    int unsigned rng_state;

    int total_cases;
    int passed_cases;
    int total_errors;

    always #5 clk <= ~clk;

    gemm_system_top #(
        .MAC_MODE(MAC_MODE)
    ) dut (
        .clk(clk),
        .reset(reset),
        .in_port(in_port),
        .out_port(out_port),
        .pc_debug(pc_debug),
        .acc_debug(acc_debug),
        .gemm_busy_debug(gemm_busy_debug),
        .gemm_state_debug(gemm_state_debug)
    );

    function automatic logic [31:0] inst_load(input logic [11:0] addr);
        begin
            inst_load = {`OP_LOAD, 16'd0, addr};
        end
    endfunction

    function automatic logic [31:0] inst_store(input logic [11:0] addr);
        begin
            inst_store = {`OP_STORE, 16'd0, addr};
        end
    endfunction

    function automatic logic [31:0] inst_loadi(input logic [27:0] imm);
        begin
            inst_loadi = {`OP_LOADI, imm};
        end
    endfunction

    function automatic logic [31:0] inst_cmpi(input logic [27:0] imm);
        begin
            inst_cmpi = {`OP_CMPI, imm};
        end
    endfunction

    function automatic logic [31:0] inst_jz(input logic [11:0] addr);
        begin
            inst_jz = {`OP_JZ, 16'd0, addr};
        end
    endfunction

    function automatic logic [31:0] inst_jmp(input logic [11:0] addr);
        begin
            inst_jmp = {`OP_JMP, 16'd0, addr};
        end
    endfunction

    function automatic logic [31:0] inst_out(input logic [3:0] port);
        begin
            inst_out = {`OP_OUT, 24'd0, port};
        end
    endfunction

    function automatic logic [31:0] pack4(
        input logic signed [7:0] l0,
        input logic signed [7:0] l1,
        input logic signed [7:0] l2,
        input logic signed [7:0] l3
    );
        begin
            pack4 = {l3[7:0], l2[7:0], l1[7:0], l0[7:0]};
        end
    endfunction

    function automatic logic signed [7:0] rand_i8();
        begin
            rng_state = (rng_state * 32'd1664525) + 32'd1013904223;
            rand_i8 = $signed(rng_state[7:0]);
        end
    endfunction

    function automatic logic [11:0] mem_addr(
        input logic [31:0] base_addr,
        input int offset
    );
        int unsigned addr;
        begin
            addr = {20'd0, base_addr[11:0]} + offset;
            mem_addr = addr[11:0];
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
                          "case_id\tcase_name\tm\tn\tk\ta_base\tb_base\tc_base\texpected_status\tactual_status\tout_port\tcycles\tbusy_cycles\tload_cycles\tcompute_cycles\tstore_cycles\tdone_cycles\tcpu_done\ttimeout\tpc_at_done\tgemm_state_at_done\tc_compare_count\tc_mismatch_count\tresult\tfail_reason");
                $fdisplay(failure_details_fd,
                          "case_id\tcase_name\tfailure_type\tlocation\texpected\tactual\tcycle\tdetail");
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
        input int case_id,
        input string case_name,
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
                          case_id, case_name, failure_type, location,
                          expected, actual, cycle, detail);
            end
        end
    endtask

    task automatic write_case_result(
        input int case_id,
        input string case_name,
        input int m_dim,
        input int n_dim,
        input int k_dim,
        input logic [31:0] actual_status,
        input int cycles,
        input int busy_cycles,
        input int load_cycles,
        input int compute_cycles,
        input int store_cycles,
        input int done_cycles,
        input bit cpu_done,
        input bit timeout,
        input logic [11:0] pc_at_done,
        input logic [2:0] gemm_state_at_done,
        input int c_compare_count,
        input int c_mismatch_count,
        input string result,
        input string fail_reason
    );
        begin
            if (result_files_enabled) begin
                $fdisplay(case_results_fd,
                          "%0d\t%s\t%0d\t%0d\t%0d\t0x%08h\t0x%08h\t0x%08h\t0x%08h\t0x%08h\t0x%01h\t%0d\t%0d\t%0d\t%0d\t%0d\t%0d\t%0d\t%0d\t0x%03h\t%0d\t%0d\t%0d\t%s\t%s",
                          case_id,
                          case_name,
                          m_dim,
                          n_dim,
                          k_dim,
                          a_base_addr,
                          b_base_addr,
                          c_base_addr,
                          expected_status,
                          actual_status,
                          out_port,
                          cycles,
                          busy_cycles,
                          load_cycles,
                          compute_cycles,
                          store_cycles,
                          done_cycles,
                          cpu_done ? 1 : 0,
                          timeout ? 1 : 0,
                          pc_at_done,
                          gemm_state_at_done,
                          c_compare_count,
                          c_mismatch_count,
                          result,
                          fail_reason);
            end
        end
    endtask

    task automatic clear_memory();
        int addr;
        begin
            for (addr = 0; addr < MEMORY_WORDS; addr++) begin
                dut.mem[addr] = 32'd0;
            end
        end
    endtask

    task automatic put_instr(inout int pc, input logic [31:0] instr);
        begin
            dut.mem[pc[11:0]] = instr;
            pc++;
        end
    endtask

    task automatic set_case_bases(input int case_id);
        int unsigned slot;
        int unsigned base_addr;
        begin
            slot = ((case_id * 7) + 3) % 32;
            base_addr = DATA_BASE_START + (slot * CASE_BASE_STRIDE);
            a_base_addr = base_addr;
            b_base_addr = base_addr + B_BASE_OFFSET;
            c_base_addr = base_addr + C_BASE_OFFSET;
        end
    endtask

    task automatic build_cpu_program(input int m_dim, input int n_dim, input int k_dim);
        int pc;
        logic [11:0] poll_pc;
        logic [11:0] jz_pc;
        logic [11:0] finish_pc;
        logic [11:0] halt_pc;
        logic [27:0] m_imm;
        logic [27:0] n_imm;
        logic [27:0] k_imm;
        begin
            m_imm = m_dim[27:0];
            n_imm = n_dim[27:0];
            k_imm = k_dim[27:0];

            pc = 0;
            put_instr(pc, inst_loadi(a_base_addr[27:0]));
            put_instr(pc, inst_store(MMIO_A_BASE));
            put_instr(pc, inst_loadi(b_base_addr[27:0]));
            put_instr(pc, inst_store(MMIO_B_BASE));
            put_instr(pc, inst_loadi(c_base_addr[27:0]));
            put_instr(pc, inst_store(MMIO_C_BASE));
            put_instr(pc, inst_loadi(m_imm));
            put_instr(pc, inst_store(MMIO_M));
            put_instr(pc, inst_loadi(n_imm));
            put_instr(pc, inst_store(MMIO_N));
            put_instr(pc, inst_loadi(k_imm));
            put_instr(pc, inst_store(MMIO_K));
            put_instr(pc, inst_loadi(28'd1));
            put_instr(pc, inst_store(MMIO_CTRL));

            poll_pc = pc[11:0];
            put_instr(pc, inst_load(MMIO_STATUS));
            put_instr(pc, inst_cmpi(expected_status[27:0]));
            jz_pc = pc[11:0];
            put_instr(pc, inst_jz(12'd0));
            put_instr(pc, inst_jmp(poll_pc));

            finish_pc = pc[11:0];
            dut.mem[jz_pc] = inst_jz(finish_pc);
            put_instr(pc, inst_out(4'd0));
            put_instr(pc, inst_loadi(28'd2));
            put_instr(pc, inst_store(MMIO_CTRL));
            put_instr(pc, inst_loadi(28'd8));
            put_instr(pc, inst_out(4'd0));

            halt_pc = pc[11:0];
            put_instr(pc, inst_jmp(halt_pc));
        end
    endtask

    task automatic mark_c_sentinel();
        int row;
        begin
            for (row = 0; row < 16; row++) begin
                dut.mem[mem_addr(c_base_addr, row)] = C_SENTINEL;
            end
        end
    endtask

    task automatic load_matrix_data(input int m_dim, input int n_dim, input int k_dim);
        int row;
        int col;
        logic signed [7:0] lanes [0:3];
        begin
            mark_c_sentinel();

            for (row = 0; row < m_dim; row++) begin
                lanes[0] = 8'sd0;
                lanes[1] = 8'sd0;
                lanes[2] = 8'sd0;
                lanes[3] = 8'sd0;
                for (col = 0; col < k_dim; col++) begin
                    lanes[col] = a_values[row * k_dim + col];
                end
                dut.mem[mem_addr(a_base_addr, row)] = pack4(lanes[0], lanes[1], lanes[2], lanes[3]);
            end

            for (row = 0; row < k_dim; row++) begin
                lanes[0] = 8'sd0;
                lanes[1] = 8'sd0;
                lanes[2] = 8'sd0;
                lanes[3] = 8'sd0;
                for (col = 0; col < n_dim; col++) begin
                    lanes[col] = b_values[row * n_dim + col];
                end
                dut.mem[mem_addr(b_base_addr, row)] = pack4(lanes[0], lanes[1], lanes[2], lanes[3]);
            end
        end
    endtask

    task automatic compute_golden(input int m_dim, input int n_dim, input int k_dim);
        int row;
        int col;
        int kk;
        int signed sum;
        begin
            for (row = 0; row < 16; row++) begin
                golden_values[row] = 32'sd0;
            end

            for (row = 0; row < m_dim; row++) begin
                for (col = 0; col < n_dim; col++) begin
                    sum = 0;
                    for (kk = 0; kk < k_dim; kk++) begin
                        sum += $signed(a_values[row * k_dim + kk]) *
                               $signed(b_values[kk * n_dim + col]);
                    end
                    golden_values[row * n_dim + col] = sum;
                end
            end
        end
    endtask

    task automatic reset_system();
        begin
            reset = 1'b1;
            in_port = 9'd0;
            repeat (3) @(posedge clk);
            reset = 1'b0;
            repeat (1) @(posedge clk);
        end
    endtask

    task automatic run_until_cpu_done(
        output bit cpu_done,
        output bit timeout,
        output int cycles,
        output int busy_cycles,
        output int load_cycles,
        output int compute_cycles,
        output int store_cycles,
        output int done_cycles,
        output logic [31:0] observed_status,
        output logic [11:0] pc_at_done,
        output logic [2:0] gemm_state_at_done
    );
        begin
            cpu_done = 1'b0;
            timeout = 1'b0;
            cycles = 0;
            busy_cycles = 0;
            load_cycles = 0;
            compute_cycles = 0;
            store_cycles = 0;
            done_cycles = 0;
            observed_status = 32'hFFFF_FFFF;
            pc_at_done = 12'd0;
            gemm_state_at_done = `GEMM_S_IDLE;

            while (cycles < DONE_TIMEOUT_CYCLES && !cpu_done) begin
                @(posedge clk);
                cycles++;
                if (gemm_busy_debug) begin
                    busy_cycles++;
                end
                case (gemm_state_debug)
                    `GEMM_S_LOAD:    load_cycles++;
                    `GEMM_S_COMPUTE: compute_cycles++;
                    `GEMM_S_STORE:   store_cycles++;
                    `GEMM_S_DONE:    done_cycles++;
                    default: ;
                endcase

                if (pc_debug >= CPU_STATUS_OUT_PC && pc_debug < CPU_DONE_PC && out_port != 4'h8) begin
                    observed_status = {28'd0, out_port};
                end

                if (out_port == 4'h8 && pc_debug == CPU_DONE_PC) begin
                    cpu_done = 1'b1;
                    pc_at_done = pc_debug;
                    gemm_state_at_done = gemm_state_debug;
                end
            end

            if (!cpu_done) begin
                timeout = 1'b1;
                pc_at_done = pc_debug;
                gemm_state_at_done = gemm_state_debug;
            end
        end
    endtask

    task automatic compare_c_memory(
        input int case_id,
        input string case_name,
        input int m_dim,
        input int n_dim,
        input int cycle,
        output int compare_count,
        output int mismatch_count
    );
        int row;
        int col;
        int idx;
        logic [11:0] addr;
        int detail_count;
        logic [31:0] expected_word;
        logic [31:0] actual_word;
        begin
            compare_count = 0;
            mismatch_count = 0;
            detail_count = 0;

            for (row = 0; row < m_dim; row++) begin
                for (col = 0; col < n_dim; col++) begin
                    idx = row * n_dim + col;
                    addr = mem_addr(c_base_addr, idx);
                    expected_word = golden_values[idx];
                    actual_word = dut.mem[addr];
                    compare_count++;
                    if (actual_word !== expected_word) begin
                        mismatch_count++;
                        if (detail_count < MAX_FAILURE_DETAILS) begin
                            log_line($sformatf("[FAIL] %s C[%0d][%0d] addr=0x%03h got=0x%08h expected=0x%08h",
                                               case_name, row, col, addr, actual_word, expected_word));
                            write_failure_detail(case_id, case_name, "C_MISMATCH",
                                                 $sformatf("C[%0d][%0d] addr=0x%03h", row, col, addr),
                                                 $sformatf("0x%08h", expected_word),
                                                 $sformatf("0x%08h", actual_word),
                                                 cycle,
                                                 "CPU-driven GEMM result memory mismatch");
                        end
                        detail_count++;
                    end
                end
            end
        end
    endtask

    task automatic compare_c_unchanged(
        input int case_id,
        input string case_name,
        input int cycle,
        output int compare_count,
        output int mismatch_count
    );
        int idx;
        logic [11:0] addr;
        logic [31:0] actual_word;
        int detail_count;
        begin
            compare_count = 0;
            mismatch_count = 0;
            detail_count = 0;

            for (idx = 0; idx < 16; idx++) begin
                addr = mem_addr(c_base_addr, idx);
                actual_word = dut.mem[addr];
                compare_count++;
                if (actual_word !== C_SENTINEL) begin
                    mismatch_count++;
                    if (detail_count < MAX_FAILURE_DETAILS) begin
                        log_line($sformatf("[FAIL] %s invalid transaction touched C addr=0x%03h got=0x%08h",
                                           case_name, addr, actual_word));
                        write_failure_detail(case_id, case_name, "C_TOUCHED",
                                             $sformatf("C sentinel addr=0x%03h", addr),
                                             $sformatf("0x%08h", C_SENTINEL),
                                             $sformatf("0x%08h", actual_word),
                                             cycle,
                                             "Invalid dimensions must not modify result memory");
                    end
                    detail_count++;
                end
            end
        end
    endtask

    task automatic run_case(
        input int case_id,
        input string case_name,
        input int m_dim,
        input int n_dim,
        input int k_dim,
        input bit expect_valid
    );
        bit cpu_done;
        bit timeout;
        int cycles;
        int busy_cycles;
        int load_cycles;
        int compute_cycles;
        int store_cycles;
        int done_cycles;
        int c_compare_count;
        int c_mismatch_count;
        int case_errors;
        logic [11:0] pc_at_done;
        logic [2:0] gemm_state_at_done;
        logic [31:0] actual_status;
        logic [31:0] observed_status;
        string result_text;
        string fail_reason;
        begin
            set_case_bases(case_id);
            expected_status = expect_valid ? STATUS_DONE : STATUS_INVALID_DIM;

            clear_memory();
            build_cpu_program(m_dim, n_dim, k_dim);
            if (expect_valid) begin
                load_matrix_data(m_dim, n_dim, k_dim);
                compute_golden(m_dim, n_dim, k_dim);
            end
            else begin
                mark_c_sentinel();
            end

            reset_system();
            run_until_cpu_done(cpu_done, timeout, cycles, busy_cycles,
                               load_cycles, compute_cycles, store_cycles,
                               done_cycles, observed_status, pc_at_done,
                               gemm_state_at_done);

            c_compare_count = 0;
            c_mismatch_count = 0;
            case_errors = 0;
            fail_reason = "";
            actual_status = cpu_done ? observed_status : dut.u_gemm.u_mmio.status_word;

            if (!cpu_done) begin
                case_errors++;
                fail_reason = timeout ? "TIMEOUT" : "CPU_NOT_DONE";
                write_failure_detail(case_id, case_name, fail_reason,
                                     "out_port", "0x8", $sformatf("0x%01h", out_port),
                                     cycles, "CPU did not reach the completion OUT instruction");
            end
            else if (actual_status !== expected_status) begin
                case_errors++;
                fail_reason = "STATUS_MISMATCH";
                write_failure_detail(case_id, case_name, "STATUS_MISMATCH",
                                     "GEMM_STATUS", $sformatf("0x%08h", expected_status),
                                     $sformatf("0x%08h", actual_status),
                                     cycles, "CPU-observed GEMM status did not match expectation");
            end
            else if (expect_valid) begin
                compare_c_memory(case_id, case_name, m_dim, n_dim, cycles,
                                 c_compare_count, c_mismatch_count);
                case_errors += c_mismatch_count;
                if (c_mismatch_count != 0) begin
                    fail_reason = "C_MISMATCH";
                end
            end
            else begin
                compare_c_unchanged(case_id, case_name, cycles,
                                    c_compare_count, c_mismatch_count);
                case_errors += c_mismatch_count;
                if (c_mismatch_count != 0) begin
                    fail_reason = "C_TOUCHED";
                end

                if (load_cycles != 0 || compute_cycles != 0 || store_cycles != 0) begin
                    case_errors++;
                    if (fail_reason == "") begin
                        fail_reason = "INVALID_RAN_PIPELINE";
                    end
                    write_failure_detail(case_id, case_name, "INVALID_RAN_PIPELINE",
                                         "gemm_phase_cycles", "load/compute/store all 0",
                                         $sformatf("%0d/%0d/%0d", load_cycles, compute_cycles, store_cycles),
                                         cycles,
                                         "Invalid dimensions must finish without entering GEMM data phases");
                end
            end

            result_text = (case_errors == 0) ? "PASS" : "FAIL";
            write_case_result(case_id, case_name, m_dim, n_dim, k_dim,
                              actual_status, cycles, busy_cycles,
                              load_cycles, compute_cycles, store_cycles,
                              done_cycles, cpu_done, timeout, pc_at_done,
                              gemm_state_at_done, c_compare_count,
                              c_mismatch_count, result_text, fail_reason);

            total_cases++;
            if (case_errors == 0) begin
                passed_cases++;
                log_line($sformatf("[CASE %0d] %s PASS M=%0d N=%0d K=%0d cycles=%0d busy=%0d c_compare=%0d",
                                   case_id, case_name, m_dim, n_dim, k_dim,
                                   cycles, busy_cycles, c_compare_count));
            end
            else begin
                total_errors += case_errors;
                log_line($sformatf("[CASE %0d] %s FAIL reason=%s errors=%0d cycles=%0d c_mismatch=%0d",
                                   case_id, case_name, fail_reason, case_errors,
                                   cycles, c_mismatch_count));
            end
        end
    endtask

    task automatic set_directed_2x2();
        begin
            a_values[0] = 8'sd1; a_values[1] = 8'sd2;
            a_values[2] = 8'sd3; a_values[3] = 8'sd4;
            b_values[0] = 8'sd5; b_values[1] = 8'sd6;
            b_values[2] = 8'sd7; b_values[3] = 8'sd8;
        end
    endtask

    task automatic set_directed_4x4();
        int idx;
        begin
            for (idx = 0; idx < 16; idx++) begin
                a_values[idx] = $signed(8'(idx - 8));
                b_values[idx] = $signed(8'(5 - idx));
            end
        end
    endtask

    task automatic set_random_case(input int m_dim, input int n_dim, input int k_dim);
        int idx;
        begin
            for (idx = 0; idx < 16; idx++) begin
                a_values[idx] = 8'sd0;
                b_values[idx] = 8'sd0;
            end
            for (idx = 0; idx < m_dim * k_dim; idx++) begin
                a_values[idx] = rand_i8();
            end
            for (idx = 0; idx < k_dim * n_dim; idx++) begin
                b_values[idx] = rand_i8();
            end
        end
    endtask

    task automatic random_dims(input int selector, output int m_dim, output int n_dim, output int k_dim);
        begin
            case (selector)
                0: begin m_dim = 1; n_dim = 1; k_dim = 1; end
                1: begin m_dim = 1; n_dim = 2; k_dim = 3; end
                2: begin m_dim = 2; n_dim = 2; k_dim = 2; end
                3: begin m_dim = 2; n_dim = 3; k_dim = 4; end
                4: begin m_dim = 3; n_dim = 3; k_dim = 3; end
                5: begin m_dim = 3; n_dim = 4; k_dim = 2; end
                6: begin m_dim = 4; n_dim = 4; k_dim = 4; end
                7: begin m_dim = 4; n_dim = 1; k_dim = 4; end
                8: begin m_dim = 1; n_dim = 4; k_dim = 4; end
                default: begin m_dim = 4; n_dim = 4; k_dim = 1; end
            endcase
        end
    endtask

    initial begin
        int case_id;
        int trial;
        int m_dim;
        int n_dim;
        int k_dim;
        string case_name;

        reset = 1'b1;
        in_port = 9'd0;
        rng_state = 32'h5A17_2026;
        total_cases = 0;
        passed_cases = 0;
        total_errors = 0;

        if (!$value$plusargs("RUN_ID=%s", run_id)) begin
            run_id = "manual";
        end

        open_result_files();

        if (!$value$plusargs("DUMPFILE=%s", dumpfile_path)) begin
            if (result_files_enabled) begin
                dumpfile_path = {result_dir, "/tb_gemm_system_v2.fst"};
            end
            else begin
                dumpfile_path = "tb_gemm_system_v2.fst";
            end
        end
        $dumpfile(dumpfile_path);
        $dumpvars(0, tb_gemm_system_v2);

        log_line("== GEMM rtl_v2 CPU-driven system verification ==");
        log_line($sformatf("  run_id:   %s", run_id));
        log_line($sformatf("  MAC_MODE: %0d", MAC_MODE));

        case_id = 0;

        set_directed_2x2();
        run_case(case_id, "directed_2x2x2", 2, 2, 2, 1'b1);
        case_id++;

        set_directed_4x4();
        run_case(case_id, "directed_4x4x4_signed", 4, 4, 4, 1'b1);
        case_id++;

        for (trial = 0; trial < 10; trial++) begin
            random_dims(trial, m_dim, n_dim, k_dim);
            set_random_case(m_dim, n_dim, k_dim);
            case_name = $sformatf("random_%02d_%0dx%0dx%0d", trial, m_dim, n_dim, k_dim);
            run_case(case_id, case_name, m_dim, n_dim, k_dim, 1'b1);
            case_id++;
        end

        set_random_case(4, 4, 4);
        run_case(case_id, "invalid_m_zero", 0, 2, 2, 1'b0);
        case_id++;

        set_random_case(4, 4, 4);
        run_case(case_id, "invalid_n_zero", 2, 0, 2, 1'b0);
        case_id++;

        set_random_case(4, 4, 4);
        run_case(case_id, "invalid_k_zero", 2, 2, 0, 1'b0);
        case_id++;

        set_random_case(4, 4, 4);
        run_case(case_id, "invalid_m_overflow", 5, 2, 2, 1'b0);
        case_id++;

        set_random_case(4, 4, 4);
        run_case(case_id, "invalid_n_overflow", 2, 5, 2, 1'b0);
        case_id++;

        set_random_case(4, 4, 4);
        run_case(case_id, "invalid_k_overflow", 2, 2, 5, 1'b0);
        case_id++;

        log_line($sformatf("[SUMMARY] total=%0d pass=%0d fail=%0d errors=%0d",
                           total_cases, passed_cases,
                           total_cases - passed_cases, total_errors));
        $display("==== %s : %0d/%0d case(s), %0d error(s) ====",
                 (total_errors == 0) ? "ALL PASS" : "TESTS FAILED",
                 passed_cases, total_cases, total_errors);

        close_result_files();

        if (total_cases == 0) begin
            $fatal(1, "no system cases were run");
        end
        if (total_errors != 0) begin
            $fatal(1, "GEMM rtl_v2 CPU-driven system verification failed");
        end
        $finish;
    end

/* verilator lint_on UNUSEDSIGNAL */
endmodule
