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

# ---------- 0. Proxmox no-subscription repository (nodes without a subscription) ----------
# Without a subscription the enterprise repository answers 401 and 'apt-get update' fails.
if command -v pvesubscription >/dev/null \
   && ! pvesubscription get 2>/dev/null | grep -qi 'status: *active'; then
  step "No active subscription - switching Proxmox repositories to no-subscription"
  CODENAME=$VERSION_CODENAME
  KEYRING=/usr/share/keyrings/proxmox-archive-keyring.gpg

  # Remember the Ceph release (e.g. ceph-squid) if a Ceph repository is configured
  CEPH_REL=""
  for f in "$DIR"/ceph.list "$DIR"/ceph.sources; do
    [[ -f $f ]] || continue
    CEPH_REL=$(grep -oE 'ceph-[a-z]+' "$f" | head -n1 || true)
    [[ -n $CEPH_REL ]] && break
  done

  # Disable enterprise repositories (kept as *.disabled)
  for f in "$DIR"/pve-enterprise.list "$DIR"/pve-enterprise.sources; do
    if [[ -f $f ]]; then mv -f "$f" "$f.disabled"; echo "Disabled: $f"; fi
  done
  CEPH_SWITCHED=0
  for f in "$DIR"/ceph.list "$DIR"/ceph.sources; do
    if [[ -f $f ]] && grep -q 'enterprise' "$f"; then
      mv -f "$f" "$f.disabled"; echo "Disabled: $f"
      CEPH_SWITCHED=1
    fi
  done

  # Add pve-no-subscription unless it is already configured
  if ! grep -rqs 'pve-no-subscription' /etc/apt/sources.list "$DIR"/*.list "$DIR"/*.sources; then
    if [[ $CODENAME == trixie ]]; then
      cat > "$DIR/proxmox.sources" <<EOF
Types: deb
URIs: http://download.proxmox.com/debian/pve
Suites: trixie
Components: pve-no-subscription
Signed-By: $KEYRING
EOF
      echo "Added: $DIR/proxmox.sources"
    else
      echo "deb http://download.proxmox.com/debian/pve bookworm pve-no-subscription" \
        > "$DIR/pve-no-subscription.list"
      echo "Added: $DIR/pve-no-subscription.list"
    fi
  fi

  # Add the Ceph no-subscription repository if the enterprise one was just disabled
  if (( CEPH_SWITCHED )) && [[ -n $CEPH_REL ]]; then
    if [[ $CODENAME == trixie ]]; then
      cat > "$DIR/ceph-no-subscription.sources" <<EOF
Types: deb
URIs: http://download.proxmox.com/debian/$CEPH_REL
Suites: trixie
Components: no-subscription
Signed-By: $KEYRING
EOF
    else
      echo "deb http://download.proxmox.com/debian/$CEPH_REL bookworm no-subscription" \
        > "$DIR/ceph-no-subscription.list"
    fi
    echo "Added: Ceph no-subscription repository ($CEPH_REL)"
  fi
fi

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