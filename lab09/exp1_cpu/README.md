# exp1_cpu — 单周期 RV32I CPU（两个 OJ 共用的单文件）

在线评测的两个题目（单周期功能测试、单周期 CPU 官方测试）提交同一个文件：

- **`rv32is.v`**

它把 `rv32is` 和 `rv32i_regfile` 两个模块放在一个文件里，满足 OJ 的单文件要求。

## 功能仿真

| 文件 | 作用 |
| :--- | :--- |
| `rv32is.v` | 被测 CPU |
| `dmem.v`、`testmem.v`、`testdmem.v` | 课程提供的存储器模型 |
| `rv32is_tb.v` | 单步自检，覆盖 add/alu/mem/branch |
| `cpu_batch_tb.v` | 官方 rv32ui-p 38 个用例 |
| `tests/` | 官方测试 hex 与单步测试 hex，共 82 个 |
| `course_tb/` | 原始课程 testbench，仅作参考，不参与综合 |

Vivado 仿真前把 `tests/` 目录拷贝到仿真工作目录
`工程名.sim/sim_1/behav/xsim/`，因为 `$readmemh` 的相对路径按仿真工作目录解析。

本地快速预检查：

```bash
# 单步
docker run --rm -v "$PWD":/work -w /work iverilog:12 \
  sh -c "iverilog -g2012 -o /tmp/a.out rv32is.v dmem.v testmem.v testdmem.v rv32is_tb.v && vvp /tmp/a.out"

# 官方测试集
docker run --rm -v "$PWD":/work -w /work iverilog:12 \
  sh -c "iverilog -g2012 -o /tmp/b.out rv32is.v dmem.v testmem.v testdmem.v cpu_batch_tb.v && vvp /tmp/b.out"
```

上板工程在 `../exp2_board/`。
