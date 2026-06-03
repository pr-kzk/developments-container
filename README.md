# development-env

ホスト PC (Ubuntu 24.04 + rootless Docker) を汚さないために、開発で使うものを全部ひとつのコンテナに閉じ込めた構成。SSH 2222 で入って tmux + Claude Code / Codex / Copilot CLI / 各クラウド CLI を回す。VS Code/Cursor からは Dev Containers 拡張でアタッチもできる。

## 構成

```
.
├── Dockerfile                 # Ubuntu 24.04 + 開発ツール一式
├── compose.yaml               # サービス定義 (rootless Docker 前提)
├── entrypoint.sh              # sshd ホスト鍵生成 + sshd 起動
├── .env                       # DOCKER_SOCK のみ (Linux 1台運用)
├── .devcontainer/
│   └── devcontainer.json      # VS Code Dev Containers 用
├── secrets/                   # 認証情報の bind mount 先 (.gitignore)
│   ├── aws/   azure/   gh/   claude/   codex/   copilot/   databricks/
├── workspace/                 # コード共有 (bind mount, .gitignore)
├── .tmux.conf  .zshrc.custom  # dotfiles
└── developments-container.pub # SSH 公開鍵 (秘密鍵はリポ外)
```

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
- SSH 鍵ペアが用意されていること
  ```sh
  ssh-keygen -t ed25519 -f developments-container -N ''
  # → developments-container (秘密鍵, .gitignore 対象)
  # → developments-container.pub (公開鍵, Dockerfile が COPY する)
  ```

## 初回セットアップ

```sh
# 1. secrets ディレクトリは git clone 後に空で存在しているはず。なければ作る。
mkdir -p secrets/{aws,azure,gh,claude,codex,copilot,databricks}

# 2. 起動
docker compose up -d --build

# 3. 接続
ssh -p 2222 -i developments-container dev@localhost
# → 各種 CLI で auth を通す (claude /login, gh auth login, az login, aws configure sso ...)
```

## 既存コンテナからのマイグレーション (旧 dev-home volume から救出)

以前は `/home/dev` 全体を named volume `dev-home` で覆っていた。そこから認証情報を新 `secrets/` に取り出す:

```sh
docker compose down  # 既存コンテナを停止

# 旧ボリュームから新 bind mount に救出
docker run --rm \
    -v development-env_dev-home:/old:ro \
    -v "$PWD/secrets":/new \
    alpine sh -c '
        for d in .aws .azure .config/gh .claude .codex .copilot .databricks; do
            src=/old/$d
            name=$(basename $d)
            if [ -d "$src" ]; then
                cp -a "$src/." "/new/$name/"
            fi
        done
    '

# sshd のホスト鍵も旧 sshd-keys volume から拾っておくと SSH の警告が出ない
docker run --rm \
    -v development-env_sshd-keys:/old:ro \
    -v development-env_sshd-host-keys:/new \
    alpine sh -c 'cp -a /old/ssh_host_* /new/ 2>/dev/null || true'

# 確認できたら起動
docker compose up -d --build

# 動作確認後、旧 volume は削除して OK
# docker volume rm development-env_dev-home development-env_sshd-keys
```

## VS Code / Cursor から開く

1. VS Code でこのフォルダを開く (`code .`)
2. Dev Containers 拡張: `Dev Containers: Reopen in Container`
3. ターミナルが dev ユーザーで開く。`forwardPorts` の 3000/5173/8000/8080 は自動で localhost に出る
4. CLI 中心の作業は SSH 2222 も並用可能 (両方同じコンテナ)

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

## volume 戦略 (どこに何が永続化されるか)

| マウント | 種別 | 中身 | 消えると |
|---|---|---|---|
| `./workspace` | bind | コード | ホスト側で管理 |
| `./secrets/*` | bind | 各種 auth | ホスト側でバックアップ要 |
| `dev-nvm` | named | nvm/node | 再 DL (~5min) |
| `dev-npm` | named | npm cache | 再 DL |
| `dev-cache` | named | Playwright browsers 等 | 再 DL (重い) |
| `dev-local-share` | named | claude のバージョン群 | 再インストール |
| `dev-ssh` | named | `~/.ssh` (authorized_keys は Dockerfile から再投入) | 公開鍵だけ再投入 |
| `sshd-host-keys` | named | sshd のホスト鍵 | SSH known_hosts 警告が出る |

**`./secrets` は絶対に git add しない** (`.gitignore` 済みだが念のため確認)。

## トラブルシュート

- **VS Code が rootful docker を探しに行く**: ホストで `echo $DOCKER_HOST` を確認。空なら `.bashrc/.zshrc` に export 追加。
- **SSH 接続で "REMOTE HOST IDENTIFICATION HAS CHANGED"**: ホスト鍵が変わった (volume を消した等)。`ssh-keygen -R "[localhost]:2222"` で known_hosts から削除して再接続。
- **`docker.sock` 書き込み権限エラー**: rootless なら通るはず。rootful 運用なら `.env` の `DOCKER_GID` をコメントアウト解除し、`compose.yaml` の `group_add` も有効化。
- **`./secrets/aws` 等が root 所有で書けない**: rootless docker で初回作成すると UID 1000 になるはずだが、もし違ったら `sudo chown -R $(id -u):$(id -g) secrets/`。
