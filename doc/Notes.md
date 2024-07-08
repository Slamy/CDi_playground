# Notes

## Sources

https://opencores.org/projects/68hc05
https://github.com/JTFPGA/fx68k
https://github.com/cdifan/cdichips

## Conversion of 68hc05 to Verilog

https://cadhut.com/2022/08/14/converting-vhdl-to-verilog/


Doesn't work

    vhd2vl  6805.vhd > 6805.v

But this?

    ghdl -a -fsynopsys -fexplicit 6805.vhd
    ghdl synth --out=verilog -fexplicit -fsynopsys --latches  ur6805  > ur6805.v


PORTD e5 1 7f   Read RW
PORTC e5 1 ff   Read LADD2
PORTC e5 1 ff   Read LADD1
PORTA e5 1 f0   Read whole PORT to A
PORTB e5 1 00   
PORTB 00 0 00   Clear Slave ACK
PORTB 00 1 00
PORTB 40 0 00   Set Slave Ack


## After bootup

ICA1 78000402 FT1=1 FT2=0 MF1=0 MF2=0 CM=0   Run-length
ICA1 c3000000 CLUT Bank 0
ICA1 8000ffff Color 0 is Cyan
ICA1 c0101313 CLUT7
ICA1 c1800008 No Mix
ICA1 c2000000 Plane A in front of Plane B
ICA1 d0000000 No Region?
ICA1 d4000000 No Region?
ICA1 db00003f Weight is off
ICA1 20000434
ICA1 5000043c Set VSR to 0x0043c
ICA1 4000043c 
ICA1 30000434
ICA1 80000000 Color 0 is black


# Later on

ICA1 4007ffb0
ICA2 40259d60
ICA1 78000402
ICA1 c3000000
ICA1 8000ffff
ICA1 c0101313
ICA1 c1800008
ICA1 c2000000
ICA1 d0000000
ICA1 d4000000
ICA1 db00003f
ICA1 20000434
ICA1 5000043c
ICA1 4000043c
ICA1 30000434
ICA1 80000000
ICA1 0

## Building mame

make SOURCES=src/mame/philips/cdi.cpp REGENIE=1 -j8

## Using mame

./mame cdimono1 -log -oslog


/opt/m68k-amigaos3/bin/vasmm68k_mot -Fbin -m68000 68ktest.asm  -o 68ktest.bin



Braucht das CDI mit berr weniger Zeit zum booten?

time ./mame cdimono1 -verbose -log -oslog

Killen bei erscheinen des Menüs

Average speed: 100.00% (11 seconds)
sdl_kill: closing audio
Enter sdlwindow_exit
Leave sdlwindow_exit

real    0m13,950s
user    0m2,421s
sys     0m0,469s


Definitiv. Ohne BERR sucht er einfach länger, wie mir scheint

Average speed: 100.00% (40 seconds)
sdl_kill: closing audio
Enter sdlwindow_exit
Leave sdlwindow_exit

real    0m41,625s
user    0m4,851s
sys     0m1,573s



ghdl_mcode -a -fsynopsys --std=08 ../tg68k/tg68dotc_verilog_wrapper.vhd
ghdl_mcode synth --out=verilog -fsynopsys --std=08  --latches tg68kdotc_verilog_wrapper > tg68kdotc_verilog_wrapper.v



## 68010 trap
Write RAM 004000 2700
Write RAM 004000 0040
Write RAM 004000 0026
Write RAM 004000 0080
Write RAM 004000 0000
Write RAM 004000 0000


