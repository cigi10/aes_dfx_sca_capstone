`timescale 1ns / 1ps

module round_rm_dummy (
    input  wire         clk,
    input  wire         rst,
    input  wire [31:0]  lfsr_seed,
    input  wire         aes_start,
    output reg          aes_done,
    input  wire [127:0] round_in,
    input  wire [127:0] round_key,
    input  wire         final_round,
    output reg  [127:0] round_out
);

    // ---- free-running LFSR ----
    reg [31:0] lfsr;
    wire lfsr_fb = lfsr[31] ^ lfsr[21] ^ lfsr[1] ^ lfsr[0];

    // ---- REAL round: purely combinational from round_in/round_key ----
    // Same depth as rm_bare - no mux, no state dependency on this path.
    wire [127:0] real_result;
    aes_round u_real (
        .round_in    (round_in),
        .round_key   (round_key),
        .final_round (final_round),
        .round_out   (real_result)
    );

    // ---- DUMMY round: separate aes_round instance fed with LFSR garbage ----
    // dont_touch on the INSTANCE forces Vivado to keep this hierarchy intact
    // in the final netlist, rather than proving the cone of logic feeding an
    // unused-looking wire is dead and deleting the whole thing.
    reg  [127:0] dummy_state;
    wire [127:0] dummy_result;
    (* dont_touch = "true" *) aes_round u_dummy (
        .round_in    (dummy_state),
        .round_key   ({lfsr, ~lfsr, lfsr ^ 32'hAAAAAAAA, ~lfsr ^ 32'h55555555}),
        .final_round (1'b0),
        .round_out   (dummy_result)
    );

    // Registered, dont_touch sink for dummy_result. A real flip-flop with
    // dont_touch is a much stronger anti-optimization guarantee than a bare
    // combinational reduction wire with only a `keep` attribute - this is
    // what actually failed last revision.
    (* dont_touch = "true" *) reg [127:0] dummy_result_reg;
    always @(posedge clk) begin
        dummy_result_reg <= dummy_result;
    end

    // ---- FSM ----
    localparam S_IDLE  = 2'd0;
    localparam S_DUMMY = 2'd1;
    localparam S_DONE  = 2'd2;

    reg [1:0] state;
    reg [1:0] dummy_count;

    always @(posedge clk) begin
        if (rst) begin
            lfsr        <= (lfsr_seed == 32'd0) ? 32'hD0D0FEED : lfsr_seed;
            state       <= S_IDLE;
            aes_done    <= 1'b0;
            round_out   <= 128'd0;
            dummy_state <= 128'd0;
            dummy_count <= 2'd0;
        end else begin
            lfsr     <= {lfsr[30:0], lfsr_fb};
            aes_done <= 1'b0;

            case (state)
                S_IDLE: begin
                    if (aes_start) begin
                        // Latch real result immediately - combinational path
                        // from round_in/round_key is already settled
                        round_out   <= real_result;
                        // Set up dummy round input for noise generation
                        dummy_state <= round_in ^ {lfsr, ~lfsr, lfsr[15:0],
                                                   lfsr[31:16]};
                        // 0-3 dummy rounds chosen fresh each time
                        dummy_count <= lfsr[1:0];
                        if (lfsr[1:0] == 2'd0)
                            state <= S_DONE;
                        else
                            state <= S_DUMMY;
                    end
                end

                S_DUMMY: begin
                    // dummy_result computed combinationally, registered above,
                    // never used downstream - purely creates realistic
                    // switching activity now guaranteed to actually exist
                    // in the implemented netlist.
                    dummy_state <= dummy_result ^ lfsr;
                    if (dummy_count == 2'd1)
                        state <= S_DONE;
                    else
                        dummy_count <= dummy_count - 2'd1;
                end

                S_DONE: begin
                    aes_done <= 1'b1;
                    state    <= S_IDLE;
                end

                default: state <= S_IDLE;
            endcase
        end
    end

endmodule
