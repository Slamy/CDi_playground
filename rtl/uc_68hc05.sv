// 68HC05 Microcontroller
// Uses naked 6805 core and attaches peripherals to it
// Used core is https://opencores.org/projects/68hc05 which only implements basic functionality
// and no peripherals

module uc68hc05 (
    input clk,
    input reset,
    input [7:0] porta_in,
    output bit [7:0] porta_out,
    input [7:0] portb_in,
    output bit [7:0] portb_out,
    input [7:0] portc_in,
    output bit [7:0] portc_out,
    input [7:0] portd_in,
    input irq,
    output bit [7:0] ddra,
    output bit [7:0] ddrb,
    output bit [7:0] ddrc
);

    bit [7:0] datain;
    bit [7:0] memory_readout = 0;

    wire [15:0] addr;
    bit [15:0] lastaddr;
    wire wr;
    wire [3:0] state;
    wire [7:0] dataout;

    bit fail = 0;
    bit [7:0] memory[8192];
`ifdef VERILATOR
    initial begin
        $readmemh("slave.mem", memory);
    end
`endif

    // Readback of PORTx registers depend on DDRx
    // With a pin being 1, provided the output value
    // With a pin being 0, provide the input when read
    wire [7:0] porta_mix;
    wire [7:0] portb_mix;
    wire [7:0] portc_mix;


    genvar i;
    generate
        for (i = 0; i < 8; i++) begin : ports
            assign porta_mix[i] = ddra[i] ? porta_out[i] : porta_in[i];
            assign portb_mix[i] = ddrb[i] ? portb_out[i] : portb_in[i];
            assign portc_mix[i] = ddrc[i] ? portc_out[i] : portc_in[i];
        end
    endgenerate
    // lower 2 bit are invisible
    bit [17:0] free_running_counter = 0;
    bit [7:0] latched_counter = 0;
    bit timerirq = 0;
    bit [7:0] serial_periph_miso_data = 0;

    bit spi_transfer_complete = 0;
    bit [15:0] output_capture = 0;

    struct packed {
        bit input_capture_interrupt_enable;
        bit output_capture_interrupt_enable;
        bit timer_overflow_interrupt_enable;
        bit [2:0] reserved;
        bit input_capture_edge_select;
        bit output_compare_output_level;
    } timer_control_register;

    struct packed {
        bit input_capture_flag;
        bit output_compare_flag;
        bit timer_overflow_flag;
        bit [4:0] reserved;
    } timer_status_register;

    always @(posedge clk) begin
        if (!wr) memory[addr[12:0]] <= dataout;
        else memory_readout <= memory[addr[12:0]];
    end

    always_comb begin
        datain = memory_readout;
        case (addr)
            16'h0000: begin
                datain = porta_mix;
                // $display("PORTA %x %d %x", dataout, wr, porta_mix);
            end
            16'h0001: begin
                datain = portb_mix;
                // $display("PORTB %x %d %x", dataout, wr, portb_mix);
            end
            16'h0002: begin
                datain = portc_mix;
                // $display("PORTC %x %d %x", dataout, wr, portc_mix);
            end
            16'h0003: begin
                // Only input for PORTD
                datain = portd_in;
                // $display("PORTD %x %d %x", dataout, wr, portd_in);
            end
            16'h0004: begin
                datain = ddra;
                // $display("DDRA %x %d", dataout, wr);
            end
            16'h0005: begin
                datain = ddrb;
                // $display("DDRB %x %d", dataout, wr);
            end
            16'h0006: begin
                datain = ddrc;
                // $display("DDRC %x %d", dataout, wr);
            end
            16'h000b: begin

                datain[6:0] = 0;
                datain[7]   = spi_transfer_complete;
            end

            16'h000c: begin
                datain = serial_periph_miso_data;
            end

            16'h0010: begin
                //$display("SERIAL COM STATUS %x %d", dataout, wr);
                datain = 8'b11000000;
            end

            16'h0013: begin
                //$display("TIMER STATUS %x %x", dataout, wr);
                datain = timer_status_register;
            end

            16'h001a: begin
                // Alternate counter High
                datain = free_running_counter[17:10];
            end
            16'h001b: begin
                datain = latched_counter;
            end
            16'h0057: begin  // TODO Patch to avoid SPI access as slave is missing
                datain = 8'hff;
            end
            16'h0099: begin  // TODO Patch to set fixed version when asked
                datain = 8'hf0;
            end
            default: begin  // do nothing
            end
        endcase
    end
    always @(posedge clk) begin
        lastaddr <= addr;

        free_running_counter <= free_running_counter + 1;

        if (free_running_counter[17:2] == output_capture && free_running_counter[1:0] == 0) begin
            timer_status_register.output_compare_flag <= 1;
            if (timer_control_register.output_capture_interrupt_enable) timerirq <= 1;
        end else timerirq <= 0;


        // only print. no affect
        case (addr)
            16'h000a: $display("SERIAL PERIPH CONTROL %x %x", dataout, wr);
            16'h000d: $display("SERIAL COM BAUD %x %x", dataout, wr);
            16'h000e: $display("SERIAL COM CONTROL1 %x %x", dataout, wr);
            16'h000f: $display("SERIAL COM CONTROL2 %x %x", dataout, wr);
            16'h0011: $display("SERIAL COM DATA %x %x", dataout, wr);
            16'h0012: begin
                // $display("TIMER CONTROL %x %x", dataout, wr);
                if (!wr) timer_control_register <= dataout;
            end
            16'h0014: $display("INPUT CAPTURE H %x %x", dataout, wr);
            16'h0015: $display("INPUT CAPTURE L %x %x", dataout, wr);
            16'h0016: begin
                //$display("OUTPUT CAPTURE H %x %x", dataout, wr);
                if (!wr) output_capture[15:8] <= dataout;
            end
            16'h0017: begin
                //$display("OUTPUT CAPTURE L %x %x", dataout, wr);
                if (!wr) begin
                    output_capture[7:0] <= dataout;
                    // TODO this is not correct. but might work anyway...
                    timer_status_register.output_compare_flag <= 0;
                end
            end
            16'h0018: $display("TIMER MSB %x %x", dataout, wr);
            16'h0019: $display("TIMER LSB %x %x", dataout, wr);
            default:  ;
        endcase

        case (addr)
            16'h0000: begin
                if (!wr) porta_out <= dataout;
                // $display("PORTA %x %d %x", dataout, wr, porta_mix);
            end
            16'h0001: begin
                if (!wr) portb_out <= dataout;
                // $display("PORTB %x %d %x", dataout, wr, portb_mix);
            end
            16'h0002: begin
                if (!wr) portc_out <= dataout;
                // $display("PORTC %x %d %x", dataout, wr, portc_mix);
            end
            16'h0003: begin
                // Only input for PORTD
                // $display("PORTD %x %d %x", dataout, wr, portd_in);
            end
            16'h0004: begin
                if (!wr) ddra <= dataout;
                // $display("DDRA %x %d", dataout, wr);
            end
            16'h0005: begin
                if (!wr) ddrb <= dataout;
                // $display("DDRB %x %d", dataout, wr);
            end
            16'h0006: begin
                if (!wr) ddrc <= dataout;
                // $display("DDRC %x %d", dataout, wr);
            end
            16'h000b: begin
                $display("SERIAL PERIPH STATUS %x %x %x %x", dataout, wr, spi_transfer_complete,
                         lastaddr);

            end

            16'h000c: begin
                $display("SERIAL PERIPH DATA %x %x %x", dataout, wr, serial_periph_miso_data);

                if (!wr) begin
                    spi_transfer_complete <= 1;
                    if (dataout == 8'hdd) serial_periph_miso_data <= 8'hee;
                end  //else spi_transfer_complete <= 0;
            end

            16'h0010: begin
                //$display("SERIAL COM STATUS %x %d", dataout, wr);
            end

            16'h0013: begin
                //$display("TIMER STATUS %x %x", dataout, wr);
            end

            16'h001a: begin
                // Alternate counter High
                latched_counter <= free_running_counter[9:2];
            end
            16'h001b: begin
            end
            16'h0057: begin  // TODO Patch to avoid SPI access as slave is missing
            end
            16'h0099: begin  // TODO Patch to set fixed version when asked
            end
            default: begin
                // The rest is just RAM and ROM
                if (addr[15:13] != 0) fail <= 1;
            end
        endcase

    end


    UR6805 slave_core (
        .clk(!clk),
        .rst(!reset),
        .extirq(irq),
        .timerirq(timerirq),
        .datain(datain),
        .addr(addr),
        .wr(wr),
        .state(state),
        .dataout(dataout)
    );

endmodule
