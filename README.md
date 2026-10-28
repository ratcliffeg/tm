# tm

A tmux session menu for running Claude Code on two accounts (work and personal) side by side,
on Linux or macOS.

- **`tm`** — full-screen session picker (fzf): sessions on the left, the highlighted session's
  screen on the right. Start new Claude sessions on either account, or plain shells, in any project.
  Opens automatically when you SSH in (handy from a phone, e.g. Termius).
- **Two accounts at once** — the personal account lives in its own config folder
  (`CLAUDE_CONFIG_DIR=~/.claude-personal`), so both stay logged in; no logging out and in.
- **Local model** — Claude Code pointed at a [local model server](#local-model) (Strata, Ollama,
  ...) on this or another machine, with its own config folder (`~/.claude-local`) and a mauve `LOCAL` label.
- **Colour-coded** — work sessions get a green tmux status bar and `WORK` label, personal ones
  blue and `PERSONAL`, plus a background tint. Plain shell sessions have no account and are grey
  with a `SHELL` label. The status bar and the terminal's title show the session and machine,
  e.g. `W-MYPROJECT (myhost)`, so you always know where a terminal is running.
- **Survives reboots** — every session (and the Claude conversation in it, on the right account)
  is snapshotted each minute and brought back after a reboot.
- **Remote Control on** — Claude starts with `--remote-control <session name>`, so every session
  can be picked up from claude.ai/code or the Claude app.

## Install

```bash
git clone https://github.com/ratcliffeg/tm.git ~/Code/tm
~/Code/tm/install.sh
```

Then log in to the personal account once:

```bash
claude-personal        # pick your personal account at the login prompt
```

To update later: `git -C ~/Code/tm pull`. The scripts are symlinked, so that's all it takes
(re-run `install.sh` if the tmux settings or services changed).

### Requirements

| | Linux | macOS |
|---|---|---|
| tmux, fzf | `sudo apt install tmux fzf` | `brew install tmux fzf` |
| bash | system bash | `brew install bash` recommended (macOS ships 3.2) |
| Claude Code | on `PATH` | on `PATH` |

`install.sh` checks these and, on macOS, offers to `brew install` anything missing.

### What install.sh does

- Symlinks the scripts in `bin/` into `~/.local/bin`. Any existing file it would replace is
  kept as `<name>.bak.<date>`.
- Saves your projects folder in `~/.config/tm/config` (`TM_PROJECTS_ROOT`, default `~/Code`).
- Adds `source-file …/tm/tmux/tm.conf` to `~/.tmux.conf`.
- Adds a marked block to `~/.bashrc` (Linux) or `~/.zshrc` (macOS) that opens `tm` on SSH logins
  (skip with `--no-ssh-hook`, or set `NO_TM=1`).
- Sets up save/restore (skip with `--no-services`):
  - **Linux:** systemd user units `tmux-save.timer` (every minute) and `tmux-restore.service` (at
    boot; needs `loginctl enable-linger $USER` to run before you log in).
  - **macOS:** launchd agents `tm.save` (every minute) and `tm.restore` (at login), in
    `~/Library/LaunchAgents`. Logs: `~/Library/Logs/tm-*.log`.

`./uninstall.sh` removes all of that again. It leaves sessions, logins and settings in place.

## Using it

| | |
|---|---|
| `tm` | Session menu. Arrows to move, type to filter, Enter to open, Ctrl-X to close the highlighted session (asks first; works on remote sessions too), `✕ stop all local sessions` (under the local sessions) to close every one on this machine (asks first), Esc to quit/go back, Ctrl-R to refresh the preview. |
| `tmux-personal` | New tmux session with Claude on the personal account, in the current folder. |
| `claude-personal` | Claude on the personal account, right here (no tmux). |
| `claude-local` | Claude on the local model server, right here (no tmux). |
| `prefix + P` | Inside tmux: new window with personal-account Claude in the current folder. |
| `prefix + s` | tmux's own session list, to hop between sessions. |
| `prefix + d` | Detach (session keeps running). If you opened it from `tm` in a plain terminal, you land back in the menu. |

