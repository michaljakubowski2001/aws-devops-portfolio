#!/usr/bin/env bash
set -euo pipefail
# GitHub-hosted Ubuntu x86_64 runner; install the fixed vendor release.
version=1.2.835.0
curl --fail --silent --show-error --retry 3 \
  "https://s3.amazonaws.com/session-manager-downloads/plugin/$version/ubuntu_64bit/session-manager-plugin.deb" \
  --output /tmp/portfolio-session-manager-plugin.deb
sudo dpkg -i /tmp/portfolio-session-manager-plugin.deb
session-manager-plugin --version
