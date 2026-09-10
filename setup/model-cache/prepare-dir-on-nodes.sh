CACHE_PATH=/var/mnt/mx-model-cache

for NODE in $(oc get nodes -o name | cut -d/ -f2); do
  echo "=== $NODE ==="
  oc debug node/"$NODE" --quiet -- chroot /host sh -euxc "
    install -d -m 0777 $CACHE_PATH
    chcon -Rt container_file_t $CACHE_PATH
    ls -Zd $CACHE_PATH
  "
done
