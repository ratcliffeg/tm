#!/usr/bin/env bash
# Regenerate the screenshots in docs/images (SVG) from the real tm, run on a throwaway demo
# setup: made-up projects and sessions, a demo home folder, and the hostname "myhost", so no
# real names, paths or machines end up in the pictures. Linux only (needs `unshare`, which
# fakes the hostname without root); needs tmux, fzf, git and python3.
#   docs/tools/make-screenshots.sh
set -eu
REPO="$(cd "$(dirname "$0")/../.." && pwd)"
# Re-run inside a private user + hostname namespace, as "myhost".
if [ "$(hostname)" != myhost ]; then exec unshare -Ur -u bash -c 'hostname myhost && exec "$0" "$@"' "$0" "$@"; fi

OUT="$REPO/docs/images"
D=$(mktemp -d)
trap 'tmux kill-server 2>/dev/null; tmux -L outer kill-server 2>/dev/null; sleep 0.5; rm -rf "$D"' EXIT
mkdir -p "$OUT"

# --- demo machine -----------------------------------------------------------------------
export HOME="$D/home" TMUX_TMPDIR="$D/tmux" XDG_CONFIG_HOME="$D/home/.config" XDG_CACHE_HOME="$D/home/.cache"
export XDG_STATE_HOME="$D/home/.local/state" PATH="$D/home/.local/bin:$PATH" LANG=C.UTF-8 TERM=xterm-256color
export GIT_AUTHOR_NAME=Demo GIT_AUTHOR_EMAIL=demo@example.com GIT_COMMITTER_NAME=Demo GIT_COMMITTER_EMAIL=demo@example.com
unset TMUX
mkdir -p "$HOME/.local/bin" "$HOME/.config/tm" "$TMUX_TMPDIR"
for f in "$REPO"/bin/*; do ln -s "$f" "$HOME/.local/bin/"; done
for p in api-server myproject notes website; do mkdir -p "$HOME/Code/$p"; done
( cd "$HOME/Code/myproject" && git init -q -b main && touch README.md main.py requirements.txt && mkdir -p src tests &&
  git add -A && git commit -qm "First version" && echo x >>main.py && git commit -qam "Add the login page" )
cat >"$HOME/.config/tm/config" <<'EOF'
TM_PROJECTS_ROOT="$HOME/Code"
TM_REMOTES="lxc=me@192.0.2.10"
TM_LOCAL_URL="http://127.0.0.1:8080"
EOF
# Demo shells: a plain prompt as a normal user would see it.
cat >"$D/bashrc" <<'EOF'
PS1='\[\e[38;2;166;227;161m\]me@myhost\[\e[0m\]:\[\e[38;2;137;180;250m\]\w\[\e[0m\]$ '
EOF
cat >"$D/tmux.conf" <<EOF
source-file $REPO/tmux/tm.conf
set -g default-command "bash --rcfile $D/bashrc"
set -g default-terminal tmux-256color
EOF

# Demo sessions; tm.conf's hooks colour them by account, as on a real machine.
session() { # <name> <folder> [env]
    tmux -f "$D/tmux.conf" new-session -d -s "$1" -x 120 -y 30 -c "$HOME/Code/$2" ${3:+-e "$3"}
}
session W-MYPROJECT myproject
session P-NOTES notes "CLAUDE_CONFIG_DIR=$HOME/.claude-personal"
session L-API-SERVER api-server "CLAUDE_CONFIG_DIR=$HOME/.claude-local"
session S-WEBSITE website
sleep 1
tmux send-keys -t W-MYPROJECT 'clear; git log --oneline' Enter 'ls' Enter
tmux send-keys -t P-NOTES 'clear; ls' Enter
tmux send-keys -t L-API-SERVER 'clear; claude-local --env | head -4' Enter
tmux send-keys -t S-WEBSITE 'clear; pwd' Enter

# --- driving tm -------------------------------------------------------------------------
# tm runs in a separate, bare tmux ("outer") so its screen can be captured whole.
tmux -L outer -f /dev/null new-session -d -s outer -x 104 -y 28 -c "$HOME" "env -u TMUX tm"
tmux -L outer set -g status off
# One key (or typed text) at a time, with time for tm to draw the next screen.
keys() { local k; for k in "$@"; do tmux -L outer send-keys -t outer "$k"; sleep 1.2; done; }
shot() { # <file> <title>
    tmux -L outer capture-pane -e -p -t outer | python3 "$REPO/docs/tools/ansi2svg.py" --title "$2" >"$OUT/$1.svg"
    echo "  $1.svg"
}
sleep 5   # the offline remote takes a few seconds to time out

echo "Writing to $OUT:"
keys Down Down Down Down;               shot menu 'tm'
keys 'new session locally' Enter;      shot new-session 'tm · new session'
keys Down Down Enter;                  shot folder 'tm · choose a folder'
keys Escape; sleep 5                   # back to the session list (the offline remote is re-checked)
keys settings Enter;                   shot settings 'tm · settings'
keys colours Enter;                    shot colours 'tm · colours'
keys Escape Escape; sleep 5
keys S-WEBSITE C-x;                    shot close 'tm · close a session'
keys Enter; sleep 5                    # = no
keys W-MYPROJECT Enter;                shot session-work 'W-MYPROJECT (myhost)'
tmux detach-client -s W-MYPROJECT; sleep 5
keys L-API-SERVER Enter;               shot session-local 'L-API-SERVER (myhost)'
tmux detach-client -s L-API-SERVER; sleep 5
