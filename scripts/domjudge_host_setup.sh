#!/usr/bin/env bash
#
# DOMjudge Docker Pre-requisites Checker & Installer
# Works on Ubuntu/Debian systems
#
# Usage:
#   ./scripts/verifyPrerequisites.sh                 # run all checks only
#   ./scripts/verifyPrerequisites.sh run_all_checks --fix   # run all checks and auto-install missing
#   ./scripts/verifyPrerequisites.sh check_docker --fix      # run single check with fix

set -euo pipefail

########################
# Helper Functions
########################

info()  { echo -e "\e[34m[INFO]\e[0m $*"; }
ok()    { echo -e "\e[32m[OK]\e[0m   $*"; }
warn()  { echo -e "\e[33m[WARN]\e[0m $*"; }
fail()  { echo -e "\e[31m[FAIL]\e[0m $*"; }

check_cmd() {
    local cmd=$1
    if command -v "$cmd" &>/dev/null; then
        return 0
    else
        return 1
    fi
}

install_pkg() {
    local pkg=$1
    info "Installing package: $pkg"
    DEBIAN_FRONTEND=noninteractive sudo apt-get install -y "$pkg"
}

check_service() {
    local svc=$1
    if systemctl is-active --quiet "$svc"; then
        ok "Service '$svc' is running"
    else
        fail "Service '$svc' is NOT running"
        if $FIX; then
            info "Starting service '$svc'..."
            sudo systemctl enable --now "$svc" || warn "Could not start $svc"
        fi
    fi
}

check_version() {
    local cmd=$1
    local min_version=$2
    local cur_version
    cur_version=$($cmd --version 2>/dev/null | head -n1 | grep -oE "[0-9]+(\.[0-9]+)+" | head -n1 || true)

    if [ -z "$cur_version" ]; then
        fail "Could not detect version for $cmd"
        return 1
    fi

    dpkg --compare-versions "$cur_version" ge "$min_version"
    if [ $? -eq 0 ]; then
        ok "$cmd version $cur_version (>= $min_version)"
    else
        fail "$cmd version $cur_version (< $min_version)"
        return 1
    fi
}

check_port() {
    local port=$1
    if ss -tuln | grep -q ":$port "; then
        ok "Port $port is open/listening"
    else
        warn "Port $port not listening (may be expected if not started yet)"
    fi
}

check_resources() {
    local min_cpu=$1
    local min_mem=$2
    local cpu mem
    cpu=$(nproc)
    mem=$(grep MemTotal /proc/meminfo | awk '{print int($2/1024)}')

    if [ "$cpu" -ge "$min_cpu" ]; then
        ok "CPU cores: $cpu (>= $min_cpu)"
    else
        fail "CPU cores: $cpu (< $min_cpu)"
    fi

    if [ "$mem" -ge "$min_mem" ]; then
        ok "Memory: ${mem}MB (>= $min_mem MB)"
    else
        fail "Memory: ${mem}MB (< $min_mem MB)"
    fi
}

########################
# Business Logic
########################

check_os() {
    info "=== Checking Host OS ==="
    if [ -f /etc/debian_version ]; then
        ok "Debian/Ubuntu detected"
    else
        warn "Non-Debian OS detected – script may not fully work"
    fi
    uname -a
}

check_privileges() {
    info "=== Checking Required Privileges ==="
    if [ "$EUID" -eq 0 ]; then
        ok "Running as root"
    elif groups | grep -qw docker; then
        ok "User is in docker group"
    else
        warn "Not root and not in docker group – may need sudo for Docker"
        if $FIX; then
            info "Adding $USER to docker group..."
            sudo usermod -aG docker "$USER"
            ok "$USER added to docker group. Please log out and log back in for this to take effect."
        fi
    fi
}

check_docker() {
    info "=== Checking Docker & Compose ==="

    if ! check_cmd docker; then
        fail "Docker not installed"
        if $FIX; then
            info "Installing Docker..."
            curl -fsSL https://get.docker.com | sh
            sudo systemctl enable --now docker
        fi
    else
        check_version docker "20.10" || {
            if $FIX; then
                info "Reinstalling/Updating Docker..."
                curl -fsSL https://get.docker.com | sh
            fi
        }
    fi

    if docker compose version &>/dev/null; then
        ok "Docker CLI compose plugin available"
    elif check_cmd docker-compose; then
        check_version docker-compose "1.29"
    else
        fail "Docker Compose missing"
        if $FIX; then
            info "Installing docker-compose..."
            sudo apt-get update -y && sudo apt-get install -y docker-compose
        fi
    fi
}

check_cli_tools() {
    info "=== Checking Required CLI tools ==="
    for c in curl git tar unzip lsb_release gpg apt-get; do
        if ! check_cmd "$c"; then
            fail "Missing: $c"
            if $FIX; then
                install_pkg "$c"
            fi
        else
            ok "$c is installed"
        fi
    done
}

check_storage_resources() {
    info "=== Checking Storage & Resources ==="
    check_resources 2 4000   # 2 cores, 4GB RAM
    df -h /
}

check_network_ports() {
    info "=== Checking Network & Ports ==="
    for p in 80 443 3306; do
        check_port "$p"
    done
}

check_database_backups() {
    info "=== Checking Database Backup Strategy (manual) ==="
    warn "Ensure MariaDB/MySQL has volume mounts and backups configured"
}

check_tls_proxy() {
    info "=== Checking TLS / Reverse Proxy ==="
    warn "TLS certs not auto-validated here – ensure traefik/nginx or certbot in place"
}

check_timing() {
    info "=== Checking System Services & Timing ==="
    check_service systemd-timesyncd || check_service ntp || warn "No time sync service detected"
}

check_kernel_cgroups() {
    info "=== Checking Kernel & cgroups ==="
    if [ -f /sys/fs/cgroup/cgroup.controllers ]; then
        ok "cgroups v2 detected"
    else
        ok "cgroups v1 detected"
    fi

    if ! grep -q memory /proc/cgroups; then
        fail "Memory cgroup not enabled"
        echo "👉 Run: sudo ./scripts/fix_cgroup.sh --reboot"
    fi
}

check_security() {
    info "=== Checking Security ==="
    if command -v aa-status &>/dev/null; then
        aa-status --enabled && ok "AppArmor enabled"
    fi
    if command -v getenforce &>/dev/null; then
        getenforce
    fi
}

check_operational() {
    info "=== Operational considerations ==="
    warn "Check docker logs / restart policies manually"
}

########################
# Orchestration
########################

run_all_checks() {
    check_os
    check_privileges
    check_docker
    check_cli_tools
    check_storage_resources
    check_network_ports
    check_database_backups
    check_tls_proxy
    check_timing
    check_kernel_cgroups
    check_security
    check_operational

    info "=== Pre-check completed ==="
}

########################
# Entry Point
########################

FIX=false

main() {
    local fn="${1:-run_all_checks}"
    if [[ "${2:-}" == "--fix" ]]; then
        FIX=true
    fi

    if declare -f "$fn" >/dev/null 2>&1; then
        $fn
    else
        echo "Usage: $0 [function_name] [--fix]"
        echo "Available functions:"
        declare -F | awk '{print " - " $3}' | grep -E '^ - check_|run_all_checks'
        exit 1
    fi
}

main "$@"
