#!/usr/bin/env bash
#
# Packages island into a real, signed `island.app` bundle and installs it to
# ~/Applications (no sudo). Ad-hoc signature (`codesign -s -`) by default for
# local/dev use; the release CI overrides ISLAND_CODESIGN_IDENTITY to sign with
# the stable certificate (release.yml, ADR-0010). No notarization, no Developer
# ID.
#
# Why a bundle: SMAppService (the login item) and the menu-bar lifecycle need a
# genuine .app — the bare SwiftPM binary fails to register (issue #6, ADR notes
# in docs/agents/agentic-driving.md).
#
# Repeatable — run any time after a build:
#     scripts/package_app.sh            # build, bundle, sign, install (X.Y.Z-dev)
#     scripts/package_app.sh --no-install   # build, bundle, sign only
#     scripts/package_app.sh --release  # bare X.Y.Z version (CI use, ADR-0010)
#
# Version: read from the top of CHANGELOG.md, suffixed `-dev` by default so a
# local build is distinguishable from a release and never self-updates (US15);
# `--release` keeps the bare version (future CI packaging, release.yml).
#
# Requires: Command Line Tools (swift, codesign, iconutil already used to make
# the icon). No full Xcode needed.

set -euo pipefail

BUNDLE_ID="${ISLAND_BUNDLE_ID:-com.taklin.island}"
APP_NAME="island"                       # bundle + executable name (lowercase)
DISPLAY_NAME="Island"
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
INSTALL_DIR="${HOME}/Applications"
DIST_DIR="${REPO_ROOT}/.build/dist"     # gitignored (.build/)
APP_DIR="${DIST_DIR}/${APP_NAME}.app"
RESOURCE_BUNDLE="Island_IslandUI.bundle"
# Signing identity: ad-hoc `-` by default (local/dev, ADR-0005). The release CI
# (release.yml, ADR-0010) exports ISLAND_CODESIGN_IDENTITY=island-release so the
# stable certificate signs the bundle and the Accessibility permission survives
# updates. One signing path — the workflow never re-signs afterwards.
CODESIGN_IDENTITY="${ISLAND_CODESIGN_IDENTITY:--}"

INSTALL=1
RELEASE=0
for arg in "$@"; do
    case "$arg" in
        --no-install) INSTALL=0 ;;
        --release) RELEASE=1 ;;
        *) echo "unknown argument: $arg" >&2; exit 2 ;;
    esac
done

# --- Version: single source of truth is the top of CHANGELOG.md (0.x.y) ------
VERSION="$(grep -m1 -Eo '^## [0-9]+\.[0-9]+\.[0-9]+' "${REPO_ROOT}/CHANGELOG.md" \
    | sed 's/^## //')"
if [[ -z "${VERSION}" ]]; then
    echo "error: could not read version from CHANGELOG.md" >&2
    exit 1
fi
# Local builds are marked `-dev` (never self-update, US15/ADR-0010); only an
# explicit --release (CI) keeps the bare version. Suffix AFTER the extraction
# so the CHANGELOG grep format stays untouched.
if [[ "${RELEASE}" -eq 0 ]]; then
    VERSION="${VERSION}-dev"
fi
echo "==> island ${VERSION} (bundle id: ${BUNDLE_ID})"

# --- Build -------------------------------------------------------------------
echo "==> swift build -c release"
swift build -c release --package-path "${REPO_ROOT}"
BIN_PATH="$(swift build -c release --package-path "${REPO_ROOT}" --show-bin-path)"

if [[ ! -x "${BIN_PATH}/${DISPLAY_NAME}" ]]; then
    echo "error: release binary not found at ${BIN_PATH}/${DISPLAY_NAME}" >&2
    exit 1
fi

# --- Icon: use the committed .icns, regenerate if missing (needs PIL) --------
ICON_SRC="${REPO_ROOT}/packaging/${APP_NAME}.icns"
if [[ ! -f "${ICON_SRC}" ]]; then
    echo "==> icon missing, regenerating via scripts/generate_icon.py"
    python3 "${REPO_ROOT}/scripts/generate_icon.py" "${ICON_SRC}" || \
        echo "warning: icon generation failed; bundling without an app icon" >&2
