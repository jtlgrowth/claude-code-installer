<div align="center">

# claude-code-installer

**One command. A working [Claude Code](https://claude.com/claude-code) CLI.**
macOS · Windows · Linux · WSL

[![ci](https://github.com/jtlgrowth/claude-code-installer/actions/workflows/ci.yml/badge.svg)](https://github.com/jtlgrowth/claude-code-installer/actions/workflows/ci.yml)
[![license: MIT](https://img.shields.io/badge/license-MIT-black.svg)](LICENSE)
[![platform](https://img.shields.io/badge/platform-macOS%20%7C%20Windows%20%7C%20Linux%20%7C%20WSL-black.svg)](#what-it-does)
[![shell](https://img.shields.io/badge/shell-bash%20%7C%20powershell-black.svg)](#how-it-works)

<img src="demo/demo.gif" alt="A dry run of the installer: it detects Homebrew, git, node and ripgrep, prints every command it would run, and changes nothing." width="820">

<sub>Recorded from a real `--dry-run`, unedited. Regenerate it with `vhs demo/demo.tape`.</sub>

</div>

---

It installs the things you actually need around Claude Code — a package manager, `git`, Node LTS,
`ripgrep` — then hands the CLI install itself to Anthropic's official installer, wires your `PATH`,
and **verifies the result** instead of assuming it. If `claude --version` does not answer at the
end, the script fails loudly rather than printing a green "done".

## Install

**macOS / Linux / WSL / Git Bash**

```bash
curl -fsSL https://raw.githubusercontent.com/jtlgrowth/claude-code-installer/main/install.sh | bash
```

**Windows (PowerShell)**

```powershell
irm https://raw.githubusercontent.com/jtlgrowth/claude-code-installer/main/install.ps1 | iex
```

Then open a new terminal and run `claude`. Sign in with `/login`.

### Read it before you pipe it

Piping a script from the internet into your shell means running code you have not read. That is
true of this script and of every other install one-liner. If you would rather look first:

```bash
curl -fsSL https://raw.githubusercontent.com/jtlgrowth/claude-code-installer/main/install.sh -o install.sh
less install.sh          # read it
bash install.sh --dry-run  # see every command it would run, without running any
bash install.sh
```

```powershell
irm https://raw.githubusercontent.com/jtlgrowth/claude-code-installer/main/install.ps1 -OutFile install.ps1
notepad install.ps1
.\install.ps1 -DryRun
.\install.ps1
```

## What it does

| Step | macOS | Windows | Linux / WSL |
| --- | --- | --- | --- |
| Package manager | Homebrew (installed if missing) | winget (must already exist) | apt / dnf / pacman / zypper |
| Build tools | Xcode Command Line Tools | — | — |
| `git` | via Homebrew | `Git.Git` | via system package manager |
| Node LTS (for MCP servers) | via Homebrew | `OpenJS.NodeJS.LTS` | via system package manager |
| `ripgrep` (fast search) | via Homebrew | `BurntSushi.ripgrep.MSVC` | via system package manager |
| Claude Code | `curl -fsSL https://claude.ai/install.sh \| bash` | `irm https://claude.ai/install.ps1 \| iex` | same as macOS |
| `PATH` | appended to your shell rc, once | refreshed from the registry | appended to your shell rc, once |
| Verify | `claude --version` + `claude doctor` | same | same |

Anything already installed is detected and skipped, so re-running is cheap and safe. Re-running
also never adds a second `PATH` line to your shell config.

**Claude Code does not need Node or Homebrew to run.** Its installer downloads a checksum-verified
native binary. Node is here because `npx`-based MCP servers need it, and `git` and `ripgrep`
because you will want them the moment you point Claude Code at a repo. If you want none of that,
use `--minimal`.

## How it works

```
                 ┌─────────────────────────────────────────┐
  one command    │  detect OS, arch, shell, package manager │
       │         └──────────────────┬──────────────────────┘
       ▼                            ▼
  install.sh          ┌──────────────────────────────┐
  install.ps1         │  install what is missing:    │   already there? skipped
                      │  brew/winget, git, node, rg  │
                      └──────────────┬───────────────┘
                                     ▼
                      ┌──────────────────────────────┐
                      │  Anthropic's own installer   │   checksum-verified native binary
                      │  claude.ai/install.sh|.ps1   │   (not mirrored, not reimplemented)
                      └──────────────┬───────────────┘
                                     ▼
                      ┌──────────────────────────────┐
                      │  PATH into your shell rc     │   exactly once, re-run safe
                      └──────────────┬───────────────┘
                                     ▼
                      ┌──────────────────────────────┐
                      │  claude --version + doctor   │   non-zero exit if this fails
                      └──────────────────────────────┘
```

Three properties this buys you, which a hand-typed sequence of commands does not:

1. **Idempotent.** Run it twice and the second run installs nothing and adds no second `PATH`
   line. The CI suite asserts that by counting the marker in the shell rc before and after.
2. **Inspectable.** `--dry-run` prints every command without executing any of them. That is the
   demo above.
3. **Honest.** The exit code reflects whether `claude --version` actually answered.

## Options

Because a piped script has no command-line arguments, every flag has an environment variable twin.

| Flag | Environment variable | Effect |
| --- | --- | --- |
| `--preset jtl` | `CCI_PRESET=jtl` | also write a starter `~/.claude` config (never overwrites an existing one) |
| `--skills hire` | `CCI_SKILLS=hire` | also install agent skills into `~/.claude/skills/` (comma-separated; never overwrites an existing skill) |
| `--minimal` | `CCI_MINIMAL=1` | skip the package manager and `git`/`node`/`ripgrep`; install Claude Code only |
| `--yes` | `CCI_YES=1` | non-interactive, answer yes to everything |
| `--dry-run` | `CCI_DRY_RUN=1` | print every command, execute none |
| `--help` | — | usage |

Piped, with options:

```bash
curl -fsSL https://raw.githubusercontent.com/jtlgrowth/claude-code-installer/main/install.sh | CCI_PRESET=jtl bash
```

```powershell
$env:CCI_PRESET = 'jtl'; irm https://raw.githubusercontent.com/jtlgrowth/claude-code-installer/main/install.ps1 | iex
```

## The preset

`--preset jtl` drops two starter files:

- `~/.claude/settings.json` — sane defaults, no keys, no telemetry changes
- `~/.claude/templates/project-CLAUDE.md` — a short template for writing project instructions

The template deliberately lands in `templates/` rather than as `~/.claude/CLAUDE.md`. That path is
your *global* instruction file, read in every project you open; a project-shaped template installed
there becomes doctrine everywhere by accident. Copy it into a project root when you want it.

It contains no credentials and no private configuration. If either file already exists, the preset
is written beside it as `.new` and yours is left untouched. See [`preset/README.md`](preset/README.md).

## Skills

`--skills hire` installs [`hire`](https://github.com/jtlgrowth/hire) into
`~/.claude/skills/hire`, which is where Claude Code looks for it — after this, `/hire`
works in any session.

```bash
curl -fsSL https://raw.githubusercontent.com/jtlgrowth/claude-code-installer/main/install.sh | CCI_SKILLS=hire bash
```

```powershell
$env:CCI_SKILLS = 'hire'; irm https://raw.githubusercontent.com/jtlgrowth/claude-code-installer/main/install.ps1 | iex
```

Known skills: `hire`. The list is an allowlist in the script rather than a
`--skills <url>` flag, because a `curl | bash` installer that downloads arbitrary URLs is
a different and much worse thing than one that installs a named, reviewable list.

A skill that is already installed is left alone and reported as such — re-running the line
is safe. Skills ship scripts, so they need Node, which this installer already sets up
unless you pass `--minimal`.

## Troubleshooting

**`claude: command not found` after install.** Your shell has not reloaded. Open a new terminal, or:

```bash
export PATH="$HOME/.local/bin:$PATH"
```

**Windows: `winget` is not recognised.** Install *App Installer* from the
[Microsoft Store](https://apps.microsoft.com/detail/9nblggh4nns1), then re-run. Claude Code itself
still installs without it — only the prerequisites are skipped.

**Windows: a script "is not digitally signed".** For the current window only:

```powershell
Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass
```

**macOS: Xcode Command Line Tools dialog.** The script triggers it, but macOS runs that install in a
GUI window it cannot wait on. Let it finish, then re-run the one-liner.

**Homebrew installed but `brew` still not found.** Re-run the script — it evaluates `brew shellenv`
for your architecture (`/opt/homebrew` on Apple Silicon, `/usr/local` on Intel) and writes it to
your shell rc.

**Do not use `sudo`.** Claude Code installs into your home directory. Under `sudo` it lands in
root's home and the `claude` command will not exist in your own shell. Both this script and
Anthropic's refuse to run that way.

## Tested on

| Platform | What was actually run |
| --- | --- |
| macOS 15 (Apple Silicon) | full smoke suite, `--dry-run` on every flag combination, and a real end-to-end install into a scratch `$HOME` — `claude --version` verified |
| Ubuntu 24.04 | real install in a container, plus a re-run asserting the shell rc does not grow — **runs in CI on every push**, not on the author's machine |
| Windows Server 2022 (CI) | parse, `PSScriptAnalyzer`, dry runs (no preset, `-Preset jtl`, `CCI_PRESET=jtl`, `-Skills hire`, `CCI_SKILLS=hire`) each asserted to exit 0, bad preset and bad skill each asserted to exit 2, **and a real skill install** — `hire` downloaded, extracted, its own test suite run, then a re-run asserted to leave it untouched. **Claude Code itself has still not been installed end to end on a real Windows desktop.** |
| WSL | covered by the Linux path; not separately exercised |

Windows is the honest gap. CI now installs a skill for real on a Windows runner and runs that
skill's tests there, so the `--skills` path is genuinely exercised — but the Claude Code install
itself still delegates to Anthropic's installer, and nobody has yet watched that run end to end
on a real Windows desktop. If you do, the output either way is genuinely useful — open an issue.

## Uninstall

Remove Claude Code itself:

```bash
rm -rf ~/.local/bin/claude ~/.local/share/claude
```

Remove the preset files, if you installed them:

```bash
rm -f ~/.claude/settings.json ~/.claude/templates/project-CLAUDE.md
```

Then delete the `# added by claude-code-installer` block from your shell rc.

Do **not** `rm -rf ~/.claude` — that directory also holds your login, your session history and
any configuration you added yourself, none of which came from this installer. Homebrew, git,
node and ripgrep are left alone too; they are normal tools, not part of Claude Code.

## License

MIT. This is an unofficial convenience wrapper. Claude Code is Anthropic's, and its installer is
called directly rather than mirrored, so you always get the official, checksum-verified binary.
