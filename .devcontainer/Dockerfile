FROM ruby:3.2

# Install basic development tools
RUN apt-get update && apt-get install -y \
    git \
    curl \
    build-essential \
    && rm -rf /var/lib/apt/lists/*

# Create non-root user
RUN useradd -ms /bin/bash vscode

# Set working directory
WORKDIR /workspace

# Switch to non-root user
USER vscode
