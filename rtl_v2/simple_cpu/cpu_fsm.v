`include "define.vh"

module cpu_fsm (
    input  wire clk,
    input  wire reset,
    input  wire clk_enable,

    output reg [1:0] state
);

    localparam FETCH     = `ST_FETCH;
    localparam DECODE    = `ST_DECODE;
    localparam EXECUTE   = `ST_EXECUTE;
    localparam INCREMENT = `ST_INCREMENT;

    always @(posedge clk) begin
        if (reset) begin
            state <= FETCH;
        end
        else if (clk_enable) begin
            case (state)
                FETCH:     state <= DECODE;
                DECODE:    state <= EXECUTE;
                EXECUTE:   state <= INCREMENT;
                INCREMENT: state <= FETCH;
                default:   state <= FETCH;
            endcase
        end
    end

endmodule
