# Les Guignols de l’Info

## Different time code?

When playing this small sized frame cutscene

    mpegFile = open("/cd/RTF/application.rtf", _READ); 
    DEBUG(lseek(mpegFile, 0x11DEA000, 0));

The TIMECD register (the one of the decoder that is filled first) returns this

    MiSTer 15302A2  0000 0001 0101 0011   0000 0010 1010 0010  10:34:05:19
    VMPEG  14002a2  0000 0001 0100 0000   0000 0010 1010 0010  10:34:05:00

    according to FMV driver
    High  SSSS SSSS SSPP PPPP
    Low   HHHH HHHH HHMM MMMM

This might indicate that the P bits are simply 0 on VMPEG side while the rest matches.
When putting the playback test in the simulator, these are the info from the stream dump.

    PICTURE @ 0x00000784  GOP --:--:--:--  temporal_ref=   4  type=B
    PICTURE @ 0x000012bc  GOP --:--:--:--  temporal_ref=   5  type=B
    GOP     @ 0x00001dfa  10:34:05:07
    PICTURE @ 0x00001e02  GOP 10:34:05:07  temporal_ref=   2  type=I
    PICTURE @ 0x00002fad  GOP 10:34:05:07  temporal_ref=   0  type=B
    PICTURE @ 0x00003476  GOP 10:34:05:07  temporal_ref=   1  type=B
    PICTURE @ 0x00003fb3  GOP 10:34:05:07  temporal_ref=   5  type=P
    PICTURE @ 0x00004af8  GOP 10:34:05:07  temporal_ref=   3  type=B
    PICTURE @ 0x0000562f  GOP 10:34:05:07  temporal_ref=   4  type=B
    PICTURE @ 0x0000616e  GOP 10:34:05:07  temporal_ref=   8  type=P
    PICTURE @ 0x00006cb0  GOP 10:34:05:07  temporal_ref=   6  type=B
    PICTURE @ 0x000077ea  GOP 10:34:05:07  temporal_ref=   7  type=B
    PICTURE @ 0x00008329  GOP 10:34:05:07  temporal_ref=  11  type=P
    PICTURE @ 0x00008e6b  GOP 10:34:05:07  temporal_ref=   9  type=B
    PICTURE @ 0x000099a4  GOP 10:34:05:07  temporal_ref=  10  type=B
    SEQUENCE @ 0x0000a4e2  208x128  aspect=1.0695 (code 11)  fps=25 (code 3)  bitrate=575600 bit/s  vbv=131072 bits, constrained
    GOP     @ 0x0000a52e  10:34:05:19
    PICTURE @ 0x0000a536  GOP 10:34:05:19  temporal_ref=   2  type=I
    PICTURE @ 0x0000b6e9  GOP 10:34:05:19  temporal_ref=   0  type=B
    PICTURE @ 0x0000bb5d  GOP 10:34:05:19  temporal_ref=   1  type=B
    PICTURE @ 0x0000c69c  GOP 10:34:05:19  temporal_ref=   5  type=P
    PICTURE @ 0x0000d1e1  GOP 10:34:05:19  temporal_ref=   3  type=B
    PICTURE @ 0x0000dd18  GOP 10:34:05:19  temporal_ref=   4  type=B
    PICTURE @ 0x0000e856  GOP 10:34:05:19  temporal_ref=   8  type=P

I see the issue now. My own decoder only starts at SEQ and ignores everything before that.
This explains why the time code on the MiSTer starts at 10:34:05:19.
On the other hand the VMPEG goes from 10:34:05:00 to 10:34:05:07 to 10:34:05:19.
