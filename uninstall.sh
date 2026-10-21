#!/usr/bin/env bash
# Remove what install.sh set up. Leaves running tmux sessions, your Claude logins
# (~/.claude, ~/.claude-personal) and the reboot snapshot alone.
set -euo pipefail

REPO="$(cd "$(dirname "$0")" && pwd)"
BIN="$HOME/.local/bin"

echo "==> Removing script links"
for f in "$REPO"/bin/*; do
    target="$BIN/$(basename "$f")"
    [ -L "$target" ] && [ "$(readlink "$target")" = "$f" ] && rm -f "$target"
done

echo "==> Removing tmux settings line"
if [ -f "$HOME/.tmux.conf" ]; then
    tmp=$(mktemp)
    grep -vF "source-file \"$REPO/tmux/tm.conf\"" "$HOME/.tmux.conf" |
        grep -vF '# tm: account colours and prefix + P personal window' >"$tmp" || true
    cat "$tmp" >"$HOME/.tmux.conf" && rm -f "$tmp"
fi

echo "==> Removing SSH-login hook"
for rc in "$HOME/.bashrc" "$HOME/.zshrc"; do
    [ -f "$rc" ] || continue
    tmp=$(mktemp)
    sed '/^# >>> tm >>>$/,/^# <<< tm <<<$/d' "$rc" >"$tmp" && cat "$tmp" >"$rc" && rm -f "$tmp"
done

echo "==> Removing save/restore services"
if [ "$(uname -s)" = Darwin ]; then
    for label in tm.save tm.restore; do
        launchctl bootout "gui/$(id -u)/$label" 2>/dev/null || true
        rm -f "$HOME/Library/LaunchAgents/$label.plist"
    done
else
    systemctl --user disable --now tmux-save.timer tmux-restore.service 2>/dev/null || true
    unit_dir="${XDG_CONFIG_HOME:-$HOME/.config}/systemd/user"
    rm -f "$unit_dir"/tmux-save.service "$unit_dir"/tmux-save.timer "$unit_dir"/tmux-restore.service
    systemctl --user daemon-reload 2>/dev/null || true
fi

echo "Done. Settings in ~/.config/tm and the snapshot in ~/.local/state/tmux-sessions were left in place."
