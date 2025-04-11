#!/bin/bash
while true; do
  for f in /var/log/postgres/postgresql.log \
    /var/log/php/laravel.log \
    /var/log/php/symphony.log \
    /var/log/nginx/access.log \
    /var/log/nginx/error.log; do
    echo "Live logging into > ${f}"
    echo "$(date '+%F %T') - New entry to keep live logging" >>"$f"
  done
  sleep 5
done
