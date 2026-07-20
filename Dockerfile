# syntax=docker/dockerfile:1.7
FROM ubuntu:26.04

# ------------------------------------------------------------------ #
# 1. 基本 + 開発ツール (apt)
# ------------------------------------------------------------------ #
ENV DEBIAN_FRONTEND=noninteractive

# 基本ツール + 開発ツール + Playwright/Chromium 用 libs + 日本語/絵文字フォント
RUN apt-get update && apt-get install -y --no-install-recommends \
        ca-certificates \
        curl \
        gnupg \
        openssh-server \
        sudo \
        git \
        wget \
        build-essential \
        zsh \
        gh \
        software-properties-common \
        jq \
        unzip \
        zip \
        tmux \
        nano \
        vim \
        ripgrep \
        poppler-utils \
        lsb-release \
        # Playwright/Chromium 実行に必要な system libs
        libasound2t64 \
        libatk-bridge2.0-0t64 \
        libatk1.0-0t64 \
        libatspi2.0-0t64 \
        libcairo2 \
        libcups2t64 \
        libdbus-1-3 \
        libdrm2 \
        libgbm1 \
        libglib2.0-0t64 \
        libnspr4 \
        libnss3 \
        libpango-1.0-0 \
        libx11-6 \
        libxcb1 \
        libxcomposite1 \
        libxdamage1 \
        libxext6 \
        libxfixes3 \
        libxkbcommon0 \
        libxrandr2 \
        libxshmfence1 \
        xvfb \
        libfontconfig1 \
        libfreetype6 \
        # フォント
        fonts-noto-color-emoji \
        fonts-unifont \
        fonts-liberation \
        fonts-ipafont-gothic \
        fonts-wqy-zenhei \
        fonts-tlwg-loma-otf \
        fonts-freefont-ttf \
        xfonts-cyrillic \
        xfonts-scalable \
    && rm -rf /var/lib/apt/lists/*

# ------------------------------------------------------------------ #
# 2. Docker CLI + Buildx + Compose (daemon は host の DooD)
# ------------------------------------------------------------------ #
RUN install -m 0755 -d /etc/apt/keyrings && \
    curl -fsSL https://download.docker.com/linux/ubuntu/gpg | \
        gpg --dearmor -o /etc/apt/keyrings/docker.gpg && \
    chmod a+r /etc/apt/keyrings/docker.gpg && \
    echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] \
        https://download.docker.com/linux/ubuntu \
        $(. /etc/os-release && echo "$VERSION_CODENAME") stable" | \
        tee /etc/apt/sources.list.d/docker.list && \
    apt-get update && apt-get install -y --no-install-recommends \
        docker-ce-cli \
        docker-buildx-plugin \
        docker-compose-plugin \
    && rm -rf /var/lib/apt/lists/*

# ------------------------------------------------------------------ #
# 3. Terraform
# ------------------------------------------------------------------ #
RUN wget -qO- https://apt.releases.hashicorp.com/gpg | \
        gpg --dearmor | tee /usr/share/keyrings/hashicorp-archive-keyring.gpg > /dev/null && \
    echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/hashicorp-archive-keyring.gpg] \
        https://apt.releases.hashicorp.com $(lsb_release -cs) main" | \
        tee /etc/apt/sources.list.d/hashicorp.list && \
    apt-get update && apt-get install -y --no-install-recommends terraform && \
    rm -rf /var/lib/apt/lists/*

# ------------------------------------------------------------------ #
# 4. Cloud CLI 群 (Azure CLI / Azure Functions Core Tools / Databricks / AWS v2)
# ------------------------------------------------------------------ #
# 注:
#  - azure-cli の apt repo は resolute (26.04) 未提供。未指定だとインストーラが jammy に
#    フォールバックするため、利用可能な最新の noble を DIST_CODE で明示する。
#    (resolute 版が公開されたらこの pin は外す)
#  - インストーラは一度ファイルに落としてから実行する。`curl -sL | bash` だと取得失敗時に
#    空入力を受けた bash が黙って exit 0 し、az 未インストールのままビルドが通ってしまう。
RUN curl -fsSL https://aka.ms/InstallAzureCLIDeb -o /tmp/install-az.sh && \
    DIST_CODE=noble bash /tmp/install-az.sh && \
    rm /tmp/install-az.sh && \
    az version && \
    curl -fsSL https://raw.githubusercontent.com/databricks/setup-cli/main/install.sh | sh && \
    databricks --version && \
    cd /tmp && \
    curl -fsSL "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "awscliv2.zip" && \
    unzip -q awscliv2.zip && \
    ./aws/install && \
    rm -rf /tmp/awscliv2.zip /tmp/aws && \
    aws --version

# Azure Functions Core Tools (Microsoft packages.microsoft.com の apt 経由 / npm 版は node 26 で post-install が壊れる)
# 注:
#  - microsoft-prod repo は resolute (26.04) 版が存在するが azure-functions-core-tools-4 を含まないので noble 固定
#  - 署名鍵は 2025 年に更新されており、古い repo (noble) と新しい repo の両方を検証できるよう 2 鍵を同居させる
RUN curl -fsSL https://packages.microsoft.com/keys/microsoft.asc -o /tmp/microsoft.asc && \
    curl -fsSL https://packages.microsoft.com/keys/microsoft-2025.asc -o /tmp/microsoft-2025.asc && \
    cat /tmp/microsoft.asc /tmp/microsoft-2025.asc | \
        gpg --batch --yes --dearmor -o /etc/apt/keyrings/microsoft.gpg && \
    rm /tmp/microsoft.asc /tmp/microsoft-2025.asc && \
    chmod a+r /etc/apt/keyrings/microsoft.gpg && \
    echo "deb [arch=amd64 signed-by=/etc/apt/keyrings/microsoft.gpg] \
        https://packages.microsoft.com/repos/microsoft-ubuntu-noble-prod noble main" | \
        tee /etc/apt/sources.list.d/microsoft-prod.list && \
    apt-get update && apt-get install -y --no-install-recommends azure-functions-core-tools-4 && \
    rm -rf /var/lib/apt/lists/* && \
    func --version

# ------------------------------------------------------------------ #
# 5. その他 CLI (peco, dbmate)
# ------------------------------------------------------------------ #
RUN curl -fsSL https://github.com/peco/peco/releases/download/v0.6.0/peco_0.6.0_linux_amd64.tar.gz | \
        tar xzf - -C /usr/local/bin peco && \
    curl -fsSL -o /usr/local/bin/dbmate \
        https://github.com/amacneil/dbmate/releases/latest/download/dbmate-linux-amd64 && \
    chmod +x /usr/local/bin/dbmate && \
    peco --version && dbmate --version

# ------------------------------------------------------------------ #
# 6. sshd 設定 (ホスト鍵は entrypoint で生成し /etc/ssh/host_keys に永続化)
# ------------------------------------------------------------------ #
RUN mkdir -p /run/sshd /etc/ssh/sshd_config.d && \
    rm -f /etc/ssh/ssh_host_*

COPY <<'EOF' /etc/ssh/sshd_config.d/99-dev-env.conf
# dev-env 用 sshd 設定 (Dockerfile 管理)
PasswordAuthentication no
PermitRootLogin no
PubkeyAuthentication yes
X11Forwarding no
PrintMotd no
AcceptEnv LANG LC_*

# ホスト鍵は永続ボリュームから読む
HostKey /etc/ssh/host_keys/ssh_host_rsa_key
HostKey /etc/ssh/host_keys/ssh_host_ecdsa_key
HostKey /etc/ssh/host_keys/ssh_host_ed25519_key
EOF

# ------------------------------------------------------------------ #
# 7. dev ユーザー作成 (base image の ubuntu ユーザーを rename)
#
# uid/gid は 1000 のまま。ホストが rootless docker なので、コンテナ内 uid 1000 は
# ホストの subuid (100999) にマップされる。bind mount したホスト側ディレクトリは
# 初期状態ではホストユーザー (= コンテナ内 root) 所有で dev から書けないため、
# entrypoint.sh が起動時に dev へ chown して追従させる。
# ------------------------------------------------------------------ #
#
# sudo 権限は /etc/sudoers 本体に追記せず drop-in で与える。本体を壊すと sudo 全体が
# 使えなくなるため、0440 で配置したうえで visudo -c による構文検証を通す。
RUN usermod -l dev -d /home/dev -m ubuntu && \
    groupmod -n dev ubuntu && \
    usermod -s /bin/zsh dev && \
    echo "dev ALL=(ALL) NOPASSWD:ALL" > /etc/sudoers.d/dev && \
    chmod 0440 /etc/sudoers.d/dev && \
    visudo -c

# 注: authorized_keys は entrypoint.sh が ./secrets/ssh-key/ の公開鍵から毎回展開する
# (鍵自体も初回 up 時に entrypoint が ed25519 で生成する)

# ------------------------------------------------------------------ #
# 8. dev ユーザー固有ツール (nvm/node, pnpm, uv, oh-my-zsh, Claude/Codex/Copilot/AzFunc)
#
# 注: 以降 (および上の CLI 群) で各インストールの直後に --version を叩いているのは
# 導通確認のため。curl | sh 形式のインストーラは、取得内容が空や部分応答でも
# シェルが exit 0 して黙って素通りする (実際に azure-cli で踏んだ)。
# ビルドが通ったのに CLI が入っていない、という状態をここで落とす。
# ------------------------------------------------------------------ #
USER dev

ENV SHELL=/bin/zsh \
    BASH_ENV=/home/dev/.bash_env \
    PATH="/home/dev/.local/bin:/home/dev/.nvm/bin:${PATH}"

RUN touch "${BASH_ENV}"

# nvm + Node.js (どちらもビルド時点の最新)
# nvm のバージョンは releases/latest のリダイレクト先からタグを動的に解決する
RUN NVM_VERSION="$(curl -fsSLI -o /dev/null -w '%{url_effective}' https://github.com/nvm-sh/nvm/releases/latest | sed 's|.*/tag/||')" && \
    echo "Installing nvm ${NVM_VERSION}" && \
    curl -fsSL "https://raw.githubusercontent.com/nvm-sh/nvm/${NVM_VERSION}/install.sh" | \
        PROFILE="${BASH_ENV}" bash && \
    bash -c 'source "${BASH_ENV}" && nvm install node && nvm --version && node -v'

