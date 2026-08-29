`include "mpeg/util.svh"

module vmpeg (
    input clk,
    input clk_mpeg,
    input reset,
    input tvmode_pal,
    // CPU interface
    input [23:1] address,
    input [15:0] din,
    output bit [15:0] dout,
    input uds,
    input lds,
    input write_strobe,
    input cs,
    output bit bus_ack,
    output intreq,
    input intack,
    output req,
    input ack,
    output rdy,
    input dtc,
    input done_in,
    output done_out,

    ddr_if.to_host ddrif,

    // Video synchronization and output
    input hsync,
    input vsync,
    input hblank,
    input vblank,
    output rgb888_s vidout,

    // Audio Out
    output signed [15:0] audio_left,
    output signed [15:0] audio_right,
    input sample_tick44,
    input clk45tick,
    output linear_volume_s dsp_volume,

    input debug_disable_vcd_clock,
    input debug_activate_vcd_filter,
    output bit mpeg_ram_enabled  // Prohibits detection of MPEG RAM by the OS RAM crawler
);
    wire access = cs && (uds || lds);

    wire dma_data_valid = ack && dtc;
    bit mpeg_word_valid_q;

    // Get bytes from words for better analysis for state machines
    bit [7:0] mpeg_temp;
    wire [7:0] mpeg_data  /*verilator public_flat_rd*/ = mpeg_word_valid_q ? mpeg_temp : din[15:8];
    wire mpeg_data_valid  /*verilator public_flat_rd*/ = mpeg_word_valid_q || mpeg_word_valid;

    wire fma_packet_body  /*verilator public_flat_rd*/;
    wire fmv_packet_body  /*verilator public_flat_rd*/;

    always_ff @(posedge clk) begin
        mpeg_word_valid_q <= mpeg_word_valid;
        if (mpeg_word_valid) mpeg_temp <= din[7:0];
    end

    wire mpeg_xferwrite = (address[15:1] == 15'h206F) && bus_ack && write_strobe && access;
    wire mpeg_word_valid = dma_data_valid || mpeg_xferwrite;
    bit dma_for_fma;
    wire fmv_data_valid  /*verilator public_flat_rd*/ = mpeg_data_valid && !dma_for_fma;
    wire fma_data_valid  /*verilator public_flat_rd*/ = mpeg_data_valid && dma_for_fma;

    wire fma_event_decoding_started;
    wire fma_event_frame_decoded;
    wire fma_event_underflow;
    bit dsp_reset_input_fifo;
    bit fma_dsp_enable = 0;
    bit fmv_dsp_enable = 0;
    bit fmv_reset_persistent_storage = 0;

    wire fma_fifo_full;
    wire fmv_fifo_full;

    wire [31:0] fma_mpeg_audio_header;

    mpeg_audio audio (
        .clk(clk),
        .reset,
        .dsp_enable(fma_dsp_enable),
        .reset_input_fifo(dsp_reset_input_fifo),
        .data_byte(mpeg_data),
        .data_strobe(fma_data_valid && fma_packet_body),
        .fifo_full(fma_fifo_full),
        .audio_left(audio_left),
        .audio_right(audio_right),
        .sample_tick44(sample_tick44),
        .playback_active(),
        .event_decoding_started(fma_event_decoding_started),
        .event_frame_decoded(fma_event_frame_decoded),
        .event_underflow(fma_event_underflow),
        .dspa(fma_dspa),
        .dspd(din[7:0]),
        .dspd_strobe(write_strobe && bus_ack && access && address[15:1] == 15'h1812),
        .dsp_volume,
        .mpeg_audio_header(fma_mpeg_audio_header)
    );

    wire fmv_event_picture_starts_display;
    wire fmv_event_potential_picture_starts_display;
    wire fmv_event_last_picture_starts_display;
    wire fmv_event_first_intra_frame_seq_starts_display;
    wire fmv_event_first_intra_frame_gop_starts_display;
    // TIMECD @ 00E04058
    // example 0x07800280 -> 10:00:30.0
    // mv_info() would have MD_TimeCd=0x0a001e00
    // [21:16] 6 Bit Frames. Not BCD
    // [27:22] 6 Bit Seconds. Not BCD
    // [5:0] 6 Bit Minutes. Not BCD
    // [10:6] 5 Bits Hours. Not BCD
    wire [31:0] fmv_display_timecode;
    wire [31:0] fmv_decoder_timecode;
    bit fmv_playback_active;
    bit fmv_decoder_active;
    bit fmv_single_step;
    wire fmv_event_sequence_end;
    wire fmv_event_frame_decoded;
    wire fmv_event_buffer_underflow;
    wire [6:0] fmv_pictures_in_fifo;
    bit [2:0] fmv_slow_motion;

    bit [8:0] latched_display_offset_y;
    bit [8:0] latched_display_offset_x;
    bit [8:0] latched_window_offset_y;
    bit [8:0] latched_window_offset_x;
    bit [8:0] latched_window_width;
    bit [8:0] latched_window_height;

    bit fmv_clear_fifo;

    mpeg_video video (
        .clk30(clk),
        .clk_mpeg(clk_mpeg),
        .reset,
        .dsp_enable(fmv_dsp_enable),
        .clear_fifo(fmv_clear_fifo),
        .reset_persistent_storage(fmv_reset_persistent_storage),
        .playback_active(fmv_playback_active),
        .synchronous_playback(fmv_system_control_register[2]),
        .decoder_active(fmv_decoder_active),
        .single_step(fmv_single_step),
        .slow_motion(fmv_slow_motion),
        .data_byte(mpeg_data),
        .data_strobe(fmv_data_valid && fmv_packet_body),
        .fifo_full(fmv_fifo_full),
        .ddrif,
        .vcd_pixel_clock(vcd_pixel_clock && !debug_disable_vcd_clock),
        .debug_activate_vcd_filter,
        .hsync,
        .vsync,
        .hblank,
        .vblank,
        .vidout,
        .display_offset_x(latched_display_offset_y),
        .display_offset_y(latched_display_offset_x),
        .window_offset_y(latched_window_offset_y),
        .window_offset_x(latched_window_offset_x),
        .window_width(latched_window_width),
        .window_height(latched_window_height),
        .show_on_next_video_frame(fmv_show_on_next_video_frame),
        .event_sequence_end(fmv_event_sequence_end),
        .event_frame_decoded(fmv_event_frame_decoded),
        .event_buffer_underflow(fmv_event_buffer_underflow),
        .event_picture_starts_display(fmv_event_picture_starts_display),
        .event_potential_picture_starts_display(fmv_event_potential_picture_starts_display),
        .event_last_picture_starts_display(fmv_event_last_picture_starts_display),
        .event_first_intra_frame_gop_starts_display(fmv_event_first_intra_frame_gop_starts_display),
        .event_first_intra_frame_seq_starts_display(fmv_event_first_intra_frame_seq_starts_display),
        .pictures_in_fifo(fmv_pictures_in_fifo),
        .demuxer_decoding_timestamp(fmv_demuxer_decoding_timestamp),
        .demuxer_decoding_timestamp_updated(fmv_demuxer_decoding_timestamp_updated),
        .demuxer_system_clock_reference(fmv_demuxer_system_clock_reference),
        .dclk(fmv_dclk),
        .decoder_width(fmv_decoder_width),
        .decoder_height(fmv_decoder_height),
        .display_width(fmv_display_width),
        .display_height(fmv_display_height),
        .display_video_status(fmv_display_video_status),
        .display_frameperiod_rawhdr(fmv_display_frameperiod_rawhdr),
        .display_timecode(fmv_display_timecode),
        .decoder_timecode(fmv_decoder_timecode),
        .decoder_frameperiod_90khz(fmv_decoder_frameperiod_90khz),
        .decoder_frameperiod_rawhdr(fmv_decoder_frameperiod_rawhdr)
    );

    wire fmv_event_program_end;
    wire fma_event_program_end;

    bit [3:0] fmv_stream_number;
    bit [3:0] fma_stream_number;

    wire signed [32:0] fma_demuxer_system_clock_reference;
    wire signed [32:0] fma_demuxer_decoding_timestamp;
    wire signed [32:0] fma_demuxer_presentation_timestamp;
    wire fma_demuxer_presentation_timestamp_updated;
    wire fma_start_playback;

    wire signed [32:0] fmv_demuxer_system_clock_reference;
    wire signed [32:0] fmv_demuxer_decoding_timestamp;
    wire signed [32:0] fmv_demuxer_presentation_timestamp;
    wire fmv_demuxer_decoding_timestamp_updated;

    // How the CPU reads it from GEN_DEC_TIM1 @ 00E040A0
    // The CPU handles this at 703.125 Hz resolution
    wire signed [14:0] fmv_demuxer_decoding_timestamp_reduced_view = fmv_demuxer_decoding_timestamp[21:7];

    mpeg_demuxer #(
        .unit("FMA")
    ) audio_demuxer (
        .clk,
        .reset(reset || (fma_command_register == 1)),
        .mpeg_data(mpeg_data),
        .data_valid(fma_data_valid),
        .mpeg_packet_body(fma_packet_body),
        .stream_filter(fma_stream_number),
        .system_clock_reference(fma_demuxer_system_clock_reference),
        .system_clock_reference_updated(),
        .decoding_timestamp(),
        .decoding_timestamp_updated(),
        .presentation_timestamp(fma_demuxer_presentation_timestamp),
        .presentation_timestamp_updated(fma_demuxer_presentation_timestamp_updated),
        .event_program_end(fma_event_program_end)
    );

    mpeg_playback_timer fma_play_start (
        .clk,
        .reset(reset || (fma_command_register == 1) || fma_event_underflow),
        .dclk(fma_dclk),
        .system_clock_reference(fma_demuxer_system_clock_reference),
        .presentation_timestamp(fma_demuxer_presentation_timestamp),
        .presentation_timestamp_strobe(fma_demuxer_presentation_timestamp_updated),
        .start_playback(fma_start_playback)
    );

    mpeg_demuxer #(
        .unit("FMV")
    ) video_demuxer (
        .clk,
        .reset(reset || fmv_dsp_enable == 0),
        .mpeg_data(mpeg_data),
        .data_valid(fmv_data_valid),
        .mpeg_packet_body(fmv_packet_body),
        .stream_filter(fmv_stream_number),
        .system_clock_reference(fmv_demuxer_system_clock_reference),
        .system_clock_reference_updated(),
        .decoding_timestamp(fmv_demuxer_decoding_timestamp),
        .decoding_timestamp_updated(fmv_demuxer_decoding_timestamp_updated),
        .presentation_timestamp(fmv_demuxer_presentation_timestamp),
        .presentation_timestamp_updated(),
        .event_program_end(fmv_event_program_end)
    );

    typedef struct packed {
        bit erdv;  // ?
        bit erdd;  // ?
        bit vcup;  // Video Clip Update ?
        bit pai;   // Pause Interrupt ?

        bit vsync;  // Vertical Synchronization ?
        bit eii;    // End ISO Indicator ?
        bit esi;    // End Sequence Indicator ?
        bit tim;    // Timer

        bit dcl;   // ?
        bit ovf;   // Overflow ?
        bit ndat;  // No data ? Underflow ?
        bit rfb;   // Request for bits ?

        bit eod;  // End Of Data
        bit pic;  // Picture Decoded
        bit gop;  // GOP Decoded
        bit seq;  // SEQ Decoded
    } interrupt_flags_s;

    // VMPEG VCD @ 00E01xxx
    // The lower 12 bits are don't care bits on real hardware
    // Write only register. Reading is impossible!
    // 0 for base case pixel clock of 15 MHz
    // 1 for VCD pixel clock of 13.5 MHz
    bit vcd_pixel_clock;

    // FMA CMD @ 00E03000
    // 0001 Stop?
    // 8002 DMA Start
    bit [15:0] fma_command_register;
    // FMA STAT @ 00E03002
    // 0200 before starting playback
    // 0210 during Lost Eden music
    // according to reverse engineering efforts of CD-i Fan
    // FMA ISO End Detected Status      STAT_EOI            BIT_MASK(0)
    // FMA Audio Stream Changed Status  STAT_CSU            BIT_MASK(1)
    // FMA Frame Header Updated Status  STAT_UPD            BIT_MASK(2)
    // FMA Underflow Status             STAT_UNF            BIT_MASK(3)
    // FMA Decoding Started Status      STAT_DEC            BIT_MASK(4)
    // The layout looks similar to the interrupt status register
    // and also similar to the ASY-block according to chapter 8.2.4.3.3
    // of the green book. There, the bits 1 and 2 are reserved
    // since the highest byte is always 0x02, we just use 8 bits here
    bit [7:0] fma_status_register;
    // FMA ISR @ 00E0301A
    // 0100 Timer?
    // 0104 Updated Header and Timer?
    // 0114 Decoding Started
    // according to reverse engineering efforts of CD-i Fan
    // FMA ISO End Detected Interrupt   ISR_EOI            BIT_MASK(0)
    // FMA Changed Stream Interrupt     ISR_CSU            BIT_MASK(1)
    // FMA Updated Header Interrupt     ISR_UPD            BIT_MASK(2)
    // FMA Underflow Interrupt          ISR_UNF            BIT_MASK(3)
    // FMA Decoding Started Interrupt   ISR_DEC            BIT_MASK(4)
    // FMA Error Interrupt              ISR_ERR            BIT_MASK(5)
    // FMA Poll Interrupt               ISR_POLL           BIT_MASK(8)
    // A value of 0x182 is possible, indicating a bit 7
    // A value of 0x44 is also possible, indicating a bit 6
    // Bit 7 is occurring together with CSU when decoding has started
    // but playback not yet.
    // Bit 6 is occurring together with POLL (is it?) when
    // playback is performed too.
    // Both bits 6 and 7 seem to be ignored by madriv and are
    // never enabled in FMA_IER
    bit [15:0] fma_interrupt_status_register;
    // FMA IER @ 00E0301C
    // typical value is 0x013d?
    // This would exclude ISR_CSU
    // After calls to ma_cntrl() to change the stream, it becomes 13f
    // until the stream was confirmed
    bit [15:0] fma_interrupt_enable_register;
    // FMA IVEC @ 00E0300C
    bit [15:0] fma_interrupt_vector_register = 0;
    // FMA DCLKH @ 00E03010, DCLKL @ 00E03012
    // Increments with 45 kHz
    // Must never be written to by CPU. Causes system reset on real 210/05
    bit [31:0] fma_dclk;

    // GEN_SYSCR @ 0E04098
    // only bits 21:6 can be changed by the CPU
    // The CPU handles this at 703.125 Hz resolution
    // Increments with 45 kHz
    bit [31:0] fmv_dclk;
    bit [15:0] fma_dclkl_latch;

    wire [31:0] dclk_diff = fma_dclk - fmv_dclk;

    bit [31:0] fmv_dclk_start_video;
    bit fmv_dclk_start_video_latched;

    bit [31:0] fmv_dclk_pause_video;
    bit fmv_dclk_pause_video_latched;

    // FMA DSPA @ 00E03022
    // Address for indirect access into DSP memory?
    bit [7:0] fma_dspa;

    // FMV SYSCMD @ 00E040C0
    // [2:0] Slow Motion (only valid when Play | Continue ?)
    // [3] Play
    // [4] Pause
    // [5] Continue
    // [6] Step
    // [7] Stop
    // [15] Start DMA
    (* keep *) (* noprune *) bit [15:0] fmv_system_command_register = 0;
    // FMV VIDCMD @ 00E040C2
    (* keep *) (* noprune *) bit [15:0] fmv_video_command_register = 0;
    // FMV SYS_SCR @ 00E040C6
    // [1:0] BSIZ ?
    // [2] 1=Synchronous 0=Asynchronous
    // [3] CDI mode?
    // [5:4] Decoder Mode
    // 882D 1000 1000 0010 1101 During Addams Family playback, Sync, CD-i Mode, Fullmotion No Interlace
    // 8829 1000 1000 0010 1001 During Addams Family Fast Forward, Async, CD-i Mode, Fullmotion No Interlace
    // 8829 1000 1000 0010 1001 During self build stepping, Async, CD-i Mode, Fullmotion No Interlace
    // So this would indicate that Sync should Synchronize to the DTS?
    // And Async shall decode and display as fast as possible?
    (* keep *) (* noprune *) bit [15:0] fmv_system_control_register = 0;

    bit fmv_show_on_next_video_frame;

    // FMV ISR @ 00E04062
    // I once thought that bits inside this register are only set
    // if the matching enable bit in IER is set too.
    // But that is wrong since MV_Abort sets IER=0x2000, keeping only VCUP activated.
    // Within the call to MV_Release, there is a sudden expectation to poll for VSync in ISR
    // at ROM address 0xe529f8. So, this theory was proven wrong
    interrupt_flags_s fmv_interrupt_status_register;
    // FMV IER @ 00E04060
    // TODO typically 0xf7cf? Masking out NDAT, RFB and VSYNC?
    // on real hardware it is 0xf7ef which enables NDAT
    interrupt_flags_s fmv_interrupt_enable_register;
    // FMV IVEC @ 00E040DC
    bit [15:0] fmv_interrupt_vector_register = 0;
    // GEN_FRAME_RATE @ 00E040AC
    bit [15:0] fmv_frame_rate = 0;
    // FMV TCNT @ 00E04064 (also named SYS_TIM)
    // according to fmvdrv sources:
    // 29700 -1 for 5.28 seconds
    // 56 -1 for 10ms interrupt
    // 75 -1 for 12.333ms interrupt
    // 225 - 1 for 40 ms interrupt
    // so we have about 5,625 ticks per ms
    // this means 5625 tick per second
    // this means 90 kHz / 5625 Hz = 16 Perfect to the power of 2
    bit [15:0] fmv_timer_compare_register = 56 - 1;

    wire fmv_intreq = (fmv_interrupt_status_register & fmv_interrupt_enable_register) != 0;
    wire fma_intreq = (fma_interrupt_status_register & fma_interrupt_enable_register) != 0;
    assign intreq = fma_intreq || fmv_intreq;

    // Where does this come from? Where is it used?
    bit  [15:0] video_ctrl_y_active = 0;
    bit  [15:0] video_ctrl_x_active = 0;

    // Where does this come from? Where is it used?
    bit  [15:0] video_ctrl_y_offset = 0;
    bit  [15:0] video_ctrl_x_offset = 0;

    // Sum of mv_org() + mv_pos()
    bit  [15:0] video_ctrl_y_display = 0;
    bit  [15:0] video_ctrl_x_display = 0;

    // set by mv_window(_,_,x,y,W,H_);
    bit  [15:0] video_ctrl_window_width = 0;
    bit  [15:0] video_ctrl_window_height = 0;

    // set by mv_window(_,_,X,Y,w,h_);
    bit  [15:0] video_ctrl_decoder_offset_y = 0;
    bit  [15:0] video_ctrl_decoder_offset_x = 0;

    wire [10:0] fmv_decoder_width;
    wire [ 8:0] fmv_decoder_height;
    wire [10:0] fmv_display_width;
    wire [ 8:0] fmv_display_height;

    wire [ 7:0] fmv_display_video_status;
    wire [15:0] fmv_decoder_frameperiod_90khz;
    wire [ 7:0] fmv_decoder_frameperiod_rawhdr;
    wire [ 7:0] fmv_display_frameperiod_rawhdr;

    localparam kDisplayRate_PAL = 16'h0708;
    localparam kDisplayRate_NTSC = 16'h05DC;  // TODO confirmation required

    wire [15:0] fmv_display_rate = tvmode_pal ? kDisplayRate_PAL : kDisplayRate_NTSC;
    bit  [15:0] fmv_video_data_input_command_register = 0;

    // GEN_DEC_CMD @ 00E04088
    // 0x2202 for stills?
    // [15:14] Redecode count?
    // [11] Display new?
    // [10] Step is accepted?
    // [5] RUN_RYTHM? in previous release of fmv driver?
    // [1:0] MODE?
    // Typical values?
    // 0x0002  first run?
    // 0x7952  0111 1001 0101 0010  when playing
    // 0x1942  0001 1001 0100 0010  when playing
    // 0x2242  0010 0010 0100 0010  Imagination in Motion - Step Reverse during Pause
    // 0x2202  0010 0010 0000 0010  Self build, directly into step
    // 0x5061  0101 0000 0110 0001  after mv_cdnext() and a lot of time in single step mode
    // 0x2202 is essential for single step?
    // 0x0042  0000 0000 0100 0010 decoding status?
    // Disco bird test with moving window in this order, without the non working loop:
    // 0x1001  0001 0000 0000 0001
    // 0x1972  0001 1001 0111 0010 RUN_RYTHM?
    // 0x5962  0101 1001 0110 0010 RUN_RYTHM?
    // 0x7952  0111 1001 0101 0010
    // 0x002c  0000 0000 0010 1100 after a long while of continues updates without new picture
    bit  [15:0] fmv_decoder_command;

    bit  [15:0] image_height = 0;
    bit  [15:0] image_width = 0;
    bit  [15:0] image_rt;

    typedef struct packed {
        bit show_next;
        bit show;
        bit hide;
        bit reserved;
        bit vid_off;
        bit vid_on;
        bit sbuf;
        bit regs_upd;
        bit scroll;
        bit [1:0] vbuf;
    } video_command_s;

    bit fmv_request_for_bits;
    always_comb begin
        // Request for bits according to actual buffer water level
        fmv_request_for_bits = !fmv_fifo_full;
    end

    bit [5:0] mpeg_ram_enabled_cnt;

    always_comb begin
        dout = 0;

        case (address[15:1])
            15'h1800: dout = fma_command_register;  // 0x0E03000 CMD
            15'h1801: dout = {8'h02, fma_status_register};  // 0x0E03002 STATUS
            15'h1802: dout = 16'h0007;  // 0x0E03004
            15'h1803: dout = 16'h0900;  // 0x0E03006
            15'h1804: dout = {12'b0, fma_stream_number};  // 0x0E03008 Wanted stream id
            15'h1805: dout = {12'b0, fma_stream_number};  // 0x0E03008 Current Stream id
            15'h1806: dout = fma_interrupt_vector_register;  // 0x0E0300C
            15'h1807: dout = 16'h0042;  // 0x0E0300E some counter?
            15'h1808: dout = fma_dclk[31:16];  // 0x0E03010
            15'h1809: dout = fma_dclkl_latch;  // 0x0E03012
            15'h180A: dout = fma_mpeg_audio_header[31:16];  // 0x0E03014 MPEG Audio Header High
            15'h180B: dout = fma_mpeg_audio_header[15:0];  // 0x0E03016 MPEG Audio Header Low
            15'h180C: dout = {15'b0, fma_dsp_enable};  // 0x0E03018 RUN?
            15'h180D: dout = fma_interrupt_status_register;  // 0x0E0301A
            15'h180E: dout = fma_interrupt_enable_register;  // 0x0E0301C
            15'h1812: dout = 16'h0004;  // 0x0E03024, HF2 Flag of DSP56001?

            15'h2001: dout = image_width;  // 00E04002 ?? Written then Read FMV_IMGSZ
            15'h2002: dout = image_height;  // 00E04004 ?? Written then Read
            15'h2003: dout = image_rt;  // 00E04006 ??
            15'h2004: dout = fmv_decoder_timecode[31:16];  // 00E04008 Temporal time code High
            15'h2005: dout = fmv_decoder_timecode[15:0];  // 00E0400C Temporal time code Low
            15'h2029: dout = {5'b0, fmv_display_width};  // e04052 PIC Width, Only read FMV_PICSZ
            15'h202a: dout = {7'b0, fmv_display_height};  // e04054 PIC Height, Only read
            15'h202b: dout = {8'b0, fmv_display_frameperiod_rawhdr};  // e04056 Pic Rt ??
            15'h202c: dout = fmv_display_timecode[31:16];  // 00E04058 Time Code High ??
            15'h202d: dout = fmv_display_timecode[15:0];  // 00E0405A Time Code Low ??
            15'h202e: dout = {8'b0, fmv_display_video_status};  // 00E0405C SYS_VSR
            15'h202f: dout = {2'b0, fmv_request_for_bits, 13'b0};  // 00E0405E ? SYS_STS
            15'h2030: dout = fmv_interrupt_enable_register;  // 0E04060
            15'h2031: dout = fmv_interrupt_status_register;  // 0E04062
            15'h2032: dout = fmv_timer_compare_register;  // 0E04064
            15'h2036: dout = video_ctrl_y_offset;  // 0E0406C FMV_VOFF
            15'h2037: dout = video_ctrl_x_offset;  // 0E0406E FMV_HOFF
            15'h2038: dout = video_ctrl_y_active;  // 0E04070 FMV_VPIX
            15'h2039: dout = video_ctrl_x_active;  // 0E04072 FMV_HPIX
            15'h203a: dout = video_ctrl_y_display;  // 0E04074 FMV_SCRPOS Y
            15'h203b: dout = video_ctrl_x_display;  // 0E04076 FMV_SCRPOS X
            15'h203c: dout = video_ctrl_window_height;  // 0E04078 FMV_DECWIN H
            15'h203d: dout = video_ctrl_window_width;  // 0E0407A FMV_DECWIN W
            15'h203e: dout = video_ctrl_decoder_offset_y;  // 0E0407C FMV_DECOFF Y
            15'h203f: dout = video_ctrl_decoder_offset_x;  // 0E0407E FMV_DECOFF X
            15'h2044: dout = fmv_decoder_command;  // E04088 Decoder Command? GEN_DEC_CMD?
            15'h2046: dout = fmv_video_data_input_command_register;  // 0E0408C GEN_VDI_CMD
            15'h2049: dout = 0;  // 0E04092 GEN_VID_BUF
            15'h204C: dout = fmv_dclk[21:6];  // 0E04098 GEN_SYSCR
            15'h204E: dout = 0;  // e0409c GEN_SYNC_DIFF? Always reads 0 on real machine
            15'h204F: dout = 1;  // e0409e GEN_DEC_DELAY? Always changing but negative?
            15'h2050:
            dout = {
                1'b0, fmv_demuxer_decoding_timestamp_reduced_view
            };  // 00E040A0 Decoding Timestamp
            15'h2052: dout = {9'b0, fmv_pictures_in_fifo};  // 00E040A4 ?? Pictures in fifo?
            15'h2054: dout = fmv_decoder_frameperiod_90khz;  // E040A8 Picture Rate Only read.
            15'h2055: dout = fmv_display_rate;  // e040aa ?? Display Rate ? Only read.
            15'h2056: dout = fmv_frame_rate;  // e040ac ?? GEN_FRAME_RATE Read and written.
            15'h2060: dout = fmv_system_command_register;  // e040c0
            15'h2061: dout = fmv_video_command_register;  // e040c2
            15'h2062: dout = {12'b0, fmv_stream_number};  // e040c4
            15'h206e: dout = fmv_interrupt_vector_register;  //
            15'h2073: dout = 0;  // e040e6 MMU Base pointer? Checked once, value is ignored

            default: ;
        endcase

        if (intack) begin
            if (fma_intreq)
                dout = {fma_interrupt_vector_register[7:0], fma_interrupt_vector_register[7:0]};
            else dout = {fmv_interrupt_vector_register[10:3], fmv_interrupt_vector_register[10:3]};
        end
    end

    bit vsync_q;
    bit dma_active;
    assign req = dma_active;
    assign rdy = dma_active;

    // Increments at 90 kHz
    bit [15+5:0] timer_cnt = 0;

    bit restart_fmv_dsp_enable  /*verilator public_flat_rd*/;
    bit restart_fmv_dsp_enable_q;
    bit pending_fma_stream_change;
    bit register_update_latch;
    bit register_update_scroll;

    bit fmv_event_frame_decoded_q;

    always @(posedge clk) begin
        bus_ack <= 0;
        vsync_q <= vsync;
        dsp_reset_input_fifo <= 0;
        fmv_single_step <= 0;
        fmv_clear_fifo <= 0;
        fmv_event_frame_decoded_q <= fmv_event_frame_decoded;

        // create a single clock delay of this signal
        // should be better since this signal must be carried over to clk_mpeg
        restart_fmv_dsp_enable <= 0;
        restart_fmv_dsp_enable_q <= restart_fmv_dsp_enable;

        if (reset) begin
            dma_active <= 0;
            fma_command_register <= 0;
            fma_dclk <= 0;
            fma_dsp_enable <= 0;
            fma_interrupt_enable_register <= 0;
            fma_interrupt_status_register <= 0;
            fma_interrupt_vector_register <= 0;
            fma_status_register <= 0;
            fma_stream_number <= 0;
            fmv_dclk <= 0;
            fmv_dclk_start_video_latched <= 0;
            fmv_decoder_command <= 0;
            fmv_dsp_enable <= 0;
            fmv_frame_rate <= 0;
            fmv_interrupt_enable_register <= 0;
            fmv_interrupt_status_register <= 0;
            fmv_interrupt_vector_register <= 0;
            fmv_playback_active <= 0;
            fmv_decoder_active <= 0;
            fmv_show_on_next_video_frame <= 0;
            fmv_stream_number <= 0;
            fmv_system_command_register <= 0;
            fmv_video_data_input_command_register <= 0;
            image_height <= 0;
            image_rt <= 0;
            image_width <= 0;
            fmv_event_frame_decoded_q <= 0;
            mpeg_ram_enabled <= 0;
            mpeg_ram_enabled_cnt <= 0;
            pending_fma_stream_change <= 0;
            timer_cnt <= 0;
            vcd_pixel_clock <= 0;
            video_ctrl_decoder_offset_x <= 0;
            video_ctrl_decoder_offset_y <= 0;
            video_ctrl_window_height <= 0;
            video_ctrl_window_width <= 0;
            video_ctrl_x_active <= 0;
            video_ctrl_x_display <= 0;
            video_ctrl_x_offset <= 0;
            video_ctrl_y_active <= 0;
            video_ctrl_y_display <= 0;
            video_ctrl_y_offset <= 0;
        end else begin

            if (fmv_event_frame_decoded_q && fmv_playback_active) begin
                image_width <= {5'b0, fmv_decoder_width};
                image_height <= {7'b0, fmv_decoder_height};
                image_rt <= {8'b0, fmv_decoder_frameperiod_rawhdr};
            end

            if (restart_fmv_dsp_enable_q) fmv_dsp_enable <= 1;
            if (fmv_demuxer_decoding_timestamp_updated)
                fmv_video_data_input_command_register[14] <= 1;

            // implementation of playback delay
            if (fmv_dclk_start_video_latched && fmv_dclk_start_video == fma_dclk) begin
                fmv_dclk_start_video_latched <= 0;
                fmv_playback_active <= 1;
            end

            if (fmv_dclk_pause_video_latched && fmv_dclk_pause_video == fma_dclk) begin
                fmv_dclk_pause_video_latched <= 0;
                fmv_interrupt_status_register.pai <= 1;
            end

            if (vsync && !vsync_q) fmv_interrupt_status_register.vsync <= 1;

            // Either update when scroll==1 and vertical retrace occurs OR
            // when scroll==0 and a new frame will be displayed
            if ((!vsync && vsync_q && register_update_latch && register_update_scroll) ||
                (register_update_latch && fmv_event_potential_picture_starts_display && !register_update_scroll)) begin

                fmv_interrupt_status_register.vcup <= 1;
                // Always present on VMPEG when VCUP occurs, never asked for in the driver
                // At 0x00e52ed2 there is a check for a solo occurence of VCUP
                // This never happens on real hardware since DCL is always there
                // resulting into a dead branch in the driver?
                fmv_interrupt_status_register.dcl <= 1;
                register_update_latch <= 0;

                latched_display_offset_y <= video_ctrl_x_display[8:0];
                latched_display_offset_x <= video_ctrl_y_display[8:0];
                latched_window_offset_y <= video_ctrl_decoder_offset_y[8:0];
                latched_window_offset_x <= video_ctrl_decoder_offset_x[8:0];
                latched_window_width <= video_ctrl_window_width[8:0];
                latched_window_height <= video_ctrl_window_height[8:0];
            end

            if (fmv_event_first_intra_frame_seq_starts_display) begin
                fmv_interrupt_status_register.seq <= 1;
                $display("Cause FMV Seq Event");
            end
            if (fmv_event_first_intra_frame_gop_starts_display)
                fmv_interrupt_status_register.gop <= 1;
            if (fmv_event_picture_starts_display) begin
                fmv_interrupt_status_register.pic <= 1;

            end
            if (fmv_event_last_picture_starts_display) fmv_interrupt_status_register.eod <= 1;
            if (fmv_event_program_end) fmv_interrupt_status_register.eii <= 1;
            if (fmv_event_sequence_end) fmv_interrupt_status_register.esi <= 1;
            if (fmv_event_buffer_underflow) begin
                fmv_interrupt_status_register.ndat <= 1;
                $display("FMV Underflow");
            end

            if (fma_event_decoding_started) begin
                // Decoding started
                fma_status_register[4] <= 1;

                // Decoding started IRQ
                fma_interrupt_status_register[4] <= 1;
            end

            if (fma_event_frame_decoded) begin
                // Frame Header Updated
                fma_status_register[2]           <= 1;

                // Frame Header Updated IRQ
                fma_interrupt_status_register[2] <= 1;

                // Stream change IRQ
                fma_interrupt_status_register[1] <= pending_fma_stream_change;
                pending_fma_stream_change        <= 0;
            end

            if (fma_event_underflow) begin
                // Underflow
                fma_status_register[3] <= 1;

                // Underflow IRQ
                fma_interrupt_status_register[3] <= 1;

                // No longer decoding
                fma_status_register[4] <= 0;

                fma_dsp_enable <= 0;
            end

            if (fma_event_program_end) begin
                // ISO End detected IRQ
                fma_interrupt_status_register[0] <= 1;

                // Operation finished
                fma_status_register[0] <= 1;
            end


            if (clk45tick) begin
                fma_dclk <= fma_dclk + 1;

                // TODO Concerning slow motion, some changes might be required
                fmv_dclk <= fmv_dclk + 1;

                // fmv_timer_compare_register can be assumed as 55
                // We need an IRQ frequency of exactly 100.446428571429 Hz,
                // to match the SCR increment of 896 as expected by fmvd
                // See dvc.md for more info
                // Since V_ExtSCR is set, this might have no impact at all though...
                if (timer_cnt >= {2'b00, fmv_timer_compare_register, 3'b000} + 7) begin
                    fmv_interrupt_status_register.tim <= 1;
                    fma_interrupt_status_register[8] <= 1;
                    timer_cnt <= 0;
                    $display("VMPEG Timer IRQ at %d", fma_dclk);
                end else begin
                    timer_cnt <= timer_cnt + 1;
                end

            end

            if (fma_start_playback) begin
                fma_dsp_enable <= 1;
            end

            if (done_in && ack) begin
                fma_command_register[15] <= 0;
                dma_active <= 0;
                dma_for_fma <= 0;
            end

            if (access) begin
                bus_ack <= !bus_ack;

                if (bus_ack) begin
                    if (write_strobe)
                        $display("DVC Write %x %x %d %d", {address[23:1], 1'b0}, din, uds, lds);
                    else $display("DVC Read %x %x %d %d", {address[23:1], 1'b0}, dout, uds, lds);
                end

                if (!write_strobe && bus_ack) begin
                    if (address[15:1] == 15'h2031) begin
                        // Reading the Interrupt Status Register resets it
                        fmv_interrupt_status_register <= 0;
                    end

                    if (address[15:1] == 15'h180D) begin
                        // Reading the Interrupt Status Register resets it
                        fma_interrupt_status_register <= 0;
                    end

                    if (address[15:1] == 15'h1808) begin
                        fma_dclkl_latch <= fma_dclk[15:0];
                    end
                end

                if (write_strobe && bus_ack) begin
                    mpeg_ram_enabled_cnt <= mpeg_ram_enabled_cnt + 1;
                    if (mpeg_ram_enabled_cnt == 6'b111111) begin
                        mpeg_ram_enabled <= 1;
                        if (!mpeg_ram_enabled) $display("MPEG RAM Enabled!");
                    end


                    if (address[15:1+8] == 7'h08) begin
                        // VMPEG Pixelclock
                        $display("VMPEG VCD %x %x", address[15:1], din);
                        vcd_pixel_clock <= din[0];
                    end

                    case (address[15:1])
                        // FMA Registers
                        15'h1800: begin
                            $display("FMA CMD %x %x", address[15:1], din);

                            /*
                            FMA CMD 1800 0001 Stop ?
                            FMA CMD 1800 0002 Start ?
                            FMA CMD 1800 8002 DMA Transfer
                            */

                            fma_command_register <= din;
                            if (din[15]) begin
                                dma_active <= 1;
                                dma_for_fma <= 1;

                                // According to 8.2.4.3.3 in the green book,
                                // the underflow status flag has to be reset
                                // when a transfer is performed
                                fma_status_register[3] <= 0;
                            end

                            if (din[0]) begin
                                // Stop command?
                                fma_dsp_enable <= 0;
                                dsp_reset_input_fifo <= 1;

                                // Reset status register?
                                fma_status_register <= 0;
                            end
                        end
                        15'h1802: begin
                            // Unknown write of immediate 7 at vmpega rom 00e50312
                            // DVC Write e03004 0007 1 1
                            // directly after writing the FMA stream number.
                        end
                        15'h1804: begin
                            // According to mv_selstrm() this can be 0-15
                            $display("FMA Write Stream Number %x %x", address[15:1], din);
                            fma_stream_number <= din[3:0];

                            // TODO Probably not accurate...
                            pending_fma_stream_change <= 1;
                        end

                        15'h1806: begin
                            $display("FMA IVEC %x %x", address[15:1], din);
                            fma_interrupt_vector_register <= din;
                        end
                        15'h180C: begin
                            $display("FMA RUN %x %x", address[15:1], din);
                        end
                        15'h180E: begin
                            fma_interrupt_enable_register <= din;
                            $display("FMA IER %x %x", address[15:1], din);
                        end
                        15'h1811: begin
                            fma_dspa <= din[7:0];
                            $display("FMA DSPA %x %x", address[15:1], din);
                        end
                        15'h1812: begin
                            $display("FMA DSPD %x %x", address[15:1], din);
                        end
                        // FMV Registers
                        15'h2030: begin
                            fmv_interrupt_enable_register <= din;
                            $display("FMV Write IER Register %x %x", address[15:1], din);
                        end
                        15'h2031: begin
                            // TODO interrupt_status_register;
                        end
                        15'h2032: begin  // 0E04064
                            $display("FMV Write TCNT Register %x %x", address[15:1], din);
                            fmv_timer_compare_register <= din;
                        end
                        15'h2057: begin
                            $display("FMV Write TRLD Register %x %x", address[15:1], din);
                            timer_cnt <= 0;
                        end
                        15'h2060: begin
                            $display("FMV Write SYSCMD Register %x %x", address[15:1], din);
                            /*
                            according to cdiemu in this order when playing videos
	                          FMV SYSCMD 2000 RELEASE
	                          FMV SYSCMD 0100 RESET
	                          FMV SYSCMD 1000 START
	                          FMV SYSCMD 8000 DMA

	                        according to fmvd.txt
                              0008 Play
                              0010 Pause
                              0020 Continue
                              0040 Step
                              0080 Stop
	                          0100 Clear FIFO
                              0400 Search for GOP
	                          1000 Decoder on
	                          2000 Decoder off
	                          8000 Start DMA

                            Certain patterns observed on 210/05 with VMPEG:
                              mv_freeze()
                                0x8000 -> 0x0010 and stay like that. no further events via mv_trigger() callback
                                Also no further DMA transfers
                              mv_continue(path,0) after mv_freeze() to continue fast
                                0x0010 -> 0x0100 -> 0x0000 -> 0x8000
                              mv_continue(path,1) after mv_freeze() to search for GOP
                                0x0010 -> 0x0100 -> 0x0400 -> 0x8000
                              mv_continue(path,2) after mv_freeze() to start at SEQ
                                0x0010 -> 0x0100 -> 0x0600 -> 0x8000
                              mv_cdplay() from cold boot
                                Reset value 0x0000 -> 0x2000 -> 0x0100 -> 0x1000 -> 0x8000 -> 0x0008 -> 0x8000
                              Fast Forward during "Coneheads"
                                0x8000 -> 0x0010 -> 0x0100 -> 0x1000 Pauses normal play
                                0x1000 -> 0x8000 -> 0x0008 -> 0x8000 -> 0x0080 -> 0x0100 -> 0x1000 and repeat
                                Beginning is like a normal playback but uses 0080 Stop
                            */
                            fmv_system_command_register <= din;

                            if (din[3]) begin  // 0008 Play
                                fmv_dclk_start_video <= fma_dclk + 32'd1000;
                                fmv_dclk_start_video_latched <= 1;

                                image_width <= {5'b0, fmv_decoder_width};
                                image_height <= {7'b0, fmv_decoder_height};
                                image_rt <= {8'b0, fmv_decoder_frameperiod_rawhdr};

                                // TODO can't be correct. set 0x42
                                fmv_decoder_command[6] <= 1;
                                fmv_decoder_command[1] <= 1;
                                fmv_slow_motion <= din[2:0];

                                fmv_decoder_active <= 1;
                            end

                            if (din[4]) begin  // 0010 Pause
                                fmv_playback_active <= 0;
                                fmv_dclk_start_video_latched <= 0;

                                fmv_dclk_pause_video <= fma_dclk + 32'd100;
                                fmv_dclk_pause_video_latched <= 1;
                            end

                            if (din[5]) begin  // 0020 Continue
                                fmv_dclk_start_video <= fma_dclk + 32'd1000;  // delay
                                fmv_dclk_start_video_latched <= 1;

                                fmv_slow_motion <= din[2:0];
                            end

                            if (din[6]) begin  // 0040 Step
                                fmv_single_step <= 1;
                                fmv_dclk_start_video_latched <= 0;
                            end

                            if (din[7]) begin  // 0080 Stop
                                fmv_playback_active <= 0;
                                fmv_dclk_start_video_latched <= 0;
                                fmv_decoder_active <= 0;
                            end

                            if (din[8]) begin  // 0100 Clear FIFO? What to do?
                                fmv_dsp_enable <= 0;
                                fmv_playback_active <= 0;
                                fmv_dclk_start_video_latched <= 0;
                                restart_fmv_dsp_enable <= 1;
                                fmv_clear_fifo <= 1;
                            end

                            if (din[10]) begin  // 0400 Search for GOP

                            end

                            if (din[12]) begin  // 1000 Decoder on
                                fmv_dsp_enable <= 1;
                                fmv_reset_persistent_storage <= 0;
                                $display("FMV Decoder On");
                            end

                            if (din[13]) begin  // 2000 Decoder off
                                fmv_dsp_enable <= 0;
                                fmv_playback_active <= 0;
                                fmv_dclk_start_video_latched <= 0;
                                fmv_reset_persistent_storage <= 1;
                                fmv_decoder_active <= 0;

                                $display("FMV Decoder Off");

                                // TODO confirm that this is happening
                                image_width <= 0;
                                image_height <= 0;
                                image_rt <= 0;
                            end

                            if (din[15]) begin  // 8000 DMA
                                dma_active  <= 1;
                                dma_for_fma <= 0;
                            end

                        end
                        15'h2061: begin
                            $display("FMV Write VIDCMD Register %x %x", address[15:1], din);
                            /*
	                        according to fmvd.txt
                              0008 RegsUpd
                              000c Scroll + RegsUpd
                              0020 VidOn
                              0100 Hide
                              0200 Show
                              0420 Show on next picture change
                            */
                            fmv_video_command_register <= din;

                            // 0008 RegsUpd
                            if (din[3]) begin
                                register_update_latch  <= 1;
                                register_update_scroll <= din[2];
                                $display("RegsUpd");
                            end

                            // Hide 0100
                            if (din[8]) fmv_show_on_next_video_frame <= 0;

                            // Show Window 0200
                            if (din[9]) fmv_show_on_next_video_frame <= 1;
                            // Show Window on next picture change 0400
                            if (din[10]) begin
                                fmv_show_on_next_video_frame <= 1;
                            end

                            // TODO this might not be right
                        end
                        15'h2063: begin
                            $display("FMV Write SYSSCR Register %x %x", address[15:1], din);
                            fmv_system_control_register <= din;
                        end
                        15'h206F: begin  // 0E040DE
                            $display("FMV Write XFER Register %x %x", address[15:1], din);
                        end
                        15'h206E: begin
                            fmv_interrupt_vector_register <= din;
                            $display("FMV Write IVEC Register %x %x", address[15:1], din);
                        end
                        15'h2036: begin
                            $display("FMV Write Y Offset %x %x", address[15:1], din);
                            video_ctrl_y_offset <= din;  // seems to be always 001A
                        end
                        15'h2037: begin
                            $display("FMV Write X Offset %x %x", address[15:1], din);
                            video_ctrl_x_offset <= din;  // seems to be always 004A
                        end
                        15'h2038: begin
                            $display("FMV Write Y Active %x %x", address[15:1], din);
                            video_ctrl_y_active <= din;
                        end
                        15'h2039: begin
                            $display("FMV Write X Active %x %x", address[15:1], din);
                            video_ctrl_x_active <= din;
                        end
                        15'h203a: begin
                            $display("FMV Write Y Display %x %x ?", address[15:1], din);
                            video_ctrl_y_display <= din;
                        end
                        15'h203b: begin
                            $display("FMV Write X Display %x %x ?", address[15:1], din);
                            video_ctrl_x_display <= din;
                        end

                        15'h203c: begin
                            $display("FMV Write FMV_DECWIN H %x %x ?", address[15:1], din);
                            video_ctrl_window_height <= din;
                        end
                        15'h203d: begin
                            $display("FMV Write FMV_DECWIN W %x %x ?", address[15:1], din);
                            video_ctrl_window_width <= din;
                        end
                        15'h203e: begin
                            $display("FMV Write FMV_DECOFF Y %x %x ?", address[15:1], din);
                            video_ctrl_decoder_offset_y <= din;
                        end
                        15'h203f: begin
                            $display("FMV Write FMV_DECOFF X %x %x ?", address[15:1], din);
                            video_ctrl_decoder_offset_x <= din;
                        end
                        15'h2044: begin
                            $display("FMV Write GEN_DEC_CMD %x %x ?", address[15:1], din);
                            fmv_decoder_command <= din;

                            // TODO I'm very unsure about this
                            if (din[15:8] == 8'h22 && fmv_system_command_register[4] == 0) begin
                                fmv_single_step <= 1;
                            end
                        end
                        15'h2046: begin
                            $display("FMV Write GEN_VDI_CMD %x %x ?", address[15:1], din);
                            fmv_video_data_input_command_register <= din;
                        end
                        15'h2049: begin
                            $display("FMV Write GEN_VID_BUF %x %x ?", address[15:1], din);
                        end
                        15'h204C: begin
                            $display("FMV Write GEN_SYSCR %x %x ?", address[15:1], din);
                            fmv_dclk[21:6] <= din;
                        end
                        15'h2056: begin
                            $display("FMV Write GEN_FRAME_RATE %x %x ?", address[15:1], din);
                            fmv_frame_rate <= din;
                        end
                        15'h2001: begin
                            $display("FMV Write Image Width2 %x %x", address[15:1], din);
                            image_width <= din;
                        end
                        15'h2002: begin
                            $display("FMV Write Image Height2 %x %x", address[15:1], din);
                            image_height <= din;
                        end
                        15'h2003: begin
                            $display("FMV Write Image RT? %x %x", address[15:1], din);
                            image_rt <= din;
                        end
                        15'h2062: begin
                            // According to mv_selstrm() this can be 0-15
                            $display("FMV Write Stream Number %x %x", address[15:1], din);
                            fmv_stream_number <= din[3:0];
                        end
                        default: ;
                    endcase
                end
            end
        end
    end


endmodule


