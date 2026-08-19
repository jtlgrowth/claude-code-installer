#!/usr/bin/env bash
#
# claude-code-installer — one command, working Claude Code CLI.
# macOS / Linux / WSL / Git Bash.
#
#   curl -fsSL https://raw.githubusercontent.com/jtlgrowth/claude-code-installer/main/install.sh | bash
#
# Flags (or env vars, for piped use):
#   --preset jtl   CCI_PRESET=jtl     also write a starter ~/.claude config
#   --minimal      CCI_MINIMAL=1      skip package manager + git/node/ripgrep
#   --yes          CCI_YES=1          non-interactive, assume yes
#   --dry-run      CCI_DRY_RUN=1      print every command, execute none
#   --help
#
# This script does NOT reimplement the Claude Code download. It delegates to
# Anthropic's official installer, which fetches a checksum-verified native
# binary. Everything here is about the things around that: prerequisites,
# PATH, and proving the result actually works.

set -Eeuo pipefail

REPO_RAW="https://raw.githubusercontent.com/jtlgrowth/claude-code-installer/main"
OFFICIAL_INSTALLER="https://claude.ai/install.sh"
HOMEBREW_INSTALLER="https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh"
NODE_MIN_MAJOR=20

PRESET="${CCI_PRESET:-}"
MINIMAL="${CCI_MINIMAL:-0}"
ASSUME_YES="${CCI_YES:-0}"
DRY_RUN="${CCI_DRY_RUN:-0}"

INSTALLED=()
ALREADY=()
SKIPPED=()

# ---------------------------------------------------------------- output ----

if [ -t 1 ] && [ -z "${NO_COLOR:-}" ]; then
  C_RESET=$'\033[0m'; C_BOLD=$'\033[1m'; C_DIM=$'\033[2m'
  C_RED=$'\033[31m'; C_GREEN=$'\033[32m'; C_YELLOW=$'\033[33m'; C_BLUE=$'\033[34m'
else
  C_RESET=""; C_BOLD=""; C_DIM=""; C_RED=""; C_GREEN=""; C_YELLOW=""; C_BLUE=""
fi

say()  { printf '%s\n' "$*"; }
info() { printf '%s==>%s %s\n' "$C_BLUE" "$C_RESET" "$*"; }
ok()   { printf '%s  ok%s %s\n' "$C_GREEN" "$C_RESET" "$*"; }
warn() { printf '%s  !!%s %s\n' "$C_YELLOW" "$C_RESET" "$*" >&2; }
err()  { printf '%serror:%s %s\n' "$C_RED" "$C_RESET" "$*" >&2; }
step() { printf '\n%s%s%s\n' "$C_BOLD" "$*" "$C_RESET"; }

on_error() {
  local exit_code=$? line=${1:-?}
  err "failed at line $line (exit $exit_code)"
  say ""
  say "What to do:"
  say "  1. Re-run with --dry-run to see the exact commands without executing them."
  say "  2. If a package install failed, run that one command by hand to see its error."
  say "  3. Claude Code itself can always be installed directly:"
  say "       curl -fsSL $OFFICIAL_INSTALLER | bash"
  exit "$exit_code"
}
trap 'on_error $LINENO' ERR

have() { command -v "$1" >/dev/null 2>&1; }

# Run a command, or print it under --dry-run.
run() {
  if [ "$DRY_RUN" = "1" ]; then
    printf '%s  would run:%s %s\n' "$C_DIM" "$C_RESET" "$*"
    return 0
  fi
  "$@"
}

# Same, but for a string that needs a shell (pipes, subshells).
run_sh() {
  if [ "$DRY_RUN" = "1" ]; then
    printf '%s  would run:%s %s\n' "$C_DIM" "$C_RESET" "$1"
    return 0
  fi
  bash -c "$1"
}

