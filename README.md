# agent-sandbox-lab

Reproducible checks of what AI coding agents' built-in sandboxes let a command do:
read credential files, see inherited environment variables, write outside the
project, reach the network, and which process owns the resulting connection.

Every check uses canaries (obviously fake credential files, a dummy environment
variable, a dummy Credential Manager entry) planted where the real ones would live.
Nothing prints a real secret.

## Windows

`.github/workflows/windows.yml` runs `windows/run.ps1` on a GitHub-hosted
`windows-latest` runner. It installs Codex CLI and runs `windows/checks.ps1`:

- with no sandbox, as a baseline
- under `codex sandbox` with `windows.sandbox = "elevated"` and `"unelevated"`,
  in the default and `workspace-write` modes, with and without network access

Results are in the job summary and the `results-windows` artifact of each run.
Run it yourself from the Actions tab (`workflow_dispatch`), or fork the repo.

### Results, 2026-09-30 (Codex CLI 0.159.2, Windows Server 2025)

Raw output: [`results/windows-2026-09-30-codex-0.159.2`](results/windows-2026-09-30-codex-0.159.2),
from [this run](https://github.com/bonifaido/agent-sandbox-lab/actions/runs/36694833618).

| Check | No sandbox | Codex elevated | Codex unelevated |
|-|-|-|-|
| Runs as | your user | a separate `CodexSandboxOffline` / `CodexSandboxOnline` user | your user, restricted |
| Read the gh token file in your `%APPDATA%` | yes | **yes** | **yes** |
| List your `%USERPROFILE%\.ssh` | yes | no | **yes** |
| Read your Credential Manager entry | yes | no (the sandbox user has its own, empty vault) | **yes** |
| See a `*_TOKEN` variable from the parent | yes | **yes** | **yes** |
| Write outside the project | yes | no | no |
| Network off: reach the internet | n/a | no (firewall; node gets `EACCES`) | **yes, if the program ignores proxy variables** (node reached api.github.com) |
| Network on: HTTPS | yes | node yes; Windows TLS (schannel, e.g. `curl.exe`) fails with `SEC_E_NO_CREDENTIALS` | same as elevated |

Notes:

- Unelevated "network off" sets proxy variables to a dead `127.0.0.1` proxy. Programs
  that honour them fail; programs that don't, such as node, go straight out.
- In the default read-only mode, Windows PowerShell can't create its policy test file
  in `%TEMP%`, falls back to Constrained Language mode, and refuses to run the script.
- The connection-owner column is only reliable for the plain run: by the time the
  sampler saw the sandboxed connections they had closed, and Windows attributes those to
  the Idle process. Node's socket address shows the connection is direct, not proxied.

## Scope

GitHub-hosted runners run Windows Server as an administrator, which is not the same
as a developer's Windows 11 laptop. Copilot CLI's Windows sandbox needs an Insiders
build, and Gemini CLI and Copilot need a login, so they aren't covered yet. Cursor and
Claude Code sandbox through WSL2 on Windows.
