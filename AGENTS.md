# AGENTS.md

This is a **hardware/FPGA lab course** (数字逻辑与计算机组成), not a software repo. You write Verilog, verify it in Xilinx Vivado, and flash it onto a physical board. There is no build server or test runner here; "verification" = Vivado simulation + on-board hardware test.

## Toolchain (exact versions matter)
- **Vivado 2022.1** only. Newer/older versions may break constraints, IP, or flow.
- Board: **Digilent Nexys A7-100T** (was Nexys 4 DDR). FPGA = Xilinx Artix-7 `XC7A100T-1CSG324C`.
- Install & project paths must contain **no Chinese characters**. Vivado quietly breaks on them.
- **This machine has NO Verilog toolchain** (no Vivado / iverilog / verilator). The assistant cannot compile, run, or lint any `.v` file locally — all verification (behavioral sim, synth) happens in the user's Vivado. Write code that is correct first time; the user runs every testbench in Vivado.

## Reading the lab PDFs
The lab PDFs are **not suitable for the assistant to read directly**: Chinese glyphs come out garbled (e.g. 选择器 → 㫍㵗㋹), so do NOT rely on pypdf extraction for requirements. The **user reads the PDF and relays the requirements in Chinese** — treat the user's relayed text as the authoritative spec for each lab.

If you still need a dump (e.g. for English figures/code/tables):
```bash
python3 -c "from pypdf import PdfReader; r=PdfReader('lab00/lab00.pdf'); print('\n'.join((p.extract_text() or '') for p in r.pages))"
```
Caveat: Chinese glyphs garble; trust only the readable parts (code, tables, English). The readable Chinese guide is `lab00/实验问题指导.md` — prefer it over the PDFs for narrative/per-lab gotchas.

## Vivado flow order (do not skip steps)
Design (RTL) → add constraints (XDC pin map) → **Run Behavioral Simulation** → Synthesize → Implementation → Generate Bitstream → Program Device (Hardware Manager).
- Re-run simulation after any design change; "sim passes, board fails" is a common, real failure mode (often an inferred latch — see below).
- Board is only detected over USB **after its power switch is turned on**. If not found: swap cable, try a lab machine, or ask the instructor to replace the board.

