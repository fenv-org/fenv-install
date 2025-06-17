#!/usr/bin/env bash

# cSpell:words substr

set -eo pipefail

if [[ -n "$FENV_DEBUG" ]]; then
  # https://wiki-dev.bash-hackers.org/scripting/debuggingtips#making_xtrace_more_useful
  export PS4='+(${BASH_SOURCE}:${LINENO}): ${FUNCNAME[0]:+${FUNCNAME[0]}(): }'
  set -x
fi

DENO_VERSION=v2.3.6

OS_TYPE_LINUX=1
OS_TYPE_MACOS=2
OS_TYPE_WSL=3
OS_TYPE_MINGW=4
OS_TYPE_GIT_BASH=5
OS_TYPE_UNKNOWN=6

SCRIPT_AUTHORITY="raw.githubusercontent.com"
SCRIPT_REPO="fenv-org/fenv-install"
SCRIPT_VERSION="main"
SCRIPT_BASE_URL="https://$SCRIPT_AUTHORITY/$SCRIPT_REPO/$SCRIPT_VERSION"
DENO_RELOAD_FLAG="--reload=https://$SCRIPT_AUTHORITY/$SCRIPT_REPO"

temp_dir=$(mktemp -d "${TMPDIR:-/tmp}/tmp_XXXXXXXX")
deno_bin=$temp_dir/bin/deno

if [[ -z "$FENV_ROOT" ]]; then
  fenv_home=$HOME/.fenv
else
  fenv_home="${FENV_ROOT%/}"
fi

function abort() {
  >&2 echo "fenv-init: $*"
  rm -rf "$temp_dir"
  exit 1
}

# shellcheck disable=SC2308
function check_os() {
  # Check if the OS is Linux
  if [[ "$(uname)" == "Linux" ]]; then
    echo $OS_TYPE_LINUX
  # Check if the OS is macOS
  elif [[ "$(uname)" == "Darwin" ]]; then
    echo $OS_TYPE_MACOS
  # Check if the OS is Windows using WSL
  elif grep -qE "(Microsoft|WSL)" /proc/version &>/dev/null; then
    echo $OS_TYPE_WSL
    abort "Unsupported OS: Windows using WSL"
  # Check if the OS is Windows using MinGW
  elif [[ "$(expr substr "$(uname -s)" 1 10)" == "MINGW32_NT" ]]; then
    echo $OS_TYPE_MINGW
    abort "Unsupported OS: Windows using MinGW"
  # Check if the OS is Windows using Git Bash
  elif [[ "$(expr substr "$(uname -s)" 1 5)" == "MINGW" ]]; then
    echo $OS_TYPE_GIT_BASH
    abort "Unsupported OS: Windows using Git Bash"
  # If none of the above conditions match, display an unknown OS message
  else
    echo $OS_TYPE_UNKNOWN
    abort "Unsupported OS"
  fi
}

function ensure_unzip() {
  if [[ -z "$(command -v "unzip" || true)" ]]; then
    abort "'unzip' is required to install 'fenv'"
  fi
}

function install_deno() {
  case "$(uname -sm)" in
  "Linux aarch64")
    # See here: https://github.com/LukeChannings/deno-arm64
    install_sh=https://gist.githubusercontent.com/LukeChannings/09d53f5c364391042186518c8598b85e/raw/ac8cd8c675b985edd4b3e16df63ffef14d1f0e24/deno_install.sh
    ;;

  *)
    install_sh=https://deno.land/install.sh
    ;;
  esac

  >&2 echo "Installing script runner..."
  curl -fsSL "$install_sh" | DENO_INSTALL=$temp_dir sh -s -- "$DENO_VERSION" >/dev/null
}

function deno_run() {
  # if [[ -n "$FENV_DEBUG" ]]; then
  #   # shellcheck disable=SC2068
  #   $deno_bin run --allow-run --allow-net --allow-read --allow-write --allow-env -L debug "$DENO_RELOAD_FLAG" $@
  # else
    # shellcheck disable=SC2068
    $deno_bin run --allow-run --allow-net --allow-read --allow-write --allow-env "$DENO_RELOAD_FLAG" $@
  # fi
}

function install_fenv() {
  >&2 echo "Downloading \`fenv\` CLI..."
  rm -rf "${fenv_home:-$HOME/.fenv}/bin"
  deno_run "$SCRIPT_BASE_URL/install-assets.ts" "$@"
  if [[ ! -f "$fenv_home/bin/fenv" ]]; then
    abort "Failed to install 'fenv'"
  fi
}

function copy_shims() {
  >&2 echo "Copying shims..."
  deno_run \
    "$SCRIPT_BASE_URL/gen-copy-shims-instructions.ts" \
    "$fenv_home" \
    "$FENV_VERSION"
}

function higher_version() {
  printf "%s\n%s" "$1" "$2" | sort --version-sort | tail -n 1
}

function main() {
  check_os >/dev/null
  ensure_unzip

  if [[ -n "$FENV_VERSION" ]] &&
    [[ "$(higher_version v0.0.4 "$FENV_VERSION")" == "v0.0.4" ]]; then
    git clone \
      -c advice.detachedHead=false \
      -b "$FENV_VERSION" \
      https://github.com/fenv-org/fenv \
      "$temp_dir"
    pushd "$temp_dir" >/dev/null
    ./setup_fenv.sh
    popd >/dev/null
    rm -rf "$temp_dir" >/dev/null
    exit 0
  fi

  install_deno
  install_fenv "$FENV_VERSION"
  copy_shims

  {
    echo ''
    echo '# Installation succeeds'
    echo '# Please execute the following command'
    echo ''
    echo "$fenv_home/bin/fenv init"
    echo ''
    echo "# And follow the instructions if you have not setup 'fenv' yet:"
  } >&2

  rm -rf "$temp_dir"
}

main
