<#
.SYNOPSIS
    claude-code-installer - one command, working Claude Code CLI, on Windows.

.DESCRIPTION
    Installs the prerequisites you need to actually use Claude Code (git, Node
    LTS, ripgrep, via winget), then delegates to Anthropic's official installer
    for the checksum-verified native binary, fixes PATH for the current session,
    and verifies the result instead of assuming it.

.EXAMPLE
    irm https://raw.githubusercontent.com/jtlgrowth/claude-code-installer/main/install.ps1 | iex

.EXAMPLE
    # With options, download first (a piped script cannot take parameters):
    irm https://raw.githubusercontent.com/jtlgrowth/claude-code-installer/main/install.ps1 -OutFile install.ps1
    .\install.ps1 -Preset jtl

.NOTES
    Piped usage can still pass options via environment variables:
      $env:CCI_PRESET  = 'jtl'
      $env:CCI_MINIMAL = '1'
      $env:CCI_YES     = '1'
      $env:CCI_DRY_RUN = '1'
#>
[CmdletBinding()]
param(
    # Deliberately not [ValidateSet]: when CCI_PRESET is unset the default binds
    # as an empty string, which a ValidateSet rejects and would break every run
    # that does not ask for a preset. Validated by hand below instead.
    [string]$Preset = $env:CCI_PRESET,
    [switch]$Minimal,
    [switch]$Yes,
    [switch]$DryRun
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'

$RepoRaw           = 'https://raw.githubusercontent.com/jtlgrowth/claude-code-installer/main'
$OfficialInstaller = 'https://claude.ai/install.ps1'
$NodeMinMajor      = 20

if ($Preset -and $Preset -ne 'jtl') {
    Write-Error "unknown preset: $Preset (only 'jtl' exists)"
    exit 2
}

if ($env:CCI_MINIMAL -eq '1') { $Minimal = $true }
if ($env:CCI_YES     -eq '1') { $Yes     = $true }
if ($env:CCI_DRY_RUN -eq '1') { $DryRun  = $true }

$script:Preset    = $Preset
$script:Installed = [System.Collections.Generic.List[string]]::new()
$script:Already   = [System.Collections.Generic.List[string]]::new()
$script:Skipped   = [System.Collections.Generic.List[string]]::new()

# ---------------------------------------------------------------- output ----

function Write-Step  { param([string]$Text) Write-Host ""; Write-Host $Text -ForegroundColor White }
function Write-Info  { param([string]$Text) Write-Host "==> " -ForegroundColor Blue -NoNewline; Write-Host $Text }
function Write-Ok    { param([string]$Text) Write-Host "  ok " -ForegroundColor Green -NoNewline; Write-Host $Text }
function Write-Warn2 { param([string]$Text) Write-Host "  !! " -ForegroundColor Yellow -NoNewline; Write-Host $Text }
function Write-Err   { param([string]$Text) Write-Host "error: " -ForegroundColor Red -NoNewline; Write-Host $Text }

function Test-Command {
    param([string]$Name)
    $null -ne (Get-Command $Name -ErrorAction SilentlyContinue)
}

# Runs $Action, or just prints it under -DryRun. Returns whatever the block
# returns (dry runs report success) so callers can branch on the result.
function Invoke-Step {
    param([string]$Description, [scriptblock]$Action)
    if ($DryRun) {
        Write-Host "  would run: " -ForegroundColor DarkGray -NoNewline
        Write-Host $Description
        return $true
    }
    $result = & $Action
    if ($null -eq $result) { return $true }
    return $result
}

# A piped script has no console input of its own; default to yes there, the way
# every other one-liner installer does.
function Confirm-Action {
    param([string]$Question)
    if ($Yes -or $DryRun) { return $true }
    if ([Console]::IsInputRedirected) { return $true }
    $reply = Read-Host "$Question [Y/n]"
    return ($reply -notmatch '^(n|no)$')
}

# -------------------------------------------------------------- preflight ----

Write-Step "Claude Code installer"
if ($DryRun) { Write-Warn2 "dry run - nothing will be installed" }

if (-not [Environment]::Is64BitProcess) {
    Write-Err "Claude Code does not support 32-bit Windows."
    exit 1
}

# WSL and Git Bash are better served by the bash script; say so rather than
# half-working here.
if ($env:WSL_DISTRO_NAME) {
    Write-Warn2 "This looks like WSL. Use the bash installer instead:"
    Write-Host "    curl -fsSL $RepoRaw/install.sh | bash"
    exit 1
}

$policy = Get-ExecutionPolicy -Scope Process
if ($policy -in @('Restricted', 'AllSigned')) {
    Write-Warn2 "Execution policy is '$policy'. If a script fails to run, first do:"
    Write-Host "    Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass"
}

$arch = if ($env:PROCESSOR_ARCHITECTURE -eq 'ARM64') { 'arm64' } else { 'x64' }
Write-Info "system: Windows ($arch), PowerShell $($PSVersionTable.PSVersion)"

# ------------------------------------------------------------- prereqs ------

function Test-WinGetPackage {
    param([string]$Id)
    try {
        $out = winget list --id $Id --exact --accept-source-agreements 2>$null | Out-String
        return $out -match [regex]::Escape($Id)
    } catch {
        return $false
    }
}

function Install-Prerequisite {
    Write-Step "Prerequisites"

    if ($Minimal) {
        $script:Skipped.Add("prerequisites (-Minimal)")
        Write-Info "minimal mode - skipping git/node/ripgrep"
        return
    }

    # winget ships as App Installer on Windows 10 1809+ / 11. Side-loading the
    # MSIX from a script is where Windows installers go to die, so we stop and
    # point at the Store instead of guessing.
    if (-not (Test-Command 'winget')) {
        Write-Warn2 "winget is not available, so prerequisites cannot be installed automatically."
        Write-Host "    Install 'App Installer' from the Microsoft Store, then re-run this script:"
        Write-Host "    https://apps.microsoft.com/detail/9nblggh4nns1"
        Write-Host "    Claude Code itself will still be installed below."
        $script:Skipped.Add("prerequisites (winget missing)")
        return
    }

    $packages = @(
        @{ Id = 'Git.Git';                Cmd = 'git'; Label = 'git' },
        @{ Id = 'OpenJS.NodeJS.LTS';      Cmd = 'node'; Label = 'Node LTS' },
        @{ Id = 'BurntSushi.ripgrep.MSVC'; Cmd = 'rg'; Label = 'ripgrep' }
    )

    foreach ($p in $packages) {
        $needsInstall = $true

        if (Test-Command $p.Cmd) {
            if ($p.Cmd -eq 'node') {
                $major = 0
                try { $major = [int](((node --version) -replace '^v', '') -split '\.')[0] } catch { $major = 0 }
                if ($major -ge $NodeMinMajor) {
                    $needsInstall = $false
                    $script:Already.Add("node $(node --version)")
                } else {
                    Write-Warn2 "node v$major is older than v$NodeMinMajor - upgrading"
                }
            } else {
                $needsInstall = $false
                $script:Already.Add($p.Label)
            }
        } elseif (Test-WinGetPackage $p.Id) {
            # Installed but not yet on this session's PATH.
            $needsInstall = $false
            $script:Already.Add("$($p.Label) (installed, needs a new terminal)")
        }

        if (-not $needsInstall) {
            Write-Ok "$($p.Label) already installed"
            continue
        }

        if (-not (Confirm-Action "Install $($p.Label)?")) {
            $script:Skipped.Add("$($p.Label) (declined)")
            continue
        }

        Write-Info "installing $($p.Label)"
        $desc = "winget install --id $($p.Id) --exact --silent"
        $pkgId = $p.Id
        $installed = Invoke-Step $desc {
            winget install --id $pkgId --exact --silent `
                --accept-package-agreements --accept-source-agreements | Out-Null
            ($LASTEXITCODE -eq 0)
        }
        if ($installed) {
            $script:Installed.Add($p.Label)
            Write-Ok "$($p.Label) installed"
        } else {
            $script:Skipped.Add("$($p.Label) (install failed)")
            Write-Warn2 "could not install $($p.Label) - continuing"
        }
    }
}

# ------------------------------------------------------------ claude code ----

function Install-ClaudeCode {
    Write-Step "Claude Code"
    $wasPresent = Test-Command 'claude'
    if ($wasPresent) {
        $script:Already.Add("Claude Code $(claude --version 2>$null)")
        Write-Ok "Claude Code already installed - running its updater anyway"
    }
    Write-Info "running the official Anthropic installer"
    Invoke-Step "irm $OfficialInstaller | iex" {
        Invoke-Expression (Invoke-RestMethod -Uri $OfficialInstaller)
    } | Out-Null
    if (-not $wasPresent) { $script:Installed.Add("Claude Code") }
}

# --------------------------------------------------------------- PATH -------

# The official installer writes the PATH entry to the user registry, but this
# process was started before that happened. Rebuild $env:Path from the registry
# so verification works without opening a new terminal.
function Update-SessionPath {
    Write-Step "PATH"
    $binDir = Join-Path $env:USERPROFILE '.local\bin'

    if ($DryRun) {
        Write-Host "  would refresh PATH from the registry and add $binDir" -ForegroundColor DarkGray
        return
    }

    $machine = [Environment]::GetEnvironmentVariable('Path', 'Machine')
    $user    = [Environment]::GetEnvironmentVariable('Path', 'User')
    $env:Path = (@($machine, $user) | Where-Object { $_ }) -join ';'

    if (($env:Path -split ';') -notcontains $binDir) {
        $env:Path = "$binDir;$env:Path"
        Write-Ok "added $binDir to this session's PATH"
    } else {
        Write-Ok "$binDir already on PATH"
    }
}

# --------------------------------------------------------------- preset -----

function Install-PresetFile {
    param([string]$Url, [string]$Dest)
    if (Test-Path $Dest) {
        Invoke-Step "download $Url -> $Dest.new" {
            Invoke-RestMethod -Uri $Url -OutFile "$Dest.new"
        } | Out-Null
        Write-Warn2 "$(Split-Path $Dest -Leaf) already exists - wrote it as .new beside the original"
        $script:Skipped.Add("$(Split-Path $Dest -Leaf) (existing file kept)")
    } else {
        Invoke-Step "download $Url -> $Dest" {
            Invoke-RestMethod -Uri $Url -OutFile $Dest
        } | Out-Null
        $script:Installed.Add("preset $(Split-Path $Dest -Leaf)")
        Write-Ok "wrote $Dest"
    }
}

function Install-Preset {
    if (-not $script:Preset) { return }
    Write-Step "Preset: $($script:Preset)"
    $claudeDir = Join-Path $env:USERPROFILE '.claude'
    if (-not $DryRun) { New-Item -ItemType Directory -Force -Path $claudeDir | Out-Null }
    Install-PresetFile "$RepoRaw/preset/settings.json" (Join-Path $claudeDir 'settings.json')
    Install-PresetFile "$RepoRaw/preset/CLAUDE.md"     (Join-Path $claudeDir 'CLAUDE.md')
}

# --------------------------------------------------------------- verify -----

function Test-Installation {
    Write-Step "Verify"
    if ($DryRun) {
        Write-Host "  would run: claude --version; claude doctor" -ForegroundColor DarkGray
        return $true
    }

    if (-not (Test-Command 'claude')) {
        Write-Err "'claude' is not on PATH after installation."
        Write-Host ""
        Write-Host "Open a NEW PowerShell window and run:  claude --version"
        Write-Host "If it works there, the install is fine - this session just had a stale PATH."
        return $false
    }

    $version = (claude --version 2>&1 | Out-String).Trim()
    if ($LASTEXITCODE -ne 0) {
        Write-Err "'claude --version' failed:"
        Write-Host $version
        return $false
    }
    Write-Ok "claude --version -> $version"

    Write-Host ""
    Write-Info "claude doctor"
    claude doctor 2>&1 | ForEach-Object { Write-Host "    $_" }
    return $true
}

function Write-Summary {
    param([bool]$Success)
    Write-Step "Summary"
    $installedLabel = if ($DryRun) { "  Would install:" } else { "  Installed:" }
    if ($script:Installed.Count) { Write-Host $installedLabel;      $script:Installed | ForEach-Object { Write-Host "    + $_" } }
    if ($script:Already.Count)   { Write-Host "  Already present:"; $script:Already   | ForEach-Object { Write-Host "    = $_" } }
    if ($script:Skipped.Count)   { Write-Host "  Skipped:";         $script:Skipped   | ForEach-Object { Write-Host "    - $_" } }

    Write-Host ""
    if ($DryRun) {
        Write-Host "Dry run complete - nothing was installed." -ForegroundColor Yellow
        Write-Host "Re-run without -DryRun to actually install."
    } elseif ($Success) {
        Write-Host "Claude Code is installed and working." -ForegroundColor Green
        Write-Host ""
        Write-Host "Next:"
        Write-Host "  1. Open a new PowerShell window (so PATH is loaded)."
        Write-Host "  2. Run:  claude"
        Write-Host "  3. Sign in when prompted with /login"
    } else {
        Write-Host "Install did not verify. See the error above." -ForegroundColor Red
    }
}

# ----------------------------------------------------------------- main -----

try {
    Install-Prerequisite
    Install-ClaudeCode
    Update-SessionPath
    Install-Preset
    $ok = Test-Installation
    Write-Summary -Success $ok
    if (-not $ok) { exit 1 }
    exit 0
} catch {
    Write-Err $_.Exception.Message
    Write-Host ""
    Write-Host "What to do:"
    Write-Host "  1. Re-run with `$env:CCI_DRY_RUN='1' to see the commands without executing them."
    Write-Host "  2. Claude Code itself can always be installed directly:"
    Write-Host "       irm $OfficialInstaller | iex"
    exit 1
}
