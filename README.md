# development-env

ホスト PC (Ubuntu 24.04 + rootless Docker) を汚さないために、開発で使うものを全部ひとつのコンテナに閉じ込めた構成。SSH 2222 で入って tmux + Claude Code / Codex / Copilot CLI / 各クラウド CLI を回す。VS Code/Cursor からは Dev Containers 拡張でアタッチもできる。

Docker は **DinD (Docker-in-Docker)** で内側に閉じ込めており、ホストの `docker.sock` は一切共有しない。dev-env 内で起動するコンテナ・イメージ・ボリュームはホストと完全に分離される。ホスト側が rootless docker なので、中の dockerd が privileged で動いても実体は host の通常ユーザに留まる。

**初回も `docker compose up -d --build` だけ**で動く設計 (SSH 鍵は entrypoint が初回に自動生成、認証ディレクトリは bind mount が自動作成)。

## 構成

```
.
├── Dockerfile                 # Ubuntu 26.04 LTS + 開発ツール一式
├── compose.yaml               # dind + dev-env の 2 サービス
├── entrypoint.sh              # sshd 鍵生成 + SSH クライアント鍵生成 + sshd 起動
├── .devcontainer/
│   └── devcontainer.json      # VS Code Dev Containers 用
├── secrets/                   # ホストに bind mount される一式 (.gitignore)
│   ├── aws/  azure/  gh/  claude/  codex/  copilot/  databricks/
│   └── ssh-key/               # 初回 up で entrypoint が生成
│       ├── dev-container        # 秘密鍵 (ホストから SSH に使う)
│       └── dev-container.pub    # 公開鍵
├── workspace/                 # コード共有 (bind mount, .gitignore)
└── .tmux.conf  .zshrc.custom  # dotfiles
```

## アーキテクチャ

```
host (rootless Docker)
  └─ compose
      ├─ dind   : docker:29-dind  (privileged, 内側 dockerd を起動 — ホスト rootless 配下なので安全)
      │            ├─ /certs        (TLS 証明書: dind-certs volume)
      │            ├─ /var/lib/docker (永続: dind-data volume)
      │            └─ ports: 2222:22 ほか
      └─ dev-env : 作業用コンテナ
                   ├─ network_mode: service:dind  (netns 共有)
                   ├─ DOCKER_HOST=tcp://localhost:2376 + TLS
                   └─ /certs (read-only) ← dind-certs
```

netns を共有しているため、

- ホスト → `localhost:2222` で SSH (dev-env の sshd に届く)
- dev-env で `docker run -p 3000:3000 ...` した inner container は dind コンテナの :3000 で listen される → ホストに公開したい場合は `compose.yaml` の `dind.ports` に追加する

## 前提

- ホストが rootless Docker で動いていること
  ```sh
  systemctl --user is-active docker  # active
  docker info | grep rootless        # rootless が出る
  ```
- ホストのシェルで `DOCKER_HOST` が設定されていること (VS Code が rootful を探さないように)
  ```sh
  # ~/.bashrc または ~/.zshrc に
  export DOCKER_HOST=unix:///run/user/$(id -u)/docker.sock
  ```

## 初回セットアップ

```sh
# 起動 (初回は dind の image pull + TLS 証明書生成 + SSH 鍵生成で 30 秒程度)
docker compose up -d --build

# 生成された秘密鍵で接続
ssh -p 2222 -i secrets/ssh-key/dev-container dev@localhost
# → 各種 CLI で auth を通す (claude /login, gh auth login, az login, aws configure sso ...)

# (任意) dev-env 内で docker が通っているか確認
ssh -p 2222 -i secrets/ssh-key/dev-container dev@localhost docker info
```

databricks の config は `secrets/databricks/config` (`DATABRICKS_CONFIG_FILE` で参照)。

### git の global config はホストと共有する

ホストの `~/.config/git` を **read-only** で `/home/dev/.config/git` にマウントしているので、
ホストとコンテナが同じ 1 ファイルを見る。alias や user.name を片方で編集すれば即両方に反映される。

前提として、ホスト側は XDG パスを実体にしておく (初回のみ):

```sh
mkdir -p ~/.config/git
mv ~/.gitconfig ~/.config/git/config
ln -s "$HOME/.config/git/config" ~/.gitconfig   # 旧パス参照の互換用
```

注意点:

- **コンテナ内で `git config --global` は使えない** (read-only)。編集はホスト側で行う。
- read-only は必須。書き込み可にすると entrypoint の `chown` でホスト側 `~/.config/git` の
  所有者が subuid (100999) に書き換わり、ホストから sudo なしで編集できなくなる。
- credential helper に `gh auth git-credential` を使っている場合、コンテナ内の `gh` も
  同じ `/usr/bin/gh` にあるためパスがそのまま通る (認証情報自体は `secrets/gh/` 側)。

