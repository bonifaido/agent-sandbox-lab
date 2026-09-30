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

## Scope

GitHub-hosted runners run Windows Server as an administrator, which is not the same
as a developer's Windows 11 laptop. Copilot CLI's Windows sandbox needs an Insiders
build, and Gemini CLI and Copilot need a login, so they aren't covered yet. Cursor and
Claude Code sandbox through WSL2 on Windows.
