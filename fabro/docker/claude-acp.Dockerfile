# Image for Fabro ACP agent stages backed by Claude Code.
#
# Contains no credentials. Auth is injected at run time as CLAUDE_CODE_OAUTH_TOKEN
# from the Fabro secret vault; see .fabro/workflows/*/workflow.toml.
#
# Build:  docker build -t fabro-claude-acp:1 -f .fabro/docker/claude-acp.Dockerfile .

FROM buildpack-deps:noble

# @agentclientprotocol/claude-agent-acp requires node >= 22.
RUN curl -fsSL https://deb.nodesource.com/setup_22.x | bash - \
    && apt-get install -y --no-install-recommends nodejs \
    && rm -rf /var/lib/apt/lists/*

RUN npm i -g @agentclientprotocol/claude-agent-acp@0.65.0 \
    && npm cache clean --force

RUN claude-agent-acp --version
