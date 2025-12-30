#!/bin/bash

TRUNCATE_BY_LINES_DIR="/var/log/truncate-by-lines"
TRUNCATE_BY_SIZE_DIR="/var/log/truncate-by-size"

mkdir -p "${TRUNCATE_BY_LINES_DIR}"
#echo "[INFO] Log initialized for Test Truncate By Lins" >"${TRUNCATE_BY_LINES_DIR}/test.log"
echo "$(date '+%F %T') - Test Truncate By Lines - Log entry 1" >"${TRUNCATE_BY_LINES_DIR}/test.log"
seq 2 10000 | while read -r i; do
	echo "$(date '+%F %T') - Test Truncate By Lines - Log entry $i" >>"${TRUNCATE_BY_LINES_DIR}/test.log"
done

cp "${TRUNCATE_BY_LINES_DIR}/test.log" "${TRUNCATE_BY_LINES_DIR}/keep-bottom.log"
faketime "2012-12-18 23:59:50" sh -c "touch ${TRUNCATE_BY_LINES_DIR}/keep-bottom.log"

cp "${TRUNCATE_BY_LINES_DIR}/test.log" "${TRUNCATE_BY_LINES_DIR}/delete-bottom.log"
faketime "2012-12-18 23:59:50" sh -c "touch ${TRUNCATE_BY_LINES_DIR}/delete-bottom.log"

cp "${TRUNCATE_BY_LINES_DIR}/test.log" "${TRUNCATE_BY_LINES_DIR}/keep-top.log"
faketime "2012-12-18 23:59:50" sh -c "touch ${TRUNCATE_BY_LINES_DIR}/keep-top.log"

cp "${TRUNCATE_BY_LINES_DIR}/test.log" "${TRUNCATE_BY_LINES_DIR}/delete-top.log"
faketime "2012-12-18 23:59:50" sh -c "touch ${TRUNCATE_BY_LINES_DIR}/delete-top.log"

mkdir -p "${TRUNCATE_BY_SIZE_DIR}"

touch "$TRUNCATE_BY_SIZE_DIR/keep-bottom.log"

awk '
BEGIN {
  n = 1
  while (1) {
    printf "%s - Test Truncate By Size - Log entry %08d\n",
           strftime("%F %T"), n++
  }
}
' | head -c 30M >"$TRUNCATE_BY_SIZE_DIR/keep-bottom.log"

cp "${TRUNCATE_BY_SIZE_DIR}/keep-bottom.log" "${TRUNCATE_BY_SIZE_DIR}/delete-bottom.log"
faketime "2012-12-18 23:59:50" sh -c "touch ${TRUNCATE_BY_SIZE_DIR}/delete-bottom.log"

cp "${TRUNCATE_BY_SIZE_DIR}/keep-bottom.log" "${TRUNCATE_BY_SIZE_DIR}/keep-top.log"
faketime "2012-12-18 23:59:50" sh -c "touch ${TRUNCATE_BY_SIZE_DIR}/keep-top.log"

cp "${TRUNCATE_BY_SIZE_DIR}/keep-bottom.log" "${TRUNCATE_BY_SIZE_DIR}/delete-top.log"
faketime "2012-12-18 23:59:50" sh -c "touch ${TRUNCATE_BY_SIZE_DIR}/delete-top.log"
