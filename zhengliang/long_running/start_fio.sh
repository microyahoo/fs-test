ansible all -i /root/zhengliang/long_running/hosts -m shell -a "nohup fio --server > /var/log/fio-server.log 2>&1 &"
