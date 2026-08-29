`ifndef HEADER_UTIL
`define HEADER_UTIL

typedef struct {
    bit [28:0] y_adr;
    bit [28:0] u_adr;
    bit [28:0] v_adr;
    bit first_intra_frame_of_gop;
    bit first_intra_frame_of_seq;
    bit [10:0] width;
    bit [8:0] height;
    bit [10:0] luma_width;
    bit [9:0] chroma_width;
    bit [7:0] video_status;  // tempref and picture type
    bit [31:0] timecode;
    bit [7:0] frameperiod_rawhdr;
} planar_yuv_s;

typedef struct packed {
    bit [7:0] factor_r2r;
    bit [7:0] factor_l2r;
    bit [7:0] factor_r2l;
    bit [7:0] factor_l2l;
} linear_volume_s;

function [31:0] ones_mask(bit [4:0] n);
    begin
        ones_mask = (32'h1 << n) - 1;  // n ones at LSB
    end
endfunction

function [31:0] reverse_endian_32;
    input [31:0] data_in;
    begin
        reverse_endian_32 = {data_in[7:0], data_in[15:8], data_in[23:16], data_in[31:24]};
    end
endfunction

// https://vlsiverify.com/verilog/verilog-codes/binary-to-gray/
module b2g_converter #(
    parameter WIDTH = 4
) (
    input  [WIDTH-1:0] binary,
    output [WIDTH-1:0] gray
);
    genvar i;
    generate
        for (i = 0; i < WIDTH - 1; i++) begin : bits
            assign gray[i] = binary[i] ^ binary[i+1];
        end
    endgenerate

    assign gray[WIDTH-1] = binary[WIDTH-1];
endmodule

// from https://vlsiverify.com/verilog/verilog-codes/gray-to-binary/
module g2b_converter #(
    parameter WIDTH = 4
) (
    input  [WIDTH-1:0] gray,
    output [WIDTH-1:0] binary
);
    genvar i;
    generate
        for (i = 0; i < WIDTH; i++) begin : bits
            assign binary[i] = ^(gray >> i);
        end
    endgenerate
endmodule

`endif
