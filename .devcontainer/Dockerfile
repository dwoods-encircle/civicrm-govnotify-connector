FROM mcr.microsoft.com/devcontainers/base:ubuntu

ARG DEBIAN_FRONTEND=noninteractive

RUN apt-get update && apt-get install -y --no-install-recommends \
  git unzip zip curl mariadb-client \
  && rm -rf /var/lib/apt/lists/*

# Composer (runs fine in workspace container even if PHP runtime is separate)
RUN curl -sS https://getcomposer.org/installer | php -- --install-dir=/usr/local/bin --filename=composer || true
