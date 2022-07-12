#!/bin/bash

set -e +x -uo pipefail # Exit after failed command but don't print commands

. ../shared/functions.inc.sh

APT="apt-get -qq"
PACMAN="pacman --color=always --noconfirm --noprogressbar"

#####################
### PREREQUISITES ###
#####################

becho "> Checking prerequisites:"

printf "Checking binary apt or pacman"
if ! has_binary "apt" && ! has_binary "pacman"; then
  err_exit "[ NOT FOUND ]"
fi

echo "[ OK ]"

check_binary "gpg"
check_binary "systemctl"

echo ""

OS_ARCH=""
if grep -i arch /etc/os-release >/dev/null 2>&1; then
  OS_ARCH="y"
else
  $APT update
fi

#######################
### INSTALLING SALT ###
#######################

becho "> Preparing to install Salt"

## Need to add python-jinja to ignored packages when installing Salt, also to prevent upgrades
## to incompatible version
if [ ! -z "$OS_ARCH" ] && ! yes_or_no "> Has https://github.com/saltstack/salt/pull/61856 been released?"; then
  SALT_61856_MERGED=""
  if ! grep -E '^IgnorePkg\s+=.+?python-jinja' /etc/pacman.conf >/dev/null; then
    echo "Patching pacman.conf"
    sed -i -E "s/^#?(IgnorePkg\s+=.*$)/\1,python-jinja/" /etc/pacman.conf
  else
    bgecho "pacman.conf already patched"
  fi
else
  SALT_61856_MERGED="y"
fi

if [ -z "$SALT_61856_MERGED" ]; then
  becho "> Installing compatible older version of python-jinja"
  $PACMAN -U https://archive.archlinux.org/packages/p/python-jinja/python-jinja-3.0.3-3-any.pkg.tar.zst
fi

becho "> Installing Salt (Minion)"

if [ -z "$OS_ARCH" ]; then
  $APT install salt-minion python-pip-whl
else
  $PACMAN -Sy --needed salt python-pip
fi

copy_file etc/salt/minion 0644

mkdir -p ~/.ssh
touch ~/.ssh/known_hosts
if ! grep 'github.com' ~/.ssh/known_hosts >/dev/null; then
  ssh-keyscan -H github.com >>~/.ssh/known_hosts
fi

###############################
### FINAL START-UP SEQUENCE ###
###############################

echo ""
becho "> Starting Salt minion"

if ! systemctl start salt-minion; then
  brecho "> Failed to start salt-minion, entering journalctl -xe"
  journalctl -xe
fi

if ! systemctl is-active salt-minion >/dev/null; then
  err_exit "Failed to start salt-minion"
fi

systemctl enable salt-minion

echo ""
echo "The Salt minion is now ready. Make sure to enroll its key in the Master before pressing enter."
echo ""

wait_for_enter

systemctl restart salt-minion

if ! systemctl is-active salt-minion >/dev/null; then
  err_exit "Failed to start salt-minion"
fi