# npm globals (pnpm, OpenAI Codex)
# 注: azure-functions-core-tools は node 26 で post-install が不安定なので Dockerfile では入れない。
# 必要なら `sudo apt install azure-functions-core-tools-4` を README 参照で実行。
RUN bash -c 'source "${BASH_ENV}" && nvm use default && \
        npm i -g pnpm@latest @openai/codex --unsafe-perm true && \
        pnpm -v && codex --version'

# uv (Python)
RUN curl -fsSL https://astral.sh/uv/install.sh | sh && \
    uv --version

# oh-my-zsh
RUN sh -c "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)" "" --unattended && \
    [ -d /home/dev/.oh-my-zsh ]

# Claude Code (公式インストーラ、~/.local/bin/claude)
RUN curl -fsSL https://claude.ai/install.sh | bash && \
    claude --version

# tmux/zsh dotfiles
COPY --chown=dev:dev .tmux.conf /home/dev/.tmux.conf
COPY --chown=dev:dev .zshrc.custom /home/dev/.zshrc.custom

# .zshrc に bash_env と custom 設定をソース (対話シェル用)
RUN echo '. "/home/dev/.bash_env"' >> /home/dev/.zshrc && \
    echo '. "/home/dev/.zshrc.custom"' >> /home/dev/.zshrc