fi

# --- Assemble the bundle -----------------------------------------------------
echo "==> assembling ${APP_DIR}"
rm -rf "${APP_DIR}"
mkdir -p "${APP_DIR}/Contents/MacOS" "${APP_DIR}/Contents/Resources"

cp "${BIN_PATH}/${DISPLAY_NAME}" "${APP_DIR}/Contents/MacOS/${APP_NAME}"

# The resource bundle goes in Contents/Resources — the codesign-legal spot.
# (The SwiftPM Bundle.module accessor would look for it at the .app root, where
# codesign refuses "unsealed contents in the bundle root"; IslandUI's
# SpriteSheet.resourceURL resolves Contents/Resources first to bridge the gap.)
if [[ -d "${BIN_PATH}/${RESOURCE_BUNDLE}" ]]; then
    rm -rf "${APP_DIR}/Contents/Resources/${RESOURCE_BUNDLE}"
    cp -R "${BIN_PATH}/${RESOURCE_BUNDLE}" "${APP_DIR}/Contents/Resources/${RESOURCE_BUNDLE}"
else
    echo "error: resource bundle ${RESOURCE_BUNDLE} not found in ${BIN_PATH}" >&2
    exit 1
fi

ICON_KEY=""
if [[ -f "${ICON_SRC}" ]]; then
    cp "${ICON_SRC}" "${APP_DIR}/Contents/Resources/${APP_NAME}.icns"
    ICON_KEY="	<key>CFBundleIconFile</key>
	<string>${APP_NAME}</string>"
fi

# PkgInfo (classic, harmless): application, no creator code.
printf 'APPL????' > "${APP_DIR}/Contents/PkgInfo"

# Info.plist. LSUIElement=true → accessory app, no Dock icon (matches
# setActivationPolicy(.accessory) in main.swift). No sandbox: the app reads
# ~/.claude and, later (#22), uses Accessibility.
cat > "${APP_DIR}/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>CFBundleName</key>
	<string>${DISPLAY_NAME}</string>
	<key>CFBundleDisplayName</key>
	<string>${DISPLAY_NAME}</string>
	<key>CFBundleIdentifier</key>
	<string>${BUNDLE_ID}</string>
	<key>CFBundleExecutable</key>
	<string>${APP_NAME}</string>
	<key>CFBundlePackageType</key>
	<string>APPL</string>
	<key>CFBundleShortVersionString</key>
	<string>${VERSION}</string>
	<key>CFBundleVersion</key>
	<string>${VERSION}</string>
	<key>CFBundleInfoDictionaryVersion</key>
	<string>6.0</string>
${ICON_KEY}
	<key>LSMinimumSystemVersion</key>
	<string>14.0</string>
	<key>LSUIElement</key>
	<true/>
	<key>NSHumanReadableCopyright</key>
	<string>island — personal build</string>
	<key>NSPrincipalClass</key>
	<string>NSApplication</string>
</dict>
</plist>
PLIST

# --- Sign (ad-hoc locally, stable certificate in release CI) -----------------
echo "==> codesign (${CODESIGN_IDENTITY})"
codesign --force --deep --sign "${CODESIGN_IDENTITY}" "${APP_DIR}"
codesign --verify --verbose "${APP_DIR}"
codesign -dv "${APP_DIR}" 2>&1 | grep -Ei 'Identifier|Signature|Authority|TeamIdentifier' || true

# --- Install -----------------------------------------------------------------
if [[ "${INSTALL}" -eq 1 ]]; then
    echo "==> installing to ${INSTALL_DIR}/${APP_NAME}.app"
    mkdir -p "${INSTALL_DIR}"
    rm -rf "${INSTALL_DIR}/${APP_NAME}.app"
    ditto "${APP_DIR}" "${INSTALL_DIR}/${APP_NAME}.app"
    echo "==> installed: ${INSTALL_DIR}/${APP_NAME}.app"
else
    echo "==> built (not installed): ${APP_DIR}"
fi

echo "==> done"
