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

### Copilot CLI, 2026-09-30 (1.0.89)

`.github/workflows/copilot-windows.yml` runs the same checks through the Copilot agent
with `sandbox.enabled` set to the policy `/sandbox enable` seeds, on `windows-11-arm`
and `windows-latest`. Raw output: [`results/windows-2026-09-30-copilot-1.0.89`](results/windows-2026-09-30-copilot-1.0.89).

| Runner | What happened |
|-|-|
| Windows 11 25H2, build 26200.9457, ARM64 | The sandbox refused every command, PowerShell and `cmd.exe` alike: *"This Windows host cannot run PowerShell in the sandbox. PowerShell needs Process Security Environment 1.1 filesystem enumeration support, which this host does not report."* |
| Windows Server 2025, build 26100.33438 | The sandbox turned itself off and every command ran with full access: *"Sandboxing is disabled for this session because this host does not support it. Shell commands and sandboxed services will run unsandboxed. Your sandbox.enabled setting remains unchanged."* |

Even unsandboxed, Copilot kept its own `COPILOT_GITHUB_TOKEN` out of the commands'
environment.

## Scope

The Windows checks cover Codex CLI and Copilot CLI. GitHub-hosted runners run Windows Server as an
administrator, which is not the same as a developer's Windows 11 laptop.
