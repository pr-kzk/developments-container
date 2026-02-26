#!/bin/bash
set -e

# Docker ソケットの権限を確認・修正
if [ -S /var/run/docker.sock ]; then
    SOCK_GID=$(stat -c '%g' /var/run/docker.sock)
    # dev ユーザーが docker.sock にアクセスできるようにする
    if ! id -nG dev | grep -qw "$(getent group "$SOCK_GID" | cut -d: -f1 2>/dev/null)"; then
        groupadd -g "$SOCK_GID" -o docker-host 2>/dev/null || true
        usermod -aG docker-host dev 2>/dev/null || true
    fi
fi

# SSH サーバーを起動
exec /usr/sbin/sshd -D
