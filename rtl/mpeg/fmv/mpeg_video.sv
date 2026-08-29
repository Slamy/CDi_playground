`timescale 1 ns / 1 ps
`include "../util.svh"

module mpeg_video (
    input clk30,
    input clk_mpeg,
    input reset,
    input dsp_enable,
    input clear_fifo,
    input reset_persistent_storage,
    input playback_active,
    input synchronous_playback,
    input decoder_active,
    input single_step,
    input [2:0] slow_motion,

    input  [7:0] data_byte,
    input        data_strobe,
    output       fifo_full,

    ddr_if.to_host ddrif,

    output rgb888_s vidout,

    input vcd_pixel_clock,
    input debug_activate_vcd_filter,
    input hsync,
    input vsync,
    input hblank,
    input vblank,

    input [8:0] display_offset_y,
    input [8:0] display_offset_x,
    input [8:0] window_offset_y,
    input [8:0] window_offset_x,
    input [8:0] window_width,
    input [8:0] window_height,
    input show_on_next_video_frame,
    output event_sequence_end,
    output event_frame_decoded,
    output bit event_buffer_underflow,
    output bit event_picture_starts_display,
    output event_last_picture_starts_display,
    output bit event_first_intra_frame_gop_starts_display,
    output bit event_first_intra_frame_seq_starts_display,
    output bit [6:0] pictures_in_fifo,
    input signed [32:0] demuxer_decoding_timestamp,
    input demuxer_decoding_timestamp_updated,
    input signed [32:0] demuxer_system_clock_reference,
    input signed [31:0] dclk,  // only 21:6 shall be used (16 bit)
    output bit event_potential_picture_starts_display,

    output bit [10:0] decoder_width,
    output bit [ 8:0] decoder_height,
    output bit [31:0] decoder_timecode,
    output bit [15:0] decoder_frameperiod_90khz,
    output bit [ 7:0] decoder_frameperiod_rawhdr,

    output bit [10:0] display_width,
    output bit [ 8:0] display_height,
    output bit [ 7:0] display_video_status,
    output bit [31:0] display_timecode,
    output bit [ 7:0] display_frameperiod_rawhdr

);
    ddr_if worker_2_ddr ();
    ddr_if worker_3_ddr ();
    ddr_if worker_4_ddr ();
    ddr_if player_ddr ();

    ddr_mux4 ddrmux (
        .clk(clk_mpeg),
        .x  (ddrif),
        .a  (player_ddr),
        .b  (worker_2_ddr),
        .c  (worker_3_ddr),
        .d  (worker_4_ddr)
    );


    bit [2:0] slow_motion_clkddr;
    // Metastability will result into a single wrongly timed frame
    // when speed is changed. That should be OK
    always_ff @(posedge clk_mpeg) slow_motion_clkddr <= slow_motion;

    wire reset_clk_mpeg;

    flag_cross_domain cross_reset (
        .clk_a(clk30),
        .clk_b(clk_mpeg),
        .flag_in_clk_a(reset),
        .flag_out_clk_b(reset_clk_mpeg)
    );

    wire dsp_enable_clk_mpeg;

    signal_cross_domain cross_reset2 (
        .clk_a(clk30),
        .clk_b(clk_mpeg),
        .signal_in_clk_a(dsp_enable),
        .signal_out_clk_b(dsp_enable_clk_mpeg)
    );

    wire reset_persistent_storage_clk_mpeg;

    signal_cross_domain cross_reset_persistent_storage (
        .clk_a(clk30),
        .clk_b(clk_mpeg),
        .signal_in_clk_a(reset_persistent_storage),
        .signal_out_clk_b(reset_persistent_storage_clk_mpeg)
    );

    wire reset_dsp_enabled = reset || !dsp_enable;
    wire reset_dsp_enabled_clk_mpeg = reset_clk_mpeg || !dsp_enable_clk_mpeg;

    bit [15:0] dct_coeff_result;
    bit dct_coeff_huffman_active = 0;
    bit dct_coeff_huffman_table = 0;

    wire dct_coeff_result_valid;
    dct_coeff_huffman_decoder huff (
        .clk(clk_mpeg),
        .reset(reset_dsp_enabled_clk_mpeg),
        .codetable(dct_coeff_huffman_table),
        .data_valid(dct_coeff_huffman_active && hw_read_mem_ready && !dct_coeff_result_valid),
        .data(mpeg_in_fifo_out[31-hw_read_bit_shift]),
        .result_valid(dct_coeff_result_valid),
        .result(dct_coeff_result)
    );

    // 8kB of MPEG stream memory to fill from outside
    wire [31:0] mpeg_in_fifo_out;

    // Why did I do this? O.o
    bit  [12:0] mpeg_input_stream_fifo_raddr_read_fix;

    always_comb begin
        mpeg_input_stream_fifo_raddr_read_fix = dmem_cmd_payload_address_1[14:2];

        if (hw_read_count != 0) begin
            mpeg_input_stream_fifo_raddr_read_fix = mpeg_stream_fifo_read_adr[14:2];

            if (hw_read_mem_ready && (!hw_read_aligned_access || mpeg_stream_bit_index[4:0]==5'b11111) )
                mpeg_input_stream_fifo_raddr_read_fix = mpeg_input_stream_fifo_raddr_read_fix + 1;
        end
    end

    wire picture_startcode;

    mpeg_video_start_code_decoder startcode (
        .clk(clk30),
        .reset,
        .mpeg_data(data_byte),
        .data_valid(data_strobe),
        .event_sequence_header(),
        .event_group_of_pictures(),
        .event_picture(picture_startcode),
        .tmpref(),
        .timecode()
    );

    wire picture_added_in_input_fifo = picture_startcode;
    bit signed [32:0] next_picture_demuxer_decoding_timestamp;
    always_ff @(posedge clk30) begin
        if (picture_added_in_input_fifo) begin
            $display("DTS ADDED %d", next_picture_demuxer_decoding_timestamp);
            next_picture_demuxer_decoding_timestamp <= 0;
        end

        if (demuxer_decoding_timestamp_updated) begin
            next_picture_demuxer_decoding_timestamp <= demuxer_decoding_timestamp;
        end
    end

    wire dts_fifo_valid;
    (* keep *) (* noprune *) wire signed [32:0] dts_fifo_out;

    wire [6:0] pictures_in_dts_fifo;

    // Keeps decoder timestamps from insertion into input FIFO
    // until they are displayed.
    // Useful for keeping timing
    mpeg_timestamp_fifo dts_fifo (
        .clk(clk30),
        .reset(reset || clear_fifo),
        .wdata(next_picture_demuxer_decoding_timestamp),
        .we(picture_added_in_input_fifo),
        // Add dts_fifo_valid to avoid underflows (just in case)
        .strobe(latch_frame_for_display && dts_fifo_valid),
        .valid(dts_fifo_valid),
        .q(dts_fifo_out),
        .cnt(pictures_in_dts_fifo)
    );

    wire dts_fifo_out_valid_dts = dts_fifo_valid && (dts_fifo_out != 0);

    // Useful for fast forwarding after slow motion
    wire signed [32:0] demuxer_dts_desync = demuxer_system_clock_reference - dts_fifo_out;

    wire totally_out_of_sync_need_frameskip = dts_fifo_out_valid_dts && demuxer_dts_desync > 15000;

    // Only bits 21:6 can be changed by the CPU
    // It should be noted that the driver wants to have bit 21 always 0.
    // So only bits 20:6 of dclk must be used here.
    (* keep *)
    (* noprune *)
    wire signed [14:0] display_dts_desync = dclk[20:6] - dts_fifo_out[21:7];

    // Latched from display_dts_desync at latch_frame_for_display
    // to help with meta stability
    (* keep *) (* noprune *) bit signed [14:0] display_dts_desync_q;

    // Inc on picture_added_in_input_fifo
    // Dec on event_frame_decoded
    bit [6:0] pictures_in_input_fifo  /*verilator public_flat_rd*/;

    // Currently unused
    // Inc on picture_added_in_input_fifo
    // Dec on event_frame_decoded
    bit [5:0] pictures_in_input_fifo_or_decoder  /*verilator public_flat_rd*/;
    // Number of decoded pictures queued for display
    // On a real VMPEG, there is probably only enough RAM for 3 pictures
    // But we have tons have RAM, so we can apply some tricks to ensure a stable decoding rate
    wire [4:0] pictures_in_output_fifo  /*verilator public_flat_rd*/;

    // The number of pictures kept inside the decoder for reordering
    // Inc on event_frame_decoded
    // Dec on just_decoded_commit
    bit [4:0] pictures_in_mpeg_decoder;

    always_comb begin
        if (playback_active) begin
            // Advertize the pictures inside the decoder as not counted
            // Seems to match the expected relation between DTS and PICS_IN_FIFO to allow fast MV_Pause
            // with matching duration as measured on real hardware
            pictures_in_fifo = pictures_in_input_fifo + {2'b00, pictures_in_output_fifo};
        end else begin
            // Act like decoder has not yet started, even so we are already decoding
            // to mimic a real VMPEG
            pictures_in_fifo = pictures_in_dts_fifo;
        end
    end

    bit signed [31:0] last_display_latch_dclk = 0;
    always_ff @(posedge clk30) begin
        // Catch something that should not be possible

        if (clear_fifo || reset_dsp_enabled) begin
            display_dts_desync_q <= 0;
        end else if (frame_period_tick) begin
            last_display_latch_dclk <= dclk;
            assert (dts_fifo_valid);
            if (dts_fifo_out_valid_dts)
                $display(
                    "desync_valid %d %d %d %d",
                    dclk,
                    dclk - last_display_latch_dclk,
                    display_dts_desync,
                    demuxer_dts_desync
                );
            else
                $display(
                    "desync %d %d %d %d",
                    dclk,
                    dclk - last_display_latch_dclk,
                    display_dts_desync,
                    demuxer_dts_desync
                );

            // Only apply during synchronous playback and when we have a valid DTS for desync calculation
            display_dts_desync_q <= (dts_fifo_out_valid_dts && synchronous_playback) ? display_dts_desync : 0;
        end

        event_buffer_underflow <= pictures_in_fifo==1 && latch_frame_for_display && pictures_in_mpeg_decoder==0;

        if (just_decoded_commit_clk30) begin
            assert (pictures_in_mpeg_decoder > 0);
            pictures_in_mpeg_decoder <= pictures_in_mpeg_decoder - 1;
        end

        if (event_frame_decoded) begin
            pictures_in_mpeg_decoder <= pictures_in_mpeg_decoder + 1;
        end

        if (clear_fifo) begin
            pictures_in_input_fifo <= 0;
            pictures_in_mpeg_decoder <= 0;
            pictures_in_input_fifo_or_decoder <= 0;
        end else if (event_frame_decoded && !picture_added_in_input_fifo && pictures_in_input_fifo!=0)
            pictures_in_input_fifo <= pictures_in_input_fifo - 1;
        else if (!event_frame_decoded && picture_added_in_input_fifo)
            pictures_in_input_fifo <= pictures_in_input_fifo + 1;

        if (picture_added_in_input_fifo && !event_frame_decoded)
            pictures_in_input_fifo_or_decoder <= pictures_in_input_fifo_or_decoder + 1;
        else if (!picture_added_in_input_fifo && event_frame_decoded)
            pictures_in_input_fifo_or_decoder <= pictures_in_input_fifo_or_decoder - 1;

    end

    mpeg_input_stream_fifo_32k in_fifo (
        .clkw(clk30),
        // In, invert endianness at the same time
        .waddr({mpeg_stream_fifo_write_adr[14:2], 2'b11 - mpeg_stream_fifo_write_adr[1:0]}),
        .wdata(data_byte),
        .we(data_strobe),
        // Out (32 bit CPU interface)
        .clkr(clk_mpeg),
        .raddr(mpeg_input_stream_fifo_raddr_read_fix),
        .q(mpeg_in_fifo_out)
    );

    bit [4:0] hw_read_count = 0;
    bit [31:0] hw_read_result = 32;

    // Byte Address
    bit [28:0] mpeg_stream_fifo_write_adr;
    bit [31:0] mpeg_stream_bit_index;
    wire [28:0] mpeg_stream_fifo_read_adr = mpeg_stream_bit_index[31:3];

    wire [28:0] fifo_level /*verilator public_flat_rd*/ = mpeg_stream_fifo_write_adr - mpeg_stream_fifo_read_adr;

    wire fifo_underflow = mpeg_stream_fifo_write_adr_clk_mpeg < mpeg_stream_fifo_read_adr;
    bit [31:0] decoder_failing_address;
    bit decoder_failing_address_set = 0;

    always_ff @(posedge clk_mpeg) begin
        if (reset_dsp_enabled_clk_mpeg) begin
            decoder_failing_address_set <= 0;
        end else if (fifo_underflow && !decoder_failing_address_set) begin
            // This is a bad sign! The reader just went faster than the writer. Prepare for impact!
            decoder_failing_address_set <= 1;
            decoder_failing_address <= imem_cmd_payload_address_1;
            $display("Underflow of FIFO at %x", imem_cmd_payload_address_1);
            //$finish();
        end
    end

    wire [28:0] fifo_level_clk_mpeg = mpeg_stream_fifo_write_adr_clk_mpeg - mpeg_stream_fifo_read_adr;
    wire fifo_full_clk_mpeg = fifo_level_clk_mpeg > 29'd28000;

    bit has_sequence_header = 0;
    bit hw_read_mem_ready = 0;
    wire [4:0] hw_read_bit_shift = mpeg_stream_bit_index[4:0];

    wire [5:0] hw_read_remaining_bits_in_dword = 32 - hw_read_bit_shift;
    wire hw_read_aligned_access = (6'(hw_read_count) <= hw_read_remaining_bits_in_dword);
    wire [ 4:0] hw_read_count_aligned = hw_read_aligned_access ? hw_read_count : hw_read_remaining_bits_in_dword[4:0];
    wire [31:0] hw_read_mask = ones_mask(hw_read_count_aligned);

    bit [3:0] sync_write_adr_cnt;
    bit [28:0] mpeg_stream_fifo_write_adr_syncval;
    bit mpeg_stream_fifo_write_adr_syncflag;
    bit mpeg_stream_fifo_write_adr_syncflag_clk_mpeg;
    bit [28:0] mpeg_stream_fifo_write_adr_clk_mpeg;

    // TODO This is a weird approach to sync the write address over
    // It has 16 clocks of latency but doesn't need any gray code
    always_ff @(posedge clk30) begin
        sync_write_adr_cnt <= sync_write_adr_cnt + 1;
        mpeg_stream_fifo_write_adr_syncflag <= 0;

        if (sync_write_adr_cnt == 0) begin
            mpeg_stream_fifo_write_adr_syncflag <= 1;
            mpeg_stream_fifo_write_adr_syncval  <= mpeg_stream_fifo_write_adr;
        end
    end

    flag_cross_domain cross_fifo_write_adr_syncflag (
        .clk_a(clk30),
        .clk_b(clk_mpeg),
        .flag_in_clk_a(mpeg_stream_fifo_write_adr_syncflag),
        .flag_out_clk_b(mpeg_stream_fifo_write_adr_syncflag_clk_mpeg)
    );

    signal_cross_domain cross_fifo_full (
        .clk_a(clk_mpeg),
        .clk_b(clk30),
        .signal_in_clk_a(fifo_full_clk_mpeg),
        .signal_out_clk_b(fifo_full)
    );

    always_ff @(posedge clk_mpeg) begin
        if (mpeg_stream_fifo_write_adr_syncflag_clk_mpeg)
            mpeg_stream_fifo_write_adr_clk_mpeg <= mpeg_stream_fifo_write_adr_syncval;
    end

    always_ff @(posedge clk30) begin
        if (reset_dsp_enabled) begin
            mpeg_stream_fifo_write_adr <= 0;
        end else if (data_strobe) begin
            mpeg_stream_fifo_write_adr <= mpeg_stream_fifo_write_adr + 1;
        end
    end

    always_ff @(posedge clk_mpeg) begin
        if (fifo_full_clk_mpeg) begin
            //$display("VIDEO FIFO FULL");
            //$finish();
        end

        hw_read_mem_ready <= 0;

        if (reset_dsp_enabled_clk_mpeg) begin
            mpeg_stream_bit_index <= 0;
            hw_read_count <= 0;
            dct_coeff_huffman_active <= 0;
        end else begin

            if (dmem_cmd_payload_write_1 && dmem_cmd_valid_1) begin
                if (dmem_cmd_payload_address_1 == 32'h10002000) $finish();

                if (dmem_cmd_payload_address_1 == 32'h10002004)
                    mpeg_stream_bit_index <= dmem_cmd_payload_data_1;
                if (dmem_cmd_payload_address_1 == 32'h10002008) begin
                    hw_read_count  <= dmem_cmd_payload_data_1[4:0];
                    hw_read_result <= 0;
                end
                if (dmem_cmd_payload_address_1 == 32'h1000200c) begin
                    hw_read_count <= 1;
                    dct_coeff_huffman_active <= 1;
                    dct_coeff_huffman_table <= dmem_cmd_payload_data_1[0];
                end
            end

            if (hw_read_count_aligned != 0) begin
                hw_read_mem_ready <= 1;

                if (hw_read_mem_ready) begin
                    hw_read_result <= (hw_read_result<<hw_read_count_aligned) |
                        ((mpeg_in_fifo_out >> (32 - hw_read_count_aligned - hw_read_bit_shift)) & hw_read_mask);

                    mpeg_stream_bit_index <= mpeg_stream_bit_index + 32'(hw_read_count_aligned);
                    hw_read_count <= hw_read_count - hw_read_count_aligned;
                end
            end

            if (dct_coeff_result_valid) begin
                dct_coeff_huffman_active <= 0;
                mpeg_stream_bit_index <= mpeg_stream_bit_index;
                hw_read_count <= 0;
            end else if (dct_coeff_huffman_active) begin
                hw_read_count <= 1;
                hw_read_mem_ready <= 1;
            end
        end


    end

    bit  [31:0] frames_decoded;

    // Memory arrays
    wire [31:0] memory_out_i1;
    wire [31:0] memory_out_d1;
    decoder_firmware_memory core1mem (
        .clk(clk_mpeg),
        .addr2(imem_cmd_payload_address_1[13:2]),
        .data_out2(memory_out_i1),
        .be2(0),
        .we2(0),
        .data_in2(0),
        .addr1(dmem_cmd_payload_address_1[13:2]),
        .data_in1(dmem_cmd_payload_data_1),
        .we1(dmem_cmd_payload_address_1[31:28]==0 && dmem_cmd_valid_1 && dmem_cmd_ready_1 &&
                dmem_cmd_payload_write_1 && !reset_dsp_enabled_clk_mpeg),
        .be1(dmem_cmd_payload_mask_1),
        .data_out1(memory_out_d1)
    );

    // Core 1 signals
    wire        imem_cmd_valid_1;
    bit         imem_cmd_ready_1;
    wire [ 0:0] imem_cmd_payload_id_1;
    wire [31:0] imem_cmd_payload_address_1;
    bit         imem_rsp_valid_1;
    bit  [ 0:0] imem_rsp_payload_id_1;
    bit         imem_rsp_payload_error_1;
    bit  [31:0] imem_rsp_payload_word_1;
    wire        dmem_cmd_valid_1;
    bit         dmem_cmd_ready_1;
    wire [ 0:0] dmem_cmd_payload_id_1;
    wire        dmem_cmd_payload_write_1;
    wire [31:0] dmem_cmd_payload_address_1;
    wire [31:0] dmem_cmd_payload_data_1;
    wire [ 1:0] dmem_cmd_payload_size_1;
    wire [ 3:0] dmem_cmd_payload_mask_1;
    wire        dmem_cmd_payload_io_1;
    wire        dmem_cmd_payload_fromHart_1;
    wire [15:0] dmem_cmd_payload_uopId_1;
    bit         dmem_rsp_valid_1;
    bit  [ 0:0] dmem_rsp_payload_id_1;
    bit         dmem_rsp_payload_error_1;
    bit  [31:0] dmem_rsp_payload_data_1;

    /*verilator tracing_off*/
    VexiiRiscv vexii1 (
        .PrivilegedPlugin_logic_rdtime(0),
        .PrivilegedPlugin_logic_harts_0_int_m_timer(0),
        .PrivilegedPlugin_logic_harts_0_int_m_software(0),
        .PrivilegedPlugin_logic_harts_0_int_m_external(0),
        .FetchCachelessPlugin_logic_bus_cmd_valid(imem_cmd_valid_1),
        .FetchCachelessPlugin_logic_bus_cmd_ready(imem_cmd_ready_1),
        .FetchCachelessPlugin_logic_bus_cmd_payload_id(imem_cmd_payload_id_1),
        .FetchCachelessPlugin_logic_bus_cmd_payload_address(imem_cmd_payload_address_1),
        .FetchCachelessPlugin_logic_bus_rsp_valid(imem_rsp_valid_1),
        .FetchCachelessPlugin_logic_bus_rsp_payload_id(imem_rsp_payload_id_1),
        .FetchCachelessPlugin_logic_bus_rsp_payload_error(imem_rsp_payload_error_1),
        .FetchCachelessPlugin_logic_bus_rsp_payload_word(imem_rsp_payload_word_1),
        .LsuCachelessPlugin_logic_bus_cmd_valid(dmem_cmd_valid_1),
        .LsuCachelessPlugin_logic_bus_cmd_ready(dmem_cmd_ready_1),
        .LsuCachelessPlugin_logic_bus_cmd_payload_id(dmem_cmd_payload_id_1),
        .LsuCachelessPlugin_logic_bus_cmd_payload_write(dmem_cmd_payload_write_1),
        .LsuCachelessPlugin_logic_bus_cmd_payload_address(dmem_cmd_payload_address_1),
        .LsuCachelessPlugin_logic_bus_cmd_payload_data(dmem_cmd_payload_data_1),
        .LsuCachelessPlugin_logic_bus_cmd_payload_size(dmem_cmd_payload_size_1),
        .LsuCachelessPlugin_logic_bus_cmd_payload_mask(dmem_cmd_payload_mask_1),
        .LsuCachelessPlugin_logic_bus_cmd_payload_io(dmem_cmd_payload_io_1),
        .LsuCachelessPlugin_logic_bus_cmd_payload_fromHart(dmem_cmd_payload_fromHart_1),
        .LsuCachelessPlugin_logic_bus_cmd_payload_uopId(dmem_cmd_payload_uopId_1),
        .LsuCachelessPlugin_logic_bus_rsp_valid(dmem_rsp_valid_1),
        .LsuCachelessPlugin_logic_bus_rsp_payload_id(dmem_rsp_payload_id_1),
        .LsuCachelessPlugin_logic_bus_rsp_payload_error(dmem_rsp_payload_error_1),
        .LsuCachelessPlugin_logic_bus_rsp_payload_data(dmem_rsp_payload_data_1),
        .clk(clk_mpeg),
        .reset(reset_dsp_enabled_clk_mpeg)
    );
    /*verilator tracing_on*/

    wire [31:0] shared_out_1[3];

    macroblock_worker #(
        .unit_index(0)
    ) worker2 (
        .clk_mpeg,
        .reset_dsp_enabled_clk_mpeg,

        .dmem_cmd_valid_1,
        .dmem_cmd_ready_1(dmem_cmd_ready_1),
        .dmem_cmd_payload_address_1,
        .dmem_cmd_payload_data_1,
        .dmem_cmd_payload_mask_1,
        .dmem_cmd_payload_write_1,

        .shared12_out_1(shared_out_1[0]),

        .ddrif(worker_2_ddr)
    );

    macroblock_worker #(
        .unit_index(1)
    ) worker3 (
        .clk_mpeg,
        .reset_dsp_enabled_clk_mpeg,

        .dmem_cmd_valid_1,
        .dmem_cmd_ready_1(dmem_cmd_ready_1),
        .dmem_cmd_payload_address_1,
        .dmem_cmd_payload_data_1,
        .dmem_cmd_payload_mask_1,
        .dmem_cmd_payload_write_1,

        .shared12_out_1(shared_out_1[1]),

        .ddrif(worker_3_ddr)
    );

    macroblock_worker #(
        .unit_index(2)
    ) worker4 (
        .clk_mpeg,
        .reset_dsp_enabled_clk_mpeg,

        .dmem_cmd_valid_1,
        .dmem_cmd_ready_1(dmem_cmd_ready_1),
        .dmem_cmd_payload_address_1,
        .dmem_cmd_payload_data_1,
        .dmem_cmd_payload_mask_1,
        .dmem_cmd_payload_write_1,

        .shared12_out_1(shared_out_1[2]),

        .ddrif(worker_4_ddr)
    );


    /*verilator tracing_on*/
    bit [31:0] frame_struct_adr  /*verilator public_flat_rd*/;
    bit [31:0] frame_y_adr  /*verilator public_flat_rd*/;
    wire expose_frame_struct_adr_clk_mpeg  = (dmem_cmd_payload_address_1 == 32'h10000010 && dmem_cmd_payload_write_1 && dmem_cmd_valid_1) ;
    wire expose_frame_y_adr_clk_mpeg  = (dmem_cmd_payload_address_1 == 32'h10000018 && dmem_cmd_payload_write_1 && dmem_cmd_valid_1) ;

    // Frame was decoded. This doesn't mean it was commited to the output FIFO yet
    bit event_frame_decoded_clk_mpeg;

    wire playback_active_clkddr;

    bit [31:0] soft_state1  /*verilator public_flat_rd*/ = 0;
    bit [31:0] debug_out  /*verilator public_flat_rd*/ = 0;

    wire expose_frame_struct_adr  /*verilator public_flat_rd*/;
    wire expose_frame_y_adr  /*verilator public_flat_rd*/;

    flag_cross_domain cross_event_sequence_end (
        .clk_a(clk_mpeg),
        .clk_b(clk30),
        .flag_in_clk_a(event_sequence_end_clk_mpeg),
        .flag_out_clk_b(event_sequence_end)
    );

    flag_cross_domain cross_event_frame_decoded (
        .clk_a(clk_mpeg),
        .clk_b(clk30),
        .flag_in_clk_a(event_frame_decoded_clk_mpeg),
        .flag_out_clk_b(event_frame_decoded)
    );

    flag_cross_domain cross_expose_frame_struct_adr (
        .clk_a(clk_mpeg),
        .clk_b(clk30),
        .flag_in_clk_a(expose_frame_struct_adr_clk_mpeg),
        .flag_out_clk_b(expose_frame_struct_adr)
    );

    flag_cross_domain cross_expose_frame_y_adr (
        .clk_a(clk_mpeg),
        .clk_b(clk30),
        .flag_in_clk_a(expose_frame_y_adr_clk_mpeg),
        .flag_out_clk_b(expose_frame_y_adr)
    );

    signal_cross_domain cross_playback_active (
        .clk_a(clk30),
        .clk_b(clk_mpeg),
        .signal_in_clk_a(playback_active),
        .signal_out_clk_b(playback_active_clkddr)
    );

    always_ff @(posedge clk_mpeg) begin
        if (expose_frame_struct_adr_clk_mpeg) begin
            frame_struct_adr <= dmem_cmd_payload_data_1;
        end
        if (expose_frame_y_adr_clk_mpeg) frame_y_adr <= dmem_cmd_payload_data_1;
    end

    always_comb begin
        imem_cmd_ready_1 = 1;
        imem_rsp_payload_word_1 = memory_out_i1;

        dmem_cmd_ready_1 = hw_read_count == 0;
        dmem_rsp_payload_data_1 = reverse_endian_32(mpeg_in_fifo_out);

        if (dmem_cmd_valid_1_q && dmem_cmd_ready_1_q) begin
            case (dmem_cmd_payload_address_1_q[31:28])
                4'd4: begin  // Shared SRAM region
                    dmem_rsp_payload_data_1 = shared_out_1[dmem_cmd_payload_address_1_q[25:24]];
                end
                4'd1: begin
                    // I/O Area
                    if (!dmem_cmd_payload_write_1_q) begin
                        if (dmem_cmd_payload_address_1_q == 32'h10002000)
                            dmem_rsp_payload_data_1 = {3'b000, mpeg_stream_fifo_write_adr_clk_mpeg};
                        if (dmem_cmd_payload_address_1_q == 32'h10002004)
                            dmem_rsp_payload_data_1 = mpeg_stream_bit_index;
                        if (dmem_cmd_payload_address_1_q == 32'h10002008)
                            dmem_rsp_payload_data_1 = hw_read_result;
                        if (dmem_cmd_payload_address_1_q == 32'h1000200c)
                            dmem_rsp_payload_data_1 = {16'b0, dct_coeff_result};
                        if (dmem_cmd_payload_address_1_q == 32'h10002010)
                            dmem_rsp_payload_data_1 = {31'b0, has_sequence_header};

                        if (dmem_cmd_payload_address_1_q == 32'h10003028)
                            dmem_rsp_payload_data_1 = {27'b0, pictures_in_output_fifo_clk_mpeg};
                        if (dmem_cmd_payload_address_1_q == 32'h1000302c)
                            dmem_rsp_payload_data_1 = {31'b0, playback_active_clkddr};
                        if (dmem_cmd_payload_address_1_q == 32'h1000303c)
                            dmem_rsp_payload_data_1 = {29'b0, slow_motion_clkddr};

                    end
                end
                4'd0: begin
                    dmem_rsp_payload_data_1 = memory_out_d1;
                end
                default: begin
                    // Assign the rest of the memory to the MPEG FIFO to fake a real big file
                    dmem_rsp_payload_data_1 = reverse_endian_32(mpeg_in_fifo_out);
                end
            endcase
        end
    end

    planar_yuv_s just_decoded;
    bit [10:0] decoder_width_clk_mpeg = 0;
    bit [8:0] decoder_height_clk_mpeg = 0;
    bit [15:0] decoder_frameperiod_90khz_clk_mpeg;
    bit [7:0] decoder_frameperiod_rawhdr_clk_mpeg;
    bit [31:0] decoder_timecode_clk_mpeg;

    bit [31:0] dmem_cmd_payload_address_1_q;
    bit dmem_cmd_valid_1_q;
    bit dmem_cmd_ready_1_q;
    bit dmem_cmd_payload_write_1_q;

    always_ff @(posedge clk_mpeg) begin
        imem_rsp_valid_1 <= 0;
        dmem_rsp_valid_1 <= 0;

        dmem_cmd_payload_address_1_q <= dmem_cmd_payload_address_1;
        dmem_cmd_valid_1_q <= dmem_cmd_valid_1;
        dmem_cmd_ready_1_q <= dmem_cmd_ready_1;
        dmem_cmd_payload_write_1_q <= dmem_cmd_payload_write_1;

        event_sequence_end_clk_mpeg <= 0;
        event_frame_decoded_clk_mpeg <= 0;

        if (dmem_cmd_payload_address_1 == 32'h1000000c && dmem_cmd_payload_write_1 && dmem_cmd_valid_1 && dmem_cmd_ready_1)begin
            $display("Core 1 stopped at %x with code %x", imem_cmd_payload_address_1,
                     dmem_cmd_payload_data_1);
            $finish();
        end
        if (dmem_cmd_payload_address_1 == 32'h10000030 && dmem_cmd_payload_write_1 && dmem_cmd_valid_1 && dmem_cmd_ready_1)
            soft_state1 <= dmem_cmd_payload_data_1;

        if (dmem_cmd_payload_address_1 == 32'h10000000 && dmem_cmd_valid_1 && dmem_cmd_payload_write_1 && dmem_cmd_ready_1)
        begin
            $display("Debug out %x", dmem_cmd_payload_data_1);
            debug_out <= dmem_cmd_payload_data_1;
        end

        // Core 1 memory access
        if (dmem_cmd_valid_1 && dmem_cmd_ready_1) begin
            dmem_rsp_payload_id_1 <= dmem_cmd_payload_id_1;
            dmem_rsp_valid_1 <= 1;

            case (dmem_cmd_payload_address_1[31:28])
                4'd4: begin  // Shared SRAM region
                end
                4'd1: begin

                    if (dmem_cmd_payload_write_1) begin
                        if (dmem_cmd_payload_address_1[15:0] == 16'h3000)
                            just_decoded.y_adr <= dmem_cmd_payload_data_1[28:0];
                        if (dmem_cmd_payload_address_1[15:0] == 16'h3004)
                            just_decoded.u_adr <= dmem_cmd_payload_data_1[28:0];
                        if (dmem_cmd_payload_address_1[15:0] == 16'h3008)
                            just_decoded.v_adr <= dmem_cmd_payload_data_1[28:0];

                        if (dmem_cmd_payload_address_1[15:0] == 16'h300c) begin
                            just_decoded.width <= dmem_cmd_payload_data_1[10:0];
                            decoder_width_clk_mpeg <= dmem_cmd_payload_data_1[10:0];
                        end
                        if (dmem_cmd_payload_address_1[15:0] == 16'h3010) begin
                            just_decoded.height <= dmem_cmd_payload_data_1[8:0];
                            decoder_height_clk_mpeg <= dmem_cmd_payload_data_1[8:0];
                        end
                        if (dmem_cmd_payload_address_1[15:0] == 16'h3014)
                            frame_period_clk_mpeg <= dmem_cmd_payload_data_1[23:0];
                        if (dmem_cmd_payload_address_1[15:0] == 16'h301c)
                            event_sequence_end_clk_mpeg <= 1;
                        if (dmem_cmd_payload_address_1[15:0] == 16'h3020)
                            just_decoded.first_intra_frame_of_gop <= dmem_cmd_payload_data_1[0];
                        if (dmem_cmd_payload_address_1[15:0] == 16'h3030) begin
                            just_decoded.frameperiod_rawhdr <= dmem_cmd_payload_data_1[7:0];
                            decoder_frameperiod_rawhdr_clk_mpeg <= dmem_cmd_payload_data_1[7:0];
                        end
                        if (dmem_cmd_payload_address_1[15:0] == 16'h3034)
                            decoder_frameperiod_90khz_clk_mpeg <= dmem_cmd_payload_data_1[15:0];
                        if (dmem_cmd_payload_address_1[15:0] == 16'h3038) begin
                            just_decoded.video_status <= dmem_cmd_payload_data_1[7:0];
                            $display("FMV video_status %d %d", dmem_cmd_payload_data_1[31:2],
                                     dmem_cmd_payload_data_1[1:0]);
                        end
                        if (dmem_cmd_payload_address_1[15:0] == 16'h3044) begin
                            just_decoded.timecode <= dmem_cmd_payload_data_1;
                            decoder_timecode_clk_mpeg <= dmem_cmd_payload_data_1;
                            $display("FMV timecode %x", dmem_cmd_payload_data_1);
                        end
                        if (dmem_cmd_payload_address_1[15:0] == 16'h3048) begin
                            just_decoded.first_intra_frame_of_seq <= dmem_cmd_payload_data_1[0];
                        end

                        if (dmem_cmd_payload_address_1[15:0] == 16'h3050)
                            event_frame_decoded_clk_mpeg <= 1;
                        if (dmem_cmd_payload_address_1[15:0] == 16'h3054)
                            just_decoded.luma_width <= dmem_cmd_payload_data_1[10:0];
                        if (dmem_cmd_payload_address_1[15:0] == 16'h3058)
                            just_decoded.chroma_width <= dmem_cmd_payload_data_1[9:0];

                        if (dmem_cmd_payload_address_1[15:0] == 16'h2010) begin
                            has_sequence_header <= dmem_cmd_payload_data_1[0];
                            $display("FMV has_sequence_header %d", dmem_cmd_payload_data_1[0]);
                        end

                    end
                end
                4'd0: begin
                end
                default: ;
            endcase
        end

        // Instruction fetch logic for core 1
        if (imem_cmd_valid_1) begin
            imem_rsp_valid_1 <= 1;
            imem_rsp_payload_id_1 <= imem_cmd_payload_id_1;
        end

        if (reset_persistent_storage_clk_mpeg) begin
            has_sequence_header <= 0;
        end
    end

    planar_yuv_s for_display;

    // Flag when a frame has left the decoder and entered the output FIFO for display
    wire just_decoded_commit = dmem_cmd_payload_write_1 && dmem_cmd_valid_1 && dmem_cmd_ready_1 && dmem_cmd_payload_address_1==32'h10003040;
    wire for_display_valid_clk_mpeg;
    bit latch_frame_for_display;
    wire latch_frame_for_display_clk_mpeg;
    bit event_sequence_end_clk_mpeg;

    // 30 MHz clock rate and 25 Hz frame rate -> 1200000
    bit [8:0] fractional_pixel_width_clk_mpeg;

    // 24 bits are required.
    // Slow motion can be factor 2-8, slowest allowed period without
    // that factor is 1251251 which requires 21 bits
    bit [23:0] frame_period_clk_mpeg = 1200000;
    bit [23:0] frame_period = 1200000;
    bit [23:0] playback_frame_cnt;

    bit latch_frame_until_vblank = 0;
    bit latch_frame_until_vsync = 0;
    bit first_intra_frame_of_gop_clk30;
    bit first_intra_frame_of_seq_clk30;

    bit vsync_q;
    bit hsync_q;
    bit vblank_q1;
    bit vblank_q2;
    bit for_display_valid;

    wire just_decoded_commit_clk30;

    // frame info are set very infrequently.
    // just_decoded_commit is set for one clk_mpeg tick to indicate change
    // just_decoded_commit_clk30 is this flag moved over to the clk30 domain
    // When just_decoded_commit_clk30 is high, the stability of all frame info is assumed
    flag_cross_domain cross_just_decoded_commit (
        .clk_a(clk_mpeg),
        .clk_b(clk30),
        .flag_in_clk_a(just_decoded_commit),
        .flag_out_clk_b(just_decoded_commit_clk30)
    );

    bit single_step_latch;
    bit frame_period_tick;

    // 24' is required to fix math problem on Verilator
    bit [23:0] frame_period_top;

    // Min period was confirmed by resuming with Continue command
    // Addams Family /cd/seq2.rtf seek 0x08d65800
    // Lost Ride     /cd/ma       seek 0x03520800
    // VMPEG had the same speed to fast forward
    wire [23:0] frame_period_min = frame_period - frame_period / 8;
    wire [23:0] frame_period_max = frame_period + frame_period / 8;

    always_comb begin
        frame_period_top = frame_period - 1 - (24'(display_dts_desync_q) * 2048);

        if (frame_period_top < frame_period_min || totally_out_of_sync_need_frameskip) begin
            frame_period_top = frame_period_min;
        end else if (frame_period_top > frame_period_max) begin
            frame_period_top = frame_period_max;
        end
    end


    // Initial DTS near SCR. Playback is allowed
    bit display_dts_desync_satisfied_latch = 0;

    always_ff @(posedge clk30) begin
        vsync_q <= vsync;
        hsync_q <= hsync;
        vblank_q1 <= vblank;
        vblank_q2 <= vblank_q1;
        frame_period_tick <= 0;

        if (reset_dsp_enabled) begin
            single_step_latch <= 0;
            latch_frame_until_vsync <= 0;
        end else if (single_step) begin
            single_step_latch <= 1;
        end

        for_display_valid <= for_display_valid_clk_mpeg;

        event_picture_starts_display <= 0;
        event_first_intra_frame_gop_starts_display <= 0;
        event_first_intra_frame_seq_starts_display <= 0;
        event_last_picture_starts_display <= 0;

        event_potential_picture_starts_display <= 0;

        if (latch_frame_for_display) begin
            latch_frame_for_display <= 0;
            display_video_status <= for_display.video_status;
            display_timecode <= for_display.timecode;
            display_frameperiod_rawhdr <= for_display.frameperiod_rawhdr;
            display_width <= for_display.width;
            display_height <= for_display.height;
            first_intra_frame_of_gop_clk30 <= for_display.first_intra_frame_of_gop;
            first_intra_frame_of_seq_clk30 <= for_display.first_intra_frame_of_seq;
        end

        if (just_decoded_commit_clk30) begin

        end

        if (event_frame_decoded) begin
            frame_period <= frame_period_clk_mpeg;
            decoder_frameperiod_90khz <= decoder_frameperiod_90khz_clk_mpeg;
            decoder_frameperiod_rawhdr <= decoder_frameperiod_rawhdr_clk_mpeg;
            decoder_width <= decoder_width_clk_mpeg;
            decoder_height <= decoder_height_clk_mpeg;
            decoder_timecode <= decoder_timecode_clk_mpeg;
        end

        if (!dsp_enable) begin
            display_video_status <= 0;
            display_timecode <= 0;
            decoder_timecode <= 0;
            decoder_frameperiod_90khz <= 0;
            decoder_frameperiod_rawhdr <= 0;
        end

        if (latch_frame_until_vblank && !vblank && vblank_q1 && vblank_q2) begin
            latch_frame_until_vblank <= 0;
            event_picture_starts_display <= 1;
            event_first_intra_frame_gop_starts_display <= first_intra_frame_of_gop_clk30;
            event_first_intra_frame_seq_starts_display <= first_intra_frame_of_seq_clk30;
            event_last_picture_starts_display <= !for_display_valid && pictures_in_mpeg_decoder==0;
        end

        if (latch_frame_until_vsync && !vsync && vsync_q) begin
            latch_frame_until_vsync <= 0;
            event_potential_picture_starts_display <= 1;

            if (for_display_valid) begin
                latch_frame_for_display  <= 1;
                latch_frame_until_vblank <= 1;
            end
        end

        if (playback_active) begin
            // Start playback only when we are near the next valid DTS 
            if (!dts_fifo_out_valid_dts || (dts_fifo_out_valid_dts && display_dts_desync > -30)) begin
                display_dts_desync_satisfied_latch <= 1;
            end

            // Always increment frame count during asynchronous mode
            // Always increment frame count when no DTS is available
            // Only increment frame count during synchronous mode, when initial DTS check was fulfilled
            if (!synchronous_playback || display_dts_desync_satisfied_latch)
                playback_frame_cnt <= playback_frame_cnt + 1;

            // Timed latching of frames
            if (playback_frame_cnt >= frame_period_top) begin
                playback_frame_cnt <= 0;

                // TODO Why Check for a frame period again? Why should it bit that low?
                // It doesn't hurt to check though...
                if (frame_period > 1200) begin
                    latch_frame_until_vsync <= 1;
                    frame_period_tick <= for_display_valid;
                end
            end
        end else begin
            display_dts_desync_satisfied_latch <= 0;
            playback_frame_cnt <= 0;
        end

        if (single_step_latch && for_display_valid && !vsync && vsync_q) begin
            single_step_latch <= 0;
            latch_frame_until_vsync <= 1;
        end
    end

    flag_cross_domain cross_latch_frame (
        .clk_a(clk30),
        .clk_b(clk_mpeg),
        .flag_in_clk_a(latch_frame_for_display),
        .flag_out_clk_b(latch_frame_for_display_clk_mpeg)
    );

    wire [4:0] pictures_in_output_fifo_clk_mpeg  /*verilator public_flat_rd*/;
    wire [4:0] pictures_in_output_fifo_clk_mpeg_gray_d;
    bit  [4:0] pictures_in_output_fifo_clk_mpeg_gray_q;
    bit  [4:0] pictures_in_output_fifo_clk30_gray;
    b2g_converter #(
        .WIDTH(5)
    ) pictures_in_output_fifo_b2g (
        .binary(pictures_in_output_fifo_clk_mpeg),
        .gray  (pictures_in_output_fifo_clk_mpeg_gray_d)
    );
    always_ff @(posedge clk_mpeg)
        pictures_in_output_fifo_clk_mpeg_gray_q <= pictures_in_output_fifo_clk_mpeg_gray_d;
    always_ff @(posedge clk30)
        pictures_in_output_fifo_clk30_gray <= pictures_in_output_fifo_clk_mpeg_gray_q;
    g2b_converter #(
        .WIDTH(5)
    ) pictures_in_output_fifo_g2b (
        .binary(pictures_in_output_fifo),
        .gray  (pictures_in_output_fifo_clk30_gray)
    );

    wire show_on_next_video_frame_clkddr;
    signal_cross_domain cross_vshow_on_next_video_frame (
        .clk_a(clk30),
        .clk_b(clk_mpeg),
        .signal_in_clk_a(show_on_next_video_frame),
        .signal_out_clk_b(show_on_next_video_frame_clkddr)
    );

    yuv_frame_adr_fifo readyframes (
        .clk(clk_mpeg),
        .reset(reset_dsp_enabled_clk_mpeg),
        .wdata(just_decoded),
        .we(just_decoded_commit),
        .strobe(latch_frame_for_display_clk_mpeg),
        .valid(for_display_valid_clk_mpeg),
        .q(for_display),
        .cnt(pictures_in_output_fifo_clk_mpeg)
    );

    frameplayer frameplayer (
        .clkvideo(clk30),
        .clkddr(clk_mpeg),
        .reset,
        .ddrif(player_ddr),
        .vidout,
        .vcd_pixel_clock,
        .debug_activate_vcd_filter,
        .hsync,
        .vsync,
        .hblank,
        .vblank,
        .frame(for_display),
        .frame_width(window_width),
        .frame_height(window_height),
        .offset_y(display_offset_y),
        .offset_x(display_offset_x),
        .window_y(window_offset_y),
        .window_x(window_offset_x),
        .latch_frame_clkvideo(latch_frame_for_display),
        .latch_frame_clkddr(latch_frame_for_display_clk_mpeg),
        .invalidate_latched_frame(reset_persistent_storage_clk_mpeg),
        .show_on_next_video_frame(show_on_next_video_frame_clkddr)
    );
endmodule
