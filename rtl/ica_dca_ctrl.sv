module ica_dca_ctrl (
    input clk,
    input reset,
    output bit [21:0] address,
    output bit as,
    input [15:0] din,
    input bus_ack,

    output [6:0] register_adr,
    output [23:0] register_data,
    output register_write,

    output reload_vsr,
    output [21:0] vsr
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

    assign register_adr = instruction[30:24];
    assign register_data = instruction[23:0];
    assign register_write = state == EXECUTE && instruction[31];

    assign vsr = instruction[21:0];
    assign reload_vsr = state == EXECUTE && instruction[31:28] == 5;
    /*
    always_ff @(posedge clk) begin
        if (register_write) $display("ICA Write %x %x %b", {1'b1, register_adr}, register_data, register_data);
    end
    */
    bit cm;
    bit mf1;
    bit mf2;
    bit ft1;
    bit ft2;

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
                        state <= READ1;
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
                            $display("STOP");

                        end
                        1: begin
                            // no operation
                            state <= IDLE;
                            $display("NOP");
                        end
                        2: begin
                            // reload dcp
                            dca_pointer <= instruction[21:0];
                            $display("Reload DCP %x", instruction[21:0]);
                            state <= IDLE;
                        end
                        3: begin
                            // reload dcp and stop
                            dca_pointer <= instruction[21:0];
                            $display("Reload DCP and STOP %x", instruction[21:0]);
                            state <= STOPPED;
                        end
                        4: begin
                            // reload ica pointer
                            ica_pointer <= instruction[21:0];
                            $display("Reload ICA %x", instruction[21:0]);
                            state <= IDLE;
                        end
                        5: begin
                            // reload vsr pointer and stop
                            $display("Reload VSR and STOP %x", instruction[21:0]);
                            state <= STOPPED;
                        end
                        6: begin
                            // interrupt
                            $display("INTERRUPT");
                            state <= IDLE;
                        end
                        7: begin
                            // reload display parameters
                            //assert(instruction[27]);
                            //assert(!instruction[5]);
                            cm  <= instruction[4];
                            mf1 <= instruction[3];
                            mf2 <= instruction[2];
                            ft1 <= instruction[1];
                            ft2 <= instruction[0];
                            $display("RELOAD DISPLAY PARAMETERS %b", instruction[4:0]);
                            state <= IDLE;
                        end
                        default: begin
                            // no command but probably a register write
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
