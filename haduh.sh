#!/bin/bash

export isDebug="no"
export isRecovery="no" 
export verbose=""
export confirm="no"
POSITIONAL=()
while [[ $# -ge 1 ]]; do
  case $1 in
    -d|--debug)
      shift  
      isDebug="yes"
      ;;
    -r|--recovery)
      shift
      isRecovery="yes"
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
      shift;
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
getwey=$(ip route | awk '/default/ { print $3 }')
ethernt="Ethernet Instance 0"

# Create Windows network configuration
cat >/tmp/net.bat<<EOF
@ECHO OFF
cd.>%windir%\GetAdmin
if exist %windir%\GetAdmin (del /f /q "%windir%\GetAdmin") else (
echo CreateObject^("Shell.Application"^).ShellExecute "%~s0", "%*", "", "runas", 1 >> "%temp%\Admin.vbs"
"%temp%\Admin.vbs"
del /f /q "%temp%\Admin.vbs"
exit /b 2)

netsh -c interface ip set address name="$ethernt" source=static address=$IP4 mask=255.255.240.0 gateway=$getwey
netsh -c interface ip add dnsservers name="$ethernt" address=1.1.1.1 index=1 validate=no
netsh -c interface ip add dnsservers name="$ethernt" address=8.8.4.4 index=2 validate=no

ECHO SELECT VOLUME=%%SystemDrive%% > "%SystemDrive%\diskpart.extend"
ECHO EXTEND >> "%SystemDrive%\diskpart.extend"
START /WAIT DISKPART /S "%SystemDrive%\diskpart.extend"

cd /d "%ProgramData%/Microsoft/Windows/Start Menu/Programs/Startup"
del "%~f0"
exit
EOF

# Windows Image URL
selectos="https://image.yha.my.id/2:/windows10.gz"

GRUBDIR=/boot/grub
GRUBFILE=grub.cfg

# Create GRUB entry
cat >/tmp/grub.new <<EndOfMessage
menuentry "Windows Installer" {
  set root=(hd0,1)
  linux /vmlinuz ro init=/bin/bash
  initrd /initrd.img
  echo 'Starting Windows installation...'
}
EndOfMessage

if [ ! -f $GRUBDIR/$GRUBFILE ]; then
  echo "Grub config not found $GRUBDIR/$GRUBFILE."
  exit 2
fi

# Installation confirmation
if [ "$confirm" = "no" ]; then
  echo "Ready to install Windows"
  echo "IP Address: $IP4"
  echo "Gateway: $getwey"
  
  if [ -n "$verbose" ]; then
    echo "============================================"
    echo "Debug: $isDebug"
    echo "GRUB entry to be added:"
    cat /tmp/grub.new
    echo "============================================"
  fi
  
  echo -n "Start installation? (y,n) : "
  read yesno
  if [ "$yesno" != "y" ]; then
    exit 1
  fi
fi

# Add GRUB entry and prepare for installation
cp /tmp/net.bat /boot/

# Add installer script 
cat >/boot/install.sh<<EOF
#!/bin/bash
wget --no-check-certificate -O- $selectos | gunzip | dd of=/dev/vda bs=3M status=progress

mount.ntfs-3g /dev/vda2 /mnt
cd "/mnt/ProgramData/Microsoft/Windows/Start Menu/Programs/"
cd Start* || cd start*
cp -f /boot/net.bat net.bat

echo 'Installation complete. System will power off in 5 seconds...'
sleep 5
poweroff
EOF

chmod +x /boot/install.sh

# Modify GRUB
sed -i '$a\\n' /tmp/grub.new
INSERTGRUB="$(awk '/menuentry /{print NR}' $GRUBDIR/$GRUBFILE|head -n 1)"
sed -i ''${INSERTGRUB}'i\\n' $GRUBDIR/$GRUBFILE
sed -i ''${INSERTGRUB}'r /tmp/grub.new' $GRUBDIR/$GRUBFILE

# Set new entry as default
sed -i 's/GRUB_DEFAULT=.*/GRUB_DEFAULT="Windows Installer"/' /etc/default/grub
update-grub

echo "Installation setup complete. System will reboot to start Windows installation..."
sleep 3
reboot
