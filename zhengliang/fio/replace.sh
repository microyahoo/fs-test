find /root/zhengliang/fio -type f -exec sed -i 's|/mnt/yrtest|/vepfsE-test|g' {} +
#find /root/zhengliang/fio -type f -exec sed -i 's|vepfsE-test|vepfsE-test|g' {} +

# for f in 3G_4K_*; do
#     new="${f/3G/10G}"
#     sed "s/3G/10G/g" "$f" > "$new"
# done
