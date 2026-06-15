#!/bin/bash
#
# 在 nodeslist 列出的所有节点上并发安装统一的 Open MPI 环境，
# 并编译链接 Open MPI 的 mdtest（IOR 套件）。
#
# 适用系统：CentOS 8.5（openmpi = Open MPI 4.x，dnf 安装）
#           对应 Ubuntu 版见 install_openmpi_mdtest.sh
#
# 为什么用 Open MPI 而不是 MPICH：
#   运行脚本 mdtest_multi.sh 用的是 Open MPI 专有参数
#   （--allow-run-as-root / --mca / -map-by），MPICH 的 mpiexec.hydra
#   不认识这些参数，会报 "unrecognized argument allow-run-as-root"。
#   本脚本把所有节点统一成 Open MPI，从根上消除混用。
#
# CentOS 8.5 三个关键差异（与 Ubuntu 不同）：
#   1. CentOS 8 已 EOL，默认 mirror 失效，需把 repo 指向 vault.centos.org。
#   2. dnf 的 openmpi 不进默认 PATH，装在 /usr/lib64/openmpi/bin，
#      必须 `module load mpi/openmpi-x86_64` 激活，本脚本会持久化到
#      /etc/profile.d，保证后续 ssh 进来 mpirun/mdtest 直接可用。
#   3. 编译工具用 `dnf groupinstall "Development Tools"`。
#
# 前提：本机到所有节点已免密 ssh（见 setup_fullmesh_ssh_parallel.sh）。
# 用法: ./install_openmpi_mdtest_centos.sh [并发度]    并发度默认 30
#
# 说明：本脚本负责在各节点 dnf 安装 Open MPI 并编译安装 mdtest。
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

# 0. CentOS 8.5 已 EOL：把失效的 mirrorlist 切到 vault.centos.org，否则 dnf 全报 404
if grep -rqsl "mirrorlist=" /etc/yum.repos.d/CentOS-*.repo 2>/dev/null; then
    sed -i -e "s|^mirrorlist=|#mirrorlist=|g" \
           -e "s|^#\?baseurl=http://mirror.centos.org|baseurl=http://vault.centos.org|g" \
           /etc/yum.repos.d/CentOS-*.repo
fi

# 1. 卸 MPICH（如装过），装 Open MPI + 编译工具 + environment-modules
dnf remove -y mpich mpich-devel 2>/dev/null || true
dnf install -y --allowerasing openmpi openmpi-devel environment-modules \
    git autoconf automake libtool
dnf groupinstall -y "Development Tools"

# 2. 激活 Open MPI 环境（CentOS 把它装在 /usr/lib64/openmpi，不进默认 PATH）
#    优先用 environment-modules；module 不可用则退回直接导出路径。
if [ -f /etc/profile.d/modules.sh ]; then . /etc/profile.d/modules.sh; fi
if command -v module >/dev/null 2>&1 && module avail 2>&1 | grep -qi "mpi/openmpi-x86_64"; then
    module load mpi/openmpi-x86_64
else
    export PATH=/usr/lib64/openmpi/bin:$PATH
    export LD_LIBRARY_PATH=/usr/lib64/openmpi/lib:${LD_LIBRARY_PATH:-}
fi

# 2b. 持久化到 /etc/profile.d，保证后续非交互 ssh 进来 mpirun/mdtest 可用
cat > /etc/profile.d/openmpi.sh <<EOF
# Open MPI (CentOS dnf 安装路径)，由 install_openmpi_mdtest_centos.sh 写入
if [ -f /etc/profile.d/modules.sh ]; then . /etc/profile.d/modules.sh; fi
if command -v module >/dev/null 2>&1 && module avail 2>&1 | grep -qi "mpi/openmpi-x86_64"; then
    module load mpi/openmpi-x86_64
else
    export PATH=/usr/lib64/openmpi/bin:\$PATH
    export LD_LIBRARY_PATH=/usr/lib64/openmpi/lib:\${LD_LIBRARY_PATH:-}
fi
EOF

# 3. 校验 mpirun 已是 Open MPI（而不是 MPICH/HYDRA）
command -v mpirun >/dev/null || { echo "ERR: 找不到 mpirun，Open MPI 未激活"; exit 1; }
mpirun --version 2>&1 | head -1 | grep -qi "open mpi" || { echo "ERR: mpirun 仍非 Open MPI"; exit 1; }

# 4. 编译安装 mdtest（IOR 套件），用 Open MPI 的 mpicc
rm -rf /tmp/ior_build && git clone --depth 1 '"$IOR_REPO"' /tmp/ior_build
cd /tmp/ior_build
./bootstrap 2>/dev/null || ./autogen.sh 2>/dev/null || true
./configure CC=mpicc MPICC=mpicc --prefix=/usr/local
make -j$(nproc)
make install
echo /usr/lib64/openmpi/lib > /etc/ld.so.conf.d/openmpi.conf
ldconfig

# 5. 最终校验：mdtest 链接 Open MPI（libmpi.so）
ldd /usr/local/bin/mdtest | grep -qi "libmpi\." || { echo "ERR: mdtest 未链接 Open MPI"; exit 1; }
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
echo "全部节点安装完成。可在首节点验证（先 source 一下环境）："
echo "  source /etc/profile.d/openmpi.sh"
echo "  mpirun --version | head -1       # Open MPI"
echo "  ldd \$(which mdtest) | grep mpi   # libmpi.so"

# ---------------------------------------------------------------
# 内网无外网环境的替代方案（不走 dnf/git）：
#   1. 在一台联网的 CentOS 8.5 按上面步骤装好 openmpi 并编译出
#      /usr/local/bin/mdtest
#   2. 打包: tar czf openmpi_mdtest_centos.tgz /usr/local/bin/mdtest \
#            /usr/lib64/openmpi ...
#   3. 用 scp 并发分发到各节点同路径，写好 /etc/profile.d/openmpi.sh
#      与 /etc/ld.so.conf.d/openmpi.conf 后 ldconfig
# ---------------------------------------------------------------
