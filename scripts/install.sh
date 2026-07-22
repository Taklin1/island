#!/usr/bin/env bash
#
# Installs (or updates) island from the latest GitHub Release — the official
# install channel (ADR-0010): a one-liner run in the terminal, so the download
# never carries the com.apple.quarantine attribute and never meets Gatekeeper.
#
#     curl -fsSL https://raw.githubusercontent.com/Taklin1/island/main/scripts/install.sh | sh
#
# What it does, in order:
#   1. downloads the `island.zip` asset of the latest Release (fixed asset
#      name — the inter-issue contract with the release workflow, no JSON
#      parsing, no jq),
#   2. extracts it in a private temp dir and validates the bundle layout,
#   3. quits any running instance (single instance only — port 41414),
#   4. replaces ~/Applications/island.app and relaunches it.
#
# No sudo. Writes nowhere but ~/Applications and a temp dir cleaned on exit.
# Idempotent: safe to re-run any time; this same script is the updater.

set -euo pipefail

DOWNLOAD_URL="https://github.com/Taklin1/island/releases/latest/download/island.zip"
APP_NAME="island"
INSTALL_DIR="${HOME}/Applications"
APP_PATH="${INSTALL_DIR}/${APP_NAME}.app"

TMP_DIR="$(mktemp -d "${TMPDIR:-/tmp}/island-install.XXXXXX")"
trap 'rm -rf "${TMP_DIR}"' EXIT

# --- Download the latest Release asset ---------------------------------------
# `releases/latest/download/<asset>` resolves the latest published Release via
# an HTTP redirect: no API token, no JSON. `-f` turns HTTP >= 400 (404 when no
# Release exists yet) into a curl failure instead of saving an error page.
echo "==> downloading latest island release"
if ! curl -fsSL -o "${TMP_DIR}/${APP_NAME}.zip" "${DOWNLOAD_URL}"; then
    echo "error: could not download ${DOWNLOAD_URL}" >&2
    echo "       No published Release found (or network error)." >&2
    echo "       Check https://github.com/Taklin1/island/releases" >&2
    exit 1
fi

# --- Extract and validate before touching anything installed -----------------
# ditto preserves the executable bit and never adds a quarantine attribute.
echo "==> extracting"
ditto -x -k "${TMP_DIR}/${APP_NAME}.zip" "${TMP_DIR}/extracted"

NEW_APP="${TMP_DIR}/extracted/${APP_NAME}.app"
if [[ ! -x "${NEW_APP}/Contents/MacOS/${APP_NAME}" ]]; then
    echo "error: unexpected zip layout — ${APP_NAME}.app/Contents/MacOS/${APP_NAME} missing or not executable" >&2
    exit 1
fi

# curl does not set com.apple.quarantine; strip it defensively anyway so a
# repackaged/forwarded zip can never trip Gatekeeper.
xattr -dr com.apple.quarantine "${NEW_APP}" 2>/dev/null || true

VERSION="$(defaults read "${NEW_APP}/Contents/Info" CFBundleShortVersionString 2>/dev/null || echo "unknown")"
echo "==> island ${VERSION} downloaded"

# --- Quit any running instance -----------------------------------------------
# island binds the fixed local port 41414: only one instance may run. Kill by
# install path (the repo's canonical pattern).
#
# `-a` is load-bearing (issue #125): by default pkill excludes its own process
# AND all of its ancestors from the match (man pgrep, flag -a). In the update
# path (#92) this script is a DESCENDANT of the running app — island →
# UpdateInstaller Process → bash → install.sh → pkill — so island is an ancestor
# of pkill and, without `-a`, is silently skipped: the old instance survives,
# keeps port 41414, and the freshly `open`ed instance dies binding it. `-a`
# includes ancestors so the running app is actually signalled. In the terminal
# install path the app is not an ancestor, so `-a` is a no-op there — same
# behaviour, bug fixed only where it existed.
#
# pkill exits 1 when nothing matched — that is fine (idempotence).
echo "==> stopping running instance (if any)"
pkill -a -f "Applications/${APP_NAME}.app" 2>/dev/null || true

# Wait (bounded) for the port to be released instead of a blind `sleep 1`: the
# signalled app needs a moment to exit and close its listening socket before the
# fresh instance can bind it. Poll up to ~5s, then proceed regardless. Idempotent:
# if nothing is listening (fresh install, or app already gone) lsof returns
# non-zero immediately and the loop exits at once — never slower than the old
# sleep when there is nothing to wait for.
for _ in $(seq 1 25); do
    lsof -nP -iTCP:41414 -sTCP:LISTEN >/dev/null 2>&1 || break
    sleep 0.2
done

# --- Replace the installed app -----------------------------------------------
# Remove the old bundle entirely, then lay down the new one — never extract
# over an existing .app (stale files from older versions would survive).
echo "==> installing to ${APP_PATH}"
mkdir -p "${INSTALL_DIR}"
rm -rf "${APP_PATH}"
ditto "${NEW_APP}" "${APP_PATH}"

# --- Relaunch ----------------------------------------------------------------
echo "==> launching ${APP_NAME}"
open "${APP_PATH}"

echo "==> island ${VERSION} installed: ${APP_PATH}"
echo "==> done"
