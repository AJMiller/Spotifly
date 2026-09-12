#!/usr/bin/env bash
# Fail if a Git tag or GitHub Release already exists for this version.
# There is no replace path: delete the tag/release by hand if you really
# intend to republish the same version.
#
# Usage:
#   assert-tag-free.sh v1.2.8 [--repo owner/name]
#
# Uses the current git remotes and, when available, `gh`.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib.sh
source "${SCRIPT_DIR}/lib.sh"

TAG="${1:-}"
[[ -n "$TAG" ]] || ci_die "usage: assert-tag-free.sh vX.Y.Z [--repo owner/name]"
shift || true

REPO="${GITHUB_REPOSITORY:-}"
if [[ "${1:-}" == "--repo" ]]; then
    REPO="${2:?}"
fi

[[ "$TAG" == v* ]] || ci_die "tag must start with v, got: $TAG"

if git rev-parse -q --verify "refs/tags/${TAG}" >/dev/null; then
    ci_die "git tag ${TAG} already exists locally. Refusing to publish a duplicate. Bump the version or delete the tag only if replacing that release is intentional."
fi

if git ls-remote --exit-code origin "refs/tags/${TAG}" >/dev/null 2>&1; then
    ci_die "git tag ${TAG} already exists on origin. Refusing to publish a duplicate."
fi

if command -v gh >/dev/null 2>&1 && [[ -n "$REPO" ]]; then
    if gh release view "$TAG" --repo "$REPO" >/dev/null 2>&1; then
        ci_die "GitHub Release ${TAG} already exists on ${REPO}. Refusing to replace it."
    fi
fi

ci_log "${TAG} is free (no local tag, remote tag, or GitHub Release)"
