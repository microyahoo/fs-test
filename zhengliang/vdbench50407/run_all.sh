ansible all -i /root/zhengliang/vdbench50407/hosts -m shell --forks 15 -a "echo 3 > /proc/sys/vm/drop_caches"
/root/zhengliang/vdbench50407/vdbench -f /root/zhengliang/vdbench50407/21client-rand-write-4K-4K-64job
sleep 1m
ansible all -i /root/zhengliang/vdbench50407/hosts -m shell --forks 15 -a "echo 3 > /proc/sys/vm/drop_caches"
/root/zhengliang/vdbench50407/vdbench -f /root/zhengliang/vdbench50407/21client-rand-read-4K-4K-64job
sleep 1m
ansible all -i /root/zhengliang/vdbench50407/hosts -m shell --forks 15 -a "echo 3 > /proc/sys/vm/drop_caches"
/root/zhengliang/vdbench50407/vdbench -f /root/zhengliang/vdbench50407/21client-read8-write2-4K-4K-64job
sleep 1m
ansible all -i /root/zhengliang/vdbench50407/hosts -m shell --forks 15 -a "echo 3 > /proc/sys/vm/drop_caches"
/root/zhengliang/vdbench50407/vdbench -f /root/zhengliang/vdbench50407/21client-rand-write-4K-4K-128job
sleep 1m
ansible all -i /root/zhengliang/vdbench50407/hosts -m shell --forks 15 -a "echo 3 > /proc/sys/vm/drop_caches"
/root/zhengliang/vdbench50407/vdbench -f /root/zhengliang/vdbench50407/21client-rand-read-4K-4K-128job
sleep 1m
ansible all -i /root/zhengliang/vdbench50407/hosts -m shell --forks 15 -a "echo 3 > /proc/sys/vm/drop_caches"
/root/zhengliang/vdbench50407/vdbench -f /root/zhengliang/vdbench50407/21client-read8-write2-4K-4K-128job
sleep 1m
ansible all -i /root/zhengliang/vdbench50407/hosts -m shell --forks 15 -a "echo 3 > /proc/sys/vm/drop_caches"
/root/zhengliang/vdbench50407/vdbench -f /root/zhengliang/vdbench50407/21client-rand-write-4K-4K-256job
sleep 1m
ansible all -i /root/zhengliang/vdbench50407/hosts -m shell --forks 15 -a "echo 3 > /proc/sys/vm/drop_caches"
/root/zhengliang/vdbench50407/vdbench -f /root/zhengliang/vdbench50407/21client-rand-read-4K-4K-256job
sleep 1m
ansible all -i /root/zhengliang/vdbench50407/hosts -m shell --forks 15 -a "echo 3 > /proc/sys/vm/drop_caches"
/root/zhengliang/vdbench50407/vdbench -f /root/zhengliang/vdbench50407/21client-read8-write2-4K-4K-256job

sleep 1m
ansible all -i /root/zhengliang/vdbench50407/hosts -m shell --forks 15 -a "echo 3 > /proc/sys/vm/drop_caches"
/root/zhengliang/vdbench50407/vdbench -f /root/zhengliang/vdbench50407/21client-rand-write-3G-4k-128job
sleep 1m
ansible all -i /root/zhengliang/vdbench50407/hosts -m shell --forks 15 -a "echo 3 > /proc/sys/vm/drop_caches"
/root/zhengliang/vdbench50407/vdbench -f /root/zhengliang/vdbench50407/21client-rand-read-3G-4k-128job
sleep 1m
ansible all -i /root/zhengliang/vdbench50407/hosts -m shell --forks 15 -a "echo 3 > /proc/sys/vm/drop_caches"
/root/zhengliang/vdbench50407/vdbench -f /root/zhengliang/vdbench50407/21client-read8-write2-3G-4k-128job
sleep 1m
ansible all -i /root/zhengliang/vdbench50407/hosts -m shell --forks 15 -a "echo 3 > /proc/sys/vm/drop_caches"
/root/zhengliang/vdbench50407/vdbench -f /root/zhengliang/vdbench50407/21client-rand-write-3G-4k-256job
sleep 1m
ansible all -i /root/zhengliang/vdbench50407/hosts -m shell --forks 15 -a "echo 3 > /proc/sys/vm/drop_caches"
/root/zhengliang/vdbench50407/vdbench -f /root/zhengliang/vdbench50407/21client-rand-read-3G-4k-256job
sleep 1m
ansible all -i /root/zhengliang/vdbench50407/hosts -m shell --forks 15 -a "echo 3 > /proc/sys/vm/drop_caches"
/root/zhengliang/vdbench50407/vdbench -f /root/zhengliang/vdbench50407/21client-read8-write2-3G-4k-256job

sleep 1m
ansible all -i /root/zhengliang/vdbench50407/hosts -m shell --forks 15 -a "echo 3 > /proc/sys/vm/drop_caches"
/root/zhengliang/vdbench50407/vdbench -f /root/zhengliang/vdbench50407/21client-rand-write-3G-1M-64job
sleep 1m
ansible all -i /root/zhengliang/vdbench50407/hosts -m shell --forks 15 -a "echo 3 > /proc/sys/vm/drop_caches"
/root/zhengliang/vdbench50407/vdbench -f /root/zhengliang/vdbench50407/21client-rand-read-3G-1M-64job
sleep 1m
ansible all -i /root/zhengliang/vdbench50407/hosts -m shell --forks 15 -a "echo 3 > /proc/sys/vm/drop_caches"
/root/zhengliang/vdbench50407/vdbench -f /root/zhengliang/vdbench50407/21client-read8-write2-3G-1M-64job
sleep 1m
ansible all -i /root/zhengliang/vdbench50407/hosts -m shell --forks 15 -a "echo 3 > /proc/sys/vm/drop_caches"
/root/zhengliang/vdbench50407/vdbench -f /root/zhengliang/vdbench50407/21client-rand-write-3G-1M-128job
sleep 1m
ansible all -i /root/zhengliang/vdbench50407/hosts -m shell --forks 15 -a "echo 3 > /proc/sys/vm/drop_caches"
/root/zhengliang/vdbench50407/vdbench -f /root/zhengliang/vdbench50407/21client-rand-read-3G-1M-128job
sleep 1m
ansible all -i /root/zhengliang/vdbench50407/hosts -m shell --forks 15 -a "echo 3 > /proc/sys/vm/drop_caches"
/root/zhengliang/vdbench50407/vdbench -f /root/zhengliang/vdbench50407/21client-read8-write2-3G-1M-128job

#sleep 1m
#ansible all -i /root/zhengliang/vdbench50407/hosts -m shell --forks 15 -a "echo 3 > /proc/sys/vm/drop_caches"
##ansible all -i /root/zhengliang/vdbench50407/hosts -m shell --forks 15 -a '/root/zhengliang/vdbench50407/vdbench -f /root/zhengliang/vdbench50407/1client-rand-read-3G-4k-128job'
#/root/zhengliang/vdbench50407/vdbench -f /root/zhengliang/vdbench50407/1client-rand-read-3G-4k-128job
#
#sleep 1m
#ansible all -i /root/zhengliang/vdbench50407/hosts -m shell --forks 15 -a "echo 3 > /proc/sys/vm/drop_caches"
#/root/zhengliang/vdbench50407/vdbench -f /root/zhengliang/vdbench50407/1client-rand-read-3G-4k-256job
##ansible all -i /root/zhengliang/vdbench50407/hosts -m shell --forks 15 -a '/root/zhengliang/vdbench50407/vdbench -f /root/zhengliang/vdbench50407/1client-rand-read-3G-4k-256job'
