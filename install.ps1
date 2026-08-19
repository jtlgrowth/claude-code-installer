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
      $env:CCI_SKILLS  = 'hire'
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

    # Comma-separated agent skills to install, e.g. 'hire'. Same no-ValidateSet
    # reasoning as -Preset above.
    [string]$Skills = $env:CCI_SKILLS,

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
    # Write-Error would throw a terminating error under ErrorActionPreference
    # 'Stop' and bury a simple usage mistake in a stack of PowerShell noise.
    # Print it plainly and exit with a code the caller can test.
    [Console]::Error.WriteLine("error: unknown preset: $Preset (only 'jtl' exists)")
    exit 2
}

# The skill allowlist: name -> tarball, the directory inside it, and how many
# leading path components to strip. An allowlist rather than a -Skills <url>
# flag, so an irm|iex installer never becomes an arbitrary-code downloader.
$SkillCatalog = @{
    hire = @{
        Url    = 'https://codeload.github.com/jtlgrowth/hire/tar.gz/refs/heads/main'
        Member = 'hire-main/skills/hire'
        Strip  = 2
    }
}

$script:SkillNames = @()
if ($Skills) {
    $script:SkillNames = $Skills.Split(',') | ForEach-Object { $_.Trim() } | Where-Object { $_ }
    foreach ($name in $script:SkillNames) {
        if (-not $SkillCatalog.ContainsKey($name)) {
            [Console]::Error.WriteLine("error: unknown skill: $name (known skills: $($SkillCatalog.Keys -join ', '))")
            exit 2
        }
    }
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
    $claudeDir   = Join-Path $env:USERPROFILE '.claude'
    $templateDir = Join-Path $claudeDir 'templates'
    if (-not $DryRun) { New-Item -ItemType Directory -Force -Path $templateDir | Out-Null }

    # settings.json belongs at ~/.claude - that IS the global settings file.
    Install-PresetFile "$RepoRaw/preset/settings.json" (Join-Path $claudeDir 'settings.json')

    # The CLAUDE.md template does not. ~/.claude/CLAUDE.md is global
    # instructions applied to every project, so a project-shaped template
    # installed there would silently become doctrine for everything you open.
    Install-PresetFile "$RepoRaw/preset/project-CLAUDE.md" (Join-Path $templateDir 'project-CLAUDE.md')
    Write-Host "     copy it into a project root as CLAUDE.md when you want it:"
    Write-Host "       copy `$env:USERPROFILE\.claude\templates\project-CLAUDE.md .\CLAUDE.md"
}

# --------------------------------------------------------------- skills -----

# Skills live in ~/.claude/skills/<name>. That path is what makes /<name> resolve
# inside Claude Code; anywhere else and the skill is just files on disk.
function Install-OneSkill {
    param([string]$Name)

    $entry     = $SkillCatalog[$Name]
    $skillsDir = Join-Path (Join-Path $env:USERPROFILE '.claude') 'skills'
    $dest      = Join-Path $skillsDir $Name

    # Already there: leave it alone. People re-run this line when the first run
    # scrolled past, and that must never overwrite a skill they have edited.
    if (Test-Path $dest) {
        Write-Warn2 "skill $Name already installed at $dest - left alone"
        $script:Skipped.Add("skill $Name (already present)")
        return
    }

    if ($DryRun) {
        Write-Host "  would download: " -ForegroundColor DarkGray -NoNewline
        Write-Host $entry.Url
        Write-Host "  would extract:  " -ForegroundColor DarkGray -NoNewline
        Write-Host "$($entry.Member) -> $dest"
        return
    }

    New-Item -ItemType Directory -Force -Path $skillsDir | Out-Null
    $tmp = Join-Path $env:TEMP "cci-skill-$Name.tgz"

    # Download to a file, then extract. A PowerShell pipeline carries text, not
    # bytes, so piping the gzip stream into tar would corrupt it - this is the
    # whole reason the bash one-liner cannot simply be reused here.
    try {
        Invoke-RestMethod -Uri $entry.Url -OutFile $tmp
    } catch {
        Write-Warn2 "could not download skill ${Name}: $($_.Exception.Message)"
        $script:Skipped.Add("skill $Name (download failed)")
        return
    }

    & tar -xzf $tmp -C $skillsDir --strip-components=$($entry.Strip) $entry.Member 2>$null
    $tarOk = ($LASTEXITCODE -eq 0)
    Remove-Item $tmp -Force -ErrorAction SilentlyContinue

    if (-not $tarOk) {
        Write-Warn2 "could not extract skill $Name"
        $script:Skipped.Add("skill $Name (extract failed)")
        return
    }

    # Prove it, rather than trusting tar exited 0 over the right paths.
    if (-not (Test-Path (Join-Path $dest 'SKILL.md'))) {
        Write-Warn2 "skill $Name extracted but has no SKILL.md - removing"
        Remove-Item $dest -Recurse -Force -ErrorAction SilentlyContinue
        $script:Skipped.Add("skill $Name (no SKILL.md)")
        return
    }

    $script:Installed.Add("skill $Name")
    Write-Ok "installed $dest"
}

function Install-Skill {
    if (-not $script:SkillNames -or $script:SkillNames.Count -eq 0) { return }
    Write-Step "Skills"

    # tar.exe ships with Windows 10 1803 and later. Older boxes get the npx route.
    if (-not (Test-Command 'tar')) {
        Write-Warn2 "tar not found - cannot install skills"
        Write-Host "     install them with: npx skills add https://github.com/jtlgrowth/<skill>"
        $script:Skipped.Add("skills (no tar)")
        return
    }

    foreach ($name in $script:SkillNames) { Install-OneSkill $name }

    # A skill is Markdown plus scripts, and the scripts need a runtime. -Minimal
    # skips the Node install, so say so rather than leaving a skill that cannot run.
    if (-not (Test-Command 'node')) {
        Write-Warn2 "node is not installed - skills that ship scripts will not run"
        Write-Host "     install Node $NodeMinMajor+ and open a new PowerShell window"
    }
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
    Install-Skill
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
