# CI release pipeline

Merging a pull request to `main` (or running **Release** by hand) builds a
Developer ID–signed, Apple-notarized `Spotifly.app` on GitHub’s `macos-26`
runners and publishes it as a GitHub Release on **this** repository
(`AJMiller/Spotifly`).

The workflow never needs write access to `ralph/spotifly` or
`ralph/homebrew-spotifly`. Those remotes are only mentioned below so a
maintainer who *does* have tap access can update Homebrew by hand.

Until the secrets in this document are set, a merge to `main` still starts
the workflow but **skips publishing**. That skip is visible: the job emits a
GitHub Actions `::warning::` and writes a job summary listing the missing
secrets. A manual **Run workflow** fails instead, so a deliberate release
cannot silently no-op.

## What the workflow does

1. Confirms the push is a merged pull request (or a `workflow_dispatch`).
   Direct pushes to `main` and `chore(release):` commits are skipped.
   Include `[skip release]` in a merge commit message to skip that merge.
2. Bumps `MARKETING_VERSION` and `CURRENT_PROJECT_VERSION` in
   `Spotifly.xcodeproj/project.pbxproj` using the same fields the Xcode UI
   and `./release.sh` already read. Tags stay `v{MARKETING_VERSION}`
   (for example `v1.2.8`), matching existing releases such as `v1.2.7`.
3. Moves `CHANGELOG.md` `[Unreleased]` notes into a dated `## [version]`
   section.
