#!/usr/bin/env bash
#
# setup-pxe.sh – Interactive PXE-boot server installer for Ubuntu
# tested on 22.04 / 23.10 / 24.04
#

set -euo pipefail

echo "PXE server quick-installer (Ubuntu)"
echo "--------------------------------------"
[[ $EUID -eq 0 ]] || { echo "Please run as root (sudo bash $0)"; exit 1; }

read -rp "Ethernet interface to bind (e.g. eno0): " IFACE
read -rp "This server's IP address       (e.g. 192.168.0.77): " SRV_IP
read -rp "DHCP range start               (e.g. 192.168.0.81): " DHCP_START
read -rp "DHCP range end                 (e.g. 192.168.0.100): " DHCP_END
read -rp "Gateway IP (router)            (e.g. 192.168.0.1): " GATEWAY
read -rp "DNS server IP  [${GATEWAY}]: " DNS_IP
DNS_IP=${DNS_IP:-$GATEWAY}

echo "  Updating apt & installing packages..."
apt-get update -qq
DEBIAN_FRONTEND=noninteractive apt-get install -y \
  dnsmasq tftpd-hpa apache2 pxelinux syslinux-common ipxe

echo "Creating TFTP root & copying boot loaders..."
mkdir -p /var/lib/tftpboot
cp /usr/lib/PXELINUX/pxelinux.0               /var/lib/tftpboot/
cp /usr/lib/syslinux/modules/bios/ldlinux.c32 /var/lib/tftpboot/
cp /usr/lib/ipxe/ipxe.efi                     /var/lib/tftpboot/
chown -R tftp:tftp /var/lib/tftpboot
chmod -R a+rX     /var/lib/tftpboot

echo "Configuring tftpd-hpa..."
cat >/etc/default/tftpd-hpa <<EOF
TFTP_USERNAME="tftp"
TFTP_DIRECTORY="/var/lib/tftpboot"
TFTP_ADDRESS="0.0.0.0:69"
TFTP_OPTIONS="--secure --create"
EOF
systemctl enable --now tftpd-hpa

echo "Writing dnsmasq PXE config..."
cat >/etc/dnsmasq.d/pxe.conf <<EOF
# ===== dnsmasq PXE configuration =====
port=0                         # disable DNS function; use router DNS
interface=${IFACE}
bind-interfaces

dhcp-range=${DHCP_START},${DHCP_END},12h
dhcp-option=3,${GATEWAY}
dhcp-option=6,${DNS_IP}

# ---- Boot files ----
# Legacy BIOS
dhcp-boot=pxelinux.0,pxeserver,${SRV_IP}

# UEFI x86-64
dhcp-match=set:efi64,option:client-arch,7
dhcp-boot=tag:efi64,ipxe.efi,pxeserver,${SRV_IP}
EOF

echo "Restarting dnsmasq..."
dnsmasq --test || { echo "dnsmasq config check failed"; exit 1; }
systemctl restart dnsmasq
systemctl enable  dnsmasq

echo "📝  Creating starter PXELINUX menu..."
mkdir -p /var/lib/tftpboot/pxelinux.cfg
cat >/var/lib/tftpboot/pxelinux.cfg/default <<'EOF'
DEFAULT menu.c32
PROMPT 0
TIMEOUT 50
ONTIMEOUT local
MENU TITLE Network Boot Menu

LABEL local
  MENU LABEL Boot from local disk
  LOCALBOOT 0

# --- Add your OS entries below ---
# Example Ubuntu entry (needs kernel+initrd over HTTP):
# LABEL ubuntu-24.04
#   MENU LABEL Ubuntu 24.04 (netboot)
#   KERNEL http://<SERVER_IP>/ubuntu/24.04/amd64/linux
#   INITRD http://<SERVER_IP>/ubuntu/24.04/amd64/initrd
#   APPEND ip=dhcp ---
EOF

echo "Ensuring Apache is running..."
systemctl enable --now apache2

echo "PXE setup complete!"
echo
echo "➡  Next steps:"
echo "   1) Copy each distro's kernel & initrd under /var/www/html/…"
echo "   2) Add a LABEL block to /var/lib/tftpboot/pxelinux.cfg/default"
echo "   3) Boot a client set to 'Network / PXE' and enjoy."
echo
echo "Use 'sudo systemctl status dnsmasq tftpd-hpa apache2' to check services."
