#!/usr/bin/env bash
# In-place upgrade of a Proxmox VE node from 8.4 to the latest 9.x
# using the pve-no-subscription repository.
#
# Run as root, on ONE node at a time, from SSH inside tmux/screen or from
# the physical console (not from the web UI shell).
# Migrate or shut down guests and make sure you have backups first.
set -euo pipefail

DIR=/etc/apt/sources.list.d
KEYRING=/usr/share/keyrings/proxmox-archive-keyring.gpg

die()     { echo "ERROR: $*" >&2; exit 1; }
step()    { echo; echo "==> $*"; }
confirm() { read -r -p "$1 [y/N] " a; [[ $a == [yY] ]] || die "Aborted by user."; }

# ---------- 0. Sanity checks ----------
[[ $EUID -eq 0 ]] || die "Run this script as root."
command -v pveversion >/dev/null || die "This is not a Proxmox VE node."

. /etc/os-release
[[ ${VERSION_CODENAME:-} == bookworm ]] \
  || die "Expected Debian bookworm (PVE 8), found '${VERSION_CODENAME:-unknown}'."

if [[ -z ${TMUX:-} && -z ${STY:-} ]]; then
  echo "WARNING: not running inside tmux/screen. If the SSH session drops,"
  echo "         the upgrade can be left half-finished."
  confirm "Continue anyway?"
fi

RUNNING_VMS=$(qm list 2>/dev/null | grep -c ' running ' || true)
RUNNING_CTS=$(pct list 2>/dev/null | grep -c ' running ' || true)
if (( RUNNING_VMS + RUNNING_CTS > 0 )); then
  echo "WARNING: $RUNNING_VMS VM(s) and $RUNNING_CTS container(s) are still running on this node."
  echo "         They will go down at the reboot. Migrate or stop them first if needed."
  confirm "Continue anyway?"
fi

# ---------- 1. Bring PVE 8 fully up to date ----------
step "Updating Proxmox VE 8 to the latest 8.4 packages"
apt-get update
apt-get -y dist-upgrade

PVE_VER=$(dpkg-query -W -f='${Version}' pve-manager)
dpkg --compare-versions "$PVE_VER" ge 8.4.1 \
  || die "pve-manager is $PVE_VER, need at least 8.4.1. Check your PVE 8 repositories."
echo "pve-manager $PVE_VER - OK"

# ---------- 2. Ceph must already be on Squid (19.x) ----------
CEPH_USED=0
if command -v ceph >/dev/null && [[ -f /etc/pve/ceph.conf ]]; then
  CEPH_USED=1
  CEPH_MAJOR=$(ceph --version | awk '{print $3}' | cut -d. -f1)
  [[ $CEPH_MAJOR -ge 19 ]] \
    || die "Ceph $CEPH_MAJOR detected. Upgrade Ceph to Squid (19.2) on PVE 8 before upgrading to PVE 9."
  echo "Ceph $CEPH_MAJOR - OK"
fi

# ---------- 3. Official pre-upgrade checklist ----------
step "Running pve8to9 --full"
CHECK_LOG=/root/pve8to9-$(date +%Y%m%d-%H%M%S).log
pve8to9 --full | tee "$CHECK_LOG" || true
echo "Checklist saved to $CHECK_LOG"

FAILS=$(grep -E '^FAILURES:' "$CHECK_LOG" | awk '{print $2}' | tail -n1)
FAILS=${FAILS:-0}
(( FAILS == 0 )) || die "pve8to9 reported $FAILS failure(s). Fix them and run the script again."

echo
echo "Review the warnings above before going further."
confirm "Switch repositories to Debian trixie / PVE 9 and start the upgrade?"

# ---------- 4. Back up and switch APT repositories ----------
step "Backing up /etc/apt"
BACKUP=/root/apt-backup-pve8-$(date +%Y%m%d-%H%M%S).tar.gz
tar -czf "$BACKUP" -C /etc apt
echo "Backup: $BACKUP"

step "Switching repositories to trixie (no-subscription)"

# Disable enterprise repositories
for f in "$DIR"/pve-enterprise.list "$DIR"/pve-enterprise.sources \
         "$DIR"/ceph.list "$DIR"/ceph.sources; do
  if [[ -f $f ]]; then mv -f "$f" "$f.disabled"; fi
done

# Remove old PVE 8 no-subscription entries
rm -f "$DIR"/pve-no-subscription.list "$DIR"/pve-install-repo.list \
      "$DIR"/ceph-no-subscription.list
sed -i '/download\.proxmox\.com/d; /enterprise\.proxmox\.com/d' /etc/apt/sources.list

# Debian (and any remaining third-party) repositories: bookworm -> trixie
sed -i 's/bookworm/trixie/g' /etc/apt/sources.list
shopt -s nullglob
for f in "$DIR"/*.list "$DIR"/*.sources; do
  sed -i 's/bookworm/trixie/g' "$f"
done
shopt -u nullglob

# PVE 9 no-subscription repository (deb822 format)
cat > "$DIR/proxmox.sources" <<EOF
Types: deb
URIs: http://download.proxmox.com/debian/pve
Suites: trixie
Components: pve-no-subscription
Signed-By: $KEYRING
EOF

# Ceph Squid no-subscription repository, only if Ceph is used
if (( CEPH_USED )); then
  cat > "$DIR/ceph.sources" <<EOF
Types: deb
URIs: http://download.proxmox.com/debian/ceph-squid
Suites: trixie
Components: no-subscription
Signed-By: $KEYRING
EOF
fi

# ---------- 5. The upgrade itself ----------
step "Refreshing package lists"
apt-get update

step "Upgrading to Proxmox VE 9 (this takes a while and may ask questions)"
echo "Tip: for changed config files, keeping the currently installed version (N)"
echo "     is the safe default, except where the Proxmox upgrade guide says otherwise."
apt-get dist-upgrade

# ---------- 6. Finish ----------
step "Upgrade finished"
pveversion || true
echo
echo "Next steps:"
echo "  1. Run 'pve8to9 --full' once more and check the result."
echo "  2. Reboot the node to boot the new kernel:  reboot"
echo "  3. After reboot, verify with 'pveversion -v' and clear the browser cache (Ctrl+Shift+R)."
echo "APT backup of the old configuration: $BACKUP"