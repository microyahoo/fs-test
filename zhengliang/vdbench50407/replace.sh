#!/bin/bash

file="/root/zhengliang/vdbench50407/1client-rand-read-3G-4k-256job"
count=1
for ip in `cat hosts`; do
    ssh "$ip" "sed -i 's/mm/$ip/g; s/xx/$count/g' $file"
    ((count++))
done
