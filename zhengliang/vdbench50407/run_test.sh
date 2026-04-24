ansible all -i /root/zhengliang/vdbench50407/hosts -m shell --forks 21 -a "echo 3 > /proc/sys/vm/drop_caches"
mkdir -p /vepfsE-test/zl/vdbench/dir1/dir2/dir3/dir4/dir5/dir6/dir7/
/root/zhengliang/vdbench50407/vdbench -f /root/zhengliang/vdbench50407/21client-rand-write-4K-4K-64job
sleep 1m
ansible all -i /root/zhengliang/vdbench50407/hosts -m shell --forks 21 -a "echo 3 > /proc/sys/vm/drop_caches"
/root/zhengliang/vdbench50407/vdbench -f /root/zhengliang/vdbench50407/21client-rand-read-4K-4K-64job
sleep 1m
ansible all -i /root/zhengliang/vdbench50407/hosts -m shell --forks 21 -a "echo 3 > /proc/sys/vm/drop_caches"
/root/zhengliang/vdbench50407/vdbench -f /root/zhengliang/vdbench50407/21client-read8-write2-4K-4K-64job
sleep 1m

ansible all -i /root/zhengliang/vdbench50407/hosts -m shell --forks 21 -a "echo 3 > /proc/sys/vm/drop_caches"
/root/zhengliang/vdbench50407/vdbench -f /root/zhengliang/vdbench50407/21client-rand-write-4K-4K-128job
sleep 1m
ansible all -i /root/zhengliang/vdbench50407/hosts -m shell --forks 21 -a "echo 3 > /proc/sys/vm/drop_caches"
/root/zhengliang/vdbench50407/vdbench -f /root/zhengliang/vdbench50407/21client-rand-read-4K-4K-128job
sleep 1m
ansible all -i /root/zhengliang/vdbench50407/hosts -m shell --forks 21 -a "echo 3 > /proc/sys/vm/drop_caches"
/root/zhengliang/vdbench50407/vdbench -f /root/zhengliang/vdbench50407/21client-read8-write2-4K-4K-128job
sleep 1m

ansible all -i /root/zhengliang/vdbench50407/hosts -m shell --forks 21 -a "echo 3 > /proc/sys/vm/drop_caches"
/root/zhengliang/vdbench50407/vdbench -f /root/zhengliang/vdbench50407/21client-rand-write-4K-4K-256job
sleep 1m
ansible all -i /root/zhengliang/vdbench50407/hosts -m shell --forks 21 -a "echo 3 > /proc/sys/vm/drop_caches"
/root/zhengliang/vdbench50407/vdbench -f /root/zhengliang/vdbench50407/21client-rand-read-4K-4K-256job
sleep 1m
ansible all -i /root/zhengliang/vdbench50407/hosts -m shell --forks 21 -a "echo 3 > /proc/sys/vm/drop_caches"
/root/zhengliang/vdbench50407/vdbench -f /root/zhengliang/vdbench50407/21client-read8-write2-4K-4K-256job
