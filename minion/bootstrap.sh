#!/bin/bash

set -e +x -uo pipefail # Exit after failed command but don't print commands

. ../shared/functions.inc.sh

#####################
### PREREQUISITES ###
#####################

becho "> Checking prerequisites:"

check_binary "systemctl"

echo ""

#######################
### INSTALLING SALT ###
#######################

becho "> Preparing to install Salt"

becho "> Installing Salt (Minion)"

curl -L https://github.com/saltstack/salt-bootstrap/releases/latest/download/bootstrap-salt.sh | sh -s -- -d -X onedir

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

echo "  Waiting for salt-minion to start"

# Obviously a fake wait
sleep 10

systemctl status salt-minion > /tmp/salt-minion-status
if grep "The payload signature did not validate" /tmp/salt-minion-status >/dev/null; then
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
