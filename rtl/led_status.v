`timescale 1ns / 1ps

module led_status #(
    parameter STRETCH_CYCLES   = 25_000_000,  // ~250ms @ 100MHz
    parameter HEARTBEAT_BITS   = 26           // ~0.67s half-period @ 100MHz
) (
    input  wire       clk,
    input  wire       rst,

    input  wire        rm_decouple_pulse,   // raw, transient, from dfx_controller_0
    input  wire        event_error_pulse,   // raw, transient, from dfx_controller_0
    input  wire [3:0]  btn_debounced,       // debounced button levels, any-pressed source

    output reg         led_heartbeat,       // -> led[2], always toggling if alive
    output reg         led_swap_active,     // -> led[0], stretched rm_decouple
    output reg         led_error_active,    // -> led[1], stretched event_error
    output wire        led_btn_active       // -> led[3], live "any button pressed"
);

    // ---- heartbeat: free-running toggle, proves clock + reset are sane ----
    reg [HEARTBEAT_BITS-1:0] hb_counter;
    always @(posedge clk) begin
        if (rst) begin
            hb_counter    <= {HEARTBEAT_BITS{1'b0}};
            led_heartbeat <= 1'b0;
        end else begin
            hb_counter <= hb_counter + 1'b1;
            if (hb_counter == {HEARTBEAT_BITS{1'b1}})
                led_heartbeat <= ~led_heartbeat;
        end
    end

    // ---- pulse stretcher for rm_decouple ----
    reg [$clog2(STRETCH_CYCLES+1)-1:0] swap_hold_count;
    always @(posedge clk) begin
        if (rst) begin
            swap_hold_count <= 0;
            led_swap_active <= 1'b0;
        end else if (rm_decouple_pulse) begin
            swap_hold_count <= STRETCH_CYCLES;
            led_swap_active <= 1'b1;
        end else if (swap_hold_count > 0) begin
            swap_hold_count <= swap_hold_count - 1'b1;
            led_swap_active <= 1'b1;
        end else begin
            led_swap_active <= 1'b0;
        end
    end

    // ---- pulse stretcher for event_error (latches until next swap, since an
    //      error is worth keeping visible rather than letting it flicker away) ----
    reg [$clog2(STRETCH_CYCLES+1)-1:0] err_hold_count;
    always @(posedge clk) begin
        if (rst) begin
            err_hold_count   <= 0;
            led_error_active <= 1'b0;
        end else if (event_error_pulse) begin
            err_hold_count   <= STRETCH_CYCLES;
            led_error_active <= 1'b1;
        end else if (err_hold_count > 0) begin
            err_hold_count   <= err_hold_count - 1'b1;
            led_error_active <= 1'b1;
        end else begin
            led_error_active <= 1'b0;
        end
    end

    // ---- direct, live button indicator - no stretching needed, this one is
    //      meant to prove the raw input path instantaneously ----
    assign led_btn_active = |btn_debounced;

endmodule
