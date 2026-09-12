#!/usr/bin/env bash
# Write an ExportOptions.plist for Developer ID export.
#
# Usage:
#   create-export-options.sh --team-id TEAM --out PATH
#       [--bundle-id rvdh.Spotifly] [--profile-name NAME]
#
# If --profile-name is omitted, signingStyle is automatic (xcodebuild must be
# given -allowProvisioningUpdates and an App Store Connect API key).

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib.sh
source "${SCRIPT_DIR}/lib.sh"

TEAM_ID=""
OUT=""
BUNDLE_ID="rvdh.Spotifly"
PROFILE_NAME=""

while [[ $# -gt 0 ]]; do
    case "$1" in
        --team-id)
            TEAM_ID="${2:?}"
            shift 2
            ;;
        --out)
            OUT="${2:?}"
            shift 2
            ;;
        --bundle-id)
            BUNDLE_ID="${2:?}"
            shift 2
            ;;
        --profile-name)
            PROFILE_NAME="${2:?}"
            shift 2
            ;;
        *)
            ci_die "unknown argument: $1"
            ;;
    esac
done

[[ -n "$TEAM_ID" ]] || ci_die "--team-id is required"
[[ -n "$OUT" ]] || ci_die "--out is required"

if [[ -n "$PROFILE_NAME" ]]; then
    SIGNING_STYLE="manual"
    PROFILE_XML=$(
        cat <<EOF
	<key>signingCertificate</key>
	<string>Developer ID Application</string>
	<key>provisioningProfiles</key>
	<dict>
		<key>${BUNDLE_ID}</key>
		<string>${PROFILE_NAME}</string>
	</dict>
EOF
    )
else
    SIGNING_STYLE="automatic"
    PROFILE_XML=""
fi

cat >"$OUT" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>method</key>
	<string>developer-id</string>
	<key>teamID</key>
	<string>${TEAM_ID}</string>
	<key>signingStyle</key>
	<string>${SIGNING_STYLE}</string>
	<key>destination</key>
	<string>export</string>
${PROFILE_XML}
</dict>
</plist>
EOF

ci_log "wrote Developer ID export options (${SIGNING_STYLE}) to $OUT"
