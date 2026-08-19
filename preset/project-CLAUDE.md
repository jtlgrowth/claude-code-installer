# Project instructions — template

Copy this file into the root of a project as `CLAUDE.md`. Claude Code reads it automatically at
the start of every session run from that directory.

It is deliberately NOT installed as `~/.claude/CLAUDE.md`: that path is your *global* file and
applies to every project you open, so project-specific rules do not belong there.
Keep it short. Everything in here is paid for on every single turn, so a rule that never changes a
decision is a rule that costs you tokens for nothing.

Delete the parts you do not need — an empty section is worse than a missing one.

## What this project is

One or two sentences. What it does, who uses it, what "working" means.

## How to run it

```bash
# install
# dev server
# tests
```

Name the real commands. This is the single highest-value section: without it, Claude Code guesses,
and guessing is how you get `npm test` in a project that uses `pnpm`.

## Conventions that are not obvious from the code

Only the things a competent newcomer would get wrong by reading the codebase. For example:

- Where new files of each kind belong
- The naming or import style that is enforced
- Which directories are generated and must never be edited by hand

If the code already makes it obvious, leave it out.

## Boundaries

- Never edit: `<generated dirs, vendored code, lockfiles>`
- Never run: `<destructive or deploy commands>`
- Ask first before: `<migrations, anything touching production>`

## Definition of done

What has to be true before a change is finished — tests pass, lint clean, types check, a specific
command runs green. Be concrete so it can be verified rather than claimed.
