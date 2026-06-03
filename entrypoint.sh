#!/bin/bash
set -e

# sshd ホスト鍵を永続ボリュームに生成 (初回のみ)
HOST_KEYS_DIR=/etc/ssh/host_keys
mkdir -p "$HOST_KEYS_DIR"
for type in rsa ecdsa ed25519; do
    key="$HOST_KEYS_DIR/ssh_host_${type}_key"
    if [ ! -f "$key" ]; then
        ssh-keygen -q -N '' -t "$type" -f "$key"
    fi
done

# ホストの docker.sock を共有している場合、dev ユーザーから書き込めるようにする。
#   - rootful Docker: socket の所有 GID を docker-host グループとしてコンテナ内に作り、
#     dev ユーザーをそのグループに追加。
#   - rootless Docker: user namespace のマッピングで通るため不要だが、害がないので
#     一律に走らせる (GID 0 のときだけスキップ)。
if [ -S /var/run/docker.sock ]; then
    SOCK_GID=$(stat -c '%g' /var/run/docker.sock)
    if [ "$SOCK_GID" != "0" ] && ! id -G dev | grep -qw "$SOCK_GID"; then
        groupadd -g "$SOCK_GID" -o docker-host 2>/dev/null || true
        usermod -aG docker-host dev 2>/dev/null || true
    fi
fi

exec /usr/sbin/sshd -D -e
