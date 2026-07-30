`timescale 1ns / 1ps

module round_rm_masking (
    input  wire         clk,
    input  wire         rst,
    input  wire [31:0]  lfsr_seed,
    input  wire         aes_start,
    output reg           aes_done,
    input  wire [127:0] round_in,
    input  wire [127:0] round_key,
    input  wire         final_round,
    output reg  [127:0] round_out
);

    reg [31:0] lfsr;
    wire lfsr_feedback = lfsr[31] ^ lfsr[21] ^ lfsr[1] ^ lfsr[0];

    reg  [7:0]   m;
    reg  [127:0] mask_full;
    reg  [127:0] mask_correction;
    reg          first_round_pending;

    (* ram_style = "block" *) reg [7:0] mtab0  [0:255];
    (* ram_style = "block" *) reg [7:0] mtab1  [0:255];
    (* ram_style = "block" *) reg [7:0] mtab2  [0:255];
    (* ram_style = "block" *) reg [7:0] mtab3  [0:255];
    (* ram_style = "block" *) reg [7:0] mtab4  [0:255];
    (* ram_style = "block" *) reg [7:0] mtab5  [0:255];
    (* ram_style = "block" *) reg [7:0] mtab6  [0:255];
    (* ram_style = "block" *) reg [7:0] mtab7  [0:255];
    (* ram_style = "block" *) reg [7:0] mtab8  [0:255];
    (* ram_style = "block" *) reg [7:0] mtab9  [0:255];
    (* ram_style = "block" *) reg [7:0] mtab10 [0:255];
    (* ram_style = "block" *) reg [7:0] mtab11 [0:255];
    (* ram_style = "block" *) reg [7:0] mtab12 [0:255];
    (* ram_style = "block" *) reg [7:0] mtab13 [0:255];
    (* ram_style = "block" *) reg [7:0] mtab14 [0:255];
    (* ram_style = "block" *) reg [7:0] mtab15 [0:255];

    reg [8:0] build_idx;

    wire [7:0] build_sbox_out;
    sbox u_build_sbox (
        .a (build_idx[7:0] ^ m),
        .c (build_sbox_out)
    );

    wire [127:0] mixed_mask_full;
    mixColumns u_mask_mix (
        .state_in  (mask_full),
        .state_out (mixed_mask_full)
    );

    wire [127:0] masked_state = first_round_pending ? (round_in ^ mask_full) : round_in;

    wire [7:0] mbyte0  = masked_state[127:120];
    wire [7:0] mbyte1  = masked_state[119:112];
    wire [7:0] mbyte2  = masked_state[111:104];
    wire [7:0] mbyte3  = masked_state[103:96];
    wire [7:0] mbyte4  = masked_state[95:88];
    wire [7:0] mbyte5  = masked_state[87:80];
    wire [7:0] mbyte6  = masked_state[79:72];
    wire [7:0] mbyte7  = masked_state[71:64];
    wire [7:0] mbyte8  = masked_state[63:56];
    wire [7:0] mbyte9  = masked_state[55:48];
    wire [7:0] mbyte10 = masked_state[47:40];
    wire [7:0] mbyte11 = masked_state[39:32];
    wire [7:0] mbyte12 = masked_state[31:24];
    wire [7:0] mbyte13 = masked_state[23:16];
    wire [7:0] mbyte14 = masked_state[15:8];
    wire [7:0] mbyte15 = masked_state[7:0];

    reg [7:0] sbyte0, sbyte1, sbyte2, sbyte3, sbyte4, sbyte5, sbyte6, sbyte7;
    reg [7:0] sbyte8, sbyte9, sbyte10, sbyte11, sbyte12, sbyte13, sbyte14, sbyte15;

    wire [127:0] sub_masked = {sbyte0,sbyte1,sbyte2,sbyte3,sbyte4,sbyte5,sbyte6,sbyte7,
                                sbyte8,sbyte9,sbyte10,sbyte11,sbyte12,sbyte13,sbyte14,sbyte15};

    wire [127:0] shift_masked;
    shiftRows u_shiftRows (
        .in      (sub_masked),
        .shifted (shift_masked)
    );

    wire [127:0] mix_masked_raw;
    mixColumns u_mixColumns (
        .state_in  (shift_masked),
        .state_out (mix_masked_raw)
    );
    wire [127:0] mix_masked      = mix_masked_raw ^ mask_correction;
    wire [127:0] post_mix_masked = final_round ? shift_masked : mix_masked;

    wire [127:0] result_masked = post_mix_masked ^ round_key;

    wire [127:0] result_final = final_round ? (result_masked ^ mask_full) : result_masked;

    localparam S_IDLE  = 2'd0;
    localparam S_BUILD = 2'd1;
    localparam S_READ  = 2'd2;
    localparam S_EVAL  = 2'd3;
    reg [1:0] state;

    always @(posedge clk) begin
        if (rst) begin
            lfsr                <= (lfsr_seed == 32'd0) ? 32'hD0D0FEED : lfsr_seed;
            state               <= S_IDLE;
            aes_done            <= 1'b0;
            round_out           <= 128'd0;
            first_round_pending <= 1'b1;
            build_idx           <= 9'd0;
            m                   <= 8'd0;
            mask_full           <= 128'd0;
            mask_correction     <= 128'd0;
        end else begin
            lfsr     <= {lfsr[30:0], lfsr_feedback};
            aes_done <= 1'b0;

            case (state)
                S_IDLE: begin
                    if (aes_start) begin
                        if (first_round_pending) begin
                            m         <= lfsr[7:0];
                            mask_full <= {16{lfsr[7:0]}};
                            build_idx <= 9'd0;
                            state     <= S_BUILD;
                        end else begin
                            state <= S_READ;
                        end
                    end
                end

                S_BUILD: begin
                    mtab0[build_idx[7:0]]  <= build_sbox_out ^ m;
                    mtab1[build_idx[7:0]]  <= build_sbox_out ^ m;
                    mtab2[build_idx[7:0]]  <= build_sbox_out ^ m;
                    mtab3[build_idx[7:0]]  <= build_sbox_out ^ m;
                    mtab4[build_idx[7:0]]  <= build_sbox_out ^ m;
                    mtab5[build_idx[7:0]]  <= build_sbox_out ^ m;
                    mtab6[build_idx[7:0]]  <= build_sbox_out ^ m;
                    mtab7[build_idx[7:0]]  <= build_sbox_out ^ m;
                    mtab8[build_idx[7:0]]  <= build_sbox_out ^ m;
                    mtab9[build_idx[7:0]]  <= build_sbox_out ^ m;
                    mtab10[build_idx[7:0]] <= build_sbox_out ^ m;
                    mtab11[build_idx[7:0]] <= build_sbox_out ^ m;
                    mtab12[build_idx[7:0]] <= build_sbox_out ^ m;
                    mtab13[build_idx[7:0]] <= build_sbox_out ^ m;
                    mtab14[build_idx[7:0]] <= build_sbox_out ^ m;
                    mtab15[build_idx[7:0]] <= build_sbox_out ^ m;
                    if (build_idx == 9'd255) begin
                        mask_correction <= mixed_mask_full ^ mask_full;
                        state           <= S_READ;
                    end else begin
                        build_idx <= build_idx + 9'd1;
                    end
                end

                S_READ: begin
                    sbyte0  <= mtab0[mbyte0];
                    sbyte1  <= mtab1[mbyte1];
                    sbyte2  <= mtab2[mbyte2];
                    sbyte3  <= mtab3[mbyte3];
                    sbyte4  <= mtab4[mbyte4];
                    sbyte5  <= mtab5[mbyte5];
                    sbyte6  <= mtab6[mbyte6];
                    sbyte7  <= mtab7[mbyte7];
                    sbyte8  <= mtab8[mbyte8];
                    sbyte9  <= mtab9[mbyte9];
                    sbyte10 <= mtab10[mbyte10];
                    sbyte11 <= mtab11[mbyte11];
                    sbyte12 <= mtab12[mbyte12];
                    sbyte13 <= mtab13[mbyte13];
                    sbyte14 <= mtab14[mbyte14];
                    sbyte15 <= mtab15[mbyte15];
                    state   <= S_EVAL;
                end

                S_EVAL: begin
                    round_out           <= result_final;
                    aes_done            <= 1'b1;
                    first_round_pending <= final_round;
                    state               <= S_IDLE;
                end

                default: state <= S_IDLE;
            endcase
        end
    end

endmodule
