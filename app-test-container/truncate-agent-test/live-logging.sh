#!/bin/bash
while true; do
  rand_num=$(((RANDOM % 5) + 1))
  for f in /var/log/delete-by-size/test.log \
    /var/log/delete-by-days/test.log; do
    echo "Live logging into > ${f}"
    echo "$(date '+%F %T') - New entry to keep live logging" >>"$f"
  done
  echo "Sleeping for ${rand_num} seconds"
  sleep ${rand_num}
done
