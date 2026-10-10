#!/usr/bin/env bash
# Prints operating system information of a Proxmox VE node as JSON.
# No extra packages needed (does not require jq).
set -euo pipefail

command -v pveversion >/dev/null || { echo "This is not a Proxmox VE node." >&2; exit 1; }

# Escape backslashes and double quotes so values are valid JSON strings
esc() { printf '%s' "$1" | sed 's/\\/\\\\/g; s/"/\\"/g'; }

. /etc/os-release

PVE_RAW=$(pveversion)                               # pve-manager/8.3.0/abc123 (running kernel: ...)
PVE_VERSION=$(echo "$PVE_RAW" | cut -d/ -f2)
PVE_REPOID=$(echo "$PVE_RAW" | cut -d/ -f3 | awk '{print $1}')

cat <<EOF
{
  "hostname": "$(esc "$(hostname -f 2>/dev/null || hostname)")",
  "os": {
    "id": "$(esc "${ID:-}")",
    "name": "$(esc "${NAME:-}")",
    "pretty_name": "$(esc "${PRETTY_NAME:-}")",
    "version_id": "$(esc "${VERSION_ID:-}")",
    "codename": "$(esc "${VERSION_CODENAME:-}")",
    "debian_version": "$(esc "$(cat /etc/debian_version 2>/dev/null || true)")"
  },
  "kernel": {
    "release": "$(esc "$(uname -r)")",
    "version": "$(esc "$(uname -v)")",
    "arch": "$(esc "$(uname -m)")"
  },
  "proxmox": {
    "pve_manager": "$(esc "$PVE_VERSION")",
    "repoid": "$(esc "$PVE_REPOID")"
  },
  "uptime_seconds": $(cut -d. -f1 /proc/uptime)
}
EOF