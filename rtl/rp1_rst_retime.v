`timescale 1ns / 1ps

module rp1_rst_retime (
    input  wire clk,
    input  wire rst_in,
    output reg  rst_out
);

    always @(posedge clk) begin
        rst_out <= rst_in;
    end

endmodule