## 旧構成からの移行

### DooD → DinD (`/var/run/docker.sock` 共有していた頃)

ホスト docker と中の docker が分離されるので、**dev-env 内で過去に build したイメージ・コンテナ・ボリュームはホストに残ったまま見えなくなる**。必要なら旧構成のままで `docker save` 等で持ち出してから移行する。

### 単独ファイル mount + repo-root の SSH 鍵だった頃

```sh
# git config: secrets/gitconfig → secrets/git/config
mkdir -p secrets/git
[ -f secrets/gitconfig ] && mv secrets/gitconfig secrets/git/config

# databricks config: secrets/databrickscfg → secrets/databricks/config
[ -f secrets/databrickscfg ] && mv secrets/databrickscfg secrets/databricks/config

# SSH 鍵: ./dev-container* → secrets/ssh-key/
mkdir -p secrets/ssh-key
[ -f dev-container ]     && mv dev-container     secrets/ssh-key/
[ -f dev-container.pub ] && mv dev-container.pub secrets/ssh-key/

# 再起動 (鍵を引き継いだので known_hosts も生きたまま)
docker compose down && docker compose up -d --build
```

`secrets/ssh-key/` を空のまま `up` すると entrypoint が新しい ed25519 を生成する。

### さらに古い `dev-home` named volume 時代

```sh
docker compose down

docker run --rm \
    -v development-env_dev-home:/old:ro \
    -v "$PWD/secrets":/new \
    alpine sh -c '
        for d in .aws .azure .config/gh .claude .codex .copilot .databricks; do
            src=/old/$d
            name=$(basename $d); name=${name#.}
            [ -d "$src" ] && cp -a "$src/." "/new/$name/" && echo "ok: $d -> /new/$name/"
        done
        mkdir -p /new/git
        [ -f /old/.gitconfig ]     && cp -a /old/.gitconfig     /new/git/config        && echo "ok: .gitconfig"
        [ -f /old/.databrickscfg ] && cp -a /old/.databrickscfg /new/databricks/config && echo "ok: .databrickscfg"
    '

docker volume create development-env_sshd-host-keys >/dev/null
docker run --rm \
    -v development-env_sshd-keys:/old:ro \
    -v development-env_sshd-host-keys:/new \
    alpine sh -c 'cp -a /old/ssh_host_* /new/ 2>/dev/null || true'

docker compose up -d --build
```

## VS Code / Cursor から開く

1. VS Code でこのフォルダを開く (`code .`)
2. Dev Containers 拡張: `Dev Containers: Reopen in Container`
3. ターミナルが dev ユーザーで開く
4. CLI 中心の作業は SSH 2222 も並用可能 (両方同じコンテナ)

inner container が listen するポートをホストに出したい場合は `compose.yaml` の `dind.ports` に追記して `docker compose up -d` で反映。

## CLI 更新ポリシー

Dockerfile に焼いてあるのは **初期インストールだけ**。以下は更新が頻繁なので、dev ユーザーで手動更新する想定:

| ツール | 更新方法 |
|---|---|
| Claude Code | `curl -fsSL https://claude.ai/install.sh \| bash` |
| Codex | `npm i -g @openai/codex@latest` |
| GitHub Copilot CLI | (Dockerfile 未収録、必要なら手動で `~/.local/bin/` に配置) |
| Azure CLI | `sudo az upgrade` |
| Azure Functions Core Tools | `sudo apt-get update && sudo apt-get install -y azure-functions-core-tools-4` |
| AWS CLI | 公式 zip を再展開 |
| Terraform | `sudo apt-get update && sudo apt-get install -y terraform` |
| pnpm | `npm i -g pnpm@latest` |

イメージ全体を作り直したいときは:

```sh
docker compose build --pull --no-cache && docker compose up -d
```

nvm は `releases/latest` を動的解決してビルドしているので `--no-cache` で常にビルド時点の最新が入る。

## volume 戦略 (どこに何が永続化されるか)

| マウント | 種別 | 中身 | 消えると |
|---|---|---|---|
| `./workspace` | bind | コード | ホスト側で管理 |
| `./secrets/*` | bind | 各種 auth + SSH 鍵 | ホスト側でバックアップ要 |
| `dind-certs` | named | DinD の TLS 証明書 | 次回起動で再生成 |
| `dind-data` | named | dev-env 内の docker image/container/volume 全部 | **全部消える** (再ビルド・再 pull) |
| `dev-nvm` | named | nvm/node | 再 DL (~5min) |
| `dev-npm` | named | npm cache | 再 DL |
| `dev-cache` | named | Playwright browsers 等 | 再 DL (重い) |
| `dev-local-share` | named | claude のバージョン群 | 再インストール |
| `dev-ssh` | named | `~/.ssh` (authorized_keys は entrypoint が毎回再投入) | 何もしなくて OK |
| `sshd-host-keys` | named | sshd のホスト鍵 | SSH known_hosts 警告が出る |

