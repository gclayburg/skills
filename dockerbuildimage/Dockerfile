FROM debian:bookworm-slim

RUN apt-get update && apt-get install -y \
    jq \
    git \
    curl \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /workspace
