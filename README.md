# tm

A tmux session menu for running Claude Code on two accounts (work and personal) side by side,
on Linux or macOS.

- **`tm`** — full-screen session picker (fzf): sessions on the left, the highlighted session's
  screen on the right. Start new Claude sessions on either account, or plain shells, in any project.
  Opens automatically when you SSH in (handy from a phone, e.g. Termius).
- **Two accounts at once** — the personal account lives in its own config folder
  (`CLAUDE_CONFIG_DIR=~/.claude-personal`), so both stay logged in; no logging out and in.
- **Colour-coded** — work sessions get a green tmux status bar and `WORK` label, personal ones
  blue and `PERSONAL`, plus a background tint. Plain shell sessions have no account and are grey
  with a `SHELL` label.
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
| `tm` | Session menu. Arrows to move, type to filter, Enter to open, Esc to quit/go back, Ctrl-R to refresh the preview. |
| `tmux-personal` | New tmux session with Claude on the personal account, in the current folder. |
| `claude-personal` | Claude on the personal account, right here (no tmux). |
| `prefix + P` | Inside tmux: new window with personal-account Claude in the current folder. |
| `prefix + s` | tmux's own session list, to hop between sessions. |
| `prefix + d` | Detach (session keeps running). If you opened it from `tm` in a plain terminal, you land back in the menu. |

Session names: `W-<FOLDER>` for work, `P-<FOLDER>` for personal, `S-<FOLDER>` for plain shells
(upper case; `-2`, `-3` added if taken). Without fzf, `tm` falls back to a numbered text menu (`tm-text`).

## Other machines

`tm` can list and open the sessions of other machines over SSH (for example a Claude LXC), next
to your local ones. Add them to `~/.config/tm/config`:

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
  or type a path. The session is created there with the same `W-`/`P-`/`S-<FOLDER>` naming and Remote
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
- **Colours** are 24-bit. iTerm2, Ghostty, WezTerm and Kitty show them exactly; Terminal.app may
  show near matches.
- **SSH into the Mac** needs Remote Login on (System Settings → General → Sharing).

## Accounts and colours

| | Config folder | tmux bar | Label |
|---|---|---|---|
| Work | `~/.claude` (Claude's default) | green `#a6e3a1` | `WORK` |
| Personal | `~/.claude-personal` | blue `#89b4fa` | `PERSONAL` |
| Shell (no account) | none | grey `#9399b2` | `SHELL` |

Change the colours at the top of `bin/tmux-account-style`.
