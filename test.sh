#!/bin/bash

for fio_test in $(find /root/juicefs/fio-*); do
    echo $fio_test;
    echo 3 > /proc/sys/vm/drop_caches;
    
    fio \
     --directory=$1 \
     --output-format=json \
     $fio_test \
     --output $fio_test.json;
done
