module ica_dca_ctrl (
    input clk,
    input reset,
    output bit [21:0] address,
    output bit as,
    input [15:0] din,
    input bus_ack
);

    localparam bit [21:0] odd_ica_start = 22'h400;
    localparam bit [21:0] even_ica_start = 22'h404;

    bit [21:0] ica_pointer;
    bit [21:0] dca_pointer;
    bit [31:0] instruction;

    enum {
        IDLE,
        READ0,
        READ1,
        EXECUTE,
        STOPPED
    } state;

    always_ff @(posedge clk) begin

        if (reset) begin
            ica_pointer <= odd_ica_start;
            as <= 0;
            state <= IDLE;
        end else begin
            case (state)
                IDLE: begin
                    state <= READ0;
                    address <= ica_pointer;
                    ica_pointer <= ica_pointer + 2;
                    as <= 1;
                end
                READ0: begin
                    if (bus_ack) begin
                        instruction[31:16] <= din;
                        state <= READ0;
                        address <= ica_pointer;
                        ica_pointer <= ica_pointer + 2;
                    end
                end
                READ1: begin
                    if (bus_ack) begin
                        instruction[15:0] <= din;
                        state <= EXECUTE;
                        as <= 0;
                    end
                end
                EXECUTE: begin
                    case (instruction[31:28])
                        0: begin
                            // stop until next field
                            state <= STOPPED;
                        end
                        1: begin
                            // no operation
                            state <= IDLE;
                        end
                        2: begin
                            // reload dcp
                            dca_pointer <= {instruction[21:0]};
                            state <= IDLE;
                        end
                        3: begin
                            // reload dcp and stop
                            dca_pointer <= {instruction[21:0]};
                            state <= STOPPED;
                        end
                        4: begin
                            // reload ica pointer
                            ica_pointer <= {instruction[21:0]};
                            state <= IDLE;
                        end
                        5: begin
                            // reload vsr pointer and stop
                            state <= STOPPED;
                        end
                        6: begin
                            // interrupt
                            state <= IDLE;
                        end
                        7: begin
                            // reload display parameters
                            state <= IDLE;
                        end

                    endcase

                end

                STOPPED: begin
                    // Do nothing until reset
                end

            endcase
        end
    end

endmodule
