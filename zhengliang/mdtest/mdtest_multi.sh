nodes_file=./nodeslist

DEPTH=1
WIDTH=320
num_files=1000000
#num_procs=720
num_procs=480

files_per_dir=$(($num_files/320/$num_procs))
mpirun --allow-run-as-root --mca btl_tcp_if_include bond4 -hostfile $nodes_file -map-by node -np ${num_procs} mdtest -d /mnt/yrtest/zl/fio/dir1/dir2/dir3/dir4/dir5/dir6/dir7/mdtest -i 1 -I ${files_per_dir} -z ${DEPTH} -b ${WIDTH} -L -T  -F -u -w 0 -r -C
#mpirun --allow-run-as-root --mca btl_tcp_if_include 10.16.8.0/21 -hostfile $nodes_file -map-by node -np ${num_procs} mdtest -d /mnt/yrtest/zl/fio/dir1/dir2/dir3/dir4/dir5/dir6/dir7/mdtest -i 1 -I ${files_per_dir} -z ${DEPTH} -b ${WIDTH} -L -T  -F -u -w 0 -r -C
#mpirun --allow-run-as-root --mca btl_tcp_if_include 10.16.17.0/24 -hostfile $nodes_file -map-by node -np ${num_procs} mdtest -d /mnt/yrtest/zl/fio/dir1/dir2/dir3/dir4/dir5/dir6/dir7/mdtest -i 1 -I ${files_per_dir} -z ${DEPTH} -b ${WIDTH} -L -T  -F -u -w 0 -r -C
