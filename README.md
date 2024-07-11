# CDi_playground

A repo dedicated to create an FPGA implementation of the Philips CDi to be usable for the MiSTer project

This repository is very experimental!

The current planned first milestone is having the boot rom usable
on the MiSTer.
It requires no CDIC to function.

## TODOs

* Fix "Error: system state exception; vector #$0010  at addr $00001500" during boot
	* Might be related to wrong on-chip auto-vectoring
* Implement ICA/DCA parser
* Implement CLUT7 RLE
* Implement functional video channel 1
* Interface to MiSTer framework
* Implementation of SDRAM controller
* Using MiSTer framework to load cdi200.rom and slave rom
* Attach MiSTer input system to the SLAVE controller
* Have the system menu usable on MiSTer
* Evaluate wrong answer on PAL/NTSC status from SLAVE
	* Right now, the expected answer 0x02 is inserted with glue logic
* Implement the CDIC audio parts
* Implement the CDIC CD parts
* Implement SPI interface to CD controller on SLAVE
* Fix I2C for the front display and show the display as picture in picture during changes?
	* It might not even be required at all.
* Have CD data available for the CDIC
* Use the MiSTer framework to save the NVRAM to sdcard
	* Only when changes are detected and when the OSD is opened
	* The N64 core does it like that to
