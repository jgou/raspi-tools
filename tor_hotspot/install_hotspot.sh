#!/bin/bash
# Based on Adafruit Learning Technologies Onion Pi project
# But mainly fixed by Raspberry Pi FR...

if (( $EUID != 0 )); then 
   echo "This must be run as root. Try 'sudo bash $0'." 
   exit 1 
fi


echo "
$(tput setaf 2)              .~~.   .~~.
$(tput setaf 6)   /         $(tput setaf 2)'. \ ' ' / .'$(tput setaf 6)         \ 
$(tput setaf 6)  |   /       $(tput setaf 1).~ .~~~..~.$(tput setaf 6)       \   |
$(tput setaf 6) |   |   /  $(tput setaf 1) : .~.'~'.~. :$(tput setaf 6)   \   |   |
$(tput setaf 6)|   |   |   $(tput setaf 1)~ (   ) (   ) ~$(tput setaf 6)   |   |   |
$(tput setaf 6)|   |  |   $(tput setaf 1)( : '~'.~.'~' : )$(tput setaf 6)   |  |   |
$(tput setaf 6)|   |   |   $(tput setaf 1)~ .~ (   ) ~. ~ $(tput setaf 6)  |   |   |
$(tput setaf 6) |   |   \   $(tput setaf 1)(  : '~' :  )$(tput setaf 6)   /   |   |
$(tput setaf 6)  |   \       $(tput setaf 1)'~ .~~~. ~'$(tput setaf 6)       /   |
$(tput setaf 6)   \              $(tput setaf 1)'~'$(tput setaf 6)              / 

"

echo "$(tput setaf 6)This script will configure your Raspberry Pi as a wireless access point.$(tput sgr0)"
read -p "$(tput bold ; tput setaf 2)Press [Enter] to begin, [Ctrl-C] to abort...$(tput sgr0)"

echo "$(tput setaf 6)Updating packages...$(tput sgr0)"
apt-get update -y

echo "Installing dnsmasq"
apt install dnsmasq -y
systemctl stop dnsmasq

echo "Configuring Wlan0 static IP for 192.168.42.1/24"
echo "interface wlan0
    static ip_address=192.168.4.1/24
    nohook wpa_supplicant" >> /etc/dhcpcd.conf

echo "Restarting dhcpcd..."
service dhcpcd restart

echo "Configuring dnsmasq..."
mv /etc/dnsmasq.conf /etc/dnsmasq.conf.orig
echo "interface=wlan0      # Use the require wireless interface - usually wlan0
dhcp-range=192.168.4.2,192.168.4.20,255.255.255.0,24h" > /etc/dnsmasq.conf

echo "Enabling dnsmasq and restart..."
systemctl unmask dnsmasq
systemctl enable dnsmasq

systemctl restart dnsmasq


echo "Unlock wlan soft lock with rfkill..."
if ! command -v rfkill &> /dev/null; then
    rfkill unblock wlan
fi

echo "Install and enable hostapd..."
apt-get install hostapd -y
systemctl unmask hostapd
systemctl enable hostapd

echo "Configuring Hostapd !"
echo "Choose the hostname for your new network (1-32 char, try to privilege ASCII chars) :"
read ssid

echo "Choose the password for your new network (minimum 8 char):"
read passphrase

echo "interface=wlan0
driver=nl80211
ssid=$ssid
hw_mode=g
channel=7
wmm_enabled=0
macaddr_acl=0
auth_algs=1
ignore_broadcast_ssid=0
wpa=2
wpa_passphrase=$passphrase
wpa_key_mgmt=WPA-PSK
wpa_pairwise=TKIP
rsn_pairwise=CCMP
" > /etc/hostapd/hostapd.conf

echo 'DAEMON_CONF="/etc/hostapd/hostapd.conf"' >> /etc/default/hostapd

echo "Starting hostapd..."
systemctl start hostapd


echo "$(tput setaf 6)Setting IP forwarding to start at system boot...$(tput sgr0)"
cp /etc/sysctl.conf /etc/sysctl.bak
echo "net.ipv4.ip_forward=1" >> /etc/sysctl.conf

echo "up iptables-restore < /etc/iptables.ipv4.nat" >> /etc/network/interfaces

echo "$(tput setaf 6)Activating IP forwarding...$(tput sgr0)"
sh -c "echo 1 > /proc/sys/net/ipv4/ip_forward"

echo "$(tput setaf 6)Setting up IP tables to interconnect ports...$(tput sgr0)"
iptables -t nat -A POSTROUTING -o eth0 -j MASQUERADE
iptables -A FORWARD -i eth0 -o wlan0 -m state --state RELATED,ESTABLISHED -j ACCEPT
iptables -A FORWARD -i wlan0 -o eth0 -j ACCEPT

echo "$(tput setaf 6)Saving IP tables...$(tput sgr0)"
sh -c "iptables-save > /etc/iptables.ipv4.nat"

echo "Add auto start on startup the Raspberry Pi."
sed -i '/exit 0/ i iptables-restore < /etc/iptables.ipv4.nat' /etc/rc.local

echo "$(tput setaf 6)Rebooting...$(tput sgr0)"
reboot

exit 0
