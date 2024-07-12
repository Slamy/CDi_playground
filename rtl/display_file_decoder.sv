module display_file_decoder (
    input clk,
    input reset,
    output bit [21:0] address,
    output bit as,
    input [15:0] din,
    input bus_ack,

    input reload_vsr,
    input [21:0] vsr_in,
    input read_pixels,
    
    output bit [7:0] pixel,
    output bit pixel_write,
    input pixel_strobe
);

    bit [21:0] vsr = 22'h0076370;

    assign address = vsr;

    enum {
        IDLE,
        READ,
        WRITE0,
        WRITE1,
        STOPPED
    } state = IDLE;

    bit [7:0] temp;

    always_ff @(posedge clk) begin

        if (reload_vsr) begin
            $display("start read");
            state <= IDLE;
            vsr   <= vsr_in;
        end else begin
            case (state)
                IDLE: begin
                    if (read_pixels) begin
                        state <= READ;
                        as <= 1;
                        pixel_write <= 0;
                    end
                end
                READ: begin
                    if (bus_ack) begin
                        vsr <= vsr + 2;
                        as <= 0;
                        state <= WRITE0;
                        //$display("Jo %x", din);
                        pixel <= din[15:8];
                        temp <= din[7:0];
                        pixel_write <= 1;
                    end
                end
                WRITE0: begin
                    if (pixel_strobe) begin
                        pixel <= temp;
                        state <= WRITE1;
                    end
                end
                WRITE1: begin
                    if (pixel_strobe) begin
                        pixel_write <= 0;
                        state <= IDLE;
                        //$display("Jo %x", din)!
                    end
                end
            endcase
        end
    end
endmodule
