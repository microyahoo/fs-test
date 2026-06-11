#!/bin/bash
#
# 并发版：为 hosts 列表中的所有节点建立全互联（full-mesh）免密 SSH。
#
# 与串行版的区别：
#   1. 串行版对每个 (src, dst) 组合单独执行一次 ssh，共 N*N 次连接（400 节点 = 16 万次）。
#   2. 本版本：
#        - 并发为所有节点生成密钥；
#        - 并发收集所有节点的公钥，合并成一个 authorized_keys 片段；
#        - 并发把这一份合并后的片段一次性追加到每个节点（每节点仅 1 次 ssh）。
#      连接数从 N*N 降到约 2*N。
#
# 用法: ./setup_fullmesh_ssh_parallel.sh [并发度]
#   并发度默认 50，可按需调整。

set -u

HOSTS_FILE="hosts"          # IP 列表文件
PARALLEL="${1:-50}"         # 最大并发数
SSH_OPTS="-o ConnectTimeout=10 -o StrictHostKeyChecking=no -o BatchMode=yes"

if [ ! -f "$HOSTS_FILE" ]; then
    echo "错误: 找不到 $HOSTS_FILE 文件"
    exit 1
fi

# 读取所有 IP（忽略空行）
mapfile -t nodes < <(grep -v '^[[:space:]]*$' "$HOSTS_FILE")
total=${#nodes[@]}
echo ">>> 共 $total 个节点，最大并发 $PARALLEL"

# 临时目录用于收集公钥
WORKDIR="$(mktemp -d)"
trap 'rm -rf "$WORKDIR"' EXIT

# 通用并发执行器：从 stdin 读取任务行，超过 PARALLEL 时等待空闲槽位。
# 用法: run_parallel <函数名>  （配合 wait_slot）
wait_slot() {
    while [ "$(jobs -rp | wc -l)" -ge "$PARALLEL" ]; do
        wait -n 2>/dev/null || sleep 0.05
    done
}

############################################
# 1. 并发确保每个节点都有自己的 SSH 密钥
############################################
echo ">>> [1/3] 并发检查/生成各节点 SSH 密钥..."
gen_key() {
    local node="$1"
    if ssh $SSH_OPTS "$node" \
        "if [ ! -f /root/.ssh/id_rsa ]; then ssh-keygen -t rsa -N '' -f /root/.ssh/id_rsa >/dev/null; fi"; then
        echo "OK $node"
    else
        echo "FAIL $node" >&2
        echo "$node" >> "$WORKDIR/keygen_failed"
    fi
}
for node in "${nodes[@]}"; do
    wait_slot
    gen_key "$node" &
done
wait

if [ -f "$WORKDIR/keygen_failed" ]; then
    echo "错误: 以下节点密钥生成/连接失败:"
    cat "$WORKDIR/keygen_failed"
    exit 1
fi

############################################
# 2. 并发收集所有节点的公钥
############################################
echo ">>> [2/3] 并发收集各节点公钥..."
fetch_key() {
    local node="$1"
    local key
    key=$(ssh $SSH_OPTS "$node" "cat /root/.ssh/id_rsa.pub" 2>/dev/null)
    if [ -n "$key" ]; then
        # 每个节点的公钥写到独立文件，避免并发写冲突
        printf '%s\n' "$key" > "$WORKDIR/pub_${node}"
    else
        echo "$node" >> "$WORKDIR/fetch_failed"
    fi
}
for node in "${nodes[@]}"; do
    wait_slot
    fetch_key "$node" &
done
wait

if [ -f "$WORKDIR/fetch_failed" ]; then
    echo "错误: 以下节点公钥获取失败:"
    cat "$WORKDIR/fetch_failed"
    exit 1
fi

# 合并所有公钥成一份 authorized_keys 片段
cat "$WORKDIR"/pub_* > "$WORKDIR/all_keys"
key_count=$(wc -l < "$WORKDIR/all_keys")
echo "    已收集 $key_count 个公钥"

############################################
# 3. 并发把合并后的公钥分发到每个节点
############################################
echo ">>> [3/3] 并发分发公钥到各节点（去重写入 authorized_keys）..."
distribute() {
    local node="$1"
    # 通过 stdin 把全部公钥传过去，在远端与现有 authorized_keys 合并去重
    if ssh $SSH_OPTS "$node" '
        mkdir -p /root/.ssh && chmod 700 /root/.ssh
        cat >> /root/.ssh/authorized_keys
        sort -u -o /root/.ssh/authorized_keys /root/.ssh/authorized_keys
        chmod 600 /root/.ssh/authorized_keys
    ' < "$WORKDIR/all_keys"; then
        echo "OK $node"
    else
        echo "FAIL $node" >&2
        echo "$node" >> "$WORKDIR/dist_failed"
    fi
}
for node in "${nodes[@]}"; do
    wait_slot
    distribute "$node" &
done
wait

if [ -f "$WORKDIR/dist_failed" ]; then
    echo "警告: 以下节点公钥分发失败:"
    cat "$WORKDIR/dist_failed"
    exit 1
fi

echo "========== 完成 =========="
echo "现在任意节点都可以免密 SSH 到任意其他节点。"
