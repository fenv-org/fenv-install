#!/usr/bin/env bash

# cSpell:words substr

set -eo pipefail

if [[ -n "$FENV_DEBUG" ]]; then
  # https://wiki-dev.bash-hackers.org/scripting/debuggingtips#making_xtrace_more_useful
  export PS4='+(${BASH_SOURCE}:${LINENO}): ${FUNCNAME[0]:+${FUNCNAME[0]}(): }'
  set -x
fi

OS_TYPE_LINUX=1
OS_TYPE_MACOS=2
OS_TYPE_WSL=3
OS_TYPE_MINGW=4
OS_TYPE_GIT_BASH=5
OS_TYPE_UNKNOWN=6

temp_dir=$(mktemp -d "${TMPDIR:-/tmp}/tmp_XXXXXXXX")

cleanup() {
  rm -rf "$temp_dir"
}

trap cleanup EXIT INT TERM

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

function download_fenv_binary() {
  local version="$1"
  local target_triple
  target_triple=$(get_target_triple)

  >&2 echo "Downloading \`fenv\` CLI..."

  # Construct download URL
  local asset_name="fenv-${target_triple}.zip"
  local download_url
  if [[ -z "$version" ]]; then
    download_url="https://github.com/fenv-org/fenv/releases/latest/download/${asset_name}"
  else
    download_url="https://github.com/fenv-org/fenv/releases/download/${version}/${asset_name}"
  fi

  if [[ -n "$FENV_DEBUG" ]]; then
    >&2 echo "Download URL: $download_url"
  fi

  # Setup auth args
  local github_token="${GITHUB_TOKEN:-${GH_TOKEN:-}}"
  local auth_args=()
  if [[ -n "$github_token" ]]; then
    auth_args=(-H "Authorization: Bearer $github_token")
  fi

  # Get redirect location to extract the tag (stored as global for use in copy_shims)
  local redirect_url
  if [[ -z "$version" ]]; then
    # For latest, get the redirect location to determine the tag
    redirect_url=$(curl -fsS -I "${auth_args[@]}" "$download_url" 2>&1 | grep -i "^location:" | head -1 | sed 's/^location: //i' | tr -d '\r')

    if [[ -z "$redirect_url" ]]; then
      >&2 echo "fenv-init: Failed to get redirect URL"
      exit 4
    fi

    # Extract tag from redirect URL
    # URL format: https://github.com/fenv-org/fenv/releases/download/{tag}/{asset}
    if [[ "$redirect_url" =~ /releases/download/([^/]+)/ ]]; then
      release_tag="${BASH_REMATCH[1]}"
      >&2 echo "fenv-init: Found release: $release_tag"
    else
      >&2 echo "fenv-init: Failed to extract tag from redirect URL: $redirect_url"
      exit 4
    fi
  else
    # For specific version, use the version as the tag
    release_tag="$version"
    >&2 echo "fenv-init: Using version: $release_tag"
  fi

  # Download the asset
  local zip_file="$temp_dir/fenv.zip"
  if ! curl -fsSL "${auth_args[@]}" -o "$zip_file" "$download_url"; then
    >&2 echo "fenv-init: Failed to download asset from $download_url"
    exit 5
  fi

  # Extract to FENV_ROOT/bin
  rm -rf "${fenv_home:?}/bin"
  mkdir -p "${fenv_home}/bin"

  if ! unzip -o "$zip_file" -d "${fenv_home}/bin" >/dev/null; then
    >&2 echo "fenv-init: Failed to extract asset"
    exit 5
  fi
}

function copy_shims() {
  >&2 echo "Copying shims..."

  # Use the global release_tag variable set by download_fenv_binary
  if [[ -z "$release_tag" ]]; then
    >&2 echo "fenv-init: Error: release_tag not set"
    exit 4
  fi

  # Setup directories
  rm -rf "${fenv_home}/shims"
  mkdir -p "${fenv_home}/shims"
  mkdir -p "${fenv_home}/versions"

  # Download shims
  local shims=("flutter" "dart")
  local github_token="${GITHUB_TOKEN:-${GH_TOKEN:-}}"
  local auth_args=()
  if [[ -n "$github_token" ]]; then
    auth_args=(-H "Authorization: Bearer $github_token")
  fi

  for shim in "${shims[@]}"; do
    local url="https://raw.githubusercontent.com/fenv-org/fenv/${release_tag}/shims/${shim}"
    local dest="${fenv_home}/shims/${shim}"

    if [[ -n "$FENV_DEBUG" ]]; then
      >&2 echo "fenv-init: Copying shims/${shim} from $url"
    fi

    if ! curl -fsSL "${auth_args[@]}" -o "$dest" "$url"; then
      >&2 echo "fenv-init: Failed to copy shims/${shim}"
      exit 3
    fi

    if [[ ! -f "$dest" ]]; then
      >&2 echo "fenv-init: Failed to copy shims/${shim}"
      exit 3
    fi

    chmod 755 "$dest"
  done
}

function higher_version() {
  printf "%s\n%s" "$1" "$2" | sort --version-sort | tail -n 1
}

function get_target_triple() {
  local arch os_type

  case "$(uname -m)" in
    x86_64) arch="x86_64" ;;
    aarch64|arm64) arch="aarch64" ;;
    *) abort "Unsupported architecture: $(uname -m)" ;;
  esac

  case "$(uname)" in
    Linux) os_type="unknown-linux-musl" ;;
    Darwin) os_type="apple-darwin" ;;
    *) abort "Unsupported OS: $(uname)" ;;
  esac

  echo "${arch}-${os_type}"
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
    exit 0
  fi

  # Install fenv binary
  download_fenv_binary "$FENV_VERSION"

  if [[ ! -f "$fenv_home/bin/fenv" ]]; then
    abort "Failed to install 'fenv'"
  fi

  # Copy shims
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
}

main
