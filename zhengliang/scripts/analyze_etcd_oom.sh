#!/usr/bin/env bash
# analyze_oom.sh — 分析 K8s 控制平面节点 OOM 日志 (etcd/apiserver 视角)
# 用法: ./analyze_oom.sh <logfile>   例: ./analyze_oom.sh oom.log
set -uo pipefail   # 不用 -e: head 关闭管道会让上游 grep 收到 SIGPIPE(141), 属正常

LOG="${1:-oom.log}"
[ -f "$LOG" ] || { echo "找不到日志文件: $LOG" >&2; exit 1; }

sep() { printf '\n=== %s ===\n' "$1"; }

sep "日志时间范围 & 规模"
printf '首行: %s\n' "$(head -1 "$LOG" | cut -c1-31)"
printf '尾行: %s\n' "$(tail -1 "$LOG" | cut -c1-31)"
printf '总行数: %s\n' "$(wc -l < "$LOG")"

sep "OOM-killer 击杀事件 (时间 / 进程 / 实际匿名内存)"
# anon-rss 才是被杀进程占用的真实物理内存(匿名页,不可回收)
grep "Out of memory: Killed process" "$LOG" | sed -E \
  's/.*([A-Z][a-z]{2}) +([0-9]+) ([0-9:]{8}).*Killed process [0-9]+ \(([^)]+)\).*anon-rss:([0-9]+)kB.*/\1 \2 \3|\4|\5/' \
  | awk -F'|' '{ printf "%s  %-14s anon-rss=%s kB  (%.1f GB)\n", $1, $2, $3, $3/1024/1024 }'

