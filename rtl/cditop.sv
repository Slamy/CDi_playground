`include "videotypes.svh"
`include "mpeg/util.svh"

module cditop (
    input clk30,
    input clk_audio,
    input clk_mpeg,
    input external_reset,

    input tvmode_pal,

    input debug_disable_vcd_clock,
    input debug_activate_vcd_filter,
    input debug_uart_fake_space,
    input [1:0] debug_force_video_plane,
    input [1:0] debug_limited_to_full,
    input audio_cd_in_tray,
    input [2:0] config_audio_mixing,

    output bit ce_pix,
    output bit HBlank,
    output bit HSync,
    output bit VBlank,
    output bit VSync,
    output vga_f1,

    output rgb888_s vidout,

    output [24:0] sdram_addr,
    output        sdram_rd,
    output        sdram_wr,
    output        sdram_word,
    output [15:0] sdram_din,
    input  [15:0] sdram_dout,
    input         sdram_busy,
    output        sdram_burst,
    output        sdram_refresh,
    input         sdram_burstdata_valid,

    ddr_if.to_host ddrif,

    output scc68_uart_tx,
    input  scc68_uart_rx,

    input [12:0] slave_worm_adr,
    input [7:0] slave_worm_data,
    input slave_worm_wr,

    input [12:0] nvram_backup_restore_adr,
    input [7:0] nvram_restore_data,
    output [7:0] nvram_backup_data,
    input nvram_restore_write,
    output bit nvram_cpu_changed,
    input nvram_allow_cpu_access,

    bytestream.source slave_serial_out,
    bytestream.sink slave_serial_in,
    output slave_rts,
    input rc_eye,

    bytestream.source scc68070_bypass_serial_out,
    bytestream.sink scc68070_bypass_serial_in,
    output scc68070_rts,

    // IO for CD data
    output bit [31:0] cd_seek_lba,
    output bit cd_seek_lba_valid,
    input [15:0] cd_data,
    input cd_data_valid,
    output cd_sector_tick,
    input cd_sector_delivered,
    output cd_stop_sector_delivery,

    input  cd_img_mount,
    input  cd_img_mounted,
    output tray_is_closed,

    output signed [15:0] audio_left,
    output signed [15:0] audio_right,

    output fail_not_enough_words,
    output fail_too_much_data,
    input config_disable_cpu_starve,
    input config_auto_play,
    input config_disable_vmpeg,
    input [64:0] hps_rtc
);

    wire reset;

    parallel_spi slave_servo_spi ();

    wire write_strobe  /*verilator public_flat_rd*/;
    wire as  /*verilator public_flat_rd*/;
    wire lds  /*verilator public_flat_rd*/;
    wire uds  /*verilator public_flat_rd*/;

    bit bus_ack  /*verilator public_flat_rd*/;

    bit [15:0] data_in;
    wire [15:0] cpu_data_out;
    wire [23:1] addr;
    wire [23:0] addr_byte  /*verilator public_flat_rd*/ = {addr[23:1], 1'b0};

    wire [15:0] cpu_data  /*verilator public_flat_rd*/ = write_strobe ? cpu_data_out : data_in;

    wire mcd212_bus_ack;
    bit cdic_bus_ack;
    bit vmpeg_bus_ack;
    bit mk48_bus_ack;
    wire [15:0] mcd212_dout;
    wire [15:0] cdic_dout;
    wire [15:0] vmpeg_dout;
    wire [7:0] mk48_dout;

    wire attex_cs_mcd212 = ((addr_byte <= 24'h27ffff) || (addr_byte >= 24'h400000)) && as && !addr[23];
    wire dvc_ram_cs = ((addr_byte[23:20] == 4'hd) || (addr_byte[23:19] == 5'b11101)) && as;
    wire dvc_rom_cs = (addr_byte[23:18] == 6'b111001) && as;
    wire dvc_mpeg_cs = (addr_byte[23:18] == 6'b111000) && as && !config_disable_vmpeg;
    wire attex_cs_cdic = addr_byte[23:16] == 8'h30 && as;
    wire attex_cs_slave = addr_byte[23:16] == 8'h31 && as;
    wire attex_cs_mk48 = addr_byte[23:16] == 8'h32 && as;

    // Custom kernel module for OS9 to start a CD-i application after booting
    // Written by "CD-i Fan" for "CD-i Emulator"
    wire rom_playcdi_cs = ((addr_byte >= 24'hf00000) && (addr_byte <= 24'hf00068)) && as;
    bit [15:0] rom_playcdi[64];
    initial $readmemh("../mem/playcdi.mem", rom_playcdi);
    bit rom_playcdi_bus_ack;
    bit [15:0] rom_playcdi_dout;

    // Activate automatic playback of CD-i discs only when
    // an image is mounted, auto play is activated in OSD,
    // there is an actual CD-i disc in the tray (no audio cd) and
    // the last reset was not self imposed.
    // When software is quitting to system shell, this is done via reset using the SLAVE
    // In that case, we want to go back to the shell.
    // Also, when booting fails, we also want to go back to shell
    bit last_reset_by_slave = 0;
    wire playcdi_rom_activated = cd_img_mounted && config_auto_play && !audio_cd_in_tray && !last_reset_by_slave;

    always_ff @(posedge clk30) begin
        if (resetsys) last_reset_by_slave <= 1;
        if (external_reset) last_reset_by_slave <= 0;
    end

    bit attex_cs_slave_q = 0;

    wire bus_err_ram_area1 = (addr_byte >= 24'h080000 && addr_byte < 24'h200000);
    wire bus_err_ram_area2 = (addr_byte >= 24'h500000 && addr_byte < 24'hd00000);
    wire bus_err_ram_area3 = (addr_byte >= 24'hf10000);
    wire bus_err_ram_area4 = (addr_byte >= 24'hf00000) && !playcdi_rom_activated;
    wire bus_err_ram_area5 = (addr_byte[23:19] == 5'b11101) && !mpeg_ram_enabled; // MPEG RAM cannot be accessed at first
    wire bus_err = (bus_err_ram_area1 || bus_err_ram_area2 || bus_err_ram_area3 || bus_err_ram_area4 || bus_err_ram_area5) && as && (lds || uds);

    always_ff @(posedge clk30) begin

        if (reset) ce_pix <= 0;
        else ce_pix <= !ce_pix;

        if (bus_ack) begin
            if ((lds || uds) && attex_cs_cdic && write_strobe)
                $display(
                    "Write CDIC %x %x %d %d %d", addr_byte, cpu_data_out, lds, uds, write_strobe
                );

            if ((lds || uds) && attex_cs_cdic && !write_strobe)
                $display("Read CDIC %x %x %d %d %d", addr_byte, data_in, lds, uds, write_strobe);

            if ((lds || uds) && attex_cs_slave && write_strobe)
                $display(
                    "Write SLAVE %x %x %d %d %d", addr[7:1], cpu_data_out, lds, uds, write_strobe
                );

            if ((lds || uds) && attex_cs_slave && !write_strobe)
                $display("Read SLAVE %x %x %d %d %d", addr[7:1], data_in, lds, uds, write_strobe);


            if ((lds || uds) && attex_cs_mk48)

                if (write_strobe)
                    $display("Write NVRAM %x %x %d%d", addr[7:1], cpu_data_out, lds, uds);
                else $display("Read NVRAM %x %x %d%d", addr[7:1], data_in, lds, uds);

        end
    end


    /* verilator tracing_off */
    mk48t08b mk48t (
        .clk(clk30),
        .reset,
        .cpu_address(addr[13:1]),
        .cpu_din(cpu_data_out[15:8]),
        .cpu_dout(mk48_dout),
        .cs(attex_cs_mk48),
        .write_strobe(write_strobe && uds),
        .bus_ack(mk48_bus_ack),

        .nvram_backup_restore_adr(nvram_backup_restore_adr),
        .nvram_restore_data(nvram_restore_data),
        .nvram_backup_data(nvram_backup_data),
        .nvram_restore_write(nvram_restore_write),
        .nvram_cpu_changed(nvram_cpu_changed),
        .nvram_allow_cpu_access(nvram_allow_cpu_access),

        .hps_rtc(hps_rtc)
    );
    /* verilator tracing_on */

    wire vdsc_int  /*verilator public_flat_rd*/;

    // VSD is set if EV-bit is set and the backdrop is shown
    // A real CDI 210/05 uses VSA because of analog
    // video mixing. But we won't do that here and use the digital
    // one instead
    wire mcd212_vsd;
    /* verilator tracing_off */
    mcd212 mcd212_inst (
        .clk(clk30),
        .reset,
        .cpu_address(addr[23:1]),
        .cpu_din(cdic_dma_ack ? cdic_dout : cpu_data_out),
        .cpu_dout(mcd212_dout),
        .cpu_bus_ack(mcd212_bus_ack),
        .cpu_uds(uds),
        .cpu_lds(lds),
        .cpu_write_strobe(write_strobe),
        .cs(attex_cs_mcd212),
        .dvc_ram_cs(dvc_ram_cs),
        .dvc_rom_cs(dvc_rom_cs),
        .vidout(mcd212_video_out),
        .vsd(mcd212_vsd),
        .hsync(HSync),
        .vsync(VSync),
        .hblank(HBlank),
        .vblank(VBlank),
        .vga_f1(vga_f1),
        .sdram_addr(sdram_addr),
        .sdram_rd(sdram_rd),
        .sdram_wr(sdram_wr),
        .sdram_word(sdram_word),
        .sdram_din(sdram_din),
        .sdram_dout(sdram_dout),
        .sdram_busy(sdram_busy),
        .sdram_burst(sdram_burst),
        .sdram_refresh(sdram_refresh),
        .sdram_burstdata_valid,
        .irq(vdsc_int),
        .debug_force_video_plane,
        .debug_limited_to_full,
        // Don't starve the CPU during DMA transfers
        .disable_cpu_starve(config_disable_cpu_starve || cdic_dma_ack || cdic_dma_req)
    );
    /*verilator tracing_on*/

    // DMA signals from CPU
    wire vmpeg_dma_ack;
    wire cdic_dma_ack;
    wire dma_dtc;
    wire dma_done_out;

    // DMA signals to CPU
    wire cdic_dma_req;
    wire vmpeg_dma_req;
    wire vmpeg_dma_rdy;
    wire cdic_dma_rdy;

    wire in2in  /*verilator public_flat_rd*/;
    wire in4in;
    wire iack2;
    wire iack4;
    wire iack5;

    wire cdic_dma_done_in;

    wire signed [15:0] cdic_audio_left;
    wire signed [15:0] cdic_audio_right;

    wire signed [15:0] mpeg_audio_left;
    wire signed [15:0] mpeg_audio_right;

    wire sample_tick37;
    wire sample_tick44  /*verilator public_flat_rd*/;
    wire mpeg_45tick;

    cdic_clock_gen cdic_clk_gen (
        .clk(clk30),
        .clk_audio(clk_audio),
        .reset,
        .sector_tick(cd_sector_tick),
        .sample_tick37,
        .sample_tick44,
        .mpeg_45tick
    );

    wire cdic_intreq;
    wire cdic_intack;
    cdic cdic_inst (
        .clk(clk30),
        .reset,
        .address(addr),
        .din(cdic_dma_ack ? mcd212_dout : cpu_data_out),
        .dout(cdic_dout),
        .uds(uds),
        .lds(lds),
        .write_strobe(write_strobe),
        .cs(attex_cs_cdic),
        .bus_ack(cdic_bus_ack),
        .intreq(cdic_intreq),
        .intack(cdic_intack),
        .req(cdic_dma_req),
        .ack(cdic_dma_ack),
        .rdy(cdic_dma_rdy),
        .dtc(dma_dtc),
        .done_in(dma_done_out),
        .done_out(cdic_dma_done_in),
        .cd_seek_lba,
        .cd_seek_lba_valid,
        .cd_data_valid,
        .cd_data,
        .cd_sector_tick,
        .cd_sector_delivered,
        .cd_stop_sector_delivery,
        .audio_left(cdic_audio_left),
        .audio_right(cdic_audio_right),
        .sample_tick37,
        .sample_tick44,
        .fail_not_enough_words(fail_not_enough_words),
        .fail_too_much_data(fail_too_much_data)
    );
    /*verilator tracing_on*/

    // TODO might not be correct
    // CDIC seems to want manual vector
    // For the SLAVE we must use autovectoring
    wire av = iack2;

    wire mpeg_ram_enabled;

    wire vmpeg_intreq;
    wire vmpeg_intack;

    rgb888_s fmv_video_out;
    rgb888_s mcd212_video_out;
    linear_volume_s mpeg_dsp_volume;

    vmpeg vmpeg_inst (
        .clk(clk30),
        .clk_mpeg,
        .reset,
        .tvmode_pal,
        .address(addr),
        .din(vmpeg_dma_ack ? mcd212_dout : cpu_data_out),
        .dout(vmpeg_dout),
        .uds(uds),
        .lds(lds),
        .write_strobe(write_strobe),
        .cs(dvc_mpeg_cs),
        .bus_ack(vmpeg_bus_ack),
        .intreq(vmpeg_intreq),
        .intack(vmpeg_intack),
        .req(vmpeg_dma_req),
        .ack(vmpeg_dma_ack),
        .rdy(vmpeg_dma_rdy),
        .dtc(dma_dtc),
        .done_in(dma_done_out),
        .done_out(),
        .debug_disable_vcd_clock,
        .debug_activate_vcd_filter,
        .mpeg_ram_enabled(mpeg_ram_enabled),
        .hsync(HSync),
        .vsync(VSync),
        .hblank(HBlank),
        .vblank(VBlank),
        .vidout(fmv_video_out),
        .audio_left(mpeg_audio_left),
        .audio_right(mpeg_audio_right),
        .sample_tick44,
        .clk45tick(mpeg_45tick),
        .dsp_volume(mpeg_dsp_volume),
        .ddrif
    );

    wire force_dvc_video = debug_force_video_plane == 2'b11;
    assign vidout = (mcd212_vsd || force_dvc_video) ? fmv_video_out : mcd212_video_out;

`ifndef DISABLE_MAIN_CPU
    wire reset68k;

    // On a real 210/05, the main CPU polls 152 times
    // for the PAL/NTSC region. The timeout is 500.
    // With CPU Turbo this timeout is reached...
    // This reset delay of 8 frames ensures
    // that the slave has enough time to react
    // It will result into 160 polls until the answer is available

`ifdef VERILATOR
    // For simulation, we are fine because of a hack in uc_68hc05.sv
    assign reset68k = reset;
`else
    resetdelay cpuresetdelay (
        .clk(clk30),
        .reset,
        .vsync(VSync),
        .delayedreset(reset68k)
    );
`endif

    /* verilator tracing_off */
    scc68070 scc68070_0 (
        .clk(clk30),
        .reset(reset68k),  // External sync reset on emulated system
        .write_strobe(write_strobe),
        .as(as),
        .lds(lds),
        .uds(uds),
        .bus_ack(bus_ack),
        .bus_err,
        .int1(vdsc_int),  // Video IRQ
        .int2(1'b0),  // unconnected in CDi MONO1
        .in2(in2in),  // Slave IRQ
        .in4(in4in),  // CDIC IRQ
        .in5(1'b0),
        .iack2(iack2),
        .iack4(iack4),
        .iack5(iack5),
        .av(av),
        .data_in(data_in),
        .data_out(cpu_data_out),
        .addr(addr),
        .uart_tx(scc68_uart_tx),
        .uart_rx(scc68_uart_rx),
        .bypass_uart_rx(scc68070_bypass_serial_in),
        .bypass_uart_rts(scc68070_rts),
        .debug_uart_fake_space,
        .req1(cdic_dma_req),
        .req2(vmpeg_dma_req),
        .ack1(cdic_dma_ack),
        .ack2(vmpeg_dma_ack),
        .rdy(cdic_dma_rdy || vmpeg_dma_rdy),
        .dtc(dma_dtc),
        .done_in(cdic_dma_done_in),
        .done_out(dma_done_out)
    );
    /*verilator tracing_on */

`endif

    wire stand = !tvmode_pal;  // 1 NTSC, 0 PAL

    wire [7:0] ddra;
    wire [7:0] ddrb;
    wire [7:0] ddrc;

    wire quirk_force_mode_fault;
    wire [7:0] porta_in = cpu_data_out[7:0];
    wire [7:0] porta_out;
    wire [7:0] portb_in = 8'hff;
    wire [7:0] portb_out;
    wire [7:0] portc_in = {stand, 5'b11111, addr[2:1]};
    wire [7:0] portc_out;
    wire [7:0] portd_in = {!write_strobe, 7'b1111111};

    bit slave_bus_ack;

    always_comb begin
        bus_ack = 1;
        data_in = 0;

        if (attex_cs_slave) begin
            data_in = {porta_out, porta_out};
            bus_ack = slave_bus_ack;
        end else if (attex_cs_cdic) begin
            data_in = cdic_dout;
            bus_ack = cdic_bus_ack;
        end else if (dvc_mpeg_cs) begin
            data_in = vmpeg_dout;
            bus_ack = vmpeg_bus_ack;
        end else if (attex_cs_mk48) begin
            data_in = {mk48_dout, mk48_dout};
            bus_ack = mk48_bus_ack;
        end else if (attex_cs_mcd212 || dvc_ram_cs || dvc_rom_cs) begin
            data_in = mcd212_dout;
            bus_ack = mcd212_bus_ack;
        end else if (rom_playcdi_cs && playcdi_rom_activated) begin
            data_in = rom_playcdi_dout;
            bus_ack = rom_playcdi_bus_ack;
        end

        if (cdic_intack) begin
            data_in = cdic_dout;
            bus_ack = 1;
        end

        if (vmpeg_intack) begin
            data_in = vmpeg_dout;
            bus_ack = 1;
        end
    end

    always_ff @(posedge clk30) begin
        rom_playcdi_dout <= rom_playcdi[addr[6:1]];
        rom_playcdi_bus_ack <= !reset && rom_playcdi_cs && !rom_playcdi_bus_ack;
    end

    wire resetsys  /*verilator public_flat_rd*/ = ddrc[2] ? portc_out[2] : 1'b0;
    wire disdat_from_uc = ddrc[3] ? portc_out[3] : 1'b1;
    wire disdat_to_ic;

    wire disdat = disdat_from_uc && disdat_to_ic;
    wire disclk = ddrc[4] ? portc_out[4] : 1'b1;

    wire dtackslaven = ddrb[6] ? portb_out[6] : 1'b1;
    assign slave_rts = ddrb[4] ? portb_out[4] : 1'b1;

    // The polarity must be altered as a real SCC68070 is low active
    assign in2in = !(ddrb[5] ? portb_out[5] : 1'b1);

    wire datadac = ddrb[0] ? portb_out[0] : 1'b0;
    wire clkdac = ddrb[1] ? portb_out[1] : 1'b0;
    wire csdac1n = ddrb[2] ? portb_out[2] : 1'b1;
    wire csdac2n = ddrb[3] ? portb_out[3] : 1'b1;

    bit  dtackslaven_q = 0;
    bit  in2in_q = 0;

    bit  slave_irq;

    assign reset = external_reset || resetsys;

`ifndef DISABLE_SLAVE_UC
    /* verilator tracing_off */
    uc68hc05 uc68hc05_0 (
        .clk30,
        .reset(reset),
        .porta_in,
        .porta_out(porta_out),
        .portb_in,
        .portb_out(portb_out),
        .portc_in({portc_in[7:5], disclk, disdat_to_ic, portc_in[2:0]}),
        .portc_out(portc_out),
        .portd_in,
        .irq(!slave_irq),
        .ddra(ddra),
        .ddrb(ddrb),
        .ddrc(ddrc),

        .worm_adr (slave_worm_adr),
        .worm_data(slave_worm_data),
        .worm_wr  (slave_worm_wr),

        .tcap(rc_eye),
        .serial_in(slave_serial_in),
        .serial_out(slave_serial_out),
        .spi(slave_servo_spi),
        .quirk_force_mode_fault(quirk_force_mode_fault)
    );
    /*verilator tracing_on*/

`endif
    wire signed [15:0] att_audio_left;
    wire signed [15:0] att_audio_right;
    /* verilator tracing_off */
    dual_ad7528_attenuation att (
        .clk(clk30),
        .datadac(datadac),
        .csdac2n(csdac2n),
        .csdac1n(csdac1n),
        .clkdac(clkdac),
        .mpeg_volume(mpeg_dsp_volume),
        .audio_left_in(cdic_audio_left),
        .audio_right_in(cdic_audio_right),
        .mpeg_left_in(mpeg_audio_left),
        .mpeg_right_in(mpeg_audio_right),
        .audio_left_out(att_audio_left),
        .audio_right_out(att_audio_right)
    );

    always_ff @(posedge clk30) begin
        case (config_audio_mixing)
            0: begin  // Original
                audio_left  <= att_audio_left;
                audio_right <= att_audio_right;
            end
            1: begin  // CDIC unmixed
                audio_left  <= cdic_audio_left;
                audio_right <= cdic_audio_right;
            end
            2: begin  // VMPEG unmixed
                audio_left  <= mpeg_audio_left;
                audio_right <= mpeg_audio_right;
            end
            3: begin  // VMPEG only left
                audio_left  <= mpeg_audio_left;
                audio_right <= mpeg_audio_left;
            end
            4: begin  // VMPEG only right
                audio_left  <= mpeg_audio_right;
                audio_right <= mpeg_audio_right;
            end
            default: begin  // Just to be sure
                audio_left  <= att_audio_left;
                audio_right <= att_audio_right;
            end
        endcase

    end

    u3090mg u3090mg (
        .clk(clk30),
        .sda_in(disdat_from_uc),
        .sda_out(disdat_to_ic),
        .scl(disclk)
    );

    servo_hle servo (
        .clk(clk30),
        .reset(reset),
        .spi(slave_servo_spi),
        .quirk_force_mode_fault(quirk_force_mode_fault),
        .audio_cd_in_tray,
        .cd_img_mount(cd_img_mount),
        .cd_img_mounted(cd_img_mounted),
        .tray_is_closed
    );
    /*verilator tracing_on*/

    always_comb begin
        slave_bus_ack = dtackslaven && !dtackslaven_q;
        slave_irq = (attex_cs_slave && !attex_cs_slave_q);
    end

    always_ff @(posedge clk30) begin
        if (reset) begin
            attex_cs_slave_q <= 0;
            dtackslaven_q <= 0;
            in2in_q <= 0;
        end else begin
            attex_cs_slave_q <= attex_cs_slave;
            dtackslaven_q <= dtackslaven;
            in2in_q <= in2in;

            if (!in2in && in2in_q) $display("SLAVE IRQ2 0");
            if (in2in && !in2in_q) $display("SLAVE IRQ2 1");
        end

    end

    // Inspired by a small 74ACT74 SR flip flop which does this in the real machine
    enum bit [1:0] {
        IDLE,
        CDIC,
        VMPEG
    } irq_in4owner;

    assign cdic_intack = iack4 && irq_in4owner == CDIC;
    assign vmpeg_intack = iack4 && irq_in4owner == VMPEG;
    assign in4in = ((irq_in4owner == CDIC) && cdic_intreq) ||  ((irq_in4owner == VMPEG) && vmpeg_intreq);

    always_ff @(posedge clk30) begin
        case (irq_in4owner)
            CDIC: begin
                if (!cdic_intreq) irq_in4owner <= IDLE;
            end
            VMPEG: begin
                if (!vmpeg_intreq) irq_in4owner <= IDLE;
            end
            default: begin
                if (cdic_intreq) irq_in4owner <= CDIC;
                if (vmpeg_intreq) irq_in4owner <= VMPEG;
            end
        endcase
    end


`ifdef VERILATOR
    // Only for gtkwave to align video images with the signals in the waveform
    int frame_index  /*verilator public_flat_rw*/;

    // Tool to observe variables in madriv module
    struct {
        bit [31:0] dma_addr;    // 0x122
        bit [15:0] irq_stat;    // 0x120
        bit [15:0] irq_enable;  // 0x150
    } madriv = '{default: 0};
    bit [23:0] madriv_static  /*verilator public_flat_rw*/ = 24'hdfb770;

    always @(posedge clk30) begin
        if (madriv_static != 0 && bus_ack && write_strobe) begin
            if (addr_byte == madriv_static + 24'h122) begin
                madriv.dma_addr[31:16] = cpu_data;
                $display("FMA dma_addr = %x", {cpu_data, madriv.dma_addr[15:0]});
            end

            if (addr_byte == madriv_static + 24'h124) begin
                madriv.dma_addr[15:0] = cpu_data;
                $display("FMA dma_addr = %x", {madriv.dma_addr[31:16], cpu_data});
            end

            if (addr_byte == madriv_static + 24'h0150) begin
                madriv.irq_stat = cpu_data;
                $display("FMA irq_stat = %x", cpu_data);
            end

            if (addr_byte == madriv_static + 24'h0120) begin
                madriv.irq_enable = cpu_data;
                $display("FMA irq_enable = %x", cpu_data);
            end
        end
    end

    // Tool to observe variables in fdrvs1 module
    struct {
        bit [7:0] V_StepDone; // 0x17a char*
        bit [7:0] V_BufStat;  // 0x17b char*
        bit [7:0] V_UpdFlag;  // 0x12e char*
        bit [15:0] V_Stat;    // 0x134
        bit [15:0] V_VCMD;    // 0x16c
        bit [15:0] V_Scroll;  // 0x16a
        bit [15:0] V_DTSVal;  // 0x1c0
        bit [31:0] V_SCR;     // 0xca
        bit [15:0] V_Status;  // 0x136
        bit [15:0] V_SigStat; // 0x13c
        bit [15:0] V_AsyStat; // 0x16e
        bit [31:0] V_Window;  // 0xe6
        bit [31:0] V_DecOff;  // 0xea
        bit [31:0] V_ScrOrg;  // 0xee
        bit [31:0] V_ScrOff;  // 0xf2
        bit [31:0] V_NISFnd;  // 0x170
        bit [7:0]  V_PicRt; // 0x0x17f char*
        bit [31:0] V_PWI; // 0x180
        bit [15:0] V_PRPA; //0x194
        bit [31:0] V_Speed; // 0x100
        bit [15:0] V_PlayType; // 0x9a
        bit [7:0] V_Sync;  // 0xc9 char*
        bit [7:0] V_SyncDone;  // 0x12c char*
        bit [15:0] V_LCntr;  // 0xac
        bit [7:0] V_Frozen;  // 0xde char*
        bit [31:0] V_PausedSCR; // 0x144
        bit [31:0] V_ChipSpd; // 0x196 long*
    } fdrvs1 = '{default: 0};
    bit [23:0] fdrvs1_static  /*verilator public_flat_rw*/ = 24'hdfb180;
    always @(posedge clk30) begin

        if (fdrvs1_static != 0 && bus_ack && write_strobe) begin

            if (addr_byte == fdrvs1_static + 24'h0136) begin
                fdrvs1.V_Status = cpu_data;
                $display("FMV V_Status = %d dez", cpu_data);
            end
            if (addr_byte == fdrvs1_static + 24'h013c) begin
                fdrvs1.V_SigStat = cpu_data;
                $display("FMV V_SigStat = %d dez", cpu_data);
            end
            if (addr_byte == fdrvs1_static + 24'h016e) begin
                fdrvs1.V_AsyStat = cpu_data;
                $display("FMV V_AsyStat = %x hex %d dez", cpu_data, cpu_data);
            end
            if (addr_byte == fdrvs1_static + 24'h0134) begin
                fdrvs1.V_Stat = cpu_data;
                $display("FMV V_Stat = %d dez", cpu_data);
            end
            if (addr_byte == fdrvs1_static + 24'h0194) begin
                fdrvs1.V_PRPA = cpu_data;
                $display("FMV V_PRPA = %d dez", cpu_data);
            end
            if (addr_byte == fdrvs1_static + 24'h009a) begin
                fdrvs1.V_PlayType = cpu_data;
                $display("FMV V_PlayType = %d dez", cpu_data);
            end

            // I assume that fdrvs1_static is always aligned to words
            if (addr_byte == fdrvs1_static + 24'h017a && uds) begin  // Location is 0x17a -> high byte
                fdrvs1.V_StepDone = cpu_data[15:8];
                $display("FMV V_StepDone = %d dez", cpu_data[15:8]);
            end

            if (addr_byte == fdrvs1_static + 24'h017a && lds) begin  // Location is 0x17b -> low byte
                fdrvs1.V_BufStat = cpu_data[7:0];
                $display("FMV V_BufStat = %d dez", cpu_data[7:0]);
            end

            if (addr_byte == fdrvs1_static + 24'h012e && uds) begin  // Location is 0x12e -> high byte
                fdrvs1.V_UpdFlag = cpu_data[15:8];
                $display("FMV V_UpdFlag = %d dez", cpu_data[15:8]);
            end

            if (addr_byte == fdrvs1_static + 24'h017e && lds) begin  // Location is 0x17f -> low byte
                fdrvs1.V_PicRt = cpu_data[7:0];
                $display("FMV V_PicRt = %d dez", cpu_data[7:0]);
            end

            if (addr_byte == fdrvs1_static + 24'h00c8 && lds) begin  // Location is 0xc9 -> low byte
                fdrvs1.V_Sync = cpu_data[7:0];
                $display("FMV V_Sync = %d dez", cpu_data[7:0]);
            end

            if (addr_byte == fdrvs1_static + 24'h012c && uds) begin  // Location is 0x12c -> high byte
                fdrvs1.V_SyncDone = cpu_data[7:0];
                $display("FMV V_SyncDone = %d dez", cpu_data[7:0]);
            end

            if (addr_byte == fdrvs1_static + 24'h0de && uds) begin  // Location is 0xde -> high byte
                fdrvs1.V_Frozen = cpu_data[7:0];
                $display("FMV V_Frozen = %d dez", cpu_data[7:0]);
            end

            if (addr_byte == fdrvs1_static + 24'h00ac) begin
                fdrvs1.V_LCntr = cpu_data;
                $display("FMV V_LCntr = %x", cpu_data);
            end

            if (addr_byte == fdrvs1_static + 24'h016a) begin
                fdrvs1.V_Scroll = cpu_data;
                $display("FMV V_Scroll = %x", cpu_data);
            end

            if (addr_byte == fdrvs1_static + 24'h016c) begin
                fdrvs1.V_VCMD = cpu_data;
                $display("FMV V_VCMD = %x", cpu_data);
            end

            if (addr_byte == fdrvs1_static + 24'h01c0) begin
                fdrvs1.V_DTSVal = cpu_data;
                $display("FMV V_DTSVal = %x", cpu_data);
            end

            if (addr_byte == fdrvs1_static + 24'h0ca) begin
                fdrvs1.V_SCR[31:16] = cpu_data;
                $display("FMV V_SCR = %x", {cpu_data, fdrvs1.V_SCR[15:0]});
            end

            if (addr_byte == fdrvs1_static + 24'h0cc) begin
                fdrvs1.V_SCR[15:0] = cpu_data;
                $display("FMV V_SCR = %x", {fdrvs1.V_SCR[31:16], cpu_data});
            end

            if (addr_byte == fdrvs1_static + 24'h0e6) begin
                fdrvs1.V_Window[31:16] = cpu_data;
                $display("FMV V_Window = %x", {cpu_data, fdrvs1.V_Window[15:0]});
            end

            if (addr_byte == fdrvs1_static + 24'h0e8) begin
                fdrvs1.V_Window[15:0] = cpu_data;
                $display("FMV V_Window = %x", {fdrvs1.V_Window[31:16], cpu_data});
            end

            if (addr_byte == fdrvs1_static + 24'h0ea) begin
                fdrvs1.V_DecOff[31:16] = cpu_data;
                $display("FMV V_DecOff = %x", {cpu_data, fdrvs1.V_DecOff[15:0]});
            end

            if (addr_byte == fdrvs1_static + 24'h0ec) begin
                fdrvs1.V_DecOff[15:0] = cpu_data;
                $display("FMV V_DecOff = %x", {fdrvs1.V_DecOff[31:16], cpu_data});
            end

            if (addr_byte == fdrvs1_static + 24'h0ee) begin
                fdrvs1.V_ScrOrg[31:16] = cpu_data;
                $display("FMV V_ScrOrg = %x", {cpu_data, fdrvs1.V_ScrOrg[15:0]});
            end

            if (addr_byte == fdrvs1_static + 24'h0f0) begin
                fdrvs1.V_ScrOrg[15:0] = cpu_data;
                $display("FMV V_ScrOrg = %x", {fdrvs1.V_ScrOrg[31:16], cpu_data});
            end

            if (addr_byte == fdrvs1_static + 24'h0f2) begin
                fdrvs1.V_ScrOff[31:16] = cpu_data;
                $display("FMV V_ScrOff = %x", {cpu_data, fdrvs1.V_ScrOff[15:0]});
            end

            if (addr_byte == fdrvs1_static + 24'h0f4) begin
                fdrvs1.V_ScrOff[15:0] = cpu_data;
                $display("FMV V_ScrOff = %x", {fdrvs1.V_ScrOff[31:16], cpu_data});
            end

            if (addr_byte == fdrvs1_static + 24'h170) begin
                fdrvs1.V_NISFnd[31:16] = cpu_data;
                $display("FMV V_NISFnd = %x", {cpu_data, fdrvs1.V_NISFnd[15:0]});
            end

            if (addr_byte == fdrvs1_static + 24'h172) begin
                fdrvs1.V_NISFnd[15:0] = cpu_data;
                $display("FMV V_NISFnd = %x", {fdrvs1.V_NISFnd[31:16], cpu_data});
            end

            if (addr_byte == fdrvs1_static + 24'h180) begin
                fdrvs1.V_PWI[31:16] = cpu_data;
                $display("FMV V_PWI = %x", {cpu_data, fdrvs1.V_PWI[15:0]});
            end

            if (addr_byte == fdrvs1_static + 24'h182) begin
                fdrvs1.V_PWI[15:0] = cpu_data;
                $display("FMV V_PWI = %x", {fdrvs1.V_PWI[31:16], cpu_data});
            end

            if (addr_byte == fdrvs1_static + 24'h100) begin
                fdrvs1.V_Speed[31:16] = cpu_data;
                $display("FMV V_Speed = %x", {cpu_data, fdrvs1.V_Speed[15:0]});
            end

            if (addr_byte == fdrvs1_static + 24'h102) begin
                fdrvs1.V_Speed[15:0] = cpu_data;
                $display("FMV V_Speed = %x", {fdrvs1.V_Speed[31:16], cpu_data});
            end

            if (addr_byte == fdrvs1_static + 24'h144) begin
                fdrvs1.V_PausedSCR[31:16] = cpu_data;
                $display("FMV V_PausedSCR = %x", {cpu_data, fdrvs1.V_PausedSCR[15:0]});
            end

            if (addr_byte == fdrvs1_static + 24'h146) begin
                fdrvs1.V_PausedSCR[15:0] = cpu_data;
                $display("FMV V_PausedSCR = %x", {fdrvs1.V_PausedSCR[31:16], cpu_data});
            end

            if (addr_byte == fdrvs1_static + 24'h196) begin
                fdrvs1.V_ChipSpd[31:16] = cpu_data;
                $display("FMV V_ChipSpd = %x", {cpu_data, fdrvs1.V_ChipSpd[15:0]});
            end

            if (addr_byte == fdrvs1_static + 24'h198) begin
                fdrvs1.V_ChipSpd[15:0] = cpu_data;
                $display("FMV V_ChipSpd = %x", {fdrvs1.V_ChipSpd[31:16], cpu_data});
            end
        end
    end
`endif

endmodule

