`timescale 1ns / 1ps

module round_rm_desync (
    input  wire         clk,
    input  wire         rst,
    input  wire [31:0]  lfsr_seed,
    input  wire         aes_start,
    output reg          aes_done,
    input  wire [127:0] round_in,
    input  wire [127:0] round_key,
    input  wire         final_round,
    output wire [127:0] round_out
);

    // ---- combinational AES round (same as rm_bare) ----
    aes_round u_aes_round (
        .round_in    (round_in),
        .round_key   (round_key),
        .final_round (final_round),
        .round_out   (round_out)
    );

    // ---- 32-bit Fibonacci LFSR ----
    // Taps at positions 32,22,2,1 (maximal-length polynomial)
    reg [31:0] lfsr;
    wire       lfsr_feedback = lfsr[31] ^ lfsr[21] ^ lfsr[1] ^ lfsr[0];

    // ---- delay counter ----
    // On aes_start: sample 4 bits of LFSR as delay (1-15 cycles, never 0)
    reg [3:0] delay_cnt;
    reg [3:0] delay_target;
    reg       waiting;

    always @(posedge clk) begin
        if (rst) begin
            lfsr         <= (lfsr_seed == 32'd0) ? 32'hDEADBEEF : lfsr_seed;
            delay_cnt    <= 4'd0;
            delay_target <= 4'd1;
            waiting      <= 1'b0;
            aes_done     <= 1'b0;
        end else begin
            // LFSR runs every cycle
            lfsr <= {lfsr[30:0], lfsr_feedback};

            aes_done <= 1'b0; // default deassert

            if (aes_start && !waiting) begin
                // Sample bits [3:0] of LFSR as delay, force non-zero
                delay_target <= (lfsr[3:0] == 4'd0) ? 4'd1 : lfsr[3:0];
                delay_cnt    <= 4'd1;
                waiting      <= 1'b1;
            end else if (waiting) begin
                if (delay_cnt >= delay_target) begin
                    aes_done <= 1'b1;
                    waiting  <= 1'b0;
                    delay_cnt <= 4'd0;
                end else begin
                    delay_cnt <= delay_cnt + 4'd1;
                end
            end
        end
    end

endmodule
