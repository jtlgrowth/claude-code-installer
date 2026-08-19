#!/usr/bin/env bash
#
# claude-code-installer — one command, working Claude Code CLI.
# macOS / Linux / WSL / Git Bash.
#
#   curl -fsSL https://raw.githubusercontent.com/jtlgrowth/claude-code-installer/main/install.sh | bash
#
# Flags (or env vars, for piped use):
#   --preset jtl   CCI_PRESET=jtl     also write a starter ~/.claude config
#   --skills hire  CCI_SKILLS=hire   also install agent skills (comma-separated)
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
SKILLS="${CCI_SKILLS:-}"
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

# ------------------------------------------------------------------ skills ----

# The skill allowlist. A name maps to a tarball, the directory inside it, and how
# many leading path components to strip.
#
# Deliberately a case statement and not a JSON manifest: this repo has no jq
# dependency anywhere and should not grow one for a table this size. Deliberately
# an allowlist and not a --skills <url> flag: that would turn a curl-to-bash
# installer into an arbitrary-code downloader.
skill_source() {
  case "$1" in
    hire)
      echo "https://codeload.github.com/jtlgrowth/hire/tar.gz/refs/heads/main"
      echo "hire-main/skills/hire"
      echo "2"
      ;;
    *) return 1 ;;
  esac
}

known_skills() { printf 'known skills: hire'; }

usage() {
  cat <<USAGE
claude-code-installer — one command, working Claude Code CLI.
macOS / Linux / WSL / Git Bash.

  curl -fsSL $REPO_RAW/install.sh | bash

Flags (or env vars, for piped use):
  --preset jtl   CCI_PRESET=jtl    also write a starter ~/.claude config
  --skills hire  CCI_SKILLS=hire   also install agent skills (comma-separated)
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
    --preset)
      if [ $# -lt 2 ] || [ -z "$2" ]; then
        err "--preset needs a value (only 'jtl' exists)"
        exit 2
      fi
      PRESET="$2"; shift 2 ;;
    --preset=*)
      PRESET="${1#*=}"
      if [ -z "$PRESET" ]; then
        err "--preset needs a value (only 'jtl' exists)"
        exit 2
      fi
      shift ;;
    --skills)
      if [ $# -lt 2 ] || [ -z "$2" ]; then
        err "--skills needs a value ($(known_skills))"
        exit 2
      fi
      SKILLS="$2"; shift 2 ;;
    --skills=*)
      SKILLS="${1#*=}"
      if [ -z "$SKILLS" ]; then
        err "--skills needs a value ($(known_skills))"
        exit 2
      fi
      shift ;;
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

# Reject an unknown skill before anything is installed, not halfway through.
if [ -n "$SKILLS" ]; then
  for _s in $(printf '%s' "$SKILLS" | tr ',' ' '); do
    if ! skill_source "$_s" >/dev/null 2>&1; then
      err "unknown skill: $_s ($(known_skills))"
      exit 2
    fi
  done
  unset _s
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
  run mkdir -p "$HOME/.claude/templates"

  # settings.json belongs at ~/.claude — that IS the global settings file.
  install_one_preset_file "$REPO_RAW/preset/settings.json" "$HOME/.claude/settings.json"

  # The CLAUDE.md template does NOT. ~/.claude/CLAUDE.md is global instructions
  # applied to every project, and a project-shaped template installed there
  # would silently become doctrine for everything you open. Park it as a
  # template and let the user copy it where it belongs.
  install_one_preset_file "$REPO_RAW/preset/project-CLAUDE.md" \
    "$HOME/.claude/templates/project-CLAUDE.md"
  say "     copy it into a project root as CLAUDE.md when you want it:"
  say "       cp ~/.claude/templates/project-CLAUDE.md ./CLAUDE.md"
}

# ------------------------------------------------------------------ skills ----

# Skills live in ~/.claude/skills/<name>. That path is what makes /<name> resolve
# inside Claude Code; anywhere else and the skill is just files on disk.
install_one_skill() {
  local name="$1" url member strip dest tmp
  { read -r url; read -r member; read -r strip; } < <(skill_source "$name")
  dest="$HOME/.claude/skills/$name"

  # Already there: leave it alone and say so. Re-running this installer is
  # something people do (the first run scrolls past), and it must never
  # overwrite a skill someone has been editing.
  if [ -e "$dest" ]; then
    warn "skill $name already installed at $dest — left alone"
    SKIPPED+=("skill $name (already present)")
    return 0
  fi

  if [ "$DRY_RUN" = "1" ]; then
    printf '%s  would download:%s %s\n' "$C_DIM" "$C_RESET" "$url"
    printf '%s  would extract:%s  %s -> %s\n' "$C_DIM" "$C_RESET" "$member" "$dest"
    return 0
  fi

  run mkdir -p "$HOME/.claude/skills"
  tmp="$(mktemp "${TMPDIR:-/tmp}/cci-skill-XXXXXX.tgz")"

  # Download to a file, then extract. Piping curl straight into tar hides
  # curl's exit code behind tar's, so a 404 looks like a corrupt archive.
  if ! fetch_to "$url" "$tmp"; then
    rm -f "$tmp"
    warn "could not download skill $name"
    SKIPPED+=("skill $name (download failed)")
    return 0
  fi

  if ! tar -xzf "$tmp" -C "$HOME/.claude/skills" --strip-components="$strip" "$member" 2>/dev/null; then
    rm -f "$tmp"
    warn "could not extract skill $name"
    SKIPPED+=("skill $name (extract failed)")
    return 0
  fi
  rm -f "$tmp"

  # Prove it, rather than trusting that tar exited 0 over the right paths.
  if [ ! -f "$dest/SKILL.md" ]; then
    warn "skill $name extracted but has no SKILL.md — removing"
    rm -rf "$dest"
    SKIPPED+=("skill $name (no SKILL.md)")
    return 0
  fi

  INSTALLED+=("skill $name")
  ok "installed $dest"
}

install_skills() {
  [ -z "$SKILLS" ] && return 0
  step "Skills"

  if ! have tar; then
    warn "tar not found — cannot install skills"
    SKIPPED+=("skills (no tar)")
    return 0
  fi

  for name in $(printf '%s' "$SKILLS" | tr ',' ' '); do
    install_one_skill "$name"
  done

  # A skill is Markdown plus scripts, and the scripts need a runtime. --minimal
  # and Git Bash both skip the Node install, so say it plainly here instead of
  # leaving someone with a skill that cannot run.
  if ! have node; then
    warn "node is not installed — skills that ship scripts will not run"
    say "     install Node 20+ and re-open your terminal"
  fi
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
    if [ "$DRY_RUN" = "1" ]; then say "  Would install:"; else say "  Installed:"; fi
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
  # A failed or declined package-manager step is not fatal: Claude Code itself
  # installs without one, so skip the prerequisites and carry on.
  if setup_pkg_manager; then
    install_prereqs
  fi
  install_claude
  fix_path
  install_preset
  install_skills

  local rc=0
  verify || rc=1
  summary "$rc"
  return "$rc"
}

main
