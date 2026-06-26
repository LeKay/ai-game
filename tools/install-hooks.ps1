# Installs project git hooks from tools/hooks/ into .git/hooks/.

$ErrorActionPreference = "Stop"

$hooksDir = Join-Path $PSScriptRoot "hooks"
$gitRoot   = & git rev-parse --show-toplevel
$gitHooks  = Join-Path $gitRoot ".git/hooks"

Get-ChildItem $hooksDir | ForEach-Object {
    $dst = Join-Path $gitHooks $_.Name
    Copy-Item $_.FullName -Destination $dst -Force
    Write-Host "  Installed: $($_.Name) -> .git/hooks/$($_.Name)"
}

Write-Host "Done. Git hooks are active."
