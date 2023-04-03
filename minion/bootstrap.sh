#!/bin/bash

set -e +x -uo pipefail # Exit after failed command but don't print commands

. ../shared/functions.inc.sh

APT="apt-get -qq -y"
PACMAN="pacman --color=always --noconfirm --noprogressbar"

if is_debian; then
  INSTALL="$APT install"
elif is_arch; then
  INSTALL="$PACMAN -Sy --needed"
fi

#####################
### PREREQUISITES ###
#####################

becho "> Checking prerequisites:"

if is_debian; then
  echo "Debian detected"
elif is_arch; then
  echo "Arch Linux detected"
else
  err_exit "Unknown OS"
fi

if is_debian; then
  check_binary "apt-get"
elif is_arch; then
  check_binary "pacman"
fi

if ! has_binary "gpg"; then
  becho "> Installing gpg"
  $INSTALL gpg
fi

check_binary "systemctl"

echo ""

#######################
### INSTALLING SALT ###
#######################

becho "> Preparing to install Salt"

if is_debian; then
  source /etc/os-release

  mkdir -p /etc/apt/keyrings

  curl -fsSL -o /etc/apt/keyrings/salt-archive-keyring.gpg "https://repo.saltproject.io/salt/py3/debian/$VERSION_ID/amd64/latest/salt-archive-keyring.gpg"
  echo "deb [signed-by=/etc/apt/keyrings/salt-archive-keyring.gpg arch=amd64] https://repo.saltproject.io/salt/py3/debian/$VERSION_ID/amd64/latest $VERSION_CODENAME main" | tee /etc/apt/sources.list.d/salt.list

  $APT update
fi

becho "> Installing Salt (Minion)"

if is_debian; then
  $INSTALL salt-minion
elif is_arch; then
  $INSTALL salt python-pip
fi

copy_file etc/salt/minion 0644

mkdir -p ~/.ssh
touch ~/.ssh/known_hosts
if ! grep 'github.com' ~/.ssh/known_hosts >/dev/null; then
  ssh-keyscan github.com >>~/.ssh/known_hosts
fi

###############################
### FINAL START-UP SEQUENCE ###
###############################

echo ""
becho "> Starting Salt minion"

if ! systemctl restart salt-minion; then
  brecho "> Failed to start salt-minion, entering journalctl -xe"
  journalctl -xe
fi

if ! systemctl is-active salt-minion >/dev/null; then
  err_exit "Failed to start salt-minion"
fi

systemctl enable salt-minion

############################
### RESETTING MASTER KEY ###
############################

if systemctl status salt-minion | grep "The master key has changed"; then
  becho "> Removing stale salt-master key"

  rm /etc/salt/pki/minion/minion_master.pub

  systemctl restart salt-minion
fi

echo ""
echo "The Salt minion is now ready. Make sure to enroll its key in the Master before pressing enter."
echo ""

wait_for_enter

systemctl restart salt-minion

if ! systemctl is-active salt-minion >/dev/null; then
  err_exit "Failed to start salt-minion"
fi