# ask "question" -> 0 for yes. Non-interactive stdin (curl | bash) counts as yes,
# because there is no terminal to answer from; --yes makes that explicit.
ask() {
  local prompt="$1" reply
  if [ "$ASSUME_YES" = "1" ] || [ "$DRY_RUN" = "1" ]; then
    return 0
  fi
  if [ ! -t 0 ]; then
    # stdin is the script itself (piped). Read the answer from the terminal if
    # one exists, otherwise proceed.
    if [ -e /dev/tty ]; then
      printf '%s [Y/n] ' "$prompt" > /dev/tty
      read -r reply < /dev/tty || reply=""
    else
      return 0
    fi
  else
    printf '%s [Y/n] ' "$prompt"
    read -r reply || reply=""
  fi
  case "$reply" in
    [nN]|[nN][oO]) return 1 ;;
    *) return 0 ;;
  esac
}

usage() {
  cat <<USAGE
claude-code-installer — one command, working Claude Code CLI.
macOS / Linux / WSL / Git Bash.

  curl -fsSL $REPO_RAW/install.sh | bash

Flags (or env vars, for piped use):
  --preset jtl   CCI_PRESET=jtl    also write a starter ~/.claude config
  --minimal      CCI_MINIMAL=1     skip package manager + git/node/ripgrep
  --yes          CCI_YES=1         non-interactive, assume yes
  --dry-run      CCI_DRY_RUN=1     print every command, execute none
  --help         show this

This script does not reimplement the Claude Code download. It delegates to
Anthropic's official installer, which fetches a checksum-verified native
binary. Everything here is about the things around that: prerequisites,
PATH, and proving the result actually works.
USAGE
  exit 0
}

# ------------------------------------------------------------------ args ----

while [ $# -gt 0 ]; do
  case "$1" in
    --preset)   PRESET="${2:-}"; shift 2 ;;
    --preset=*) PRESET="${1#*=}"; shift ;;
    --minimal)  MINIMAL=1; shift ;;
    --yes|-y)   ASSUME_YES=1; shift ;;
    --dry-run)  DRY_RUN=1; shift ;;
    --help|-h)  usage ;;
    *) err "unknown option: $1"; say "Run with --help for usage."; exit 2 ;;
  esac
done

if [ -n "$PRESET" ] && [ "$PRESET" != "jtl" ]; then
  err "unknown preset: $PRESET (only 'jtl' exists)"
  exit 2
fi

# -------------------------------------------------------------- preflight ----

step "Claude Code installer"
[ "$DRY_RUN" = "1" ] && warn "dry run — nothing will be installed"

# Same reasoning as Anthropic's own installer: this puts everything under
# $HOME, and under sudo that is root's home, so `claude` would not exist in
# your own shell.
if [ "$(id -u)" -eq 0 ] && [ -n "${SUDO_USER:-}" ] && [ "$SUDO_USER" != "root" ]; then
  err "do not run this installer with sudo."
  say ""
  say "Claude Code installs into your home directory and does not need root."
  say "Under sudo it would land in root's home instead of yours."
  say "Re-run the same command without sudo."
  exit 1
fi

OS=""
case "$(uname -s)" in
  Darwin) OS="macos" ;;
  Linux)
    if grep -qi microsoft /proc/version 2>/dev/null; then OS="wsl"; else OS="linux"; fi ;;
  MINGW*|MSYS*|CYGWIN*)
    OS="gitbash" ;;
  *)
    err "unsupported system: $(uname -s)"
    say "This script covers macOS, Linux, WSL and Git Bash."
    say "On native Windows PowerShell use install.ps1 instead:"
    say "  irm $REPO_RAW/install.ps1 | iex"
    exit 1 ;;
esac
ARCH="$(uname -m)"
info "system: $OS ($ARCH)"

if [ "$OS" = "gitbash" ]; then
  warn "Git Bash detected. The native Windows installer is the better path:"
  say "    irm $REPO_RAW/install.ps1 | iex"
  say "  Continuing anyway — package-manager steps will be skipped."
  MINIMAL=1
fi

if ! have curl && ! have wget; then
  err "neither curl nor wget is available, and both are needed to download anything."
  say "Install curl first, then re-run this script."
  exit 1
fi

# ------------------------------------------------------- package manager ----

PKG=""          # brew | apt | dnf | pacman | zypper | ""
PKG_SUDO=""     # "sudo" where needed

detect_pkg() {
  if have brew; then PKG="brew"; return; fi
  if have apt-get; then PKG="apt"; return; fi
  if have dnf; then PKG="dnf"; return; fi
  if have pacman; then PKG="pacman"; return; fi
  if have zypper; then PKG="zypper"; return; fi
  PKG=""
}

