#!/usr/bin/env bash
# Installs a pinned kubeconform release after checking its checksum.
# Input env: KUBECONFORM_VERSION, KUBECONFORM_SHA256 (linux-amd64 tarball).
set -euo pipefail

archive="$(mktemp)"
curl -sSfL -o "$archive" \
  "https://github.com/yannh/kubeconform/releases/download/${KUBECONFORM_VERSION}/kubeconform-linux-amd64.tar.gz"
echo "${KUBECONFORM_SHA256}  ${archive}" | sha256sum --check --status
mkdir -p "$HOME/.local/bin"
tar -xzf "$archive" -C "$HOME/.local/bin" kubeconform
echo "$HOME/.local/bin" >> "$GITHUB_PATH"
