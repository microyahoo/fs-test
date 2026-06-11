#!/bin/bash
#
# 在 nodeslist 列出的所有节点上并发安装统一的 MPICH 环境，
# 解决「mpirun(Open MPI) 与 mdtest(MPICH) 混用导致退化成 rank-0」的问题。
#
# 前提：本机到所有节点已免密 ssh（见 setup_fullmesh_ssh_parallel.sh）。
# 用法: ./install_mpich_mdtest.sh [并发度]    并发度默认 30
#
# 说明：本脚本只负责在各节点 apt 安装 MPICH 并编译安装 mdtest。
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
# 1. 卸 Open MPI，装 MPICH + 编译工具
apt-get remove -y openmpi-bin libopenmpi-dev 2>/dev/null || true
apt-get update -y
apt-get install -y mpich libmpich-dev build-essential autoconf automake libtool git
# 2. 校验 mpirun 已是 MPICH/HYDRA
mpirun --version 2>&1 | head -1 | grep -qiE "hydra|mpich" || { echo "ERR: mpirun 仍非 MPICH"; exit 1; }
# 3. 编译安装 mdtest（IOR 套件）
rm -rf /tmp/ior_build && git clone --depth 1 '"$IOR_REPO"' /tmp/ior_build
cd /tmp/ior_build
./configure CC=mpicc MPICC=mpicc --prefix=/usr/local
make -j$(nproc)
make install
# 4. 最终校验：mdtest 链接 MPICH
ldd $(command -v mdtest) | grep -qi mpich || { echo "ERR: mdtest 未链接 MPICH"; exit 1; }
echo "DONE $(mdtest -h 2>&1 | head -1)"
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
    # 保留失败日志供排查
    keep="/tmp/mpich_install_failed_logs"
    mkdir -p "$keep"
    while read -r n; do cp "$WORKDIR/log_$n" "$keep/" 2>/dev/null; done < "$WORKDIR/failed"
    echo "失败日志已复制到 $keep/"
    exit 1
fi
echo "全部节点安装完成。可在首节点验证："
echo "  mpirun --version | head -1     # HYDRA/MPICH"
echo "  ldd \$(which mdtest) | grep mpi  # libmpich"

# ---------------------------------------------------------------
# 内网无外网环境的替代方案（不走 apt/git）：
#   1. 在一台联网机按上面步骤装好 mpich 并编译出 /usr/local/bin/mdtest
#   2. 打包: tar czf mpich_mdtest.tgz /usr/local/bin/mdtest /usr/bin/mpirun ...
#   3. 用 scp 并发分发到各节点同路径，并确保 libmpich 运行库一致
# ---------------------------------------------------------------
