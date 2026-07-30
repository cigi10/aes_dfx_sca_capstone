`timescale 1ns / 1ps

module key_schedule (
    input  wire          clk,
    input  wire          rst,
    input  wire          start,             // pulse 1 cycle to begin expansion
    input  wire [127:0]  key,               // 128-bit cipher key
    output wire [1407:0] round_keys_flat,   // 11 concatenated round keys, MSB-first
    output reg           done               // pulses 1 cycle when expansion complete
);

    reg  [127:0] rk [0:10];   // one register per round key
    reg  [3:0]   round_cnt;   // which round key is currently being computed (1..10)
    reg          running;

    // ---- combinational: one round's worth of key-schedule logic ----
    // (this replaces ONE link of the original 10x-chained combinational loop)
    wire [31:0] prev0 = rk[round_cnt - 4'd1][127:96];
    wire [31:0] prev1 = rk[round_cnt - 4'd1][95:64];
    wire [31:0] prev2 = rk[round_cnt - 4'd1][63:32];
    wire [31:0] prev3 = rk[round_cnt - 4'd1][31:0];

    // RotWord: left-rotate by one byte (equivalent to original
    // rotword={x[8:31],x[0:7]} under ascending-bit convention)
    wire [31:0] rotted = {prev3[23:0], prev3[31:24]};

    // SubWord: S-box applied to each byte, reusing the existing sbox module
    // so the substitution table is bit-identical to the rest of the design
    wire [7:0] sb0, sb1, sb2, sb3;
    sbox u_sb0 (.a(rotted[31:24]), .c(sb0));
    sbox u_sb1 (.a(rotted[23:16]), .c(sb1));
    sbox u_sb2 (.a(rotted[15:8]),  .c(sb2));
    sbox u_sb3 (.a(rotted[7:0]),   .c(sb3));
    wire [31:0] subbed = {sb0, sb1, sb2, sb3};

    // Rcon table - identical values to original rconx() function
    reg [31:0] rconv;
    always @(*) begin
        case (round_cnt)
            4'd1:  rconv = 32'h01000000;
            4'd2:  rconv = 32'h02000000;
            4'd3:  rconv = 32'h04000000;
            4'd4:  rconv = 32'h08000000;
            4'd5:  rconv = 32'h10000000;
            4'd6:  rconv = 32'h20000000;
            4'd7:  rconv = 32'h40000000;
            4'd8:  rconv = 32'h80000000;
            4'd9:  rconv = 32'h1b000000;
            4'd10: rconv = 32'h36000000;
            default: rconv = 32'h00000000;
        endcase
    end

    wire [31:0] w0 = prev0 ^ subbed ^ rconv;
    wire [31:0] w1 = prev1 ^ w0;
    wire [31:0] w2 = prev2 ^ w1;
    wire [31:0] w3 = prev3 ^ w2;

    // ---- sequencing: one round key latched per clock ----
    always @(posedge clk) begin
        if (rst) begin
            round_cnt <= 4'd0;
            running   <= 1'b0;
            done      <= 1'b0;
        end else if (start) begin
            rk[0]     <= key;      // round key 0 = the cipher key itself
            round_cnt <= 4'd1;
            running   <= 1'b1;
            done      <= 1'b0;
        end else if (running) begin
            rk[round_cnt] <= {w0, w1, w2, w3};
            if (round_cnt == 4'd10) begin
                running <= 1'b0;
                done    <= 1'b1;   // pulses exactly one cycle
            end else begin
                round_cnt <= round_cnt + 4'd1;
            end
        end else begin
            done <= 1'b0;
        end
    end

    // ---- pack round key registers into the same flat bus format as before ----
    genvar g;
    generate
        for (g = 0; g <= 10; g = g + 1) begin : pack_round_keys
            assign round_keys_flat[(1407 - g*128) -: 128] = rk[g];
        end
    endgenerate

endmodule
