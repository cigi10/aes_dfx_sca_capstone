`timescale 1ns / 1ps

module aes_round (
    input  wire [127:0] round_in,      // state coming into this round
    input  wire [127:0] round_key,     // this round's expanded key
    input  wire         final_round,   // 1 => skip MixColumns (AES round 10)
    output wire [127:0] round_out      // state after this round
);

    wire [127:0] sub_out;
    wire [127:0] shift_out;
    wire [127:0] mix_out;
    wire [127:0] post_mix; // value entering AddRoundKey

    // SubBytes: byte-wise S-box substitution
    subBytes u_subBytes (
        .in  (round_in),
        .out (sub_out)
    );

    // ShiftRows: cyclic row shifts (module port order is [0:127];
    // Verilog connects MSB-to-MSB by position, so this composes correctly
    // with the [127:0]-declared signals around it)
    shiftRows u_shiftRows (
        .in      (sub_out),
        .shifted (shift_out)
    );

    // MixColumns: GF(2^8) column mixing
    mixColumns u_mixColumns (
        .state_in  (shift_out),
        .state_out (mix_out)
    );

    // Final round (round 10) skips MixColumns per the AES spec
    assign post_mix = final_round ? shift_out : mix_out;

    // AddRoundKey
    assign round_out = post_mix ^ round_key;

endmodule
