# AGENTS.md

This is a **hardware/FPGA lab course** (数字逻辑与计算机组成), not a software repo. You write Verilog, verify it in Xilinx Vivado, and flash it onto a physical board. There is no build server or test runner here; "verification" = Vivado simulation + on-board hardware test.

## Toolchain (exact versions matter)
- **Vivado 2022.1** only. Newer/older versions may break constraints, IP, or flow.
- Board: **Digilent Nexys A7-100T** (was Nexys 4 DDR). FPGA = Xilinx Artix-7 `XC7A100T-1CSG324C`.
- Install & project paths must contain **no Chinese characters**. Vivado quietly breaks on them.

## Reading the lab PDFs
All PDFs are readable with `pypdf` (already installed). Dump a PDF to text:
```bash
python3 -c "from pypdf import PdfReader; r=PdfReader('lab00/lab00.pdf'); print('\n'.join((p.extract_text() or '') for p in r.pages))"
```
Caveat: some Chinese glyphs come out garbled in extraction. The readable Chinese guide is `lab00/实验问题指导.md` — prefer it over the PDFs for narrative/per-lab gotchas.

## Vivado flow order (do not skip steps)
Design (RTL) → add constraints (XDC pin map) → **Run Behavioral Simulation** → Synthesize → Implementation → Generate Bitstream → Program Device (Hardware Manager).
- Re-run simulation after any design change; "sim passes, board fails" is a common, real failure mode (often an inferred latch — see below).
- Board is only detected over USB **after its power switch is turned on**. If not found: swap cable, try a lab machine, or ask the instructor to replace the board.

## Per-lab workflow (user-driven, do not skip stages)
1. **Write the `.v` design** — port list only, no pin info. The user then submits it to the **online judge (OJ)**; iterate until it passes. The OJ has its own testbench and port definitions — match the module name/ports the OJ expects.
2. **Only after OJ passes**, write the **constraint (XDC) file** from `ref.xdc` (repo-root pin map, do not modify it; copy pins from there). Then the user flashes the board.
3. **After board test passes**, write the **lab report**.

## CRITICAL hardware rule
Pin assignment in the XDC file **must match the Nexys A7-100T pinout** (SW0=J15, LD0=H17, etc.). Wrong pins can cause **shorts that physically damage the chip**. Never guess pin numbers — copy from `ref.xdc` / the board manual.

## Lab report template (Chinese, one per lab)
Sections: **1. 实验目的** · **2. 实验原理** · **3. 实验设备** · **4. 实验步骤** · **5. 实验结果** · **6. 思考题** (only if the manual has one). Fill in the actual OJ + board results; describe the design (module structure, I/O wiring to SW/LED).

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

## Per-lab pitfalls
See `lab00/实验问题指导.md` for detailed gotchas per lab (latch debugging, lab02 overflow/carry in subtraction, lab03 100kHz scan rate, lab08 RAM 32-bit read-modify-write, lab09 single-cycle CPU timing/`nextpc` init, lab12 BRAM "output register" must be unchecked, etc.).
