#!/bin/bash
# Disposable two-user tmux visibility lab. Runs as root inside WSL. Cleans up on exit.
cleanup() {
  su adlab_dev -c "tmux kill-server" >/dev/null 2>&1
  pkill -u adlab_dev >/dev/null 2>&1; pkill -u adlab_svc >/dev/null 2>&1; sleep 1
  userdel -r adlab_dev >/dev/null 2>&1; userdel -r adlab_svc >/dev/null 2>&1
  rm -rf /tmp/tmux-"$DEVUID" /tmp/tmux-"$SVCUID"
}
trap cleanup EXIT
useradd -m -s /bin/bash adlab_dev && useradd -m -s /bin/bash adlab_svc || exit 1
DEVUID=$(id -u adlab_dev); SVCUID=$(id -u adlab_svc)
su adlab_dev -c "tmux new-session -d -s ad_agent_lab 'sleep 300'"
echo "[1] dev user sees own session (control):"
su adlab_dev -c "tmux list-sessions 2>&1" | head -2
echo "[2] DIFFERENT user (companion as 'agentdeck' vs dev), default socket:"
su adlab_svc -c "tmux list-sessions 2>&1" | head -2
echo "[3] different user pointing at dev socket directly:"
DEVUID=$(id -u adlab_dev)
su adlab_svc -c "tmux -S /tmp/tmux-$DEVUID/default list-sessions 2>&1" | head -2
echo "[4] SAME user but private /tmp (simulates PrivateTmp=true):"
unshare -m bash -c "mount -t tmpfs tmpfs /tmp && su adlab_dev -c 'tmux list-sessions 2>&1'" | head -2
echo "[5] SAME user, shared /tmp (candidate fix):"
su adlab_dev -c "tmux list-sessions 2>&1" | head -2
