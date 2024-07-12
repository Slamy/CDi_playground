// Info from Chapter 5 - Image Display Control (MCD212)

module video_timing (
    input clk,
    input reset,
    input sm,  // scan mode, 1 = interlaced, 0 = non-interlaced
    input cf,  // crystal, 0 = 28 MHz for NTSC monitors, 1 = 30 MHz for TV
    input st,  // standard, 1=360/720 pixels per line, 0=384/768
    input cm,  // color mode, 0 = 4 clocks per pixel, 1 = 2 clocks per pixel
    input fd,  // frame duration, 0=50 Hz, 1=60 Hz
    output bit [8:0] video_y,
    output bit [12:0] video_x,
    output bit hsync,
    output bit vsync,
    output bit hblank,
    output bit vblank,
    output bit new_line,
    output bit new_frame,
    output bit new_pixel
);

    localparam bit [12:0] ClksPerCycle = 16 * 2;

    // horizontal timing according to Table 5-4
    bit [12:0] h_total;  // A in datasheet
    bit [12:0] h_active;  // B in datashheet
    bit [12:0] h_start;  // C in datasheet
    bit [12:0] h_sync;  // E in datasheet

    always_comb begin
        if (st && cf) begin
            h_total  = 120;
            h_active = 90;
            h_start  = 23;
            h_sync   = 9;
        end else if (cf) begin
            h_total  = 120;
            h_active = 96;
            h_start  = 20;
            h_sync   = 9;
        end else begin
            h_total  = 112;
            h_active = 90;
            h_start  = 19;
            h_sync   = 8;
        end

        h_total  = h_total * ClksPerCycle;
        h_active = h_active * ClksPerCycle;
        h_start  = h_start * ClksPerCycle;
        h_sync = h_sync * ClksPerCycle;
    end

    // vertical timing according to Table 5-6
    bit [8:0] v_total;  // J in datasheet
    bit [8:0] v_active;  // K in datasheet
    bit [8:0] v_sync;  // P in datasheet
    bit [8:0] v_start;  // L in datasheet
    bit [8:0] v_front_porch;  // M in datasheet

    always_comb begin
        v_sync = 3;
        if (fd) begin
            // NTSC
            v_total = 262;
            v_active = 240;
            v_start = 18;
            v_front_porch = 4;
        end else if (st) begin
            // PAL with NTSC height
            v_total = 312;
            v_active = 240;
            v_start = 46;
            v_front_porch = 26;
        end else begin
            // PAL full height
            v_total = 312;
            v_active = 280;
            v_start = 26;
            v_front_porch = 6;
        end
    end

    always_ff @(posedge clk) begin
        if (reset) begin
            video_x <= 0;
            video_y <= 0;
        end else begin
            if (video_x == (h_total - 1)) begin  // end of line reached?
                video_x <= 0;
                if (video_y == (v_total - 1)) begin
                    video_y <= 0;
                end else begin
                    video_y <= video_y + 1;
                end
            end else begin
                video_x <= video_x + 1;
            end

        end
    end

    always_ff @(posedge clk) begin
        hsync <= video_x < h_sync;
        vsync <= video_y < v_sync;
        new_frame <= video_x == 0 && video_y == 0;
        new_line <= video_x == 0;
        hblank <= !(video_x >= h_start && video_x < (h_start + h_active));
        vblank <= !(video_y >= v_start && video_y < (v_start + v_active));
        new_pixel <= (cm ? video_x[1:0] == 0 : video_x[2:0] == 0) && !hblank && !vblank;
    end

    int pixels_per_line = 0;
    always_ff @(posedge clk) begin
        if (new_line) begin
            $display(pixels_per_line);
            pixels_per_line <= 0;
        end else if (new_pixel) begin
            pixels_per_line <= pixels_per_line + 1;
        end
    end



endmodule
