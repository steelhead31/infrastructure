#!/bin/bash

echo "Extracting CPU Performance Information..."

# CPU Model and Architecture
CPU_MODEL=$(awk -F': ' '/model name/ {print $2; exit}' /proc/cpuinfo)
CPU_ARCH=$(uname -m)

# CPU Core Information
TOTAL_CORES=$(nproc)
PHYSICAL_CPUS=$(grep "physical id" /proc/cpuinfo | sort -u | wc -l)
THREADS_PER_CORE=$(awk -F': ' '/siblings/ {sibs=$2} /cpu cores/ {cores=$2} END {print sibs/cores}' /proc/cpuinfo)

# CPU Frequency
MAX_FREQ=$(lscpu | awk -F': ' '/CPU max MHz/ {print $2 " MHz"}')
CURRENT_FREQ=$(awk '{print $1 " MHz"}' /sys/devices/system/cpu/cpu0/cpufreq/scaling_cur_freq 2>/dev/null || echo "Unavailable")

# CPU Load Average
LOAD_AVG=$(awk '{print "1 min: " $1 ", 5 min: " $2 ", 15 min: " $3}' /proc/loadavg)

# CPU Usage (Total percentage across all cores)
CPU_USAGE=$(top -bn1 | grep "Cpu(s)" | awk '{print $2 + $4 "%"}')

# Display Results
echo "CPU Model: $CPU_MODEL"
echo "CPU Architecture: $CPU_ARCH"
echo "Total CPU Cores: $TOTAL_CORES"
echo "Physical CPUs: $PHYSICAL_CPUS"
echo "Threads per Core: $THREADS_PER_CORE"
echo "Max CPU Frequency: $MAX_FREQ"
echo "Current CPU Frequency: $CURRENT_FREQ"
echo "CPU Load Average: $LOAD_AVG"

echo "Extraction complete."
