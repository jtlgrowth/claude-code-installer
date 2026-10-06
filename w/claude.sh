#!/usr/bin/env bash
# Workshop line for Mac/Linux Claude Code users: Claude Code plus the hire and setup skills.
#   curl -fsSL https://raw.githubusercontent.com/jtlgrowth/claude-code-installer/main/w/claude.sh | bash
# No underscore and no variable in the line: copied out of a PDF, Apple's PDFKit splits a
# line at an underscore (tested 2026-10-07 on CCI_SKILLS), and a split line fails in zsh.
# Every option is set here, so leftovers from an earlier try cannot steer this run.
export CCI_SKILLS=hire,setup CCI_NO_CLAUDE='' CCI_CODEX='' CCI_YES='' CCI_DRY_RUN='' CCI_MINIMAL='' CCI_PRESET=''
base="${CCI_BASE:-https://raw.githubusercontent.com/jtlgrowth/claude-code-installer/main}"
curl -fsSL "$base/install.sh" | bash
