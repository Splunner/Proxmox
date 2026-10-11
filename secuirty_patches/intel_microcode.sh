#!/usr/bin/env bash
# Installs Intel CPU microcode updates on a Proxmox VE node.
# Works on PVE 8 (Debian 12 bookworm) and PVE 9 (Debian 13 trixie).
# Enables the Debian "non-free-firmware" component and installs intel-microcode.
# Run as root. A reboot is needed to load the new microcode.
set -euo pipefail

DIR=/etc/apt/sources.list.d
STAMP=$(date +%Y%m%d-%H%M%S)

die()  { echo "ERROR: $*" >&2; exit 1; }
step() { echo; echo "==> $*"; }

[[ $EUID -eq 0 ]] || die "Run this script as root."

. /etc/os-release
case "${VERSION_CODENAME:-}" in
  bookworm|trixie) ;;
  *) die "Unsupported Debian release: '${VERSION_CODENAME:-unknown}' (need bookworm or trixie)." ;;
esac

grep -q 'GenuineIntel' /proc/cpuinfo \
  || die "This is not an Intel CPU. For AMD install the 'amd64-microcode' package instead."

echo "System:            $PRETTY_NAME"
echo "CPU:               $(grep -m1 'model name' /proc/cpuinfo | cut -d: -f2- | sed 's/^ //')"
echo "Current microcode: $(grep -m1 'microcode' /proc/cpuinfo | awk '{print $3}')"

# ---------- 1. Enable non-free-firmware on the Debian repositories ----------
step "Enabling the 'non-free-firmware' component"

# Classic one-line format (PVE 8, and PVE 9 nodes upgraded from 8)
if [[ -f /etc/apt/sources.list ]] && grep -qE '^deb .*debian\.org' /etc/apt/sources.list; then
  cp /etc/apt/sources.list "/etc/apt/sources.list.bak-$STAMP"
  sed -i -E '/^deb .*debian\.org/ { /non-free-firmware/! s/[[:space:]]*$/ non-free-firmware/ }' \
    /etc/apt/sources.list
  echo "Checked: /etc/apt/sources.list"
fi

# deb822 format (fresh PVE 9 installations)
if [[ -f $DIR/debian.sources ]]; then
  cp "$DIR/debian.sources" "/root/debian.sources.bak-$STAMP"
  sed -i -E '/^Components:/ { /non-free-firmware/! s/[[:space:]]*$/ non-free-firmware/ }' \
    "$DIR/debian.sources"
  echo "Checked: $DIR/debian.sources"
fi

# ---------- 2. Install the package ----------
step "Installing intel-microcode"
apt-get update
apt-get install -y intel-microcode

# ---------- 3. Done ----------
step "Finished"
echo "Reboot the node to load the new microcode:  reboot"
echo "After the reboot, verify with:"
echo "  journalctl -k | grep -i microcode"
echo "  grep -m1 microcode /proc/cpuinfo"