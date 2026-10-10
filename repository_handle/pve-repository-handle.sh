#!/usr/bin/env bash
# Switches Proxmox VE repositories from enterprise to pve-no-subscription.
# Works on PVE 8 (bookworm) and PVE 9 (trixie). Run as root on every node.
set -euo pipefail

[[ $EUID -eq 0 ]] || { echo "Run this script as root." >&2; exit 1; }
command -v pveversion >/dev/null || { echo "This is not a Proxmox VE node." >&2; exit 1; }

. /etc/os-release
CODENAME="${VERSION_CODENAME:-}"
DIR=/etc/apt/sources.list.d
KEYRING=/usr/share/keyrings/proxmox-archive-keyring.gpg

case "$CODENAME" in
  bookworm|trixie) ;;
  *) echo "Unsupported Debian release: '$CODENAME'." >&2; exit 1 ;;
esac

echo "Detected: $(pveversion | cut -d/ -f1-2), Debian $CODENAME"

# 1. Check whether Ceph is in use and which release (e.g. ceph-squid)
CEPH_REL=""
for f in "$DIR"/ceph.list "$DIR"/ceph.sources; do
  [[ -f $f ]] || continue
  CEPH_REL=$(grep -oE 'ceph-[a-z]+' "$f" | head -n1 || true)
  [[ -n $CEPH_REL ]] && break
done

# 2. Disable the enterprise repositories (files are kept as *.disabled)
for f in "$DIR"/pve-enterprise.list "$DIR"/pve-enterprise.sources \
         "$DIR"/ceph.list "$DIR"/ceph.sources; do
  if [[ -f $f ]]; then
    mv -f "$f" "$f.disabled"
    echo "Disabled: $f -> $f.disabled"
  fi
done

# 3. Remove any old Proxmox entries from the main sources.list
if [[ -f /etc/apt/sources.list ]]; then
  sed -i.bak '/download\.proxmox\.com/d; /enterprise\.proxmox\.com/d' /etc/apt/sources.list
fi
rm -f "$DIR"/pve-no-subscription.list "$DIR"/proxmox.sources \
      "$DIR"/ceph-no-subscription.list "$DIR"/ceph-no-subscription.sources

# 4. Add the no-subscription repositories
if [[ $CODENAME == trixie ]]; then
  # PVE 9: deb822 format
  cat > "$DIR/proxmox.sources" <<EOF
Types: deb
URIs: http://download.proxmox.com/debian/pve
Suites: trixie
Components: pve-no-subscription
Signed-By: $KEYRING
EOF
  echo "Added: $DIR/proxmox.sources"

  if [[ -n $CEPH_REL ]]; then
    cat > "$DIR/ceph-no-subscription.sources" <<EOF
Types: deb
URIs: http://download.proxmox.com/debian/$CEPH_REL
Suites: trixie
Components: no-subscription
Signed-By: $KEYRING
EOF
    echo "Added: $DIR/ceph-no-subscription.sources ($CEPH_REL)"
  fi
else
  # PVE 8: classic .list format
  echo "deb http://download.proxmox.com/debian/pve bookworm pve-no-subscription" \
    > "$DIR/pve-no-subscription.list"
  echo "Added: $DIR/pve-no-subscription.list"

  if [[ -n $CEPH_REL ]]; then
    echo "deb http://download.proxmox.com/debian/$CEPH_REL bookworm no-subscription" \
      > "$DIR/ceph-no-subscription.list"
    echo "Added: $DIR/ceph-no-subscription.list ($CEPH_REL)"
  fi
fi

# 5. Refresh the package lists
apt-get update

echo
echo "Done. Install updates with: apt dist-upgrade (not 'apt upgrade')."