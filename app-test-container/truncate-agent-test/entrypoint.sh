#!/bin/bash

# shellcheck source=/dev/null
source /etc/profile

cd /root/tase/ && zig build -p /tmp

faketime '2012-12-20 23:59:50' \
	/tmp/bin/tase --agent --secret e93ccf5ffc90eefcc0bdb81f87d25d1a --host 0.0.0.0 --port 7426 --master-host localhost --master-port 7423 &
touch /var/signal/truncate-agent.rdy

faketime '2012-12-20 23:59:50' \
	live-logging.sh >/tmp/live-log.log &

sleep 3
tail -n 20 -f /var/log/tase/tase-agent.log
