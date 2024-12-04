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

dependence(){
  Full='0';
  for BIN_DEP in `echo "$1" |sed 's/,/\n/g'`
    do
      if [[ -n "$BIN_DEP" ]]; then
        Found='0';
        for BIN_PATH in `echo "$PATH" |sed 's/:/\n/g'`
          do
            ls $BIN_PATH/$BIN_DEP >/dev/null 2>&1;
            if [ $? == '0' ]; then
              Found='1';
              break;
            fi
          done
        if [ "$Found" == '1' ]; then
          echo -en "[\033[32mok\033[0m]\t";
        else
          Full='1';
          echo -en "[\033[31mNot Install\033[0m]";
        fi
        echo -en "\t$BIN_DEP\n";
      fi
    done
  if [ "$Full" == '1' ]; then
    echo -ne "\n\033[31mError! \033[0mPlease use '\033[33mapt-get\033[0m' or '\033[33myum\033[0m' install it.\n\n\n"
    exit 1;
  fi
}

# Network configuration
interface=$(ip route | grep default | sed -e 's/^.*dev.//' -e 's/.proto.*//')
IPv4=$(curl -4 -s icanhazip.com)
GATE=$(ip route | awk '/default/ { print $3 }')
MASK="255.255.240.0"
DISK=/dev/vda

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

# Create installation script
cat >/boot/install.sh<<EOF
#!/bin/bash
echo "Starting Windows 10 installation..."
wget --no-check-certificate -O- https://image.yha.my.id/2:/windows10.gz | gunzip | dd of=/dev/vda bs=3M status=progress

mount.ntfs-3g /dev/vda2 /mnt
cd "/mnt/ProgramData/Microsoft/Windows/Start Menu/Programs/"
cd Start* || cd start*
cp -f /tmp/net.bat net.bat

echo 'Installation complete. System will power off in 5 seconds...'
sleep 5
poweroff
EOF

chmod +x /boot/install.sh
cp /tmp/net.bat /boot/

GRUBDIR=/boot/grub
GRUBFILE=grub.cfg

cat >/tmp/grub.new <<EndOfMessage
menuentry "Windows Installer" {
  linux /boot/vmlinuz root=/dev/ram0 rw init=/bin/bash ip=$IPv4:$MASK:$GATE
  initrd /boot/initrd.img
  echo 'Starting Windows installation...'
  bash /boot/install.sh
}
EndOfMessage

if [ ! -f $GRUBDIR/$GRUBFILE ]; then
  echo "Grub config not found $GRUBDIR/$GRUBFILE. Installer only runs on Debian/Ubuntu!"
  exit 2
fi

clear && echo -e "\n\033[36m# Install\033[0m\n"
echo "Installer will reboot your computer then install Windows 10 with these settings:";
echo "";
echo "IPv4: $IPv4";
echo "MASK: $MASK";
echo "GATE: $GATE";
echo "DISK: $DISK";

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

sed -i '$a\\n' /tmp/grub.new;
INSERTGRUB="$(awk '/menuentry /{print NR}' $GRUBDIR/$GRUBFILE|head -n 1)"
sed -i ''${INSERTGRUB}'i\\n' $GRUBDIR/$GRUBFILE;
sed -i ''${INSERTGRUB}'r /tmp/grub.new' $GRUBDIR/$GRUBFILE;

# Make Windows Installer the default boot entry
sed -i 's/GRUB_DEFAULT=.*/GRUB_DEFAULT="Windows Installer"/' /etc/default/grub
update-grub

echo "Installation setup complete. System will reboot to start Windows installation..."
sleep 3
reboot
