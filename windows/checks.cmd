@echo off
rem cmd.exe version of checks.ps1, for sandboxes that can't run PowerShell.
rem Usage: checks.cmd <gh hosts.yml> <.ssh dir> <file outside the project>
rem Reports reachability only; never prints a secret.
setlocal
echo running as                                     %USERDOMAIN%\%USERNAME%
type "%~1" >nul 2>&1 && (echo read gh token file ^(hosts.yml^)                 READABLE) || (echo read gh token file ^(hosts.yml^)                 blocked)
dir /b "%~2" >nul 2>&1 && (echo list %%USERPROFILE%%\.ssh                        READABLE) || (echo list %%USERPROFILE%%\.ssh                        blocked)
if defined CANARY_TOKEN (echo env var from the parent ^(CANARY_TOKEN^)         VISIBLE) else (echo env var from the parent ^(CANARY_TOKEN^)         not visible)
cmdkey /list:riptides-canary 2>nul | find /i "riptides-canary" >nul && (echo Credential Manager entry listed                YES) || (echo Credential Manager entry listed                no)
type nul > workspace-canary 2>nul && (echo write inside the project                       allowed) || (echo write inside the project                       blocked)
type nul > "%~3" 2>nul && (echo write outside the project ^(profile^)            ALLOWED) || (echo write outside the project ^(profile^)            blocked)
for %%h in (api.github.com example.com) do (
  curl.exe -s -o nul --max-time 8 -w "HTTPS to %%h                        %%{http_code} via %%{remote_ip}\n" https://%%h/ || echo HTTPS to %%h                        blocked
)
where node >nul 2>&1 && node -e "require('https').get('https://api.github.com/',{headers:{'user-agent':'lab'}},r=>{console.log('HTTPS from node                                HTTP '+r.statusCode);process.exit(0)}).on('error',e=>{console.log('HTTPS from node                                blocked '+e.code);process.exit(1)})"
