#!/bin/bash

VD_DIR="/root/zhengliang/vdbench50407"
LONG_RUNNING_DIR="/root/zhengliang/long_running"
HOSTS_FILE="$LONG_RUNNING_DIR/hosts"

# 所有需要修改的 FIO job 文件列表（按执行顺序）
FIO_JOB_FILES=(
    "3G_4K_128job_randwrite.job"
    "3G_4K_128job_prewrite.job"
    "3G_4K_128job_randread.job"
    "3G_4K_128job_read8write2.job"
    "3G_4K_256job_randwrite.job"
    "3G_4K_256job_prewrite.job"
    "3G_4K_256job_randread.job"
    "3G_4K_256job_read8write2.job"
)

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

# 对应的输出日志文件（可选，添加随机字符串前缀以避免覆盖）
FIO_LOG_FILES=(
    "3G_4K_128job_randwrite.log"
    "3G_4K_128job_prewrite.log"
    "3G_4K_128job_randread.log"
    "3G_4K_128job_read8write2.log"
    "3G_4K_256job_randwrite.log"
    "3G_4K_256job_prewrite.job"
    "3G_4K_256job_randread.log"
    "3G_4K_256job_read8write2.log"
)

# 生成随机字符串（10 位字母数字）
random_string() {
    cat /dev/urandom | tr -dc 'a-zA-Z0-9' | fold -w 10 | head -n 1
}

# 在所有客户端上创建测试目录（递归创建）
# 参数：$1 = 随机字符串，$2 = job 序号（用于独立模式时区分目录，共享模式时忽略）
create_fio_dirs() {
    local rand_str=$1
    local test_path="/mnt/yrtest/fio/${rand_str}/dir1/dir2/dir3/dir4/dir5/dir6/dir7/dir8"
    mkdir -p $test_path
}

# 修改所有 FIO job 文件中的 directory 路径
# 将 /mnt/yrtest/任意字符串/ 替换为 /mnt/yrtest/新随机字符串/
modify_fio_job_files() {
    local rand_str=$1
    for job in "${FIO_JOB_FILES[@]}"; do
	local random_runtime=$(( RANDOM % 301 + 300 ))
        local job_path="$LONG_RUNNING_DIR/$job"
        sed -i "s|/mnt/yrtest/fio/[^/]*/|/mnt/yrtest/fio/${rand_str}/|g" "$job_path"
	sed -i "s/\(^[[:space:]]*runtime=\)[0-9]\+/\1$random_runtime/" "$job_path"
    done
}

# 在所有客户端上创建 anchor 目录
create_vd_dirs() {
    local rand_str=$1
    local anchor_path="/mnt/yrtest/vdbench/${rand_str}/dir1/dir2/dir3/dir4/dir5/dir6/dir7/dir8"
    mkdir -p $anchor_path
}

# 修改所有配置文件中的 anchor 路径
modify_vd_configs() {
    local rand_str=$1
    for f in "${VD_FILES[@]}"; do
        local file_path="$LONG_RUNNING_DIR/$f"
        sed -i "s|/mnt/yrtest/vdbench/[^/]*/|/mnt/yrtest/vdbench/${rand_str}/|g" "$file_path"
    done
}

# 执行一组测试（写、读、混合读写）
run_vd_group() {
    local job_suffix=$1   # 64job / 128job / 256job / 512job
    echo "  -> Running $job_suffix"

    ansible all -i "$HOSTS_FILE" -m shell --forks 21 -a "echo 3 > /proc/sys/vm/drop_caches"
    "$VD_DIR/vdbench" -f "$LONG_RUNNING_DIR/21client-rand-write-4K-4K-${job_suffix}"
    #sleep 1m
    sleep 30s

    ansible all -i "$HOSTS_FILE" -m shell --forks 21 -a "echo 3 > /proc/sys/vm/drop_caches"
    "$VD_DIR/vdbench" -f "$LONG_RUNNING_DIR/21client-rand-read-4K-4K-${job_suffix}"
    #sleep 1m
    sleep 30s

    ansible all -i "$HOSTS_FILE" -m shell --forks 21 -a "echo 3 > /proc/sys/vm/drop_caches"
    "$VD_DIR/vdbench" -f "$LONG_RUNNING_DIR/21client-read8-write2-4K-4K-${job_suffix}"
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
    ansible all -i hosts -m synchronize -a "src=/root/zhengliang/long_running/ dest=/root/zhengliang/long_running delete=yes"
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
        ansible all -i hosts -m synchronize -a "src=/root/zhengliang/long_running/ dest=/root/zhengliang/long_running delete=yes"
        echo "sync up vdbench"

        echo "=================start to run vdbench jobs========================="
        run_vd_group "$job" 
    done
}

# 执行单个测试（清缓存 -> 运行 fio -> sleep）
run_fio_single_test() {
    local job_file=$1
    local log_file=$2
    local rand_str=$3   # 仅用于日志文件名可选，但不强求

    echo "  -> Running fio with $job_file"
    ansible all -i "$HOSTS_FILE" -m shell --forks 21 -a "echo 3 > /proc/sys/vm/drop_caches"
    mkdir -p $LONG_RUNNING_DIR/fio-logs/$rand_str/
    fio --client="$HOSTS_FILE" "$LONG_RUNNING_DIR/$job_file" --output="$LONG_RUNNING_DIR/fio-logs/$rand_str/$log_file"
    sleep 30s
}

# 模式1：所有测试共用同一个随机字符串目录
run_fio_mode_shared() {
    local rand_str=$(random_string)
    echo "=== MODE: SHARED directory for all tests ==="
    echo "Random string: $rand_str"

    # 修改所有 job 文件中的路径
    modify_fio_job_files "$rand_str"
    # 创建一次目录
    create_fio_dirs "$rand_str"

    # 按顺序执行所有测试
    for i in "${!FIO_JOB_FILES[@]}"; do
        run_fio_single_test "${FIO_JOB_FILES[$i]}" "${FIO_LOG_FILES[$i]}" "$rand_str"
    done
}

# 模式2：每个测试使用独立的随机字符串目录
run_fio_mode_independent() {
    echo "=== MODE: INDEPENDENT directories per test ==="
    for i in "${!FIO_JOB_FILES[@]}"; do
        local rand_str=$(random_string)
        echo "  -> Test ${FIO_JOB_FILES[$i]} using random string: $rand_str"

        # 修改所有 job 文件（注意：这里每次都修改全部文件，但每个测试只关心自己的路径，
        # 由于后续测试会再次覆盖，所以没问题。也可以只修改当前 job 文件，但为了脚本简单，全部修改）
        modify_fio_job_files "$rand_str"
        create_fio_dirs "$rand_str"

        run_fio_single_test "${FIO_JOB_FILES[$i]}" "${FIO_LOG_FILES[$i]}" "$rand_str"
    done
}

# 主循环：交替执行两种模式
MODE=0  # 0 表示共享模式，1 表示独立模式
while true; do
    if [ $MODE -eq 0 ]; then
        run_vd_mode_shared
        MODE=1
    else
        run_vd_mode_independent
        MODE=0
    fi
    echo "=========================================="
    echo "Cycle finished at $(date), waiting 5 seconds before next cycle..."
    sleep 5

    run_fio_mode_shared
    echo "=========================================="
    echo "fio finished at $(date), waiting 5 seconds..."
    sleep 5
done
