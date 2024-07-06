module mcd212 (
    input clk,
    input [22:1] cpu_address,
    input [15:0] cpu_din,
    output bit [15:0] cpu_dout,
    input cpu_uds,
    input cpu_lds,
    input cpu_write_strobe,
    output bit cpu_bus_ack,
    input cs,
    output csrom,

    output [7:0] r,
    output [7:0] g,
    output [7:0] b,
    output hsync,
    output vsync
);
    bit [15:0] testram[512*1024]  /*verilator public_flat_rw*/;

    initial begin
        //$readmemh("ramdump.mem", testram);
    end


    wire [22:0] cpu_addressb = {cpu_address[22:1], 1'b0};
    // implementation of memory map according to MCD212 datasheet
    wire cs_ram = cpu_addressb <= 23'h3fffff && cs;  // 4MB
    wire cs_rom = cpu_addressb >= 23'h400000 && cpu_addressb <= 23'h4ffbff && cs;
    wire cs_system_io = cpu_addressb >= 23'h4ffc00 && cpu_addressb <= 23'h4fffdf && cs;
    wire cs_channel2 = cpu_addressb >= 23'h4fffe0 && cpu_addressb <= 23'h4fffef && cs;
    wire cs_channel1 = cpu_addressb >= 23'h4ffff0 && cpu_addressb <= 23'h4fffff && cs;

    // Memory Swapping according to chapter 3.4
    // of MCD212 datasheet.
    bit [3:0] early_rom_cnt = 0;
    wire cs_early_rom = early_rom_cnt <= 10;
    always @(posedge clk) begin
        // first 4 memory accesses must be mapped to ROM
        if (cs && cpu_uds) begin
            if (cs_early_rom) early_rom_cnt <= early_rom_cnt + 1;
        end
    end

    assign csrom = (cs_rom || cs_early_rom) && cs;

    //wire [9:0] ras = {cpu_address[19], cpu_address[10], cpu_address[18:11]};
    //wire [9:0] cas = {cpu_address[10:1]};

    // Bit 18 is the Bank selection for TD=0
    // CAS1 if A18=0, CAS2 if A18=1
    wire [19:1] ram_address = {cpu_address[18], cpu_address[21], cpu_address[17:1]};

    bit cs_q = 0;
    bit cpu_lds_q = 0;
    bit cpu_uds_q = 0;

    bit parity = 0;
    bit display_active = 0;

    bit [7:0] tempcnt = 0;

    always_ff @(posedge clk) begin
        tempcnt <= tempcnt + 1;
        display_active <= tempcnt[7];
    end
    bit ram_read_access_q = 0;
    wire ram_read_access = !cpu_write_strobe && cs_ram && (cpu_uds || cpu_lds) && !ram_read_access_q;

    always_comb begin
        cpu_bus_ack = 1;

        if (ram_read_access) cpu_bus_ack = 0;
    end

    always_ff @(posedge clk) begin
        cs_q <= cs;
        cpu_uds_q <= cpu_uds;
        cpu_lds_q <= cpu_lds;
        ram_read_access_q <= ram_read_access;

        if (cs_ram) begin
            if (cpu_uds && cpu_write_strobe) begin
                testram[ram_address[19:1]][15:8] <= cpu_din[15:8];
            end
            if (cpu_lds && cpu_write_strobe) begin
                testram[ram_address[19:1]][7:0] <= cpu_din[7:0];
            end

            if (!cpu_write_strobe) begin
                cpu_dout <= testram[ram_address[19:1]];
            end
        end else if (cs_channel1) begin
            case (cpu_addressb[7:0])
                8'hf0: begin
                    cpu_dout <= {8'h0, display_active, 1'b0, parity, 5'b0};
                    //cpu_dout <= {display_active, 1'b0, parity, 5'b0, display_active, 1'b0, parity, 5'b0};
                end
                default: cpu_dout <= 16'h0;
            endcase
        end else if (cs_channel2) begin
            case (cpu_addressb[7:0])
                default: cpu_dout <= 16'h0;
            endcase
        end

        /*
        if ((cpu_lds || cpu_uds) && cs_ram && !cpu_write_strobe && cpu_bus_ack) 
            $display("Read DRAM %x %x", cpu_addressb, cpu_dout);
        
        if (cpu_lds && cpu_uds && cs_ram && cpu_write_strobe) begin
            $display("Write DRAM %x %x", cpu_addressb, cpu_din);
            assert (!(cpu_addressb==0 && cpu_din ==16'h5aa5));
        end else if (cpu_lds && cs_ram && cpu_write_strobe)
            $display("Write Lower Byte RAM %x %x", cpu_addressb, cpu_din);
        else if (cpu_uds && cs_ram && cpu_write_strobe)
            $display("Write Upper Byte RAM %x %x", cpu_addressb, cpu_din);
        */

        if ((cpu_lds || cpu_uds) && cs_channel1 && cpu_write_strobe)
            $display("Write Channel 1 %x %x", cpu_addressb, cpu_din);

        if ((cpu_lds || cpu_uds) && cs_channel1 && !cpu_write_strobe)
            $display("Read Channel 1 %x %x", cpu_addressb, cpu_dout);

        if ((cpu_lds || cpu_uds) && cs_channel2 && cpu_write_strobe)
            $display("Write Channel 2 %x %x", cpu_addressb, cpu_din);

        if ((cpu_lds || cpu_uds) && cs_channel2 && !cpu_write_strobe)
            $display("Read Channel 2 %x %x", cpu_addressb, cpu_dout);

        if ((cpu_lds || cpu_uds) && cs_system_io && cpu_write_strobe)
            $display("Write Sys %x %x", cpu_addressb, cpu_din);
    end

    typedef struct packed {
        bit [5:0] r;
        bit [5:0] g;
        bit [5:0] b;
    } clut_entry;

    typedef struct packed {
        bit [3:0] op;
        bit rf;
        bit [5:0] wf;
        bit [9:0] x;
    } region_entry;

    region_entry region_control[8];

    clut_entry clut[256];
    clut_entry trans_color_plane_a;
    clut_entry trans_color_plane_b;
    clut_entry mask_color_plane_a;
    clut_entry mask_color_plane_b;

    bit sm = 0;
    bit cf = 0;
    bit st = 0;
    bit fd = 1;  // 60Hz
    bit cm = 0;
    bit [8:0] video_y;
    bit [8:0] video_x;
    video_timing vt (
        .clk,
        .sm,
        .cf,
        .st,
        .cm,
        .fd,
        .video_y,
        .video_x,
        .hsync,
        .vsync
    );

    bit ica0_reset = 1;
    bit [21:0] ica0_adr;
    bit ica0_as;
    bit [15:0] ica0_din;
    bit ica0_bus_ack;

    bit [6:0] register_adr;
    bit [23:0] register_data;
    bit register_write;

    bit ica0_reload_vsr;
    bit [21:0] ica0_vsr;

    ica_dca_ctrl ica0 (
        .clk,
        .reset(ica0_reset),
        .address(ica0_adr),
        .as(ica0_as),
        .din(ica0_din),
        .bus_ack(ica0_bus_ack),
        .register_adr,
        .register_data,
        .register_write,
        .reload_vsr(ica0_reload_vsr),
        .vsr(ica0_vsr)
    );

    bit [21:0] file0_adr;
    bit file0_as;
    bit [15:0] file0_din;
    bit file0_bus_ack;

    bit [7:0] pixel;
    bit pixel_strobe;

    display_file_decoder file0 (
        .clk,
        .reset(0),
        .address(file0_adr),
        .as(file0_as),
        .din(file0_din),
        .bus_ack(file0_bus_ack),
        .reload_vsr(ica0_reload_vsr),
        .vsr_in(ica0_vsr),
        .pixel,
        .pixel_strobe
    );

    always_ff @(posedge clk) begin
        if (pixel_strobe) $display("%x  %x %x %x",pixel, clut[pixel].r, clut[pixel].g, clut[pixel].b);
    end

    always_ff @(posedge clk) begin
        file0_din <= testram[file0_adr[19:1]];

        if (file0_bus_ack) file0_bus_ack <= 0;
        else file0_bus_ack <= file0_as;
    end

    always_ff @(posedge clk) begin
        if (ica0_reload_vsr) $display("Reload VSR %x", ica0_vsr);
    end

    initial begin
        @(posedge clk) @(posedge clk) @(posedge clk) ica0_reset = 0;
    end

    always_ff @(posedge clk) begin
        ica0_din <= testram[ica0_adr[19:1]];

        if (ica0_bus_ack) ica0_bus_ack <= 0;
        else ica0_bus_ack <= ica0_as;
    end

    bit [15:0] cursor[16];

    bit [1:0] clut_bank;
    bit [9:0] cursor_x;
    bit [9:0] cursor_y;

    always_ff @(posedge clk) begin
        if (register_write) begin
            case (register_adr)
                7'h40: begin
                    // Image Coding Method
                    $display("Coding %b %b", register_data[11:8], register_data[3:0]);
                end
                7'h41: begin
                    // Transparency Control
                end
                7'h42: begin
                    // Plane Order
                end
                7'h43: begin
                    // CLUT Bank
                    clut_bank <= register_data[1:0];
                end
                7'h44: begin
                    trans_color_plane_a <= {
                        register_data[23:18], register_data[15:10], register_data[7:2]
                    };
                end
                7'h46: begin
                    trans_color_plane_b <= {
                        register_data[23:18], register_data[15:10], register_data[7:2]
                    };
                end
                7'h47: begin
                    mask_color_plane_a <= {
                        register_data[23:18], register_data[15:10], register_data[7:2]
                    };
                end
                7'h49: begin
                    mask_color_plane_b <= {
                        register_data[23:18], register_data[15:10], register_data[7:2]
                    };
                end
                7'h4a: begin
                    // DYUV Abs. Start Value for Plane A
                end
                7'h4b: begin
                    // DYUV Abs. Start Value for Plane B
                end
                7'h4d: begin
                    // Cursor Position
                    cursor_x <= register_data[9:0];
                    cursor_y <= register_data[21:12];
                end
                7'h4e: begin
                    // Cursor Control
                end

                7'h4f: begin
                    // Cursor Pattern
                    cursor[register_data[19:16]] <= register_data[15:0];

                    $display("Cursor %x %b", register_data[19:16], register_data[15:0]);
                end

                7'h58: begin
                    // Backdrop Color
                end
                7'h59: begin
                    // Mosaic Pixel Hold for Plane A
                end
                7'h5b: begin
                    // Weight Factor for Plane A
                end
                default: begin
                    if (register_adr >= 7'h40) begin
                        $display("Ignored %x", register_adr);
                    end
                end
            endcase

            if (register_adr[6:3] == 4'b1010) begin
                $display("Region %d %b", register_adr[2:0], register_data);
                region_control[register_adr[2:0]] <= {register_data[23:20], register_data[16:0]};
            end

            if (register_adr <= 7'h3f) begin
                // CLUT Color 0 to 63
                $display("CLUT  %d  %d %d %d", {clut_bank, register_adr[5:0]},
                         register_data[23:18], register_data[15:10], register_data[7:2]);
                clut[{
                    clut_bank, register_adr[5:0]
                }] <= {
                    register_data[23:18], register_data[15:10], register_data[7:2]
                };
            end
        end
    end
endmodule

