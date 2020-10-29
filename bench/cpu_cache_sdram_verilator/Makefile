OBJ_DIR=obj_dir
VERILATOR_DIR=/usr/share/verilator/include
HDL_FILES = cpu_cache_sdram_tb.v mt48lc16m16a2.v ../../rtl/sdram/cpu_cache_new.v ../../rtl/sdram/sdram_ctrl.v ../../rtl/sdram/dpram_inf_256x32.v ../../rtl/sdram/dpram_inf_be_1024x32.v ../../rtl/sdram/dpram_inf_generic.v

all: cpu_cache_sdram_tb

Vcpu_cache_sdram_tb.cpp: ${OBJ_DIR}/Vcpu_cache_sdram_tb.cpp


${OBJ_DIR}/Vcpu_cache_sdram_tb.cpp: ${HDL_FILES}
	verilator --trace --top-module cpu_cache_sdram_tb -cc ${HDL_FILES}

cpu_cache_sdram_tb: ${OBJ_DIR}/Vcpu_cache_sdram_tb.cpp cpu_cache_sdram_tb.cpp
	g++ -I $(OBJ_DIR) -I$(VERILATOR_DIR) $(VERILATOR_DIR)/verilated.cpp $(VERILATOR_DIR)/verilated_vcd_c.cpp cpu_cache_sdram_tb.cpp  $(OBJ_DIR)/Vcpu_cache_sdram_tb__Trace.cpp $(OBJ_DIR)/Vcpu_cache_sdram_tb__Trace__Slow.cpp $(OBJ_DIR)/Vcpu_cache_sdram_tb.cpp $(OBJ_DIR)/Vcpu_cache_sdram_tb__Syms.cpp -DOPT=-DVL_DEBUG -o cpu_cache_sdram_tb

