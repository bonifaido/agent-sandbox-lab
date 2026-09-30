# Runs inside a sandbox (Windows PowerShell 5.1 compatible). Reports only whether each
# canary is reachable; never prints a secret. Paths are passed in because a sandbox may
# run as a different Windows user with its own profile.
param(
    [Parameter(Mandatory)] [string] $GhFile,
    [Parameter(Mandatory)] [string] $SshDir,
    [Parameter(Mandatory)] [string] $OutsideFile
)
$ErrorActionPreference = 'Continue'
function Report([string] $name, [string] $value) { '{0,-46} {1}' -f $name, $value }

Report 'running as' ([Security.Principal.WindowsIdentity]::GetCurrent().Name)

try { $n = [IO.File]::ReadAllBytes($GhFile).Length; Report 'read gh token file (hosts.yml)' "READABLE ($n bytes)" }
catch { Report 'read gh token file (hosts.yml)' 'blocked' }

try { $null = Get-ChildItem -LiteralPath $SshDir -ErrorAction Stop; Report 'list %USERPROFILE%\.ssh' 'READABLE' }
catch { Report 'list %USERPROFILE%\.ssh' 'blocked' }

if ($env:CANARY_TOKEN) { Report 'env var from the parent (CANARY_TOKEN)' 'VISIBLE' } else { Report 'env var from the parent (CANARY_TOKEN)' 'not visible' }
$names = @(Get-ChildItem env: | Where-Object { $_.Name -match '^(GH_|GITHUB_|COPILOT_|GIT_)|TOKEN|SECRET|PASS' } | ForEach-Object { $_.Name } | Sort-Object)
Report 'credential-looking env var names' ($names -join ' ')

$cred = 'blocked'
try {
    Add-Type -ErrorAction Stop -TypeDefinition @'
using System; using System.Runtime.InteropServices;
public static class LabCred {
  [DllImport("advapi32.dll", SetLastError=true, CharSet=CharSet.Unicode)]
  public static extern bool CredReadW(string target, int type, int flags, out IntPtr cred);
  [DllImport("advapi32.dll")] public static extern void CredFree(IntPtr cred);
  public static bool CanRead(string target) { IntPtr p; if (!CredReadW(target, 1, 0, out p)) return false; CredFree(p); return true; }
}
'@
    if ([LabCred]::CanRead('riptides-canary')) { $cred = 'READABLE' } else { $cred = "blocked (win32 error $([Runtime.InteropServices.Marshal]::GetLastWin32Error()))" }
} catch { $cred = "could not test ($($_.Exception.GetType().Name))" }
Report 'read Credential Manager entry' $cred

try { New-Item -ItemType File -Force -Path '.\workspace-canary' -ErrorAction Stop | Out-Null; Report 'write inside the project' 'allowed' }
catch { Report 'write inside the project' 'blocked' }

try { New-Item -ItemType File -Force -Path $OutsideFile -ErrorAction Stop | Out-Null; Report 'write outside the project (profile)' 'ALLOWED' }
catch { Report 'write outside the project (profile)' 'blocked' }

function Probe([string] $label, [string[]] $extra, [string] $url) {
    $o = & curl.exe -sS -o NUL -w '%{http_code} via %{remote_ip}:%{remote_port}' --max-time 8 @extra $url 2>&1
    $rc = $LASTEXITCODE
    $line = (($o | Out-String).Trim() -replace '\s+', ' ')
    if ($line.Length -gt 110) { $line = $line.Substring(0, 110) + '...' }
    if ($rc -eq 0) { Report $label "REACHABLE ($line)" } else { Report $label "blocked (curl rc=${rc}: $line)" }
}
Probe 'HTTPS to api.github.com' @() 'https://api.github.com/'
Probe 'HTTPS to example.com' @() 'https://example.com/'
Probe 'HTTPS to api.github.com, no revocation check' @('--ssl-no-revoke') 'https://api.github.com/'
Probe 'HTTPS to api.github.com, ignoring proxy vars' @('--noproxy', '*') 'https://api.github.com/'
Probe 'plain HTTP to example.com' @() 'http://example.com/'

# Node brings its own TLS stack (OpenSSL) and ignores proxy variables by default.
$js = "require('https').get('https://api.github.com/',{headers:{'user-agent':'lab'}},r=>{console.log('HTTP '+r.statusCode+' via '+r.socket.remoteAddress);process.exit(0)}).on('error',e=>{console.log('error '+e.code);process.exit(1)})"
$n = & node -e $js 2>&1; $rc = $LASTEXITCODE
$line = (($n | Out-String).Trim() -replace '\s+', ' ')
if ($rc -eq 0) { Report 'HTTPS to api.github.com from node' "REACHABLE ($line)" } else { Report 'HTTPS to api.github.com from node' "blocked ($line)" }
Report 'proxy variables seen' ((Get-ChildItem env: | Where-Object { $_.Name -match '^(https?|all)_proxy$' } | ForEach-Object { "$($_.Name)=$($_.Value)" }) -join ' ')

# Hold one slow connection open so the sampler outside can see who owns it.
& curl.exe -s -o NUL --max-time 6 --limit-rate 2k --ssl-no-revoke 'https://api.github.com/meta' 2>$null | Out-Null
