# Plants canaries, then runs checks.ps1 plain and under each Codex Windows sandbox
# mode, recording which process owned the connection to api.github.com.
param([string] $OutDir = 'results')
$ErrorActionPreference = 'Continue'
$root = Split-Path -Parent $MyInvocation.MyCommand.Path
New-Item -ItemType Directory -Force -Path $OutDir | Out-Null
$OutDir = (Resolve-Path $OutDir).Path
$ws = Join-Path $env:RUNNER_TEMP 'lab-workspace'
New-Item -ItemType Directory -Force -Path $ws | Out-Null

# Canaries where the real credentials would live. Obviously fake values only.
$ghDir = Join-Path $env:APPDATA 'GitHub CLI'
New-Item -ItemType Directory -Force -Path $ghDir | Out-Null
$ghFile = Join-Path $ghDir 'hosts.yml'
Set-Content -Path $ghFile -Value "github.com:`n    oauth_token: canary-not-a-real-token`n    user: canary"
$sshDir = Join-Path $env:USERPROFILE '.ssh'
New-Item -ItemType Directory -Force -Path $sshDir | Out-Null
Set-Content -Path (Join-Path $sshDir 'id_canary') -Value 'canary-not-a-real-key'
cmdkey /generic:riptides-canary /user:canary /pass:canary-not-a-real-secret | Out-Null
$outside = Join-Path $env:USERPROFILE 'sandbox-write-canary'
$env:CANARY_TOKEN = 'canary-not-a-real-secret'

$checks = Join-Path $root 'checks.ps1'
$psArgs = @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', $checks, '-GhFile', $ghFile, '-SshDir', $sshDir, '-OutsideFile', $outside)
$ghIps = @((Resolve-DnsName api.github.com -Type A).IPAddress)

$runs = [ordered]@{
    'plain'                           = @()
    'codex-elevated-default'          = @('sandbox', '-c', 'windows.sandbox=elevated', '--')
    'codex-elevated-workspace-write'  = @('sandbox', '-c', 'windows.sandbox=elevated', '-c', 'sandbox_mode=workspace-write', '--')
    'codex-elevated-ws-network'       = @('sandbox', '-c', 'windows.sandbox=elevated', '-c', 'sandbox_mode=workspace-write', '-c', 'sandbox_workspace_write.network_access=true', '--')
    'codex-unelevated-workspace-write'= @('sandbox', '-c', 'windows.sandbox=unelevated', '-c', 'sandbox_mode=workspace-write', '--')
    'codex-unelevated-ws-network'     = @('sandbox', '-c', 'windows.sandbox=unelevated', '-c', 'sandbox_mode=workspace-write', '-c', 'sandbox_workspace_write.network_access=true', '--')
}

$summary = @()
foreach ($name in $runs.Keys) {
    Remove-Item -Force -ErrorAction SilentlyContinue $outside, (Join-Path $ws 'workspace-canary')
    $ownersFile = Join-Path $OutDir "$name.owners.txt"
    $sampler = Start-Job -ArgumentList (,$ghIps), $ownersFile -ScriptBlock {
        param($ips, $file)
        while ($true) {
            Get-NetTCPConnection -RemotePort 443 -ErrorAction SilentlyContinue |
                ForEach-Object { $p = Get-Process -Id $_.OwningProcess -ErrorAction SilentlyContinue; if ($p) { "$($p.ProcessName) $($_.RemoteAddress)" } } |
                Add-Content -Path $file
            Start-Sleep -Milliseconds 100
        }
    }
    Start-Sleep -Seconds 2
    Push-Location $ws
    $out = if ($runs[$name].Count -eq 0) {
        & powershell.exe @psArgs 2>&1
    } else {
        & codex.cmd @($runs[$name]) powershell.exe @psArgs 2>&1
    }
    $exit = $LASTEXITCODE
    Pop-Location
    Start-Sleep -Seconds 1
    Stop-Job $sampler; Remove-Job $sampler
    # Owners of connections to any address the probes reported for api.github.com
    $seen = @(($out | Out-String) | Select-String -AllMatches -Pattern 'api\.github\.com.*?via ([0-9.]+)' | ForEach-Object { $_.Matches } | ForEach-Object { $_.Groups[1].Value }) + $ghIps | Sort-Object -Unique
    $owners = if (Test-Path $ownersFile) { (Get-Content $ownersFile | Where-Object { $seen -contains (($_ -split ' ')[1]) } | ForEach-Object { ($_ -split ' ')[0] } | Sort-Object -Unique) -join ',' } else { '' }
    if (-not $owners) { $owners = 'none seen' }
    $block = @("=== $name (exit $exit) ===") + ($out | ForEach-Object { "$_" }) + @(('{0,-46} {1}' -f 'owner of the api.github.com connection', $owners), '')
    $block | Tee-Object -FilePath (Join-Path $OutDir "$name.txt") | Write-Output
    $summary += $block
}
Remove-Item -Force -ErrorAction SilentlyContinue $outside
cmdkey /delete:riptides-canary | Out-Null

$versions = "codex $(& codex.cmd --version 2>&1) | $((Get-CimInstance Win32_OperatingSystem).Caption) $([Environment]::OSVersion.Version) | runner $env:ImageOS $env:ImageVersion"
$versions | Tee-Object -FilePath (Join-Path $OutDir 'versions.txt')
if ($env:GITHUB_STEP_SUMMARY) {
    @('```', $versions, '') + $summary + @('```') | Add-Content -Path $env:GITHUB_STEP_SUMMARY
}
