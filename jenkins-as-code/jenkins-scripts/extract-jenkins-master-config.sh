#!/bin/bash
################################################################################
# Jenkins Master Configuration Extraction Script
# 
# This script extracts all important configuration files from a Jenkins master
# server into a single tarball for use in Ansible playbook configuration.
#
# Usage: sudo bash extract-jenkins-master-config.sh
################################################################################

set -e

# Configuration
TIMESTAMP=$(date +%Y%m%d-%H%M%S)
BACKUP_DIR="jenkins-master-configs-${TIMESTAMP}"
TARBALL="${BACKUP_DIR}.tar.gz"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Check if running as root
if [[ $EUID -ne 0 ]]; then
   echo -e "${RED}Error: This script must be run as root (use sudo)${NC}" 
   exit 1
fi

echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}Jenkins Master Config Extraction${NC}"
echo -e "${GREEN}========================================${NC}"
echo ""

# Create backup directory
mkdir -p "$BACKUP_DIR"
echo -e "${YELLOW}Created backup directory: $BACKUP_DIR${NC}"
echo ""

# Function to safely copy files/directories
safe_copy() {
    local source=$1
    local dest=$2
    local description=$3
    
    if [ -e "$source" ]; then
        echo -n "Extracting $description... "
        cp -r "$source" "$dest" 2>/dev/null && echo -e "${GREEN}✓${NC}" || echo -e "${RED}✗${NC}"
    else
        echo -e "${YELLOW}Skipping $description (not found)${NC}"
    fi
}

# Function to safely create tarball of directory
safe_tar() {
    local source=$1
    local dest=$2
    local description=$3
    
    if [ -e "$source" ]; then
        echo -n "Extracting $description... "
        tar -czf "$dest" "$source" 2>/dev/null && echo -e "${GREEN}✓${NC}" || echo -e "${RED}✗${NC}"
    else
        echo -e "${YELLOW}Skipping $description (not found)${NC}"
    fi
}

echo -e "${GREEN}Extracting configuration files...${NC}"
echo ""

# fail2ban configuration
safe_tar "/etc/fail2ban" "$BACKUP_DIR/fail2ban.tar.gz" "fail2ban configuration"

# nginx configuration
safe_tar "/etc/nginx" "$BACKUP_DIR/nginx.tar.gz" "nginx configuration"

# SSH configuration
safe_copy "/etc/ssh/sshd_config" "$BACKUP_DIR/sshd_config" "SSH daemon configuration"
safe_copy "/etc/ssh/ssh_config" "$BACKUP_DIR/ssh_config" "SSH client configuration"

# NTP configuration
safe_copy "/etc/ntp.conf" "$BACKUP_DIR/ntp.conf" "NTP configuration"
safe_copy "/etc/systemd/timesyncd.conf" "$BACKUP_DIR/timesyncd.conf" "systemd timesyncd configuration"

# Unattended upgrades configuration
safe_copy "/etc/apt/apt.conf.d/50unattended-upgrades" "$BACKUP_DIR/50unattended-upgrades" "unattended-upgrades configuration"
safe_copy "/etc/apt/apt.conf.d/20auto-upgrades" "$BACKUP_DIR/20auto-upgrades" "auto-upgrades configuration"

# Cron jobs
echo -n "Extracting cron jobs... "
mkdir -p "$BACKUP_DIR/cron"
cp -r /etc/cron.d/ "$BACKUP_DIR/cron/" 2>/dev/null || true
cp -r /etc/cron.daily/ "$BACKUP_DIR/cron/" 2>/dev/null || true
cp -r /etc/cron.hourly/ "$BACKUP_DIR/cron/" 2>/dev/null || true
cp -r /etc/cron.weekly/ "$BACKUP_DIR/cron/" 2>/dev/null || true
cp -r /etc/cron.monthly/ "$BACKUP_DIR/cron/" 2>/dev/null || true
echo -e "${GREEN}✓${NC}"

# User crontabs
echo -n "Extracting user crontabs... "
crontab -l > "$BACKUP_DIR/root-crontab.txt" 2>/dev/null || echo "# No root crontab" > "$BACKUP_DIR/root-crontab.txt"
crontab -u jenkins -l > "$BACKUP_DIR/jenkins-crontab.txt" 2>/dev/null || echo "# No jenkins crontab" > "$BACKUP_DIR/jenkins-crontab.txt"
echo -e "${GREEN}✓${NC}"

