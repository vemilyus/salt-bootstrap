#!/bin/bash

set -e +x -uo pipefail # Exit after failed command but don't print commands

. ../shared/functions.inc.sh

PACMAN="pacman --color=always --noconfirm --noprogressbar"

#####################
### PREREQUISITES ###
#####################

becho "> Checking prerequisites:"

check_binary "pacman"
check_binary "ssh"
check_binary "ssh-keygen"
check_binary "ssh-keyscan"
check_binary "systemctl"

if ! has_binary "gpg"; then
  becho "> Installing gpg"
  $PACMAN -Sy --needed gpg
fi

if ! has_binary "vim"; then
  becho "> Installing vim"
  $PACMAN -Sy --needed vim
fi

echo ""

#######################
### INSTALLING SALT ###
#######################

becho "> Preparing to install Salt"

## Need to add python-jinja to ignored packages when installing Salt, also to prevent upgrades
## to incompatible version
if ! yes_or_no "> Has https://github.com/saltstack/salt/pull/61856 been released?"; then
  SALT_61856_MERGED=""
  if ! grep -E '^IgnorePkg\s+=.+?python-jinja' /etc/pacman.conf >/dev/null; then
    echo "Patching pacman.conf"
    sed -i -E "s/^#?(IgnorePkg\s+=.*$)/\1,python-jinja/" /etc/pacman.conf
  else
    bgecho "pacman.conf already patched"
  fi
else
  SALT_61856_MERGED=1
fi

if [ -z "$SALT_61856_MERGED" ]; then
  becho "> Installing compatible older version of python-jinja"
  $PACMAN -U https://archive.archlinux.org/packages/p/python-jinja/python-jinja-3.0.3-3-any.pkg.tar.zst
fi

becho "> Installing Salt"

$PACMAN -Sy --needed salt python-pygit2

copy_file etc/salt/master 0644
copy_file etc/salt/minion 0644
copy_file etc/salt/roster 0644

#############################################
### INITIALIZING GPG KEYS FOR SALT PILLAR ###
#############################################

mkdir -p /etc/salt/gpgkeys
chmod 700 /etc/salt/gpgkeys

GPG="gpg --homedir /etc/salt/gpgkeys/"

if yes_or_no "> Generate GPG key-pair for Salt Pillar?"; then
  if $GPG --list-secret-keys "Salt Master" >/dev/null 2>&1; then
    becho "> GPG key-pair exists. Printing public key:"
  else
    becho "> Generating new GPG key-pair"
    $GPG --batch --passphrase '' --gen-key etc/salt/gpgkeys/gpg_gen_key
    echo ""
    becho "> Printing public key:"
  fi

  echo ""
  $GPG --armor --export "Salt Master"
  echo ""

  bgecho "GPG key-pair initialized"

  wait_for_enter
else
  becho "> Using existing GPG key-pair"
  becho "> Paste your private key into the new editor and :wq"

  PRIV_KEY_TMP_FILE=$(mktemp)
  trap 'rm -f $PRIV_KEY_TMP_FILE' EXIT

  wait_for_enter

  vim $PRIV_KEY_TMP_FILE

  becho "> Paste your public key into the new editor and :wq"

  PUB_KEY_TMP_FILE=$(mktemp)
  trap 'rm -rf $PRIV_KEY_TMP_FILE $PUB_KEY_TMP_FILE' EXIT

  wait_for_enter

  vim $PUB_KEY_TMP_FILE

  set +e # Let's ignore GPG import errors here, not irrecoverable
  $GPG --import $PRIV_KEY_TMP_FILE
  $GPG --import $PUB_KEY_TMP_FILE
  set -e

  rm -f $PRIV_KEY_TMP_FILE $PUB_KEY_TMP_FILE
  trap - EXIT

  bgecho "GPG key-pair initialized"
fi

#################################################
### GENERATING SSH KEYS FOR STATES AND PILLAR ###
#################################################

mkdir -p "$HOME/.ssh"

HAS_SSH_KEYS=1

for KEY_PURPOSE in pillar states; do
  if [ ! -f "$HOME/.ssh/salt-${KEY_PURPOSE}@salt-master" ]; then
    HAS_SSH_KEYS=""
    break
  fi
done

if [ -z $HAS_SSH_KEYS ]; then
  becho "> Generating SSH keys for states and pillar repo"

  for KEY_PURPOSE in pillar states; do
    NAME="salt-${KEY_PURPOSE}@salt-master"
    TARGET_FILE="$HOME/.ssh/${NAME}"

    # Overwrites any existing file
    ssh-keygen -q -t ed25519 -C $NAME -N '' -f $TARGET_FILE <<<y >/dev/null

    echo ""
    bgecho "Generated $KEY_PURPOSE key, add this public key as a deploy key in the $KEY_PURPOSE repo:"

    echo ""
    becho "$(cat ${TARGET_FILE}.pub)"
    echo ""

    wait_for_enter
  done

  bgecho "Keys generated"
fi

if ! grep 'github.com' ~/.ssh/known_hosts >/dev/null; then
  ssh-keyscan -H github.com >>~/.ssh/known_hosts
fi

###############################
### FINAL START-UP SEQUENCE ###
###############################

echo ""
becho "> Starting salt master and minion"

if ! systemctl start salt-master; then
  brecho "> Failed to start salt-master, entering journalctl -xe"
  journalctl -xe
fi

if ! systemctl start salt-minion; then
  brecho "> Failed to start salt-minion, entering journalctl -xe"
  journalctl -xe
fi

systemctl enable salt-master
systemctl enable salt-minion

systemctl is-active salt-master
systemctl is-active salt-minion

bgecho "Salt master and minion started and enabled"

echo ""
echo "The Salt master is now ready to accept connections from minions"
echo ""

wait_for_enter
