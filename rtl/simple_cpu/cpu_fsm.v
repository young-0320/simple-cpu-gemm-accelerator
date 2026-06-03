module cpu_fsm (
    input  wire clk,
    input  wire reset,
    input  wire clk_enable,

    output reg [1:0] state
);

    localparam FETCH     = 2'd0;
    localparam DECODE    = 2'd1;
    localparam EXECUTE   = 2'd2;
    localparam INCREMENT = 2'd3;

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