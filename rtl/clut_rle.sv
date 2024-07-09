/// CLUT7 RLE Decompression

module clut_rle (
    input clk,
    input reset,
    input [7:0] src_pixel,
    input src_pixel_write,
    output bit src_pixel_strobe,

    output bit [7:0] dst_pixel,
    output bit dst_pixel_write,
    input dst_pixel_strobe
);

    enum {
        SINGLE,
        GET_NUMBER,
        LIMITED_RLE,
        END_OF_LINE_RLE
    } state = SINGLE;

    bit [7:0] rle_counter = 0;
    bit [6:0] stored_pixel = 0;

    bit [10:0] pixelcounter;
    wire reset_pixelcounter = pixelcounter == 0;

    always_ff @(posedge clk) begin
        if (reset || reset_pixelcounter) pixelcounter <= 384;
        else if (dst_pixel_write && dst_pixel_strobe) pixelcounter <= pixelcounter - 1;
    end

    always_comb begin
        dst_pixel_write = 0;
        src_pixel_strobe = 0;
        dst_pixel = {1'b0, stored_pixel};

        case (state)
            SINGLE: begin
                if (src_pixel[7]) begin
                    src_pixel_strobe = 1;
                end else begin
                    dst_pixel = {1'b0, src_pixel[6:0]};
                    dst_pixel_write = src_pixel_write;
                    src_pixel_strobe = dst_pixel_strobe;
                end

            end
            GET_NUMBER: begin
                if (src_pixel_write) src_pixel_strobe = 1;
            end
            LIMITED_RLE: begin
                if (rle_counter != 0) dst_pixel_write = 1;
            end
            END_OF_LINE_RLE: begin
                if (pixelcounter != 0) dst_pixel_write = 1;
            end
        endcase
    end

    always_ff @(posedge clk) begin
        if (reset) begin
            state <= SINGLE;
        end else begin
            case (state)
                SINGLE: begin
                    if (src_pixel_write && src_pixel[7]) begin
                        stored_pixel <= src_pixel[6:0];
                        state <= GET_NUMBER;
                    end
                end
                GET_NUMBER: begin
                    if (src_pixel_write) begin
                        rle_counter <= src_pixel;

                        //$display("RLE %d %d", src_pixel, dst_pixel);
                        if (src_pixel == 0) state <= END_OF_LINE_RLE;
                        else state <= LIMITED_RLE;
                    end
                end
                LIMITED_RLE: begin
                    if (rle_counter == 0) begin
                        state <= SINGLE;
                    end else if (dst_pixel_strobe) begin
                        rle_counter <= rle_counter - 1;
                    end
                end
                END_OF_LINE_RLE: begin
                    if (pixelcounter == 0) state <= SINGLE;
                end
            endcase
        end
    end
endmodule



