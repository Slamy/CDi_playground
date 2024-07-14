// MCD 212 - DRAM and Video
// TODO Remove internal memory which cannot be synthesized. Replace with external bus
// TODO Attach an SDRAM controller

module mcd212 (
    input clk,
    input reset,
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
    output       hsync,
    output       vsync,
    output       hblank,
    output       vblank,

    output bit [24:0] sdram_addr,
    output bit        sdram_rd,
    output bit        sdram_wr,
    output bit        sdram_word,
    output bit [15:0] sdram_din,
    input      [15:0] sdram_dout,
    input             sdram_busy
);

    // Memory Swapping according to chapter 3.4
    // of MCD212 datasheet.
    bit [3:0] early_rom_cnt = 0;
    wire cs_early_rom = early_rom_cnt <= 10;
    always @(posedge clk) begin
        // first 4 memory accesses must be mapped to ROM
        if (reset) begin
            early_rom_cnt <= 0;
        end else if (cs && cpu_uds && cs_early_rom) begin
            early_rom_cnt <= early_rom_cnt + 1;
        end
    end


    wire [22:0] cpu_addressb = {cpu_address[22:1], 1'b0};
    // implementation of memory map according to MCD212 datasheet
    wire cs_ram = cpu_addressb <= 23'h3fffff && cs && !cs_early_rom;  // 4MB
    wire cs_rom = cpu_addressb >= 23'h400000 && cpu_addressb <= 23'h4ffbff && cs;
    wire cs_system_io = cpu_addressb >= 23'h4ffc00 && cpu_addressb <= 23'h4fffdf && cs;
    wire cs_channel2 = cpu_addressb >= 23'h4fffe0 && cpu_addressb <= 23'h4fffef && cs;
    wire cs_channel1 = cpu_addressb >= 23'h4ffff0 && cpu_addressb <= 23'h4fffff && cs;


    assign csrom = (cs_rom || cs_early_rom) && cs;

    // Bit 18 is the Bank selection for TD=0
    // CAS1 if A18=0, CAS2 if A18=1
    wire [19:1] ram_address = {cpu_address[18], cpu_address[21], cpu_address[17:1]};

    bit cs_q = 0;
    bit cpu_lds_q = 0;
    bit cpu_uds_q = 0;

    bit parity = 0;


    bit ram_access_q = 0;
    wire ram_access = cs_ram && (cpu_uds || cpu_lds) && !ram_access_q;

    always_comb begin
        cpu_dout = 0;
        cpu_bus_ack = 1;
        if (ram_access || sdram_busy) cpu_bus_ack = 0;

        sdram_addr[24:1] = {5'b0, ram_address[19:1]};
        sdram_addr[0] = cpu_lds && !cpu_uds;  // only active on odd byte accesses
        sdram_word = cpu_lds && cpu_uds;
        sdram_rd = cs_ram && !cpu_write_strobe;
        sdram_wr = cs_ram && cpu_write_strobe;
        sdram_din = cpu_din;

        //sdram_din[7:0] = cpu_lds ? cpu_din[7:0] : ;


        if (cs_ram) begin
            cpu_dout = sdram_dout;
        end else if (cs_channel1) begin
            case (cpu_addressb[7:0])
                8'hf0: begin
                    cpu_dout = {8'h0, !vblank, 1'b0, parity, 5'b0};
                    //cpu_dout <= {display_active, 1'b0, parity, 5'b0, display_active, 1'b0, parity, 5'b0};
                end
                default: cpu_dout = 16'h0;
            endcase
        end else if (cs_channel2) begin
            case (cpu_addressb[7:0])
                default: cpu_dout = 16'h0;
            endcase
        end
    end

    always_ff @(posedge clk) begin
        cs_q <= cs;
        cpu_uds_q <= cpu_uds;
        cpu_lds_q <= cpu_lds;
        ram_access_q <= ram_access;



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
    clut_entry clut_out;

    bit sm = 0;
    bit cf = 1;
    bit st = 0;
    bit fd = 0;
    bit cm = 0;
    bit [8:0] video_y;
    bit [12:0] video_x;
    bit new_frame;
    bit new_line;
    bit new_pixel;

    video_timing vt (
        .clk,
        .reset,
        .sm(sm),
        .cf(cf),
        .st(st),
        .cm(cm),
        .fd(fd),
        .video_y,
        .video_x,
        .hsync(hsync),
        .vsync(vsync),
        .hblank(hblank),
        .vblank(vblank),
        .new_frame,
        .new_line,
        .new_pixel
    );

    wire ica0_reset = new_frame;
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
        .register_adr(register_adr),
        .register_data(register_data),
        .register_write(register_write),
        .reload_vsr(ica0_reload_vsr),
        .vsr(ica0_vsr)
    );

    bit [21:0] file0_adr;
    bit file0_as;
    bit [15:0] file0_din;
    bit file0_bus_ack;
    bit file0_read_pixels;

    bit [7:0] file_pixel;
    bit file_pixel_strobe  /*verilator public_flat_rd*/;
    bit file_pixel_write  /*verilator public_flat_rd*/;

    bit [7:0] rle_pixel;
    bit rle_pixel_strobe  /*verilator public_flat_rd*/;
    bit rle_pixel_write  /*verilator public_flat_rd*/;

    bit [15:0] videotestram[9000]  /*verilator public_flat_rw*/;

    initial begin
        $readmemh("videotestram.mem", videotestram);
    end

    always_ff @(posedge clk) begin
        //if (file0_as && file0_bus_ack) $display("XYZ %x", file0_din);
        //if (ica0_as && ica0_bus_ack) $display("ZYX %d : ica0_din <= %d;", ica0_adr, ica0_din);
    end

    display_file_decoder file0 (
        .clk,
        .reset(0),
        .address(file0_adr),
        .as(file0_as),
        .din(file0_din),
        .bus_ack(file0_bus_ack),
        .reload_vsr(ica0_reload_vsr),
        .vsr_in(ica0_vsr),
        .pixel(file_pixel),
        .pixel_write(file_pixel_write),
        .pixel_strobe(file_pixel_strobe),
        .read_pixels(!vblank)
    );


    clut_rle rle (
        .clk,
        .reset(new_frame),
        .src_pixel(file_pixel),
        .src_pixel_write(file_pixel_write),
        .src_pixel_strobe(file_pixel_strobe),
        .dst_pixel(rle_pixel),
        .dst_pixel_write(rle_pixel_write),
        .dst_pixel_strobe(rle_pixel_strobe)
    );

    bit [7:0] synchronized_pixel;

    assign rle_pixel_strobe = new_pixel;
    bit fail = 0;

    always_ff @(posedge clk) begin
        if (new_pixel && !rle_pixel_write) fail <= 1;

        if (new_line) synchronized_pixel <= 0;
        else if (rle_pixel_write && rle_pixel_strobe) synchronized_pixel <= rle_pixel;


        clut_out <= clut[synchronized_pixel];
    end


    assign r = {clut_out.r, 2'b00};
    assign g = {clut_out.g, 2'b00};
    assign b = {clut_out.b, 2'b00};
    //assign b =  (rle_pixel_write && rle_pixel_strobe)  ? 255 : 0;

    /*
    always_ff @(posedge clk) begin
        
        if (pixel_strobe)
            $display("%x  %x %x %x", pixel, clut[pixel].r, clut[pixel].g, clut[pixel].b);
    end
    */

    always_ff @(posedge clk) begin
        //file0_din <= testram[file0_adr[19:1]];
        file0_din <= videotestram[file0_adr[19:1]-484208/2];

        if (file0_bus_ack) file0_bus_ack <= 0;
        else file0_bus_ack <= file0_as;
    end

    always_ff @(posedge clk) begin
        if (ica0_reload_vsr) $display("Reload VSR %x", ica0_vsr);
    end

    always_ff @(posedge clk) begin
        //ica0_din <= testram[ica0_adr[19:1]];

        case (ica0_adr[19:0])
            1024:   ica0_din <= 16391;
            1026:   ica0_din <= 65456;
            524208: ica0_din <= 52484;
            524210: ica0_din <= 49593;
            524212: ica0_din <= 52872;
            524214: ica0_din <= 15;
            524216: ica0_din <= 52992;
            524218: ica0_din <= 32768;
            524220: ica0_din <= 52993;
            524222: ica0_din <= 49152;
            524224: ica0_din <= 52994;
            524226: ica0_din <= 57344;
            524228: ica0_din <= 52995;
            524230: ica0_din <= 61440;
            524232: ica0_din <= 52996;
            524234: ica0_din <= 63488;
            524236: ica0_din <= 52997;
            524238: ica0_din <= 64512;
            524240: ica0_din <= 52998;
            524242: ica0_din <= 65024;
            524244: ica0_din <= 52999;
            524246: ica0_din <= 65280;
            524248: ica0_din <= 53000;
            524250: ica0_din <= 63488;
            524252: ica0_din <= 53001;
            524254: ica0_din <= 55296;
            524256: ica0_din <= 53002;
            524258: ica0_din <= 35840;
            524260: ica0_din <= 53003;
            524262: ica0_din <= 3072;
            524264: ica0_din <= 53004;
            524266: ica0_din <= 1536;
            524268: ica0_din <= 53005;
            524270: ica0_din <= 1536;
            524272: ica0_din <= 53006;
            524274: ica0_din <= 768;
            524276: ica0_din <= 53007;
            524278: ica0_din <= 768;
            524280: ica0_din <= 4096;
            524282: ica0_din <= 0;
            524284: ica0_din <= 16390;
            524286: ica0_din <= 11568;
            404784: ica0_din <= 30720;
            404786: ica0_din <= 1026;
            404788: ica0_din <= 4096;
            404790: ica0_din <= 0;
            404792: ica0_din <= 24576;
            404794: ica0_din <= 0;
            404796: ica0_din <= 28672;
            404798: ica0_din <= 0;
            404800: ica0_din <= 49164;
            404802: ica0_din <= 4883;
            404804: ica0_din <= 49536;
            404806: ica0_din <= 257;
            404808: ica0_din <= 49664;
            404810: ica0_din <= 1;
            404812: ica0_din <= 50183;
            404814: ica0_din <= 1799;
            404816: ica0_din <= 50944;
            404818: ica0_din <= 0;
            404820: ica0_din <= 51712;
            404822: ica0_din <= 0;
            404824: ica0_din <= 55296;
            404826: ica0_din <= 0;
            404828: ica0_din <= 55552;
            404830: ica0_din <= 0;
            404832: ica0_din <= 56064;
            404834: ica0_din <= 63;
            404836: ica0_din <= 49920;
            404838: ica0_din <= 0;
            404840: ica0_din <= 33023;
            404842: ica0_din <= 65535;
            404844: ica0_din <= 33144;
            404846: ica0_din <= 30870;
            404848: ica0_din <= 33426;
            404850: ica0_din <= 34741;
            404852: ica0_din <= 33636;
            404854: ica0_din <= 25700;
            404856: ica0_din <= 33897;
            404858: ica0_din <= 32115;
            404860: ica0_din <= 34178;
            404862: ica0_din <= 44950;
            404864: ica0_din <= 34450;
            404866: ica0_din <= 34741;
            404868: ica0_din <= 34706;
            404870: ica0_din <= 34741;
            404872: ica0_din <= 34936;
            404874: ica0_din <= 30870;
            404876: ica0_din <= 35202;
            404878: ica0_din <= 44950;
            404880: ica0_din <= 35463;
            404882: ica0_din <= 39880;
            404884: ica0_din <= 35698;
            404886: ica0_din <= 31097;
            404888: ica0_din <= 35941;
            404890: ica0_din <= 25963;
            404892: ica0_din <= 36225;
            404894: ica0_din <= 34952;
            404896: ica0_din <= 36562;
            404898: ica0_din <= 53970;
            404900: ica0_din <= 36624;
            404902: ica0_din <= 5676;
            404904: ica0_din <= 36965;
            404906: ica0_din <= 27513;
            404908: ica0_din <= 37206;
            404910: ica0_din <= 23915;
            404912: ica0_din <= 37525;
            404914: ica0_din <= 40349;
            404916: ica0_din <= 37838;
            404918: ica0_din <= 54998;
            404920: ica0_din <= 37995;
            404922: ica0_din <= 27499;
            404924: ica0_din <= 38166;
            404926: ica0_din <= 5654;
            404928: ica0_din <= 38464;
            404930: ica0_din <= 16448;
            404932: ica0_din <= 38846;
            404934: ica0_din <= 48830;
            404936: ica0_din <= 38970;
            404938: ica0_din <= 14906;
            404940: ica0_din <= 39204;
            404942: ica0_din <= 9252;
            404944: ica0_din <= 39475;
            404946: ica0_din <= 13107;
            404948: ica0_din <= 39759;
            404950: ica0_din <= 20303;
            404952: ica0_din <= 40051;
            404954: ica0_din <= 30875;
            404956: ica0_din <= 40236;
            404958: ica0_din <= 11336;
            404960: ica0_din <= 40506;
            404962: ica0_din <= 16470;
            404964: ica0_din <= 40805;
            404966: ica0_din <= 27506;
            404968: ica0_din <= 41024;
            404970: ica0_din <= 18525;
            404972: ica0_din <= 41245;
            404974: ica0_din <= 11322;
            404976: ica0_din <= 41586;
            404978: ica0_din <= 29298;
            404980: ica0_din <= 41842;
            404982: ica0_din <= 31097;
            404984: ica0_din <= 42020;
            404986: ica0_din <= 11328;
            404988: ica0_din <= 42388;
            404990: ica0_din <= 38036;
            404992: ica0_din <= 42644;
            404994: ica0_din <= 38036;
            404996: ica0_din <= 42898;
            404998: ica0_din <= 34741;
            405000: ica0_din <= 43154;
            405002: ica0_din <= 34741;
            405004: ica0_din <= 43360;
            405006: ica0_din <= 24672;
            405008: ica0_din <= 43620;
            405010: ica0_din <= 28260;
            405012: ica0_din <= 43924;
            405014: ica0_din <= 38036;
            405016: ica0_din <= 44162;
            405018: ica0_din <= 44950;
            405020: ica0_din <= 44304;
            405022: ica0_din <= 4112;
            405024: ica0_din <= 44664;
            405026: ica0_din <= 30870;
            405028: ica0_din <= 44920;
            405030: ica0_din <= 30870;
            405032: ica0_din <= 45176;
            405034: ica0_din <= 30870;
            405036: ica0_din <= 45417;
            405038: ica0_din <= 32115;
            405040: ica0_din <= 45788;
            405042: ica0_din <= 56540;
            405044: ica0_din <= 46044;
            405046: ica0_din <= 56540;
            405048: ica0_din <= 46228;
            405050: ica0_din <= 38036;
            405052: ica0_din <= 46484;
            405054: ica0_din <= 38036;
            405056: ica0_din <= 46756;
            405058: ica0_din <= 43947;
            405060: ica0_din <= 46996;
            405062: ica0_din <= 38036;
            405064: ica0_din <= 47247;
            405066: ica0_din <= 38293;
            405068: ica0_din <= 47489;
            405070: ica0_din <= 34952;
            405072: ica0_din <= 47826;
            405074: ica0_din <= 53970;
            405076: ica0_din <= 47944;
            405078: ica0_din <= 18504;
            405080: ica0_din <= 48342;
            405082: ica0_din <= 56797;
            405084: ica0_din <= 48533;
            405086: ica0_din <= 40349;
            405088: ica0_din <= 48846;
            405090: ica0_din <= 54998;
            405092: ica0_din <= 49003;
            405094: ica0_din <= 27499;
            405096: ica0_din <= 49920;
            405098: ica0_din <= 1;
            405100: ica0_din <= 32790;
            405102: ica0_din <= 5654;
            405104: ica0_din <= 33088;
            405106: ica0_din <= 16448;
            405108: ica0_din <= 33470;
            405110: ica0_din <= 48830;
            405112: ica0_din <= 33594;
            405114: ica0_din <= 14906;
            405116: ica0_din <= 33828;
            405118: ica0_din <= 9252;
            405120: ica0_din <= 34099;
            405122: ica0_din <= 13107;
            405124: ica0_din <= 34383;
            405126: ica0_din <= 20303;
            405128: ica0_din <= 34708;
            405130: ica0_din <= 38036;
            405132: ica0_din <= 34860;
            405134: ica0_din <= 11336;
            405136: ica0_din <= 35130;
            405138: ica0_din <= 16470;
            405140: ica0_din <= 35429;
            405142: ica0_din <= 27506;
            405144: ica0_din <= 35704;
            405146: ica0_din <= 30870;
            405148: ica0_din <= 35869;
            405150: ica0_din <= 11322;
            405152: ica0_din <= 36210;
            405154: ica0_din <= 29298;
            405156: ica0_din <= 36448;
            405158: ica0_din <= 24672;
            405160: ica0_din <= 36644;
            405162: ica0_din <= 11328;
            405164: ica0_din <= 36984;
            405166: ica0_din <= 30840;
            405168: ica0_din <= 37192;
            405170: ica0_din <= 20317;
            405172: ica0_din <= 37472;
            405174: ica0_din <= 24672;
            405176: ica0_din <= 37648;
            405178: ica0_din <= 5690;
            405180: ica0_din <= 37939;
            405182: ica0_din <= 13135;
            405184: ica0_din <= 38237;
            405186: ica0_din <= 25963;
            405188: ica0_din <= 38514;
            405190: ica0_din <= 29305;
            405192: ica0_din <= 38707;
            405194: ica0_din <= 13128;
            405196: ica0_din <= 39005;
            405198: ica0_din <= 23901;
            405200: ica0_din <= 39304;
            405202: ica0_din <= 34952;
            405204: ica0_din <= 39531;
            405206: ica0_din <= 27506;
            405208: ica0_din <= 39780;
            405210: ica0_din <= 25700;
            405212: ica0_din <= 40079;
            405214: ica0_din <= 36757;
            405216: ica0_din <= 40271;
            405218: ica0_din <= 22117;
            405220: ica0_din <= 40577;
            405222: ica0_din <= 33160;
            405224: ica0_din <= 40720;
            405226: ica0_din <= 4112;
            405228: ica0_din <= 41180;
            405230: ica0_din <= 56540;
            405232: ica0_din <= 41317;
            405234: ica0_din <= 25957;
            405236: ica0_din <= 41523;
            405238: ica0_din <= 14920;
            405240: ica0_din <= 41864;
            405242: ica0_din <= 34959;
            405244: ica0_din <= 42042;
            405246: ica0_din <= 16463;
            405248: ica0_din <= 42319;
            405250: ica0_din <= 20317;
            405252: ica0_din <= 42512;
            405254: ica0_din <= 5683;
            405256: ica0_din <= 42866;
            405258: ica0_din <= 31105;
            405260: ica0_din <= 43094;
            405262: ica0_din <= 23909;
            405264: ica0_din <= 43350;
            405266: ica0_din <= 22117;
            405268: ica0_din <= 43655;
            405270: ica0_din <= 50608;
            405272: ica0_din <= 43805;
            405274: ica0_din <= 9274;
            405276: ica0_din <= 44048;
            405278: ica0_din <= 4112;
            405280: ica0_din <= 44310;
            405282: ica0_din <= 7475;
            405284: ica0_din <= 44588;
            405286: ica0_din <= 13128;
            405288: ica0_din <= 44864;
            405290: ica0_din <= 18518;
            405292: ica0_din <= 45142;
            405294: ica0_din <= 22102;
            405296: ica0_din <= 45356;
            405298: ica0_din <= 11308;
            405300: ica0_din <= 45618;
            405302: ica0_din <= 12850;
            405304: ica0_din <= 45853;
            405306: ica0_din <= 7453;
            405308: ica0_din <= 46209;
            405310: ica0_din <= 33153;
            405312: ica0_din <= 46472;
            405314: ica0_din <= 38301;
            405316: ica0_din <= 46738;
            405318: ica0_din <= 34741;
            405320: ica0_din <= 46908;
            405322: ica0_din <= 18040;
            405324: ica0_din <= 47169;
            405326: ica0_din <= 21885;
            405328: ica0_din <= 47559;
            405330: ica0_din <= 52942;
            405332: ica0_din <= 47780;
            405334: ica0_din <= 42148;
            405336: ica0_din <= 48017;
            405338: ica0_din <= 37265;
            405340: ica0_din <= 48311;
            405342: ica0_din <= 47031;
            405344: ica0_din <= 48555;
            405346: ica0_din <= 43947;
            405348: ica0_din <= 48797;
            405350: ica0_din <= 40349;
            405352: ica0_din <= 49044;
            405354: ica0_din <= 38036;
            405356: ica0_din <= 4096;
            405358: ica0_din <= 0;
            405360: ica0_din <= 4096;
            405362: ica0_din <= 0;
            405364: ica0_din <= 4096;
            405366: ica0_din <= 0;
            405368: ica0_din <= 4096;
            405370: ica0_din <= 0;
            405372: ica0_din <= 4096;
            405374: ica0_din <= 0;
            405376: ica0_din <= 4096;
            405378: ica0_din <= 0;
            405380: ica0_din <= 4096;
            405382: ica0_din <= 0;
            405384: ica0_din <= 4096;
            405386: ica0_din <= 0;
            405388: ica0_din <= 4096;
            405390: ica0_din <= 0;
            405392: ica0_din <= 4096;
            405394: ica0_din <= 0;
            405396: ica0_din <= 4096;
            405398: ica0_din <= 0;
            405400: ica0_din <= 4096;
            405402: ica0_din <= 0;
            405404: ica0_din <= 4096;
            405406: ica0_din <= 0;
            405408: ica0_din <= 4096;
            405410: ica0_din <= 0;
            405412: ica0_din <= 4096;
            405414: ica0_din <= 0;
            405416: ica0_din <= 4096;
            405418: ica0_din <= 0;
            405420: ica0_din <= 4096;
            405422: ica0_din <= 0;
            405424: ica0_din <= 4096;
            405426: ica0_din <= 0;
            405428: ica0_din <= 4096;
            405430: ica0_din <= 0;
            405432: ica0_din <= 4096;
            405434: ica0_din <= 0;
            405436: ica0_din <= 4096;
            405438: ica0_din <= 0;
            405440: ica0_din <= 4096;
            405442: ica0_din <= 0;
            405444: ica0_din <= 4096;
            405446: ica0_din <= 0;
            405448: ica0_din <= 4096;
            405450: ica0_din <= 0;
            405452: ica0_din <= 4096;
            405454: ica0_din <= 0;
            405456: ica0_din <= 4096;
            405458: ica0_din <= 0;
            405460: ica0_din <= 4096;
            405462: ica0_din <= 0;
            405464: ica0_din <= 4096;
            405466: ica0_din <= 0;
            405468: ica0_din <= 4096;
            405470: ica0_din <= 0;
            405472: ica0_din <= 4096;
            405474: ica0_din <= 0;
            405476: ica0_din <= 4096;
            405478: ica0_din <= 0;
            405480: ica0_din <= 4096;
            405482: ica0_din <= 0;
            405484: ica0_din <= 4096;
            405486: ica0_din <= 0;
            405488: ica0_din <= 4096;
            405490: ica0_din <= 0;
            405492: ica0_din <= 4096;
            405494: ica0_din <= 0;
            405496: ica0_din <= 4096;
            405498: ica0_din <= 0;
            405500: ica0_din <= 4096;
            405502: ica0_din <= 0;
            405504: ica0_din <= 4096;
            405506: ica0_din <= 0;
            405508: ica0_din <= 4096;
            405510: ica0_din <= 0;
            405512: ica0_din <= 4096;
            405514: ica0_din <= 0;
            405516: ica0_din <= 4096;
            405518: ica0_din <= 0;
            405520: ica0_din <= 4096;
            405522: ica0_din <= 0;
            405524: ica0_din <= 4096;
            405526: ica0_din <= 0;
            405528: ica0_din <= 4096;
            405530: ica0_din <= 0;
            405532: ica0_din <= 4096;
            405534: ica0_din <= 0;
            405536: ica0_din <= 4096;
            405538: ica0_din <= 0;
            405540: ica0_din <= 4096;
            405542: ica0_din <= 0;
            405544: ica0_din <= 4096;
            405546: ica0_din <= 0;
            405548: ica0_din <= 4096;
            405550: ica0_din <= 0;
            405552: ica0_din <= 4096;
            405554: ica0_din <= 0;
            405556: ica0_din <= 4096;
            405558: ica0_din <= 0;
            405560: ica0_din <= 4096;
            405562: ica0_din <= 0;
            405564: ica0_din <= 4096;
            405566: ica0_din <= 0;
            405568: ica0_din <= 4096;
            405570: ica0_din <= 0;
            405572: ica0_din <= 4096;
            405574: ica0_din <= 0;
            405576: ica0_din <= 4096;
            405578: ica0_din <= 0;
            405580: ica0_din <= 4096;
            405582: ica0_din <= 0;
            405584: ica0_din <= 4096;
            405586: ica0_din <= 0;
            405588: ica0_din <= 4096;
            405590: ica0_din <= 0;
            405592: ica0_din <= 4096;
            405594: ica0_din <= 0;
            405596: ica0_din <= 4096;
            405598: ica0_din <= 0;
            405600: ica0_din <= 4096;
            405602: ica0_din <= 0;
            405604: ica0_din <= 4096;
            405606: ica0_din <= 0;
            405608: ica0_din <= 4096;
            405610: ica0_din <= 0;
            405612: ica0_din <= 4096;
            405614: ica0_din <= 0;
            405616: ica0_din <= 4096;
            405618: ica0_din <= 0;
            405620: ica0_din <= 4096;
            405622: ica0_din <= 0;
            405624: ica0_din <= 4096;
            405626: ica0_din <= 0;
            405628: ica0_din <= 4096;
            405630: ica0_din <= 0;
            405632: ica0_din <= 4096;
            405634: ica0_din <= 0;
            405636: ica0_din <= 4096;
            405638: ica0_din <= 0;
            405640: ica0_din <= 4096;
            405642: ica0_din <= 0;
            405644: ica0_din <= 4096;
            405646: ica0_din <= 0;
            405648: ica0_din <= 4096;
            405650: ica0_din <= 0;
            405652: ica0_din <= 4096;
            405654: ica0_din <= 0;
            405656: ica0_din <= 4096;
            405658: ica0_din <= 0;
            405660: ica0_din <= 4096;
            405662: ica0_din <= 0;
            405664: ica0_din <= 4096;
            405666: ica0_din <= 0;
            405668: ica0_din <= 4096;
            405670: ica0_din <= 0;
            405672: ica0_din <= 4096;
            405674: ica0_din <= 0;
            405676: ica0_din <= 4096;
            405678: ica0_din <= 0;
            405680: ica0_din <= 4096;
            405682: ica0_din <= 0;
            405684: ica0_din <= 4096;
            405686: ica0_din <= 0;
            405688: ica0_din <= 4096;
            405690: ica0_din <= 0;
            405692: ica0_din <= 4096;
            405694: ica0_din <= 0;
            405696: ica0_din <= 4096;
            405698: ica0_din <= 0;
            405700: ica0_din <= 4096;
            405702: ica0_din <= 0;
            405704: ica0_din <= 4096;
            405706: ica0_din <= 0;
            405708: ica0_din <= 4096;
            405710: ica0_din <= 0;
            405712: ica0_din <= 4096;
            405714: ica0_din <= 0;
            405716: ica0_din <= 4096;
            405718: ica0_din <= 0;
            405720: ica0_din <= 4096;
            405722: ica0_din <= 0;
            405724: ica0_din <= 4096;
            405726: ica0_din <= 0;
            405728: ica0_din <= 4096;
            405730: ica0_din <= 0;
            405732: ica0_din <= 4096;
            405734: ica0_din <= 0;
            405736: ica0_din <= 4096;
            405738: ica0_din <= 0;
            405740: ica0_din <= 4096;
            405742: ica0_din <= 0;
            405744: ica0_din <= 4096;
            405746: ica0_din <= 0;
            405748: ica0_din <= 4096;
            405750: ica0_din <= 0;
            405752: ica0_din <= 4096;
            405754: ica0_din <= 0;
            405756: ica0_din <= 4096;
            405758: ica0_din <= 0;
            405760: ica0_din <= 4096;
            405762: ica0_din <= 0;
            405764: ica0_din <= 4096;
            405766: ica0_din <= 0;
            405768: ica0_din <= 4096;
            405770: ica0_din <= 0;
            405772: ica0_din <= 4096;
            405774: ica0_din <= 0;
            405776: ica0_din <= 4096;
            405778: ica0_din <= 0;
            405780: ica0_din <= 4096;
            405782: ica0_din <= 0;
            405784: ica0_din <= 4096;
            405786: ica0_din <= 0;
            405788: ica0_din <= 4096;
            405790: ica0_din <= 0;
            405792: ica0_din <= 4096;
            405794: ica0_din <= 0;
            405796: ica0_din <= 4096;
            405798: ica0_din <= 0;
            405800: ica0_din <= 4096;
            405802: ica0_din <= 0;
            405804: ica0_din <= 4096;
            405806: ica0_din <= 0;
            405808: ica0_din <= 4096;
            405810: ica0_din <= 0;
            405812: ica0_din <= 4096;
            405814: ica0_din <= 0;
            405816: ica0_din <= 4096;
            405818: ica0_din <= 0;
            405820: ica0_din <= 4096;
            405822: ica0_din <= 0;
            405824: ica0_din <= 4096;
            405826: ica0_din <= 0;
            405828: ica0_din <= 4096;
            405830: ica0_din <= 0;
            405832: ica0_din <= 4096;
            405834: ica0_din <= 0;
            405836: ica0_din <= 4096;
            405838: ica0_din <= 0;
            405840: ica0_din <= 4096;
            405842: ica0_din <= 0;
            405844: ica0_din <= 4096;
            405846: ica0_din <= 0;
            405848: ica0_din <= 4096;
            405850: ica0_din <= 0;
            405852: ica0_din <= 4096;
            405854: ica0_din <= 0;
            405856: ica0_din <= 4096;
            405858: ica0_din <= 0;
            405860: ica0_din <= 4096;
            405862: ica0_din <= 0;
            405864: ica0_din <= 4096;
            405866: ica0_din <= 0;
            405868: ica0_din <= 4096;
            405870: ica0_din <= 0;
            405872: ica0_din <= 4096;
            405874: ica0_din <= 0;
            405876: ica0_din <= 53248;
            405878: ica0_din <= 0;
            405880: ica0_din <= 53504;
            405882: ica0_din <= 0;
            405884: ica0_din <= 53760;
            405886: ica0_din <= 0;
            405888: ica0_din <= 54016;
            405890: ica0_din <= 0;
            405892: ica0_din <= 54272;
            405894: ica0_din <= 0;
            405896: ica0_din <= 54528;
            405898: ica0_din <= 0;
            405900: ica0_din <= 54784;
            405902: ica0_din <= 0;
            405904: ica0_din <= 55040;
            405906: ica0_din <= 0;
            405908: ica0_din <= 4096;
            405910: ica0_din <= 0;
            405912: ica0_din <= 4096;
            405914: ica0_din <= 0;
            405916: ica0_din <= 4096;
            405918: ica0_din <= 0;
            405920: ica0_din <= 4096;
            405922: ica0_din <= 0;
            405924: ica0_din <= 4096;
            405926: ica0_din <= 0;
            405928: ica0_din <= 4096;
            405930: ica0_din <= 0;
            405932: ica0_din <= 4096;
            405934: ica0_din <= 0;
            405936: ica0_din <= 4096;
            405938: ica0_din <= 0;
            405940: ica0_din <= 4096;
            405942: ica0_din <= 0;
            405944: ica0_din <= 8198;
            405946: ica0_din <= 30800;
            405948: ica0_din <= 20487;
            405950: ica0_din <= 25456;
        endcase

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

