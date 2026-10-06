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
    # From Command Prompt (cmd.exe), including the Windows Terminal cmd profile,
    # where the PowerShell one-liner above is a syntax error:
    powershell -NoProfile -ExecutionPolicy Bypass -Command "irm https://raw.githubusercontent.com/jtlgrowth/claude-code-installer/main/install.ps1 | iex"

.EXAMPLE
    # With options, download first (a piped script cannot take parameters):
    irm https://raw.githubusercontent.com/jtlgrowth/claude-code-installer/main/install.ps1 -OutFile install.ps1
    .\install.ps1 -Preset jtl

.NOTES
    Piped usage can still pass options via environment variables:
      $env:CCI_PRESET  = 'jtl'
      $env:CCI_SKILLS  = 'hire,setup'
      $env:CCI_KEY     = 'wk_...'   # workshop key for the skills (asked for when missing)
      $env:CCI_CODEX   = '1'        # also install the OpenAI Codex CLI (skills always go to Codex too)
      $env:CCI_NO_CLAUDE = '1'      # Codex users: skip Claude Code, install only the skills
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

    # Workshop key (wk_...) that opens the private skills; asked for when missing.
    [string]$Key = $env:CCI_KEY,

    # Also install the OpenAI Codex CLI from npm. The skills go to Codex either way.
    [switch]$Codex,

    # Codex users: do not install or check Claude Code; the skills still install.
    [switch]$NoClaude,

    [switch]$Minimal,
    [switch]$Yes,
    [switch]$DryRun
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# 'exit' inside irm | iex ends the PowerShell window itself, so the person never sees
# the summary or the error they were told to screenshot. Run as a file, exit with the
# code; run through iex, stop with 'break' instead, which leaves the window open
# (the same reason the Scoop installer uses break).
function Stop-Installer {
    param([int]$Code)
    if ($PSCommandPath) { exit $Code }
    if ($Code -eq 0) { return }   # success: let the script simply end
    break
}

# AppLocker / WDAC machines run PowerShell in Constrained Language Mode, where an
# installer dies on its first .NET call with an error nobody can act on. First, and
# with plain cmdlets only, so it runs before anything that mode would block.
if ($ExecutionContext.SessionState.LanguageMode -ne 'FullLanguage') {
    Write-Host ""
    Write-Host "error: this PC runs PowerShell in $($ExecutionContext.SessionState.LanguageMode) mode (set by IT), which blocks installers." -ForegroundColor Red
    Write-Host "    Ask IT to run this line for you, or to allow PowerShell scripts for your account."
    Stop-Installer 1
}
$ProgressPreference = 'SilentlyContinue'

