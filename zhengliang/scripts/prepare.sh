#! /bin/bash

if [ -f /etc/os-release ]; then
    . /etc/os-release
    OS_NAME=$NAME
else
    echo "ERROR: unknown system"
    exit 1
fi

# update repo
if [[ "$OS_NAME" == *"CentOS"* ]]; then
    echo "The system was detected as CentOS"
    sed -i 's/mirrorlist/#mirrorlist/g' /etc/yum.repos.d/CentOS-*
    sed -i 's|#baseurl=http://mirror.centos.org|baseurl=http://vault.centos.org|g' /etc/yum.repos.d/CentOS-*
elif [[ "$OS_NAME" == *"Rocky"* ]]; then
    echo "The system was detected as Rocky"
    find /etc/yum.repos.d/ -name '*.repo' -exec bash -c 'mv "$0" "${0%.repo}.bak"' {} \;
    cp Rocky-BaseOS.repo.tmpl /etc/yum.repos.d/Rocky-BaseOS.repo

    rpm --import https://mirrors.aliyun.com/epel/RPM-GPG-KEY-EPEL-9
    cp Rocky-EPEL.repo.tmpl /etc/yum.repos.d/Rocky-EPEL.repo
    yum clean all && yum makecache
else
    echo "WARNING: Unknown system: $OS_NAME"
fi

# install
wget http://s3-smd.deeproute.cn/smd-pkg/tools/sshpass-1.10.tar.gz -P /tmp/ && tar -xvf /tmp/sshpass-1.10.tar.gz -C /tmp
wget http://s3-smd.deeproute.cn/smd-pkg/tools/dool-v1.3.3.tar.gz -P /tmp/ && tar -xvf /tmp/dool-v1.3.3.tar.gz -C /tmp
cd /tmp/sshpass-1.10 && ./configure --prefix=/usr && make install
cd /tmp/dool-1.3.3 && mv dool /usr/local/bin/ && mkdir -p /root/.dool/ && cp -r plugins/* /root/.dool/

yum install python3 python3-pip -y
yum install rsync -y
#pip3 install --upgrade pip -i  https://pypi.tuna.tsinghua.edu.cn/simple/
#pip3 install setuptools_rust -i https://pypi.tuna.tsinghua.edu.cn/simple/
#pip3 install ansible-core==2.11.12 -i https://pypi.tuna.tsinghua.edu.cn/simple/
#pip3 install ansible -i https://pypi.tuna.tsinghua.edu.cn/simple/
pip3 install --upgrade pip -i https://nexus.deeproute.ai/repository/pypi-group/simple
pip3 install setuptools_rust -i https://nexus.deeproute.ai/repository/pypi-group/simple
pip3 install ansible-core==2.11.12 -i https://nexus.deeproute.ai/repository/pypi-group/simple
pip3 install ansible -i https://nexus.deeproute.ai/repository/pypi-group/simple
pip3 install ansible -i https://nexus.deeproute.ai/repository/pypi-group/simple
