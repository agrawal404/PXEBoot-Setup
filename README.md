# PXE-Boot Server on Ubuntu 24.04 LTS  
This is a Repo for steps on installing PXE Boot server on a linux based machine

---

## 0  What This Repo Contains
| File / Dir               | Purpose |
|--------------------------|---------|
| **setup-pxe.sh**         | One-shot interactive installer (run as `sudo bash setup-pxe.sh`) |
| **README.md**            | This guide |
| **/var/lib/tftpboot/**   | TFTP root (pxelinux.0, ipxe.efi, menu files) |
| **/var/www/html/**       | HTTP root for kernels, initrds, ISOs, cloud-init seeds |

---

## 1  Quick Install (the 60-second path)
```bash
curl -LO https://<your_repo>/setup-pxe.sh
chmod +x setup-pxe.sh
sudo ./setup-pxe.sh               # answer the 5 prompts → done
```
The script installs **dnsmasq (DHCP), tftpd-hpa (TFTP)** and **Apache (HTTP)**, drops the boot loaders in place and writes a starter PXELINUX menu.

---

## 2  Manual Step-by-Step (what the script does)
> Use this if you’re curious or need to tweak things by hand.

1. **Update & install packages**  
   ```bash
   sudo apt update
   sudo apt install -y dnsmasq tftpd-hpa apache2 pxelinux syslinux-common ipxe
   ```

2. **Populate TFTP root**  
   ```bash
   sudo mkdir -p /var/lib/tftpboot
   sudo cp /usr/lib/PXELINUX/pxelinux.0               /var/lib/tftpboot/
   sudo cp /usr/lib/syslinux/modules/bios/ldlinux.c32 /var/lib/tftpboot/
   sudo cp /usr/lib/ipxe/ipxe.efi                     /var/lib/tftpboot/
   sudo chown -R tftp:tftp /var/lib/tftpboot && sudo chmod -R a+rX /var/lib/tftpboot
   ```

3. **Configure `tftpd-hpa`** – `/etc/default/tftpd-hpa`
   ```ini
   TFTP_DIRECTORY="/var/lib/tftpboot"
   TFTP_ADDRESS="0.0.0.0:69"
   TFTP_OPTIONS="--secure --create"
   ```

4. **Configure `dnsmasq`** – `/etc/dnsmasq.d/pxe.conf`
   ```ini
   port=0                     # DNS disabled (router keeps DNS)
   interface=eno0             # NIC with 192.168.0.77
   bind-interfaces
   dhcp-range=192.168.0.81,192.168.0.85,12h
   dhcp-option=3,192.168.0.1  # gateway
   dhcp-option=6,192.168.0.1  # DNS
   # BIOS
   dhcp-boot=pxelinux.0,pxeserver,192.168.0.77
   # UEFI x86-64
   dhcp-match=set:efi64,option:client-arch,7
   dhcp-boot=tag:efi64,ipxe.efi,pxeserver,192.168.0.77
   ```

5. **Starter PXELINUX menu** – `/var/lib/tftpboot/pxelinux.cfg/default`
   ```text
   DEFAULT menu.c32
   PROMPT 0
   TIMEOUT 50
   ONTIMEOUT local
   MENU TITLE Network Boot Menu

   LABEL local
     MENU LABEL Boot from local disk
     LOCALBOOT 0
   ```

6. **Enable & start services**
   ```bash
   sudo systemctl enable --now tftpd-hpa dnsmasq apache2
   ```

---

## 3  Adding More Operating Systems

### 3.1  Linux Net-install (Debian 12 example)
```bash
# 1) Copy kernel & initrd
sudo mkdir -p /var/www/html/debian/12/amd64
cd /var/www/html/debian/12/amd64
sudo wget -O linux \
     https://deb.debian.org/debian/dists/bookworm/main/installer-amd64/current/images/netboot/debian-installer/amd64/linux
sudo wget -O initrd \
     https://deb.debian.org/debian/dists/bookworm/main/installer-amd64/current/images/netboot/debian-installer/amd64/initrd.gz

# 2) Add a LABEL block
sudo nano /var/lib/tftpboot/pxelinux.cfg/default
# ────────────────────────────────────────────────────
LABEL debian-12
  MENU LABEL Debian 12 (netboot)
  KERNEL http://192.168.0.77/debian/12/amd64/linux
  INITRD http://192.168.0.77/debian/12/amd64/initrd
  APPEND ip=dhcp ---
# ────────────────────────────────────────────────────
# 3) Save – no service restart needed.
```

### 3.2  Windows Installer (Win PE, Windows 10/11)
```bash
sudo mkdir -p /var/www/html/win11/{boot,sources}
# copy BCD, boot.sdi, boot.wim from ISO into those dirs
sudo wget -O /var/www/html/win11/wimboot \
     https://github.com/ipxe/wimboot/releases/latest/download/wimboot

# Menu entry
LABEL win11
  MENU LABEL Windows 11 Installer
  KERNEL http://192.168.0.77/win11/wimboot
  INITRD boot/bcd           BCD
  INITRD boot/boot.sdi      boot.sdi
  INITRD sources/boot.wim   boot.wim
  APPEND quiet --
```

### 3.3  Single-file Tools (Clonezilla ISO via MEMDISK)
```text
LABEL clonezilla
  MENU LABEL Clonezilla Live
  KERNEL memdisk
  INITRD http://192.168.0.77/isos/clonezilla.iso
  APPEND iso
```

> **No service restarts** are required; PXELINUX reads the menu fresh each boot.

---

## 4  Health-Check Commands

| Purpose | Command |
|---------|---------|
| Verify TFTP | `tftp 192.168.0.77 -c get pxelinux.0` |
| Verify DHCP offer | `sudo nmap --script broadcast-dhcp-discover -e <NIC>` |
| Verify HTTP files | `curl -I http://192.168.0.77/ubuntu/24.04/amd64/linux` |

All three must succeed for a clean PXE boot.

---

## 5  Important – The **VLAN / DHCP** Caveat
This README assumes **your PXE server is the only DHCP responder** on the subnet.  
In real networks you should **either**:

1. **Move PXE traffic to a dedicated VLAN** (cleanest in production), *or*  
2. Convert dnsmasq to **proxy-DHCP** (`dhcp-range=::,proxy`) so it *only* hands out PXE options while your router keeps leasing IPs.

Until you implement one of those, machines might receive an IP from the router’s DHCP first and skip network boot. Consider this README **incomplete** until a separate VLAN or proxy-DHCP arrangement is in place.

---

## 6  Troubleshooting Cheat-Sheet

| Symptom | Fix |
|---------|-----|
| **TFTP open timeout** | File path typo or wrong perms → check `/var/lib/tftpboot` and ownership `tftp:tftp`. |
| **HTTP 404 on kernel** | URL in menu doesn’t match real path/filename. |
| **UEFI PCs ignore PXE** | Confirm `ipxe.efi` exists & `option:client-arch,7` stanza present. |
| **Clients skip PXE entirely** | Router’s DHCP wins → disable router DHCP, use proxy-DHCP, or isolate VLAN. |

---

## 7  Useful References
* Syslinux PXE wiki  
* iPXE `wimboot` documentation  
* Ubuntu “netboot” download pages  
* netboot.xyz if you want a huge pre-built menu fetched via iPXE

Happy net-booting!  
Feel free to open an issue / PR when you add new distros.
