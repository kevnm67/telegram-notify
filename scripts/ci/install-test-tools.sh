#!/usr/bin/env bash
# Install bats-core (pinned release tag) and kcov for the unit-test job.
# bats-core v1.14.0 verified 2026-08-22 from github.com/bats-core/bats-core/releases.
# kcov comes from apt: Ubuntu 22.04 ships kcov 38; 24.04 dropped the package,
# which is why the CI job pins cimg/base:current-22.04.
set -euo pipefail

BATS_VERSION="${BATS_VERSION:-v1.14.0}"
PREFIX="${PREFIX:-/usr/local}"
MINIMAL=false
[[ "${1:-}" == "--minimal" ]] && MINIMAL=true # bats only (Alpine bash:3.2 image: no kcov, no sudo)

if [[ "$MINIMAL" == true ]] && command -v apk >/dev/null; then
    apk add --no-cache git curl >/dev/null
fi

if ! command -v bats >/dev/null; then
    tmp="$(mktemp -d)"
    git clone --quiet --depth 1 --branch "$BATS_VERSION" https://github.com/bats-core/bats-core.git "$tmp/bats-core"
    if command -v sudo >/dev/null; then
        sudo "$tmp/bats-core/install.sh" "$PREFIX" >/dev/null
    else
        "$tmp/bats-core/install.sh" "$PREFIX" >/dev/null
    fi
    rm -rf "$tmp"
fi
echo "bats: $(bats --version)"

if [[ "$MINIMAL" == true ]]; then
    exit 0
fi
if ! command -v kcov >/dev/null; then
    if [[ "$(uname -s)" != "Linux" ]]; then
        echo "kcov is Linux-only; run 'make coverage' (uses Docker) on macOS" >&2
        exit 1
    fi
    sudo apt-get update -qq
    sudo apt-get install -y -qq --no-install-recommends kcov
fi
echo "kcov: $(kcov --version)"
