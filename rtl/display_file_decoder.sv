module display_file_decoder (
    input clk,
    input reset,
    output bit [21:0] address,
    output bit as,
    input [15:0] din,
    input bus_ack,

    input reload_vsr,
    input [21:0] vsr_in,

    output bit [7:0] pixel,
    output bit pixel_strobe
);

    bit [21:0] vsr = 22'h076370;
    //bit [21:0] vsr = 22'h0610e0;

    assign address = vsr;

    enum {
        IDLE,
        READ0,
        READ1,
        STOPPED
    } state;

    bit [7:0] temp;

    always_ff @(posedge clk) begin
        case (state)
            IDLE: begin
                state <= READ0;
                as <= 1;
                pixel_strobe <= 0;

            end
            READ0: begin
                if (bus_ack) begin
                    vsr <= vsr + 2;
                    as <= 0;
                    state <= READ1;
                    //$display("Jo %x", din);
                    pixel <= din[15:8];
                    temp <= din[7:0];
                    pixel_strobe <= 1;
                end
            end
            READ1: begin
                state <= IDLE;
                //$display("Jo %x", din);
                pixel <= temp;
                as <= 1;
            end
        endcase
    end
endmodule
