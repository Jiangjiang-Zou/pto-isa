#!/usr/bin/env bash

set -euo pipefail

a5_runner_log() {
  echo "[a5-runner-init] $*"
}

a5_runner_warn() {
  echo "[a5-runner-init] WARN: $*" >&2
}

a5_runner_fail() {
  echo "[a5-runner-init] ERROR: $*" >&2
  return 1
}

a5_runner_is_root() {
  [[ "$(id -u)" -eq 0 ]]
}

a5_runner_has_command() {
  command -v "$1" >/dev/null 2>&1
}

a5_runner_python_has_module() {
  local module_name="$1"
  python3 -c "import importlib.util, sys; sys.exit(0 if importlib.util.find_spec('${module_name}') else 1)"
}

a5_runner_detect_pkg_manager() {
  local manager=""
  for manager in yum dnf apt-get zypper; do
    if a5_runner_has_command "${manager}"; then
      printf '%s\n' "${manager}"
      return 0
    fi
  done

  return 1
}

a5_runner_install_with_pm() {
  local manager="$1"
  shift

  case "${manager}" in
    yum | dnf)
      "${manager}" -y install "$@"
      ;;
    apt-get)
      DEBIAN_FRONTEND=noninteractive "${manager}" update
      DEBIAN_FRONTEND=noninteractive "${manager}" install -y "$@"
      ;;
    zypper)
      zypper --non-interactive install "$@"
      ;;
    *)
      return 1
      ;;
  esac
}

a5_runner_ensure_system_packages() {
  local manager=""
  manager="$(a5_runner_detect_pkg_manager || true)"

  if [[ -z "${manager}" ]]; then
    a5_runner_warn "No supported package manager was detected; skipping system package bootstrap."
    return 0
  fi

  if ! a5_runner_is_root; then
    a5_runner_warn "Runner bootstrap is not running as root; skipping system package installation."
    return 0
  fi

  case "${manager}" in
    yum | dnf)
      a5_runner_install_with_pm "${manager}" cmake git
      a5_runner_install_with_pm "${manager}" gtest-devel || a5_runner_install_with_pm "${manager}" googletest-devel
      ;;
    apt-get)
      a5_runner_install_with_pm "${manager}" cmake git libgtest-dev
      ;;
    zypper)
      a5_runner_install_with_pm "${manager}" cmake git gtest-devel
      ;;
  esac
}

a5_runner_prefer_system_tool() {
  local tool_name="$1"
  local candidate=""

  for candidate in "/usr/bin/${tool_name}" "/bin/${tool_name}"; do
    if [[ -x "${candidate}" ]]; then
      mkdir -p /usr/local/bin
      ln -sf "${candidate}" "/usr/local/bin/${tool_name}"
      return 0
    fi
  done

  return 1
}

a5_runner_ensure_python_package() {
  local module_name="$1"
  local package_name="${2:-$1}"

  if a5_runner_python_has_module "${module_name}"; then
    return 0
  fi

  a5_runner_log "Installing Python package ${package_name}"
  python3 -m pip install "${package_name}"
}

a5_bootstrap_runner_env() {
  if [[ "${A5_RUNNER_SKIP_BOOTSTRAP:-0}" == "1" ]]; then
    a5_runner_log "Skipping bootstrap because A5_RUNNER_SKIP_BOOTSTRAP=1"
    return 0
  fi

  a5_runner_ensure_system_packages

  a5_runner_prefer_system_tool cmake || a5_runner_warn "System cmake was not found."
  a5_runner_prefer_system_tool git || a5_runner_warn "System git was not found."

  export PATH="/usr/local/bin:${PATH}"

  a5_runner_has_command python3 || a5_runner_fail "python3 is required on the runner."
  a5_runner_has_command cmake || a5_runner_fail "cmake is required on the runner."
  a5_runner_has_command git || a5_runner_fail "git is required on the runner."

  a5_runner_ensure_python_package numpy numpy
  a5_runner_ensure_python_package ml_dtypes ml_dtypes
  a5_runner_ensure_python_package en_dtypes en_dtypes

  a5_runner_log "Using python: $(command -v python3)"
  a5_runner_log "Using git: $(command -v git)"
  a5_runner_log "Using cmake: $(command -v cmake)"
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  a5_bootstrap_runner_env "$@"
fi