## Per-lab workflow (user-driven, do not skip stages)
0. **Functional simulation first** — every sub-experiment that is verified on the board gets a self-checking testbench `<top>_tb.v` in the same exp folder (write it only for the **board top**, not for OJ modules). Style: a few representative selected cases only (must fit Vivado's 1000ns default sim time — **no exhaustive sweeps**), `$display` each mismatch, end with `TEST PASSED`/`TEST FAILED` + `$finish`. The user runs it in Vivado behavioral simulation (tb as sim top) before OJ and before flashing. The user verifies locally; the assistant cannot run sim.
1. **Write the `.v` design** — port list only, no pin info. The user then submits it to the **online judge (OJ)**; iterate until it passes. The OJ has its own testbench and port definitions — match the module name/ports the OJ expects.
2. **Only after OJ passes**, write the **constraint (XDC) file** from `ref.xdc` (repo-root pin map, do not modify it; copy pins from there). Then the user flashes the board.
3. **After board test passes**, write the **lab report**.

### Board top module MUST be self-contained (single file)
The user evaluates by **completely clearing the Vivado project, adding ONLY the assistant's `.v` file(s) + `.xdc`, then compile + flash** — nothing else. So the board top must:
- Be **one standalone module in one `.v` file** — all submodules (decoder, mux, encoder, …) inlined or in the same file, **zero dependency on any other file** (no separate OJ module needed for board builds).
- Match the XDC port names exactly (that `.v` + `.xdc` pair must build and flash alone).
- If the OJ module and the board top differ, keep them as **separate files**: the OJ design file stays as-is for OJ submission; the board gets its own self-contained top file.

## User evaluation flow (for guiding the user)
1. User clears all previous project content, adds the assistant's code files + XDC, sets top module, runs synthesis → implementation → generate bitstream → program board.
2. Board behavior is checked against the lab manual; mismatches (e.g. wrong switch mapping) usually mean the XDC didn't match the manual or wasn't re-flashed.
3. OJ and board are separate checks — passing one does not mean the other passes.

## CRITICAL hardware rule
Pin assignment in the XDC file **must match the Nexys A7-100T pinout** (SW0=J15, LD0=H17, etc.). Wrong pins can cause **shorts that physically damage the chip**. Never guess pin numbers — copy from `ref.xdc` / the board manual.

## 七段数码管段码（易错，务必照抄，勿手推）
Nexys A7-100T 的数码管为**共阳极、低电平点亮**。本仓库统一约定 `seg[6:0] = {G,F,E,D,C,B,A}`，bit6=G … bit0=A；接 `HEX` 时用 `HEX = {seg, DP}`（HEX[7]=G … HEX[1]=A、HEX[0]=DP），小数点不需要时置 `1'b1` 熄灭。位选 `AN[n]=0` 选中第 n 位数码管。

**历史坑 1：`f` 字形左右镜像。** 根因是把段码位序写反，当成 `{A,B,C,D,E,F,G}` 来写。左右镜像最直观的表现就是 `f`：正确段码是 `7'b0001110`，一旦写成它的位反 `7'b0111000`，板面上就是镜像的 f（其余非对称数字也会看起来镜像）。

**历史坑 2：`E` 的段码写成 `7'b0001100`。** 这是把 `E` 和别的位搞混：`7'b0001100` 只点亮 D、C 两段，根本不是合法字形。`E` 正确是 `7'b0000110`（点亮 A、D、E、F、G，B、C 熄灭）。lab04/05/06/10/11 都曾抄错这一行。

**每写一个新译码器都从下表原样复制，不要再凭记忆手推。**

| 字符 | seg[6:0] | 十六进制 |
|------|----------|----------|
| 0 | `7'b1000000` | `0x40` |
| 1 | `7'b1111001` | `0x79` |
| 2 | `7'b0100100` | `0x24` |
| 3 | `7'b0110000` | `0x30` |
| 4 | `7'b0011001` | `0x19` |
| 5 | `7'b0010010` | `0x12` |
| 6 | `7'b0000010` | `0x02` |
| 7 | `7'b1111000` | `0x78` |
| 8 | `7'b0000000` | `0x00` |
| 9 | `7'b0010000` | `0x10` |
| A | `7'b0001000` | `0x08` |
| b | `7'b0000011` | `0x03` |
| C | `7'b1000110` | `0x46` |
| d | `7'b0100001` | `0x21` |
| E | `7'b0000110` | `0x06` |
| F | `7'b0001110` | `0x0E` |

## Lab report template (Chinese, one per lab)
Sections: **1. 实验目的** · **2. 实验原理** · **3. 实验设备** · **4. 实验步骤** · **5. 实验结果** · **6. 思考题** (only if the manual requires) · **个人思考** (always last). Fill in the actual OJ + board results; describe the design (module structure, I/O wiring to SW/LED).

### Report style rules
- **Do NOT put （OJ）/（上板）tags in the report** — not in section headings (`### 4.1 ...（OJ）`) nor in result subsection titles. OJ/上板 is workflow metadata, not report content; just state results normally (e.g. "在线评测通过").
- **Minimize parenthesized asides （）in general.** Rewrite them inline (e.g. "动态（扫描）显示" → "动态扫描显示", "（周期 10ns）" → "周期 10ns 的 …"). Keep parens only where they carry real info that reads badly inline (pin locations like `CLK100MHZ`（E3）, parameter overrides, component models). lab04 报告是正面范例，继续保持。
- **标点规范。** 中文正文一律用全角标点（，。；：？！）和全角引号“ ”；英文文本用半角引号 `" "`。不要中英文混用半角标点。
- **每个报告最后必须有一节「个人思考」。** 用真人第一人称、口语化的语气，简单总结本次实验的收获与教训，例如踩到的坑、如何定位、对硬件设计的新认识。不要写成模板套话，不要重复前文实验步骤。
- **思考题 section is NOT unconditional.** If the lab manual has no 思考题, omit the `## 6. 思考题` section entirely — never emit a placeholder like "（本实验手册未列出思考题。）". Check each lab's manual first.

## Verilog conventions (differ from software defaults)
- Think in **circuit diagrams**, not code. Except in testbenches, **do not use `for`/`while`** in synthesizable code.
- **Avoid inferred latches**: give every combinational `case` a `default` and every `if` an `else`. Latches are a top cause of "sim pass, board fail".
- **Warnings are dangerous here.** Vivado does NOT stop on them and they get buried among hundreds. Treat these as real errors:
  - `Synth 8-689` width mismatch (causes `z`/`x` in sim)
  - `Synth 8-373` inferring latch
  - `Synth 8-6859` multi-driven net (signal driven by >1 always/assign) / timing loop (combinational loop)
  - `Synth 8-151` unreachable case (often a typo'd variable silently treated as 1-bit wire)
- `wire` vs `reg`: only assign `reg` in **one** always block, driven by a single edge (handle reset as the first condition). Init `reg` in simulation.
- Don't use `reg[][]` as a 2D array / RAM; use a real RAM module, one read/write per cycle, no partial-bit writes.
- OJ (online judge) definitions sometimes differ from the on-board definitions — verify which target you're building for.

## Repo layout / per-lab directory convention (from lab01/lab02 experience)
Keep each lab self-contained under `labNN/`, one **`expN_name/` subdirectory per exercise**, mirroring the lab manual's exercise numbering:
- `labNN/exp1_adder/adder.v` — OJ submission module (exact OJ port list, no pins)
- `labNN/exp2_alu/alu_s.v` — OJ module
- `labNN/exp2_alu/alu_top.v` — **separate, self-contained board top** (all submodules inlined in this one file)
- `labNN/exp2_alu/alu_top.xdc` — board pin map for that top
- `labNN/exp2_alu/alu_top_tb.v` — self-checking functional simulation testbench for the board top (same folder, `<top>_tb.v` naming; one per board-bound exercise)
- `labNN/assets/` — lab report figures: screenshots of simulation waveforms (`expN_simulation.png`) and synthesized schematics (`expN_schematic.png`). PDFs can't be inlined in Markdown, so always save screenshots as PNG (Vivado screenshot / Win+Shift+S / PDF viewer screenshot). Reference from the report with a relative path `![caption](assets/expN_xxx.png)`.
- The lab PDF stays at `labNN/`.
Do NOT drop files loose in `labNN/` root; keep the OJ module and the board top as **separate files** in the same `expN_name/` folder when they differ. Report lives at `labNN/labNN实验报告.md`.

## Lab numbering (current, matches this repo's PDFs)
The lab PDFs under `labNN/` define the authoritative numbering:
- **lab08 字符输入界面** — ASCII 字模 ROM + 字符显存 + 键盘回显
- **lab09 CPU 数据通路** — RV32I 寄存器堆 / ALU / 数据存储器
- **lab10 单周期 CPU** — RV32I（37 条指令）
- **lab11 五段流水线 CPU** — 前转与 load-use 阻塞
- **lab12 计算机系统** — 内存映射外设 + C 软件 + UART 调试

`lab00/实验问题指导.md` 的 per-lab 小节是**旧编号**（CPU 数据通路记作 lab08、单周期记作 lab09、流水线记作 lab10、字符输入界面记作 lab11）。内容仍然适用，但编号要按上表平移，不要照抄。

## Per-lab pitfalls
See `lab00/实验问题指导.md` for detailed gotchas per lab (latch debugging, lab02 overflow/carry in subtraction, lab03 100kHz scan rate, lab09 RAM 32-bit read-modify-write, lab10 single-cycle CPU timing/`nextpc` init, lab12 BRAM "output register" must be unchecked, etc.).
