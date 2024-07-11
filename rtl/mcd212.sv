// MCD 212 - DRAM and Video
// TODO Remove internal memory which cannot be synthesized. Replace with external bus
// TODO Attach an SDRAM controller

module mcd212 (
    input clk,
    input [22:1] address,
    input [15:0] din,
    output bit [15:0] dout,
    input uds,
    input lds,
    input write_strobe,
    output bit bus_ack,
    input cs,
    output csrom
);

    // TODO remove this
`ifdef VERILATOR
    bit [15:0] testram[512*1024]  /*verilator public_flat_rw*/;
`else
    bit [15:0] testram[16]  /*verilator public_flat_rw*/;
`endif

    wire [22:0] addressb = {address[22:1], 1'b0};
    // implementation of memory map according to MCD212 datasheet
    wire cs_ram = addressb <= 23'h3fffff && cs;  // 4MB
    wire cs_rom = addressb >= 23'h400000 && addressb <= 23'h4ffbff && cs;
    wire cs_system_io = addressb >= 23'h4ffc00 && addressb <= 23'h4fffdf && cs;
    wire cs_channel2 = addressb >= 23'h4fffe0 && addressb <= 23'h4fffef && cs;
    wire cs_channel1 = addressb >= 23'h4ffff0 && addressb <= 23'h4fffff && cs;

    // Memory Swapping according to chapter 3.4
    // of MCD212 datasheet.
    bit [3:0] early_rom_cnt = 0;
    wire cs_early_rom = early_rom_cnt <= 10;
    always @(posedge clk) begin
        // first 4 memory accesses must be mapped to ROM
        if (cs && uds) begin
            if (cs_early_rom) early_rom_cnt <= early_rom_cnt + 1;
        end

    end

    assign csrom = (cs_rom || cs_early_rom) && cs;

    wire [9:0] ras = {address[19], address[10], address[18:11]};
    wire [9:0] cas = {address[10:1]};

    // Bit 18 is the Bank selection for TD=0
    // CAS1 if A18=0, CAS2 if A18=1
    wire [19:1] ram_address = {address[18], address[21], address[17:1]};

    bit cs_q = 0;
    bit lds_q = 0;
    bit uds_q = 0;

    bit parity = 0;
    bit display_active = 0;

    bit [7:0] tempcnt = 0;

    always_ff @(posedge clk) begin
        tempcnt <= tempcnt + 1;
        display_active <= tempcnt[7];
    end
    bit  ram_read_access_q = 0;
    wire ram_read_access = !write_strobe && cs_ram && (uds || lds) && !ram_read_access_q;

    always_comb begin
        bus_ack = 1;

        if (ram_read_access) bus_ack = 0;
    end

    always_ff @(posedge clk) begin
        cs_q <= cs;
        uds_q <= uds;
        lds_q <= lds;
        ram_read_access_q <= ram_read_access;

        if (cs_ram) begin
            if (uds && write_strobe) begin
                testram[ram_address[19:1]][15:8] <= din[15:8];
            end
            if (lds && write_strobe) begin
                testram[ram_address[19:1]][7:0] <= din[7:0];
            end

            if (!write_strobe) begin
                dout <= testram[ram_address[19:1]];
            end
        end else if (cs_channel1) begin
            case (addressb[7:0])
                8'hf0: begin
                    dout <= {8'h0, display_active, 1'b0, parity, 5'b0};
                    //dout <= {display_active, 1'b0, parity, 5'b0, display_active, 1'b0, parity, 5'b0};
                end
                default: dout <= 16'h0;
            endcase
        end else if (cs_channel2) begin
            case (addressb[7:0])
                default: dout <= 16'h0;
            endcase
        end

        /*
        if ((lds || uds) && cs_ram && !write_strobe && bus_ack) 
            $display("Read DRAM %x %x", addressb, dout);
        
        if (lds && uds && cs_ram && write_strobe) begin
            $display("Write DRAM %x %x", addressb, din);
            assert (!(addressb==0 && din ==16'h5aa5));
        end else if (lds && cs_ram && write_strobe)
            $display("Write Lower Byte RAM %x %x", addressb, din);
        else if (uds && cs_ram && write_strobe)
            $display("Write Upper Byte RAM %x %x", addressb, din);
        */

        if ((lds || uds) && cs_channel1 && write_strobe)
            $display("Write Channel 1 %x %x", addressb, din);

        if ((lds || uds) && cs_channel1 && !write_strobe)
            $display("Read Channel 1 %x %x", addressb, dout);

        if ((lds || uds) && cs_channel2 && write_strobe)
            $display("Write Channel 2 %x %x", addressb, din);

        if ((lds || uds) && cs_channel2 && !write_strobe)
            $display("Read Channel 2 %x %x", addressb, dout);

        if ((lds || uds) && cs_system_io && write_strobe)
            $display("Write Sys %x %x", addressb, din);
    end

endmodule

