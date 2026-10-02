#!/usr/bin/env bash
# Write an ExportOptions.plist for Developer ID export (Manual signing only).
#
# Usage:
#   create-export-options.sh --team-id TEAM --out PATH --profile-name NAME
#       [--bundle-id com.ajmiller.spotifly]

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib.sh
source "${SCRIPT_DIR}/lib.sh"

TEAM_ID=""
OUT=""
BUNDLE_ID="com.ajmiller.spotifly"
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
[[ -n "$PROFILE_NAME" ]] || ci_die "--profile-name is required (Manual Developer ID signing only; automatic profile minting is not supported)"

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
	<string>manual</string>
	<key>signingCertificate</key>
	<string>Developer ID Application</string>
	<key>destination</key>
	<string>export</string>
	<key>provisioningProfiles</key>
	<dict>
		<key>${BUNDLE_ID}</key>
		<string>${PROFILE_NAME}</string>
	</dict>
</dict>
</plist>
EOF

ci_log "wrote Developer ID export options (manual) to $OUT"
