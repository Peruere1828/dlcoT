# AGENTS.md

This is a **hardware/FPGA lab course** (数字逻辑与计算机组成), not a software repo. You write Verilog, verify it in Xilinx Vivado, and flash it onto a physical board. "Verification" here means Vivado simulation + on-board hardware test; there is no build server. A `iverilog` Docker image is available for quick pre-checks (see below), but it is **not** a substitute for Vivado.

## Toolchain (exact versions matter)
- **Vivado 2022.1** only, on another machine.
- Board: **Digilent Nexys A7-100T** (was Nexys 4 DDR). FPGA = Xilinx Artix-7 `XC7A100T-1CSG324C`.

### Self-check with iverilog (Docker)
A local Docker image `iverilog:12` is available. Use it for **fast syntax + behavioral pre-checks** before handing code to the user. Compile the design together with a testbench and run it:

```bash
docker run --rm -v "$PWD":/work -w /work iverilog:12 \
  sh -c "iverilog -g2012 -Wall -o /tmp/sim.out design.v design_tb.v && vvp /tmp/sim.out"
```

- `-g2012` enables SystemVerilog-2012 constructs; `-Wall` surfaces width/undeclared warnings.
- Output goes to `/tmp/sim.out` **inside the container** so no root-owned files land in the repo.
- Escape hatches: pass `--user "$(id -u):$(id -g)"` if you must write files into the mounted repo.
- Limitations: iverilog does **not** do synthesis, so it cannot flag inferred latches (`Synth 8-373`), multi-driven nets at implementation, or Xilinx primitives/IP. Treat a green iverilog run as a *pre-check only*; the authoritative sim is Vivado behavioral simulation, and the final check is the board.

## Reading the lab PDFs
Lab PDFs are probably not suitable for the assistant to read directly, so only pypdf-extracted text is available. Treat that extracted text as reference only; for specifics, ask the user for more information. The user reads the PDF and relays the requirements in Chinese — treat the relayed text as the authoritative spec for each lab.

## Vivado flow order (do not skip steps)
Design (RTL) → add constraints (XDC pin map) → **Run Behavioral Simulation** → Synthesize → Implementation → Generate Bitstream → Program Device (Hardware Manager).
- Re-run simulation after any design change; "sim passes, board fails" is a common, real failure mode (often an inferred latch — see below).
- Board is only detected over USB **after its power switch is turned on**. If not found: swap cable, try a lab machine, or ask the instructor to replace the board.

## Per-lab workflow (user-driven, do not skip stages)
0. **Functional simulation first** — every sub-experiment that is verified on the board gets a self-checking testbench `<top>_tb.v` in the same exp folder (write it only for the **board top**, not for OJ modules). Style: a few representative selected cases only (must fit Vivado's 1000ns default sim time — **no exhaustive sweeps**), `$display` each mismatch, end with `TEST PASSED`/`TEST FAILED` + `$finish`. You may run this testbench with iverilog (Docker) first to catch syntax/logic errors; the user then runs it in Vivado behavioral simulation (tb as sim top) before OJ and before flashing.
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

## 七段数码管段码
Nexys A7-100T 的数码管为**共阳极、低电平点亮**。本仓库统一约定 `seg[6:0] = {G,F,E,D,C,B,A}`；接 `HEX` 时用 `HEX = {seg, DP}`（HEX[7]=G … HEX[1]=A、HEX[0]=DP），小数点不需要时置 `1'b1` 熄灭。位选 `AN[n]=0` 选中第 n 位数码管。参考如下段码：

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
- **标点规范：** 中文正文一律用全角标点（，。；：？！）和全角引号“ ”；英文文本用半角引号 `" "`。不要中英文混用半角标点。
- **数学公式规范：** 所有数学公式使用 Latex，并用 `$$` 或 `$$$$` 括起
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
- `labNN/assets/` — lab report figures: screenshots of simulation waveforms (`expN_simulation.png`) and synthesized schematics (`expN_schematic.png`). Reference from the report with a relative path `![caption](assets/expN_xxx.png)`. Always keep the pictures' filename as `expN_xxx.png`.
- The lab PDF stays at `labNN/`.
Do NOT drop files loose in `labNN/` root; keep the OJ module and the board top as **separate files** in the same `expN_name/` folder when they differ. Report lives at `labNN/labNN实验报告.md`.

## Per-lab pitfalls
See `lab00/实验问题指导.md` for detailed gotchas per lab (latch debugging, lab02 overflow/carry in subtraction, lab03 100kHz scan rate, lab09 RAM 32-bit read-modify-write, lab10 single-cycle CPU timing/`nextpc` init, lab12 BRAM "output register" must be unchecked, etc.).
