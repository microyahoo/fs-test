#!/bin/bash
#
# 在 nodeslist 列出的所有节点上并发安装统一的 Open MPI 环境，
# 并编译链接 Open MPI 的 mdtest（IOR 套件）。
#
# 适用系统：Ubuntu 22.04（openmpi-bin = Open MPI 4.1.2）
#
# 为什么用 Open MPI 而不是 MPICH：
#   你的运行脚本 mdtest_multi.sh 用的是 Open MPI 专有参数
#   （--allow-run-as-root / --mca / -map-by），MPICH 的 mpiexec.hydra
#   不认识这些参数，会报 "unrecognized argument allow-run-as-root"。
#   本脚本把所有节点统一成 Open MPI，从根上消除混用。
#
# 前提：本机到所有节点已免密 ssh（见 setup_fullmesh_ssh_parallel.sh）。
# 用法: ./install_openmpi_mdtest.sh [并发度]    并发度默认 30
#
# 说明：本脚本负责在各节点 apt 安装 Open MPI 并编译安装 mdtest。
#       若节点无外网，请改为分发预编译好的二进制（见脚本末注释）。

set -u

NODES_FILE="./nodeslist"
PARALLEL="${1:-30}"
SSH_OPTS="-o ConnectTimeout=10 -o StrictHostKeyChecking=no -o BatchMode=yes"
IOR_REPO="https://github.com/hpc/ior.git"

if [ ! -f "$NODES_FILE" ]; then
    echo "错误: 找不到 $NODES_FILE"
    exit 1
fi
mapfile -t nodes < <(grep -v '^[[:space:]]*$' "$NODES_FILE")
echo ">>> 共 ${#nodes[@]} 个节点，最大并发 $PARALLEL"

WORKDIR="$(mktemp -d)"
trap 'rm -rf "$WORKDIR"' EXIT

# 在每个节点上执行的安装命令
REMOTE_CMD='
set -e
export DEBIAN_FRONTEND=noninteractive
# 1. 卸 MPICH，装 Open MPI + 编译工具
apt-get remove -y mpich libmpich-dev 2>/dev/null || true
apt-get update -y
apt-get install -y openmpi-bin libopenmpi-dev build-essential autoconf automake libtool git
# 2. 校验 mpirun 已是 Open MPI（而不是 MPICH/HYDRA）
mpirun --version 2>&1 | head -1 | grep -qi "open mpi" || { echo "ERR: mpirun 仍非 Open MPI"; exit 1; }
# 3. 编译安装 mdtest（IOR 套件），用 Open MPI 的 mpicc
rm -rf /tmp/ior_build && git clone --depth 1 '"$IOR_REPO"' /tmp/ior_build
cd /tmp/ior_build
./configure CC=mpicc MPICC=mpicc --prefix=/usr/local
make -j$(nproc)
make install
ldconfig
# 4. 最终校验：mdtest 链接 Open MPI（libmpi.so）
ldd $(command -v mdtest) | grep -qi "libmpi\." || { echo "ERR: mdtest 未链接 Open MPI"; exit 1; }
echo "DONE $(mpirun --version 2>&1 | head -1)"
'

wait_slot() {
    while [ "$(jobs -rp | wc -l)" -ge "$PARALLEL" ]; do
        wait -n 2>/dev/null || sleep 0.1
    done
}

install_one() {
    local node="$1"
    if ssh $SSH_OPTS "$node" "bash -s" <<< "$REMOTE_CMD" > "$WORKDIR/log_$node" 2>&1; then
        echo "OK   $node"
    else
        echo "FAIL $node"
        echo "$node" >> "$WORKDIR/failed"
    fi
}

for node in "${nodes[@]}"; do
    wait_slot
    install_one "$node" &
done
wait

echo "========================================"
if [ -f "$WORKDIR/failed" ]; then
    echo "以下节点失败，日志在 $WORKDIR/log_<node>（脚本退出会清理，需要的话先 cp 出来）:"
    cat "$WORKDIR/failed"
    keep="/tmp/openmpi_install_failed_logs"
    mkdir -p "$keep"
    while read -r n; do cp "$WORKDIR/log_$n" "$keep/" 2>/dev/null; done < "$WORKDIR/failed"
    echo "失败日志已复制到 $keep/"
    exit 1
fi
echo "全部节点安装完成。可在首节点验证："
echo "  mpirun --version | head -1       # Open MPI"
echo "  ldd \$(which mdtest) | grep mpi   # libmpi.so"

# ---------------------------------------------------------------
# 内网无外网环境的替代方案（不走 apt/git）：
#   1. 在一台联网的 Ubuntu 22.04 按上面步骤装好 openmpi-bin 并编译出
#      /usr/local/bin/mdtest
#   2. 打包: tar czf openmpi_mdtest.tgz /usr/local/bin/mdtest \
#            /usr/bin/mpirun /usr/bin/orterun /usr/lib/x86_64-linux-gnu/openmpi ...
#   3. 用 scp 并发分发到各节点同路径，并确保 libmpi 运行库一致后 ldconfig
# ---------------------------------------------------------------
