// Include common routines
#include <verilated.h>
#include <verilated_vcd_c.h>

// Include model header, generated from Verilating "top.v"
#include "Vemu.h"
#include "Vemu___024root.h"

#include <csignal>
#include <cstdio>
#include <cstdlib>
#include <png.h>

uint64_t sim_time = 0;

static bool kDoTrace{true};

volatile sig_atomic_t status = 0;

static void catch_function(int signo) {
    status = signo;
}
const int width = 120 * 16 * 2;
const int height = 600;

uint8_t output_image[width * height * 3] = {0};

void write_png_file(const char *filename) {
    int y;

    FILE *fp = fopen(filename, "wb");
    if (!fp)
        abort();

    png_structp png = png_create_write_struct(PNG_LIBPNG_VER_STRING, NULL, NULL, NULL);
    if (!png)
        abort();

    png_infop info = png_create_info_struct(png);
    if (!info)
        abort();

    if (setjmp(png_jmpbuf(png)))
        abort();

    png_init_io(png, fp);

    // Output is 8bit depth, RGBA format.
    png_set_IHDR(png, info, width, height, 8, PNG_COLOR_TYPE_RGB, PNG_INTERLACE_NONE, PNG_COMPRESSION_TYPE_DEFAULT,
                 PNG_FILTER_TYPE_DEFAULT);
    png_write_info(png, info);

    png_bytepp row_pointers = (png_bytepp)png_malloc(png, sizeof(png_bytepp) * height);

    // output_image[1] = 255;
    for (int i = 0; i < height; i++) {
        row_pointers[i] = &output_image[width * 3 * i];
    }

    png_write_image(png, row_pointers);
    png_write_end(png, NULL);

    free(row_pointers);

    fclose(fp);

    png_destroy_write_struct(&png, &info);
}

void clock(VerilatedVcdC &m_trace, Vemu &dut) {
    dut.rootp->emu__DOT__clk_sys = (sim_time & 2) >> 1;
    dut.rootp->emu__DOT__clk_mem = (sim_time & 1);
    dut.eval();
    if (kDoTrace) {
        m_trace.dump(sim_time);
    }
    sim_time++;
}

