#!/bin/bash
set -e

# cgroup v2 対応
if [ -f /sys/fs/cgroup/cgroup.controllers ]; then
    mkdir -p /sys/fs/cgroup/init
    xargs -rn1 < /sys/fs/cgroup/cgroup.controllers \
        printf '+%s\n' > /sys/fs/cgroup/cgroup.subtree_control 2>/dev/null || true
fi

# iptables レガシーモードに切り替え（コンテナ内での互換性確保）
update-alternatives --set iptables /usr/sbin/iptables-legacy 2>/dev/null || true
update-alternatives --set ip6tables /usr/sbin/ip6tables-legacy 2>/dev/null || true

# dockerd をバックグラウンドで起動
dockerd \
    --host=unix:///var/run/docker.sock \
    --host=tcp://0.0.0.0:2375 \
    --tls=false \
    &

# dockerd が起動するまで待機
echo "Waiting for Docker daemon..."
timeout 30 sh -c 'until docker info >/dev/null 2>&1; do sleep 0.5; done'
echo "Docker daemon started."

# SSH サーバーを起動
exec /usr/sbin/sshd -D
