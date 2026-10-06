# Workshop doctor for Windows: finds and fixes the path problems that stop Claude Code,
# Codex or a /setup alias from starting. Paste in PowerShell:
#   irm https://raw.githubusercontent.com/jtlgrowth/claude-code-installer/main/w/doctor.ps1 | iex
# Safe to run any number of times. It only ever adds a missing folder to your user PATH,
# sets CLAUDE_CODE_GIT_BASH_PATH, and moves this window out of the Windows folder.
# It deletes nothing and never calls exit, so the window stays open on the report.

function Invoke-JtlDoctor {
    $ErrorActionPreference = 'Continue'
    try { [Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12 } catch { $null = $_ }
    $fixed = [System.Collections.Generic.List[string]]::new()
    $needs = [System.Collections.Generic.List[string]]::new()
    function Write-Good  { param([string]$t) Write-Host "  ok    " -ForegroundColor Green -NoNewline; Write-Host $t }
    function Write-Fixed { param([string]$t) Write-Host "  fixed " -ForegroundColor Cyan -NoNewline; Write-Host $t; $fixed.Add($t) }
    function Write-Need  { param([string]$t) Write-Host "  !!    " -ForegroundColor Yellow -NoNewline; Write-Host $t; $needs.Add($t) }

    Write-Host ""
    Write-Host "JTL workshop doctor" -ForegroundColor White
    $userHome = $env:USERPROFILE
    $bin = Join-Path $userHome '.local\bin'

    # 1. The folder this window is in. "Run as administrator" opens in C:\Windows\System32,
    #    and a desk folder made there is lost or refused.
    $here = (Get-Location).Path
    $isAdmin = $false
    try { $isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator) } catch { $null = $_ }
    if ($env:WINDIR -and $here.ToLower().StartsWith($env:WINDIR.ToLower())) {
        Set-Location $userHome
        Write-Fixed "this window was in $here (the Windows folder); moved to $userHome"
    } else { Write-Good "this window is in $here" }
    if ($isAdmin) { Write-Need "this window runs as Administrator. Close it and open PowerShell normally (no 'Run as administrator')" }

    # 2. ~/.local/bin on PATH: claude.exe and every /setup alias live there.
    $userPath = [Environment]::GetEnvironmentVariable('Path', 'User')
    $entries = @(($userPath -split ';') | Where-Object { $_ })
    $known = @($entries | ForEach-Object { [Environment]::ExpandEnvironmentVariables($_).TrimEnd('\') })
    if ($known -notcontains $bin.TrimEnd('\')) {
        [Environment]::SetEnvironmentVariable('Path', (@($entries) + $bin) -join ';', 'User')
        Write-Fixed "added $bin to your PATH for new windows"
    } else { Write-Good "$bin is on your PATH" }
    if ((($env:Path -split ';') | ForEach-Object { $_.TrimEnd('\') }) -notcontains $bin.TrimEnd('\')) { $env:Path = "$bin;$env:Path" }
    $npmBin = Join-Path $env:APPDATA 'npm'
    if ((Test-Path $npmBin) -and ((($env:Path -split ';') | ForEach-Object { $_.TrimEnd('\') }) -notcontains $npmBin)) { $env:Path = "$env:Path;$npmBin" }

    # 3. Claude Code and Codex.
    $claude = Get-Command claude -ErrorAction SilentlyContinue
    if ($claude) { Write-Good "claude found at $($claude.Source)" }
    elseif (Test-Path (Join-Path $bin 'claude.exe')) { Write-Good "claude is installed at $bin (opens in a new window)" }
    $codex = Get-Command codex -ErrorAction SilentlyContinue
    if ($codex) { Write-Good "codex found at $($codex.Source)" }
    if (-not $claude -and -not (Test-Path (Join-Path $bin 'claude.exe')) -and -not $codex) {
        Write-Need "neither Claude Code nor Codex is installed. Paste your workshop install line again"
    }

    # 4. Git Bash. Claude Code on Windows needs bash.exe and says "requires git-bash" when it
    #    cannot find it, most often after Git was installed somewhere unusual or PATH is stale.
    $bash = $null
    $cands = [System.Collections.Generic.List[string]]::new()
    $git = Get-Command git -ErrorAction SilentlyContinue
    if ($git) { $cands.Add((Join-Path (Split-Path (Split-Path $git.Source)) 'bin\bash.exe')) }
    foreach ($root in @($env:ProgramFiles, ${env:ProgramFiles(x86)}, (Join-Path $env:LOCALAPPDATA 'Programs'))) {
        if ($root) { $cands.Add((Join-Path $root 'Git\bin\bash.exe')) }
    }
    foreach ($c in $cands) { if (Test-Path -LiteralPath $c) { $bash = (Resolve-Path -LiteralPath $c).Path; break } }
    $set = [Environment]::GetEnvironmentVariable('CLAUDE_CODE_GIT_BASH_PATH', 'User')
    if ($bash) {
        if ($set -and (Test-Path -LiteralPath $set)) { Write-Good "Git Bash is set: $set" }
        else {
            [Environment]::SetEnvironmentVariable('CLAUDE_CODE_GIT_BASH_PATH', $bash, 'User')
            $env:CLAUDE_CODE_GIT_BASH_PATH = $bash
            if ($set) { Write-Fixed "CLAUDE_CODE_GIT_BASH_PATH pointed to a missing file; now $bash" }
            else { Write-Fixed "told Claude Code where Git Bash is: $bash" }
        }
    } elseif ($claude -or (Test-Path (Join-Path $bin 'claude.exe'))) {
        if (Get-Command winget -ErrorAction SilentlyContinue) {
            Write-Host "  ...   Git Bash is missing; installing Git (click Yes if Windows asks)"
            winget install --id Git.Git --exact --silent --accept-package-agreements --accept-source-agreements | Out-Null
            $b = Join-Path $env:ProgramFiles 'Git\bin\bash.exe'
            if (Test-Path -LiteralPath $b) {
                [Environment]::SetEnvironmentVariable('CLAUDE_CODE_GIT_BASH_PATH', $b, 'User')
                Write-Fixed "installed Git and set CLAUDE_CODE_GIT_BASH_PATH to $b"
            } else { Write-Need "Git did not install. Get it from https://git-scm.com/downloads/win, then run this doctor again" }
        } else { Write-Need "Git Bash is missing. Install Git from https://git-scm.com/downloads/win, then run this doctor again" }
    }

    # 5. Node: the setup and hire skills run on it.
    $node = Get-Command node -ErrorAction SilentlyContinue
    if ($node) {
        $v = (& node --version) 2>$null
        if ("$v" -match '^v(\d+)' -and [int]$Matches[1] -ge 20) { Write-Good "node $v" }
        else { Write-Need "node $v is older than v20. Run: winget install OpenJS.NodeJS.LTS" }
    } else { Write-Need "node is not installed. Run: winget install OpenJS.NodeJS.LTS   (then open a new window)" }

    # 6. The skills, where each app reads them.
    $codexHome = if ($env:CODEX_HOME) { $env:CODEX_HOME } else { Join-Path $userHome '.codex' }
    foreach ($pair in @(@('Claude Code', (Join-Path $userHome '.claude\skills')), @('Codex', (Join-Path $codexHome 'skills')))) {
        $have = @('setup', 'hire' | Where-Object { Test-Path -LiteralPath (Join-Path (Join-Path $pair[1] $_) 'SKILL.md') })
        if ($have.Count -eq 2) { Write-Good "$($pair[0]) skills: setup and hire" }
        elseif ($have.Count -eq 1) { Write-Need "$($pair[0]) has only $($have[0]). Paste your workshop install line again" }
    }

    # 7. /setup aliases: a .cmd launcher in ~/.local/bin that runs claude or codex.
    $shims = @(Get-ChildItem -LiteralPath $bin -Filter '*.cmd' -ErrorAction SilentlyContinue |
        Where-Object { (Get-Content -LiteralPath $_.FullName -Raw -ErrorAction SilentlyContinue) -match 'written by /setup' })
    foreach ($s in $shims) {
        $target = if ((Get-Content -LiteralPath $s.FullName -Raw) -match '@codex') { 'codex' } else { 'claude' }
        $alias = [IO.Path]::GetFileNameWithoutExtension($s.Name)
        $exists = (Get-Command $target -ErrorAction SilentlyContinue) -or ($target -eq 'claude' -and (Test-Path (Join-Path $bin 'claude.exe')))
        if ($exists) { Write-Good "alias '$alias' opens $target (type it in a new window)" }
        else { Write-Need "alias '$alias' opens $target, which is not installed here. Paste your workshop install line again" }
    }

    # 8. Where Desktop and Documents really are. With OneDrive they move, and "cd Desktop" fails.
    $desk = [Environment]::GetFolderPath('Desktop'); $docs = [Environment]::GetFolderPath('MyDocuments')
    if ($desk -match 'OneDrive' -or $docs -match 'OneDrive') {
        Write-Good "your Desktop is inside OneDrive. To go there:  cd `"$desk`""
    } else { Write-Good "Desktop: $desk" }

    Write-Host ""
    if ($needs.Count -eq 0 -and $fixed.Count -eq 0) { Write-Host "All good. Open Claude Code (or Codex) in your desk folder." -ForegroundColor Green }
    elseif ($needs.Count -eq 0) { Write-Host "Fixed $($fixed.Count) thing(s). Close this window, open a NEW one, then type claude (or your alias)." -ForegroundColor Green }
    else { Write-Host "$($needs.Count) thing(s) need you (the !! lines above). Screenshot this window if you are stuck." -ForegroundColor Yellow }
    Write-Host "Folder names with spaces need quotes:  cd `"My Folder`""
}
Invoke-JtlDoctor
