#!/bin/bash

mkdir -p "/var/log/postgres"
echo "[INFO] Log initialized for postgres" >"/var/log/postgres/postgresql.log"
seq 1 1000 | while read -r i; do
  echo "$(date '+%F %T') - postgres - Log entry $i" >>"/var/log/postgres/postgresql.log"
done

cp /var/log/postgres/postgresql.log /var/log/postgres/postgresql-Mon.log
faketime -f "-1d" sh -c "touch /var/log/postgres/postgresql-Mon.log"
cp /var/log/postgres/postgresql.log /var/log/postgres/postgresql-Tue.log
faketime -f "-2d" sh -c "touch /var/log/postgres/postgresql-Tue.log"
cp /var/log/postgres/postgresql.log /var/log/postgres/postgresql-Wed.log
faketime -f "-3d" sh -c "touch /var/log/postgres/postgresql-Wed.log"
cp /var/log/postgres/postgresql.log /var/log/postgres/postgresql-Thu.log
faketime -f "-4d" sh -c "touch /var/log/postgres/postgresql-Thu.log"
cp /var/log/postgres/postgresql.log /var/log/postgres/postgresql-Fri.log
faketime -f "-5d" sh -c "touch /var/log/postgres/postgresql-Fri.log"

mkdir -p "/var/log/php"
echo "[INFO] Log initialized for postgres" >"/var/log/php/laravel.log"
seq 1 2000 | while read -r i; do
  echo "$(date '+%F %T') - laravel - Log entry $i" >>"/var/log/php/laravel.log"
done

cp /var/log/php/laravel.log /var/log/php/laravel.log.12-12-2012
faketime -f "-1d" sh -c "touch /var/log/php/laravel.log.12-12-2012"
cp /var/log/php/laravel.log /var/log/php/laravel.log.13-12-2012
faketime -f "-2d" sh -c "touch /var/log/php/laravel.log.13-12-2012"
cp /var/log/php/laravel.log /var/log/php/laravel.log.14-12-2012
faketime -f "-3d" sh -c "touch /var/log/php/laravel.log.14-12-2012"
cp /var/log/php/laravel.log /var/log/php/laravel.log.15-12-2012
faketime -f "-4d" sh -c "touch /var/log/php/laravel.log.15-12-2012"

mkdir -p "/var/log/php"
echo "[INFO] Log initialized for postgres" >"/var/log/php/symphony.log"
seq 1 1500 | while read -r i; do
  echo "$(date '+%F %T') - symphony - Log entry $i" >>"/var/log/php/symphony.log"
done

mkdir -p "/var/log/nginx"
echo "[INFO] Log initialized for postgres" >"/var/log/nginx/access.log"
seq 1 3000 | while read -r i; do
  echo "$(date '+%F %T') - nginx-access - Log entry $i" >>"/var/log/nginx/access.log"
done

cp /var/log/nginx/access.log /var/log/nginx/access_1.log
faketime -f "-1d" sh -c "touch /var/log/nginx/access_1.log"
cp /var/log/nginx/access.log /var/log/nginx/access_2.log
faketime -f "-2d" sh -c "touch /var/log/nginx/access_2.log"
cp /var/log/nginx/access.log /var/log/nginx/access_3.log
faketime -f "-3d" sh -c "touch /var/log/nginx/access_3.log"
cp /var/log/nginx/access.log /var/log/nginx/access_4.log
faketime -f "-4d" sh -c "touch /var/log/nginx/access_4.log"
cp /var/log/nginx/access.log /var/log/nginx/access_5.log
faketime -f "-5d" sh -c "touch /var/log/nginx/access_5.log"

mkdir -p "/var/log/nginx"
echo "[INFO] Log initialized for postgres" >"/var/log/nginx/error.log"
seq 1 3000 | while read -r i; do
  echo "$(date '+%F %T') - nginx-error - Log entry $i" >>"/var/log/nginx/error.log"
done

cp /var/log/nginx/error.log /var/log/nginx/error_1.log
faketime -f "-1d" sh -c "touch /var/log/nginx/error_1.log"
cp /var/log/nginx/error.log /var/log/nginx/error_2.log
faketime -f "-2d" sh -c "touch /var/log/nginx/error_2.log"
