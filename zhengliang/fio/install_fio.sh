wget http://s3-smd.deeproute.cn/smd-pkg/tools/fio-3.38.tar.gz -P /tmp/ && tar -xvf /tmp/fio-3.38.tar.gz -C /tmp && cd /tmp/fio-3.38 && ./configure --prefix=/usr && make -j4 && make install
