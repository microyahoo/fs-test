#!/bin/bash
#
# 并发版：为 hosts 列表中的所有节点互相添加主机密钥到 known_hosts，
# 使得任意节点 SSH 到任意其他节点时不再询问 yes/no。
#
# 与串行版的区别：
#   串行版逐个登录每个节点执行 ssh-keyscan。本版本并发登录所有节点，
#   每个节点内部仍对全部目标做 ssh-keyscan 并去重。
#
# 用法: ./setup_known_hosts_fullmesh_parallel.sh [并发度]
#   并发度默认 50。

set -u

HOSTS_FILE="hosts"
PARALLEL="${1:-50}"
SSH_OPTS="-o ConnectTimeout=10 -o StrictHostKeyChecking=no -o BatchMode=yes"

if [ ! -f "$HOSTS_FILE" ]; then
    echo "错误: 找不到 $HOSTS_FILE"
    exit 1
fi

# 读取所有 IP（忽略空行）
mapfile -t nodes < <(grep -v '^[[:space:]]*$' "$HOSTS_FILE")
total=${#nodes[@]}
echo ">>> 共 $total 个节点，最大并发 $PARALLEL"

WORKDIR="$(mktemp -d)"
trap 'rm -rf "$WORKDIR"' EXIT

# 每个节点上要执行的命令：对 hosts 列表所有主机做 ssh-keyscan 并去重
CMD="
HOSTS='${nodes[*]}'
mkdir -p ~/.ssh && chmod 700 ~/.ssh
for ip in \$HOSTS; do
    ssh-keyscan \$ip 2>/dev/null >> ~/.ssh/known_hosts
done
sort -u -o ~/.ssh/known_hosts ~/.ssh/known_hosts
"

wait_slot() {
    while [ "$(jobs -rp | wc -l)" -ge "$PARALLEL" ]; do
        wait -n 2>/dev/null || sleep 0.05
    done
}

echo ">>> 并发为所有节点互相添加主机密钥（免 yes 确认）..."
process_node() {
    local node="$1"
    if ssh $SSH_OPTS "$node" "bash -s" <<< "$CMD"; then
        echo "OK $node"
    else
        echo "FAIL $node" >&2
        echo "$node" >> "$WORKDIR/failed"
    fi
}

for node in "${nodes[@]}"; do
    wait_slot
    process_node "$node" &
done
wait

if [ -f "$WORKDIR/failed" ]; then
    echo "警告: 以下节点处理失败，请检查网络或免密登录:"
    cat "$WORKDIR/failed"
    exit 1
fi

echo "========== 完成 =========="
echo "现在任意节点 SSH 到任意其他节点都不会再询问 yes/no。"
