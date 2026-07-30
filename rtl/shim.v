`timescale 1ns / 1ps

module bram_to_aes_shim (
    input  wire         clk,
    input  wire         rst,
    input  wire         fetch_trigger,
    output reg          data_ready,

    // BRAM port B - read/write
    output reg  [31:0]  bram_addrb,
    output reg          bram_enb,
    output reg  [3:0]   bram_web,        
    output reg  [31:0]  bram_dinb,       
    input  wire [31:0]  bram_doutb,

    // AES sequencer outputs
    output reg  [127:0] aes_plaintext,
    output reg  [127:0] aes_key,

    // AES result inputs
    input  wire         aes_done,
    input  wire [127:0] ciphertext
);

    localparam IDLE      = 2'd0;
    localparam FETCH     = 2'd1;
    localparam WRITEBACK = 2'd2;

    reg [1:0] state;
    reg [3:0] read_count;
    reg [3:0] capture_count;
    reg [2:0] write_count;   
    reg       valid_d;

    always @(posedge clk) begin
        if (rst) begin
            state         <= IDLE;
            read_count    <= 4'd0;
            capture_count <= 4'd0;
            write_count   <= 2'd0;
            valid_d       <= 1'b0;
            bram_addrb    <= 32'd0;
            bram_enb      <= 1'b0;
            bram_web      <= 4'b0000;
            bram_dinb     <= 32'd0;
            data_ready    <= 1'b0;
            aes_plaintext <= 128'd0;
            aes_key       <= 128'd0;
        end else begin
            valid_d   <= bram_enb & (bram_web == 4'b0000); // read valid only
            bram_web  <= 4'b0000; // default: no write
            bram_dinb <= 32'd0;

            case (state)

                IDLE: begin
                    data_ready <= 1'b0;
                    bram_enb   <= 1'b0;
                    if (fetch_trigger) begin
                        bram_enb      <= 1'b1;
                        bram_addrb    <= 32'd0;
                        read_count    <= 4'd1;
                        capture_count <= 4'd0;
                        state         <= FETCH;
                    end
                    // Writeback: when sequencer signals done
                    if (aes_done) begin
                        write_count <= 2'd0;
                        state       <= WRITEBACK;
                    end
                end

                FETCH: begin
                    if (read_count < 4'd8) begin
                        bram_addrb <= bram_addrb + 32'd4;
                        read_count <= read_count + 4'd1;
                    end else begin
                        bram_enb <= 1'b0;
                    end
                    if (valid_d) begin
                        capture_count <= capture_count + 4'd1;
                        case (capture_count)
                            4'd0: aes_plaintext[31:0]   <= bram_doutb;
                            4'd1: aes_plaintext[63:32]  <= bram_doutb;
                            4'd2: aes_plaintext[95:64]  <= bram_doutb;
                            4'd3: aes_plaintext[127:96] <= bram_doutb;
                            4'd4: aes_key[31:0]         <= bram_doutb;
                            4'd5: aes_key[63:32]        <= bram_doutb;
                            4'd6: aes_key[95:64]        <= bram_doutb;
                            4'd7: begin
                                aes_key[127:96] <= bram_doutb;
                                data_ready      <= 1'b1;
                                state           <= IDLE;
                            end
                        endcase
                    end
                end

                WRITEBACK: begin
                  
                    bram_enb   <= 1'b1;
                    bram_web   <= 4'b1111;
                    case (write_count)
                        3'd0: begin
                            bram_addrb  <= 32'd32;
                            bram_dinb   <= ciphertext[31:0];
                            write_count <= 3'd1;
                        end
                        3'd1: begin
                            bram_addrb  <= 32'd36;
                            bram_dinb   <= ciphertext[63:32];
                            write_count <= 3'd2;
                        end
                        3'd2: begin
                            bram_addrb  <= 32'd40;
                            bram_dinb   <= ciphertext[95:64];
                            write_count <= 3'd3;
                        end
                        3'd3: begin
                            bram_addrb  <= 32'd44;
                            bram_dinb   <= ciphertext[127:96];
                            write_count <= 3'd4;
                            // enb/web stay high through this cycle - word 4
                            // actually gets written now
                        end
                        3'd4: begin
                            // one cycle later: safe to drop enable/write-strobe
                            bram_enb    <= 1'b0;
                            bram_web    <= 4'b0000;
                            state       <= IDLE;
                        end
                    endcase
                end

                default: state <= IDLE;
            endcase
        end
    end
endmodule
