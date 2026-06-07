`timescale 1ns / 1ps
`include "gemm_define.vh"

// Compatibility top for the existing single-port transaction testbench.
// The original rtl_AT controller/LSU target a dual-port memory path; this
// wrapper preserves the public rtl/gemm_accelerator interface and uses the
// rtl_AT adder-tree datapath for each C element.
module gemm_accelerator_top #(
    parameter MAC_MODE = 4,
    parameter MEMORY_PORTS = 1
) (
    input wire clk,
    input wire reset,

    input  wire        mmio_sel,
    input  wire        mmio_we,
    input  wire [ 2:0] mmio_off,
    input  wire [31:0] mmio_wdata,
    output reg  [31:0] mmio_rdata,

    output reg  [11:0] mem_addr,
    input  wire [31:0] mem_rdata,
    output reg  [31:0] mem_wdata,
    output reg         mem_we,

    output reg  [11:0] mem_addr_a,
    input  wire [31:0] mem_rdata_a,
    output reg         mem_en,
    output reg  [11:0] mem_addr_b,
    input  wire [31:0] mem_rdata_b,

    output wire       busy,
    output wire [2:0] state_debug
);

  localparam S_IDLE = 3'd0;
  localparam S_READ_A_REQ = 3'd1;
  localparam S_READ_A_LAT = 3'd2;
  localparam S_READ_B_REQ = 3'd3;
  localparam S_READ_B_LAT = 3'd4;
  localparam S_STORE = 3'd5;
  localparam S_ADVANCE = 3'd6;
  localparam S_DONE = 3'd7;

  reg [2:0] state;
  reg [2:0] phase_debug;
  reg [11:0] a_base;
  reg [11:0] b_base;
  reg [11:0] c_base;
  reg [31:0] m_dim_full;
  reg [31:0] n_dim_full;
  reg [31:0] k_dim_full;
  reg [2:0] m_dim;
  reg [2:0] n_dim;
  reg [2:0] k_dim;

  reg status_done;
  reg status_error;
  reg status_invalid_size;

  reg [2:0] row_idx;
  reg [2:0] col_idx;
  reg [2:0] k_idx;
  reg [31:0] a_buf;
  reg [31:0] b_buf;

  wire valid_m = (m_dim_full >= `GEMM_DIM_MIN) && (m_dim_full <= `GEMM_DIM_MAX);
  wire valid_n = (n_dim_full >= `GEMM_DIM_MIN) && (n_dim_full <= `GEMM_DIM_MAX);
  wire valid_k = (k_dim_full >= `GEMM_DIM_MIN) && (k_dim_full <= `GEMM_DIM_MAX);
  wire dims_ok = valid_m && valid_n && valid_k;

  wire start_pulse = mmio_sel && mmio_we && (mmio_off == `GEMM_OFF_CTRL) &&
                       mmio_wdata[`GEMM_CTRL_START_BIT];
  wire clear_pulse = mmio_sel && mmio_we && (mmio_off == `GEMM_OFF_CTRL) &&
                       mmio_wdata[`GEMM_CTRL_CLEAR_DONE_BIT];

  wire dual_memory = (MEMORY_PORTS == 2);
  // compat top은 adder-tree datapath 고정이라 MAC_MODE 값으로 분기하지 않는다.
  // 파라미터를 의도적으로 소비해 Verilator UNUSEDPARAM 경고를 없앤다.
  wire unused_mac_mode = (MAC_MODE != 0);
  wire [31:0] active_a_rdata = dual_memory ? mem_rdata_a : mem_rdata;
  wire [31:0] active_b_rdata = dual_memory ? mem_rdata_b : mem_rdata;

  // row/col/k 인덱스는 3비트지만 외부 메모리 주소는 12비트 word address이다.
  // 주소 덧셈 폭을 명시해 Verilator WIDTHEXPAND 경고와 해석 여지를 없앤다.
  wire [11:0] row_addr_offset = {9'd0, row_idx};
  wire [11:0] next_row_addr_offset = {9'd0, row_idx} + 12'd1;
  wire [11:0] next_k_addr_offset = {9'd0, k_idx} + 12'd1;
  wire [5:0]  c_row_offset = {3'd0, row_idx} * {3'd0, n_dim};
  wire [11:0] c_elem_offset = {6'd0, c_row_offset} + {9'd0, col_idx};

  wire [31:0] c_sum;
  gemm_mac_datapath u_at_mac (
      .gemm_k(k_dim_full),
      .cnt_k (32'd0),
      .a_buf (a_buf),
      .b_buf (b_buf),
      .c_buf (32'd0),
      .c_out (c_sum)
  );

  assign busy = (state != S_IDLE) && (state != S_DONE);
  assign state_debug = phase_debug;

  always @(*) begin
    case (state)
      S_IDLE: phase_debug = `GEMM_S_IDLE;
      S_READ_A_REQ,
      S_READ_A_LAT,
      S_READ_B_REQ,
      S_READ_B_LAT: phase_debug = `GEMM_S_LOAD;
      S_STORE: phase_debug = `GEMM_S_STORE;
      S_ADVANCE: phase_debug = `GEMM_S_COMPUTE;
      S_DONE: phase_debug = `GEMM_S_DONE;
      default: phase_debug = `GEMM_S_IDLE;
    endcase
  end

  function automatic [7:0] lane_byte(input [31:0] word, input [1:0] lane);
    begin
      case (lane)
        2'd0: lane_byte = word[7:0];
        2'd1: lane_byte = word[15:8];
        2'd2: lane_byte = word[23:16];
        default: lane_byte = word[31:24];
      endcase
    end
  endfunction

  always @(posedge clk) begin
    if (reset) begin
      state <= S_IDLE;
      a_base <= 12'd0;
      b_base <= 12'd0;
      c_base <= 12'd0;
      m_dim_full <= 32'd0;
      n_dim_full <= 32'd0;
      k_dim_full <= 32'd0;
      m_dim <= 3'd0;
      n_dim <= 3'd0;
      k_dim <= 3'd0;
      status_done <= 1'b0;
      status_error <= 1'b0;
      status_invalid_size <= 1'b0;
      row_idx <= 3'd0;
      col_idx <= 3'd0;
      k_idx <= 3'd0;
      a_buf <= 32'd0;
      b_buf <= 32'd0;
      mem_addr <= 12'd0;
      mem_addr_a <= 12'd0;
      mem_addr_b <= 12'd0;
      mem_wdata <= 32'd0;
      mem_we <= 1'b0;
      mem_en <= 1'b0;
    end else begin
      mem_we <= 1'b0;
      mem_en <= 1'b0;

      if (mmio_sel && mmio_we && !busy) begin
        case (mmio_off)
          `GEMM_OFF_A_BASE: a_base <= mmio_wdata[11:0];
          `GEMM_OFF_B_BASE: b_base <= mmio_wdata[11:0];
          `GEMM_OFF_C_BASE: c_base <= mmio_wdata[11:0];
          `GEMM_OFF_M: begin
            m_dim_full <= mmio_wdata;
            m_dim <= mmio_wdata[2:0];
          end
          `GEMM_OFF_N: begin
            n_dim_full <= mmio_wdata;
            n_dim <= mmio_wdata[2:0];
          end
          `GEMM_OFF_K: begin
            k_dim_full <= mmio_wdata;
            k_dim <= mmio_wdata[2:0];
          end
          default: ;
        endcase
      end

      if (clear_pulse) begin
        status_done <= 1'b0;
        status_error <= 1'b0;
        status_invalid_size <= 1'b0;
        state <= S_IDLE;
      end else begin
        case (state)
          S_IDLE: begin
            if (start_pulse) begin
              status_done <= 1'b0;
              status_error <= 1'b0;
              status_invalid_size <= 1'b0;
              if (!dims_ok) begin
                status_done <= 1'b1;
                status_error <= 1'b1;
                status_invalid_size <= 1'b1;
                state <= S_DONE;
              end else begin
                row_idx <= 3'd0;
                col_idx <= 3'd0;
                k_idx <= 3'd0;
                b_buf <= 32'd0;
                if (dual_memory) begin
                  mem_addr_a <= a_base;
                  mem_addr_b <= b_base;
                end else begin
                  mem_addr <= a_base;
                end
                state <= S_READ_A_REQ;
              end
            end
          end

          S_READ_A_REQ: begin
            state <= S_READ_A_LAT;
          end

          S_READ_A_LAT: begin
            a_buf <= active_a_rdata;
            b_buf <= 32'd0;
            k_idx <= 3'd0;
            if (dual_memory) begin
              b_buf[7:0] <= lane_byte(active_b_rdata, col_idx[1:0]);
              if (k_dim == 3'd1) begin
                state <= S_STORE;
              end else begin
                k_idx <= 3'd1;
                mem_addr_b <= b_base + 12'd1;
                state <= S_READ_B_REQ;
              end
            end else begin
              mem_addr <= b_base;
              state <= S_READ_B_REQ;
            end
          end

          S_READ_B_REQ: begin
            state <= S_READ_B_LAT;
          end

          S_READ_B_LAT: begin
            case (k_idx)
              3'd0: b_buf[7:0] <= lane_byte(active_b_rdata, col_idx[1:0]);
              3'd1: b_buf[15:8] <= lane_byte(active_b_rdata, col_idx[1:0]);
              3'd2: b_buf[23:16] <= lane_byte(active_b_rdata, col_idx[1:0]);
              default: b_buf[31:24] <= lane_byte(active_b_rdata, col_idx[1:0]);
            endcase

            if (k_idx + 3'd1 == k_dim) begin
              state <= S_STORE;
            end else begin
              k_idx <= k_idx + 3'd1;
              if (dual_memory) begin
                mem_addr_b <= b_base + next_k_addr_offset;
              end else begin
                mem_addr <= b_base + next_k_addr_offset;
              end
              state <= S_READ_B_REQ;
            end
          end

          S_STORE: begin
            if (dual_memory) begin
              mem_addr_a <= c_base + c_elem_offset;
              mem_en <= 1'b1;
            end else begin
              mem_addr <= c_base + c_elem_offset;
              mem_we <= 1'b1;
            end
            mem_wdata <= c_sum;
            state <= S_ADVANCE;
          end

          S_ADVANCE: begin
            if ((row_idx + 3'd1 == m_dim) && (col_idx + 3'd1 == n_dim)) begin
              status_done <= 1'b1;
              state <= S_DONE;
            end else begin
              if (col_idx + 3'd1 == n_dim) begin
                row_idx  <= row_idx + 3'd1;
                col_idx  <= 3'd0;
                if (dual_memory) begin
                  mem_addr_a <= a_base + next_row_addr_offset;
                  mem_addr_b <= b_base;
                end else begin
                  mem_addr <= a_base + next_row_addr_offset;
                end
              end else begin
                col_idx  <= col_idx + 3'd1;
                if (dual_memory) begin
                  mem_addr_a <= a_base + row_addr_offset;
                  mem_addr_b <= b_base;
                end else begin
                  mem_addr <= a_base + row_addr_offset;
                end
              end
              state <= S_READ_A_REQ;
            end
          end

          S_DONE: begin
            status_done <= 1'b1;
          end

          default: begin
            state <= S_IDLE;
          end
        endcase
      end
    end
  end

  always @(*) begin
    mmio_rdata = 32'd0;
    if (mmio_sel && !mmio_we) begin
      case (mmio_off)
        `GEMM_OFF_A_BASE: mmio_rdata = {20'd0, a_base};
        `GEMM_OFF_B_BASE: mmio_rdata = {20'd0, b_base};
        `GEMM_OFF_C_BASE: mmio_rdata = {20'd0, c_base};
        `GEMM_OFF_M: mmio_rdata = m_dim_full;
        `GEMM_OFF_N: mmio_rdata = n_dim_full;
        `GEMM_OFF_K: mmio_rdata = k_dim_full;
        `GEMM_OFF_STATUS: begin
          mmio_rdata[`GEMM_ST_BUSY_BIT] = busy;
          mmio_rdata[`GEMM_ST_DONE_BIT] = status_done;
          mmio_rdata[`GEMM_ST_ERROR_BIT] = status_error;
          mmio_rdata[`GEMM_ST_INVSIZE_BIT] = status_invalid_size;
        end
        default: mmio_rdata = 32'd0;
      endcase
    end
  end

endmodule
