`timescale 1ns / 1ps

module round_rm_bare (
    input  wire         clk,
    input  wire         rst,
    input  wire [31:0]  lfsr_seed,    // consumed by desync/dummy/masking RMs
    input  wire         aes_start,
    output wire         aes_done,
    input  wire [127:0] round_in,
    input  wire [127:0] round_key,
    input  wire         final_round,
    output wire [127:0] round_out
);

    // rm_bare: no countermeasure, purely combinational pass-through.
    // aes_done is tied combinationally to aes_start - result is valid
    // the same cycle start is asserted. lfsr_seed is unused here.
    assign aes_done = aes_start;

    aes_round u_aes_round (
        .round_in    (round_in),
        .round_key   (round_key),
        .final_round (final_round),
        .round_out   (round_out)
    );

endmodule
