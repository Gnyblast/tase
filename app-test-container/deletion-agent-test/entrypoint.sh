#!/bin/bash

# shellcheck source=/dev/null
source /etc/profile

cd /root/tase/ && zig build -p /tmp

faketime '2012-12-20 23:59:50' \
    /tmp/bin/tase --agent --secret b9d36fa4b6cd3d8a2f5527c792143bfc --host 0.0.0.0 --port 7424 --master-host localhost --master-port 7423 &
touch /var/signal/delete-agent.rdy

faketime '2012-12-20 23:59:50' \
    live-logging.sh >/tmp/live-log.log &

sleep 3
tail -f /var/log/tase/tase-agent.log
