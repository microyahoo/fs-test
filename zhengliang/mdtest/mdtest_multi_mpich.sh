#!/bin/bash
#
# mdtest 多目录并发元数据测试 —— MPICH / Hydra 版
#
# 你的 mdtest 链接的是 libmpich.so.12（MPICH 系），所以必须用 MPICH 配套的
# mpirun/mpiexec.hydra，且不能用 Open MPI 的 --mca / -map-by 等参数。
#
# 启动前务必确认 mpirun 与 mdtest 同源：
#   which mpirun && mpirun --version | head -1   # 应显示 HYDRA / MPICH，而非 Open MPI
#   ldd $(which mdtest) | grep -i mpi            # libmpich.so.12

set -eu

nodes_file=./nodeslist
TARGET=/training-vepfs-new/mm/xxx/zl/fio/dir1/dir2/dir3/dir4/dir5/dir6/dir7/mdtest

# 用于 MPI 通信的网卡名（各节点都要存在），MPICH 通过环境变量指定
IFACE=eth0

DEPTH=1
WIDTH=320
num_files=1000000
num_procs=480

files_per_dir=$(( num_files / num_procs / WIDTH ))
[ "$files_per_dir" -lt 1 ] && files_per_dir=1
actual_total=$(( num_procs * WIDTH * files_per_dir ))
echo ">>> num_procs=$num_procs WIDTH=$WIDTH files_per_dir=$files_per_dir 实际总文件≈$actual_total"

# MPICH/Hydra 指定网卡用环境变量，而不是 Open MPI 的 --mca
export MPIR_CVAR_CH3_INTERFACE_HOSTNAME=   # 如需可按节点设置，一般留空
export MPICH_NEMESIS_NETMOD=tcp

# -iface 让 Hydra 选定 TCP 网卡；-f 指定 hostfile
mpirun \
    -iface "$IFACE" \
    -f "$nodes_file" \
    -np "${num_procs}" \
    mdtest -d "$TARGET" \
        -i 1 \
        -I "${files_per_dir}" \
        -z "${DEPTH}" \
        -b "${WIDTH}" \
        -L -T -F -u -w 0 -r -C
