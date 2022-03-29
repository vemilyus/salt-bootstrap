#!/bin/bash

set -e +x # Exit after failed command but don't print commands

#################
### FUNCTIONS ###
#################

function err_exit() {
  echo >&2 $1
  echo >&2 ""
  exit 1
}

function check_binary() {
  printf "Checking binary %s " $1

  if ! which "$1" >/dev/null 2>&1; then
    err_exit "[ NOT FOUND ]"
  fi

  echo "[ OK ]"
}

function reset_dir() {
  echo "Leaving bootstrap directory"
  cd $1
}

######################
### ARG VALIDATION ###
######################
case "$1" in
"master" | "minion")
  SCRIPT_DIR=$1
  ;;
"")
  err_exit 'Expected argument: "master" or "minion"'
  ;;
*)
  err_exit "Unrecognized argument \"$1\""
  ;;
esac

#####################
### PREREQUISITES ###
#####################

echo "Checking out bootstrap repo"
echo ""

echo "Checking prerequisites:"

check_binary "git"

echo ""

#########################
### CHECKING OUT REPO ###
#########################

mkdir -p "${HOME}/git"

LOCAL_PATH="${HOME}/git/salt-bootstrap"

if [ ! -d "${LOCAL_PATH}/.git" ]; then
  echo "Checking out bootstrap repo"
  git clone "https://github.com/vemilyus/salt-bootstrap.git" "${LOCAL_PATH}"

  echo ""
fi

####################
### PREPARATIONS ###
####################

# We always want to return to the original directory, it's just cleaner that way
PREV_DIR=$(pwd)
trap 'reset_dir $PREV_DIR' EXIT

echo "Entering bootstrap directory (${LOCAL_PATH})"
cd "${LOCAL_PATH}"
echo ""

echo "Updating bootstrap repository"
git pull >/dev/null

echo ""

######################
### DOING THE WORK ###
######################

cd ./${SCRIPT_DIR}
chmod +x ./bootstrap.sh

./bootstrap.sh

###############
### CLEANUP ###
###############

echo ""
echo "Done bootstrapping"
