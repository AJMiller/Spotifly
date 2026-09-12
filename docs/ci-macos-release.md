# CI release pipeline

Merging a pull request to `main` (or running **Release** by hand) builds a
Developer ID–signed, Apple-notarized `Spotifly.app` on GitHub’s `macos-26`
runners and publishes it as a GitHub Release on **this** repository
(`AJMiller/Spotifly`).

The workflow never needs write access to `ralph/spotifly` or
`ralph/homebrew-spotifly`. Those remotes are only mentioned below so a
maintainer who *does* have tap access can update Homebrew by hand.

Until the secrets in this document are set, a merge to `main` still starts
the workflow but **skips publishing** (the job succeeds with a log line
listing what is missing). A manual **Run workflow** fails instead, so a
deliberate release cannot silently no-op.

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
5. Archives with `xcodebuild`, exports a Developer ID app, submits it with
   `notarytool`, staples the ticket, and zips the app with `ditto`.
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
| `APPLE_PROVISIONING_PROFILE_BASE64` | recommended | Base64 of a **Developer ID** Mac provisioning profile for `rvdh.Spotifly` |
| `HOMEBREW_TAP_TOKEN` | unused | Reserved name only. This workflow does not write `ralph/homebrew-spotifly` |

`GITHUB_TOKEN` (automatic) is enough to push the version tag and create
the GitHub Release on `AJMiller/Spotifly`.

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

Without a provisioning profile the workflow also passes this key to
`xcodebuild -allowProvisioningUpdates` so Xcode can mint a Developer ID
profile at archive time. That only works if the API key’s team owns the
App ID (see bundle ID below).

### Create a Developer ID provisioning profile (recommended)

Spotifly enables App Sandbox and the Hardened Runtime, so a **Developer ID**
Mac App profile for `rvdh.Spotifly` is the reliable signing path.

1. Register the macOS App ID `rvdh.Spotifly` on the same team as the
   certificate (Identifiers → App IDs), if it is not already there.
2. Create a **Developer ID** profile for that App ID, download the
   `.provisionprofile`.
3. Encode it:

   ```bash
   base64 -i Spotifly.provisionprofile | pbcopy
   ```

   Paste into `APPLE_PROVISIONING_PROFILE_BASE64`.

If this secret is unset, the workflow falls back to automatic signing with
the API key. Prefer shipping the profile so archive does not depend on
Xcode creating one on the runner.

### Team ID and bundle identifier

The Xcode project still has `PRODUCT_BUNDLE_IDENTIFIER = rvdh.Spotifly` and
a checked-in `DEVELOPMENT_TEAM`. CI **overrides** `DEVELOPMENT_TEAM` with
`APPLE_TEAM_ID`.

Bundle IDs are globally unique. If your Apple team is not the team that
already owns `rvdh.Spotifly`, Apple will not let you create a matching
Developer ID profile. In that case you must change the bundle ID in the
Xcode project (and the App ID on developer.apple.com) before this pipeline
can sign a sandboxed build. That project change is outside this workflow.

## Runner and tools

| Piece | Value |
| --- | --- |
| Runner | `macos-26` (Apple Silicon). Default Xcode on that image is 26.6+, which matches `DEVELOPMENT.md`. |
| Rust | `stable` plus `aarch64-apple-darwin` |
| librespot | Sibling clone at `LIBRESPOT_REF` (see the `env` block in `.github/workflows/release.yml`) |
| Signing | Temporary keychain, deleted at the end of the job |
| Zip | `ditto -c -k --keepParent` so AppleDouble / resource forks survive |

To pin a newer known-good librespot revision, change `LIBRESPOT_REF` in the
workflow (and `CONTRIBUTING.md`).

## Enabling the pipeline (maintainer checklist)

1. Create the Apple artifacts above.
2. Add every **required** secret on `AJMiller/Spotifly`.
3. Confirm **Settings → Actions → General** allows GitHub Actions and that
   the workflow has permission to create releases (`contents: write` is set
   in the YAML; the repo must not block that).
4. Merge a pull request to `main`, or run **Release** from the Actions tab.
5. Confirm the new `v*` tag and the ZIP on
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