4. Clones official [librespot](https://github.com/librespot-org/librespot)
   as a sibling of the repo checkout (`../librespot`) at the known-good
   revision recorded in `CONTRIBUTING.md` (`9c7d756` today).
5. Selects the pinned Xcode (26.6), archives with `xcodebuild` using
   **Manual** Developer ID signing and the uploaded provisioning profile,
   exports the app, submits it with `notarytool`, staples the ticket, and
   zips the app with `ditto`.
6. Creates an annotated tag and a GitHub Release whose asset is
   `Spotifly-{version}.zip`.
7. Pushes the version-bump commit to `main` only when that is a
   fast-forward. If `main` moved during the (long) notarization, the tag
   still points at the commit that was built; the next release increments
   from `max(project MARKETING_VERSION, highest v* tag)` so versions cannot
   collide.

There is **no replace path**. If `v{version}` already exists as a git tag
or a GitHub Release, the job fails with a clear error. Delete that tag and
release yourself only if republishing the same version is intentional.

Homebrew is **not** updated. The release notes include the ZIP SHA-256 so
you can edit a tap by hand if you want.

## Version policy

| Input | Result |
| --- | --- |
| Default merge to `main` | Patch bump of `max(MARKETING_VERSION, highest v* tag)` and `CURRENT_PROJECT_VERSION + 1` |
| Project already ahead of every tag (you bumped Xcode first) | That marketing version is used as-is; the build number still increments |
| **Run workflow** → bump `minor` / `major` | Bump that component instead of patch |
| **Run workflow** → version `1.3.0` | Use exactly `1.3.0`, unless `v1.3.0` already exists (then fail) |

`CURRENT_PROJECT_VERSION` is the integer Xcode calls “Build”. It starts at
`7` in this tree and goes `8`, `9`, … on each CI release.

## Repository secrets

Add these under **Settings → Secrets and variables → Actions**. Do not
commit them.

| Secret | Required | Contents |
| --- | --- | --- |
| `APPLE_TEAM_ID` | yes | 10-character Team ID (Membership details on [developer.apple.com](https://developer.apple.com/account)) |
| `APPLE_DEVELOPER_CERTIFICATE_P12_BASE64` | yes | Base64 of a **Developer ID Application** certificate exported as PKCS#12 (`.p12`) |
| `APPLE_DEVELOPER_CERTIFICATE_PASSWORD` | yes | Password you set when exporting that `.p12` |
| `APPLE_API_KEY_ID` | yes | App Store Connect API key ID (the 10-character `KEY ID`) |
| `APPLE_API_ISSUER_ID` | yes | App Store Connect issuer UUID (Users and Access → Integrations) |
| `APPLE_API_KEY_P8` | yes | Full PEM text of `AuthKey_<KEY_ID>.p8`, including `BEGIN`/`END` lines |
| `APPLE_PROVISIONING_PROFILE_BASE64` | yes | Base64 of a **Developer ID** Mac provisioning profile for `com.ajmiller.spotifly` |
| `RELEASE_GITHUB_TOKEN` | optional | PAT used instead of `GITHUB_TOKEN` to push the `chore(release):` commit onto a protected `main` (see [Branch protection](#branch-protection-and-the-chorerelease-push)) |
| `HOMEBREW_TAP_TOKEN` | unused | Reserved name only. This workflow does not write `ralph/homebrew-spotifly` |

`GITHUB_TOKEN` (automatic) is enough to create the tag and the GitHub
Release on `AJMiller/Spotifly`. Pushing the version-bump commit to a
protected `main` is a separate question; see below.

### Create the Developer ID certificate

1. In [Certificates, Identifiers & Profiles](https://developer.apple.com/account/resources/certificates/list)
   create a **Developer ID Application** certificate (not Apple Development
   and not Mac App Store).
2. On a Mac that has the matching private key, open **Keychain Access**,
   select the certificate, and export it as `.p12` with a password.
3. Encode the file (run this on your Mac, not in the repo):

   ```bash
   base64 -i DeveloperID.p12 | pbcopy
   ```

   Paste the result into `APPLE_DEVELOPER_CERTIFICATE_P12_BASE64`. Put the
   export password in `APPLE_DEVELOPER_CERTIFICATE_PASSWORD`.

The `.p12` should contain **one** Developer ID Application identity. The
workflow looks up `CODE_SIGN_IDENTITY=Developer ID Application`.

### Create the App Store Connect API key (notarization)

1. In App Store Connect go to **Users and Access → Integrations → App Store
   Connect API**.
2. Create a key with access to **Developer** (or Admin). Notarization uses
   the [Notary API](https://developer.apple.com/documentation/notaryapi).
3. Download the `.p8` once. Store:
   - file contents → `APPLE_API_KEY_P8`
   - Key ID → `APPLE_API_KEY_ID`
   - Issuer ID (shown on the same page) → `APPLE_API_ISSUER_ID`

This key is used only for `notarytool`. Signing is Manual and does **not**
ask Xcode to mint a profile.

### Create a Developer ID provisioning profile (required)

Spotifly enables App Sandbox and the Hardened Runtime. The pipeline signs
**only** with a **Developer ID** Mac App profile for
`com.ajmiller.spotifly`. There is no automatic-signing fallback.

1. Register the macOS App ID `com.ajmiller.spotifly` on the same team as
   the certificate (Identifiers → App IDs).
2. Create a **Developer ID** profile for that App ID, download the
   `.provisionprofile`.
3. Encode it:

   ```bash
   base64 -i Spotifly.provisionprofile | pbcopy
   ```

   Paste into `APPLE_PROVISIONING_PROFILE_BASE64`.

If this secret is missing, a merge to `main` soft-skips publishing (warning
+ job summary). **Run workflow** fails.

### Team ID and bundle identifier

The app’s bundle ID is `com.ajmiller.spotifly` (`PRODUCT_BUNDLE_IDENTIFIER`
in the Xcode project, `CFBundleIdentifier` in `Spotifly/Info.plist`). CI
uses the same value via `PRODUCT_BUNDLE_IDENTIFIER` in the workflow `env`
block and **overrides** `DEVELOPMENT_TEAM` with `APPLE_TEAM_ID`.

Register that App ID on *your* Apple team and issue the Developer ID
profile against it. The checked-in `DEVELOPMENT_TEAM` is only a local
Xcode default; the runner never uses it for the release archive.

Keychain access still uses the group `$(AppIdentifierPrefix)com.spotifly.keychain`
from `Spotifly.entitlements`. `KeychainManager` reads `AppIdentifierPrefix`
from Info.plist so the team prefix matches the signed build.

## Branch protection and the `chore(release):` push

After a successful notarization the workflow commits
`chore(release): vX.Y.Z` (version + changelog) and, when `main` has not
moved, pushes that commit with the checkout token.

**`GITHUB_TOKEN` cannot push to a protected `main`** that requires a pull
request, required reviewers, or required status checks — unless the
ruleset explicitly lets GitHub Actions through. A rejected push does **not**
roll back the GitHub Release: the `v*` tag still points at the commit that
was built, and the next release increments from `max(project, tags)`.

Pick one of these if you want the version bump to land on `main`
automatically:

1. **Allow the Actions bot to bypass** (simplest if you trust this
   workflow). In the `main` ruleset, add **Bypass list** entries for
   `github-actions[bot]` (and/or the GitHub Actions app). Keep “Do not
   allow bypassing the above settings” **off** for those actors.
2. **Dedicated PAT.** Create a fine-grained personal access token (or a
   machine-user PAT) with **Contents: Read and write** on this repository,
   belonging to an account that is allowed to push to `main`. Store it as
   `RELEASE_GITHUB_TOKEN`. The workflow’s `actions/checkout` uses that
   token when the secret is set, otherwise `github.token`.
3. **Leave `main` unprotected for this**, or accept tag-only versioning
   when the push is rejected.

Do **not** grant the PAT more than Contents write on this repo. Do not
commit the token.

## Runner and tools

| Piece | Value |
| --- | --- |
| Runner | `macos-26` (Apple Silicon) |
| Xcode | Pinned to `/Applications/Xcode_26.6.app` (`xcode-select`). Matches `DEVELOPMENT.md` (Xcode 26.6+). Change `XCODE_APP` in `.github/workflows/release.yml` when you intend to move. |
| Rust | `stable` plus `aarch64-apple-darwin` |
| librespot | Sibling clone at `LIBRESPOT_REF` (see the `env` block in `.github/workflows/release.yml`) |
| Signing | Temporary keychain + installed Developer ID profile; Manual `CODE_SIGN_STYLE` only |
| Zip | `ditto -c -k --keepParent` so AppleDouble / resource forks survive |

To pin a newer known-good librespot revision, change `LIBRESPOT_REF` in the
workflow (and `CONTRIBUTING.md`).

## Enabling the pipeline (maintainer checklist)

1. Create the Apple artifacts above, including a Developer ID profile for
   `com.ajmiller.spotifly`.
2. Add every **required** secret on `AJMiller/Spotifly`.
3. Confirm **Settings → Actions → General** allows GitHub Actions and that
   the workflow has permission to create releases (`contents: write` is set
   in the YAML; the repo must not block that).
4. If `main` is protected, apply one of the [branch-protection](#branch-protection-and-the-chorerelease-push) options.
5. Merge a pull request to `main`, or run **Release** from the Actions tab.
6. Confirm the new `v*` tag and the ZIP on
   `https://github.com/AJMiller/Spotifly/releases`.

## What this fork does not do

- It does **not** upload to `ralph/spotifly` releases.
- It does **not** update `ralph/homebrew-spotifly` (formula URL + SHA-256).
  The ZIP SHA-256 is printed in the job log and in the release notes.
- It does **not** replace the interactive `./release.sh` / Xcode Organizer
  flow. That script still targets the upstream remotes and is the local
  fallback when you want to notarize from your own Mac.

## Local helper tests

The version, changelog, and export-options scripts are covered by
Linux-safe checks:

```bash
scripts/ci/tests/run.sh
```

`.github/workflows/scripts.yml` runs that on pull requests that touch
`scripts/ci/**`.
