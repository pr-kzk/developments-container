FROM ubuntu:24.04

# ------------------------------------------------------------------ #
# 1. 基本パッケージ
# ------------------------------------------------------------------ #
ENV DEBIAN_FRONTEND=noninteractive

RUN apt-get update && apt-get install -y --no-install-recommends \
    ca-certificates \
    curl \
    gnupg \
    # 開発ツール
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
    tmux \
    nano \
    zip \
    lsb-release \
    && rm -rf /var/lib/apt/lists/*

# ------------------------------------------------------------------ #
# 2. Docker CLI + Buildx のみ（daemon は不要）
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
# 4. Cloud CLI ツール
# ------------------------------------------------------------------ #
RUN curl -sL https://aka.ms/InstallAzureCLIDeb | bash && \
    curl -fsSL https://raw.githubusercontent.com/databricks/setup-cli/main/install.sh | sh && \
    curl "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "awscliv2.zip" && \
    unzip awscliv2.zip && \
    ./aws/install && \
    rm -rf awscliv2.zip aws/

# ------------------------------------------------------------------ #
# 5. peco
# ------------------------------------------------------------------ #
RUN curl -fsSL https://github.com/peco/peco/releases/download/v0.6.0/peco_0.6.0_linux_amd64.tar.gz | \
    tar xzf - -C /usr/local/bin peco

# ------------------------------------------------------------------ #
# 6. SSH ディレクトリの準備
# ------------------------------------------------------------------ #
RUN mkdir -p /run/sshd && \
    curl -fsSL https://astral.sh/uv/install.sh -o /tmp/uv-install.sh

# ------------------------------------------------------------------ #
# 6. dev ユーザーを作成
# ------------------------------------------------------------------ #
RUN usermod -l dev -d /home/dev -m ubuntu && \
    groupmod -n dev ubuntu && \
    usermod -s /bin/zsh dev && \
    echo "dev ALL=(ALL) NOPASSWD:ALL" >> /etc/sudoers && \
    mkdir -p /home/dev/.ssh

# Docker ソケットへのアクセス権を付与
# ホストの docker グループGID に合わせる（compose.yaml の group_add で対応）

# SSH 公開鍵
COPY developments-container.pub /home/dev/.ssh/authorized_keys
RUN chown -R dev:dev /home/dev/.ssh && \
    chmod 700 /home/dev/.ssh && \
    chmod 600 /home/dev/.ssh/authorized_keys

# ------------------------------------------------------------------ #
# 7. dev ユーザー固有ツールをインストール
# ------------------------------------------------------------------ #
USER dev

ENV SHELL=/bin/zsh \
    BASH_ENV=/home/dev/.bash_env \
    PATH="/home/dev/.local/bin:/home/dev/.nvm/bin:${PATH}"

RUN touch "${BASH_ENV}"

# nvm + Node.js
RUN curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/v0.40.3/install.sh | \
        PROFILE="${BASH_ENV}" bash && \
    bash -c 'source "${BASH_ENV}" && nvm install node'

# uv
RUN sh /tmp/uv-install.sh

# oh-my-zsh
RUN sh -c "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)" "" --unattended

# Claude Code
RUN curl -fsSL https://claude.ai/install.sh | bash

# OpenAI Codex
RUN bash -c 'source "${BASH_ENV}" && npm i -g @openai/codex'

# tmux 設定
COPY --chown=dev:dev .tmux.conf /home/dev/.tmux.conf

# カスタム zshrc
COPY --chown=dev:dev .zshrc.custom /home/dev/.zshrc.custom

# .zshrc に BASH_ENV とカスタム設定をソース
RUN echo '. "/home/dev/.bash_env"' >> ~/.zshrc && \
    echo '. "/home/dev/.zshrc.custom"' >> ~/.zshrc

# ------------------------------------------------------------------ #
# 8. エントリポイント
# ------------------------------------------------------------------ #
USER root

COPY entrypoint.sh /usr/local/bin/entrypoint.sh
RUN chmod +x /usr/local/bin/entrypoint.sh

EXPOSE 22

CMD ["/usr/local/bin/entrypoint.sh"]
