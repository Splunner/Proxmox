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

(Location upgrade/upgrade8to9 directory) 

```
chmod +x check_pve8to9_upgrade.sh
chmod +x pve8to9_upgrade.sh
tmux new -s upgrade
./check_pve8to9_upgrade.sh
```

Save the generated log file, apply all settings, and back up the configuration files.

Run the check script multiple times if necessary to identify and resolve any errors before running the upgrade script.

When you run the upgrade scripts, you will be prompted to specify the locations of the new configuration files and choose the new configuration approach.

Be careful when selecting the appropriate options. Always keep the default settings to preserve the existing configuration for LVM, networking, and boot. Otherwise, your current working configuration may be overwritten.


### Secuirty Patches 

Intel microcode which support additional secuirty patches for intel CPU base. Old + new.

(Location security_patches directory) 

```
chmod +x intel_microcode.sh
./intel_microcode.sh
reboot
```