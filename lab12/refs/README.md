# lab12 参考资料索引

本目录把 `lab12/` 下原有压缩包和 docx 的内容整理成 Markdown，原件删除后仍可查阅。`lab12.pdf` 和 `labextend.pdf` 保留，不在本目录重复。

## 文件

| 文件 | 来源 | 用途 |
| :--- | :--- | :--- |
| `01_串口通信与加密解密.md` | `实验12 串口通信及加密解密.docx`、`uart_debug.zip` | UART 原理与代码、`uart_port` 调试器、LFSR 加解密实验 |
| `02_音频输出实验.md` | `实验11音频输出实验.docx`、`sound_source.zip` | PWM 音频、正弦表、音调选择、参考 RTL |
| `03_参考板级设计与RTL.md` | `student-board-design-min.zip` | 旧 n4-riscv 板级 Block Design、地址映射、时钟、AXI 外设与关键 RTL |
| `04_软件工具链与示例程序.md` | `software.zip` | RISC-V C 编译流程、Makefile、链接脚本、Hello World |
| `05_系统扩展指导.md` | `labextend-ai.zip`、`labextend.pdf` | 扩展指导书正文 |
| `06_lab12指导书要点.md` | `lab12.pdf` | 手册正文按章节整理：硬件、软件、调试、验收 |
| `assets/` | 上述 docx 与 zip | 图片：ASCII 表、DB9、FT2232 接线、PWM 波形、参考 Block Design |

## 阅读顺序

1. `PLAN.md`：先看总体设计和阶段计划。
2. `lab12.pdf`：实验目标、内存映射、验收要求；`06_lab12指导书要点.md` 是同一内容的文字整理，便于检索。
3. `04`：先搭好编译环境，编译出可用的 `.hex`。
4. `03`：需要参考 VGA、键盘、AXI、DDR、QSPI 时查。
5. `01`、`02`：做串口调试和音频扩展时查。
6. `05`：规划加分项时查。

## 出处与可信度

- `01`、`02` 的正文来自课程 docx，代码来自课程 zip；这两份是实验指导性质，不是最终验收标准，验收以 `lab12.pdf` 12.5 和老师要求为准。
- `03` 的原始工程是 2021 级的 n4-riscv，CPU 是 RV64，板级工程的 Block Design 还带有 2019.1 的版本痕迹。它只能作为接口和参数参考，不能直接综合。
- `04` 的 Makefile 与 `sections.ld` 直接来自课程示例，地址约定与 `lab12.pdf` 一致。
- `05` 是 `labextend.pdf` 的 Markdown 版本，内容和 PDF 一致。

## 图片

| 文件 | 说明 |
| :--- | :--- |
| `assets/ascii_table.png` | USASCII 字符编码表，串口实验和软件字符处理用 |
| `assets/rs232_db9.png` | DB9 串口接头公母头引脚编号 |
| `assets/uart_ft2232.png` | Nexys A7 上 FT2232 与 FPGA 的 UART 引脚连接 |
| `assets/pwm_waveform.png` | PWM 数字波形经低通滤波得到模拟波形 |
| `assets/design_1.png` | 旧 n4-riscv 的 CPU 系统 Block Design 位图 |
| `assets/design_1.pdf` | 同一 Block Design 的矢量图，可放大看连线 |

## 未转换的图

docx 里还有几个 EMF 矢量图，分别是串口帧结构、加密流程、音频系统框图和音频滤波电路。这些图没有合适的转换工具，未导出为图片；串口帧结构和加密流程在 `01` 的正文里有文字说明，帧结构也可对照 `lab12.pdf` 图 12-4，音频系统框图在 `02` 第 3 节按模块描述。
