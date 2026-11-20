ENTRY(entry)
OUTPUT_FORMAT("elf32-littleriscv")

/* 代码段从 0x0000_0000 开始, entry 放在最前面
 * 数据段从 0x0010_0000 开始, 与 dmem 的 addr[16:2] 索引对齐
 * 栈顶在数据存储器最高地址 0x0011_FFFC, entry 里用 lui/addi 设置
 */
SECTIONS
{
    . = 0x00000000;
    .text : {
        *(entry)
        main.o (.text)
        *(.text*)
        *(text_end)
    }
    etext = .;
    _etext = .;

    . = 0x00100000;
    .rodata : {
        *(.rodata*)
    }
    .data : {
        *(.data)
    }
    edata = .;
    _data = .;

    .bss : {
        _bss_start = .;
        *(.bss*)
        *(.sbss*)
        *(.scommon)
    }
    _bss_end = .;

    _stack_pointer = 0x0011FFFC;
    end = .;
    _end = .;
}
