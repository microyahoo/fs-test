#!/bin/bash

FIO_DIR="/root/zhengliang/fio/"
HOSTS_FILE="$FIO_DIR/hosts"

# 所有需要修改的 FIO job 文件列表（按执行顺序）
JOB_FILES=(
    "16M_4K_128job_randwrite.job"
    "16M_4K_128job_prewrite.job"
    "16M_4K_128job_randread.job"
    "16M_4K_128job_read8write2.job"
    "16M_4K_256job_randwrite.job"
    "16M_4K_256job_prewrite.job"
    "16M_4K_256job_randread.job"
    "16M_4K_256job_read8write2.job"
    "16M_4K_600job_randwrite.job"
    "16M_4K_600job_prewrite.job"
    "16M_4K_600job_randread.job"
    "16M_4K_600job_read8write2.job"
    "3G_4K_64job_randwrite.job"
    "3G_4K_64job_prewrite.job"
    "3G_4K_64job_randread.job"
    "3G_4K_64job_read8write2.job"
    "3G_4K_128job_randwrite.job"
    "3G_4K_128job_prewrite.job"
    "3G_4K_128job_randread.job"
    "3G_4K_128job_read8write2.job"
    "3G_4K_256job_randwrite.job"
    "3G_4K_256job_prewrite.job"
    "3G_4K_256job_randread.job"
    "3G_4K_256job_read8write2.job"
    "3G_1M_64job_randwrite.job"
    "3G_1M_64job_randread.job"
    "3G_1M_64job_read8write2.job"
)

# 对应的输出日志文件（可选，添加随机字符串前缀以避免覆盖）
LOG_FILES=(
    "16M_4K_128job_randwrite.log"
    "16M_4K_128job_prewrite.log"
    "16M_4K_128job_randread.log"
    "16M_4K_128job_read8write2.log"
    "16M_4K_256job_randwrite.log"
    "16M_4K_256job_prewrite.log"
    "16M_4K_256job_randread.log"
    "16M_4K_256job_read8write2.log"
    "16M_4K_600job_randwrite.log"
    "16M_4K_600job_prewrite.log"
    "16M_4K_600job_randread.log"
    "16M_4K_600job_read8write2.log"
    "3G_4K_64job_randwrite.log"
    "3G_4K_64job_prewrite.log"
    "3G_4K_64job_randread.log"
    "3G_4K_64job_read8write2.log"
    "3G_4K_128job_randwrite.log"
    "3G_4K_128job_prewrite.log"
    "3G_4K_128job_randread.log"
    "3G_4K_128job_read8write2.log"
    "3G_4K_256job_randwrite.log"
    "3G_4K_256job_prewrite.log"
    "3G_4K_256job_randread.log"
    "3G_4K_256job_read8write2.log"
    "3G_1M_64job_randwrite.log"
    "3G_1M_64job_randread.log"
    "3G_1M_64job_read8write2.log"
)

# 生成随机字符串（8位字母数字）
random_string() {
    cat /dev/urandom | tr -dc 'a-zA-Z0-9' | fold -w 8 | head -n 1
}

# 在所有客户端上创建测试目录（递归创建）
# 参数：$1 = 随机字符串，$2 = job 序号（用于独立模式时区分目录，共享模式时忽略）
create_dirs() {
    local rand_str=$1
    local test_path="/vepfsE-test/zl/fio/${rand_str}/dir1/dir2/dir3/dir4/dir5/dir6/dir7/dir8"
    mkdir -p $test_path
}

# 修改所有 FIO job 文件中的 directory 路径
# 将 /vepfsE-test/任意字符串/ 替换为 /vepfsE-test/新随机字符串/
modify_job_files() {
    local rand_str=$1
    for job in "${JOB_FILES[@]}"; do
        local job_path="$FIO_DIR/$job"
        sed -i "s|/vepfsE-test/zl/fio/[^/]*/|/vepfsE-test/zl/fio/${rand_str}/|g" "$job_path"
    done
}

# 执行单个测试（清缓存 -> 运行 fio -> sleep）
run_single_test() {
    local job_file=$1
    local log_file=$2
    local rand_str=$3   # 仅用于日志文件名可选，但不强求

    echo "  -> Running fio with $job_file"
    ansible all -i "$HOSTS_FILE" -m shell --forks 12 -a "echo 3 > /proc/sys/vm/drop_caches"
    fio --client="$HOSTS_FILE" "$FIO_DIR/$job_file" --output="$FIO_DIR/$log_file"
    sleep 30s
}

# 模式1：所有测试共用同一个随机字符串目录
run_mode_shared() {
    local rand_str=$(random_string)
    echo "=== MODE: SHARED directory for all tests ==="
    echo "Random string: $rand_str"

    # 修改所有 job 文件中的路径
    modify_job_files "$rand_str"
    # 创建一次目录
    create_dirs "$rand_str"

    # 按顺序执行所有测试
    for i in "${!JOB_FILES[@]}"; do
        run_single_test "${JOB_FILES[$i]}" "${LOG_FILES[$i]}" "$rand_str"
    done
}

# 模式2：每个测试使用独立的随机字符串目录
run_mode_independent() {
    echo "=== MODE: INDEPENDENT directories per test ==="
    for i in "${!JOB_FILES[@]}"; do
        local rand_str=$(random_string)
        echo "  -> Test ${JOB_FILES[$i]} using random string: $rand_str"

        # 修改所有 job 文件（注意：这里每次都修改全部文件，但每个测试只关心自己的路径，
        # 由于后续测试会再次覆盖，所以没问题。也可以只修改当前 job 文件，但为了脚本简单，全部修改）
        modify_job_files "$rand_str"
        create_dirs "$rand_str"

        run_single_test "${JOB_FILES[$i]}" "${LOG_FILES[$i]}" "$rand_str"
    done
}

run_mode_shared

## 主循环：交替执行两种模式
#MODE=0  # 0 表示共享模式，1 表示独立模式
#while true; do
    #run_mode_shared
    ##if [ $MODE -eq 0 ]; then
        ##run_mode_shared
        ##MODE=1
    ##else
        ##run_mode_independent
        ##MODE=0
    ##fi
    #echo "=========================================="
    #echo "Cycle finished at $(date), waiting 5 seconds before next cycle..."
    #sleep 5
#done