# Windows PowerShell 5.1 on an older .NET still offers only TLS 1.0, which GitHub,
# claude.ai and nodejs.org refuse ("could not create SSL/TLS secure channel"). Add
# TLS 1.2 without dropping anything already allowed.
try { [Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12 } catch { $null = $_ }
# Office networks: an authenticating proxy (407) refuses the default anonymous
# request; hand it the signed-in Windows account, the way a browser would.
try { [Net.WebRequest]::DefaultWebProxy.Credentials = [Net.CredentialCache]::DefaultNetworkCredentials } catch { $null = $_ }

$RepoRaw           = 'https://raw.githubusercontent.com/jtlgrowth/claude-code-installer/main'
$OfficialInstaller = 'https://claude.ai/install.ps1'
$NodeMinMajor      = 20

if ($Preset -and $Preset -ne 'jtl') {
    # Write-Error would throw a terminating error under ErrorActionPreference
    # 'Stop' and bury a simple usage mistake in a stack of PowerShell noise.
    # Print it plainly and exit with a code the caller can test.
    [Console]::Error.WriteLine("error: unknown preset: $Preset (only 'jtl' exists)")
    Stop-Installer 2
}

# The skill allowlist: name -> tarball, the directory inside it, and how many
# leading path components to strip. An allowlist rather than a -Skills <url>
# flag, so an irm|iex installer never becomes an arbitrary-code downloader.
# Private since 2026-10-06: served behind a workshop key (wk_...) that each JTL
# workshop hands out and closes afterwards, never from a public repo.
$SkillCatalog = @{
    hire = @{
        Url    = 'https://download.jtlgrowth.com/skills/hire.tgz'
        Member = 'hire'
        Strip  = 0
    }
    setup = @{
        Url    = 'https://download.jtlgrowth.com/skills/setup.tgz'
        Member = 'setup'
        Strip  = 0
    }
}

$script:SkillNames = @()
if ($Skills) {
    # @() is load-bearing: a one-element pipeline returns a scalar string, and
    # under Set-StrictMode reading .Count on a string is a terminating error.
    # Without it, --skills with exactly one skill - the common case - throws.
    $script:SkillNames = @($Skills.Split(',') | ForEach-Object { $_.Trim() } | Where-Object { $_ })
    # Checked outside a loop: Stop-Installer's 'break' would only leave the loop.
    $unknown = @($script:SkillNames | Where-Object { -not $SkillCatalog.ContainsKey($_) })
    if ($unknown.Count -gt 0) {
        [Console]::Error.WriteLine("error: unknown skill: $($unknown[0]) (known skills: $($SkillCatalog.Keys -join ', '))")
        Stop-Installer 2
    }
}

if ($env:CCI_MINIMAL -eq '1') { $Minimal = $true }
if ($env:CCI_YES     -eq '1') { $Yes     = $true }
if ($env:CCI_DRY_RUN -eq '1') { $DryRun  = $true }
if ($env:CCI_CODEX   -eq '1') { $Codex   = $true }
if ($env:CCI_NO_CLAUDE -eq '1') { $NoClaude = $true }
# Workshop lines (w/*.ps1): install the prerequisites without a Y/n per package, but
# still ask for the workshop key. -Yes would skip the key prompt too.
$script:Workshop = ($env:CCI_WORKSHOP -eq '1')
$script:ClaudeFailed = $false
# Read here so a pasted key with stray spaces still works; Get-WorkshopKey reads
# $Key from script scope, which the analyzer cannot see (PSReviewUnusedParameter).
if ($Key) { $Key = $Key.Trim() }

$script:Preset    = $Preset
$script:Installed = [System.Collections.Generic.List[string]]::new()
$script:Already   = [System.Collections.Generic.List[string]]::new()
$script:Skipped   = [System.Collections.Generic.List[string]]::new()
# The workshop key: $null until a skill first needs it, '' when none was given.
$script:WorkshopKey = $null
$script:KeyRejected = $false
$script:KeyAsks     = 0   # times a rejected key was asked for again; capped
$script:KeyPattern  = '^wk_[A-Za-z0-9_-]{32,128}$'

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
    if ($Yes -or $DryRun -or $script:Workshop) { return $true }
    if ([Console]::IsInputRedirected) { return $true }
    $reply = Read-Host "$Question [Y/n]"
    return ($reply -notmatch '^(n|no)$')
}

# -------------------------------------------------------------- preflight ----

if ($NoClaude) { Write-Step "JTL skills installer (Codex)" } else { Write-Step "Claude Code installer" }
if ($DryRun) { Write-Warn2 "dry run - nothing will be installed" }


if (-not [Environment]::Is64BitProcess) {
    Write-Err "Claude Code does not support 32-bit Windows."
    Stop-Installer 1
}

# WSL and Git Bash are better served by the bash script; say so rather than
# half-working here.
if ($env:WSL_DISTRO_NAME) {
    Write-Warn2 "This looks like WSL. Use the bash installer instead:"
    Write-Host "    curl -fsSL $RepoRaw/install.sh | bash"
    Stop-Installer 1
}

$policy = Get-ExecutionPolicy -Scope Process
if ($policy -in @('Restricted', 'AllSigned')) {
    Write-Warn2 "Execution policy is '$policy'. If a script fails to run, first do:"
    Write-Host "    Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass"
}

$arch = if ($env:PROCESSOR_ARCHITECTURE -eq 'ARM64') { 'arm64' } else { 'x64' }
Write-Info "system: Windows ($arch), PowerShell $($PSVersionTable.PSVersion)"

