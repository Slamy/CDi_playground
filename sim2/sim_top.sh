verilator --top-module fx68k_tb --trace --cc --assert --exe  --timing --build \
    --build-jobs 8 sim_top.cpp \
    ../sim/fx68k_tb.sv ../rtl/*.sv  ../rtl/*.v  ../rtl/*.svh \
    /usr/lib/x86_64-linux-gnu/libpng.so && ./obj_dir/Vfx68k_tb
