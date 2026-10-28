#!/usr/bin/env bash
# Install tm on Linux or macOS. Safe to re-run (it updates in place).
#
#   ./install.sh [--projects DIR] [--no-services] [--no-ssh-hook] [-y]
#
#   --projects DIR   folder tm lists projects from (default: ~/Code, asked if missing)
#   --no-services    skip save/restore-after-reboot (systemd on Linux, launchd on macOS)
#   --no-ssh-hook    don't open tm automatically on SSH logins
#   -y               don't ask questions; take the defaults
set -euo pipefail

REPO="$(cd "$(dirname "$0")" && pwd)"
OS="$(uname -s)"
BIN="$HOME/.local/bin"
CONFIG_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/tm"
PROJECTS="" SERVICES=1 SSH_HOOK=1 YES=0

while [ $# -gt 0 ]; do
    case "$1" in
        --projects) PROJECTS="$2"; shift ;;
        --no-services) SERVICES=0 ;;
        --no-ssh-hook) SSH_HOOK=0 ;;
        -y) YES=1 ;;
        -h|--help) sed -n '2,10p' "$0"; exit 0 ;;
        *) echo "Unknown option: $1" >&2; exit 1 ;;
    esac
    shift
done

say() { printf '\033[1m==>\033[0m %s\n' "$*"; }
warn() { printf '\033[33m!!\033[0m  %s\n' "$*"; }
ask() { # ask "question" default -> echoes answer
    local reply
    if [ "$YES" = 1 ]; then echo "$2"; return; fi
    read -rp "$1 [$2]: " reply
    echo "${reply:-$2}"
}

case "$OS" in
    Linux|Darwin) ;;
    *) echo "Unsupported OS: $OS" >&2; exit 1 ;;
esac

# --- dependencies -------------------------------------------------------------------
say "Checking dependencies"
missing=()
for cmd in tmux fzf; do command -v "$cmd" >/dev/null || missing+=("$cmd"); done
if [ "$OS" = Darwin ]; then
    # macOS ships bash 3.2; the scripts cope, but Homebrew's bash is better.
    bash_major=$(bash -c 'echo ${BASH_VERSINFO[0]}')
    [ "$bash_major" -lt 4 ] && missing+=(bash)
