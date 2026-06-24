#!/bin/bash
################################################################################
# Jenkins Complete Backup Script
# 
# Purpose: Create a single comprehensive backup of Jenkins and infrastructure
# Usage: ./jenkins-complete-backup.sh [options]
# 
# This script creates a unified backup containing:
# - Jenkins configuration (jobs, plugins, credentials, users, nodes)
# - Infrastructure configuration (nginx, SSL, systemd, firewall, cron)
# - All necessary metadata and restore instructions
#
# Output: Single .tar.gz file ready for transfer and restoration
#
# Author: Adoptium Infrastructure Team
# Date: 2026-06-22
################################################################################

set -euo pipefail

# Configuration
JENKINS_HOME="${JENKINS_HOME:-/home/jenkins/.jenkins}"
BACKUP_DIR="${BACKUP_DIR:-./jenkins-complete-backups}"
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
BACKUP_NAME="jenkins-complete-backup-${TIMESTAMP}"
BACKUP_PATH="${BACKUP_DIR}/${BACKUP_NAME}"
FINAL_ARCHIVE="${BACKUP_DIR}/${BACKUP_NAME}.tar.gz"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# Logging functions
log_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

log_section() {
    echo ""
    echo -e "${BLUE}========================================${NC}"
    echo -e "${BLUE}$1${NC}"
    echo -e "${BLUE}========================================${NC}"
}

log_subsection() {
    echo -e "${CYAN}--- $1 ---${NC}"
}

# Display usage information
usage() {
    cat <<EOF
Jenkins Complete Backup Script

Purpose: Create a single comprehensive backup of Jenkins and infrastructure

Usage: $0 [OPTIONS]

Options:
  -h, --help              Show this help message
  -j, --jenkins-home DIR  Jenkins home directory (default: /home/jenkins/.jenkins)
  -o, --output DIR        Backup output directory (default: ./jenkins-complete-backups)
  -n, --name NAME         Custom backup name (default: jenkins-complete-backup-TIMESTAMP)
  -v, --verbose           Verbose output
  --skip-certs            Skip SSL certificate backup
  --skip-infra            Skip infrastructure backup (Jenkins only)
  --skip-jenkins          Skip Jenkins backup (infrastructure only)

Examples:
  $0                                    # Complete backup with defaults
  $0 -j /home/jenkins -o /backups      # Custom paths
  $0 --skip-certs                       # Skip SSL certificates
  $0 --skip-infra                       # Jenkins configuration only

Environment Variables:
  JENKINS_HOME            Jenkins home directory
  BACKUP_DIR              Backup output directory

Requirements:
  - Must be run as root (for infrastructure backup)
  - Read access to Jenkins home
  - Standard Unix tools (tar, gzip, find)

Output:
  Single .tar.gz file containing complete backup ready for transfer

EOF
    exit 0
}

# Parse command line arguments
SKIP_CERTS=false
SKIP_INFRA=false
SKIP_JENKINS=false
VERBOSE=false

while [[ $# -gt 0 ]]; do
    case $1 in
        -h|--help)
            usage
            ;;
        -j|--jenkins-home)
            JENKINS_HOME="$2"
            shift 2
            ;;
        -o|--output)
            BACKUP_DIR="$2"
            shift 2
            ;;
        -n|--name)
            BACKUP_NAME="$2"
            BACKUP_PATH="${BACKUP_DIR}/${BACKUP_NAME}"
            FINAL_ARCHIVE="${BACKUP_DIR}/${BACKUP_NAME}.tar.gz"
            shift 2
            ;;
        -v|--verbose)
            VERBOSE=true
            shift
            ;;
        --skip-certs)
            SKIP_CERTS=true
            shift
            ;;
        --skip-infra)
            SKIP_INFRA=true
            shift
            ;;
        --skip-jenkins)
            SKIP_JENKINS=true
            shift
            ;;
        *)
            log_error "Unknown option: $1"
            usage
            ;;
    esac
done

