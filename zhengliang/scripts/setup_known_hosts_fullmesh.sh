#!/bin/bash

HOSTS_FILE="hosts"

if [ ! -f "$HOSTS_FILE" ]; then
    echo "错误: 找不到 $HOSTS_FILE"
    exit 1
fi

# 读取所有 IP
mapfile -t nodes < "$HOSTS_FILE"

echo ">>> 为所有节点互相添加主机密钥（免 yes 确认）..."

# 定义每个节点需要执行的命令
# 功能：把 hosts 列表里所有主机的公钥加入自己的 known_hosts，并去重
CMD="
HOSTS='${nodes[@]}'
for ip in \$HOSTS; do
    ssh-keyscan \$ip 2>/dev/null >> ~/.ssh/known_hosts
done
sort -u -o ~/.ssh/known_hosts ~/.ssh/known_hosts
"

# 对每一个节点执行上述命令（包括当前节点）
for node in "${nodes[@]}"; do
    echo "  处理节点: $node"
    ssh -o ConnectTimeout=5 "$node" "bash -s" <<< "$CMD"
    if [ $? -eq 0 ]; then
        echo "    完成"
    else
        echo "    失败，请检查网络或免密登录"
        exit 1
    fi
done

echo "========== 完成 =========="
echo "现在任意节点 SSH 到任意其他节点都不会再询问 yes/no。"
