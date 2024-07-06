`timescale 1 ns / 1 ns

module fx68k_tb;
    bit clk  /*verilator public_flat_rw*/;
    bit reset = 1;  // External sync reset on emulated system

    wire write_strobe;
    wire as;
    wire lds;
    wire uds;

    bit bus_ack;

    bit [15:0] data_in;
    wire [15:0] cpu_data_out;
    wire [23:1] addr;
    wire [23:0] addr_byte = {addr[23:1], 1'b0};

    // 512 kB of ROM
    bit [15:0] rom[262144]  /*verilator public_flat_rw*/;

    // 8 kB of NVRAM
    bit [7:0] nvram[8192]  /*verilator public_flat_rw*/;

    initial begin
        $readmemh("cdi200.mem", rom);
    end

    wire mcd212_bus_ack;
    wire [15:0] mcd212_dout;
    wire [15:0] cdic_dout;
    wire csrom;

    wire attex_cs_mcd212 = ((addr_byte <= 24'h27ffff) || (addr_byte >= 24'h400000)) && as && !addr[23];
    wire attex_cs_cdic = addr_byte[23:16] == 8'h30;
    wire attex_cs_slave = addr_byte[23:16] == 8'h31;
    wire attex_cs_nvram = addr_byte[23:16] == 8'h32;

    bit cs_q = 0;
    bit lds_q = 0;
    bit uds_q = 0;

    bit [15:0] data_in_q = 0;

    bit attex_cs_slave_q = 0;

    wire bus_err_ram_area1 = (addr_byte >= 24'h600000 && addr_byte < 24'hd00000);
    wire bus_err_ram_area2 = (addr_byte >= 24'hf00000);
    wire bus_err = (bus_err_ram_area1 || bus_err_ram_area2) && as && (lds || uds);

    wire trap_addr_error  /*verilator public_flat_rd*/ = scc68070_0.tg68.tg68kdotcinst.trap_addr_error;
    always @(posedge clk) begin
        uds_q <= uds;
        lds_q <= lds;
        data_in_q <= data_in;

        /*
        if (bus_err)
            $display("BUS ERR %x %x %d %d %d", addr_byte, cpu_data_out, lds, uds, write_strobe);

        if (trap_addr_error)
            $display("ADDR ERR %x %x %d %d %d", addr_byte, cpu_data_out, lds, uds, write_strobe);
        */

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
                $display("Read SLAVE %x %x %d %d %d", addr[7:1], data_in_q, lds, uds, write_strobe);

            /*
            if ((lds || uds) && attex_cs_nvram)
                $display(
                    "Access NVRAM %x %x %x %d %d %d",
                    addr[7:1],
                    data_in_q,
                    cpu_data_out,
                    lds,
                    uds,
                    write_strobe
                );
                */
        end
    end


    wire [7:0] r;
    wire [7:0] g;
    wire [7:0] b;
    wire hsync;
    wire vsync;

    mcd212 mcd212_inst (
        .clk,
        .cpu_address(addr[22:1]),
        .cpu_din(cpu_data_out),
        .cpu_dout(mcd212_dout),
        .cpu_bus_ack(mcd212_bus_ack),
        .cpu_uds(uds),
        .cpu_lds(lds),
        .cpu_write_strobe(write_strobe),
        .cs(attex_cs_mcd212),
        .csrom,
        .r,
        .g,
        .b,
        .hsync,
        .vsync
    );

    cdic cdic_inst (
        .clk,
        .address(addr),
        .din(cpu_data_out),
        .dout(cdic_dout),
        .uds(uds),
        .lds(lds),
        .write_strobe(write_strobe),
        .cs(attex_cs_cdic)
    );

    //wire [31:0] d1  /*verilator public_flat_rd*/ = scc68070_0.tg68.tg68kdotcinst.regfile[1];
    //wire [31:0] d0  /*verilator public_flat_rd*/ = scc68070_0.tg68.tg68kdotcinst.regfile[0];

    wire vsdc_intn = 1'b1;
    wire in2in;

    scc68070 scc68070_0 (
        .clk,
        .reset,  // External sync reset on emulated system
        .write_strobe,
        .as,
        .lds,
        .uds,
        .bus_ack,
        .bus_err,
        .int1(!vsdc_intn),
        .int2(1'b0),  // unconnected in CDi MONO1
        .in2(!in2in),
        .in4(1'b0),
        .in5(1'b0),
        .data_in,
        .data_out(cpu_data_out),
        .addr
    );

    bit [19:0] resetcnt  /*verilator public_flat_rw*/ = 0;

    always_ff @(posedge clk) begin
        resetcnt <= resetcnt + 1;
        if (resetcnt[19]) reset <= 0;
        //if (resetcnt[3]) reset <= 0;
    end
    initial begin
        //reset = 1;
    end


    wire [7:0] ddra;
    wire [7:0] ddrb;
    wire [7:0] ddrc;

    wire [7:0] porta_in = cpu_data_out[7:0];
    wire [7:0] porta_out;
    wire [7:0] portb_in = 8'hff;
    wire [7:0] portb_out;
    wire [7:0] portc_in = {6'b111111, addr[2:1]};
    wire [7:0] portc_out;
    wire [7:0] portd_in = {!write_strobe, 7'b1111111};

    bit slave_bus_ack;

    always_comb begin
        bus_ack = 1;
        data_in = 0;

        if (csrom) begin
            data_in = rom[addr[18:1]];
        end else if (attex_cs_slave) begin
            if (porta_out == 8'h01) data_in = 16'h0202;  // TODO Slave antwortet falsch
            else data_in = {porta_out, porta_out};
            bus_ack = slave_bus_ack;

        end else if (attex_cs_cdic) begin
            data_in = cdic_dout;
        end else if (attex_cs_nvram) begin
            data_in = {nvram[addr[13:1]], nvram[addr[13:1]]};
        end else if (attex_cs_mcd212) begin
            data_in = mcd212_dout;
            bus_ack = mcd212_bus_ack;
        end
    end

    // clock for modelsim
    always begin
        #10 clk = !clk;
    end


    always @(posedge clk) begin

        if (attex_cs_nvram) begin
            if (uds && write_strobe) nvram[addr[13:1]] <= cpu_data_out[15:8];
        end
    end

    wire disdat_from_uc = ddrc[3] ? portc_out[3] : 1'b1;
    wire disdat_to_ic;

    wire disdat = disdat_from_uc && disdat_to_ic;
    wire disclk = ddrc[4] ? portc_out[4] : 1'b1;

    wire dtackslaven = ddrb[6] ? portb_out[6] : 1'b1;
    assign in2in = ddrb[5] ? portb_out[5] : 1'b1;

    bit dtackslaven_q = 0;
    bit in2in_q = 1;

    bit slave_irq;
    bit [7:0] irq_cooldown = 0;

    /*
    uc68hc05 uc68hc05_0 (
        .clk,
        .porta_in,
        .porta_out,
        .portb_in,
        .portb_out,
        .portc_in({portc_in[7:5], disclk, disdat_to_ic, portc_in[2:0]}),
        .portc_out,
        .portd_in,
        .irq(!slave_irq),
        .ddra,
        .ddrb,
        .ddrc
    );
*/

    u3090mg u3090mg (
        .clk,
        .sda_in(disdat_from_uc),
        .sda_out(disdat_to_ic),
        .scl(disclk)
    );

    always_comb begin
        slave_bus_ack = dtackslaven && !dtackslaven_q;

        slave_irq = irq_cooldown == 1;
    end
    always_ff @(posedge clk) begin
        attex_cs_slave_q <= attex_cs_slave;
        dtackslaven_q <= dtackslaven;
        in2in_q <= in2in;

        if (!in2in && in2in_q) $display("SLAVE IRQ2 1");
        if (in2in && !in2in_q) $display("SLAVE IRQ2 0");

        if (attex_cs_slave && !attex_cs_slave_q) irq_cooldown <= 20;
        else if (irq_cooldown != 0) irq_cooldown <= irq_cooldown - 1;
    end


endmodule
