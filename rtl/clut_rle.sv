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


    always_ff @(posedge clk) begin
        dst_pixel_write  <= 0;
        src_pixel_strobe <= 0;

        if (reset) begin
            state <= SINGLE;
        end else begin
            case (state)
                SINGLE: begin
                    if (src_pixel_write && !src_pixel_strobe) begin
                        dst_pixel <= {1'b0, src_pixel[6:0]};
                        src_pixel_strobe <= 1;

                        if (src_pixel[7]) begin
                            state <= GET_NUMBER;
                        end else begin
                            dst_pixel_write <= 1;
                        end
                    end
                end
                GET_NUMBER: begin
                    if (src_pixel_write && !src_pixel_strobe) begin
                        rle_counter <= src_pixel;
                        src_pixel_strobe <= 1;

                        if (src_pixel == 0) state <= END_OF_LINE_RLE;
                        else state <= LIMITED_RLE;
                    end
                end
                LIMITED_RLE: begin
                    if (rle_counter == 0) begin
                        state <= SINGLE;
                    end else begin
                        rle_counter <= rle_counter - 1;
                        dst_pixel_write <= 1;
                    end
                end
                END_OF_LINE_RLE: begin
                    state <= SINGLE;

                end
            endcase
        end
    end
endmodule