# Check prerequisites
check_prerequisites() {
    log_section "Checking Prerequisites"
    
    # Check if running as root (needed for infrastructure backup)
    if [ "$EUID" -ne 0 ] && [ "$SKIP_INFRA" = false ]; then
        log_error "This script must be run as root for complete backup"
        log_error "Run: sudo $0"
        log_error "Or use --skip-infra to backup Jenkins only"
        exit 1
    fi
    
    # Check if Jenkins home exists
    if [ "$SKIP_JENKINS" = false ]; then
        if [ ! -d "${JENKINS_HOME}" ]; then
            log_error "Jenkins home directory not found: ${JENKINS_HOME}"
            log_error "Please specify correct path with -j option"
            exit 1
        fi
        
        if [ ! -r "${JENKINS_HOME}" ]; then
            log_error "No read permission for Jenkins home: ${JENKINS_HOME}"
            exit 1
        fi
    fi
    
    # Check required commands
    for cmd in tar gzip find; do
        if ! command -v $cmd &> /dev/null; then
            log_error "Required command not found: $cmd"
            exit 1
        fi
    done
    
    # Check disk space
    REQUIRED_SPACE_MB=2000
    AVAILABLE_SPACE_MB=$(df -BM "${BACKUP_DIR%/*}" 2>/dev/null | awk 'NR==2 {print $4}' | sed 's/M//' || echo "5000")
    if [ "${AVAILABLE_SPACE_MB}" -lt "${REQUIRED_SPACE_MB}" ]; then
        log_warn "Low disk space: ${AVAILABLE_SPACE_MB}MB available (recommended: ${REQUIRED_SPACE_MB}MB)"
        read -p "Continue anyway? (y/N) " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            exit 1
        fi
    fi
    
    log_info "Running as: $(whoami)"
    log_info "Hostname: $(hostname)"
    log_info "Jenkins home: ${JENKINS_HOME}"
    log_info "Backup destination: ${FINAL_ARCHIVE}"
    log_info "Prerequisites check passed!"
}

# Create backup directory structure
create_backup_structure() {
    log_section "Creating Backup Structure"
    
    mkdir -p "${BACKUP_PATH}"
    mkdir -p "${BACKUP_PATH}/jenkins"
    mkdir -p "${BACKUP_PATH}/infrastructure"
    mkdir -p "${BACKUP_PATH}/metadata"
    
    log_info "Backup directory structure created"
}

