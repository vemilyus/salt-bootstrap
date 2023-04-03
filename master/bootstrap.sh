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

check_binary "systemctl"

if ! has_binary "ssh"; then
  becho "> Installing OpenSSH"
  $INSTALL openssh
fi

if ! has_binary "curl"; then
  becho "> Installing curl"
  $INSTALL curl
fi

if ! has_binary "gpg"; then
  becho "> Installing gpg"
  $INSTALL gpg
fi

if ! has_binary "vim"; then
  becho "> Installing vim"
  $INSTALL vim
fi

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

becho "> Installing Salt"

if is_debian; then
  $INSTALL salt-master salt-minion salt-ssh salt-api libgit2-1.1

  salt-pip install pygit2
elif is_arch; then
  $INSTALL salt python-pip python-pygit2 python-cherrypy python-psutil
fi

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

echo "  Waiting for salt-master to start"

if ! systemctl restart salt-master >/dev/null; then
  brecho "> Failed to start salt-master, entering journalctl -xe"
  journalctl -xe

  err_exit "Failed to start salt-master"
fi

# Obviously a fake wait
sleep 3
if ! systemctl is-active salt-master >/dev/null; then
  err_exit "Failed to start salt-master"
fi

salt-run cache.clear_git_lock gitfs type=update >/dev/null

if ! systemctl restart salt-api >/dev/null; then
  brecho "> Failed to start salt-api, entering journalctl -xe"
  journalctl -xe

  err_exit "Failed to start salt-api"
fi

if ! systemctl restart salt-minion >/dev/null; then
  brecho "> Failed to start salt-minion, entering journalctl -xe"
  journalctl -xe

  err_exit "Failed to start salt-minion"
fi

if ! systemctl is-active salt-minion >/dev/null; then
  err_exit "Failed to start salt-minion"
fi

systemctl enable salt-master >/dev/null
systemctl enable salt-api >/dev/null
systemctl enable salt-minion >/dev/null

becho "> Enrolling local salt-minion key"
salt-key -A -y >/dev/null

systemctl restart salt-minion >/dev/null

if ! systemctl is-active salt-minion >/dev/null; then
  err_exit "Failed to start salt-minion"
fi

echo ""
echo "The Salt master is now ready to accept connections from minions"
echo ""

wait_for_enter
