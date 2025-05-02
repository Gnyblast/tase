#!/bin/bash

ROTATE_BY_DAYS_NO_COMPRESS_DIR="/var/log/rotate-by-days-no-compress"
ROTATE_BY_DAYS_COMPRESS_DIR="/var/log/rotate-by-days-compress"
ROTATE_BY_DAYS_COMPRESS_PRUNE_BY_DAYS_DIR="/var/log/rotate-by-days-compress-prune"
ROTATE_BY_SIZE_NO_COMPRESS_DIR="/var/log/rotate-by-size-no-compress"
ROTATE_BY_SIZE_COMPRESS_DIR="/var/log/rotate-by-size-compress"
ROTATE_BY_SIZE_NO_COMPRESS_PRUNE_BY_SIZE_DIR="/var/log/rotate-by-size-no-compress-prune"

mkdir -p "${ROTATE_BY_DAYS_NO_COMPRESS_DIR}"
echo "[INFO] Log initialized for Test Rotate By Days" >"${ROTATE_BY_DAYS_NO_COMPRESS_DIR}/test.log"
seq 1 1000 | while read -r i; do
  echo "$(date '+%F %T') - Test Rotate By Days - Log entry $i" >>"${ROTATE_BY_DAYS_NO_COMPRESS_DIR}/test.log"
done

mkdir -p "${ROTATE_BY_DAYS_COMPRESS_DIR}"
echo "[INFO] Log initialized for Test Rotate By Days Compress" >"${ROTATE_BY_DAYS_COMPRESS_DIR}/test.log"
seq 1 1000 | while read -r i; do
  echo "$(date '+%F %T') - Test Rotate By Days Compress - Log entry $i" >>"${ROTATE_BY_DAYS_COMPRESS_DIR}/test.log"
done

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

mkdir -p "${ROTATE_BY_SIZE_NO_COMPRESS_DIR}"
dd if=/dev/zero of="${ROTATE_BY_SIZE_NO_COMPRESS_DIR}/test.log" bs=30M count=1

mkdir -p "${ROTATE_BY_SIZE_COMPRESS_DIR}"
dd if=/dev/zero of="${ROTATE_BY_SIZE_COMPRESS_DIR}/test.log" bs=30M count=1

mkdir -p "${ROTATE_BY_SIZE_NO_COMPRESS_PRUNE_BY_SIZE_DIR}"
mkdir -p "${ROTATE_BY_SIZE_NO_COMPRESS_PRUNE_BY_SIZE_DIR}/archives"
dd if=/dev/zero of="${ROTATE_BY_SIZE_NO_COMPRESS_PRUNE_BY_SIZE_DIR}/test.log" bs=30M count=1

dd if=/dev/zero of="${ROTATE_BY_SIZE_NO_COMPRESS_PRUNE_BY_SIZE_DIR}/archives/test.log-7126371263" bs=12M count=1
faketime "2012-12-19 23:59:50" sh -c "touch ${ROTATE_BY_SIZE_NO_COMPRESS_PRUNE_BY_SIZE_DIR}/archives/test.log-7126371263"
dd if=/dev/zero of="${ROTATE_BY_SIZE_NO_COMPRESS_PRUNE_BY_SIZE_DIR}/archives/test.log-1283671283" bs=14M count=1
faketime "2012-12-18 23:59:50" sh -c "touch ${ROTATE_BY_SIZE_NO_COMPRESS_PRUNE_BY_SIZE_DIR}/archives/test.log-1283671283"
dd if=/dev/zero of="${ROTATE_BY_SIZE_NO_COMPRESS_PRUNE_BY_SIZE_DIR}/archives/test.log-9247892742" bs=16M count=1
faketime "2012-12-17 23:59:50" sh -c "touch ${ROTATE_BY_SIZE_NO_COMPRESS_PRUNE_BY_SIZE_DIR}/archives/test.log-9247892742"
dd if=/dev/zero of="${ROTATE_BY_SIZE_NO_COMPRESS_PRUNE_BY_SIZE_DIR}/archives/test.log-6273612725" bs=18M count=1
faketime "2012-12-16 23:59:50" sh -c "touch ${ROTATE_BY_SIZE_NO_COMPRESS_PRUNE_BY_SIZE_DIR}/archives/test.log-6273612725"
dd if=/dev/zero of="${ROTATE_BY_SIZE_NO_COMPRESS_PRUNE_BY_SIZE_DIR}/archives/test.log-5126352631" bs=20M count=1
faketime "2012-12-15 23:59:50" sh -c "touch ${ROTATE_BY_SIZE_NO_COMPRESS_PRUNE_BY_SIZE_DIR}/archives/test.log-5126352631"
