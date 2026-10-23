# 原始课程 testbench（仅作参考）

- `cpu_step.v`：课程提供的单步 testbench，含 `add`、`alu`、`mem`、`branch` 四段程序的逐条检查。
- `cpu_batch.v`：课程提供的官方测试集 testbench，顺序运行 rv32ui-p-* 用例。

实际仿真使用上一级的自检版本：

- `../rv32is_tb.v`：由 `cpu_step.v` 改写，出错时打印 MISMATCH，最后输出 TEST PASSED/FAILED。
- `../cpu_batch_tb.v`：由 `cpu_batch.v` 改写，增加通过/失败计数和最终汇总。

这两个文件不参与综合，上板只用 `lab09/exp2_board/cpu_top.v` 和 `cpu_top.xdc`。
