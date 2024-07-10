// CD-Interface Controller
// TODO implement audio
// TODO implement CD reading

module cdic (
    input clk,
    input [23:1] address,
    input [15:0] din,
    output bit [15:0] dout,
    input uds,
    input lds,
    input write_strobe,
    input cs
);

    // 16 kB of CDIC memory
    bit [15:0] ram[8192];

    wire access = cs && uds && lds;
    bit access_q = 1;

    // All access must be word aligned according to
    // https://github.com/cdifan/cdichips/blob/master/ims66490cdic.md
    always_ff @(posedge clk) begin
        access_q <= access;

        if (address[13:1] < 13'h1E00) begin  // Is it before register area?
            case (address[13:1])
                default: begin
                    if (access && cs && write_strobe) begin
                        $display("CDIC Write RAM %x %x", address[13:1], din);

                        ram[address[13:1]] <= din;
                    end else if (access && cs && !write_strobe) begin
                        $display("CDIC Read RAM %x %x", address[13:1], dout);
                    end
                end
            endcase
        end else if (cs) begin
                $display("CDIC %x", address[13:1]);
            
        end

    end

    always_comb begin
        dout = 16'h0;

        case (address[13:1])
            13'h001FFA: begin  // 0x3FF4  ABUF	Audio buffer register
                dout = 16'h0;
            end
            13'h001FFB: begin  // 0x3FF6  XBUF	Extra buffer register
                dout = 16'h0;
            end
            13'h001FFD: begin  // 0x3FFA  AUDCTL	Audio control register
                //$display("Audio control!");
                dout = 16'hd7fe;
            end
            13'h001FFE: begin  // 0x3FFC  IVEC	Interrupt vector register
                //$display("IVEC");
                dout = 16'h0;
            end
            13'h001FFF: begin  // 0x3FFE  DBUF	Data buffer register
                //$display("DBUF");
                dout = 16'h0;
            end
            default: begin
                // TODO fix this. Must be clocked for proper block ram
                //dout = ram[address[13:1]];
            end
        endcase
    end

endmodule
