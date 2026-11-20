# lab12 exp1_system 软件工程, RV32I 裸机程序
#
# 在 exp1_system 目录下用容器编译:
#   docker run --rm -u "$(id -u):$(id -g)" -e HOME=/tmp \
#       -v "$PWD":/work -w /work/sw riscv32:12 \
#       bash -lc 'make RISCV_PREFIX=riscv64-linux-gnu-'
#
# 产物 main.hex 与 main_d.hex 复制到上一级目录, 供 Vivado 的 $readmemh 使用
#
# 关键参数:
#   -march=rv32i -mabi=ilp32  交叉 GCC 默认生成 RV64, 必须显式指定
#   -mno-relax                关闭链接松弛, 指令序列与反汇编一致
#   -Wl,--build-id=none       Ubuntu 的 GCC 会生成 .note.gnu.build-id 挤占地址 0
#   -fno-stack-protector      Ubuntu 默认开 SSP, 会引入 __stack_chk_fail
#   -nostdlib -nolibc         没有 C 库, 除法等由 mul.c 提供

XLEN          ?= 32
RISCV_PREFIX  ?= riscv$(XLEN)-unknown-elf-
RISCV_GCC     ?= $(RISCV_PREFIX)gcc
RISCV_OBJCOPY ?= $(RISCV_PREFIX)objcopy -O verilog
RISCV_OBJDUMP ?= $(RISCV_PREFIX)objdump --disassemble-all --disassemble-zeroes \
                 --section=.text --section=.text.startup --section=.text.init --section=.data

ARCH      := -march=rv32i -mabi=ilp32 -mno-relax
GCC_WARNS := -Wall -Wextra
OPT       ?= -O0

RISCV_GCC_OPTS ?= $(ARCH) -static -mcmodel=medany -fvisibility=hidden \
                  -Wl,--build-id=none -Tsections.ld -nostdlib -nolibc -nostartfiles \
                  -fno-builtin -fno-stack-protector $(GCC_WARNS)

SRCS := $(wildcard *.c)
OBJS := $(SRCS:.c=.o)
EXEC := main

DMEM_WORDS := 32768

# objcopy -O verilog 的输出按 @字节地址 分段, 这里拆成代码段和数据段两个文件
#   code=1 输出代码段, code=0 输出数据段
#   @ 地址换算成字地址: (addr % 262144) / 4
# 数据段起始 0x0010_0000 % 262144 == 0, 所以 main_d.hex 从 0 开始
RISCV_HEXGEN := 'BEGIN{output=0;} { gsub("\r","",$$(NF)); if ($$1 ~ /@/) { if ($$1 ~ /@00000000/) {output=code;} else {output=1-code;}; gsub("@","0x",$$1); addr=strtonum($$1); if (output==1) {printf "@%08x\n",(addr%262144)/4;}} else { if (output==1) { for(i=1;i<NF;i+=4) print $$(i+3)$$(i+2)$$(i+1)$$i;}}}'

.PHONY: all clean check

all: ../$(EXEC).hex

%.o: %.c sys.h
	$(RISCV_GCC) -c $(RISCV_GCC_OPTS) $(OPT) $< -o $@

$(EXEC).elf: $(OBJS) sections.ld
	$(RISCV_GCC) $(RISCV_GCC_OPTS) $(OPT) -e entry $(OBJS) -o $@
	$(RISCV_OBJDUMP) $@ > $(EXEC).dump

$(EXEC).tmp: $(EXEC).elf
	$(RISCV_OBJCOPY) $< $@

# main_d.hex 补齐到整个数据存储器的大小, 保证 BRAM 里没有未初始化单元
$(EXEC).hex: $(EXEC).tmp
	awk -v code=1 $(RISCV_HEXGEN) $< > $@
	awk -v code=0 $(RISCV_HEXGEN) $< > $(EXEC)_d.hex
	awk '{ if ($$1 ~ /^@/) { print; next } n += NF; print } \
	     END { for (; n < $(DMEM_WORDS); n++) print "00000000" }' \
	    $(EXEC)_d.hex > $(EXEC)_d.pad
	mv $(EXEC)_d.pad $(EXEC)_d.hex

../$(EXEC).hex: $(EXEC).hex
	cp $(EXEC).hex ../$(EXEC).hex
	cp $(EXEC)_d.hex ../$(EXEC)_d.hex

check: $(EXEC).elf
	@echo "--- 入口 ---"
	@sed -n '1,12p' $(EXEC).dump
	@echo "--- main.hex 段地址 ---"
	@grep '@' ../$(EXEC).hex
	@echo "--- main_d.hex 字地址 ---"
	@grep '@' ../$(EXEC)_d.hex

clean:
	rm -f *.o *.elf *.dump *.tmp *.hex *.pad
	rm -f ../$(EXEC).hex ../$(EXEC)_d.hex
