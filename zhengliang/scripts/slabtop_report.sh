#!/bin/bash
#
# slabtop_report.sh —— 解析 slabinfo，按内存占用排序，给出占用大户的明细。
#
# 用法:
#   ./slabtop_report.sh                 # 解析本机 /proc/slabinfo
#   ./slabtop_report.sh slabinfo.txt    # 解析指定的 slabinfo 文件
#   ./slabtop_report.sh -n 40           # 只看 Top 40（默认 25）
#   ./slabtop_report.sh -n 40 slabinfo.txt
#
# 占用按 num_objs * objsize 计算（含 slab 内部 slack，更接近实际占的物理内存）。
# 同时给出 active_objs * objsize 作为"真正在用"的下限参考。

set -eu

TOPN=25
SRC=/proc/slabinfo

# 解析参数：-n N 控制条数，其余位置参数当作输入文件
while [ $# -gt 0 ]; do
    case "$1" in
        -n) TOPN="$2"; shift 2 ;;
        -h|--help)
            sed -n '2,18p' "$0"; exit 0 ;;
        *) SRC="$1"; shift ;;
    esac
done

if [ ! -r "$SRC" ]; then
    echo "错误: 无法读取 $SRC" >&2
    exit 1
fi

awk -v topn="$TOPN" '
# 跳过头两行（version 行 + 列名注释行），只处理数据行
NR>2 && NF>=4 && $1 !~ /^#/ {
    name=$1; active=$2+0; num=$3+0; objsize=$4+0;
    total=num*objsize;          # 含 slack 的占用（字节）
    act=active*objsize;         # 真正在用的下限（字节）
    names[NR]=name; A[NR]=active; N[NR]=num; OS[NR]=objsize;
    TOT[NR]=total; ACT[NR]=act;
    sum_tot+=total; sum_act+=act;
    idx[++cnt]=NR;
}
END {
    # 按 total（含 slack）降序冒泡排序索引
    for (i=1;i<=cnt;i++)
        for (j=i+1;j<=cnt;j++)
            if (TOT[idx[j]] > TOT[idx[i]]) { t=idx[i]; idx[i]=idx[j]; idx[j]=t }

    printf "%-26s %14s %14s %9s %12s %12s %7s\n", \
        "name","active_objs","num_objs","objsize","active_MB","total_MB","用率%";
    printf "%s\n", "------------------------------------------------------------------------------------------------------";

    shown_tot=0;
    for (k=1;k<=cnt && k<=topn;k++) {
        r=idx[k];
        ratio = (N[r]>0) ? 100.0*A[r]/N[r] : 0;   # active/num，越低说明 slab 越碎
        printf "%-26s %14d %14d %9d %12.1f %12.1f %7.0f\n", \
            names[r], A[r], N[r], OS[r], ACT[r]/1048576, TOT[r]/1048576, ratio;
        shown_tot+=TOT[r];
    }

    printf "%s\n", "------------------------------------------------------------------------------------------------------";
    printf "Top %d 合计:        %.1f MB (%.2f GB)，占全部 slab 的 %.1f%%\n", \
        (cnt<topn?cnt:topn), shown_tot/1048576, shown_tot/1073741824, \
        (sum_tot>0?100.0*shown_tot/sum_tot:0);
    printf "全部 slab 合计:     active=%.1f GB（在用下限）   total=%.1f GB（含 slack，≈实际物理占用）\n", \
        sum_act/1073741824, sum_tot/1073741824;
    printf "\n说明: total_MB = num_objs*objsize（含 slab 内部碎片）。用率%% = active/num，\n";
    printf "      偏低说明该 slab 释放了大量对象但页未归还、存在碎片（如 dentry 常见）。\n";
    printf "      多数文件系统/VFS slab 计入 buff/cache，可被内核回收，未必是真正占用。\n";
}
' "$SRC"