# Backup Jenkins configuration
backup_jenkins_config() {
    if [ "$SKIP_JENKINS" = true ]; then
        log_section "Skipping Jenkins Backup"
        return
    fi
    
    log_section "Backing Up Jenkins Configuration"
    
    local jenkins_backup="${BACKUP_PATH}/jenkins"
    
    # Create subdirectories
    mkdir -p "${jenkins_backup}/config"
    mkdir -p "${jenkins_backup}/plugins"
    mkdir -p "${jenkins_backup}/jobs"
    mkdir -p "${jenkins_backup}/secrets"
    mkdir -p "${jenkins_backup}/users"
    mkdir -p "${jenkins_backup}/nodes"
    
    # Core configuration
    log_subsection "Core Configuration"
    if [ -f "${JENKINS_HOME}/config.xml" ]; then
        cp "${JENKINS_HOME}/config.xml" "${jenkins_backup}/config/"
        log_info "✓ config.xml"
    fi
    
    # System configuration files
    local config_patterns=(
        "*.xml"
        "*.key"
        "*.key.enc"
    )
    
    for pattern in "${config_patterns[@]}"; do
        find "${JENKINS_HOME}" -maxdepth 1 -name "$pattern" -type f -exec cp {} "${jenkins_backup}/config/" \; 2>/dev/null || true
    done
    log_info "✓ System configuration files"
    
    # Plugins
    log_subsection "Plugins"
    if [ -d "${JENKINS_HOME}/plugins" ]; then
        # Create plugins list
        echo "# Jenkins Plugins - ${TIMESTAMP}" > "${jenkins_backup}/plugins/plugins.txt"
        echo "# Format: plugin-name:version" >> "${jenkins_backup}/plugins/plugins.txt"
        echo "" >> "${jenkins_backup}/plugins/plugins.txt"
        
        local plugin_count=0
        local plugin_file_count=0
        
        # Document plugin versions from manifests
        for plugin_dir in ${JENKINS_HOME}/plugins/*/; do
            if [ -d "$plugin_dir" ]; then
                plugin_name=$(basename "$plugin_dir")
                manifest="${plugin_dir}META-INF/MANIFEST.MF"
                
                if [ -f "$manifest" ]; then
                    version=$(grep "Plugin-Version:" "$manifest" | cut -d' ' -f2 | tr -d '\r\n' || echo "unknown")
                    echo "${plugin_name}:${version}" >> "${jenkins_backup}/plugins/plugins.txt"
                    ((plugin_count++))
                fi
            fi
        done
        
        # Backup actual plugin files (.jpi and .hpi files)
        mkdir -p "${jenkins_backup}/plugins/files"
        for plugin_file in ${JENKINS_HOME}/plugins/*.jpi ${JENKINS_HOME}/plugins/*.hpi; do
            if [ -f "$plugin_file" ]; then
                cp "$plugin_file" "${jenkins_backup}/plugins/files/"
                ((plugin_file_count++))
                [ "$VERBOSE" = true ] && log_info "  ✓ $(basename $plugin_file)"
            fi
        done
        
        # Backup pinned plugins list
        if [ -f "${JENKINS_HOME}/plugins/plugins.txt" ]; then
            cp "${JENKINS_HOME}/plugins/plugins.txt" "${jenkins_backup}/plugins/pinned-plugins.txt"
        fi
        
        log_info "✓ ${plugin_count} plugins documented, ${plugin_file_count} plugin files backed up"
    else
        log_warn "No plugins directory found at ${JENKINS_HOME}/plugins"
    fi
    
    # Jobs
    log_subsection "Job Configurations"
    if [ -d "${JENKINS_HOME}/jobs" ]; then
        local job_count=0
        while IFS= read -r -d '' config_file; do
            rel_path="${config_file#${JENKINS_HOME}/jobs/}"
            dest_dir="${jenkins_backup}/jobs/$(dirname "$rel_path")"
            mkdir -p "$dest_dir"
            cp "$config_file" "$dest_dir/"
            ((job_count++))
        done < <(find "${JENKINS_HOME}/jobs" -name "config.xml" -type f -print0)
        
        # Backup nextBuildNumber files
        find "${JENKINS_HOME}/jobs" -name "nextBuildNumber" -type f -print0 | while IFS= read -r -d '' build_num_file; do
            rel_path="${build_num_file#${JENKINS_HOME}/jobs/}"
            dest_dir="${jenkins_backup}/jobs/$(dirname "$rel_path")"
            mkdir -p "$dest_dir"
            cp "$build_num_file" "$dest_dir/"
        done
        
        log_info "✓ ${job_count} job configurations"
    fi
    
    # Secrets and credentials
    log_subsection "Secrets and Credentials"
    if [ -d "${JENKINS_HOME}/secrets" ]; then
        cp -r "${JENKINS_HOME}/secrets" "${jenkins_backup}/"
        log_info "✓ Secrets directory"
    fi
    
    if [ -d "${JENKINS_HOME}/credentials" ]; then
        cp -r "${JENKINS_HOME}/credentials" "${jenkins_backup}/"
        log_info "✓ Credentials"
    fi
    
    for key_file in identity.key.enc secret.key secret.key.not-so-secret; do
        if [ -f "${JENKINS_HOME}/${key_file}" ]; then
            cp "${JENKINS_HOME}/${key_file}" "${jenkins_backup}/secrets/" 2>/dev/null || true
        fi
    done
    
    # Users
    log_subsection "Users"
    if [ -d "${JENKINS_HOME}/users" ]; then
        cp -r "${JENKINS_HOME}/users" "${jenkins_backup}/"
        local user_count=$(find "${JENKINS_HOME}/users" -mindepth 1 -maxdepth 1 -type d | wc -l)
        log_info "✓ ${user_count} user configurations"
    fi
    
    # Nodes
    log_subsection "Nodes"
    if [ -d "${JENKINS_HOME}/nodes" ]; then
        local node_count=0
        for node_dir in ${JENKINS_HOME}/nodes/*/; do
            if [ -d "$node_dir" ]; then
                node_name=$(basename "$node_dir")
                mkdir -p "${jenkins_backup}/nodes/${node_name}"
                find "$node_dir" -maxdepth 1 -name "*.xml" -exec cp {} "${jenkins_backup}/nodes/${node_name}/" \;
                ((node_count++))
            fi
        done
        log_info "✓ ${node_count} node configurations"
    fi
    
    # Additional files
    log_subsection "Additional Files"
    for dir in init.groovy.d userContent views; do
        if [ -d "${JENKINS_HOME}/${dir}" ]; then
            cp -r "${JENKINS_HOME}/${dir}" "${jenkins_backup}/"
            log_info "✓ ${dir}"
        fi
    done
    
    log_info "Jenkins configuration backup complete"
}

