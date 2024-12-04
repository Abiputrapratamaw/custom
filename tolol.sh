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
dependence ip
interface=$(ip route | grep default | sed -e 's/^.*dev.//' -e 's/.proto.*//')
IPv4=$(curl -4 -s icanhazip.com)
GATE=$(ip route | awk '/default/ { print $3 }')
MASK="255.255.240.0"

# Create Windows network configuration
ethernt="Ethernet Instance 0"
cat >/tmp/net.bat<<EOF
@ECHO OFF
cd.>%windir%\GetAdmin
if exist %windir%\GetAdmin (del /f /q "%windir%\GetAdmin") else (
echo CreateObject^("Shell.Application"^).ShellExecute "%~s0", "%*", "", "runas", 1 >> "%temp%\Admin.vbs"
"%temp%\Admin.vbs"
del /f /q "%temp%\Admin.vbs"
exit /b 2)

netsh -c interface ip set address name="$ethernt" source=static address=$IPv4 mask=255.255.240.0 gateway=$GATE
netsh -c interface ip add dnsservers name="$ethernt" address=1.1.1.1 index=1 validate=no
netsh -c interface ip add dnsservers name="$ethernt" address=8.8.4.4 index=2 validate=no

ECHO SELECT VOLUME=%%SystemDrive%% > "%SystemDrive%\diskpart.extend"
ECHO EXTEND >> "%SystemDrive%\diskpart.extend"
START /WAIT DISKPART /S "%SystemDrive%\diskpart.extend"

cd /d "%ProgramData%/Microsoft/Windows/Start Menu/Programs/Startup"
del "%~f0"
exit
EOF

# Create installer script
cat >/tmp/install.sh<<'EOF'
#!/bin/bash
wget --no-check-certificate -O- https://image.yha.my.id/2:/windows10.gz | gunzip | dd of=/dev/vda bs=3M status=progress

mount.ntfs-3g /dev/vda2 /mnt
cd "/mnt/ProgramData/Microsoft/Windows/Start Menu/Programs/"
cd Start* || cd start*
cp -f /tmp/net.bat net.bat

echo 'Your server will turning off in 5 second'
sleep 5
poweroff
EOF

chmod +x /tmp/install.sh

GRUBDIR=/boot/grub
GRUBFILE=grub.cfg

cat >/tmp/grub.new <<EndOfMessage
menuentry "Install Windows 10" {
  set root=(hd0,1)
  linux /vmlinuz noswap ip=$IPv4::$GATE:$MASK
  initrd /initrd.img
  linux16 /tmp/install.sh
}
EndOfMessage

if [ ! -f $GRUBDIR/$GRUBFILE ]; then
  echo "Grub config not found $GRUBDIR/$GRUBFILE. Installer only runs on Debian or Ubuntu!"
  exit 2
fi

clear && echo -e "\n\033[36m# Install\033[0m\n"
echo "Installer will reboot your computer then install Windows 10 with these settings:";
echo "";
echo "IPv4: $IPv4";
echo "MASK: $MASK";
echo "GATE: $GATE";

if [ -n "$verbose" ]; then
  echo "============================================"
  echo "Debug: $isDebug";
  echo "Recovery: $isRecovery";
  echo "Grub entry:"
  cat /tmp/grub.new
  echo "============================================"
fi
echo "";

if [ "$confirm" = "no" ]; then
  echo -n "Start installation? (y,n) : ";
  read yesno;
  if [ "$yesno" != "y" ]; then
    exit 1;
  fi
fi

# Copy install script
cp /tmp/install.sh /boot/
cp /tmp/net.bat /boot/

sed -i '$a\\n' /tmp/grub.new;
INSERTGRUB="$(awk '/menuentry /{print NR}' $GRUBDIR/$GRUBFILE|head -n 1)"
sed -i ''${INSERTGRUB}'i\\n' $GRUBDIR/$GRUBFILE;
sed -i ''${INSERTGRUB}'r /tmp/grub.new' $GRUBDIR/$GRUBFILE;

# Set as default boot entry
sed -i 's/GRUB_DEFAULT=.*/GRUB_DEFAULT="Install Windows 10"/' /etc/default/grub
update-grub

echo "Rebooting to start installation..."
sleep 3
reboot