# Put brew on PATH for THIS process after a fresh install. This is the step
# hand-written installers usually miss: brew installs fine, then every later
# `brew install` fails because the shell never learned where it went.
load_brew_env() {
  local brew_bin=""
  for candidate in /opt/homebrew/bin/brew /usr/local/bin/brew "$HOME/.linuxbrew/bin/brew" /home/linuxbrew/.linuxbrew/bin/brew; do
    [ -x "$candidate" ] && { brew_bin="$candidate"; break; }
  done
  [ -z "$brew_bin" ] && return 1
  eval "$("$brew_bin" shellenv)"
  return 0
}

install_homebrew() {
  if have brew; then
    ALREADY+=("Homebrew ($(brew --version 2>/dev/null | head -1))")
    ok "Homebrew already installed"
    return 0
  fi
  if ! ask "Homebrew is not installed. Install it now?"; then
    SKIPPED+=("Homebrew (declined)")
    warn "skipping Homebrew — git/node/ripgrep will be skipped too"
    return 1
  fi
  info "installing Homebrew (this asks for your password and takes a few minutes)"
  run_sh "NONINTERACTIVE=1 /bin/bash -c \"\$(curl -fsSL $HOMEBREW_INSTALLER)\""
  if [ "$DRY_RUN" != "1" ]; then
    load_brew_env || { err "Homebrew installed but 'brew' is not on PATH"; return 1; }
    add_line_to_shell_rc "eval \"\$($(command -v brew) shellenv)\"" "brew shellenv"
  fi
  INSTALLED+=("Homebrew")
  ok "Homebrew installed"
}

pkg_install() {
  local pkg="$1"
  case "$PKG" in
    brew)   run brew install "$pkg" ;;
    apt)    run $PKG_SUDO apt-get install -y "$pkg" ;;
    dnf)    run $PKG_SUDO dnf install -y "$pkg" ;;
    pacman) run $PKG_SUDO pacman -S --noconfirm "$pkg" ;;
    zypper) run $PKG_SUDO zypper install -y "$pkg" ;;
    *)      return 1 ;;
  esac
}

# Package names differ per manager for exactly one of our three tools.
pkg_name_for() {
  case "$1:$PKG" in
    ripgrep:*)  echo "ripgrep" ;;
    node:brew)  echo "node" ;;
    node:apt)   echo "nodejs" ;;
    node:dnf)   echo "nodejs" ;;
    node:pacman) echo "nodejs" ;;
    node:zypper) echo "nodejs" ;;
    git:*)      echo "git" ;;
    *)          echo "$1" ;;
  esac
}

setup_pkg_manager() {
  if [ "$MINIMAL" = "1" ]; then
    SKIPPED+=("package manager + prerequisites (--minimal)")
    info "minimal mode — skipping package manager and prerequisites"
    return 1
  fi

  if [ "$OS" = "macos" ]; then
    # Command Line Tools carry git and the compilers Homebrew needs.
    if ! xcode-select -p >/dev/null 2>&1; then
      warn "Xcode Command Line Tools are missing."
      if ask "Trigger the Command Line Tools installer now?"; then
        run xcode-select --install || true
        say ""
        warn "A macOS dialog opened. Finish that install, then re-run this script."
        say "  curl -fsSL $REPO_RAW/install.sh | bash"
        exit 0
      fi
      SKIPPED+=("Xcode Command Line Tools (declined)")
    else
      ALREADY+=("Xcode Command Line Tools")
    fi
    install_homebrew || return 1
    PKG="brew"
    return 0
  fi

  detect_pkg
  if [ -z "$PKG" ]; then
    warn "no supported package manager found (apt/dnf/pacman/zypper/brew)"
    SKIPPED+=("prerequisites (no package manager)")
    return 1
  fi
  info "package manager: $PKG"

  if [ "$PKG" != "brew" ] && [ "$(id -u)" -ne 0 ]; then
    if ! have sudo; then
      warn "sudo not available — cannot install system packages"
      SKIPPED+=("prerequisites (no sudo)")
      return 1
    fi
    if ! ask "Install git/node/ripgrep with $PKG (needs sudo)?"; then
      SKIPPED+=("prerequisites (declined)")
      return 1
    fi
    PKG_SUDO="sudo"
  fi

  case "$PKG" in
    apt)    run $PKG_SUDO apt-get update ;;
    zypper) run $PKG_SUDO zypper refresh ;;
  esac
  return 0
}

