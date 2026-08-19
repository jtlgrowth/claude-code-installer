# Demo assets

`demo.gif` and `summary.png` are generated, not hand-made. Nothing in here is staged: the tape
runs the published one-liner and records whatever it prints.

## Regenerate

```bash
brew install vhs        # needs ttyd and ffmpeg, which vhs pulls in
vhs demo/demo.tape
```

The tape redirects `$HOME` to a scratch directory first, so the recording shows what a new
machine sees rather than the recording machine's own state, and the machine doing the recording
is left untouched.

It records the **dry run** on purpose. A real install is mostly a progress bar and ends with
`claude doctor` printing account and keychain state — machine-specific noise that would date the
recording and leak nothing useful. The dry run shows every decision the script makes and every
command it would run, in about fifteen seconds.
