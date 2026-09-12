#!/usr/bin/env bash
# Unit tests for the CI release helpers. Safe to run on Linux.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CI_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
# shellcheck source=../lib.sh
source "${CI_DIR}/lib.sh"

PASS=0
FAIL=0

assert_eq() {
    local got="$1" want="$2" label="$3"
    if [[ "$got" == "$want" ]]; then
        PASS=$((PASS + 1))
        printf 'ok  %s\n' "$label"
    else
        FAIL=$((FAIL + 1))
        printf 'not ok  %s\n  got:  %s\n  want: %s\n' "$label" "$got" "$want"
    fi
}

assert_file_contains() {
    local file="$1" needle="$2" label="$3"
    if grep -qF -- "$needle" "$file"; then
        PASS=$((PASS + 1))
        printf 'ok  %s\n' "$label"
    else
        FAIL=$((FAIL + 1))
        printf 'not ok  %s\n  missing %s in %s\n' "$label" "$needle" "$file"
    fi
}

assert_file_not_contains() {
    local file="$1" needle="$2" label="$3"
    if grep -qF -- "$needle" "$file"; then
        FAIL=$((FAIL + 1))
        printf 'not ok  %s\n  unexpectedly found %s in %s\n' "$label" "$needle" "$file"
    else
        PASS=$((PASS + 1))
        printf 'ok  %s\n' "$label"
    fi
}

WORKDIR="$(mktemp -d)"
trap 'rm -rf "$WORKDIR"' EXIT

# --- lib.sh --------------------------------------------------------------

assert_eq "$(normalize_semver 1.2.7)" "1.2.7" "normalize 1.2.7"
assert_eq "$(normalize_semver v1.2)" "1.2.0" "normalize v1.2"
assert_eq "$(bump_semver 1.2.7 patch)" "1.2.8" "bump patch"
assert_eq "$(bump_semver 1.2.7 minor)" "1.3.0" "bump minor"
assert_eq "$(bump_semver 1.2.7 major)" "2.0.0" "bump major"
assert_eq "$(cmp_semver 1.2.8 1.2.7)" "1" "1.2.8 > 1.2.7"
assert_eq "$(cmp_semver 1.2.7 1.2.7)" "0" "1.2.7 == 1.2.7"
assert_eq "$(cmp_semver 1.2.6 1.2.7)" "-1" "1.2.6 < 1.2.7"

# --- prepare-version.sh --------------------------------------------------

write_fixture_pbxproj() {
    local path="$1" marketing="$2" build="$3"
    cat >"$path" <<EOF
				CURRENT_PROJECT_VERSION = ${build};
				MARKETING_VERSION = ${marketing};
				CURRENT_PROJECT_VERSION = ${build};
				MARKETING_VERSION = ${marketing};
EOF
}

REPO="${WORKDIR}/repo"
mkdir -p "${REPO}/Spotifly.xcodeproj"
git -C "$WORKDIR" init -q repo
git -C "$REPO" config user.email "ci@example.com"
git -C "$REPO" config user.name "CI"
write_fixture_pbxproj "${REPO}/Spotifly.xcodeproj/project.pbxproj" "1.2.7" "7"
git -C "$REPO" add Spotifly.xcodeproj/project.pbxproj
git -C "$REPO" commit -qm "init"
git -C "$REPO" tag v1.2.7

pushd "$REPO" >/dev/null

OUT="$(
    "${CI_DIR}/prepare-version.sh" \
        --pbxproj Spotifly.xcodeproj/project.pbxproj \
        --bump patch
)"
assert_eq "$(printf '%s\n' "$OUT" | awk -F= '/^MARKETING_VERSION=/{print $2}')" "1.2.8" "patch bump from 1.2.7 + tag v1.2.7"
assert_eq "$(printf '%s\n' "$OUT" | awk -F= '/^CURRENT_PROJECT_VERSION=/{print $2}')" "8" "build number increments"
assert_eq "$(printf '%s\n' "$OUT" | awk -F= '/^TAG=/{print $2}')" "v1.2.8" "tag is v + marketing"

# Prepared tree: project already ahead of tags.
write_fixture_pbxproj Spotifly.xcodeproj/project.pbxproj "1.2.8" "7"
OUT="$(
    "${CI_DIR}/prepare-version.sh" \
        --pbxproj Spotifly.xcodeproj/project.pbxproj \
        --bump patch
)"
assert_eq "$(printf '%s\n' "$OUT" | awk -F= '/^MARKETING_VERSION=/{print $2}')" "1.2.8" "use prepared 1.2.8"
assert_eq "$(printf '%s\n' "$OUT" | awk -F= '/^ALREADY_PREPARED=/{print $2}')" "true" "already prepared"
assert_eq "$(printf '%s\n' "$OUT" | awk -F= '/^CURRENT_PROJECT_VERSION=/{print $2}')" "8" "prepared bump still increments build"

# Tag ahead of project (previous CI release did not persist pbxproj).
write_fixture_pbxproj Spotifly.xcodeproj/project.pbxproj "1.2.7" "7"
git tag v1.2.9
OUT="$(
    "${CI_DIR}/prepare-version.sh" \
        --pbxproj Spotifly.xcodeproj/project.pbxproj \
        --bump patch
)"
assert_eq "$(printf '%s\n' "$OUT" | awk -F= '/^MARKETING_VERSION=/{print $2}')" "1.2.10" "bump from highest tag when project lags"

