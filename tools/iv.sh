#!/usr/bin/env bash
# 用 docker 里的 iverilog 编译并运行某个实验目录下的仿真。
# 用法: tools/iv.sh <相对仓库根的目录> <仿真顶层模块名>
# 例:   tools/iv.sh lab09/exp2_alu alu_tb
#       tools/iv.sh tools/iverilog/smoke adder_tb
set -euo pipefail

image="${IV_IMAGE:-iverilog:12}"
root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

if [ $# -lt 2 ]; then
    echo "usage: $(basename "$0") <subdir> <top_module>" >&2
    echo "  e.g. $(basename "$0") lab09/exp2_alu alu_tb" >&2
    exit 2
fi

sub="$1"
top="$2"

docker run --rm \
    -u "$(id -u):$(id -g)" \
    -e HOME=/tmp \
    -v "$root":/work \
    -w "/work/$sub" \
    "$image" \
    bash -lc "iverilog -g2005 -s $top -o /tmp/$top.vvp ./*.v && vvp /tmp/$top.vvp"
