# Workshop line for Codex users: the hire and setup skills for Codex, no Claude Code.
# Pasted as one line that works in PowerShell, Command Prompt and Git Bash alike:
#   powershell -NoProfile -ExecutionPolicy Bypass -Command "[Net.ServicePointManager]::SecurityProtocol=3072; irm https://raw.githubusercontent.com/jtlgrowth/claude-code-installer/main/w/codex.ps1 | iex"
# The line holds no $, so no shell rewrites it, and it runs in its own PowerShell, so
# the window stays open on the summary when the installer exits.
# Every option is set here, not inherited: a variable left over from an earlier
# attempt in the same window must not change what this line does.
$env:CCI_SKILLS = 'hire,setup'
$env:CCI_WORKSHOP = '1'   # prerequisites without a Y/n each; the key is still asked
$env:CCI_NO_CLAUDE = '1'
$env:CCI_CODEX = '1'
$env:CCI_YES = ''
$env:CCI_MINIMAL = ''
$env:CCI_DRY_RUN = ''
$env:CCI_PRESET = ''
$base = 'https://raw.githubusercontent.com/jtlgrowth/claude-code-installer/main'
if ($env:CCI_BASE) { $base = $env:CCI_BASE }   # CI points this at the commit under test
Invoke-Expression (Invoke-RestMethod -Uri "$base/install.ps1" -UseBasicParsing)