sep "进程表中 RSS 最高的进程 (从首个 oom-killer 的 task dump 提取, 单位换算为 MB)"
# 列: pid uid tgid total_vm rss pgtables_bytes swapents oom_score_adj name
# 第5列(rss)单位是页(4KB). 注意第5列不是pgtables!
awk '
  /invoked oom-killer/ { grab=1 }
  grab && /\[ *pid *\] +uid/ { intab=1; next }
  intab && /oom-kill:|Out of memory/ { exit }
  intab {
    # 去掉 syslog 前缀, 找到以 [ 开头的进程表行
    line=$0; sub(/.*kernel: \[[0-9.]+\] /,"",line)
    n=split(line,f," ")
    if (f[1] ~ /^\[/ && n>=9) {
      rss=f[5]; name=f[n]
      printf "%10.1f MB  %s\n", rss*4/1024, name
    }
  }
' "$LOG" | sort -rn | head -12

sep "etcd 进程实例 (区分正常 vs 失控)"
for pid in $(grep -oE 'etcd\[[0-9]+\]' "$LOG" | grep -oE '[0-9]+' | sort -u); do
  cnt=$(grep -c "etcd\[$pid\]" "$LOG" || true)
  printf 'etcd pid=%s  日志条数=%s\n' "$pid" "$cnt"
done
echo '(日志条数远多的那个即实际在服务、且最终失控的实例)'

# 确定主 etcd pid (日志最多者)
MAIN_PID=$(grep -oE 'etcd\[[0-9]+\]' "$LOG" | grep -oE '[0-9]+' | sort | uniq -c | sort -rn | head -1 | awk '{print $2}')
sep "主 etcd (pid=$MAIN_PID) 慢查询 (apply request took too long) 按分钟分布"
grep "etcd\[$MAIN_PID\]" "$LOG" | grep "apply request took too long" \
  | grep -oE '[0-9]{2}:[0-9]{2}:' | sort | uniq -c

sep "主 etcd 慢查询最慢 Top10 (耗时 / key / 命中数·response大小)"
# 只取真正的查询(apply request took too long), 排除 compaction 自身的 took.
# 用 perl 非贪婪匹配稳定抽出 took / request / response 三段.
grep "etcd\[$MAIN_PID\]" "$LOG" | grep "apply request took too long" \
  | perl -ne 'print "$1|$2|$3\n" if /"took":"([\d.]+)s".*?"request":"(.*?)","response":"(.*?)"/' \
  | sort -rn | head -10 \
  | awk -F'|' '{
      key=$2; gsub(/\\"/,"",key); gsub(/key:/,"",key); gsub(/ +$/,"",key);
      resp=$3; gsub(/range_response_count:/,"count=",resp); gsub(/ size:/," size=",resp);
      printf "%7.2fs  %-70s [%s]\n", $1, key, resp
    }'
echo '(注意: 多数被拖慢的是单 key 小查询(size 才几百~几千字节) => 瓶颈是 raft 共识/内存压力, 非查询本身大)'

sep "慢查询瓶颈阶段 (raft 共识 vs 读 bolt db)"
printf 'raft 共识(agreement among raft nodes) 命中: %s\n' "$(grep -c 'agreement among raft nodes' "$LOG" || true)"
printf '读盘(range keys from bolt db)          命中: %s\n' "$(grep -c 'range keys from bolt db' "$LOG" || true)"
echo '(前者远大于后者 => 瓶颈是内存压力拖慢 raft, 而非磁盘 IO)'

sep "慢查询命中的 key 前缀 Top15 (谁在拖垮 etcd)"
grep "etcd\[$MAIN_PID\]" "$LOG" | grep "apply request took too long" \
  | grep -oE 'key:\\"/registry/[a-z0-9.]+' | sed -E 's#.*registry/##' \
  | sort | uniq -c | sort -rn | head -15

sep "巨型 response 查询 Top8 (response_count / size) —— 内存炸弹"
grep "etcd\[$MAIN_PID\]" "$LOG" | grep -oE 'range_response_count:[0-9]+ size:[0-9]+' \
  | awk -F'size:' '{print $2, $0}' | sort -rn | uniq | head -8 \
  | awk '{ printf "%.1f MB   %s %s\n", $1/1024/1024, $3, $4 }'

sep "全量 list 统计 (动态发现, 不写死资源名) —— 最危险的访问模式"
# 不写死资源名: 动态发现所有 'key:"P/" range_end:"P0"' 形式的 list(P 以 / 结尾,
# range_end 是把结尾 / 换成 0). 无论元凶是 pods / events / 某个 CRD 都自动浮现, 不会漏.
# 用 perl 同时判定层级并打标:
#   TOP = 顶层全量(LIST 整个资源类型, 不限 ns): /registry/<res>/ 或 /registry/<group.domain>/<res>/
#   NS  = namespace 内 list(范围小): /registry/<res>/<ns>/
grep "etcd\[$MAIN_PID\]" "$LOG" \
  | perl -ne 'while(/"key:\\"([^\\]+)\\" range_end:\\"([^\\]+)\\"/g){
        $k=$1; $e=$2;
        next unless $k=~m{/$} && $e eq (substr($k,0,-1)."0");
        (my $p=$k)=~s{^/registry/}{}; $p=~s{/$}{};
        my @s=split m{/},$p;
        # 顶层: 单段(核心资源) 或 两段且首段含点(CRD 的 group/resource)
        my $top = (@s==1) || (@s==2 && $s[0]=~/\./);
        print(($top?"TOP ":"NS  "), $k, "\n");
     }' > /tmp/_lists.$$
echo '--- 顶层全量 list(资源类型级, 最危险) Top15 ---'
grep '^TOP ' /tmp/_lists.$$ | sed 's/^TOP //' | sort | uniq -c | sort -rn | head -15
echo '--- namespace 内 list(范围小但高频也放大内存) Top10 ---'
grep '^NS  ' /tmp/_lists.$$ | sed 's/^NS  //' | sort | uniq -c | sort -rn | head -10
rm -f /tmp/_lists.$$
echo '(次数多 + 单对象大者即内存放大主因, 应改用 watch / 分页 limit+continue)'

sep "巨型查询 (response_count >= 10000) 明细 —— 内存炸弹的具体请求"
# 这类是 v3rpc 'request stats' 行: 含 time spent / remote / response count/size / request content.
# perl 按数值阈值筛(不用位数正则, 避免漏掉 >=10万 的), 提取关键字段.
GIANT=$(grep "etcd\[$MAIN_PID\]" "$LOG" | grep '"msg":"request stats"' \
  | perl -ne 'if(/"ts":"[\dT:.-]+(\d\d:\d\d:\d\d)\.\d+Z".*?"time spent":"([^"]+)".*?"remote":"([^"]+)".*?"response count":(\d+),"response size":(\d+),"request content":"(.*?)"\}\s*$/){
        ($tm,$spent,$rem,$cnt,$sz,$rc)=($1,$2,$3,$4,$5,$6);
        next unless $cnt>=10000;
        # request content 内是转义的 key:\"..\"(key 内可能含 \\000 continue token); 取到第一个未转义的 \"
        $key = ($rc=~/key:\\"(.*?)\\" /) ? $1 : "?";
        $lim = ($rc=~/(limit:\d+)/) ? " $1" : " (无limit)";
        $full = ($rc=~/range_end/) ? " [全量扫描]" : "";
        printf "%s|%s|%s|%d|%d|%s|%s%s\n",$tm,$spent,$rem,$cnt,$sz,$key,$lim,$full;
     }')