Sim2:
416824 e e d8 0 400000 2c70 40817c 800080 416650 4165d8 27ec30 80002010 41685e 2c18 1500 2bbc
Write Lower Byte RAM 27ecaa 0e0e
416828 e e d8 0 400000 2c70 40817c 800080 416650 4165d8 27ec30 80002010 41685e 2c18 1500 2bbc
41682a e e d8 0 400000 2c70 40817c 800080 416650 4165d8 27ec30 80002010 41685e 2c18 1500 2bbc
41682c e e d8 0 400000 2c70 40817c 800080 416650 4165d8 27ec30 80002010 41685d 2c18 1500 2bbc
416830 66 e d8 0 400000 2c70 40817c 800080 416650 4165d8 27ec30 80002010 41685d 2c18 1500 2bbc
416834 e6 e d8 0 400000 2c70 40817c 800080 416650 4165d8 27ec30 80002010 41685d 2c18 1500 2bbc
Read DRAM 002bbc 0041
Read DRAM 002bbe 6752
416836 e6 e d8 0 400000 2c70 40817c 800080 416650 4165d8 27ec30 80002010 41685d 2c18 1500 2bc0
416754 e6 e d8 0 400000 2c70 40817c 800080 416650 4165d8 27ec30 80002010 41685d 2c18 1500 2bc0
41675a 0 e d8 0 400000 2c70 40817c 800080 416650 4165d8 27ec30 80002010 41685d 2c18 1500 2bc0
BUS ERR 7d2548 41ea 1 1 0
Write DRAM 002bbc 0000
Write DRAM 002bbe 0000
Write DRAM 002bb8 0000
Write DRAM 002bba 0000
Write DRAM 002bb4 0000
Write DRAM 002bb6 0000

MAME:
41682c 66 e d8 0 400000 2c70 40817c 800080 416650 4165d8 efec30 80002010 41685d 2c18 1500 2bbc
416830 e6 e d8 0 400000 2c70 40817c 800080 416650 4165d8 efec30 80002010 41685d 2c18 1500 2bbc
416834 e6 e d8 0 400000 2c70 40817c 800080 416650 4165d8 efec30 80002010 41685d 2c18 1500 2bbc
Read DRAM 002bbc 0041
Read DRAM 002bbe 6752
416752 e6 e d8 0 400000 2c70 40817c 800080 416650 4165d8 efec30 80002010 41685d 2c18 1500 2bc0
416756 e6 e d8 0 400000 2c70 40817c 800080 416650 4165d8 efec30 80002010 41685d 2c18 1500 2bc0
41675c e6 e d8 0 400000 2c70 40817c 800080 416650 4165d8 efec30 80002010 41685d 2c18 1500 2bc0
416760 e6 e d8 0 400000 2c70 40817c 800080 efecad 4165d8 efec30 80002010 41685d 2c18 1500 2bc0
416764 e6 e d8 0 400000 2c70 40817c 800080 efecad 4165d8 efec30 80002010 41685d 2c18 1500 2bc0


Address error bei 4006de:
TG68_PC=0x4006df
clkena_lw=0
microstate=nop
PC_dataa=0x4006df
exe_pc=0x4006da

Falscher address error bei 0x41:
Rückkehr per RTS nach 0x416752 von 0x416834
clkena_lw=0
PC_dataa=0x41
exe_pc=0x416834
TG68_PC=0x41
microstate=nopnop


[:mcd212] Scanline 311: VSR Channel 1, ICM (03), VSR (0027fe80)
[:mcd212] Scanline 311: Chan 1: VSR[7fe80] = 40
[:mcd212] Scanline 311: Chan 1: BMP
[:mcd212] Scanline 32: VSR Channel 0, ICM (03), VSR (00076370)
[:mcd212] Scanline 32: Chan 0: VSR[76370] = ff
[:mcd212] Scanline 32: Chan 0: RLE
[:mcd212] Byte ff w/ run length 4b at 0
[:mcd212] Scanline 32: Chan 0: VSR[76372] = fe
[:mcd212] Scanline 32: Chan 0: RLE
[:mcd212] Byte fe w/ run length 05 at 75
[:mcd212] Scanline 32: Chan 0: VSR[76374] = ff
[:mcd212] Scanline 32: Chan 0: RLE
[:mcd212] Byte ff w/ run length 22 at 80
[:mcd212] Scanline 32: Chan 0: VSR[76376] = fe
[:mcd212] Scanline 32: Chan 0: RLE
[:mcd212] Byte fe w/ run length 0e at 114
[:mcd212] Scanline 32: Chan 0: VSR[76378] = fd
[:mcd212] Scanline 32: Chan 0: RLE
[:mcd212] Byte fd w/ run length 09 at 128
[:mcd212] Scanline 32: Chan 0: VSR[7637a] = 7c
[:mcd212] Scanline 32: Chan 0: RLE
[:mcd212] Byte 7c, single at 137
[:mcd212] Scanline 32: Chan 0: VSR[7637b] = fb
[:mcd212] Scanline 32: Chan 0: RLE
[:mcd212] Byte fb w/ run length 06 at 138

