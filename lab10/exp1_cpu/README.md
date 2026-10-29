# exp1_cpu — 五段流水线 RV32I CPU（两个 OJ 共用的单文件）

在线评测的两个题目（流水线功能测试、流水线 CPU 官方测试）提交同一个文件：

- **`rv32ip.v`**

它把 `rv32ip` 和 `rv32i_regfile` 两个模块放在一个文件里，满足 OJ 的单文件要求。
端口与课程 testbench 一致；寄存器堆实例名保持 `myregfile`、数组名保持 `regs`，
因为课程 testbench 里用 `mycpu.myregfile.regs[x]` 读寄存器。

## 功能仿真

| 文件 | 作用 |
| :--- | :--- |
| `rv32ip.v` | 被测 CPU |
| `dmem.v`、`testmem.v`、`testdmem.v` | 课程提供的存储器模型 |
| `rv32ip_tb.v` | 单步自检，检查序列与课程 `cpu_step.v` 完全一致，覆盖 add/alu/mem/branch |
| `rv32ip_hazard_tb.v` | 冒险边界情况自检，程序见 `tests/hazard.S` |
| `cpu_batch_tb.v` | 官方 rv32ui-p 38 个用例 |
| `tests/` | 官方测试 hex、四段单步测试 hex、冒险测试 hex 与源码 |
| `course_tb/cpu_step.v` | 原始课程单步 testbench，仅作参考，不参与综合 |

Vivado 仿真前把 `tests/` 目录拷贝到仿真工作目录
`工程名.sim/sim_1/behav/xsim/`，因为 `$readmemh` 的相对路径按仿真工作目录解析。

本地快速预检查：

```bash
# 单步
docker run --rm -v "$PWD":/work -w /work iverilog:12 \
  sh -c "iverilog -g2012 -o /tmp/a.out rv32ip.v dmem.v testmem.v testdmem.v rv32ip_tb.v && vvp /tmp/a.out"

# 冒险边界
docker run --rm -v "$PWD":/work -w /work iverilog:12 \
  sh -c "iverilog -g2012 -o /tmp/h.out rv32ip.v dmem.v testmem.v testdmem.v rv32ip_hazard_tb.v && vvp /tmp/h.out"

# 官方测试集
docker run --rm -v "$PWD":/work -w /work iverilog:12 \
  sh -c "iverilog -g2012 -o /tmp/b.out rv32ip.v dmem.v testmem.v testdmem.v cpu_batch_tb.v && vvp /tmp/b.out"
```

`rv32ui-p-fence_i` 不在批量测试列表里：它把指令写进存储器再执行，需要统一的
指令/数据存储器和 `fence.i` 语义，本设计的指令存储器是只读的，无法支持。

上板工程在 `../exp2_board/`。
