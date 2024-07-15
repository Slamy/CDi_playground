# Bootup

We need to get the ROM into the SDRAM

## How does PSX and the Mega CD do it?

Inside psx.cpp there is `load_bios()`. It is called by `psx_mount_cd()`.
But who calls it? From menu.cpp? But why is it called?

Inside megacd.cpp there is `mcd_set_image()`. Inside `MegaCD.sv` there is

```verilog
    wire rom_download = ioctl_download & (ioctl_index[5:0] <= 6'h01);
```
But where does this come from?

Ok, everything revolves around `user_io_file_tx()`
It even says something like this

```c
	// set index byte (0=bios rom, 1-n=OSD entry index)
```

## How does the CD-i do it?


## References

https://github.com/alanswx/Tutorials_MiSTer/tree/master/basic/lesson2/rtl
https://github.com/alanswx/Tutorials_MiSTer/tree/master/basic/lesson2
https://mister-devel.github.io/MkDocs_MiSTer/developer/hps_io/#rom-and-file-loading-nvram-saving
