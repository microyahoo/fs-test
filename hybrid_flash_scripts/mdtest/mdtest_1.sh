#!/bin/bash
set -e
set -u

nodes_file=./nodeslist
timestamp=$(date +%Y%m%d_%H%M%S)
log_file="mdtest_1_${timestamp}.log"

# 验证节点文件
if [ ! -f "$nodes_file" ]; then
    echo "Error: nodes file not found: $nodes_file"
    exit 1
fi

DEPTH=1
WIDTH=${1:-320}
num_files=${2:-10000000}
num_procs=${3:-960}
files_per_dir=$(($num_files/$WIDTH/$num_procs))

echo "========================================"
echo "MDTest Run Start: $(date)"
echo "========================================"
echo "DEPTH=$DEPTH, WIDTH=$WIDTH"
echo "Total files=$num_files, Processes=$num_procs"
echo "Files per directory=$files_per_dir"
echo "Log file: $log_file"
echo "========================================"

mpirun --allow-run-as-root --mca btl_tcp_if_include 10.16.20.0/20 -hostfile $nodes_file -map-by node -np ${num_procs} mdtest -d /mnt/yrtest/mdtest/dir1/dir2/dir3/dir4/dir5/dir6/dir7/dir8/dir9 -i 1 -I ${files_per_dir} -z ${DEPTH} -b ${WIDTH} -L -T  -F -u -w 0 -r -C | tee "$log_file"

echo "========================================"
echo "MDTest Run Complete: $(date)"
echo "========================================"