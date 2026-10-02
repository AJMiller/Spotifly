#!/usr/bin/env bash
# Move the CHANGELOG.md [Unreleased] body into a dated version section.
#
# Usage:
#   update-changelog.sh --version 1.2.8 [--changelog PATH] [--date YYYY-MM-DD]
#                       [--print-notes]
#
# If ## [VERSION] already exists, the file is left alone (and --print-notes
# extracts that section). The [Unreleased] heading is always kept.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib.sh
source "${SCRIPT_DIR}/lib.sh"

VERSION=""
CHANGELOG=""
DATE=""
PRINT_NOTES=false

while [[ $# -gt 0 ]]; do
    case "$1" in
        --version)
            VERSION="${2:?}"
            shift 2
            ;;
        --changelog)
            CHANGELOG="${2:?}"
            shift 2
            ;;
        --date)
            DATE="${2:?}"
            shift 2
            ;;
        --print-notes)
            PRINT_NOTES=true
            shift
            ;;
        *)
            ci_die "unknown argument: $1"
            ;;
    esac
done

[[ -n "$VERSION" ]] || ci_die "--version is required"
VERSION="${VERSION#v}"
is_semver "$VERSION" || ci_die "--version must be semver, got: $VERSION"

if [[ -z "$CHANGELOG" ]]; then
    REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
    CHANGELOG="${REPO_ROOT}/CHANGELOG.md"
fi
[[ -f "$CHANGELOG" ]] || ci_die "changelog not found: $CHANGELOG"

if [[ -z "$DATE" ]]; then
    DATE="$(date -u +%F)"
fi

export CHANGELOG VERSION DATE PRINT_NOTES
python3 <<'PY'
import os
import re
import sys
from pathlib import Path

changelog = Path(os.environ["CHANGELOG"])
version = os.environ["VERSION"]
date = os.environ["DATE"]
print_notes = os.environ.get("PRINT_NOTES") == "true"
text = changelog.read_text()

def section_body(text: str, heading_re: str) -> str:
    match = re.search(heading_re, text, flags=re.M)
    if not match:
        return ""
    rest = text[match.end():]
    nxt = re.search(r"^## \[", rest, flags=re.M)
    body = rest[: nxt.start()] if nxt else rest
    return body.strip("\n")

existing = re.search(rf"^## \[{re.escape(version)}\].*$", text, flags=re.M)
if existing:
    print(
        f"changelog already has a ## [{version}] section; leaving it in place",
        file=sys.stderr,
    )
    if print_notes:
        print(section_body(text, rf"^## \[{re.escape(version)}\].*$"))
    sys.exit(0)

unreleased_match = re.search(r"^## \[Unreleased\][ \t]*\n", text, flags=re.M)
if not unreleased_match:
    sys.exit("CHANGELOG.md has no ## [Unreleased] heading")

rest = text[unreleased_match.end():]
nxt = re.search(r"^## \[", rest, flags=re.M)
body = rest[: nxt.start()] if nxt else rest
body = body.strip("\n")
if not body.strip():
    body = (
        "### Changed\n"
        "- Automated CI release; no additional notes were recorded under [Unreleased]."
    )

after = rest[nxt.start() :] if nxt else ""
new_text = (
    text[: unreleased_match.end()]
    + "\n"
    + f"## [{version}] - {date}\n\n"
    + body
    + "\n\n"
    + after
)
changelog.write_text(new_text)
print(f"moved [Unreleased] notes to ## [{version}] - {date}", file=sys.stderr)
if print_notes:
    print(body)
PY
