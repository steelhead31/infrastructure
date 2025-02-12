!/bin/bash

echo "Extracting MongoDB Container Performance Characteristics..."

# Find the MongoDB container
MONGO_CONTAINER=$1

if [[ -z "$MONGO_CONTAINER" ]]; then
    echo "No running MongoDB container found."
    exit 1
fi

# Get container name
CONTAINER_NAME=$(docker inspect --format '{{.Name}}' "$MONGO_CONTAINER" | sed 's|/||')

# Get CPU usage
CPU_USAGE=$(docker stats --no-stream --format "{{.CPUPerc}}" "$MONGO_CONTAINER" | sed 's/%//')

# Get memory usage
MEMORY_USAGE=$(docker stats --no-stream --format "{{.MemUsage}}" "$MONGO_CONTAINER" | awk '{print $1}')
MEMORY_LIMIT=$(docker stats --no-stream --format "{{.MemUsage}}" "$MONGO_CONTAINER" | awk '{print $3}')

# Get network I/O
NETWORK_IO=$(docker inspect --format '{{json .NetworkSettings.Networks}}' "$MONGO_CONTAINER" | jq -r '..|.rx_bytes? // empty, .tx_bytes? // empty' | paste -sd ' ' -)
RX_BYTES=$(echo "$NETWORK_IO" | awk '{print $1}')
TX_BYTES=$(echo "$NETWORK_IO" | awk '{print $2}')

# Get disk I/O
DISK_IO=$(docker inspect --format '{{json .HostConfig.BlkioDeviceReadBps}},{{json .HostConfig.BlkioDeviceWriteBps}}' "$MONGO_CONTAINER" | sed 's/null/0/g' | tr -d '[]"')
READ_BYTES=$(echo "$DISK_IO" | cut -d',' -f1)
WRITE_BYTES=$(echo "$DISK_IO" | cut -d',' -f2)

# Get uptime
UPTIME=$(docker inspect --format '{{.State.StartedAt}}' "$MONGO_CONTAINER" | xargs -I{} date -d "{}" "+%Y-%m-%d %H:%M:%S")

# Get number of MongoDB processes inside the container
MONGO_PROCESSES=$(docker exec "$MONGO_CONTAINER" pgrep -c mongod)

# Display results
echo "MongoDB Container Name: $CONTAINER_NAME"
echo "MongoDB Container ID: $MONGO_CONTAINER"
echo "CPU Usage: $CPU_USAGE%"
echo "Memory Usage: $MEMORY_USAGE MB / $MEMORY_LIMIT MB"
echo "Network I/O: Received $RX_BYTES bytes, Sent $TX_BYTES bytes"
echo "Disk I/O: Read $READ_BYTES Bps, Write $WRITE_BYTES Bps"
echo "Container Uptime: $UPTIME"
echo "MongoDB Running Processes: $MONGO_PROCESSES"

echo "Extraction complete."
