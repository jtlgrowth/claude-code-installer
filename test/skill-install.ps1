# Pulls Install-Skill / Install-OneSkill out of the real install.ps1 by AST and runs
# them against a scratch USERPROFILE. install.ps1 as a whole cannot run off Windows
# (Update-SessionPath reads the registry), but the skill logic is portable.
$ErrorActionPreference = 'Stop'
$src = Resolve-Path $args[0]
$scratch = $args[1]

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
$script:SkillNames = @('hire')

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