node_major() {
  local v
  v="$(node --version 2>/dev/null || true)"   # v22.11.0
  v="${v#v}"; v="${v%%.*}"
  [ -n "$v" ] && printf '%s' "$v" || printf '0'
}

install_prereqs() {
  step "Prerequisites"

  for tool in git node rg; do
    local label="$tool" pkg
    [ "$tool" = "rg" ] && label="ripgrep"

    if have "$tool"; then
      # node has a version floor; the other two just need to exist.
      if [ "$tool" = "node" ] && [ "$(node_major)" -lt "$NODE_MIN_MAJOR" ]; then
        warn "node $(node --version) is older than v$NODE_MIN_MAJOR — upgrading"
      else
        case "$tool" in
          git)  ALREADY+=("git $(git --version 2>/dev/null | awk '{print $3}')") ;;
          node) ALREADY+=("node $(node --version 2>/dev/null)") ;;
          rg)   ALREADY+=("ripgrep $(rg --version 2>/dev/null | head -1 | awk '{print $2}')") ;;
        esac
        ok "$label already installed"
        continue
      fi
    fi

    [ "$tool" = "rg" ] && tool="ripgrep"
    pkg="$(pkg_name_for "$tool")"
    info "installing $label"
    if pkg_install "$pkg"; then
      INSTALLED+=("$label")
      ok "$label installed"
    else
      SKIPPED+=("$label (install failed)")
      warn "could not install $label — continuing"
    fi
  done
}

# ------------------------------------------------------------- PATH doctor ---

shell_rc_files() {
  local shell_name
  shell_name="$(basename "${SHELL:-/bin/bash}")"
  case "$shell_name" in
    zsh)  printf '%s\n' "${ZDOTDIR:-$HOME}/.zshrc" ;;
    fish) printf '%s\n' "$HOME/.config/fish/config.fish" ;;
    bash)
      printf '%s\n' "$HOME/.bashrc"
      [ "$OS" = "macos" ] && printf '%s\n' "$HOME/.bash_profile"
      ;;
    *)    printf '%s\n' "$HOME/.profile" ;;
  esac
}

# Append a line to the shell rc exactly once. Re-running this script must never
# grow the rc file — that is the idempotence test.
add_line_to_shell_rc() {
  local line="$1" label="$2" rc
  while IFS= read -r rc; do
    [ -z "$rc" ] && continue
    if [ -f "$rc" ] && grep -Fqs -- "$line" "$rc"; then
      ok "$label already in $(basename "$rc")"
      continue
    fi
    if [ "$DRY_RUN" = "1" ]; then
      printf '%s  would append to %s:%s %s\n' "$C_DIM" "$rc" "$C_RESET" "$line"
      continue
    fi
    mkdir -p "$(dirname "$rc")"
    {
      printf '\n# added by claude-code-installer\n'
      printf '%s\n' "$line"
    } >> "$rc"
    ok "$label added to $(basename "$rc")"
  done <<< "$(shell_rc_files)"
}

fix_path() {
  step "PATH"
  local bin_dir="$HOME/.local/bin"
  local shell_name; shell_name="$(basename "${SHELL:-/bin/bash}")"

  if [ ! -d "$bin_dir" ] && [ "$DRY_RUN" != "1" ]; then
    warn "$bin_dir does not exist — the installer may have used a different location"
  fi

  if [ "$shell_name" = "fish" ]; then
    add_line_to_shell_rc "fish_add_path $bin_dir" "PATH entry"
  else
    add_line_to_shell_rc "export PATH=\"\$HOME/.local/bin:\$PATH\"" "PATH entry"
  fi

  case ":$PATH:" in
    *":$bin_dir:"*) : ;;
    *) export PATH="$bin_dir:$PATH" ;;   # so verification works in THIS session
  esac
}

# ---------------------------------------------------------------- install ----

