ansible all -i /root/zhengliang/vdbench50407/hosts -m shell --forks 21 -a "echo 3 > /proc/sys/vm/drop_caches"
ansible all -i /root/zhengliang/vdbench50407/hosts -m shell --forks 21 -a '/root/zhengliang/vdbench50407/vdbench -f /root/zhengliang/vdbench50407/1client-rand-read-3G-4k-128job'

sleep 1m
ansible all -i /root/zhengliang/vdbench50407/hosts -m shell --forks 21 -a "echo 3 > /proc/sys/vm/drop_caches"
ansible all -i /root/zhengliang/vdbench50407/hosts -m shell --forks 21 -a '/root/zhengliang/vdbench50407/vdbench -f /root/zhengliang/vdbench50407/1client-rand-read-3G-4k-256job'
