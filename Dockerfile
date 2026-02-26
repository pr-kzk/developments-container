FROM ubuntu:24.04

# ------------------------------------------------------------------ #
# 1. 基本パッケージ + DinD 必須ツール
# ------------------------------------------------------------------ #
ENV DEBIAN_FRONTEND=noninteractive

RUN apt-get update && apt-get install -y --no-install-recommends \
    # DinD 必須
    ca-certificates \
    curl \
    gnupg \
    iproute2 \
    fuse-overlayfs \
    slirp4netns \
    iptables \
    kmod \
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
    lsb-release \
    && rm -rf /var/lib/apt/lists/*

# ------------------------------------------------------------------ #
# 2. Docker Engine をインストール
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
        docker-ce \
        docker-ce-cli \
        containerd.io \
        docker-buildx-plugin \
        docker-compose-plugin \
    && rm -rf /var/lib/apt/lists/*

# ------------------------------------------------------------------ #
# 3. Docker rootless extras（rootlesskit, vpnkit）
# ------------------------------------------------------------------ #
RUN set -eux; \
    dpkgArch="$(dpkg --print-architecture)"; \
    case "$dpkgArch" in \
        'amd64')  url='https://download.docker.com/linux/static/stable/x86_64/docker-rootless-extras-29.2.1.tgz' ;; \
        'arm64')  url='https://download.docker.com/linux/static/stable/aarch64/docker-rootless-extras-29.2.1.tgz' ;; \
        *) echo >&2 "error: unsupported architecture ($dpkgArch)"; exit 1 ;; \
    esac; \
    wget -O rootless.tgz "$url"; \
    tar --extract \
        --file rootless.tgz \
        --strip-components 1 \
        --directory /usr/local/bin/ \
        'docker-rootless-extras/rootlesskit' \
        'docker-rootless-extras/vpnkit'; \
    rm rootless.tgz; \
    rootlesskit --version; \
    vpnkit --version

# ------------------------------------------------------------------ #
# 4. Terraform
# ------------------------------------------------------------------ #
RUN wget -qO- https://apt.releases.hashicorp.com/gpg | \
        gpg --dearmor | tee /usr/share/keyrings/hashicorp-archive-keyring.gpg > /dev/null && \
    echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/hashicorp-archive-keyring.gpg] \
        https://apt.releases.hashicorp.com $(lsb_release -cs) main" | \
        tee /etc/apt/sources.list.d/hashicorp.list && \
    apt-get update && apt-get install -y --no-install-recommends terraform && \
    rm -rf /var/lib/apt/lists/*

# ------------------------------------------------------------------ #
# 5. Cloud CLI ツール
# ------------------------------------------------------------------ #
RUN curl -sL https://aka.ms/InstallAzureCLIDeb | bash && \
    curl -fsSL https://raw.githubusercontent.com/databricks/setup-cli/main/install.sh | sh

# ------------------------------------------------------------------ #
# 6. XDG_RUNTIME_DIR / SSH ディレクトリの準備
# ------------------------------------------------------------------ #
RUN mkdir -p /run/user && chmod 1777 /run/user && \
    mkdir -p /run/sshd && \
    curl -fsSL https://astral.sh/uv/install.sh -o /tmp/uv-install.sh

# ------------------------------------------------------------------ #
# 7. dev ユーザーを作成
# ------------------------------------------------------------------ #
RUN usermod -l dev -d /home/dev -m ubuntu && \
    groupmod -n dev ubuntu && \
    usermod -s /bin/zsh dev && \
    echo "dev ALL=(ALL) NOPASSWD:ALL" >> /etc/sudoers && \
    echo 'dev:100000:65536' >> /etc/subuid && \
    echo 'dev:100000:65536' >> /etc/subgid && \
    usermod -aG docker dev && \
    mkdir -p /home/dev/.ssh

# SSH 公開鍵
COPY dev-container.pub /home/dev/.ssh/authorized_keys
RUN chown -R dev:dev /home/dev/.ssh && \
    chmod 700 /home/dev/.ssh && \
    chmod 600 /home/dev/.ssh/authorized_keys

# rootless Docker 用データディレクトリ
RUN mkdir -p /home/dev/.local/share/docker && \
    mkdir -p /home/dev/.local/bin && \
    chown -R dev:dev /home/dev/.local

VOLUME /home/dev/.local/share/docker

# ------------------------------------------------------------------ #
# 8. dev ユーザー固有ツールをインストール
# ------------------------------------------------------------------ #
USER dev

ENV SHELL=/bin/zsh \
    BASH_ENV=/home/dev/.bash_env \
    XDG_RUNTIME_DIR=/run/user/1000 \
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

# .zshrc に BASH_ENV をソース
RUN echo '. "/home/dev/.bash_env"' >> ~/.zshrc

# ------------------------------------------------------------------ #
# 9. エントリポイント
# ------------------------------------------------------------------ #
USER root

# dockerd を起動しつつ SSH サーバーも起動するエントリポイント
COPY entrypoint.sh /usr/local/bin/entrypoint.sh
RUN chmod +x /usr/local/bin/entrypoint.sh

EXPOSE 22 2375 2376

CMD ["/usr/local/bin/entrypoint.sh"]