# rsyslog configuration
safe_tar "/etc/rsyslog.d" "$BACKUP_DIR/rsyslog.d.tar.gz" "rsyslog.d configuration"
safe_copy "/etc/rsyslog.conf" "$BACKUP_DIR/rsyslog.conf" "rsyslog configuration"

# LVM configuration
safe_copy "/etc/lvm/lvm.conf" "$BACKUP_DIR/lvm.conf" "LVM configuration"

# davfs2 configuration
safe_tar "/etc/davfs2" "$BACKUP_DIR/davfs2.tar.gz" "davfs2 configuration"

# systemd service overrides
echo -n "Extracting systemd service overrides... "
mkdir -p "$BACKUP_DIR/systemd"
cp -r /etc/systemd/system/*.d "$BACKUP_DIR/systemd/" 2>/dev/null || true
echo -e "${GREEN}✓${NC}"

# Network configuration
safe_copy "/etc/network/interfaces" "$BACKUP_DIR/network-interfaces" "network interfaces"
safe_copy "/etc/netplan" "$BACKUP_DIR/netplan" "netplan configuration"

# Security limits
safe_copy "/etc/security/limits.conf" "$BACKUP_DIR/limits.conf" "security limits"
safe_copy "/etc/security/limits.d" "$BACKUP_DIR/limits.d" "security limits.d"

# Sysctl configuration
safe_copy "/etc/sysctl.conf" "$BACKUP_DIR/sysctl.conf" "sysctl configuration"
safe_copy "/etc/sysctl.d" "$BACKUP_DIR/sysctl.d" "sysctl.d configuration"

# Environment variables
safe_copy "/etc/environment" "$BACKUP_DIR/environment" "environment variables"

# Hosts file
safe_copy "/etc/hosts" "$BACKUP_DIR/hosts" "hosts file"

# Sudoers configuration
safe_copy "/etc/sudoers" "$BACKUP_DIR/sudoers" "sudoers configuration"
safe_tar "/etc/sudoers.d" "$BACKUP_DIR/sudoers.d.tar.gz" "sudoers.d configuration"

# Jenkins configuration (if exists)
if [ -d "/var/lib/jenkins" ]; then
    echo -n "Extracting Jenkins configuration... "
    mkdir -p "$BACKUP_DIR/jenkins"
    cp /var/lib/jenkins/config.xml "$BACKUP_DIR/jenkins/" 2>/dev/null || true
    cp -r /var/lib/jenkins/*.xml "$BACKUP_DIR/jenkins/" 2>/dev/null || true
    cp -r /var/lib/jenkins/users "$BACKUP_DIR/jenkins/" 2>/dev/null || true
    echo -e "${GREEN}✓${NC}"
fi

# System information
echo -n "Collecting system information... "
{
    echo "# System Information"
    echo "# Generated: $(date)"
    echo ""
    echo "## OS Information"
    cat /etc/os-release
    echo ""
    echo "## Kernel Version"
    uname -a
    echo ""
    echo "## Installed Packages"
    apt-mark showmanual | sort
    echo ""
    echo "## Network Interfaces"
    ip addr
    echo ""
    echo "## Disk Usage"
    df -h
    echo ""
    echo "## Memory"
    free -h
} > "$BACKUP_DIR/system-info.txt"
echo -e "${GREEN}✓${NC}"

echo ""
echo -e "${GREEN}Creating final tarball...${NC}"
tar -czf "$TARBALL" "$BACKUP_DIR"

# Cleanup temporary directory
rm -rf "$BACKUP_DIR"

echo ""
echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}Extraction Complete!${NC}"
echo -e "${GREEN}========================================${NC}"
echo ""
echo -e "Configuration backup created: ${GREEN}$TARBALL${NC}"
echo -e "File size: $(du -h "$TARBALL" | cut -f1)"
echo ""
echo "To extract on another system:"
echo "  tar -xzf $TARBALL"
echo ""
echo "To view contents:"
echo "  tar -tzf $TARBALL"
echo ""

# Made with Bob
