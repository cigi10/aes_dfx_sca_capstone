`timescale 1ns / 1ps

module aes_op_done_latch (
    input  wire clk,
    input  wire rst,
    (* mark_debug = "true" *) input  wire fetch_trigger,
    (* mark_debug = "true" *) input  wire aes_done_pulse,
    (* mark_debug = "true" *) output reg  op_complete

);

    reg fetch_trigger_d;

    always @(posedge clk) begin
        if (rst) begin
            op_complete    <= 1'b0;
            fetch_trigger_d <= 1'b0;
        end else begin
            fetch_trigger_d <= fetch_trigger;

            if (fetch_trigger && !fetch_trigger_d) begin
                // rising edge of a new trigger - a fresh operation is starting
                op_complete <= 1'b0;
            end else if (aes_done_pulse) begin
                op_complete <= 1'b1;
            end
        end
    end

endmodule
