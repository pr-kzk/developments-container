#!/bin/bash
set -e

# ------------------------------------------------------------------ #
# マウント済みディレクトリの所有者を dev に揃える
#
# ホストは rootless docker なので、ホスト側で作った bind mount 元 (./secrets/*,
# ./workspace) はコンテナ内では root:root に見え、dev から書き込めない。
# named volume も初回は root 所有で作られる。ここで dev に chown して解消する。
# ホスト側では uid 100999 (kz の subuid) 所有になるため、ホストから直接編集する
# には sudo が必要になる。
#
# トップの所有者が既に dev なら何もしない (2 回目以降のコストを避ける)
#
# 注: /home/dev/.config/git は対象に含めない。ホストの ~/.config/git を read-only で
# マウントしており、chown すると失敗して起動できなくなる (かつ本来 chown してはいけない)。
# ------------------------------------------------------------------ #
DEV_UID=$(id -u dev)

for d in \
    /home/dev/.aws \
    /home/dev/.azure \
    /home/dev/.claude \
    /home/dev/.codex \
    /home/dev/.copilot \
    /home/dev/.databricks \
    /home/dev/.config/gh \
    /home/dev/.cache \
    /home/dev/.local/share \
    /home/dev/.npm \
    /home/dev/.nvm \
    /home/dev/workspace \
; do
    if [ -d "$d" ] && [ "$(stat -c %u "$d")" != "$DEV_UID" ]; then
        echo "Fixing ownership of $d"
        chown -R dev:dev "$d"
    fi
done

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