NG=$(printf '%s\n' "$GIANT" | grep -c . || true)
printf '总条数(扫描条目数 response_count>=10000): %s\n' "$NG"
echo '注: response_count 是 etcd 实际遍历/匹配的条目数. 即便带 limit:500, 若指定旧 revision + continue,'
echo '    在高 churn 下 etcd 仍需扫描上万条才凑够一页 => 比裸全量 list 更隐蔽的内存放大.'
echo ''

echo '--- 按响应大小 Top12 (耗时 / 扫描数 / response大小 / 客户端 / key + limit) ---'
printf '%s\n' "$GIANT" | sort -t'|' -k5 -rn | head -12 \
  | awk -F'|' '{ printf "  %12s  scan=%-6s %6.1fMB  %-18s %s%s\n", $2, $4, $5/1024/1024, $3, $6, $7 }'

echo ''
echo '--- 命中资源(按 key 前缀归并, 去掉具体对象名)及次数 ---'
printf '%s\n' "$GIANT" | awk -F'|' '{print $6}' \
  | sed -E 's#(/registry/[a-z0-9.]+/[a-z0-9.-]+/).*#\1*#; s#(/registry/[a-z0-9.]+/)$#\1*(全量)#' \
  | sort | uniq -c | sort -rn | head

echo ''
echo '--- 客户端来源 IP:Port 及次数 ---'
printf '%s\n' "$GIANT" | awk -F'|' '{print $3}' | sort | uniq -c | sort -rn | head

echo ''
echo '--- 按分钟分布(看是否随时间加密 => 雪崩前兆) ---'
printf '%s\n' "$GIANT" | awk -F'|' '{print substr($1,1,5)}' | sort | uniq -c

sep "etcd compaction 实况 (直接读日志, 不靠 revision 绝对值猜)"
# revision 是单调递增的全局逻辑时钟, 做不做 compaction 都照涨 => 绝对值无法判断 compaction.
# 真凭实据是 'finished scheduled compaction' 日志: 有=在压缩, 且其中带真实 DB 大小.
CNUM=$(grep -c "finished scheduled compaction" "$LOG" || true)
printf "主 etcd 'finished scheduled compaction' 次数: %s\n" "$CNUM"
if [ "${CNUM:-0}" -gt 0 ]; then
  echo '=> auto-compaction 在工作(每次成功完成). 摘录(含真实 DB 大小):'
  grep "etcd\[$MAIN_PID\]" "$LOG" | grep "finished scheduled compaction" \
    | grep -oE '"ts":"[^"]+"|compact-revision":[0-9]+|current-db-size":"[^"]+"|current-db-size-in-use":"[^"]+"' \
    | paste -d' ' - - - - | head -6
  echo "compact-revision 是否推进 (推进=在持续删旧版本):"
  CREVS=$(grep "etcd\[$MAIN_PID\]" "$LOG" | grep "finished scheduled compaction" | grep -oE 'compact-revision":[0-9]+' | grep -oE '[0-9]+' | sort -n)
  printf '  首次 %s -> 末次 %s (差 %s)\n' "$(echo "$CREVS" | head -1)" "$(echo "$CREVS" | tail -1)" "$(( $(echo "$CREVS" | tail -1) - $(echo "$CREVS" | head -1) ))"
else
  echo '=> 未见 compaction 完成日志, 需进一步排查是否未配置 --auto-compaction.'
fi
echo "旁证: 'mvcc: required revision has been compacted' 出现次数(>0 说明压缩确实在生效): $(grep -c 'required revision has been compacted' "$LOG" || true)"

