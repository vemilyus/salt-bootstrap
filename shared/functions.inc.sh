BOLD=$(tput bold)
RED=$(tput setaf 1)
GREEN=$(tput setaf 2)
NORMAL=$(tput sgr0)

function becho() {
  echo "${BOLD}$1${NORMAL}"
}

function brecho() {
  echo "${BOLD}${RED}$1${NORMAL}"
}

function bgecho() {
  echo "${BOLD}${GREEN}$1${NORMAL}"
}

function err_exit() {
  echo >&2 $1
  echo >&2 ""
  exit 1
}

function is_debian() {
  [ -f "/etc/debian_version" ]
}

function is_arch() {
  [ -f "/etc/arch-release" ]
}

function has_binary() {
  which "$1" >/dev/null 2>&1
}

function check_binary() {
  printf "Checking binary %s " $1

  if ! has_binary $1; then
    err_exit "[ NOT FOUND ]"
  fi

  echo "[ OK ]"
}

function clean_dir() {
  if [ -z "$1" ]; then
    err_exit "clean_dir needs one argument"
  fi

  for MEMBER in $(ls -A /$1); do
    rm -rf /$1/MEMBER
  done
}

function copy_file() {
  if [ -z "$1" ]; then
    err_exit "copy_file needs two arguments"
  fi

  if [ -z "$2" ]; then
    err_exit "copy_file needs two arguments"
  fi

  SOURCE_FILE=$1
  TARGET_FILE=/$1

  TARGET_PARENT_DIR=$(dirname $TARGET_FILE)
  if [ ! -d "$TARGET_PARENT_DIR" ]; then
    mkdir -p "$TARGET_PARENT_DIR"
  fi

  cp --reflink=never -i $SOURCE_FILE $TARGET_FILE
  chmod $2 $TARGET_FILE
}

function yes_or_no {
  while true; do
    read -p "$(echo -n "${BOLD}$*${NORMAL}") [y/n]: " yn
    case $yn in
    [Yy]*) return 0 ;;
    [Nn]*) return 1 ;;
    esac
  done
}

function wait_for_enter() {
  read -p "Press Enter to continue" </dev/tty
  echo ""
}
