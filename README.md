# Proxmox
Proxmox scritps, configs and informations.


Get info about proxmox node, kernel, pve version in json format. (Location check_scripts directory)

```
chmod +x pve-os-info.sh
./pve-os-info.sh
```

Setup repository for the open source version ! Do not use for Proxmox on Production\
Also it supports Proxmox 8 and 9. (Location repository_handle directory)
```
chmod +x pve-repository-handle.sh
./pve-repository-handle.sh

```

### Upgrades

Upgade from Proxmox 8.2 to 9.2  Scripts 

(Location upgrade directory) 

```
chmod +x pve8to9_upgrade.sh
tmux new -s upgrade
./pve8to9_upgrade.sh
```