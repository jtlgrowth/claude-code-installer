#!/usr/bin/env bash
# Workshop doctor for Mac/Linux: finds and fixes the path problems that stop Claude Code,
# Codex or a /setup alias from starting. Paste in Terminal:
#   curl -fsSL https://raw.githubusercontent.com/jtlgrowth/claude-code-installer/main/w/doctor.sh | bash
# Safe to run any number of times. It only ever adds ~/.local/bin to your shell's PATH
# (one marked line in ~/.zshrc or ~/.bashrc) and deletes nothing.

bin="$HOME/.local/bin"
fixed=0; needs=0
good()  { printf '  \033[32mok\033[0m    %s\n' "$*"; }
fixed() { printf '  \033[36mfixed\033[0m %s\n' "$*"; fixed=$((fixed + 1)); }
need()  { printf '  \033[33m!!\033[0m    %s\n' "$*"; needs=$((needs + 1)); }

printf '\n\033[1mJTL workshop doctor\033[0m\n'
good "this terminal is in $(pwd)"

# ~/.local/bin on PATH, for every new terminal: claude and every /setup alias live there.
case "$(basename "${SHELL:-zsh}")" in bash) rc="$HOME/.bashrc" ;; *) rc="$HOME/.zshrc" ;; esac
if grep -qs 'jtl-doctor: local bin' "$rc" || grep -qs 'claude-code-installer' "$rc" || grep -qs '\.local/bin' "$rc"; then
  good "$bin is on PATH for new terminals ($rc)"
else
  printf '\nexport PATH="$HOME/.local/bin:$PATH"  # jtl-doctor: local bin\n' >> "$rc"
  fixed "added $bin to PATH in $rc"
fi
case ":$PATH:" in *":$bin:"*) ;; *) PATH="$bin:$PATH" ;; esac
npm_bin="$(npm prefix -g 2>/dev/null)/bin"
case ":$PATH:" in *":$npm_bin:"*) ;; *) [ -d "$npm_bin" ] && PATH="$PATH:$npm_bin" ;; esac

have_claude=0; have_codex=0
if command -v claude >/dev/null 2>&1; then have_claude=1; good "claude found at $(command -v claude)"; fi
if command -v codex >/dev/null 2>&1; then have_codex=1; good "codex found at $(command -v codex)"; fi
[ $have_claude = 0 ] && [ $have_codex = 0 ] && need "neither Claude Code nor Codex is installed. Paste your workshop install line again"

if command -v node >/dev/null 2>&1; then
  v="$(node --version)"; major="${v#v}"; major="${major%%.*}"
  if [ "${major:-0}" -ge 20 ] 2>/dev/null; then good "node $v"; else need "node $v is older than v20: brew install node"; fi
else
  need "node is not installed: brew install node   (no Homebrew? https://nodejs.org)"
fi

for pair in "Claude Code:$HOME/.claude/skills" "Codex:${CODEX_HOME:-$HOME/.codex}/skills"; do
  label="${pair%%:*}"; dir="${pair#*:}"; n=0
  for s in setup hire; do [ -f "$dir/$s/SKILL.md" ] && n=$((n + 1)); done
  [ $n = 2 ] && good "$label skills: setup and hire"
  [ $n = 1 ] && need "$label has only one of setup and hire. Paste your workshop install line again"
done

for f in "$bin"/*; do
  if [ ! -f "$f" ] || ! grep -qs 'written by /setup' "$f"; then continue; fi
  target=claude; grep -qs 'exec codex' "$f" && target=codex
  if command -v "$target" >/dev/null 2>&1; then good "alias '$(basename "$f")' opens $target (type it in a new terminal)"
  else need "alias '$(basename "$f")' opens $target, which is not installed here. Paste your workshop install line again"; fi
done

printf '\n'
if [ $needs = 0 ] && [ $fixed = 0 ]; then printf '\033[32mAll good.\033[0m Open Claude Code (or Codex) in your desk folder.\n'
elif [ $needs = 0 ]; then printf '\033[32mFixed %s thing(s).\033[0m Open a NEW terminal, then type claude (or your alias).\n' "$fixed"
else printf '\033[33m%s thing(s) need you\033[0m (the !! lines above). Screenshot this window if you are stuck.\n' "$needs"; fi
printf 'Folder names with spaces need quotes:  cd "My Folder"\n'
