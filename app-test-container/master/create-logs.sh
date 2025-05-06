#!/bin/bash

DELETE_BY_DAYS_DIR="/var/log/delete-by-days"
ROTATE_BY_DAYS_COMPRESS_PRUNE_BY_DAYS_DIR="/var/log/rotate-by-days-compress-prune"

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

mkdir -p "${ROTATE_BY_DAYS_COMPRESS_PRUNE_BY_DAYS_DIR}"
mkdir -p "${ROTATE_BY_DAYS_COMPRESS_PRUNE_BY_DAYS_DIR}/archives"
echo "[INFO] Log initialized for Test Rotate By Days Prune" >"${ROTATE_BY_DAYS_COMPRESS_PRUNE_BY_DAYS_DIR}/test.log"
seq 1 1000 | while read -r i; do
  echo "$(date '+%F %T') - Test Rotate By Days Prune - Log entry $i" >>"${ROTATE_BY_DAYS_COMPRESS_PRUNE_BY_DAYS_DIR}/test.log"
done

cp "${ROTATE_BY_DAYS_COMPRESS_PRUNE_BY_DAYS_DIR}/test.log" "${ROTATE_BY_DAYS_COMPRESS_PRUNE_BY_DAYS_DIR}/archives/test.log-282462424.gz"
faketime "2012-12-19 23:59:50" sh -c "touch ${ROTATE_BY_DAYS_COMPRESS_PRUNE_BY_DAYS_DIR}/archives/test.log-282462424.gz"
cp "${ROTATE_BY_DAYS_COMPRESS_PRUNE_BY_DAYS_DIR}/test.log" "${ROTATE_BY_DAYS_COMPRESS_PRUNE_BY_DAYS_DIR}/archives/test.log-901726232.gz"
faketime "2012-12-18 23:59:50" sh -c "touch ${ROTATE_BY_DAYS_COMPRESS_PRUNE_BY_DAYS_DIR}/archives/test.log-901726232.gz"
cp "${ROTATE_BY_DAYS_COMPRESS_PRUNE_BY_DAYS_DIR}/test.log" "/${ROTATE_BY_DAYS_COMPRESS_PRUNE_BY_DAYS_DIR}/archives/test.log-8226424928.gz"
faketime "2012-12-17 23:59:50" sh -c "touch ${ROTATE_BY_DAYS_COMPRESS_PRUNE_BY_DAYS_DIR}/archives/test.log-8226424928.gz"
cp "${ROTATE_BY_DAYS_COMPRESS_PRUNE_BY_DAYS_DIR}/test.log" "${ROTATE_BY_DAYS_COMPRESS_PRUNE_BY_DAYS_DIR}/archives/test.log-1781256252.gz"
faketime "2012-12-16 23:59:50" sh -c "touch ${ROTATE_BY_DAYS_COMPRESS_PRUNE_BY_DAYS_DIR}/archives/test.log-1781256252.gz"
cp "${ROTATE_BY_DAYS_COMPRESS_PRUNE_BY_DAYS_DIR}/test.log" "${ROTATE_BY_DAYS_COMPRESS_PRUNE_BY_DAYS_DIR}/archives/test.log-7126371269.gz"
faketime "2012-12-15 23:59:50" sh -c "touch ${ROTATE_BY_DAYS_COMPRESS_PRUNE_BY_DAYS_DIR}/archives/test.log-7126371269.gz"