# 非対話 zsh (ssh host 'cmd') でも DOCKER_HOST と PATH が効くように .zshenv で
# /etc/profile.d/dev-env.sh と .bash_env を必ず source する。
# /etc/profile.d/dev-env.sh の中身は root ステージで配置する (後段)。
RUN cat > /home/dev/.zshenv <<'EOF'
[ -r /etc/profile.d/dev-env.sh ] && . /etc/profile.d/dev-env.sh
[ -r /home/dev/.bash_env ]       && . /home/dev/.bash_env
EOF

# ------------------------------------------------------------------ #
# 9. エントリポイント + 全シェル共通 env
# ------------------------------------------------------------------ #
USER root

# DinD への接続情報と dev ユーザ PATH を /etc/profile.d 経由で配る。
# - 対話 login shell: /etc/profile が読む
# - 非対話 zsh: 上で作った ~/.zshenv が読む
COPY <<'EOF' /etc/profile.d/dev-env.sh
# dev-env コンテナ共通環境変数 (Dockerfile 管理)
export DOCKER_HOST=tcp://localhost:2376
export DOCKER_TLS_VERIFY=1
export DOCKER_CERT_PATH=/certs/client
export DATABRICKS_CONFIG_FILE=/home/dev/.databricks/config
export PATH="/home/dev/.local/bin:/home/dev/.nvm/bin:${PATH}"
EOF
RUN chmod 0644 /etc/profile.d/dev-env.sh

COPY entrypoint.sh /usr/local/bin/entrypoint.sh
RUN chmod +x /usr/local/bin/entrypoint.sh

EXPOSE 22

CMD ["/usr/local/bin/entrypoint.sh"]
