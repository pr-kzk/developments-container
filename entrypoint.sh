#!/bin/bash
set -e

# ------------------------------------------------------------------ #
# sshd ホスト鍵を永続ボリュームに生成 (初回のみ)
# ------------------------------------------------------------------ #
HOST_KEYS_DIR=/etc/ssh/host_keys
mkdir -p "$HOST_KEYS_DIR"
for type in rsa ecdsa ed25519; do
    key="$HOST_KEYS_DIR/ssh_host_${type}_key"
    if [ ! -f "$key" ]; then
        ssh-keygen -q -N '' -t "$type" -f "$key"
    fi
done

# ------------------------------------------------------------------ #
# クライアント用 SSH 鍵 (ホストに bind mount された ./secrets/ssh-key/)
# 無ければ ed25519 を生成 → 起動毎に authorized_keys を再投入する
# ------------------------------------------------------------------ #
SSH_KEY_DIR=/home/dev/.ssh-key
mkdir -p "$SSH_KEY_DIR"
chmod 700 "$SSH_KEY_DIR"

PRIV_KEY="$SSH_KEY_DIR/dev-container"
PUB_KEY="$SSH_KEY_DIR/dev-container.pub"

if [ ! -f "$PRIV_KEY" ]; then
    ssh-keygen -q -N '' -t ed25519 -f "$PRIV_KEY" -C "dev-env"
    chmod 600 "$PRIV_KEY"
    chmod 644 "$PUB_KEY"
    echo "Generated new SSH keypair at ./secrets/ssh-key/dev-container{,.pub}"
fi

mkdir -p /home/dev/.ssh
chown dev:dev /home/dev/.ssh
chmod 700 /home/dev/.ssh
install -m 600 -o dev -g dev "$PUB_KEY" /home/dev/.ssh/authorized_keys

exec /usr/sbin/sshd -D -e