Session names: `W-<FOLDER>` for work, `P-<FOLDER>` for personal, `L-<FOLDER>` for the local
model, `S-<FOLDER>` for plain shells, `CX-<FOLDER>` for Codex (upper case; `-2`, `-3` added if taken). Without fzf, `tm` falls back to a numbered text menu (`tm-text`).

## Settings

`⚙ settings` at the bottom of the menu edits the config file for you:

- **remote machines** — add, change addresses, rename, test or remove. Adding or editing one runs
  a connection test and tells you what's wrong (unreachable, key not accepted, new host key to
  trust).
- **projects folder** — the folder new sessions pick a project from.
- **local model address, name, token and token limits** — where the local model server is,
  what to send it and how much (see [Local model](#local-model)), plus a connection test.
  Type `-` to clear the model name or token, or put a limit back to its default.
- **colours** — the status-bar colour and dark background tint for work, personal, local-model,
  shell and Codex sessions, as `#rrggbb`. Set a bar colour and the tint follows (15% of it); type `auto`
  on a tint to go back to that. Running sessions on this machine are restyled straight away.
  A remote machine uses its own colour settings.
- **account names and prefixes** — what the work and personal accounts are called in the menu and
  status bar, and how new sessions are named (default `WORK`/`W` and `PERSONAL`/`P`; existing
  sessions keep their names). Plain shells are always `S-<FOLDER>` / `SHELL`, Codex sessions
  `CX-<FOLDER>` / `CODEX`, and local-model sessions `L-<FOLDER>` / `LOCAL`.

Everything is stored in `~/.config/tm/config`, so you can also edit it by hand.

## Local model

`+ Claude   local model` in the new-session menu starts Claude Code against a local model server
instead of Anthropic: anything that offers an Anthropic-compatible API (`/v1/messages`), such as
Strata or a recent Ollama, on this machine or another one (e.g. over Tailscale). `claude-local`
does the same without tmux. Sessions:

- use their own config folder, `~/.claude-local`, so they don't touch the work or personal logins;
- send every request (including background ones) to `ANTHROPIC_BASE_URL`, the server's address,
  with its API key and, if you set one, the model name in every model slot;
- cap requests at 131072 context and 4096 output tokens (Claude Code otherwise asks for more
  output than a local model returns);
- run without Remote Control, and with Claude Code's telemetry, error reports and auto-updates
  turned off;
- come back after a reboot on the same server.

Set it under `⚙ settings`, or in `~/.config/tm/config`:

```bash
TM_LOCAL_URL="http://<tailscale address>:8080"   # default http://127.0.0.1:8080; Claude Code adds /v1/messages
TM_LOCAL_TOKEN="<api key>"                        # if the server needs one, e.g. Strata's sk-strata-...
TM_LOCAL_MODEL="<model name>"                     # optional for Strata; Ollama needs a model it has
TM_LOCAL_MAX_CONTEXT_TOKENS=131072               # the default
TM_LOCAL_MAX_OUTPUT_TOKENS=4096                  # the default
```

Strata shows the address, model and API key in its settings for connecting Claude. Ollama listens
on port 11434 (`http://<address>:11434`) and needs no key. On the machine the server runs on, the
address is `127.0.0.1`; from another machine use its Tailscale name or address, which only works
if the server listens on more than 127.0.0.1. tm keeps the
config file readable only by you, as it holds the key. Changes apply to sessions started afterwards.

The settings menu takes a bare Tailscale name or address too, and adds `http://` and port 8080.
A local-model session started on a remote machine uses that machine's own settings when tm is
installed there (set them in its own `⚙ settings`), and the settings of the machine you run `tm`
on when it isn't. Each machine needs the address as it sees the server: `127.0.0.1` on the
server's machine, its Tailscale address everywhere else.

## Other machines

`tm` can list and open the sessions of other machines over SSH (for example a Claude LXC), next
to your local ones. Add them under `⚙ settings` → remote machines, or put them in `~/.config/tm/config`:

```bash
TM_REMOTES="lxc=me@192.0.2.10,me@lxc.example-tailnet.ts.net"
```

Space-separated `name=target[,fallback...]` entries. The first target that answers wins, so put
the LAN address before the Tailscale one and it works at home and away. Needs key-based SSH
(`ssh-copy-id`); `tm` only needs to be installed on the machine you run it on.

- Remote sessions show under a `── name ──` heading with the same WORK / PERSONAL colours and a
  live preview. An unreachable machine shows as `(offline)` and doesn't hold the menu up.
- Enter attaches over SSH. Inside tmux it opens a new window named `name:SESSION`; press the tmux
  prefix twice to send keys to the remote tmux (`prefix prefix d` detaches it). From a plain
  terminal there is only one tmux, so a single `prefix d` detaches and returns you to the menu.
- Each remote has a `+ new session on <name>` entry, and the bottom of the menu has
  `+ new session locally`; both work the same way. Pick Claude (work or personal) or a shell,
  then a folder from that machine's projects folder (its own `TM_PROJECTS_ROOT`, default `~/Code`)
  or type a path. The session is created there with the same `W-`/`P-`/`L-`/`S-<FOLDER>` naming and Remote
  Control as a local one, then you're attached. The remote needs `claude` installed and, for
  personal sessions, `claude-personal` logged in (`~/.claude-personal`). `tm` doesn't need to be
  updated there.

## Files

| | |
|---|---|
| `bin/tm` | fzf session menu |
| `bin/tm-text` | numbered text menu (fallback) |
| `bin/tmux-personal` | new personal-account tmux session |
| `bin/claude-personal` | personal-account Claude |
| `bin/claude-local` | Claude on the local model server; `--env` prints its settings for tm |
| `bin/tmux-account-style` | colours sessions/windows by account (called by tmux hooks) |
| `bin/tmux-save`, `bin/tmux-restore` | snapshot / restore sessions and their Claude conversations |
| `tmux/tm.conf` | tmux hooks and the `prefix + P` binding |
| `systemd/` | Linux save/restore units (macOS launchd agents are generated by `install.sh`) |

## macOS notes

- **Logins live in the Keychain on macOS**, not in a file. Claude Code keeps a separate Keychain
  entry per config folder, so work and personal should stay apart. This hasn't been tested on
  a Mac yet, so check after setup:
  run `/status` in a `claude` and a `claude-personal` session and confirm the two accounts.
- **Closed sessions may come back after a reboot.** On Linux the snapshot is cleared when you
  close every session; macOS can't tell that apart from a shutdown, so it keeps the last
  snapshot. Close sessions you don't want back with `tmux kill-session -t NAME`, then wait a
  minute for the next snapshot.
- **Colours** are 24-bit, and `tmux/tm.conf` declares that to tmux so the account tints survive SSH
  (a remote tmux otherwise assumes 256 colours and rounds the very dark tints to the same grey).
  Machines you attach to need `tm.conf` pulled and `tmux source-file ~/.tmux.conf` run once; it
  applies to the next attach. iTerm2, Ghostty, WezTerm and Kitty show the colours exactly;
  Terminal.app may show near matches.
- **SSH into the Mac** needs Remote Login on (System Settings → General → Sharing).

## Accounts and colours

| | Config folder | tmux bar | Label |
|---|---|---|---|
| Work | `~/.claude` (Claude's default) | green `#a6e3a1` | `WORK` |
| Personal | `~/.claude-personal` | blue `#89b4fa` | `PERSONAL` |
| Shell (no account) | none | grey `#9399b2` | `SHELL` |
| Codex (no account split) | `~/.codex` | orange `#fab387` | `CODEX` |
| Local model | `~/.claude-local` | mauve `#cba6f7` | `LOCAL` |

Change the colours under `⚙ settings` → colours (the built-in defaults are at the top of
`bin/tmux-account-style`).

## Licence

MIT — see [LICENSE](LICENSE). Use it, change it, and share fixes or additions as you like.
