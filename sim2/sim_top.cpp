// Include common routines
#include <verilated.h>
#include <verilated_vcd_c.h>

// Include model header, generated from Verilating "top.v"
#include "Vfx68k_tb.h"
#include "Vfx68k_tb___024root.h"

#include <csignal>
#include <cstdio>
#include <cstdlib>
#include <png.h>

int sim_time = 0;

static bool kDoTrace{false};

volatile sig_atomic_t status = 0;

static void catch_function(int signo) {
    status = signo;
}
const int width = 384;
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

    //output_image[1] = 255;
    for (int i = 0; i < height; i++) {
        row_pointers[i] = &output_image[width * 3 * i];
    }

    png_write_image(png, row_pointers);
    png_write_end(png, NULL);

    free(row_pointers);

    fclose(fp);

    png_destroy_write_struct(&png, &info);
}

uint32_t readlongword(Vfx68k_tb &dut, uint32_t adr) {
    return (dut.rootp->fx68k_tb__DOT__mcd212_inst__DOT__testram[adr >> 1] << 16) |
           dut.rootp->fx68k_tb__DOT__mcd212_inst__DOT__testram[(adr >> 1) + 1];
}
void do_justwait(VerilatedVcdC &m_trace, Vfx68k_tb &dut) {
    dut.eval();

    dut.rootp->fx68k_tb__DOT__scc68070_0__DOT__uart_status_register |= 0x04;
    // dut.rootp->fx68k_tb__DOT__resetcnt = 0x7FFF8;

    kDoTrace = true;

    FILE *f = fopen("ramdump.bin", "rb");
    assert(f);
    fread(&dut.rootp->fx68k_tb__DOT__mcd212_inst__DOT__testram[0], 1, 1024 * 256 * 4, f);
    fclose(f);

    for (int y = 0; y < 280000; y++) {
        //  for (int y = 0;; y++) {
        dut.rootp->fx68k_tb__DOT__clk = 0;
        dut.eval();
        if (kDoTrace) {
            m_trace.dump(sim_time);
        }
        sim_time++;

        dut.rootp->fx68k_tb__DOT__clk = 1;
        dut.eval();
        if (kDoTrace) {
            m_trace.dump(sim_time);
        }
        sim_time++;

        static int output_index=0;
        if (dut.rootp->fx68k_tb__DOT__mcd212_inst__DOT__rle_pixel_strobe) {
            //printf("%d %d\n",(output_index/3) % 384,dut.rootp->fx68k_tb__DOT__mcd212_inst__DOT__rle_pixel);
            output_image[output_index++] = dut.rootp->fx68k_tb__DOT__r;
            output_image[output_index++] = dut.rootp->fx68k_tb__DOT__g;
            output_image[output_index++] = dut.rootp->fx68k_tb__DOT__b;
        }

        // Print characters sent to UART to stderr
        if ((dut.rootp->fx68k_tb__DOT__scc68070_0__DOT__uart_status_register & 0x04) == 0) {
            dut.rootp->fx68k_tb__DOT__scc68070_0__DOT__uart_status_register |= 0x04;
            // fprintf(stderr, " -> Uart Write %x\n",
            // dut.rootp->fx68k_tb__DOT__scc68070_0__DOT__uart_transmit_holding_register);
            fputc(dut.rootp->fx68k_tb__DOT__scc68070_0__DOT__uart_transmit_holding_register, stderr);
        }

        if ((y % 100000) == 0) {
            printf("%d %d\n", y, dut.rootp->fx68k_tb__DOT__scc68070_0__DOT__timer0);
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

void do_selftest_dram(VerilatedVcdC &m_trace, Vfx68k_tb &dut) {
    dut.rootp->fx68k_tb__DOT__scc68070_0__DOT__uart_status_register |= 0x04;

    // for (int y = 0; y < 1000; y++) {
    for (int y = 0;; y++) {
        dut.rootp->fx68k_tb__DOT__clk = 0;
        dut.eval();
        if (kDoTrace) {
            m_trace.dump(sim_time);
        }
        sim_time++;

        if (y == 1000) {
            printf("Space!\n");
            dut.rootp->fx68k_tb__DOT__scc68070_0__DOT__uart_receive_holding_register = ' ';
            dut.rootp->fx68k_tb__DOT__scc68070_0__DOT__uart_status_register |= 1;
        }

        if (y == 8000) {
            printf("Press A!\n");
            dut.rootp->fx68k_tb__DOT__scc68070_0__DOT__uart_receive_holding_register = 'A';
            dut.rootp->fx68k_tb__DOT__scc68070_0__DOT__uart_status_register |= 1;
        }

        if (y == 19000) {
            printf("Press 4!\n");
            dut.rootp->fx68k_tb__DOT__scc68070_0__DOT__uart_receive_holding_register = '4';
            dut.rootp->fx68k_tb__DOT__scc68070_0__DOT__uart_status_register |= 1;
        }

        if (1) {
            if (y == 21000) {
                printf("Press!\n");
                dut.rootp->fx68k_tb__DOT__scc68070_0__DOT__uart_receive_holding_register = 'Y';
                dut.rootp->fx68k_tb__DOT__scc68070_0__DOT__uart_status_register |= 1;
            }
        } else {
            if (y == 21000) {
                printf("Press!\n");
                dut.rootp->fx68k_tb__DOT__scc68070_0__DOT__uart_receive_holding_register = 'N';
                dut.rootp->fx68k_tb__DOT__scc68070_0__DOT__uart_status_register |= 1;
            }

            if (y == 22000) {
                printf("Press!\n");
                dut.rootp->fx68k_tb__DOT__scc68070_0__DOT__uart_receive_holding_register = 'Y';
                dut.rootp->fx68k_tb__DOT__scc68070_0__DOT__uart_status_register |= 1;
            }
        }

        /*
        if (y == 1000) {
            kDoTrace = false;
            printf("Trace Off!\n");
        }

        if (y == 3430000) {
            kDoTrace = true;
            printf("Trace On!\n");
        }

        if (y == 3440000) {
            kDoTrace = false;
            printf("Trace Off!\n");
        }*/

        if ((y % 10000) == 0) {
            // printf("%d\n", y);
        }

        // Print characters sent to UART to stderr
        if ((dut.rootp->fx68k_tb__DOT__scc68070_0__DOT__uart_status_register & 0x04) == 0) {
            dut.rootp->fx68k_tb__DOT__scc68070_0__DOT__uart_status_register |= 0x04;
            // fprintf(stderr, " -> Uart Write %x\n",
            // dut.rootp->fx68k_tb__DOT__scc68070_0__DOT__uart_transmit_holding_register);
            fputc(dut.rootp->fx68k_tb__DOT__scc68070_0__DOT__uart_transmit_holding_register, stderr);
        }

        dut.rootp->fx68k_tb__DOT__clk = 1;
        dut.eval();
        if (kDoTrace) {
            m_trace.dump(sim_time);
            sim_time++;
        }

        if (status == SIGINT)
            break;
    }
}

void do_selftest_slave(VerilatedVcdC &m_trace, Vfx68k_tb &dut) {
    dut.rootp->fx68k_tb__DOT__scc68070_0__DOT__uart_status_register |= 0x04;
    int y = 0;

    for (; y < 289000; y++) {
        dut.rootp->fx68k_tb__DOT__clk = 0;
        dut.eval();
        if (kDoTrace) {
            m_trace.dump(sim_time);
            sim_time++;
        }

        if (y == 1000) {
            printf("Space!\n");
            dut.rootp->fx68k_tb__DOT__scc68070_0__DOT__uart_receive_holding_register = ' ';
            dut.rootp->fx68k_tb__DOT__scc68070_0__DOT__uart_status_register |= 1;
        }

        if (y == 70000) {
            printf("Press!\n");
            dut.rootp->fx68k_tb__DOT__scc68070_0__DOT__uart_receive_holding_register = 'A';
            dut.rootp->fx68k_tb__DOT__scc68070_0__DOT__uart_status_register |= 1;
        }

        if (y == 240000) {
            printf("Press!\n");
            dut.rootp->fx68k_tb__DOT__scc68070_0__DOT__uart_receive_holding_register = '6';
            dut.rootp->fx68k_tb__DOT__scc68070_0__DOT__uart_status_register |= 1;
        }

        // Print characters sent to UART to stderr
        if ((dut.rootp->fx68k_tb__DOT__scc68070_0__DOT__uart_status_register & 0x04) == 0) {
            dut.rootp->fx68k_tb__DOT__scc68070_0__DOT__uart_status_register |= 0x04;
            // fprintf(stderr, " -> Uart Write %x\n",
            // dut.rootp->fx68k_tb__DOT__scc68070_0__DOT__uart_transmit_holding_register);
            fputc(dut.rootp->fx68k_tb__DOT__scc68070_0__DOT__uart_transmit_holding_register, stderr);
        }

        dut.rootp->fx68k_tb__DOT__clk = 1;
        dut.eval();
        if (kDoTrace) {
            m_trace.dump(sim_time);
            sim_time++;
        }

        if (status == SIGINT)
            break;
    }

    for (;; y++) {

        dut.rootp->fx68k_tb__DOT__clk = 0;
        dut.eval();
        if (kDoTrace && y >= 18100000) {
            m_trace.dump(sim_time);
            sim_time++;
        }

        dut.rootp->fx68k_tb__DOT__clk = 1;
        dut.eval();
        if (kDoTrace && y >= 18100000) {
            m_trace.dump(sim_time);
            sim_time++;
        }

        if ((y % 100000) == 0) {
            printf("%d\n", y);
        }

        // Print characters sent to UART to stderr
        if ((dut.rootp->fx68k_tb__DOT__scc68070_0__DOT__uart_status_register & 0x04) == 0) {
            dut.rootp->fx68k_tb__DOT__scc68070_0__DOT__uart_status_register |= 0x04;
            // fprintf(stderr, " -> Uart Write %x\n",
            // dut.rootp->fx68k_tb__DOT__scc68070_0__DOT__uart_transmit_holding_register);
            fputc(dut.rootp->fx68k_tb__DOT__scc68070_0__DOT__uart_transmit_holding_register, stderr);
        }

        if (status == SIGINT)
            break;
    }
}

void do_selftest_cdic(VerilatedVcdC &m_trace, Vfx68k_tb &dut) {
    dut.rootp->fx68k_tb__DOT__scc68070_0__DOT__uart_status_register |= 0x04;
    int y = 0;

    for (; y < 289000; y++) {
        dut.rootp->fx68k_tb__DOT__clk = 0;
        dut.eval();
        if (kDoTrace) {
            m_trace.dump(sim_time);
            sim_time++;
        }

        if (y == 1000) {
            printf("Space!\n");
            dut.rootp->fx68k_tb__DOT__scc68070_0__DOT__uart_receive_holding_register = ' ';
            dut.rootp->fx68k_tb__DOT__scc68070_0__DOT__uart_status_register |= 1;
        }

        if (y == 70000) {
            printf("Press!\n");
            dut.rootp->fx68k_tb__DOT__scc68070_0__DOT__uart_receive_holding_register = 'A';
            dut.rootp->fx68k_tb__DOT__scc68070_0__DOT__uart_status_register |= 1;
        }

        if (y == 240000) {
            printf("Press!\n");
            dut.rootp->fx68k_tb__DOT__scc68070_0__DOT__uart_receive_holding_register = '5';
            dut.rootp->fx68k_tb__DOT__scc68070_0__DOT__uart_status_register |= 1;
        }

        // Print characters sent to UART to stderr
        if ((dut.rootp->fx68k_tb__DOT__scc68070_0__DOT__uart_status_register & 0x04) == 0) {
            dut.rootp->fx68k_tb__DOT__scc68070_0__DOT__uart_status_register |= 0x04;
            // fprintf(stderr, " -> Uart Write %x\n",
            // dut.rootp->fx68k_tb__DOT__scc68070_0__DOT__uart_transmit_holding_register);
            fputc(dut.rootp->fx68k_tb__DOT__scc68070_0__DOT__uart_transmit_holding_register, stderr);
        }

        dut.rootp->fx68k_tb__DOT__clk = 1;
        dut.eval();
        if (kDoTrace) {
            m_trace.dump(sim_time);
            sim_time++;
        }

        if (status == SIGINT)
            break;
    }

    for (;; y++) {

        dut.rootp->fx68k_tb__DOT__clk = 0;
        dut.eval();
        if (kDoTrace) {
            m_trace.dump(sim_time);
            sim_time++;
        }

        dut.rootp->fx68k_tb__DOT__clk = 1;
        dut.eval();
        if (kDoTrace) {
            m_trace.dump(sim_time);
            sim_time++;
        }

        if ((y % 100000) == 0) {
            printf("%d\n", y);
        }

        if ((dut.rootp->fx68k_tb__DOT__scc68070_0__DOT__uart_status_register & 0x04) == 0) {
            dut.rootp->fx68k_tb__DOT__scc68070_0__DOT__uart_status_register |= 0x04;
            // fprintf(stderr, " -> Uart Write %x\n",
            // dut.rootp->fx68k_tb__DOT__scc68070_0__DOT__uart_transmit_holding_register);
            fputc(dut.rootp->fx68k_tb__DOT__scc68070_0__DOT__uart_transmit_holding_register, stderr);
        }

        if (status == SIGINT)
            break;
    }
}

void do_selftest_lowlevelpcb(VerilatedVcdC &m_trace, Vfx68k_tb &dut) {
    dut.rootp->fx68k_tb__DOT__scc68070_0__DOT__uart_status_register |= 0x04;
    int y = 0;

    uint16_t backup[3];

    dut.eval();

    backup[0] = dut.rootp->fx68k_tb__DOT__rom[0x14a6 >> 1];
    backup[1] = dut.rootp->fx68k_tb__DOT__rom[0x15ce >> 1];
    backup[2] = dut.rootp->fx68k_tb__DOT__rom[0x1614 >> 1];

    dut.rootp->fx68k_tb__DOT__rom[0x14a6 >> 1] = 0;
    dut.rootp->fx68k_tb__DOT__rom[0x15ce >> 1] = 0;
    dut.rootp->fx68k_tb__DOT__rom[0x1614 >> 1] = 0;

    for (; y < 289000; y++) {
        dut.rootp->fx68k_tb__DOT__clk = 0;
        dut.eval();
        if (kDoTrace) {
            m_trace.dump(sim_time);
            sim_time++;
        }

        if (y == 9000) {
            printf("Space!\n");
            dut.rootp->fx68k_tb__DOT__scc68070_0__DOT__uart_receive_holding_register = 0x06;
            dut.rootp->fx68k_tb__DOT__scc68070_0__DOT__uart_status_register |= 1;
        }

        if (y == 19000) {
            printf("Space!\n");
            dut.rootp->fx68k_tb__DOT__scc68070_0__DOT__uart_receive_holding_register = 'N';
            dut.rootp->fx68k_tb__DOT__scc68070_0__DOT__uart_status_register |= 1;
        }

        // Print characters sent to UART to stderr
        if ((dut.rootp->fx68k_tb__DOT__scc68070_0__DOT__uart_status_register & 0x04) == 0) {
            dut.rootp->fx68k_tb__DOT__scc68070_0__DOT__uart_status_register |= 0x04;
            printf(" -> Uart Write %x %c\n", dut.rootp->fx68k_tb__DOT__scc68070_0__DOT__uart_transmit_holding_register,
                   dut.rootp->fx68k_tb__DOT__scc68070_0__DOT__uart_transmit_holding_register);
            // fputc(dut.rootp->fx68k_tb__DOT__scc68070_0__DOT__uart_transmit_holding_register, stderr);
        }

        dut.rootp->fx68k_tb__DOT__clk = 1;
        dut.eval();
        if (kDoTrace) {
            m_trace.dump(sim_time);
            sim_time++;
        }

        if (status == SIGINT)
            break;
    }

    for (;; y++) {

        dut.rootp->fx68k_tb__DOT__clk = 0;
        dut.eval();
        if (kDoTrace) {
            m_trace.dump(sim_time);
            sim_time++;
        }

        dut.rootp->fx68k_tb__DOT__clk = 1;
        dut.eval();
        if (kDoTrace) {
            m_trace.dump(sim_time);
            sim_time++;
        }

        if ((y % 100000) == 0) {
            printf("%x\n", y);
        }

        // Print characters sent to UART to stderr
        if ((dut.rootp->fx68k_tb__DOT__scc68070_0__DOT__uart_status_register & 0x04) == 0) {
            dut.rootp->fx68k_tb__DOT__scc68070_0__DOT__uart_status_register |= 0x04;
            // fprintf(stderr, " -> Uart Write %x\n",
            // dut.rootp->fx68k_tb__DOT__scc68070_0__DOT__uart_transmit_holding_register);
            printf(" -> Uart Write %x %c %d\n",
                   dut.rootp->fx68k_tb__DOT__scc68070_0__DOT__uart_transmit_holding_register,
                   dut.rootp->fx68k_tb__DOT__scc68070_0__DOT__uart_transmit_holding_register, y);

            // fputc(dut.rootp->fx68k_tb__DOT__scc68070_0__DOT__uart_transmit_holding_register, stderr);
        }

        if (y == 5090053) {
            printf("restore backup\n");
            dut.rootp->fx68k_tb__DOT__rom[0x14a6 >> 1] = backup[0];
            dut.rootp->fx68k_tb__DOT__rom[0x15ce >> 1] = backup[1];
            dut.rootp->fx68k_tb__DOT__rom[0x1614 >> 1] = backup[2];
        }

        if (y == 0x31ed1c0) {
            printf("remove delay\n");

            dut.rootp->fx68k_tb__DOT__rom[0x14b8 >> 1] = 0;
        }

        if (status == SIGINT)
            break;
    }
}

int main(int argc, char **argv) {
    // Initialize Verilators variables
    Verilated::commandArgs(argc, argv);

    if (kDoTrace)
        Verilated::traceEverOn(true);

    VerilatedVcdC m_trace;
    Vfx68k_tb dut;

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
