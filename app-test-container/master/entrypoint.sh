#!/bin/bash

# shellcheck source=/dev/null
source /etc/profile

cd /root/tase/ && zig build -p /tmp

faketime '2012-12-20 23:59:50' \
    /tmp/bin/tase --master --config /root/tase/app-test-container/master/config.yaml &

sleep 3
tail -f /var/log/tase/tase-master.log
