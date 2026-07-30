module aes_sequencer (
    input  wire         clk,
    input  wire         rst,
    input  wire         start,
    input  wire [127:0] plaintext,
    input  wire [127:0] key,
    output reg  [127:0] ciphertext,
    output reg          done,

    // ---- Reconfigurable Partition interface (frozen, Section 3.3) ----
    output reg  [127:0] round_in,
    input  wire [127:0] round_out,
    output reg  [127:0] round_key,
    output reg          final_round,
    output reg          aes_start,
    input  wire         aes_done,

    // ---- Debug outputs (for block-design ILA) ----
    output wire [2:0]   dbg_state,
    output wire [3:0]   dbg_round_count
);

    // ---- all signals declared before first use ----
    wire [1407:0] round_keys_flat;
    wire [127:0]  round_keys_w [0:10];
    reg  [127:0]  round_keys_r [0:10];

    // key schedule handshake
    reg  ks_start;
    wire ks_done;

    // start edge-detection (mirrors aes_op_done_latch.v's fetch_trigger handling)
    reg  start_d;
    wire start_pulse;

    localparam S_IDLE    = 3'd0;
    localparam S_KS_WAIT = 3'd1;   // waiting for pipelined key schedule
    localparam S_LOAD    = 3'd2;
    localparam S_ROUND   = 3'd3;
    localparam S_DONE    = 3'd4;

    reg [2:0] state;
    reg [3:0] round_count;

    integer k;
    genvar  g;

    // ---- debug taps ----
    assign dbg_state       = state;
    assign dbg_round_count = round_count;

    // ---- start edge detector ----
    assign start_pulse = start & ~start_d;

    always @(posedge clk) begin
        if (rst)
            start_d <= 1'b0;
        else
            start_d <= start;
    end

    // ---- pipelined key schedule ----
    key_schedule u_key_schedule (
        .clk             (clk),
        .rst             (rst),
        .start           (ks_start),
        .key             (key),
        .round_keys_flat (round_keys_flat),
        .done            (ks_done)
    );

    generate
        for (g = 0; g <= 10; g = g + 1) begin : unpack_round_keys
            assign round_keys_w[g] = round_keys_flat[(1407 - g*128) -: 128];
        end
    endgenerate

    // ---- FSM ----
    always @(posedge clk) begin
        if (rst) begin
            state       <= S_IDLE;
            done        <= 1'b0;
            round_count <= 4'd0;
            ciphertext  <= 128'd0;
            round_in    <= 128'd0;
            round_key   <= 128'd0;
            final_round <= 1'b0;
            aes_start   <= 1'b0;
            ks_start    <= 1'b0;
        end else begin
            aes_start <= 1'b0;
            ks_start  <= 1'b0;

            case (state)

                S_IDLE: begin
                    done <= 1'b0;
                    if (start_pulse) begin
                        ks_start <= 1'b1;   // kick off key schedule
                        state    <= S_KS_WAIT;
                    end
                end

                // Wait 10 cycles for pipelined key schedule to complete
                S_KS_WAIT: begin
                    if (ks_done) begin
                        state <= S_LOAD;
                    end
                end

                S_LOAD: begin
                    for (k = 0; k <= 10; k = k + 1)
                        round_keys_r[k] <= round_keys_w[k];
                    round_in    <= plaintext ^ round_keys_w[0];
                    round_key   <= round_keys_w[1];
                    round_count <= 4'd0;
                    final_round <= 1'b0;
                    aes_start   <= 1'b1;
                    state       <= S_ROUND;
                end

                S_ROUND: begin
                    if (aes_done) begin
                        round_in <= round_out;
                        if (round_count == 4'd9) begin
                            state <= S_DONE;
                        end else begin
                            round_count <= round_count + 4'd1;
                            round_key   <= round_keys_r[round_count + 4'd2];
                            final_round <= (round_count + 4'd1 == 4'd9);
                            aes_start   <= 1'b1;
                        end
                    end
                end

                S_DONE: begin
                    ciphertext <= round_in;
                    done       <= 1'b1;
                    state      <= S_IDLE;
                end

                default: state <= S_IDLE;
            endcase
        end
    end

endmodule
