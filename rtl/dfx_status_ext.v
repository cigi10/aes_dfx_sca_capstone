`timescale 1ns / 1ps

module dfx_status_ext (
    input  wire clk,
    input  wire rst,

    input  wire trig0_pulse,   // -> rm_bare
    input  wire trig1_pulse,   // -> rm_desync
    input  wire trig2_pulse,   // -> rm_masking
    input  wire trig3_pulse,   // -> rm_dummy, now sourced from a dedicated
                                // switch (sw_dummy) rather than btn3, so it
                                // no longer shares a reset domain with the
                                // event that would otherwise race it.

    input  wire event_error_pulse,

    output reg  [3:0] rm_active,     // one-hot, persists until next trigger
    output reg         error_sticky  // latches high, clears only on rst
);

    // ---- one-hot RM indicator ----
    always @(posedge clk) begin
        if (rst) begin
            rm_active <= 4'b0001;  // rm_bare is POR default
        end else begin
            if (trig0_pulse)      rm_active <= 4'b0001;
            else if (trig1_pulse) rm_active <= 4'b0010;
            else if (trig2_pulse) rm_active <= 4'b0100;
            else if (trig3_pulse) rm_active <= 4'b1000;
        end
    end

    // ---- sticky error latch ----
    // Now that rm_dummy selection is via a dedicated switch (not btn3),
    // this can safely go back to a plain reset-clears-it latch: routine
    // RM switching no longer triggers a system reset, so there's no more
    // risk of a real error getting silently wiped by normal use.
    always @(posedge clk) begin
        if (rst)
            error_sticky <= 1'b0;
        else if (event_error_pulse)
            error_sticky <= 1'b1;
        // else: holds its value
    end

endmodule
