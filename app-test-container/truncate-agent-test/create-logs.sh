#!/bin/bash

TRUNCATE_BY_LINES_DIR="/var/log/truncate-by-lines"

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