# One quick look at every site this run needs, before anything installs. An office
# filter that blocks one of them otherwise surfaces twenty lines later as a vague
# download error; here it is one list the person can hand to IT.
function Test-Reach {
    param([string]$Url)
    try {
        Invoke-WebRequest -Uri $Url -Method Head -UseBasicParsing -TimeoutSec 20 | Out-Null
        return $true
    } catch {
        # Any HTTP answer (403, 404, 405) means the site is reachable; only a
        # connection that never got an answer means it is blocked.
        return ($null -ne $_.Exception.Response)
    }
}

function Test-Network {
    if ($DryRun) { return }
    $sites = [System.Collections.Generic.List[string]]::new()
    if ($script:SkillNames.Count -gt 0) { $sites.Add('https://download.jtlgrowth.com/healthz') }
    if (-not $NoClaude) { $sites.Add('https://claude.ai/install.ps1'); $sites.Add('https://downloads.claude.ai') }
    if ($Codex) { $sites.Add('https://registry.npmjs.org') }
    $blocked = @($sites | Where-Object { -not (Test-Reach $_) } | ForEach-Object { ([Uri]$_).Host })
    if ($blocked.Count -eq 0) { Write-Ok "network: every site this needs is reachable"; return }
    Write-Warn2 "this network cannot reach: $($blocked -join ', ')"
    Write-Host "     ask IT to allow those sites (or try another Wi-Fi / phone hotspot); continuing anyway"
}
Test-Network

# ------------------------------------------------------------- prereqs ------

# Rebuild $env:Path from the registry. An installer that just wrote a PATH entry
# did so in the registry, not in this already-running process, so without this
# every check right after an install reports "not found" and lies.
function Sync-PathFromRegistry {
    $machine = [Environment]::GetEnvironmentVariable('Path', 'Machine')
    $user    = [Environment]::GetEnvironmentVariable('Path', 'User')
    $rebuilt = (@($machine, $user) | Where-Object { $_ }) -join ';'
    if ($rebuilt) { $env:Path = $rebuilt }
}

function Get-NodeMajor {
    if (-not (Test-Command 'node')) { return 0 }
    try { return [int](((node --version) -replace '^v', '') -split '\.')[0] } catch { return 0 }
}

