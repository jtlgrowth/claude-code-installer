# claude-code-installer

One command. A working [Claude Code](https://claude.com/claude-code) CLI. macOS, Windows, Linux, WSL.

It installs the things you actually need around Claude Code — a package manager, `git`, Node LTS,
`ripgrep` — then hands the CLI install itself to Anthropic's official installer, wires your `PATH`,
and **verifies the result** instead of assuming it. If `claude --version` does not answer at the
end, the script fails loudly rather than printing a green "done".

## Install

**macOS / Linux / WSL / Git Bash**

```bash
curl -fsSL https://raw.githubusercontent.com/whereisdotva-gif/claude-code-installer/main/install.sh | bash
```

**Windows (PowerShell)**

```powershell
irm https://raw.githubusercontent.com/whereisdotva-gif/claude-code-installer/main/install.ps1 | iex
```

Then open a new terminal and run `claude`. Sign in with `/login`.

### Read it before you pipe it

Piping a script from the internet into your shell means running code you have not read. That is
true of this script and of every other install one-liner. If you would rather look first:

```bash
curl -fsSL https://raw.githubusercontent.com/whereisdotva-gif/claude-code-installer/main/install.sh -o install.sh
less install.sh          # read it
bash install.sh --dry-run  # see every command it would run, without running any
bash install.sh
```

```powershell
irm https://raw.githubusercontent.com/whereisdotva-gif/claude-code-installer/main/install.ps1 -OutFile install.ps1
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

## Options

Because a piped script has no command-line arguments, every flag has an environment variable twin.

| Flag | Environment variable | Effect |
| --- | --- | --- |
| `--preset jtl` | `CCI_PRESET=jtl` | also write a starter `~/.claude` config (never overwrites an existing one) |
| `--minimal` | `CCI_MINIMAL=1` | skip the package manager and `git`/`node`/`ripgrep`; install Claude Code only |
| `--yes` | `CCI_YES=1` | non-interactive, answer yes to everything |
| `--dry-run` | `CCI_DRY_RUN=1` | print every command, execute none |
| `--help` | — | usage |

Piped, with options:

```bash
curl -fsSL https://raw.githubusercontent.com/whereisdotva-gif/claude-code-installer/main/install.sh | CCI_PRESET=jtl bash
```

```powershell
$env:CCI_PRESET = 'jtl'; irm https://raw.githubusercontent.com/whereisdotva-gif/claude-code-installer/main/install.ps1 | iex
```

## The preset

`--preset jtl` drops two starter files into `~/.claude`:

- `settings.json` — sane defaults, no keys, no telemetry changes
- `CLAUDE.md` — a short template for writing project instructions that Claude Code actually follows

It contains no credentials and no private configuration. If either file already exists, the preset
is written beside it as `.new` and yours is left untouched. See [`preset/README.md`](preset/README.md).

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

| Platform | Status |
| --- | --- |
| macOS (Apple Silicon) | dry-run + idempotence verified locally |
| Ubuntu 24.04 (Docker) | full install verified |
| Windows 10 / 11 | **not yet tested on real hardware** — CI parses the script, no end-to-end run |
| WSL | covered by the Linux path, not separately tested |

If you run it on Windows, an issue with the output either way is genuinely useful.

## Uninstall

```bash
rm -rf ~/.claude ~/.local/bin/claude
```

Then remove the `# added by claude-code-installer` block from your shell rc. Homebrew, git, node
and ripgrep are left alone — they are normal tools, not part of Claude Code.

## License

MIT. This is an unofficial convenience wrapper. Claude Code is Anthropic's, and its installer is
called directly rather than mirrored, so you always get the official, checksum-verified binary.
