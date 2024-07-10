
module cditop
(
	input         clk,
	input         reset,
	
	input         pal,
	input         scandouble,

	output reg    ce_pix,

	output reg    HBlank,
	output reg    HSync,
	output reg    VBlank,
	output reg    VSync,

	output  [7:0] video
);

reg   [9:0] hc;
reg   [9:0] vc;
reg   [9:0] vvc;
reg  [63:0] rnd_reg;

wire  [5:0] rnd_c = {rnd_reg[0],rnd_reg[1],rnd_reg[2],rnd_reg[2],rnd_reg[2],rnd_reg[2]};
wire [63:0] rnd;

lfsr random(rnd);

always @(posedge clk) begin
	if(scandouble) ce_pix <= 1;
		else ce_pix <= ~ce_pix;

	if(reset) begin
		hc <= 0;
		vc <= 0;
	end
	else if(ce_pix) begin
		if(hc == 637) begin
			hc <= 0;
			if(vc == (pal ? (scandouble ? 623 : 311) : (scandouble ? 523 : 261))) begin 
				vc <= 0;
				vvc <= vvc + 9'd6;
			end else begin
				vc <= vc + 1'd1;
			end
		end else begin
			hc <= hc + 1'd1;
		end

		rnd_reg <= rnd;
	end
end

always @(posedge clk) begin
	if (hc == 529) HBlank <= 1;
		else if (hc == 0) HBlank <= 0;

	if (hc == 544) begin
		HSync <= 1;

		if(pal) begin
			if(vc == (scandouble ? 609 : 304)) VSync <= 1;
				else if (vc == (scandouble ? 617 : 308)) VSync <= 0;

			if(vc == (scandouble ? 601 : 300)) VBlank <= 1;
				else if (vc == 0) VBlank <= 0;
		end
		else begin
			if(vc == (scandouble ? 490 : 245)) VSync <= 1;
				else if (vc == (scandouble ? 496 : 248)) VSync <= 0;

			if(vc == (scandouble ? 480 : 240)) VBlank <= 1;
				else if (vc == 0) VBlank <= 0;
		end
	end
	
	if (hc == 590) HSync <= 0;
end

reg  [7:0] cos_out;
wire [5:0] cos_g = cos_out[7:3]+6'd32;
cos cos(vvc + {vc>>scandouble, 2'b00}, cos_out);

assign video = (cos_g >= rnd_c) ? {cos_g - rnd_c, 2'b00} : 8'd0;


    wire write_strobe;
    wire as;
    wire lds;
    wire uds;

    wire bus_ack;

    bit [15:0] data_in;
    wire [15:0] cpu_data_out;
    wire [23:1] addr;
    wire [23:0] addr_byte = {addr[23:1], 1'b0};

    // 512 kB of ROM
    bit [15:0] rom[256]  /*verilator public_flat_rw*/;

    // 8 kB of NVRAM
    bit [7:0] nvram[8192]  /*verilator public_flat_rw*/;

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

    always @(posedge clk) begin
        uds_q <= uds;
        lds_q <= lds;
        data_in_q <= data_in;

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


    mcd212 mcd212_inst (
        .clk,
        .address(addr[22:1]),
        .din(cpu_data_out),
        .dout(mcd212_dout),
        .bus_ack(mcd212_bus_ack),
        .uds(uds),
        .lds(lds),
        .write_strobe(write_strobe),
        .cs(attex_cs_mcd212),
        .csrom
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
        .data_in(data_in),
        .data_out(cpu_data_out),
        .addr
    );

    bit [7:0] ddra;
    bit [7:0] ddrb;
    bit [7:0] ddrc;

    wire [7:0] porta_in = cpu_data_out[7:0];
    bit [7:0] porta_out;
    wire [7:0] portb_in = 8'hff;
    bit [7:0] portb_out;
    wire [7:0] portc_in = {6'b111111, addr[2:1]};
    bit [7:0] portc_out;
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
