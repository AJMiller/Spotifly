#!/usr/bin/env bash
# Shared helpers for Spotifly CI release scripts.
# shellcheck shell=bash

set -euo pipefail

ci_log() {
    printf '%s\n' "$*"
}

ci_die() {
    printf 'error: %s\n' "$*" >&2
    exit 1
}

# Print MARKETING_VERSION from an Xcode project.pbxproj.
read_marketing_version() {
    local pbxproj="$1"
    local value
    value="$(grep -E 'MARKETING_VERSION = ' "$pbxproj" | head -1 | awk '{print $3}' | tr -d ';')"
    [[ -n "$value" ]] || ci_die "MARKETING_VERSION not found in $pbxproj"
    printf '%s\n' "$value"
}

# Print CURRENT_PROJECT_VERSION from an Xcode project.pbxproj.
read_project_version() {
    local pbxproj="$1"
    local value
    value="$(grep -E 'CURRENT_PROJECT_VERSION = ' "$pbxproj" | head -1 | awk '{print $3}' | tr -d ';')"
    [[ -n "$value" ]] || ci_die "CURRENT_PROJECT_VERSION not found in $pbxproj"
    printf '%s\n' "$value"
}

# Normalize a version to major.minor.patch (missing parts become 0).
normalize_semver() {
    local raw="${1#v}"
    local major=0 minor=0 patch=0
    IFS='.' read -r major minor patch _ <<<"${raw}"
    major="${major:-0}"
    minor="${minor:-0}"
    patch="${patch:-0}"
    printf '%s.%s.%s\n' "$major" "$minor" "$patch"
}

# Return 0 if $1 is a semver-compatible X.Y or X.Y.Z string.
is_semver() {
    [[ "$1" =~ ^[0-9]+\.[0-9]+(\.[0-9]+)?$ ]]
}

# Compare two normalized semver strings. Prints -1, 0, or 1.
cmp_semver() {
    local a b
    a="$(normalize_semver "$1")"
    b="$(normalize_semver "$2")"
    if [[ "$a" == "$b" ]]; then
        printf '0\n'
        return
    fi
    if [[ "$(printf '%s\n%s\n' "$a" "$b" | sort -V | tail -1)" == "$a" ]]; then
        printf '%s\n' "1"
    else
        printf '%s\n' "-1"
    fi
}

# Bump a normalized semver by patch|minor|major.
bump_semver() {
    local version part="$2"
    version="$(normalize_semver "$1")"
    local major minor patch
    IFS='.' read -r major minor patch <<<"$version"
    case "$part" in
        major) printf '%s.0.0\n' "$((major + 1))" ;;
        minor) printf '%s.%s.0\n' "$major" "$((minor + 1))" ;;
        patch) printf '%s.%s.%s\n' "$major" "$minor" "$((patch + 1))" ;;
        *) ci_die "unknown bump type: $part (expected patch, minor, or major)" ;;
    esac
}

# Highest vX.Y.Z tag in the current repo, without the leading v. Empty if none.
highest_release_tag_version() {
    local tag
    tag="$(git tag -l 'v[0-9]*' 2>/dev/null | sed 's/^v//' | grep -E '^[0-9]+\.[0-9]+(\.[0-9]+)?$' | sort -V | tail -1 || true)"
    printf '%s\n' "$tag"
}

# Replace every MARKETING_VERSION / CURRENT_PROJECT_VERSION assignment in a pbxproj.
write_xcode_versions() {
    local pbxproj="$1"
    local marketing="$2"
    local project="$3"
    local tmp
    tmp="$(mktemp)"
    sed -E \
        -e "s/MARKETING_VERSION = [^;]+;/MARKETING_VERSION = ${marketing};/g" \
        -e "s/CURRENT_PROJECT_VERSION = [^;]+;/CURRENT_PROJECT_VERSION = ${project};/g" \
        "$pbxproj" >"$tmp"
    mv "$tmp" "$pbxproj"
}
