# The `jtl` preset

Two starter files for a fresh `~/.claude`, installed only when you pass `--preset jtl`
(or `CCI_PRESET=jtl`).

## What it contains

**`settings.json`** — a conservative default:

- `includeCoAuthoredBy: false` — no `Co-Authored-By` trailer in your commits
- `cleanupPeriodDays: 30` — old transcripts do not accumulate forever
- an `allow` list of genuinely read-only commands (`git status`, `ls`, `rg`, …) so you stop
  approving the same harmless calls a dozen times a day
- a `deny` list covering `.env` files, private keys, and a couple of obviously destructive shapes

**`project-CLAUDE.md`** — a template for *project* instructions, written around one idea: every
line is re-read on every turn, so a rule that never changes a decision is pure cost.

It installs to `~/.claude/templates/project-CLAUDE.md`, **not** to `~/.claude/CLAUDE.md`. That
second path is your global file and applies to every project you ever open — dropping a
project-shaped template there would quietly make it doctrine for all of them. Copy it where it
belongs when you want it:

```bash
cp ~/.claude/templates/project-CLAUDE.md ./CLAUDE.md
```

## What it does not contain

No API keys. No credentials. No telemetry or model overrides. No private paths. It is a public
repo, so it holds only content that is safe for anyone to run.

## Safety

Existing files are never overwritten. If `~/.claude/settings.json` already exists, the preset lands
as `~/.claude/settings.json.new` and yours is untouched.

## Removing it

```bash
rm ~/.claude/settings.json ~/.claude/templates/project-CLAUDE.md
```

Claude Code works fine with no settings file at all.
