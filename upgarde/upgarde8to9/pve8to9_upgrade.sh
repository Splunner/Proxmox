#!/usr/bin/env bash
# Switches APT repositories from PVE 8 (bookworm) to PVE 9 (trixie),
# no-subscription, and upgrades the node. Follows the official
# "Upgrade from 8 to 9" guide. Run as root, one node at a time,
# inside tmux/screen or on the physical console.
set -euo pipefail

DIR=/etc/apt/sources.list.d
KEYRING=/usr/share/keyrings/proxmox-archive-keyring.gpg

die()  { echo "ERROR: $*" >&2; exit 1; }
step() { echo; echo "==> $*"; }

[[ $EUID -eq 0 ]] || die "Run this script as root."
command -v pveversion >/dev/null || die "This is not a Proxmox VE node."
. /etc/os-release
[[ ${VERSION_CODENAME:-} == bookworm ]] \
  || die "Expected Debian bookworm (PVE 8), found '${VERSION_CODENAME:-unknown}'."

# ---------- 1. Latest PVE 8.4 packages ----------
step "Updating to the latest Proxmox VE 8.4 packages"
apt-get update
apt-get -y dist-upgrade

PVE_VER=$(dpkg-query -W -f='${Version}' pve-manager)
dpkg --compare-versions "$PVE_VER" ge 8.4.1 \
  || die "pve-manager is $PVE_VER, need at least 8.4.1."
echo "pve-manager $PVE_VER - OK"

# ---------- 2. Ceph must be Squid (19) before going on ----------
CEPH_USED=0
if command -v ceph >/dev/null && [[ -f /etc/pve/ceph.conf ]]; then
  CEPH_USED=1
  CEPH_MAJOR=$(ceph --version | awk '{print $3}' | cut -d. -f1)
  [[ $CEPH_MAJOR -ge 19 ]] || die "Ceph $CEPH_MAJOR found. Upgrade Ceph to Squid (19.2) first."
fi

read -r -p "Switch repositories to trixie and upgrade to Proxmox VE 9 now? [y/N] " a
[[ $a == [yY] ]] || die "Aborted by user."

# ---------- 3. Switch repositories ----------
step "Backing up /etc/apt"
BACKUP=/root/apt-backup-pve8-$(date +%Y%m%d-%H%M%S).tar.gz
tar -czf "$BACKUP" -C /etc apt
echo "Backup: $BACKUP"

step "Switching repositories to trixie (no-subscription)"

# Old enterprise and PVE 8 no-subscription repositories
for f in "$DIR"/pve-enterprise.list "$DIR"/pve-enterprise.sources \
         "$DIR"/ceph.list "$DIR"/ceph.sources; do
  if [[ -f $f ]]; then mv -f "$f" "$f.disabled"; fi
done
rm -f "$DIR"/pve-no-subscription.list "$DIR"/pve-install-repo.list \
      "$DIR"/ceph-no-subscription.list
sed -i '/download\.proxmox\.com/d; /enterprise\.proxmox\.com/d' /etc/apt/sources.list

# Backports are not supported during the upgrade
sed -i '/backports/ s/^[^#]/#&/' /etc/apt/sources.list

# Debian base (and remaining third-party) repositories: bookworm -> trixie
sed -i 's/bookworm/trixie/g' /etc/apt/sources.list
shopt -s nullglob
for f in "$DIR"/*.list "$DIR"/*.sources; do
  sed -i 's/bookworm/trixie/g' "$f"
done
shopt -u nullglob

# Proxmox VE 9 no-subscription repository
cat > "$DIR/proxmox.sources" <<EOF
Types: deb
URIs: http://download.proxmox.com/debian/pve
Suites: trixie
Components: pve-no-subscription
Signed-By: $KEYRING
EOF

# Ceph Squid no-subscription repository (hyper-converged setups only)
if (( CEPH_USED )); then
  cat > "$DIR/ceph.sources" <<EOF
Types: deb
URIs: http://download.proxmox.com/debian/ceph-squid
Suites: trixie
Components: no-subscription
Signed-By: $KEYRING
EOF
fi

# ---------- 4. Upgrade ----------
step "Refreshing package index"
apt-get update

if grep -rqs 'bookworm' /etc/apt/sources.list "$DIR"/*.list "$DIR"/*.sources 2>/dev/null; then
  die "Some repositories still point to bookworm. Fix them and run: apt update && apt dist-upgrade"
fi

step "Upgrading to Debian trixie / Proxmox VE 9"
cat <<'EOF'
Config file prompts - recommended answers from the Proxmox guide:
  /etc/issue                -> N (keep current)
  /etc/lvm/lvm.conf         -> Y (maintainer's version), unless you changed it
  /etc/ssh/sshd_config      -> Y, unless you changed it
  /etc/default/grub         -> N (keep current)
  /etc/chrony/chrony.conf   -> Y, unless you changed it
  apt-listchanges screen    -> press q
EOF
apt-get dist-upgrade

# ---------- 5. Done ----------
step "Upgrade finished"
pveversion || true
echo
echo "Now run 'pve8to9 --full' once more, then reboot the node:  reboot"
echo "APT backup of the old configuration: $BACKUP"