# Explicit version that already has a tag must fail.
if "${CI_DIR}/prepare-version.sh" --pbxproj Spotifly.xcodeproj/project.pbxproj --version 1.2.7 >/tmp/prepare-version-fail.out 2>/tmp/prepare-version-fail.err; then
    FAIL=$((FAIL + 1))
    printf 'not ok  explicit version matching existing tag should fail\n'
else
    PASS=$((PASS + 1))
    printf 'ok  explicit version matching existing tag should fail\n'
fi

# --write updates every assignment.
write_fixture_pbxproj Spotifly.xcodeproj/project.pbxproj "1.2.7" "7"
"${CI_DIR}/prepare-version.sh" \
    --pbxproj Spotifly.xcodeproj/project.pbxproj \
    --version 1.3.0 \
    --write >/dev/null
count_m="$(grep -c 'MARKETING_VERSION = 1.3.0;' Spotifly.xcodeproj/project.pbxproj)"
count_b="$(grep -c 'CURRENT_PROJECT_VERSION = 8;' Spotifly.xcodeproj/project.pbxproj)"
assert_eq "$count_m" "2" "--write updates all MARKETING_VERSION lines"
assert_eq "$count_b" "2" "--write updates all CURRENT_PROJECT_VERSION lines"

popd >/dev/null

# --- update-changelog.sh -------------------------------------------------

CL="${WORKDIR}/CHANGELOG.md"
cat >"$CL" <<'EOF'
# Changelog

## [Unreleased]

### Added
- New thing

### Fixed
- A bug

## [1.2.7] - 2026-08-14

### Fixed
- Older fix
EOF

NOTES="$("${CI_DIR}/update-changelog.sh" --changelog "$CL" --version 1.2.8 --date 2026-09-12 --print-notes)"
assert_file_contains "$CL" "## [Unreleased]" "keeps Unreleased heading"
assert_file_contains "$CL" "## [1.2.8] - 2026-09-12" "adds dated version heading"
assert_file_contains "$CL" "- New thing" "moves Added notes"
assert_file_contains "$CL" "## [1.2.7] - 2026-08-14" "keeps previous version"
if python3 - "$CL" <<'PY'
import sys
from pathlib import Path
text = Path(sys.argv[1]).read_text()
unreleased = text.split("## [1.2.8]", 1)[0]
sys.exit(0 if "New thing" not in unreleased else 1)
PY
then
    PASS=$((PASS + 1))
    printf 'ok  does not leave notes under Unreleased\n'
else
    FAIL=$((FAIL + 1))
    printf 'not ok  does not leave notes under Unreleased\n'
fi
assert_eq "$(printf '%s\n' "$NOTES" | grep -c -- 'New thing')" "1" "prints moved notes"

# Empty Unreleased still gets a placeholder section.
cat >"$CL" <<'EOF'
# Changelog

## [Unreleased]

## [1.2.8] - 2026-09-12
EOF

# Wait, that already has 1.2.8. Use 1.2.9 with empty unreleased.
cat >"$CL" <<'EOF'
# Changelog

## [Unreleased]

## [1.2.8] - 2026-09-12
EOF
"${CI_DIR}/update-changelog.sh" --changelog "$CL" --version 1.2.9 --date 2026-09-13 >/dev/null
assert_file_contains "$CL" "## [1.2.9] - 2026-09-13" "empty Unreleased still creates a version section"
assert_file_contains "$CL" "no additional notes were recorded" "placeholder notes for empty Unreleased"

# Existing section is left alone.
BEFORE="$(cat "$CL")"
"${CI_DIR}/update-changelog.sh" --changelog "$CL" --version 1.2.9 --date 2099-01-01 >/dev/null
AFTER="$(cat "$CL")"
assert_eq "$BEFORE" "$AFTER" "existing version section is not rewritten"

# --- create-export-options.sh --------------------------------------------

PLIST="${WORKDIR}/ExportOptions.plist"
"${CI_DIR}/create-export-options.sh" --team-id 89S4HZY343 --out "$PLIST"
assert_file_contains "$PLIST" "<string>developer-id</string>" "export method is developer-id"
assert_file_contains "$PLIST" "<string>89S4HZY343</string>" "export team id"
assert_file_contains "$PLIST" "<string>automatic</string>" "no profile → automatic signing"

"${CI_DIR}/create-export-options.sh" \
    --team-id 89S4HZY343 \
    --out "$PLIST" \
    --bundle-id rvdh.Spotifly \
    --profile-name "Spotifly Developer ID"
assert_file_contains "$PLIST" "<string>manual</string>" "profile → manual signing"
assert_file_contains "$PLIST" "<key>rvdh.Spotifly</key>" "profile maps bundle id"
assert_file_contains "$PLIST" "<string>Spotifly Developer ID</string>" "profile name"

# --- assert-tag-free.sh --------------------------------------------------

pushd "$REPO" >/dev/null
if "${CI_DIR}/assert-tag-free.sh" v1.2.7 >/dev/null 2>&1; then
    FAIL=$((FAIL + 1))
    printf 'not ok  assert-tag-free should reject an existing local tag\n'
else
    PASS=$((PASS + 1))
    printf 'ok  assert-tag-free rejects existing local tag\n'
fi
if "${CI_DIR}/assert-tag-free.sh" v9.9.9 >/dev/null 2>&1; then
    PASS=$((PASS + 1))
    printf 'ok  assert-tag-free accepts a free tag\n'
else
    FAIL=$((FAIL + 1))
    printf 'not ok  assert-tag-free should accept v9.9.9\n'
fi
popd >/dev/null

printf '\n%d passed, %d failed\n' "$PASS" "$FAIL"
[[ "$FAIL" -eq 0 ]]