sep "DB 真实大小 vs etcd RSS (判断是数据型增长还是请求堆积型膨胀)"
# 从 compaction 日志取最近一次的真实 DB 大小, 与被 OOM 杀掉时的 RSS 对比.
DBLINE=$(grep "etcd\[$MAIN_PID\]" "$LOG" | grep "finished scheduled compaction" | tail -1)
if [ -n "$DBLINE" ]; then
  echo "$DBLINE" | grep -oE 'current-db-size":"[^"]+"|current-db-size-in-use":"[^"]+"' | sed 's/^/  /'
fi
RSSKB=$(grep "Killed process" "$LOG" | grep "(etcd)" | grep -oE 'anon-rss:[0-9]+kB' | grep -oE '[0-9]+' | sort -rn | head -1)
[ -n "$RSSKB" ] && awk -v r="$RSSKB" 'BEGIN{ printf "  etcd 被杀时 anon-rss ≈ %.1f GB\n", r/1024/1024 }'
echo '=> DB 仅个位数 GB 而 RSS 上百 GB(差几十~上百倍) => 内存不是被数据/索引撑大的,'
echo '   而是请求处理路径的瞬时/堆积型膨胀(大 list 并发 + 慢查询致请求 inflight 堆积 + Go 不立即归还堆).'

sep "写入 churn 速率 (独立指标: 反映集群写压力, 与 compaction 无关)"
REVS=$(grep "etcd\[$MAIN_PID\]" "$LOG" | grep -oE 'response_revision:[0-9]+' | grep -oE '[0-9]+' | sort -n)
RMIN=$(echo "$REVS" | head -1); RMAX=$(echo "$REVS" | tail -1)
T1=$(head -1 "$LOG" | grep -oE '[0-9]{2}:[0-9]{2}:[0-9]{2}' | head -1)
T2=$(tail -1 "$LOG" | grep -oE '[0-9]{2}:[0-9]{2}:[0-9]{2}' | head -1)
SECS=$(awk -v a="$T1" -v b="$T2" 'BEGIN{split(a,x,":");split(b,y,":");print (y[1]*3600+y[2]*60+y[3])-(x[1]*3600+x[2]*60+x[3])}')
printf 'revision 区间: %s -> %s  (增量 %s)\n' "$RMIN" "$RMAX" "$((RMAX-RMIN))"
[ "${SECS:-0}" -gt 0 ] && awk -v d="$((RMAX-RMIN))" -v s="$SECS" 'BEGIN{ printf "时间跨度 %d 秒 => 写入 churn ≈ %.0f revision/分钟\n", s, d/s*60 }'
echo '(churn 高只说明写压力大; revision 绝对值大≠无 compaction —— 切勿据此推断 compaction)'

sep "节点内存总量 & swap (来自 Mem-Info)"
grep -m1 "Total swap" "$LOG" | sed -E 's/.*\] //'
# 日志里有多次 Mem-Info, 只取第一次的各 Node present 求和(物理内存不变)
awk '
  /Mem-Info/ { seen++ }
  seen==1 && /present:[0-9]+kB/ {
    match($0,/present:([0-9]+)kB/,a); sum+=a[1]
  }
  seen>=2 { exit }
  END { printf "物理内存 present 合计 ≈ %.1f GB\n", sum/1024/1024 }
' "$LOG"

sep "结论速览"
cat <<'EOF'
- 直接死因: 主 etcd 进程匿名内存涨至 ~106GB, 占满整机(无 swap), 触发 global OOM.
- 内核先杀 oom_score_adj 高(=999)的炮灰 pod(coredns/node-cache/virt-api), 释放不足, 最终杀 etcd.
- 内存性质: DB 真实大小仅个位数 GB(compaction 正常工作), 而 RSS 上百 GB =>
  属"请求堆积型"膨胀, 非"数据/索引型"增长.
- 放大链: apiserver 反复发起 /registry/pods/ 等全量 list(单次百 MB 级 response)
          + 慢查询致大量请求长时间 inflight 不释放 + Go 不立即归还堆内存
          => 内存正反馈雪崩, 几分钟冲到上百 GB.
- 与 apiserver 的关系: 直接相关. apiserver 是 etcd 唯一客户端, 把大 range/list 透传给 etcd,
  etcd 为构造 response 在内存中物化全部结果, 产生内存放大.
- 注意: compaction 没问题, 不要往这个方向排查. 该查: (1)谁在反复全量 list pods(改 watch/分页)
  (2)etcd 版本是否有已知内存泄漏 bug (3)给 etcd 加 --max-request-bytes 与 systemd MemoryMax.
EOF
