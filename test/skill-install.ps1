# Pulls Install-Skill / Install-OneSkill out of the real install.ps1 by AST and runs
# them against a scratch USERPROFILE. install.ps1 as a whole cannot run off Windows
# (Update-SessionPath reads the registry), but the skill logic is portable.
# These are consumed by the functions lifted out of install.ps1 and defined here via
# Invoke-Expression, which the analyzer cannot follow - so it reports them unused.
[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseDeclaredVarsMoreThanAssignments', '',
    Justification = 'Read by functions defined through Invoke-Expression')]
param(
    [Parameter(Mandatory)][string]$ScriptPath,
    [Parameter(Mandatory)][string]$Scratch
)

$ErrorActionPreference = 'Stop'
# install.ps1 sets this at its top. Without it here the harness runs the same code
# under looser rules than production and can pass on a bug that fails on Windows -
# which is exactly what happened once already.
Set-StrictMode -Version Latest
$src = Resolve-Path $ScriptPath
$scratch = $Scratch

$ast = [System.Management.Automation.Language.Parser]::ParseFile($src, [ref]$null, [ref]$null)
$wanted = 'Install-OneSkill','Install-Skill','Write-Step','Write-Ok','Write-Warn2','Test-Command'
$fns = $ast.FindAll({ param($n) $n -is [System.Management.Automation.Language.FunctionDefinitionAst] }, $true) |
       Where-Object { $wanted -contains $_.Name }
if ($fns.Count -ne $wanted.Count) { Write-Host "  FAIL extracted $($fns.Count)/$($wanted.Count) functions"; exit 1 }
$fns | ForEach-Object { Invoke-Expression $_.Extent.Text }

# the catalog, also lifted from the real file
$catalogAst = $ast.FindAll({ param($n)
  $n -is [System.Management.Automation.Language.AssignmentStatementAst] -and
  $n.Left.Extent.Text -eq '$SkillCatalog' }, $true)
if (-not $catalogAst) { Write-Host "  FAIL no `$SkillCatalog found"; exit 1 }
Invoke-Expression $catalogAst[0].Extent.Text

$env:USERPROFILE = $scratch
$env:TEMP = $scratch
$DryRun = $false
$NodeMinMajor = 20
$script:Installed = [System.Collections.Generic.List[string]]::new()
$script:Skipped   = [System.Collections.Generic.List[string]]::new()
# Use the REAL parsing block from install.ps1, not a hand-made array. Hardcoding
# @('hire') here is exactly what hid a StrictMode .Count failure that only the
# genuine one-element pipeline produces.
$Skills = 'hire'
$namesAst = $ast.FindAll({ param($n)
  $n -is [System.Management.Automation.Language.AssignmentStatementAst] -and
  $n.Left.Extent.Text -eq '$script:SkillNames' -and
  $n.Right.Extent.Text -match 'Split' }, $true)
if (-not $namesAst) { Write-Host "  FAIL no `$script:SkillNames parse found"; exit 1 }
Invoke-Expression $namesAst[0].Extent.Text
if ($script:SkillNames.Count -ne 1) { Write-Host "  FAIL parsed $($script:SkillNames.Count) names, expected 1"; exit 1 }
Write-Host "  PASS one skill parses to a 1-element array (not a scalar)"

Install-Skill

$dest = Join-Path (Join-Path (Join-Path $scratch '.claude') 'skills') 'hire'
$fails = 0
if (-not (Test-Path (Join-Path $dest 'SKILL.md'))) { Write-Host "  FAIL SKILL.md missing"; $fails++ }
else { Write-Host "  PASS skill extracted to ~/.claude/skills/hire" }
if ($script:Installed -notcontains 'skill hire') { Write-Host "  FAIL not reported installed"; $fails++ }
else { Write-Host "  PASS reported as installed" }

# second run must leave it alone
$script:Installed.Clear(); $script:Skipped.Clear()
Install-Skill
if ($script:Skipped -notcontains 'skill hire (already present)') { Write-Host "  FAIL re-run did not skip"; $fails++ }
else { Write-Host "  PASS re-run left it alone" }

exit $fails