fi
# tmux is needed; fzf (else a text menu) and a newer bash on macOS are nice to have.
if [ ${#missing[@]} -gt 0 ]; then
    if [ "$OS" = Darwin ] && command -v brew >/dev/null; then
        if [ "$(ask "Install ${missing[*]} with Homebrew?" y)" = y ]; then
            brew install "${missing[@]}"
        fi
    else
        warn "Missing: ${missing[*]} (tmux is needed; fzf and a newer bash are optional)"
        [ "$OS" = Linux ] && warn "Install with: sudo apt install ${missing[*]}"
        if [ "$OS" = Darwin ]; then
            warn "Install them any way you like, e.g. Homebrew (brew install ${missing[*]})"
            warn "or MacPorts (sudo port install ${missing[*]}), then re-run install.sh."
        fi
    fi
fi
command -v tmux >/dev/null || warn "tmux not found on PATH: tm won't work until it's installed."
command -v claude >/dev/null || warn "Claude Code not found on PATH (https://claude.com/claude-code)"

# --- scripts --------------------------------------------------------------------------
say "Linking scripts into $BIN"
mkdir -p "$BIN"
for f in "$REPO"/bin/*; do
    name=$(basename "$f")
    target="$BIN/$name"
    # Keep a copy of anything that isn't already one of our links.
    if [ -e "$target" ] && [ ! -L "$target" ]; then
        mv "$target" "$target.bak.$(date +%Y%m%d%H%M%S)"
        warn "Backed up existing $target"
    fi
    ln -sfn "$f" "$target"
done
case ":$PATH:" in
    *":$BIN:"*) ;;
    *) warn "$BIN isn't on your PATH in this shell; the shell hook below adds it." ;;
esac

# --- config ---------------------------------------------------------------------------
mkdir -p "$CONFIG_DIR"
if [ -n "$PROJECTS" ] || [ ! -f "$CONFIG_DIR/config" ]; then
    if [ -z "$PROJECTS" ]; then
        default="$HOME/Code"
        [ -d "$default" ] || { [ -d "$HOME/Projects" ] && default="$HOME/Projects"; }
        PROJECTS=$(ask "Folder that holds your projects" "${default/#$HOME/\~}")
    fi
    PROJECTS="${PROJECTS/#\~/$HOME}"
    [ -d "$PROJECTS" ] || warn "$PROJECTS doesn't exist yet"
    # The config file is read as shell code, so no quotes, $, ` or \ in the path.
    case "$PROJECTS" in *[\"\$\`\\]*) echo "The projects folder can't contain \" \$ \` or \\: $PROJECTS" >&2; exit 1 ;; esac
    printf '# tm settings\nTM_PROJECTS_ROOT="%s"\n' "$PROJECTS" >"$CONFIG_DIR/config"
    say "Projects folder: $PROJECTS (saved in $CONFIG_DIR/config)"
fi

# --- tmux -----------------------------------------------------------------------------
say "Adding tm's tmux settings to ~/.tmux.conf"
line="source-file \"$REPO/tmux/tm.conf\""
touch "$HOME/.tmux.conf"
grep -qF "$line" "$HOME/.tmux.conf" || printf '\n# tm: account colours and prefix + P personal window\n%s\n' "$line" >>"$HOME/.tmux.conf"
if tmux ls >/dev/null 2>&1; then
    tmux source-file "$HOME/.tmux.conf"
    "$BIN/tmux-account-style" all
fi

# --- shell hook -----------------------------------------------------------------------
if [ "$SSH_HOOK" = 1 ]; then
    rc="$HOME/.bashrc"
    [ "$OS" = Darwin ] && rc="$HOME/.zshrc"
    say "Adding the SSH-login hook to $rc"
    touch "$rc"
    # Drop any previous block, then append the current one.
    tmp=$(mktemp)
    sed '/^# >>> tm >>>$/,/^# <<< tm <<<$/d' "$rc" >"$tmp" && cat "$tmp" >"$rc" && rm -f "$tmp"
    cat >>"$rc" <<'EOF'
# >>> tm >>>
# Managed by tm's install.sh. SSH logins open the tm session menu (q for a plain shell).
# Never runs inside tmux; set NO_TM=1 to skip.
case ":$PATH:" in *":$HOME/.local/bin:"*) ;; *) export PATH="$HOME/.local/bin:$PATH" ;; esac
if [ -n "$SSH_CONNECTION" ] && [ -z "$TMUX" ] && [ -z "${NO_TM:-}" ] && command -v tm >/dev/null; then
  tm
fi
# <<< tm <<<
EOF
fi

# --- save / restore after reboot ------------------------------------------------------
if [ "$SERVICES" = 1 ]; then
    if [ "$OS" = Linux ]; then
        say "Installing systemd user units (snapshot every minute, restore at boot)"
        unit_dir="${XDG_CONFIG_HOME:-$HOME/.config}/systemd/user"
        mkdir -p "$unit_dir"
        cp "$REPO"/systemd/tmux-save.service "$REPO"/systemd/tmux-save.timer "$REPO"/systemd/tmux-restore.service "$unit_dir/"
        systemctl --user daemon-reload
        systemctl --user enable --now tmux-save.timer
        systemctl --user enable tmux-restore.service
        if [ "$(loginctl show-user "$USER" -p Linger --value 2>/dev/null)" != yes ]; then
            warn "Sessions restore when you first log in. To restore at boot without logging in: loginctl enable-linger $USER"
        fi
    else
        say "Installing launchd agents (snapshot every minute, restore at login)"
        agents="$HOME/Library/LaunchAgents"
        mkdir -p "$agents" "$HOME/Library/Logs"
        # launchd starts jobs with a bare PATH: give them the folders tmux, claude and codex are
        # in (however they were installed), then the usual Homebrew and MacPorts ones.
        path="$BIN"
        for d in $(for c in tmux claude codex bash; do command -v "$c" 2>/dev/null; done | xargs -n1 dirname 2>/dev/null) \
                 /opt/homebrew/bin /usr/local/bin /opt/local/bin /usr/bin /bin; do
            case ":$path:" in *":$d:"*) ;; *) path="$path:$d" ;; esac
        done
        cat >"$agents/tm.save.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key><string>tm.save</string>
  <key>ProgramArguments</key><array><string>$BIN/tmux-save</string></array>
  <key>StartInterval</key><integer>60</integer>
  <key>EnvironmentVariables</key><dict><key>PATH</key><string>$path</string><key>LANG</key><string>en_US.UTF-8</string></dict>
  <key>StandardErrorPath</key><string>$HOME/Library/Logs/tm-save.log</string>
</dict>
</plist>
EOF
        cat >"$agents/tm.restore.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key><string>tm.restore</string>
  <key>ProgramArguments</key><array><string>/bin/sh</string><string>-c</string><string>sleep 15; exec "$BIN/tmux-restore"</string></array>
  <key>RunAtLoad</key><true/>
  <!-- Let the tmux server it starts outlive the job. -->
  <key>AbandonProcessGroup</key><true/>
  <!-- LANG: a tmux server started without a UTF-8 locale draws Claude's UI with underscores. -->
  <key>EnvironmentVariables</key><dict><key>PATH</key><string>$path</string><key>LANG</key><string>en_US.UTF-8</string></dict>
  <key>StandardOutPath</key><string>$HOME/Library/Logs/tm-restore.log</string>
  <key>StandardErrorPath</key><string>$HOME/Library/Logs/tm-restore.log</string>
</dict>
</plist>
EOF
        for label in tm.save tm.restore; do
            launchctl bootout "gui/$(id -u)/$label" 2>/dev/null || true
            # Bootstrapping tm.restore runs it once now; it skips sessions that already exist.
            launchctl bootstrap "gui/$(id -u)" "$agents/$label.plist"
        done
    fi
fi

say "Done."
cat <<EOF

  tm                  session menu (also opens on SSH login)
  tmux-personal       new tmux session with Claude on the personal account
  claude-personal     Claude on the personal account, right here
  prefix + P          (in tmux) personal-account Claude window

First time on the personal account: run claude-personal and log in.
EOF
