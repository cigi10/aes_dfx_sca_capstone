`timescale 1ns / 1ps

module btn_edge_pulse (
    input  wire clk,
    input  wire rst,
    input  wire level_in,   // debounced, held-high-while-pressed
    output wire pulse_out   // exactly 1 clock cycle high per press
);
    reg level_d;
    always @(posedge clk) begin
        if (rst)
            level_d <= 1'b0;
        else
            level_d <= level_in;
    end

    assign pulse_out = level_in & ~level_d;
endmodule