**`./secrets` は絶対に git add しない** (`.gitignore` 済みだが念のため確認)。

## UID マッピング (rootless docker)

ホストが rootless docker なので、UID はそのまま素通しにならず user namespace でずれる。

| ホスト | コンテナ内 |
|---|---|
| `kz` (1000) | `root` (0) |
| 100999 (kz の subuid) | `dev` (1000) |

**ホスト uid 1000 がコンテナ内 uid 0 にマップされる 1 点だけが固定**で、それ以外は subuid 領域 (100000+) に飛ぶ。つまりホストとコンテナで所有権が一致する UID は 0 しか存在しない。

この結果、ホスト側で作った `./secrets/*` や `./workspace` はコンテナ内では `root:root 755` に見え、`dev` (uid 1000) から書き込めない。`entrypoint.sh` が起動時にこれらを `dev` へ `chown -R` して解消している (トップの所有者が既に `dev` ならスキップするので 2 回目以降はノーコスト)。

副作用として、**ホスト側では `./secrets/*` と `./workspace` が uid 100999 所有になり、ホストから直接編集するには `sudo` が要る**。編集は基本コンテナ内 (SSH / VS Code Remote) から行う前提。

`./secrets/ssh-key` だけは chown 対象外にしてある。ホストから秘密鍵を読めないと SSH でコンテナに入れなくなるため、ホストユーザー所有のまま残す必要がある。

なお rootless では回避策が使えないことを確認済み:

- `--mount type=bind,...,idmap` (id-mapped mount) → `invalid mode: idmap` で非対応
- `/etc/subuid` の細工 → ホスト全体の rootless コンテナに影響し順序依存で壊れやすい
- 共有グループ方式 → ホスト側の umask が 022 だとホストで新規作成したファイルがコンテナから書けず破綻

ホストが **rootful** docker なら UID が素通しになり (ホスト 1000 = コンテナ 1000)、この chown は不要になる。環境を判定するには:

```bash
docker info -f '{{.SecurityOptions}}'   # name=rootless があれば rootless
mkdir -p /tmp/uidtest && docker run --rm -v /tmp/uidtest:/t alpine stat -c '%u:%g' /t
# → 0:0 なら rootless、1000:1000 なら rootful
```

## トラブルシュート

- **VS Code が rootful docker を探しに行く**: ホストで `echo $DOCKER_HOST` を確認。空なら `.bashrc/.zshrc` に export 追加。
- **SSH 接続で "REMOTE HOST IDENTIFICATION HAS CHANGED"**: ホスト鍵が変わった (volume を消した等)。`ssh-keygen -R "[localhost]:2222"` で known_hosts から削除して再接続。
- **`Permission denied (publickey)` で SSH できない**: `secrets/ssh-key/dev-container` が無ければ起動失敗。`docker compose logs dev-env` で `Generated new SSH keypair` ログを確認。あるのに失敗するなら、鍵の owner/mode を確認 (private は 600、ホストの自分が読める owner)。
- **dev-env 内で `docker info` が `Cannot connect to the Docker daemon`**: dind がまだ起動中 (TLS 証明書生成や ipv6 が遅い等)。`docker compose logs dind` で `API listen on [::]:2376` が出るまで待つ。30 秒経っても出なければ healthcheck (`docker compose ps`) を確認。
- **inner container のポートにホストから繋がらない**: `compose.yaml` の `dind.ports` にそのポートを追加して `docker compose up -d` で反映。`network_mode: service:dind` の都合で dev-env 側に `ports:` を書いても無視される。
- **コンテナ内で `~/.claude` や `~/.aws` が空・書き込めない**: bind mount 元の所有者がコンテナ内で `root` に見えている。`entrypoint.sh` の chown が効いていないので `docker compose logs dev-env` で `Fixing ownership of ...` が出ているか確認。詳細は [UID マッピング](#uid-マッピング-rootless-docker) 参照。ホスト側で `sudo chown -R $(id -u):$(id -g) secrets/` を実行すると**この問題が再発する**ので注意 (コンテナから書けなくなる)。
- **ホストから `./secrets/*` や `./workspace` を編集できない**: 仕様。uid 100999 所有になっているため `sudo` が必要。通常はコンテナ内から編集する。
- **dind のイメージ/ボリュームを綺麗にしたい**: `docker compose down && docker volume rm development-env_dind-data` で `/var/lib/docker` ごと消える。次回起動で空から始まる。
