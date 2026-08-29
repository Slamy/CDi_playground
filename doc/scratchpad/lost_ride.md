# Analysis of Lost Ride

## Timing of Window update

@00407FB2(kernel)   Found cdi_LostRide module at $dd7710 (revision 1, crc $B1DE13, 125950 bytes)

4076ec

DVC ROM Addresses

00e52944 PSOrg      15018308
00e5297c PSPos      15018364
00e52a50 PSWndw     15018576
00e54386 IndicNIS   15025030

PSWndw
D3 0
D4 04800160    1152x352


PSOrg
D3 ff24005e
   ffe60038
   
setstt
  MV_Org = 0x10c   d3 H:V origin

00ded4ac Wrapper function for PSOrg / MV_Org?
  Called from d0879c (jump table?)
    Called from de279a (inside function FUN_00de2122) dez 14559130

When broken at the start
    de279a calls d0879c calls 00ded4ac

So what is the problem? A failing test?

00ded4ac is a wrapper function for MV_Org! The parameter D3 is taken from stack.

uVar2 = (*(code *)(unaff_A6 + 0x79c))((int)*(short *)(unaff_A6 + -0x320a),iVar1,0);


a6 d08000

unaff_A6 + -0x320a
unaff_A6 + -0x3206

d0bab6 ffff ffac    dez 13679286
d0baba 0000 005e    dez 13679290


(short*)-0x320a,A6     d04df6 horizontal pos? used for MV_Org 13651446
(char*) -0x446f,A6            joystick controls maybe?
(short*)-0x3206,A6     d04dfa allowed limit? is 0 when broken  dez 13651450


at 00de1cb8 there is a write to (A6-0x320a)    dez 14556344
at 00dde56a there is a read to (A6-0x320a)
at 00de2720 there is a read to (A6-0x320a) and a write, the one for position setting? dez 14559008

at 00de272E there is a clear of (A6-0x320a)   dez 14559022
It seems to trigger whenever one touches the left side of the screen during working condition

at 0de2742 there is an overwrite of (A6-0x320a)  with (A6-0x3206)?    dez 14559042


At df6bca event handler for MPEG?
At df0de2 another event handler for MPEG?


    (short*)-0x3206,A6 / d04dfa is preloaded with FE80 when loading a save file

    (short*)-0x3206,A6 is
    written at de1cc4 during loading of save
    read at 0xdde562 even when paused but also during game
    read at de273c during game


## Too fast playback after map close

Present since Timesync rework with release 20260807 git hash 8894b795f0b85956127372e5172b73278aea3655

It is not that special. Just playback from CD using PCLs with Normal playback speed without sync.

It might be possible that the position on disk for the first playable area is this

    Syscall @ df087a 88 I$Seek 00000007 03520800 03520800 00000003 f5022001 00000001 0000bca0 00000000  00d06e18 00000000 00d03aa4 00dffd90 00d0bc98 00d0bad6 00d08000 00dfd428


    cat backup_lostride/log_close_map | grep -e " MV_" -e bmp

    Written video_671.bmp
    Written video_672.bmp
    Syscall @ ded56e 8e I$SetStt 00000003 0000010e 00000001 00000000 00000000 00000000 ffffffff 00000000  00d06a10 00d0fed0 00d10630 00dffd90 00d03b4e 00d0bb16 00d08000 00dfd428 SetStt MV_Play
    Written video_673.bmp
    Written video_674.bmp
    Written video_675.bmp
    Written video_676.bmp
    Written video_677.bmp
    Written video_678.bmp
    Written video_679.bmp
    FMV Writing 5/fmv_022.bmp at Fifo Level 3421 at Frame Level 4 2 0 I 0
    Written video_680.bmp
    Written video_681.bmp
    ...
    Syscall @ ded50c 8e I$SetStt 00000003 00d0010d 00000001 00000003 00000000 00000024 0000bca0 00000000  00d06e18 00000000 00d042be 00dffd90 00d0bc98 00d0bb9e 00d08000 00dfd428 SetStt MV_Pause
    FMV Writing 5/fmv_169.bmp at Fifo Level 26299 at Frame Level 5 2 2 P 9
    Written video_978.bmp
    Written video_979.bmp
    FMV Writing 5/fmv_170.bmp at Fifo Level 25534 at Frame Level 5 2 2 P 10
    Written video_980.bmp
    Written video_981.bmp
    ...
    Written video_992.bmp
    Written video_993.bmp
    FMV Writing 5/fmv_174.bmp at Fifo Level 4014 at Frame Level 1 2 6 P 14
    Written video_994.bmp
    ...
    Written video_1040.bmp
    Syscall @ ded2fa 8e I$SetStt 00000003 00000105 00000000 00000003 00000000 00000024 0000bca0 00000000  0007aa0c 00000000 00d104f0 00dffd90 00d0bc98 00d0bb9e 00d08000 00dfd428 SetStt MV_Continue
    Written video_1041.bmp
    Written video_1042.bmp
    FMV Writing 5/fmv_175.bmp at Fifo Level 4584 at Frame Level 1 2 7 P 15
    Written video_1043.bmp
    Written video_1044.bmp