# Node straight from nodejs.org, no package manager involved. This is the path
# for boxes with no winget - Windows 10 before 1809, LTSC images, and machines
# where the Store is policy-blocked - which is exactly where "install Node
# yourself" leaves someone with a Claude Code that cannot run a single skill
# script. The version is queried, never hardcoded, so this does not rot.
function Install-NodeViaMsi {
    $msiArch = if ($env:PROCESSOR_ARCHITECTURE -eq 'ARM64') { 'arm64' } else { 'x64' }

    if ($DryRun) {
        Write-Host "  would run: download the latest Node LTS $msiArch .msi from nodejs.org and msiexec /qn it" -ForegroundColor DarkGray
        return $true
    }

    $version = $null
    try {
        # index.json is newest-first, and an LTS entry carries the codename
        # string while current releases carry the boolean false.
        $index = Invoke-RestMethod -Uri 'https://nodejs.org/dist/index.json' -UseBasicParsing
        foreach ($rel in $index) {
            if ($rel.lts -is [string] -and $rel.lts) {
                $major = [int](($rel.version -replace '^v', '') -split '\.')[0]
                if ($major -ge $NodeMinMajor) { $version = $rel.version }
                break
            }
        }
    } catch {
        Write-Warn2 "could not reach nodejs.org to find the current Node LTS"
        return $false
    }

    if (-not $version) {
        Write-Warn2 "nodejs.org lists no LTS at or above v$NodeMinMajor"
        return $false
    }

    $msiUrl = "https://nodejs.org/dist/$version/node-$version-$msiArch.msi"
    $msiPath = Join-Path $env:TEMP "node-$version-$msiArch.msi"
    Write-Info "downloading Node $version ($msiArch) from nodejs.org"
    try {
        Invoke-WebRequest -Uri $msiUrl -OutFile $msiPath -UseBasicParsing
    } catch {
        Write-Warn2 "download failed: $msiUrl"
        return $false
    }

    # /qn is the only sane mode here: this script is usually running inside an
    # irm|iex pipe with no console to click a wizard in.
    Write-Info "installing Node $version (msiexec, silent)"
    $proc = Start-Process -FilePath 'msiexec.exe' `
        -ArgumentList @('/i', "`"$msiPath`"", '/qn', '/norestart') `
        -Wait -PassThru
    Remove-Item $msiPath -Force -ErrorAction SilentlyContinue

    if ($proc.ExitCode -ne 0) {
        Write-Warn2 "msiexec exited $($proc.ExitCode) - Node was not installed"
        return $false
    }

    Sync-PathFromRegistry
    if ((Get-NodeMajor) -lt $NodeMinMajor) {
        # The MSI landed but PATH has not caught up in this process. Not a
        # failure - just something a new window fixes.
        Write-Ok "Node $version installed (open a new terminal to use it)"
    } else {
        Write-Ok "Node $(node --version) installed"
    }
    return $true
}

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
    # MSIX from a script is where Windows installers go to die, so we do not
    # try. Node is the one prerequisite worth installing the hard way anyway:
    # without it every skill that ships a script is dead on arrival, so it gets
    # a direct-from-nodejs.org MSI path while git and ripgrep stay advisory.
    if (-not (Test-Command 'winget')) {
        Write-Warn2 "winget is not available, so git/ripgrep cannot be installed automatically."
        Write-Host "    Install 'App Installer' from the Microsoft Store to get them:"
        Write-Host "    https://apps.microsoft.com/detail/9nblggh4nns1"
        $script:Skipped.Add("git/ripgrep (winget missing)")

        if ((Get-NodeMajor) -ge $NodeMinMajor) {
            Write-Ok "Node $(node --version) already installed"
            $script:Already.Add("node $(node --version)")
        } elseif (-not (Confirm-Action "Install Node LTS from nodejs.org?")) {
            $script:Skipped.Add("Node LTS (declined)")
        } elseif (Install-NodeViaMsi) {
            $script:Installed.Add("Node LTS")
        } else {
            $script:Skipped.Add("Node LTS (install failed)")
            Write-Host "     install it by hand from https://nodejs.org/en/download"
        }

        Write-Host "    Claude Code itself will still be installed below."
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
                $major = Get-NodeMajor
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
        } elseif ($p.Cmd -eq 'node' -and (Install-NodeViaMsi)) {
            # winget's Node package fails often enough on locked-down boxes
            # (source agreements, blocked msstore) that giving up here would
            # strand the one prerequisite the skills actually need.
            Write-Warn2 "winget could not install Node - fell back to the nodejs.org MSI"
            $script:Installed.Add($p.Label)
        } else {
            $script:Skipped.Add("$($p.Label) (install failed)")
            Write-Warn2 "could not install $($p.Label) - continuing"
        }
    }
}

# ------------------------------------------------------------------ codex ----

# Opt-in (-Codex or CCI_CODEX=1): the OpenAI Codex CLI from npm, for people who
# run Codex instead of, or next to, Claude Code. Needs Node, which the
# prerequisites step installs.
function Install-Codex {
    if (-not $Codex) { return }
    Write-Step "Codex"
    if (Test-Command 'codex') {
        $script:Already.Add("Codex $(codex --version 2>$null)")
        Write-Ok "Codex already installed"
        return
    }
    if (-not (Test-Command 'npm')) {
        Write-Warn2 "npm not found, so Codex cannot install (it needs Node $NodeMinMajor+; re-run without -Minimal)"
        $script:Skipped.Add("Codex (no npm)")
        return
    }
    Invoke-Step "npm install -g @openai/codex" { & npm install -g '@openai/codex' | Out-Host } | Out-Null
    if ($DryRun) { return }
    # npm's global bin is on the user PATH for new windows; add it to this one so
    # the verify step and the summary see codex now.
    $npmBin = Join-Path $env:APPDATA 'npm'
    if ((Test-Path $npmBin) -and (($env:Path -split ';') -notcontains $npmBin)) { $env:Path = "$npmBin;$env:Path" }
    if (Test-Command 'codex') {
        $script:Installed.Add("Codex")
        Write-Ok "Codex installed"
    } else {
        Write-Warn2 "Codex did not install; run: npm install -g @openai/codex"
        $script:Skipped.Add("Codex (npm install failed)")
    }
}

# ------------------------------------------------------------ claude code ----

