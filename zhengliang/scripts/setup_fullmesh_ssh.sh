#!/bin/bash

HOSTS_FILE="hosts"   # 你的 IP 列表文件

# 检查 hosts 文件是否存在
if [ ! -f "$HOSTS_FILE" ]; then
    echo "错误: 找不到 $HOSTS_FILE 文件"
    exit 1
fi

# 读取所有 IP 到数组
mapfile -t nodes < "$HOSTS_FILE"

# 1. 确保每个节点都生成了自己的 SSH 密钥（如果还没有）
for node in "${nodes[@]}"; do
    echo ">>> 检查节点 $node 的 SSH 密钥..."
    ssh -o ConnectTimeout=5 "$node" "if [ ! -f /root/.ssh/id_rsa ]; then ssh-keygen -t rsa -N '' -f /root/.ssh/id_rsa; fi"
    if [ $? -ne 0 ]; then
        echo "错误: 无法连接或操作节点 $node"
        exit 1
    fi
done

# 2. 对于每一个节点，将其公钥添加到所有节点的 authorized_keys
for src in "${nodes[@]}"; do
    echo ">>> 从节点 $src 获取公钥..."
    # 获取源节点的公钥内容
    pubkey=$(ssh "$src" "cat /root/.ssh/id_rsa.pub")
    if [ -z "$pubkey" ]; then
        echo "错误: 无法获取节点 $src 的公钥"
        exit 1
    fi
    
    # 将该公钥追加到所有节点的 authorized_keys（包括自身）
    for dst in "${nodes[@]}"; do
        echo "    将 $src 的公钥添加到 $dst"
        ssh "$dst" "mkdir -p /root/.ssh && chmod 700 /root/.ssh && echo '$pubkey' >> /root/.ssh/authorized_keys && chmod 600 /root/.ssh/authorized_keys"
        # 检查是否成功
        if [ $? -ne 0 ]; then
            echo "警告: 添加到 $dst 失败"
        fi
    done
done

echo "========== 完成 =========="
echo "现在任意节点都可以免密 SSH 到任意其他节点。"
