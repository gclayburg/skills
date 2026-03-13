FROM docker/sandbox-templates:claude-code

USER root

# parallel needed for faster bats-core testing
RUN apt-get update && apt-get install -y \
    parallel \
    && rm -rf /var/lib/apt/lists/*

USER agent
