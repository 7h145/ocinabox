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
    curl \
    entr \
    fd-find \
    fzf \
    gh \
    git \
    jq \
    less \
    make \
    man-db \
    ripgrep \
    tree \
    yq

# languages/compiler/interpreter
RUN true \
  && apt-get install -y --no-install-recommends \
    lua5.1 \
    python3 \
    python3-pip \
    python3-venv

RUN true \
  && apt-get -y remove --purge --auto-remove && apt-get -y clean \
  && rm -rf /var/lib/apt/lists/*


FROM base AS payload

# invalidate the build cache on payload version change
ARG PAYLOAD="opencode-ai"
ARG PAYLOADVERSION

ENV WORKDIR='/stage'
RUN mkdir $WORKDIR
WORKDIR $WORKDIR

RUN true \
  && echo "payload: ${PAYLOAD}${PAYLOADVERSION:+@${PAYLOADVERSION}}" \
  && npm install -g "${PAYLOAD}${PAYLOADVERSION:+@${PAYLOADVERSION}}" \
  && npm cache clean --force

# opencode uses a random port by default; a fixed port is needed for
# '--publish' or 'EXPOSE', which may be necessary for authorization
# callbacks or client/server mode.  Not done for now: this will hinder
# normal command line operation without proper 'ENTRYPOINT' wrapper.
#ENTRYPOINT [ "/usr/local/bin/opencode", "--hostname", "0.0.0.0", "--port", "47817" ]
#EXPOSE 47817/tcp

ENTRYPOINT [ "/usr/local/bin/opencode" ]
#CMD ["--agent", "Plan"]

VOLUME $WORKDIR