install_claude() {
  step "Claude Code"
  local was_present=0
  if have claude; then
    was_present=1
    ALREADY+=("Claude Code $(claude --version 2>/dev/null | head -1 | awk '{print $1}')")
    ok "Claude Code already installed — running its updater anyway"
  fi
  info "running the official Anthropic installer"
  run_sh "curl -fsSL $OFFICIAL_INSTALLER | bash"
  [ "$was_present" -eq 0 ] && INSTALLED+=("Claude Code")
  return 0
}

# ----------------------------------------------------------------- preset ----

fetch_to() {
  local url="$1" dest="$2"
  if [ "$DRY_RUN" = "1" ]; then
    printf '%s  would download:%s %s -> %s\n' "$C_DIM" "$C_RESET" "$url" "$dest"
    return 0
  fi
  if have curl; then
    curl -fsSL "$url" -o "$dest"
  else
    wget -qO "$dest" "$url"
  fi
}

# Never overwrite an existing config. A person re-running this on a machine they
# already configured must not lose their settings.
install_one_preset_file() {
  local url="$1" dest="$2"
  if [ -e "$dest" ]; then
    fetch_to "$url" "$dest.new"
    warn "$(basename "$dest") already exists — wrote $(basename "$dest").new beside it"
    SKIPPED+=("$(basename "$dest") (existing file kept)")
  else
    fetch_to "$url" "$dest"
    INSTALLED+=("preset $(basename "$dest")")
    ok "wrote $dest"
  fi
}

install_preset() {
  [ -z "$PRESET" ] && return 0
  step "Preset: $PRESET"
  run mkdir -p "$HOME/.claude"
  install_one_preset_file "$REPO_RAW/preset/settings.json" "$HOME/.claude/settings.json"
  install_one_preset_file "$REPO_RAW/preset/CLAUDE.md" "$HOME/.claude/CLAUDE.md"
}

# ----------------------------------------------------------------- verify ----

verify() {
  step "Verify"
  if [ "$DRY_RUN" = "1" ]; then
    printf '%s  would run:%s claude --version && claude doctor\n' "$C_DIM" "$C_RESET"
    return 0
  fi

  if ! have claude; then
    err "'claude' is not on PATH after installation."
    say ""
    say "Most likely your shell has not reloaded. Try:"
    say "  export PATH=\"\$HOME/.local/bin:\$PATH\" && claude --version"
    say "If that works, open a new terminal and it will stick."
    return 1
  fi

  local version
  if ! version="$(claude --version 2>&1)"; then
    err "'claude --version' failed:"
    say "$version"
    return 1
  fi
  ok "claude --version -> $version"

  say ""
  info "claude doctor"
  claude doctor 2>&1 | sed 's/^/    /' || warn "claude doctor reported problems (see above)"
  return 0
}

summary() {
  local rc="$1"
  step "Summary"
  if [ ${#INSTALLED[@]} -gt 0 ]; then
    say "  Installed:"
    for i in "${INSTALLED[@]}"; do say "    + $i"; done
  fi
  if [ ${#ALREADY[@]} -gt 0 ]; then
    say "  Already present:"
    for i in "${ALREADY[@]}"; do say "    = $i"; done
  fi
  if [ ${#SKIPPED[@]} -gt 0 ]; then
    say "  Skipped:"
    for i in "${SKIPPED[@]}"; do say "    - $i"; done
  fi

  say ""
  if [ "$DRY_RUN" = "1" ]; then
    printf '%sDry run complete — nothing was installed.%s\n' "$C_YELLOW$C_BOLD" "$C_RESET"
    say "Re-run without --dry-run to actually install."
  elif [ "$rc" -eq 0 ]; then
    printf '%sClaude Code is installed and working.%s\n' "$C_GREEN$C_BOLD" "$C_RESET"
    say ""
    say "Next:"
    say "  1. Open a new terminal (so PATH is loaded)."
    say "  2. Run:  claude"
    say "  3. Sign in when prompted with /login"
  else
    printf '%sInstall did not verify.%s See the error above.\n' "$C_RED$C_BOLD" "$C_RESET"
  fi
}

# ------------------------------------------------------------------- main ----

main() {
  setup_pkg_manager && install_prereqs || true
  install_claude
  fix_path
  install_preset

  local rc=0
  verify || rc=1
  summary "$rc"
  return "$rc"
}

main