void do_justwait(VerilatedVcdC &m_trace, Vemu &dut) {
    dut.eval();

    // dut.rootp->fx68k_tb__DOT__resetcnt = 0x7FFF8;

    kDoTrace = false;

    for (int y = 0; y < 1880000; y++) {
        //  for (int y = 0;; y++) {
        clock(m_trace, dut);
        clock(m_trace, dut);
        clock(m_trace, dut);
        clock(m_trace, dut);

        static int output_index = 0;

        output_image[output_index++] = dut.rootp->emu__DOT__r;
        output_image[output_index++] = dut.rootp->emu__DOT__g;
        output_image[output_index++] = dut.rootp->emu__DOT__b;

        if ((y % 100000) == 0) {
            printf("%d\n", y);
        }
        /*
        printf("%x %x %x %x\n",
           dut.rootp-> fx68k_tb__DOT__scc68070_0__DOT__tg68__DOT__tg68kdotcinst__DOT__tg68_pc,
            dut.rootp->fx68k_tb__DOT__scc68070_0__DOT__tg68__DOT__tg68kdotcinst__DOT__tmp_tg68_pc,
           dut.rootp-> fx68k_tb__DOT__scc68070_0__DOT__tg68__DOT__tg68kdotcinst__DOT__exe_pc,
           dut.rootp-> fx68k_tb__DOT__scc68070_0__DOT__tg68__DOT__tg68kdotcinst__DOT__last_opc_pc
            );
            */
        static uint32_t pc = 0;

        // static uint32_t d1 = 0;
        // static uint32_t d0 = 0;
        static uint32_t regfile[16];

#if 0
        if (dut.rootp->fx68k_tb__DOT__scc68070_0__DOT__tg68__DOT__tg68kdotcinst__DOT__decodeopc) {
            pc = dut.rootp->fx68k_tb__DOT__scc68070_0__DOT__tg68__DOT__tg68kdotcinst__DOT__exe_pc;
            // d0 = dut.rootp->fx68k_tb__DOT__d0;
            memcpy(regfile, &dut.rootp->fx68k_tb__DOT__scc68070_0__DOT__tg68__DOT__tg68kdotcinst__DOT__regfile[0],
                   sizeof(regfile));

            printf("%x", pc);
            for (int i = 0; i < 16; i++)
                printf(" %x", regfile[i]);
            printf("\n");

            // d1 = dut.rootp->fx68k_tb__DOT__d1;
            /*
            printf("%x %x %x %x %x %x\n", pc, dut.rootp->fx68k_tb__DOT__d0, dut.rootp->fx68k_tb__DOT__d1,
                   regfile[8 + 0], regfile[8 + 2], regfile[8 + 6]);
            */
        }
#endif

        /*
        if (y == 29600000)
        uart_receive_holding_register*/

        if (y == 21200000)
            kDoTrace = true;

        if (y == 21300000)
            kDoTrace = false;

        if (status == SIGINT)
            break;
    }
    /*
        uint32_t ica1 = readlongword(dut, 0x400);
        uint32_t ica2 = readlongword(dut, 0x40400);

        printf("ICA1 %x\n", ica1);
        printf("ICA2 %x\n", ica2);

        for (int i = 0; i < 20; i++)
            printf("ICA1 %x\n", readlongword(dut, 0x408 + i * 4));

        for (int i = 0; i < 20; i++)
            printf("ICA2 %x\n", readlongword(dut, 0x40408 + i * 4));
            */

    write_png_file("derp.png");
    /*
        for (int i = 0; i < 100; i++)
            printf("pixels %04x\n", dut.rootp->fx68k_tb__DOT__mcd212_inst__DOT__testram[(0x43c >> 1) + i]);
    */
    // uint8_t *src = (uint8_t *)&dut.rootp->fx68k_tb__DOT__mcd212_inst__DOT__testram[0x43c >> 1];
#if 0
    for (int y = 0; y < 220; y++) {
        for (int x = 0; x < 360; x++) {
            uint8_t color = *src;
            printf("%02x", color);
            src++;
        }
        printf("\n");
    }
#endif
#if 0
    for (int y = 0; y < 220; y++) {
        int x = 0;
        while (x < 360) {

            uint8_t color = *src & 0x7f;
            if (*src & 0x80) {
                src++;
                uint8_t number = *src;
                if (number == 0) {
                    while (x < 360) {
                        x++;
                        printf("%02x", color);
                    }
                } else if (number == 1) {
                    printf("Nope!\n");
                    exit(1);
                } else {
                    while (number > 0) {
                        number--;
                        x++;
                        printf("%02x", color);
                    }
                }
            } else {
                printf("%02x", color);
                x++;
            }

            src++;
        }
        printf("\n");
    }
#endif

    // printf("ICA1 %x\n",dut.rootp->fx68k_tb__DOT__mcd212_inst__DOT__testram[ica1>>1]);
}

int main(int argc, char **argv) {
    // Initialize Verilators variables
    Verilated::commandArgs(argc, argv);

    if (kDoTrace)
        Verilated::traceEverOn(true);

    VerilatedVcdC m_trace;
    Vemu dut;

    if (signal(SIGINT, catch_function) == SIG_ERR) {
        fputs("An error occurred while setting a signal handler.\n", stderr);
        return EXIT_FAILURE;
    }

    dut.trace(&m_trace, 5);

    if (kDoTrace)
        m_trace.open("/tmp/waveform.vcd");

    // do_selftest_dram(m_trace, dut);
    //  do_selftest_lowlevelpcb(m_trace, dut);
    //  do_selftest_cdic(m_trace, dut);
    //  do_selftest_slave(m_trace, dut);
    do_justwait(m_trace, dut);

    fprintf(stderr, "Closing...\n");
    fflush(stdout);

    return 0;
}
