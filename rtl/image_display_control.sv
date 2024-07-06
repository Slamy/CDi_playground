// Info from Chapter 5 - Image Display Control (MCD212)

module video_timing (
    input sm,  // scan mode, 1 == interlaced
    input cf,  // crystal, 1 = 28 MHz for monitors, 0 = 30 MHz for TV
    input st,  // standard
    input cm,  // color mode
    input fd,  // frame duration
    output bit [8:0] video_y,
    output bit [12:0] video_x
);


    // according to Table 5-6
    bit [8:0] h_total;  // A in datasheet
    bit [8:0] h_active;  // B in datashheet
    bit [8:0] h_start;  // C in datasheet

    bit [8:0] v_total;  // J in datasheet
    bit [8:0] v_active;  // K in datasheet
    bit [8:0] v_sync;  // P in datasheet
    bit [8:0] v_start;  // L in datasheet
    bit [8:0] v_front_porch;  // M in datasheet

    localparam bit [22:0] ica_start = 23'h400;

    always_comb begin
        if (fd) begin
            v_total = 262;
            v_active = 240;
            v_start = 18;
            v_front_porch = 4;
        end else if (st) begin
            v_total = 312;
            v_active = 240;
            v_start = 46;
            v_front_porch = 26;
        end else begin
            v_total = 312;
            v_active = 280;
            v_start = 26;
            v_front_porch = 6;
        end
    end

    always_ff @(posedge clk) begin
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


    bit [31:0] instruction;
    always_ff @(posedge clk) begin
        case (instruction[31:28])
            0: begin
                // stop until next field
            end
            1: begin
                // no operation
            end
            2: begin
                // reload dcp
            end
            3: begin
                // reload dcp and stop
            end
            4: begin
                // reload ica pointer
            end
            5: begin
                // reload vsr pointer and stop
            end
            6: begin
                // interrupt
            end
            7: begin
                // reload display parameters
            end

        endcase

    end

endmodule
