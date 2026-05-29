# syntax=docker/dockerfile:1
# copyright 2025 <github.attic@typedef.net>, CC BY 4.0

FROM node:current-trixie-slim AS base

ARG TZ="Europe/Berlin"
ENV TZ=${TZ}

RUN true \
  && echo 'debconf debconf/frontend select Noninteractive' |debconf-set-selections \
  && dpkg-reconfigure --frontend noninteractive debconf \
  && apt-get update && apt-get -y upgrade \
  && apt-get install -y --no-install-recommends \
    ca-certificates \
    iproute2 \
    procps

# basic tooling
RUN true \
  && apt-get install -y --no-install-recommends \
    bat \
    curl \
    entr \
    fd-find \
    file \
    fzf \
    gh \
    git \
    jq \
    less \
    make \
    man-db \
    pkgconf \
    ripgrep \
    sqlite3 \
    tree \
    yq \
    zip unzip

# additional tooling, YMMV
RUN true \
  && apt-get install -y --no-install-recommends \
    bind9-dnsutils \
    build-essential \
    git-lfs \
    iputils-ping \
    lsof \
    netcat-openbsd \
    openssh-client \
    rsync \
    socat \
    strace \
    tmux

# interactive tooling
RUN true \
  && apt-get install -y --no-install-recommends \
    vim

# languages/compilers/interpreters
RUN true \
  && apt-get install -y --no-install-recommends \
    lua5.1 \
    pipx \
    python3 \
    python3-pip \
    python3-venv

# https://docs.astral.sh/uv/
ENV PATH=${PATH}:/root/.local/bin
RUN true \
  && pipx install uv

# agents tend to have expectations
RUN true \
  && ln -sf /usr/bin/python3 /usr/local/bin/python \
  && ln -sf /usr/bin/fdfind /usr/local/bin/fd \
  && ln -sf /usr/bin/batcat /usr/local/bin/bat

RUN true \
  && apt-get -y remove --purge --auto-remove && apt-get -y clean \
  && rm -rf /var/lib/apt/lists/*


FROM base AS payload

# invalidate the build cache on payload version change
ARG PAYLOAD="opencode-ai"
ARG PAYLOADVERSION

# there can be only one $EDITOR
ARG EDITOR="vim"
ENV EDITOR=${EDITOR}

ENV WORKDIR="/stage"
WORKDIR $WORKDIR

RUN true \
  && echo "payload: ${PAYLOAD}${PAYLOADVERSION:+@${PAYLOADVERSION}}" \
  && npm install -g "${PAYLOAD}${PAYLOADVERSION:+@${PAYLOADVERSION}}" \
  && npm cache clean --force

ENTRYPOINT [ "/usr/local/bin/opencode" ]
#CMD ["--agent", "Plan"]

VOLUME $WORKDIR

