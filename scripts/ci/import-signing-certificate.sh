#!/usr/bin/env bash
# Import a Developer ID Application .p12 (and optional provisioning profile)
# into a throwaway keychain for xcodebuild on a GitHub Actions macOS runner.
#
# Required environment:
#   APPLE_DEVELOPER_CERTIFICATE_P12_BASE64
#   APPLE_DEVELOPER_CERTIFICATE_PASSWORD
#   RUNNER_TEMP                 (set by GitHub Actions)
#
# Optional:
#   APPLE_PROVISIONING_PROFILE_BASE64
#   KEYCHAIN_PASSWORD           (generated if unset)
#
# Writes KEYCHAIN_PATH, KEYCHAIN_PASSWORD, and optionally
# PROVISIONING_PROFILE_SPECIFIER / PROVISIONING_PROFILE_PATH to GITHUB_OUTPUT
# when that variable is set.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib.sh
source "${SCRIPT_DIR}/lib.sh"

[[ "$(uname -s)" == "Darwin" ]] || ci_die "import-signing-certificate.sh must run on macOS"

[[ -n "${APPLE_DEVELOPER_CERTIFICATE_P12_BASE64:-}" ]] || ci_die "APPLE_DEVELOPER_CERTIFICATE_P12_BASE64 is empty"
[[ -n "${APPLE_DEVELOPER_CERTIFICATE_PASSWORD:-}" ]] || ci_die "APPLE_DEVELOPER_CERTIFICATE_PASSWORD is empty"
[[ -n "${RUNNER_TEMP:-}" ]] || ci_die "RUNNER_TEMP is empty"

KEYCHAIN_PASSWORD="${KEYCHAIN_PASSWORD:-$(uuidgen)}"
KEYCHAIN_PATH="${RUNNER_TEMP}/spotifly-signing.keychain-db"
CERT_PATH="${RUNNER_TEMP}/developer-id.p12"

python3 -c 'import base64, os, sys; sys.stdout.buffer.write(base64.b64decode(os.environ["APPLE_DEVELOPER_CERTIFICATE_P12_BASE64"]))' >"$CERT_PATH"
[[ -s "$CERT_PATH" ]] || ci_die "failed to decode APPLE_DEVELOPER_CERTIFICATE_P12_BASE64"

security delete-keychain "$KEYCHAIN_PATH" >/dev/null 2>&1 || true
security create-keychain -p "$KEYCHAIN_PASSWORD" "$KEYCHAIN_PATH"
security set-keychain-settings -lut 21600 "$KEYCHAIN_PATH"
security unlock-keychain -p "$KEYCHAIN_PASSWORD" "$KEYCHAIN_PATH"

security import "$CERT_PATH" \
    -k "$KEYCHAIN_PATH" \
    -P "$APPLE_DEVELOPER_CERTIFICATE_PASSWORD" \
    -T /usr/bin/codesign \
    -T /usr/bin/security \
    -T /usr/bin/xcodebuild

# Allow codesign to use the imported key without a GUI prompt.
security set-key-partition-list \
    -S apple-tool:,apple:,codesign: \
    -s \
    -k "$KEYCHAIN_PASSWORD" \
    "$KEYCHAIN_PATH" >/dev/null

EXISTING_KEYCHAINS="$(security list-keychains -d user | tr -d '"')"
# shellcheck disable=SC2086
security list-keychains -d user -s "$KEYCHAIN_PATH" $EXISTING_KEYCHAINS
security default-keychain -s "$KEYCHAIN_PATH"

rm -f "$CERT_PATH"

if security find-identity -v -p codesigning "$KEYCHAIN_PATH" | grep -q "Developer ID Application"; then
    ci_log "imported Developer ID Application certificate"
else
    ci_die "p12 imported but no 'Developer ID Application' identity is visible. Export the Developer ID Application certificate (not Apple Development / Distribution)."
fi

PROFILE_NAME=""
PROFILE_PATH=""
if [[ -n "${APPLE_PROVISIONING_PROFILE_BASE64:-}" ]]; then
    PROFILES_DIR="${HOME}/Library/MobileDevice/Provisioning Profiles"
    mkdir -p "$PROFILES_DIR"
    RAW_PROFILE="${RUNNER_TEMP}/spotifly.provisionprofile"
    python3 -c 'import base64, os, sys; sys.stdout.buffer.write(base64.b64decode(os.environ["APPLE_PROVISIONING_PROFILE_BASE64"]))' >"$RAW_PROFILE"
    [[ -s "$RAW_PROFILE" ]] || ci_die "failed to decode APPLE_PROVISIONING_PROFILE_BASE64"

    PROFILE_NAME="$(security cms -D -i "$RAW_PROFILE" | plutil -extract Name raw -)"
    PROFILE_UUID="$(security cms -D -i "$RAW_PROFILE" | plutil -extract UUID raw -)"
    [[ -n "$PROFILE_NAME" && -n "$PROFILE_UUID" ]] || ci_die "could not read Name/UUID from the provisioning profile"

    PROFILE_PATH="${PROFILES_DIR}/${PROFILE_UUID}.provisionprofile"
    cp "$RAW_PROFILE" "$PROFILE_PATH"
    rm -f "$RAW_PROFILE"
    ci_log "installed provisioning profile '${PROFILE_NAME}' (${PROFILE_UUID})"
fi

emit() {
    printf '%s=%s\n' "$1" "$2"
}

emit KEYCHAIN_PATH "$KEYCHAIN_PATH"
emit KEYCHAIN_PASSWORD "$KEYCHAIN_PASSWORD"
if [[ -n "$PROFILE_NAME" ]]; then
    emit PROVISIONING_PROFILE_SPECIFIER "$PROFILE_NAME"
    emit PROVISIONING_PROFILE_PATH "$PROFILE_PATH"
fi

if [[ -n "${GITHUB_OUTPUT:-}" ]]; then
    {
        emit KEYCHAIN_PATH "$KEYCHAIN_PATH"
        emit KEYCHAIN_PASSWORD "$KEYCHAIN_PASSWORD"
        if [[ -n "$PROFILE_NAME" ]]; then
            emit PROVISIONING_PROFILE_SPECIFIER "$PROFILE_NAME"
            emit PROVISIONING_PROFILE_PATH "$PROFILE_PATH"
        fi
    } >>"$GITHUB_OUTPUT"
fi
