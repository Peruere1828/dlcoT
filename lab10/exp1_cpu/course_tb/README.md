# 原始课程 testbench（仅作参考）

- `cpu_step.v`：课程提供的单步 testbench，含 `add`、`alu`、`mem`、`branch` 四段程序的逐条检查。

实际仿真使用上一级的自检版本：

- `../rv32ip_tb.v`：由 `cpu_step.v` 改写，检查序列完全相同，出错时打印 MISMATCH，最后输出 TEST PASSED/FAILED。
- `../rv32ip_hazard_tb.v`：冒险边界情况自检。
- `../cpu_batch_tb.v`：官方 rv32ui-p 38 个用例。

这三个文件都不参与综合。上板只用 `../exp2_board/` 下的 `cpu_top.v`、`rv32ip.v`、`prog_rom.v`、`board_dmem.v`、`prog.hex` 和 `cpu_top.xdc`。

直接用 `cpu_step.v` 跑时，它从当前工作目录读 `add.hex` 等文件，
所以要么在 `exp1_cpu` 目录下运行并把 `tests/` 里的四个 hex 拷过来，
要么把 `$readmemh` 的路径改成 `tests/`。
