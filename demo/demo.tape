# Records demo.gif — the installer's dry run, unedited.
#
#   vhs demo/demo.tape
#
# The dry run is what gets recorded on purpose: it shows every decision the
# script makes and every command it would run, in about fifteen seconds, with
# no account state or machine-specific noise on screen. HOME is redirected to
# a scratch directory so the output looks like a new machine's rather than the
# recording machine's.

Require bash

Output demo/demo.gif

Set Shell "bash"
Set FontSize 15
Set Width 1180
Set Height 720
Set Padding 24
Set Theme "Catppuccin Mocha"
Set TypingSpeed 40ms

# --- setup, not shown -------------------------------------------------------
Hide
Type "export HOME=/tmp/cci-demo-home && unset ZDOTDIR && rm -rf $HOME && mkdir -p $HOME && cd $HOME"
Enter
Type "export PS1='$ ' && clear"
Enter
Sleep 1s
Show

# --- the demo ---------------------------------------------------------------
Sleep 1200ms
Type "curl -fsSL https://raw.githubusercontent.com/jtlgrowth/claude-code-installer/main/install.sh | CCI_DRY_RUN=1 bash"
Sleep 600ms
Enter

Wait+Screen@120s /Re-run without/
Sleep 3500ms
Screenshot demo/summary.png