# Backup infrastructure
backup_infrastructure() {
    if [ "$SKIP_INFRA" = true ]; then
        log_section "Skipping Infrastructure Backup"
        return
    fi
    
    log_section "Backing Up Infrastructure"
    
    local infra_backup="${BACKUP_PATH}/infrastructure"
    
    # Create subdirectories
    mkdir -p "${infra_backup}/nginx"
    mkdir -p "${infra_backup}/ssl"
    mkdir -p "${infra_backup}/systemd"
    mkdir -p "${infra_backup}/firewall"
    mkdir -p "${infra_backup}/cron"
    mkdir -p "${infra_backup}/system"
    
    # Nginx
    log_subsection "Nginx Configuration"
    if [ -d "/etc/nginx" ]; then
        cp -r /etc/nginx "${infra_backup}/"
        if command -v nginx &> /dev/null; then
            nginx -v 2>&1 | tee "${infra_backup}/nginx/version.txt" > /dev/null
            nginx -t 2>&1 | tee "${infra_backup}/nginx/config-test.txt" > /dev/null || true
        fi
        log_info "✓ Nginx configuration"
    else
        log_warn "Nginx not found"
    fi
    
    # SSL Certificates
    if [ "$SKIP_CERTS" = false ]; then
        log_subsection "SSL Certificates"
        local cert_count=0
        for ssl_dir in /etc/ssl /etc/letsencrypt /etc/nginx/ssl /etc/pki/tls; do
            if [ -d "$ssl_dir" ]; then
                parent=$(basename $(dirname "$ssl_dir"))
                mkdir -p "${infra_backup}/ssl/${parent}"
                cp -r "$ssl_dir" "${infra_backup}/ssl/${parent}/"
                ((cert_count++))
            fi
        done
        if [ $cert_count -gt 0 ]; then
            log_info "✓ SSL certificates from ${cert_count} locations"
            log_warn "SSL private keys included - keep backup secure!"
        else
            log_warn "No SSL certificates found"
        fi
    else
        log_info "Skipping SSL certificates (--skip-certs)"
    fi
    
    # Systemd services
    log_subsection "Systemd Services"
    if command -v systemctl &> /dev/null; then
        for service in jenkins nginx httpd apache2; do
            local service_file=$(systemctl show -p FragmentPath "${service}.service" 2>/dev/null | cut -d= -f2)
            if [ -n "$service_file" ] && [ -f "$service_file" ]; then
                cp "$service_file" "${infra_backup}/systemd/"
                [ "$VERBOSE" = true ] && log_info "✓ ${service}.service"
            fi
        done
        log_info "✓ Systemd service files"
    fi
    
    # Firewall
    log_subsection "Firewall Rules"
    if command -v iptables &> /dev/null; then
        iptables-save > "${infra_backup}/firewall/iptables-rules.txt" 2>/dev/null || true
        log_info "✓ iptables rules"
    fi
    if command -v ufw &> /dev/null; then
        ufw status verbose > "${infra_backup}/firewall/ufw-status.txt" 2>/dev/null || true
        [ -d "/etc/ufw" ] && cp -r /etc/ufw "${infra_backup}/firewall/"
        log_info "✓ UFW configuration"
    fi
    
    # Cron jobs
    log_subsection "Cron Jobs"
    [ -f "/etc/crontab" ] && cp /etc/crontab "${infra_backup}/cron/system-crontab"
    for cron_dir in /etc/cron.d /etc/cron.daily /etc/cron.hourly /etc/cron.weekly /etc/cron.monthly; do
        if [ -d "$cron_dir" ]; then
            dir_name=$(basename "$cron_dir")
            mkdir -p "${infra_backup}/cron/${dir_name}"
            cp -r "$cron_dir"/* "${infra_backup}/cron/${dir_name}/" 2>/dev/null || true
        fi
    done
    crontab -u jenkins -l > "${infra_backup}/cron/jenkins-user-crontab.txt" 2>/dev/null || true
    log_info "✓ Cron jobs"
    
    # System configuration
    log_subsection "System Configuration"
    for file in /etc/hosts /etc/hostname /etc/resolv.conf /etc/environment; do
        [ -f "$file" ] && cp "$file" "${infra_backup}/system/"
    done
    log_info "✓ System configuration files"
    
    log_info "Infrastructure backup complete"
}

# Create comprehensive metadata
create_metadata() {
    log_section "Creating Backup Metadata"
    
    cat > "${BACKUP_PATH}/metadata/README.md" <<EOF
# Jenkins Complete Backup

**Backup Date:** $(date)  
**Timestamp:** ${TIMESTAMP}  
**Hostname:** $(hostname)  
**IP Address:** $(hostname -I 2>/dev/null | awk '{print $1}' || echo "N/A")

## Contents

This backup contains:

### Jenkins Configuration
- Core configuration files (config.xml, etc.)
- Plugin list with versions
- Job configurations (no build history)
- Secrets and credentials
- User configurations
- Node configurations
- Views and UI settings
- Init scripts and user content

### Infrastructure Configuration
- Nginx/Apache configuration
- SSL/TLS certificates and keys
- Systemd service files
- Firewall rules
- Cron jobs
- System configuration

## What's NOT Included

- Build artifacts
- Workspaces
- Build logs and history
- Temporary files
- Caches

## System Information

**Operating System:** $(cat /etc/os-release 2>/dev/null | grep PRETTY_NAME | cut -d'"' -f2 || uname -s)  
**Kernel:** $(uname -r)  
**Jenkins Version:** $(grep -oP '(?<=<version>)[^<]+' "${JENKINS_HOME}/config.xml" 2>/dev/null || echo "Unknown")

## Quick Start Restore

1. **Transfer this backup to new server**
   \`\`\`bash
   scp ${BACKUP_NAME}.tar.gz user@new-server:/tmp/
   \`\`\`

2. **Extract on new server**
   \`\`\`bash
   cd /tmp
   tar -xzf ${BACKUP_NAME}.tar.gz
   cd ${BACKUP_NAME}
   \`\`\`

3. **Follow detailed restore guide**
   \`\`\`bash
   cat metadata/RESTORE-GUIDE.md
   \`\`\`

## Security Warning

⚠️ **CRITICAL:** This backup contains:
- Jenkins secrets and credentials
- SSL private keys
- Sensitive configuration data

**Actions Required:**
1. Encrypt this backup immediately
2. Store in secure location
3. Restrict access appropriately
4. Delete unencrypted copies

**Encryption Example:**
\`\`\`bash
gpg --encrypt --recipient your-key@example.com ${BACKUP_NAME}.tar.gz
\`\`\`

## File Structure

\`\`\`
${BACKUP_NAME}/
├── jenkins/              # Jenkins configuration
│   ├── config/          # Core config files
│   ├── plugins/         # Plugin list
│   ├── jobs/            # Job configurations
│   ├── secrets/         # Secrets and keys
│   ├── users/           # User configs
│   └── nodes/           # Node configs
├── infrastructure/       # Infrastructure config
│   ├── nginx/           # Nginx configuration
│   ├── ssl/             # SSL certificates
│   ├── systemd/         # Service files
│   ├── firewall/        # Firewall rules
│   ├── cron/            # Cron jobs
│   └── system/          # System config
└── metadata/            # Backup metadata
    ├── README.md        # This file
    ├── RESTORE-GUIDE.md # Detailed restore instructions
    └── inventory.txt    # File inventory
\`\`\`

## Support

For issues or questions:
1. Review RESTORE-GUIDE.md
2. Check Jenkins documentation
3. Contact infrastructure team

---
*Generated by jenkins-complete-backup.sh*
EOF

    # Create detailed restore guide
    cat > "${BACKUP_PATH}/metadata/RESTORE-GUIDE.md" <<'EOFGUIDE'
# Complete Restore Guide

## Prerequisites

- New server with compatible OS
- Root access
- Jenkins installed (same or newer version)
- Basic packages: nginx, systemd, etc.

## Step-by-Step Restore Process

### Phase 1: Preparation

1. **Stop Jenkins on new server**
   ```bash
   sudo systemctl stop jenkins
   ```

2. **Backup existing configuration (if any)**
   ```bash
   sudo mv /var/lib/jenkins /var/lib/jenkins.old.$(date +%Y%m%d)
   ```

3. **Extract backup**
   ```bash
   cd /tmp
   tar -xzf jenkins-complete-backup-TIMESTAMP.tar.gz
   cd jenkins-complete-backup-TIMESTAMP
   ```

### Phase 2: Restore Jenkins Configuration

1. **Create Jenkins home directory**
   ```bash
   sudo mkdir -p /var/lib/jenkins
   ```

2. **Copy Jenkins configuration**
   ```bash
   sudo cp -r jenkins/* /var/lib/jenkins/
   ```

3. **Update Jenkins URL** (if hostname changed)
   ```bash
   NEW_URL="https://new-jenkins.example.com"
   sudo sed -i "s|<jenkinsUrl>.*</jenkinsUrl>|<jenkinsUrl>${NEW_URL}/</jenkinsUrl>|" \
       /var/lib/jenkins/jenkins.model.JenkinsLocationConfiguration.xml
   ```

4. **Set ownership**
   ```bash
   sudo chown -R jenkins:jenkins /var/lib/jenkins
   ```

5. **Install plugins**
   ```bash
   # Review plugin list
   cat jenkins/plugins/plugins.txt
   
   # Install Jenkins Plugin Manager CLI or use UI after start
   ```

### Phase 3: Restore Infrastructure

1. **Review and update Nginx configuration**
   ```bash
   # Check for old hostname/IP references
   grep -r "server_name\|proxy_pass" infrastructure/nginx/
   
   # Update as needed
   sudo cp -r infrastructure/nginx/nginx /etc/nginx
   
   # Update server_name
   sudo sed -i 's/old-hostname/new-hostname/g' /etc/nginx/sites-available/*
   
   # Test configuration
   sudo nginx -t
   ```

2. **Restore SSL certificates**
   
   **Option A: Same hostname (restore existing certs)**
   ```bash
   sudo cp -r infrastructure/ssl/etc/ssl/* /etc/ssl/
   sudo cp -r infrastructure/ssl/etc/letsencrypt/* /etc/letsencrypt/
   ```
   
   **Option B: New hostname (request new certs)**
   ```bash
   sudo certbot --nginx -d new-hostname.example.com
   ```

3. **Restore systemd services**
   ```bash
   sudo cp infrastructure/systemd/*.service /etc/systemd/system/
   sudo systemctl daemon-reload
   ```

4. **Configure firewall**
   ```bash
   # Review rules first
   cat infrastructure/firewall/iptables-rules.txt
   
   # Apply if appropriate
   sudo iptables-restore < infrastructure/firewall/iptables-rules.txt
   
   # Or use UFW
   sudo ufw allow 80/tcp
   sudo ufw allow 443/tcp
   sudo ufw allow 8080/tcp
   sudo ufw enable
   ```

5. **Restore cron jobs**
   ```bash
   # Review first
   cat infrastructure/cron/system-crontab
   
   # Copy if appropriate
   sudo cp infrastructure/cron/system-crontab /etc/crontab
   sudo cp infrastructure/cron/cron.d/* /etc/cron.d/
   ```

### Phase 4: Start Services

1. **Start Jenkins**
   ```bash
   sudo systemctl start jenkins
   sudo systemctl enable jenkins
   ```

2. **Start Nginx**
   ```bash
   sudo systemctl start nginx
   sudo systemctl enable nginx
   ```

3. **Check status**
   ```bash
   sudo systemctl status jenkins nginx
   ```

### Phase 5: Verification

1. **Check Jenkins is running**
   ```bash
   curl -I http://localhost:8080
   ```

2. **Check Nginx proxy**
   ```bash
   curl -I https://new-hostname.example.com
   ```

3. **Access Jenkins UI**
   - Open browser to https://new-hostname.example.com
   - Verify login works
   - Check job configurations
   - Test a simple job

4. **Review logs**
   ```bash
   sudo journalctl -u jenkins -n 100
   sudo journalctl -u nginx -n 100
   tail -f /var/log/jenkins/jenkins.log
   ```

### Phase 6: Post-Restore Tasks

1. **Update node configurations**
   - Review node settings in Jenkins UI
   - Update any hardcoded paths or IPs
   - Test node connectivity

2. **Verify credentials**
   - Check all credentials are present
   - Test credential access in jobs

3. **Update job configurations**
   - Review jobs for hardcoded hostnames/IPs
   - Update SCM URLs if needed
   - Test critical jobs

4. **Configure backups**
   - Set up regular backup schedule
   - Test backup/restore procedure

## Troubleshooting

### Jenkins Won't Start

```bash
# Check logs
sudo journalctl -u jenkins -n 50
tail -f /var/log/jenkins/jenkins.log

# Check permissions
ls -la /var/lib/jenkins
sudo chown -R jenkins:jenkins /var/lib/jenkins

# Check port availability
sudo ss -tlnp | grep 8080
```

### Nginx Configuration Errors

```bash
# Test configuration
sudo nginx -t

# Check error log
sudo tail -f /var/log/nginx/error.log

# Verify SSL certificates
sudo openssl x509 -in /etc/ssl/certs/jenkins.crt -noout -text
```

### Plugin Issues

```bash
# Check plugin directory
ls -la /var/lib/jenkins/plugins/

# Reinstall plugins from list
cat /var/lib/jenkins/plugins/plugins.txt

# Use Jenkins Plugin Manager or UI
```

### Permission Denied Errors

```bash
# Fix ownership
sudo chown -R jenkins:jenkins /var/lib/jenkins

# Fix permissions
sudo chmod -R 755 /var/lib/jenkins
sudo chmod 600 /var/lib/jenkins/secrets/*
```

## Rollback Procedure

If restore fails:

```bash
# Stop services
sudo systemctl stop jenkins nginx

# Restore old configuration
sudo rm -rf /var/lib/jenkins
sudo mv /var/lib/jenkins.old.TIMESTAMP /var/lib/jenkins

# Restart services
sudo systemctl start jenkins nginx
```

## Security Checklist

- [ ] SSL certificates valid and match hostname
- [ ] Firewall rules appropriate for environment
- [ ] File permissions correct (especially secrets)
- [ ] Jenkins security realm configured
- [ ] User accounts reviewed
- [ ] Credentials tested
- [ ] Backup encryption verified
- [ ] Old server decommissioned securely

## Additional Resources

- Jenkins Documentation: https://www.jenkins.io/doc/
- Nginx Documentation: https://nginx.org/en/docs/
- Let's Encrypt: https://letsencrypt.org/docs/

---
*For support, contact infrastructure team*
EOFGUIDE

    # Create file inventory
    {
        echo "File Inventory"
        echo "=============="
        echo "Generated: $(date)"
        echo ""
        echo "Total files: $(find "${BACKUP_PATH}" -type f | wc -l)"
        echo "Total size: $(du -sh "${BACKUP_PATH}" | cut -f1)"
        echo ""
        echo "Breakdown:"
        echo "  Jenkins configs: $(find "${BACKUP_PATH}/jenkins" -type f 2>/dev/null | wc -l)"
        echo "  Job configs: $(find "${BACKUP_PATH}/jenkins/jobs" -name "config.xml" 2>/dev/null | wc -l)"
        echo "  Plugins: $(grep -c ":" "${BACKUP_PATH}/jenkins/plugins/plugins.txt" 2>/dev/null || echo 0)"
        echo "  Infrastructure files: $(find "${BACKUP_PATH}/infrastructure" -type f 2>/dev/null | wc -l)"
    } > "${BACKUP_PATH}/metadata/inventory.txt"
    
    log_info "Metadata created"
}

# Create final archive
create_final_archive() {
    log_section "Creating Final Archive"
    
    log_info "Compressing backup..."
    tar -czf "${FINAL_ARCHIVE}" -C "${BACKUP_DIR}" "${BACKUP_NAME}"
    
    local archive_size=$(du -h "${FINAL_ARCHIVE}" | cut -f1)
    log_info "✓ Archive created: ${FINAL_ARCHIVE}"
    log_info "✓ Archive size: ${archive_size}"
    
    # Calculate checksum
    log_info "Calculating checksum..."
    sha256sum "${FINAL_ARCHIVE}" > "${FINAL_ARCHIVE}.sha256"
    local checksum=$(cat "${FINAL_ARCHIVE}.sha256" | cut -d' ' -f1)
    log_info "✓ SHA256: ${checksum}"
    
    # Clean up temporary directory
    log_info "Cleaning up temporary files..."
    rm -rf "${BACKUP_PATH}"
    
    log_info "Archive creation complete"
}

# Display summary
display_summary() {
    log_section "Backup Complete!"
    
    echo ""
    echo "╔════════════════════════════════════════════════════════════╗"
    echo "║           Jenkins Complete Backup Summary                  ║"
    echo "╚════════════════════════════════════════════════════════════╝"
    echo ""
    echo "Backup Details:"
    echo "  📦 Archive: ${FINAL_ARCHIVE}"
    echo "  📊 Size: $(du -h ${FINAL_ARCHIVE} | cut -f1)"
    echo "  🔐 Checksum: ${FINAL_ARCHIVE}.sha256"
    echo "  ⏰ Timestamp: ${TIMESTAMP}"
    echo "  🖥️  Source: $(hostname)"
    echo ""
    echo "What's Included:"
    if [ "$SKIP_JENKINS" = false ]; then
        echo "  ✅ Jenkins configuration"
        echo "  ✅ Job definitions"
        echo "  ✅ Plugins list"
        echo "  ✅ Secrets and credentials"
        echo "  ✅ User configurations"
    fi
    if [ "$SKIP_INFRA" = false ]; then
        echo "  ✅ Nginx/Apache configuration"
        [ "$SKIP_CERTS" = false ] && echo "  ✅ SSL certificates"
        echo "  ✅ Systemd services"
        echo "  ✅ Firewall rules"
        echo "  ✅ Cron jobs"
    fi
    echo ""
    echo "Next Steps:"
    echo "  1️⃣  Transfer backup to safe location"
    echo "  2️⃣  Encrypt the backup:"
    echo "     gpg --encrypt --recipient your-key@example.com ${FINAL_ARCHIVE}"
    echo "  3️⃣  Verify checksum:"
    echo "     sha256sum -c ${FINAL_ARCHIVE}.sha256"
    echo "  4️⃣  For restore, extract and read:"
    echo "     tar -xzf ${FINAL_ARCHIVE}"
    echo "     cat ${BACKUP_NAME}/metadata/RESTORE-GUIDE.md"
    echo ""
    
    log_warn "⚠️  SECURITY WARNING ⚠️"
    log_warn "This backup contains sensitive data:"
    log_warn "  • Jenkins secrets and credentials"
    [ "$SKIP_CERTS" = false ] && log_warn "  • SSL private keys"
    log_warn "  • System configuration"
    log_warn ""
    log_warn "ENCRYPT IMMEDIATELY before storage or transmission!"
    echo ""
}

# Main execution
main() {
    echo ""
    echo "╔════════════════════════════════════════════════════════════╗"
    echo "║      Jenkins Complete Backup Script                        ║"
    echo "║      Creating unified backup for transfer                  ║"
    echo "╚════════════════════════════════════════════════════════════╝"
    echo ""
    
    check_prerequisites
    create_backup_structure
    backup_jenkins_config
    backup_infrastructure
    create_metadata
    create_final_archive
    display_summary
    
    log_info "✨ Backup process completed successfully!"
    echo ""
}

# Trap errors
trap 'log_error "Backup failed at line $LINENO. Exit code: $?"' ERR

# Run main function
main "$@"

# Made with Bob