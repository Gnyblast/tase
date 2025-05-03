#!/bin/bash

DELETE_BY_DAYS_DIR="/var/log/delete-by-days"

mkdir -p "${DELETE_BY_DAYS_DIR}"
echo "[INFO] Log initialized for Test Delete By Days" >"${DELETE_BY_DAYS_DIR}/test.log"
seq 1 1000 | while read -r i; do
  echo "$(date '+%F %T') - Test Delete By Days - Log entry $i" >>"${DELETE_BY_DAYS_DIR}/test.log"
done

cp "${DELETE_BY_DAYS_DIR}/test.log" "${DELETE_BY_DAYS_DIR}/test-Mon.log"
faketime "2012-12-19 23:59:50" sh -c "touch ${DELETE_BY_DAYS_DIR}/test-Mon.log"
cp "${DELETE_BY_DAYS_DIR}/test.log" "${DELETE_BY_DAYS_DIR}/test-Tue.log"
faketime "2012-12-18 23:59:50" sh -c "touch ${DELETE_BY_DAYS_DIR}/test-Tue.log"
cp "${DELETE_BY_DAYS_DIR}/test.log" "/${DELETE_BY_DAYS_DIR}/test-Wed.log"
faketime "2012-12-17 23:59:50" sh -c "touch ${DELETE_BY_DAYS_DIR}/test-Wed.log"
cp "${DELETE_BY_DAYS_DIR}/test.log" "${DELETE_BY_DAYS_DIR}/test-Thu.log"
faketime "2012-12-16 23:59:50" sh -c "touch ${DELETE_BY_DAYS_DIR}/test-Thu.log"
cp "${DELETE_BY_DAYS_DIR}/test.log" "${DELETE_BY_DAYS_DIR}/test-Fri.log"
faketime "2012-12-15 23:59:50" sh -c "touch ${DELETE_BY_DAYS_DIR}/test-Fri.log"
