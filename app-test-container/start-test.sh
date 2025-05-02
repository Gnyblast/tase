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
podman container rm -f "${DELETION_CONTAINER}"
podman container rm -f "${ROTATION_CONTAINER}"
podman container rm -f "${MASTER_CONTAINER}"
podman network rm "${NETWORK}"

podman network create "${NETWORK}"

SIGNAL_DIR="/tmp/tase-signal"
rm -rf "${SIGNAL_DIR}"
mkdir -p "${SIGNAL_DIR}"

podman run -d -v "${SCRIPT_PATH}/../:/root/tase" -v "${SIGNAL_DIR}:/var/signal" -p 7424 --network "${NETWORK}" --name "${DELETION_CONTAINER}" "${DELETION_AGENT_IMAGE}"
podman run -d -v "${SCRIPT_PATH}/../:/root/tase" -v "${SIGNAL_DIR}:/var/signal" -p 7425 --network "${NETWORK}" --name "${ROTATION_CONTAINER}" "${ROTATION_AGENT_IMAGE}"

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
podman run -d -v "${SCRIPT_PATH}/../:/root/tase" -p 7425 --network "${NETWORK}" --name "${MASTER_CONTAINER}" "${MASTER_IMAGE}"

sleep 60
podman container stop "${DELETION_CONTAINER}"
podman container stop "${ROTATION_CONTAINER}"
podman container stop "${MASTER_CONTAINER}"
podman container prune -f
