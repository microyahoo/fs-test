#!/bin/bash
#
# mdtest 多目录并发元数据测试（MPI 版）
#
# 关键前提（务必先满足，否则会退化成 N 个独立的单进程 mdtest，
# 全部 rank=0、全挤进 test-dir.0-0，产生海量 race-condition WARNING）：
#   1. 所有节点安装的是【带 MPI 的 mdtest】，且是同一份/同一路径。
#      验证: ldd $(which mdtest) | grep -i mpi   # 应能看到 libmpi*
#   2. mpirun 与 mdtest 来自同一套 MPI（Open MPI / MPICH 不要混）。
#   3. --mca btl_tcp_if_include 指定的网卡名在所有节点都存在。

set -eu

nodes_file=./nodeslist
TARGET=/training-vepfs-new/mm/xxx/zl/fio/dir1/dir2/dir3/dir4/dir5/dir6/dir7/mdtest

# 用于 MPI 进程间通信的网卡：改成各节点真实存在的接口名（如 bond4 / eth0）
IFACE=eth0

DEPTH=1          # 树深度
WIDTH=320        # 每个 rank 的分支数（= 每个 rank 的叶子目录数）
num_files=1000000
num_procs=480

# 每个叶子目录里的文件数。
# 总文件数 = num_procs * WIDTH * files_per_dir
# 反推: files_per_dir = num_files / num_procs / WIDTH
files_per_dir=$(( num_files / num_procs / WIDTH ))
[ "$files_per_dir" -lt 1 ] && files_per_dir=1

actual_total=$(( num_procs * WIDTH * files_per_dir ))
echo ">>> num_procs=$num_procs  WIDTH=$WIDTH  files_per_dir=$files_per_dir"
echo ">>> 实际总文件数 ≈ $actual_total （目标 $num_files，整数截断导致的偏差属正常）"

# --- 启动前自检：确认 mpirun 是 Open MPI、mdtest 链接 Open MPI ---
# 本脚本用的是 Open MPI 专有参数（--allow-run-as-root / --mca / -map-by）。
# 若 mpirun 是 MPICH/Hydra，会报 "unrecognized argument allow-run-as-root"，
# 此时请先用 ./install_openmpi_mdtest.sh 把所有节点统一成 Open MPI。
if command -v mpirun >/dev/null; then
    if ! mpirun --version 2>&1 | head -1 | grep -qi "open mpi"; then
        echo "错误: 本机 mpirun 不是 Open MPI（可能是 MPICH/Hydra）。"
        echo "      本脚本的参数仅 Open MPI 支持，请先运行 ./install_openmpi_mdtest.sh。"
        exit 1
    fi
fi
if command -v ldd >/dev/null && command -v mdtest >/dev/null; then
    if ! ldd "$(command -v mdtest)" 2>/dev/null | grep -qi "libmpi\."; then
        echo "警告: 本机 mdtest 似乎未链接 Open MPI 库 —— 跨节点会退化成各自 rank=0。"
        echo "      请确认所有节点用的是 Open MPI 编译的 mdtest。"
    fi
fi

# Ubuntu 22.04 / Open MPI 4.1 走 TCP：
#   --mca btl tcp,self            只用 TCP 与本地回环，禁用 openib/vader 之外的传输
#   --mca btl_tcp_if_include      指定 TCP 网卡（白名单）
#   --mca pml ob1                 配合纯 TCP，避免 UCX 在无 IB 环境下报错
#   --mca btl_openib_allow_ib 0   彻底关掉 IB，消除 openib 相关 WARNING
mpirun --allow-run-as-root \
    --mca btl tcp,self \
    --mca btl_tcp_if_include "$IFACE" \
    --mca pml ob1 \
    --mca btl_openib_allow_ib 0 \
    -hostfile "$nodes_file" \
    -map-by node \
    -np "${num_procs}" \
    mdtest -d "$TARGET" \
        -i 1 \
        -I "${files_per_dir}" \
        -z "${DEPTH}" \
        -b "${WIDTH}" \
        -L -T -F -u -w 0 -r -C
