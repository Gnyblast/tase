#!/bin/bash

# shellcheck source=/dev/null
source /etc/profile

cd /root/tase/ && zig build -p /tmp

faketime '2012-12-20 23:59:50' \
    /tmp/bin/tase --master --config /root/tase/app-test-container/master/config.yaml &
touch /var/signal/master-agent.rdy

sleep 3
tail -n 20 -f /var/log/tase/tase-master.log
