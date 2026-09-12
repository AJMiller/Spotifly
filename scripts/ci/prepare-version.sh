#!/usr/bin/env bash
# Compute the next Spotifly release version from MARKETING_VERSION,
# CURRENT_PROJECT_VERSION, and existing v* tags.
#
# Policy:
#   next marketing version = max(project MARKETING_VERSION, highest v* tag)
#     — if the project is already ahead of every tag (a prepared bump), use it
#     — otherwise bump that baseline by patch|minor|major
#   next CURRENT_PROJECT_VERSION = current + 1 (always, so each CI release
#     has a distinct CFBundleVersion)
#
# Usage:
#   prepare-version.sh [--bump patch|minor|major] [--version X.Y.Z]
#                      [--pbxproj PATH] [--write] [--output github]
#
# Prints MARKETING_VERSION, CURRENT_PROJECT_VERSION, TAG, and ALREADY_PREPARED
# as KEY=value lines. With --output github, also appends them to $GITHUB_OUTPUT.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib.sh
source "${SCRIPT_DIR}/lib.sh"

BUMP="patch"
EXPLICIT_VERSION=""
PBXPROJ=""
WRITE=false
OUTPUT=""

usage() {
    cat <<'EOF'
Usage: prepare-version.sh [options]

  --bump patch|minor|major   Semver component to increment (default: patch)
  --version X.Y.Z            Use this marketing version instead of bumping
  --pbxproj PATH             Path to project.pbxproj
  --write                    Write MARKETING_VERSION and CURRENT_PROJECT_VERSION
  --output github            Also write KEY=value to $GITHUB_OUTPUT
EOF
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --bump)
            BUMP="${2:?}"
            shift 2
            ;;
        --version)
            EXPLICIT_VERSION="${2:?}"
            shift 2
            ;;
        --pbxproj)
            PBXPROJ="${2:?}"
            shift 2
            ;;
        --write)
            WRITE=true
            shift
            ;;
        --output)
            OUTPUT="${2:?}"
            shift 2
            ;;
        -h | --help)
            usage
            exit 0
            ;;
        *)
            ci_die "unknown argument: $1"
            ;;
    esac
done

if [[ -z "$PBXPROJ" ]]; then
    REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
    PBXPROJ="${REPO_ROOT}/Spotifly.xcodeproj/project.pbxproj"
fi

[[ -f "$PBXPROJ" ]] || ci_die "pbxproj not found: $PBXPROJ"

PROJECT_MARKETING="$(read_marketing_version "$PBXPROJ")"
PROJECT_BUILD="$(read_project_version "$PBXPROJ")"
TAG_MARKETING="$(highest_release_tag_version || true)"

ci_log "project MARKETING_VERSION=${PROJECT_MARKETING}" >&2
ci_log "project CURRENT_PROJECT_VERSION=${PROJECT_BUILD}" >&2
ci_log "highest release tag=${TAG_MARKETING:-<none>}" >&2

ALREADY_PREPARED=false
NEXT_MARKETING=""

if [[ -n "$EXPLICIT_VERSION" ]]; then
    is_semver "$EXPLICIT_VERSION" || ci_die "--version must be semver (e.g. 1.2.8), got: $EXPLICIT_VERSION"
    NEXT_MARKETING="$(normalize_semver "$EXPLICIT_VERSION")"
else
    BASE="$(normalize_semver "$PROJECT_MARKETING")"
    if [[ -n "$TAG_MARKETING" ]]; then
        TAG_NORM="$(normalize_semver "$TAG_MARKETING")"
        if [[ "$(cmp_semver "$TAG_NORM" "$BASE")" == "1" ]]; then
            BASE="$TAG_NORM"
        fi
    fi

    if [[ -n "$TAG_MARKETING" ]] && [[ "$(cmp_semver "$(normalize_semver "$PROJECT_MARKETING")" "$(normalize_semver "$TAG_MARKETING")")" == "1" ]]; then
        NEXT_MARKETING="$(normalize_semver "$PROJECT_MARKETING")"
        ALREADY_PREPARED=true
        ci_log "project version ${NEXT_MARKETING} is already ahead of tag v${TAG_MARKETING}; using it" >&2
    else
        NEXT_MARKETING="$(bump_semver "$BASE" "$BUMP")"
    fi
fi

if [[ -n "$TAG_MARKETING" ]] && [[ "$(cmp_semver "$NEXT_MARKETING" "$(normalize_semver "$TAG_MARKETING")")" != "1" ]]; then
    ci_die "refusing to reuse version ${NEXT_MARKETING}: tag v${TAG_MARKETING} already exists. Pass --version with a newer semver, or delete the tag only if you intend to replace that release."
fi

# Integer build number. Increment the project value; if an explicit / prepared
# marketing version was chosen, still increment so two releases never share a
# CFBundleVersion even when MARKETING_VERSION was already edited by hand.
if [[ "$PROJECT_BUILD" =~ ^[0-9]+$ ]]; then
    NEXT_BUILD=$((PROJECT_BUILD + 1))
else
    ci_die "CURRENT_PROJECT_VERSION is not an integer: $PROJECT_BUILD"
fi

TAG="v${NEXT_MARKETING}"

if [[ "$WRITE" == true ]]; then
    write_xcode_versions "$PBXPROJ" "$NEXT_MARKETING" "$NEXT_BUILD"
    ci_log "wrote MARKETING_VERSION=${NEXT_MARKETING} CURRENT_PROJECT_VERSION=${NEXT_BUILD} to $PBXPROJ" >&2
fi

emit() {
    printf '%s=%s\n' "$1" "$2"
}

emit MARKETING_VERSION "$NEXT_MARKETING"
emit CURRENT_PROJECT_VERSION "$NEXT_BUILD"
emit TAG "$TAG"
emit ALREADY_PREPARED "$ALREADY_PREPARED"

if [[ "$OUTPUT" == "github" ]]; then
    [[ -n "${GITHUB_OUTPUT:-}" ]] || ci_die "--output github requires GITHUB_OUTPUT"
    {
        emit MARKETING_VERSION "$NEXT_MARKETING"
        emit CURRENT_PROJECT_VERSION "$NEXT_BUILD"
        emit TAG "$TAG"
        emit ALREADY_PREPARED "$ALREADY_PREPARED"
    } >>"$GITHUB_OUTPUT"
fi
