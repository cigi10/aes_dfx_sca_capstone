`timescale 1ns / 1ps

module debounce_btn #(
    parameter DEBOUNCE_CYCLES = 2_000_000
) (
    input  wire clk,
    input  wire rst,
    input  wire btn_in,
    output reg  btn_out
);

    // ---- 2-stage synchronizer ----
    reg btn_sync_0, btn_sync_1;
    always @(posedge clk) begin
        if (rst) begin
            btn_sync_0 <= 1'b0;
            btn_sync_1 <= 1'b0;
        end else begin
            btn_sync_0 <= btn_in;
            btn_sync_1 <= btn_sync_0;
        end
    end

    // ---- stability counter ----
    localparam CNT_WIDTH = $clog2(DEBOUNCE_CYCLES + 1);
    reg [CNT_WIDTH-1:0] count;
    reg                 btn_sync_1_d;

    always @(posedge clk) begin
        if (rst) begin
            count        <= {CNT_WIDTH{1'b0}};
            btn_out      <= 1'b0;
            btn_sync_1_d <= 1'b0;
        end else begin
            btn_sync_1_d <= btn_sync_1;

            if (btn_sync_1 != btn_sync_1_d) begin
                // input changed - restart the stability count
                count <= {CNT_WIDTH{1'b0}};
            end else if (count < DEBOUNCE_CYCLES) begin
                count <= count + 1'b1;
            end else begin
                // stable for DEBOUNCE_CYCLES - commit the new value
                btn_out <= btn_sync_1;
            end
        end
    end

endmodule
