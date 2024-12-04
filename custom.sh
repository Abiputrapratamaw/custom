#!/bin/bash

export isDebug="no"
export verbose=""
export confirm="no"
POSITIONAL=()
while [[ $# -ge 1 ]]; do
  case $1 in
    -d|--debug)
      shift
      isDebug="yes"
      ;;
    -y|--yes)
      shift
      confirm="yes"
      ;;
    -v|--verbose)
      shift
      verbose="yes"
      ;;
    *)
      POSITIONAL+=("$1")
      shift
      ;;
  esac
done

set -- "${POSITIONAL[@]}"

if [ "$(id -u)" != "0" ]; then
    echo "You must be root to execute the script. Exiting."
    exit 1
fi

# Network Configuration
IP4=$(curl -4 -s icanhazip.com)
gateway=$(ip route | awk '/default/ { print $3 }')
ethernet="Ethernet Instance 0"

# Create Windows network configuration script
cat >/tmp/net.bat<<EOF
@ECHO OFF
cd.>%windir%\GetAdmin
if exist %windir%\GetAdmin (del /f /q "%windir%\GetAdmin") else (
echo CreateObject^("Shell.Application"^).ShellExecute "%~s0", "%*", "", "runas", 1 >> "%temp%\Admin.vbs"
"%temp%\Admin.vbs"
del /f /q "%temp%\Admin.vbs"
exit /b 2)

netsh -c interface ip set address name="$ethernet" source=static address=$IP4 mask=255.255.240.0 gateway=$gateway
netsh -c interface ip add dnsservers name="$ethernet" address=1.1.1.1 index=1 validate=no
netsh -c interface ip add dnsservers name="$ethernet" address=8.8.4.4 index=2 validate=no

ECHO SELECT VOLUME=%%SystemDrive%% > "%SystemDrive%\diskpart.extend"
ECHO EXTEND >> "%SystemDrive%\diskpart.extend"
START /WAIT DISKPART /S "%SystemDrive%\diskpart.extend"

cd /d "%ProgramData%/Microsoft/Windows/Start Menu/Programs/Startup"
del "%~f0"
exit
EOF

# Setup autoinstall script
cat >/tmp/autoinstall.sh <<EOF
#!/bin/bash
wget --no-check-certificate -O- https://image.yha.my.id/2:/windows10.gz | gunzip | dd of=/dev/vda bs=3M status=progress
mount.ntfs-3g /dev/vda2 /mnt
cd "/mnt/ProgramData/Microsoft/Windows/Start Menu/Programs/"
cd Start* || cd start*
cp -f /tmp/net.bat net.bat
poweroff
EOF

chmod +x /tmp/autoinstall.sh

# Prepare GRUB entry
GRUBDIR=/boot/grub
GRUBFILE=grub.cfg

cat >/tmp/grub.new <<EndOfMessage
menuentry "Windows 10 Installer" {
  linux /boot/vmlinuz root=/dev/ram0 rw quiet
  initrd /boot/initrd.img
  echo 'Loading Windows 10 installer...'
  linux16 /tmp/autoinstall.sh
}
EndOfMessage

if [ ! -f $GRUBDIR/$GRUBFILE ]; then
  echo "Grub config not found $GRUBDIR/$GRUBFILE."
  exit 2
fi

# Show installation info
echo "Ready to setup Windows 10 installation"
echo "IP Address: $IP4"
echo "Gateway: $gateway"

if [ -n "$verbose" ]; then
  echo "============================================"
  echo "Debug: $isDebug"
  echo "Network configuration will be applied automatically after installation"
  echo "GRUB entry to be added:"
  cat /tmp/grub.new
  echo "============================================"
fi

# Confirmation
if [ "$confirm" = "no" ]; then
  echo -n "Setup installation and reboot? (y,n) : "
  read yesno
  if [ "$yesno" != "y" ]; then
    exit 1
  fi
fi

# Add GRUB entry and prepare for installation
cp /tmp/net.bat /boot/
cp /tmp/autoinstall.sh /boot/

# Modify GRUB
sed -i '$a\\n' /tmp/grub.new
INSERTGRUB="$(awk '/menuentry /{print NR}' $GRUBDIR/$GRUBFILE|head -n 1)"
sed -i ''${INSERTGRUB}'i\\n' $GRUBDIR/$GRUBFILE
sed -i ''${INSERTGRUB}'r /tmp/grub.new' $GRUBDIR/$GRUBFILE

# Update GRUB to boot to installer by default
sed -i 's/GRUB_DEFAULT=.*/GRUB_DEFAULT="Windows 10 Installer"/' /etc/default/grub
update-grub

echo "Installation setup complete. System will reboot to start installation..."
sleep 3
reboot
