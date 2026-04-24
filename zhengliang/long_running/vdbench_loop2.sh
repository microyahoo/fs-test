#!/bin/bash

VD_DIR="/root/zhengliang/vdbench50407"
HOSTS_FILE="$VD_DIR/hosts"

# 所有需要修改的配置文件
VD_FILES=(
    "21client-rand-write-4K-4K-64job"
    "21client-rand-read-4K-4K-64job"
    "21client-read8-write2-4K-4K-64job"
    "21client-rand-write-4K-4K-128job"
    "21client-rand-read-4K-4K-128job"
    "21client-read8-write2-4K-4K-128job"
    "21client-rand-write-4K-4K-256job"
    "21client-rand-read-4K-4K-256job"
    "21client-read8-write2-4K-4K-256job"
    "21client-rand-write-4K-4K-512job"
    "21client-rand-read-4K-4K-512job"
    "21client-read8-write2-4K-4K-512job"
)

# 生成随机字符串（10位字母数字）
random_string() {
    cat /dev/urandom | tr -dc 'a-zA-Z0-9' | fold -w 10 | head -n 1
}

# 在所有客户端上创建 anchor 目录
create_vd_dirs() {
    local rand_str=$1
    local anchor_path="/mnt/yrtest/${rand_str}/vdbench/dir1/dir2/dir3/dir4/dir5/dir6/dir7"
    mkdir -p $anchor_path
    #ansible all -i "$HOSTS_FILE" -m file -a "path=$anchor_path state=directory mode=0755" --forks 21
}

# 修改所有配置文件中的 anchor 路径
modify_vd_configs() {
    local rand_str=$1
    for f in "${VD_FILES[@]}"; do
        local file_path="$VD_DIR/$f"
        sed -i "s|/mnt/yrtest/[^/]*/|/mnt/yrtest/${rand_str}/|g" "$file_path"
    done
}

# 执行一组测试（写、读、混合读写）
run_vd_group() {
    local job_suffix=$1   # 64job / 128job / 256job / 512job
    echo "  -> Running $job_suffix"

    ansible all -i "$HOSTS_FILE" -m shell --forks 21 -a "echo 3 > /proc/sys/vm/drop_caches"
    "$VD_DIR/vdbench" -f "$VD_DIR/21client-rand-write-4K-4K-${job_suffix}"
    #sleep 1m
    sleep 30s

    ansible all -i "$HOSTS_FILE" -m shell --forks 21 -a "echo 3 > /proc/sys/vm/drop_caches"
    "$VD_DIR/vdbench" -f "$VD_DIR/21client-rand-read-4K-4K-${job_suffix}"
    #sleep 1m
    sleep 30s

    ansible all -i "$HOSTS_FILE" -m shell --forks 21 -a "echo 3 > /proc/sys/vm/drop_caches"
    "$VD_DIR/vdbench" -f "$VD_DIR/21client-read8-write2-4K-4K-${job_suffix}"
    #sleep 1m
    sleep 30s
}

# 模式1：所有组共用同一个随机字符串
run_vd_mode_shared() {
    local rand_str=$(random_string)
    echo "=== MODE: SHARED directory for all groups ==="
    echo "Random string: $rand_str"
    modify_vd_configs "$rand_str"
    create_vd_dirs "$rand_str"
    echo "=========================================="
    ansible all -i hosts -m synchronize -a "src=/root/zhengliang/vdbench50407/ dest=/root/zhengliang/vdbench50407 delete=yes"
    echo "sync up vdbench"

    echo "=================start to run vdbench jobs========================="
    run_vd_group "64job"
    run_vd_group "128job"
    run_vd_group "256job"
    run_vd_group "512job"
}

# 模式2：每个组使用独立的随机字符串
run_vd_mode_independent() {
    echo "=== MODE: INDEPENDENT directories per group ==="
    for job in "64job" "128job" "256job" "512job"; do
        local rand_str=$(random_string)
        echo "  -> $job using random string: $rand_str"
        modify_vd_configs "$rand_str"
        create_vd_dirs "$rand_str"
        ansible all -i hosts -m synchronize -a "src=/root/zhengliang/vdbench50407/ dest=/root/zhengliang/vdbench50407 delete=yes"
        echo "sync up vdbench"

        echo "=================start to run vdbench jobs========================="
        run_vd_group "$job" 
    done
}

# 主循环：交替执行两种模式
MODE=0  # 0表示共享模式，1表示独立模式
while true; do
    if [ $MODE -eq 0 ]; then
        run_vd_mode_shared
        MODE=1
    else
        run_vd_mode_independent
        MODE=0
    fi
    echo "=========================================="
    echo "Cycle finished at $(date), waiting 5 seconds..."
    sleep 5
done