function Install-ClaudeCode {
    Write-Step "Claude Code"
    if ($NoClaude) {
        Write-Info "skipped (-NoClaude): Codex only"
        $script:Skipped.Add("Claude Code (Codex only)")
        return
    }
    $wasPresent = Test-Command 'claude'
    if ($wasPresent) {
        $script:Already.Add("Claude Code $(claude --version 2>$null)")
        Write-Ok "Claude Code already installed - running its updater anyway"
    }
    Write-Info "running the official Anthropic installer"
    # A failure here must not stop the skills: a Codex user only needs those. It runs
    # in its own PowerShell process because it ends with 'exit 1' on any failure,
    # which inside this process would end the whole run before the skills.
    $psExe = (Get-Process -Id $PID).Path
    $childCmd = "[Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor 3072; irm $OfficialInstaller | iex"
    try {
        Invoke-Step "irm $OfficialInstaller | iex" {
            & $psExe -NoProfile -ExecutionPolicy Bypass -Command $childCmd | Out-Host
            if ($LASTEXITCODE -ne 0) { throw "the official installer exited with code $LASTEXITCODE" }
        } | Out-Null
    } catch {
        Write-Warn2 "Claude Code did not install: $($_.Exception.Message)"
        Write-Host "     the skills still install below; Claude Code can be retried with: irm $OfficialInstaller | iex"
        $script:Skipped.Add("Claude Code (install failed)")
        $script:ClaudeFailed = $true
        return
    }
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

    Sync-PathFromRegistry

    if (($env:Path -split ';') -notcontains $binDir) {
        $env:Path = "$binDir;$env:Path"
        Write-Ok "added $binDir to this session's PATH"
    } else {
        Write-Ok "$binDir already on PATH"
    }

    # Make it stick for every new window too. The official installer usually writes
    # this entry; when it does not, the new window says 'claude' is not recognized and
    # the fix is buried in Windows settings. Only adds what is missing, so re-runs are
    # no-ops. -notcontains is case-insensitive, and %VARS% are expanded before comparing.
    $userPath = [Environment]::GetEnvironmentVariable('Path', 'User')
    $entries  = @(($userPath -split ';') | Where-Object { $_ })
    $known    = @($entries | ForEach-Object { [Environment]::ExpandEnvironmentVariables($_).TrimEnd('\') })
    if ($known -notcontains $binDir.TrimEnd('\')) {
        [Environment]::SetEnvironmentVariable('Path', (@($entries) + $binDir) -join ';', 'User')
        Write-Ok "added $binDir to your PATH for new windows"
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
    # scrolled past, and that must never overwrite a skill they have edited. A
    # folder with no SKILL.md is what an interrupted run leaves; that one is redone.
    if (Test-Path $dest) {
        if (Test-Path (Join-Path $dest 'SKILL.md')) {
            Write-Warn2 "skill $Name already installed at $dest - left alone"
            $script:Skipped.Add("skill $Name (already present)")
            return
        }
        Write-Warn2 "found an unfinished $Name folder from an earlier run - installing it again"
        if (-not $DryRun) { Remove-Item $dest -Recurse -Force }
    }

    if ($DryRun) {
        Write-Host "  would download: " -ForegroundColor DarkGray -NoNewline
        Write-Host $entry.Url
        Write-Host "  would extract:  " -ForegroundColor DarkGray -NoNewline
        Write-Host "$($entry.Member) -> $dest"
        return
    }

    # Asked only when a skill actually needs downloading, so a re-run after the
    # workshop closed still says "already installed" instead of asking for a key.
    if ($null -eq $script:WorkshopKey) { $script:WorkshopKey = Get-WorkshopKey; if (-not $script:WorkshopKey) { $script:WorkshopKey = '' } }
    if (-not $script:WorkshopKey) {
        if ($script:KeyRejected) { $script:Skipped.Add("skill $Name (workshop key not accepted)") }
        else { $script:Skipped.Add("skill $Name (no workshop key)") }
        return
    }

    New-Item -ItemType Directory -Force -Path $skillsDir | Out-Null
    $tmp = Join-Path $env:TEMP "cci-skill-$Name.tgz"

    # Download to a file, then extract. A PowerShell pipeline carries text, not
    # bytes, so piping the gzip stream into tar would corrupt it - this is the
    # whole reason the bash one-liner cannot simply be reused here.
    # A wrong key asks again (a room full of people pasting makes typos), a rate
    # limit waits it out once, and a dropped connection gets one more try, so one
    # hiccup does not mean starting the whole line over.
    $waited = $false; $retried = $false
    while ($true) {
        try {
            Invoke-WebRequest -UseBasicParsing -Uri $entry.Url -OutFile $tmp `
                -Headers @{ Authorization = "Bearer $script:WorkshopKey" }
            break
        } catch {
            $code = $null
            if ($_.Exception.Response) { $code = [int]$_.Exception.Response.StatusCode }
            Remove-Item $tmp -Force -ErrorAction SilentlyContinue
            if ($code -eq 401) {
                Write-Warn2 "that workshop key was not accepted (a typo, or the workshop has closed)"
                $again = $null
                if ((Test-CanAsk) -and $script:KeyAsks -lt 3) { $script:KeyAsks++; $again = Read-WorkshopKey }
                if ($again) { $script:WorkshopKey = $again; continue }
                $script:WorkshopKey = ''; $script:KeyRejected = $true
                $script:Skipped.Add("skill $Name (workshop key not accepted)")
            } elseif ($code -eq 429 -and -not $waited) {
                Write-Warn2 "too many wrong keys from this network (one office Wi-Fi counts as one); waiting 60 seconds, then trying again"
                Start-Sleep -Seconds 61; $waited = $true; continue
            } elseif ($code -eq 429) {
                Write-Warn2 "skill ${Name}: still rate limited; wait a minute and run the same line again"
                $script:Skipped.Add("skill $Name (rate limited)")
            } elseif ($null -eq $code -and -not $retried) {
                Write-Warn2 "the download dropped ($($_.Exception.Message)); trying once more"
                Start-Sleep -Seconds 3; $retried = $true; continue
            } else {
                Write-Warn2 "could not download skill ${Name}: $($_.Exception.Message)"
                if ($null -eq $code) { Write-Host "     if this office blocks download.jtlgrowth.com, try a phone hotspot" }
                $script:Skipped.Add("skill $Name (download failed)")
            }
            return
        }
    }

    # Windows' own tar.exe by full path: with Git's Unix tools on PATH, plain 'tar'
    # can be GNU tar, which reads 'C:\...' as a remote host and fails.
    & $script:TarExe -xzf $tmp -C $skillsDir --strip-components=$($entry.Strip) $entry.Member 2>$null
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

# May the key be asked for at all: not under -Yes, which promises no prompts.
function Test-CanAsk { return (-not $Yes) }

# Prompts for the key, up to 3 tries. Returns $null when none of them looked like a key.
function Read-WorkshopKey {
    for ($i = 1; $i -le 3; $i++) {
        # Piped input that ran out makes Read-Host fail rather than wait; treat it as blank.
        try { $value = Read-Host '  Workshop key (starts with wk_, from your workshop host)' } catch { $value = '' }
        $value = ("$value" -replace '\s', '')
        if ($value -match $script:KeyPattern) { return $value }
        if (-not $value) { Write-Warn2 "nothing was pasted" }
        else { Write-Warn2 "that does not look like a workshop key (it starts with wk_ and is one long line)" }
        if ($i -lt 3) { Write-Host "     paste it again (right-click pastes in most windows)" }
    }
    return $null
}

# The key from CCI_KEY / -Key, or asked for. Returns $null (and says why) when there is none.
function Get-WorkshopKey {
    $value = ("$Key" -replace '\s', '')
    if ($value -match $script:KeyPattern) { return $value }
    if ($value) { Write-Warn2 "CCI_KEY does not look like a workshop key (it starts with wk_)" }
    if ($Yes) {
        Write-Warn2 "no workshop key: set `$env:CCI_KEY = 'wk_...' (your workshop host has it)"
        return $null
    }
    return Read-WorkshopKey
}

# Codex reads skills from $CODEX_HOME\skills (default ~\.codex\skills), not from
# ~\.claude\skills. Copy each installed skill there too, so $hire and $setup work in
# Codex as well. A copy, not a link: links on Windows need admin or Developer Mode.
function Copy-SkillToCodex {
    param([string]$Name)
    $src       = Join-Path (Join-Path (Join-Path $env:USERPROFILE '.claude') 'skills') $Name
    $codexHome = if ($env:CODEX_HOME) { $env:CODEX_HOME } else { Join-Path $env:USERPROFILE '.codex' }
    $skillsDir = Join-Path $codexHome 'skills'
    $dest      = Join-Path $skillsDir $Name
    if ($DryRun) {
        Write-Host "  would copy:     " -ForegroundColor DarkGray -NoNewline
        Write-Host "$src -> $dest"
        return
    }
    if (-not (Test-Path (Join-Path $src 'SKILL.md'))) { return }
    if (Test-Path (Join-Path $dest 'SKILL.md')) {
        $script:Skipped.Add("skill $Name for Codex (already present)")
        return
    }
    # An unfinished copy from an earlier run: redo it, or Copy-Item nests into it.
    if (Test-Path $dest) { Remove-Item $dest -Recurse -Force }
    New-Item -ItemType Directory -Force -Path $skillsDir | Out-Null
    Copy-Item -Recurse -Path $src -Destination $dest
    if (Test-Path (Join-Path $dest 'SKILL.md')) {
        $script:Installed.Add("skill $Name for Codex")
        Write-Ok "installed $dest"
    } else {
        Write-Warn2 "could not copy skill $Name for Codex"
        $script:Skipped.Add("skill $Name for Codex (copy failed)")
    }
}

function Install-Skill {
    if ($script:SkillNames.Count -eq 0) { return }
    Write-Step "Skills"

    # tar.exe ships with Windows 10 1803 and later. Older boxes get the npx route.
    $sysTar = Join-Path $env:SystemRoot 'System32\tar.exe'
    $script:TarExe = if (Test-Path $sysTar) { $sysTar } else { 'tar' }
    if (-not (Test-Path $sysTar) -and -not (Test-Command 'tar')) {
        Write-Warn2 "tar not found - cannot install skills"
        Write-Host "     update Windows (tar.exe ships with Windows 10 1803 and later), then run this again"
        $script:Skipped.Add("skills (no tar)")
        return
    }

    foreach ($name in $script:SkillNames) { Install-OneSkill $name }
    foreach ($name in $script:SkillNames) { Copy-SkillToCodex $name }

    # A skill is Markdown plus scripts, and the scripts need a runtime. -Minimal
    # skips the Node install, so say so rather than leaving a skill that cannot run.
    if (-not (Test-Command 'node')) {
        Write-Warn2 "node is not installed - skills that ship scripts will not run"
        Write-Host "     re-run this installer without -Minimal, or get Node $NodeMinMajor+ from"
        Write-Host "     https://nodejs.org/en/download - then open a new PowerShell window"
    }
}

# ----------------------------------------------------------------- node -----

# Claude Code runs without Node, but the setup and hire skills do not, and a new
# user only finds out at their first /setup. So check it where everyone looks: the
# summary. A warning, not a failure: claude itself is installed and working.
$script:NodeFix = ''
function Test-Node {
    if ($DryRun) { return }
    Sync-PathFromRegistry   # picks up a Node that winget or the MSI installed this run
    if ((Get-NodeMajor) -ge $NodeMinMajor) {
        Write-Ok "node $(node --version) (the setup and hire skills run on it)"
        return
    }
    if (Test-Command 'node') {
        Write-Warn2 "node $(node --version) is older than v$NodeMinMajor - the setup and hire skills need v$NodeMinMajor+"
    } else {
        Write-Warn2 "node is not installed - the setup and hire skills will not run"
    }
    $script:NodeFix = 'winget install OpenJS.NodeJS.LTS   (no winget? the Windows installer at https://nodejs.org)'
}

# --------------------------------------------------------------- verify -----

# The requested skills that are not on disk where the chosen app reads them. The
# summary must never say "installed" over a skill that is not there.
$script:MissingSkills = @()
function Test-SkillsOnDisk {
    $root = if ($NoClaude) {
        Join-Path $(if ($env:CODEX_HOME) { $env:CODEX_HOME } else { Join-Path $env:USERPROFILE '.codex' }) 'skills'
    } else { Join-Path (Join-Path $env:USERPROFILE '.claude') 'skills' }
    $script:MissingSkills = @($script:SkillNames | Where-Object { -not (Test-Path (Join-Path (Join-Path $root $_) 'SKILL.md')) })
    foreach ($n in $script:SkillNames) {
        if ($script:MissingSkills -notcontains $n) { Write-Ok "skill $n is in $root" }
    }
    return ($script:MissingSkills.Count -eq 0)
}

function Test-Installation {
    Write-Step "Verify"
    if ($DryRun) {
        Write-Host "  would run: claude --version; claude doctor" -ForegroundColor DarkGray
        return $true
    }
    $skillsOk = Test-SkillsOnDisk

    # Codex only: what has to work is the skills.
    if ($NoClaude) {
        if (Test-Command 'codex') { Write-Ok "codex --version -> $((codex --version 2>&1 | Out-String).Trim())" }
        else { Write-Warn2 "codex is not on PATH in this window; open a new window and run: codex --version" }
        return $skillsOk
    }
    if ($script:ClaudeFailed) { return $false }

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
    return $skillsOk
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
    } elseif ($Success -and $NoClaude) {
        Write-Host "The skills are installed for Codex." -ForegroundColor Green
        Write-Host ""
        Write-Host "Next:"
        Write-Host "  1. If Codex was open, quit it and open it again (it reads skills at start)."
        Write-Host "  2. Codex app: start a new chat. Codex CLI: open a new window and run  codex"
        Write-Host '  3. Type:  $setup   then  $hire'
    } elseif ($Success) {
        Write-Host "Claude Code is installed and working." -ForegroundColor Green
        Write-Host ""
        Write-Host "Next:"
        Write-Host "  1. Open a new PowerShell or Command Prompt window (so PATH is loaded)."
        Write-Host "  2. Run:  claude   (sign in when it asks; if Claude was already open, close it first)"
        if ($script:SkillNames.Count -gt 0) { Write-Host "  3. Type:  /setup   then  /hire" }
        else { Write-Host "  3. Sign in when prompted with /login" }
        if ($Codex) { Write-Host '  Using Codex instead: run  codex , sign in, then type  $setup' }
    } elseif ($script:MissingSkills.Count -gt 0) {
        Write-Host "Not done yet: the $($script:MissingSkills -join ' and ') skill did not install." -ForegroundColor Red
        Write-Host "  The reason is in the Skipped list above. Fix it, then paste the SAME line again;"
        Write-Host "  whatever already installed is kept, so only the missing part runs."
    } else {
        Write-Host "Install did not verify. See the error above." -ForegroundColor Red
        if ($script:ClaudeFailed -and ($script:Installed | Where-Object { $_ -like 'skill * for Codex' })) {
            Write-Host 'The skills did install. Using Codex? Open a new window, run  codex , then type  $setup' -ForegroundColor Yellow
        }
    }

    if ($script:NodeFix) {
        Write-Host ""
        Write-Host "Node.js is missing: the setup and hire skills will not run without it." -ForegroundColor Red
        Write-Host "  Fix:  $($script:NodeFix)"
        Write-Host "  Then open a new window and check:  node --version   (v$NodeMinMajor or higher)"
    }
}

# ----------------------------------------------------------------- main -----

try {
    # A failed prerequisite (winget, Node) must not stop the skills either.
    try { Install-Prerequisite } catch {
        Write-Warn2 "prerequisites step failed: $($_.Exception.Message)"
        $script:Skipped.Add("prerequisites (failed)")
    }
    Install-ClaudeCode
    Update-SessionPath
    Install-Codex
    Install-Preset
    Install-Skill
    $ok = Test-Installation
    Test-Node
    Write-Summary -Success $ok
    if (-not $ok) { Stop-Installer 1 }
    Stop-Installer 0
} catch {
    Write-Err $_.Exception.Message
    Write-Host ""
    Write-Host "What to do:"
    Write-Host "  1. Re-run with `$env:CCI_DRY_RUN='1' to see the commands without executing them."
    Write-Host "  2. Claude Code itself can always be installed directly:"
    Write-Host "       irm $OfficialInstaller | iex"
    Stop-Installer 1
}
