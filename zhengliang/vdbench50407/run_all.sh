#!/bin/bash

BASE_DIR=/root/zhengliang/vdbench50407
HOSTS=${BASE_DIR}/hosts
VDBENCH=${BASE_DIR}/vdbench

drop_caches() {
    ansible all -i "${HOSTS}" -m shell --forks 15 -a "echo 3 > /proc/sys/vm/drop_caches"
}

run_test() {
    local test_name=$1
    echo ">>> Running: ${test_name}"
    drop_caches
    ${VDBENCH} -f "${BASE_DIR}/${test_name}"
    sleep 1m
}

# 4K文件 4K IO 64job
run_test 21client-rand-write-4K-4K-64job
run_test 21client-rand-read-4K-4K-64job
run_test 21client-read8-write2-4K-4K-64job

# 4K文件 4K IO 128job
run_test 21client-rand-write-4K-4K-128job
run_test 21client-rand-read-4K-4K-128job
run_test 21client-read8-write2-4K-4K-128job

# 4K文件 4K IO 256job
run_test 21client-rand-write-4K-4K-256job
run_test 21client-rand-read-4K-4K-256job
run_test 21client-read8-write2-4K-4K-256job

# 3G文件 4k IO 128job
run_test 21client-rand-write-3G-4k-128job
run_test 21client-rand-read-3G-4k-128job
run_test 21client-read8-write2-3G-4k-128job

# 3G文件 4k IO 256job
run_test 21client-rand-write-3G-4k-256job
run_test 21client-rand-read-3G-4k-256job
run_test 21client-read8-write2-3G-4k-256job

# 3G文件 1M IO 64job
run_test 21client-rand-write-3G-1M-64job
run_test 21client-rand-read-3G-1M-64job
run_test 21client-read8-write2-3G-1M-64job

# 3G文件 1M IO 128job
run_test 21client-rand-write-3G-1M-128job
run_test 21client-rand-read-3G-1M-128job
run_test 21client-read8-write2-3G-1M-128job

# 4K文件 4K IO depth=3 (含create/write/read/mix)
run_test 21client-4K_4K_3deep
run_test 21client-4K_4K_3deep_2x
run_test 21client-4K_4K_3deep_16x

# 4K文件 4K IO depth=10 (含create/write/read/mix)
run_test 21client-4K_4K_10deep
run_test 21client-4K_4K_10deep_2x
run_test 21client-4K_4K_10deep_16x
