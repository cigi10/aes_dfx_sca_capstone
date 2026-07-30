`timescale 1ns / 1ps

module icap_wrapper (
    input  wire        icap_clk,
    input  wire        icap_csib,
    input  wire        icap_rdwrb,
    input  wire [31:0] icap_i,
    output wire [31:0] icap_o
);
 
    ICAPE2 #(
        .ICAP_WIDTH ("X32")
    ) u_icape2 (
        .O     (icap_o),
        .CLK   (icap_clk),
        .CSIB  (icap_csib),
        .I     (icap_i),
        .RDWRB (icap_rdwrb)
    );
 
endmodule
