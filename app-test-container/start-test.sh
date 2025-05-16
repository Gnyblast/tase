#!/bin/bash
SCRIPT_PATH="$(cd "$(dirname "$0")" && pwd)"
echo "Mount path: ${SCRIPT_PATH}/../"

MASTER_IMAGE="tase:master"
MASTER_CONTAINER="tase_master"

DELETION_AGENT_IMAGE="tase:deletion-agent"
DELETION_CONTAINER="tase_delete_agent"

ROTATION_AGENT_IMAGE="tase:rotation-agent"
ROTATION_CONTAINER="tase_rotate_agent"

NETWORK="tase_network"
SIGNAL_DIR="/tmp/tase-signal"

cleanupExit() {
    local exit_code=0
    if [ -n "${1}" ]; then
        exit_code=$1
    fi
    podman container stop "${DELETION_CONTAINER}"
    podman container stop "${ROTATION_CONTAINER}"
    podman container stop "${MASTER_CONTAINER}"
    podman container prune -f
    exit "${exit_code}"
}

prepare() {
    podman container rm -f "${DELETION_CONTAINER}"
    podman container rm -f "${ROTATION_CONTAINER}"
    podman container rm -f "${MASTER_CONTAINER}"
    podman network rm "${NETWORK}"
    podman network create "${NETWORK}"
    rm -rf "${SIGNAL_DIR}"
    mkdir -p "${SIGNAL_DIR}"

}

startAgents() {
    podman run -d -v "${SCRIPT_PATH}/../:/root/tase" -v "${SIGNAL_DIR}:/var/signal" -p 7424 --network "${NETWORK}" --name "${DELETION_CONTAINER}" "${DELETION_AGENT_IMAGE}"
    podman run -d -v "${SCRIPT_PATH}/../:/root/tase" -v "${SIGNAL_DIR}:/var/signal" -p 7425 --network "${NETWORK}" --name "${ROTATION_CONTAINER}" "${ROTATION_AGENT_IMAGE}"
}

startMaster() {
    podman run -d -v "${SCRIPT_PATH}/../:/root/tase" -v "${SIGNAL_DIR}:/var/signal" -p 7425 --network "${NETWORK}" --name "${MASTER_CONTAINER}" "${MASTER_IMAGE}"
}

checkFiles() {
    local err=""
    local DIR="$1"
    local CONTAINER_NAME="$2"
    local REGEX_NEG="$3"
    local REGEX="$4"
    local EXPECTED_COUNT="$5"
    files=$(podman exec -it "${CONTAINER_NAME}" find "${DIR}" -maxdepth 1 -type f)
    files_sc=$?
    file_count=$(echo -e "${files}" | wc -l)
    if [ ${files_sc} -ne 0 ] || [ "${file_count}" -ne "${EXPECTED_COUNT}" ]; then
        err+="Unexpected number of files found ${file_count}/${EXPECTED_COUNT} \n${files}\n"
    fi

    grep_res_neg=$(echo -e "$files" | grep -E "${REGEX_NEG}")
    grep_neg_sc=$?
    grep_neg_count=$(echo -e "${grep_res_neg}" | wc -l)
    if [ ${grep_neg_sc} -lt 1 ]; then
        err+="Negative match errors total Match: ${grep_neg_count}: \n${grep_res_neg}\n"
    fi

    grep_res=$(echo -e "$files" | grep -E "${REGEX}")
    grep_sc=$?
    grep_count=$(echo -e "${grep_res}" | wc -l)
    if [ ${grep_sc} -gt 0 ] || [ "${grep_count}" -ne "${EXPECTED_COUNT}" ]; then
        err+="Positive match errors total Match: ${grep_count}/${EXPECTED_COUNT} \n$grep_res\n"
    fi

    if [ -n "$err" ]; then
        echo "$err"
    fi
}

master_checks() {
    checkFiles '/var/log/delete-by-days' "${MASTER_CONTAINER}" 'test-(Tue|Wed|Thu|Fri)\.log' 'test(-Mon)?\.log' 2
    checkFiles '/var/log/rotate-by-days-compress-prune' "${MASTER_CONTAINER}" 'test\.log-.*.gz' 'test\.log\s' 1
    checkFiles '/var/log/rotate-by-days-compress-prune/archives' "${MASTER_CONTAINER}" 'test\.log\s' 'test\.log-[0-9]+.gz' 3
}

deletion_checks() {
    checkFiles '/var/log/delete-by-days' "${DELETION_CONTAINER}" 'test-(Tue|Wed|Thu|Fri)\.log' 'test(-Mon)?\.log' 2
    checkFiles '/var/log/delete-by-size' "${DELETION_CONTAINER}" 'test\.log\.(16|15|14)-12-2012' 'test\.log\s|test\.log\.1[23]-12-2012' 3
}

