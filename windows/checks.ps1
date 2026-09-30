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

foreach ($h in 'api.github.com', 'example.com') {
    $code = & curl.exe -s -o NUL -w '%{http_code}' --max-time 8 "https://$h/" 2>$null
    $rc = $LASTEXITCODE
    if ($rc -eq 0 -and $code -ne '000') { Report "HTTPS to $h" "REACHABLE ($code)" } else { Report "HTTPS to $h" "blocked (curl rc=$rc)" }
}
