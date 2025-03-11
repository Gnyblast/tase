#!/bin/bash

if ! zig build; then
    exit 1
fi

# Start both processes in the background
./zig-out/bin/tase --agent --config ./app.yaml --secret b9d36fa4b6cd3d8a2f5527c792143bfc --port 7424 --master-host localhost --master-port 7423 &
AGENT_PID=$!

./zig-out/bin/tase --master --config ./app.yaml &
MASTER_PID=$!

echo "master: $MASTER_PID"
echo "agent: $AGENT_PID"

# Function to terminate both process groups
terminate() {
    echo "Terminating processes..."
    kill $MASTER_PID 2>/dev/null
    kill $AGENT_PID 2>/dev/null
    wait $MASTER_PID $AGENT_PID 2>/dev/null
    exit 0
}

# Trap CTRL+C (SIGINT) and call the terminate function
trap terminate SIGINT

# Wait for both processes to complete
wait