rotation_checks() {
    checkFiles '/var/log/rotate-by-days-no-compress' "${ROTATION_CONTAINER}" 'test\.log-.*' 'test\.log\s' 1
    checkFiles '/var/log/rotate-by-days-no-compress/archives/' "${ROTATION_CONTAINER}" 'test\.log\s' 'test\.log-[0-9]+' 1
    checkFiles '/var/log/rotate-by-days-compress' "${ROTATION_CONTAINER}" 'test\.log-.*.gz' 'test\.log\s' 1
    checkFiles '/var/log/rotate-by-days-compress/archives' "${ROTATION_CONTAINER}" 'test\.log\s' 'test\.log-[0-9]+.gz' 1
    checkFiles '/var/log/rotate-by-days-compress-prune' "${ROTATION_CONTAINER}" 'test\.log-.*.gz' 'test\.log\s' 1
    checkFiles '/var/log/rotate-by-days-compress-prune/archives' "${ROTATION_CONTAINER}" 'test\.log\s' 'test\.log-[0-9]+.gz' 3
    checkFiles '/var/log/rotate-by-size-no-compress' "${ROTATION_CONTAINER}" 'test\.log-.*.gz' 'test\.log\s' 1
    checkFiles '/var/log/rotate-by-size-no-compress/archives' "${ROTATION_CONTAINER}" 'test\.log\s' 'test\.log-[0-9]+' 1
    checkFiles '/var/log/rotate-by-size-compress' "${ROTATION_CONTAINER}" 'test\.log-.*.gz' 'test\.log\s' 1
    checkFiles '/var/log/rotate-by-size-compress/archives' "${ROTATION_CONTAINER}" 'test\.log\s' 'test\.log-[0-9]+.gz' 1
    checkFiles '/var/log/rotate-by-size-no-compress-prune' "${ROTATION_CONTAINER}" 'test\.log-.*.gz' 'test\.log\s' 1
    checkFiles '/var/log/rotate-by-size-no-compress-prune/archives' "${ROTATION_CONTAINER}" 'test\.log\s' 'test\.log-[0-9]+' 2
}

testResults() {
    echo "=============Checking Deletions============="
    deletion_error=$(deletion_checks)
    if [ -n "${deletion_error}" ]; then
        echo -e "Deletion Files Check Failed: \n${deletion_error}"
    else
        echo "Deletion Files: OK"
    fi

    podman logs ${DELETION_CONTAINER} 2>&1 | grep -iE "\berrors?\b|\bfailures?\b|\bpanic\b|segfault|segmentation fault|memory leak|invalid memory (access|address)|null pointer"
    DELETION_RESULT=$?
    if [ "${DELETION_RESULT}" -lt 1 ]; then
        echo -e "Deletion Logs Check Failed: \n${DELETION_RESULT}"
    else
        echo "Deletion Logs: OK"
    fi
    echo

    echo "=============Checking Rotations============="
    rotation_error=$(rotation_checks)
    if [ -n "${rotation_error}" ]; then
        echo -e "Rotation Files Check Failed: \n${rotation_error}"
    else
        echo "Rotation Files: OK"
    fi

    podman logs ${ROTATION_CONTAINER} 2>&1 | grep -iE "\berrors?\b|\bfailures?\b|\bpanic\b|segfault|segmentation fault|memory leak|invalid memory (access|address)|null pointer"
    ROTATION_RESULT=$?
    if [ "${ROTATION_RESULT}" -lt 1 ]; then
        echo -e "Rotation Logs Check Failed: \n${ROTATION_RESULT}"
    else
        echo "Rotation Logs: OK"
    fi
    echo

    echo "=============Checking Master============="
    master_error=$(master_checks)
    if [ -n "${master_error}" ]; then
        echo -e "Master Files Check Failed: \n${master_error}"
    else
        echo "Master Files: OK"
    fi

    podman logs ${MASTER_CONTAINER} 2>&1 | grep -iE "\berrors?\b|\bfailures?\b|\bpanic\b|segfault|segmentation fault|memory leak|invalid memory (access|address)|null pointer"
    MASTER_RESULT=$?
    if [ "${MASTER_RESULT}" -lt 1 ]; then
        echo -e "Master failed: \n${MASTER_RESULT}"
    else
        echo "Master Logs: OK"
    fi
    echo

    if [ "${MASTER_RESULT}" -lt 1 ] || [ "${ROTATION_RESULT}" -lt 1 ] || [ "${DELETION_RESULT}" -lt 1 ] || [ -n "${deletion_error}" ] || [ -n "${rotation_error}" ] || [ -n "${master_error}" ]; then
        echo "============== TEST ERROR ABOVE=============="
        cleanupExit 1
    fi
}

trap cleanupExit SIGINT

prepare
startAgents

for i in {1..30}; do
    echo "Waiting agents to come up: ${i}. try!"
    if [ -f "/tmp/tase-signal/rotate-agent.rdy" ] && [ -f "/tmp/tase-signal/delete-agent.rdy" ]; then
        break
    fi
    if [ "$i" -gt 29 ]; then
        exit 1
    fi
    sleep 1
done

startMaster
for i in {1..30}; do
    echo "Waiting master to come up: ${i}. try!"
    if [ -f "/tmp/tase-signal/master-agent.rdy" ]; then
        break
    fi
    if [ "$i" -gt 29 ]; then
        exit 1
    fi
    sleep 1
done
sleep 20
testResults
cleanupExit 0
