# Releasing MGL

Releases are built by GitHub Actions ([.github/workflows/release.yml](../.github/workflows/release.yml)) when a `v*` tag is pushed: tests → universal `MGL.app` → `MGL-<version>.dmg` (+ `.sha256`) → GitHub Release with the notes of that version from [CHANGELOG.md](../CHANGELOG.md).

## Steps

1. Bump `MGL.version` in `Sources/MGLCore/MGL.swift` (e.g. `0.2.0`) — the workflow fails if the tag does not match.
2. Add a `## [0.2.0] — YYYY-MM-DD` section to `CHANGELOG.md`.
3. Commit, then tag and push:
   ```bash
   git tag -a v0.2.0 -m "MGL v0.2.0"
   git push --follow-tags
   ```
4. Check the *Release* workflow run and the new release page.

Local dry run of the packaging: `./scripts/build-app.sh --universal && ./scripts/make-dmg.sh` → `build/MGL-<version>.dmg`.

## Optional: stable signing for releases

Without secrets, release builds are signed **ad-hoc**: their signature changes with every version, so users must re-enable MGL under *Accessibility* after each update. Signing releases with your local identity ("MGL Local Code Signing", created by `scripts/create-signing-identity.sh`) keeps the signature stable across versions. It does **not** remove the Gatekeeper "Open Anyway" step — only notarization (paid Apple Developer Program) does.

1. *Keychain Access* → login keychain → *My Certificates* → right-click **MGL Local Code Signing** → *Export…* → `.p12`, choose a password. Export only this item.
2. Store it as repository secrets (GitHub CLI):
   ```bash
   base64 -i MGL.p12 | gh secret set MGL_SIGNING_P12_BASE64
   gh secret set MGL_SIGNING_P12_PASSWORD
   ```
3. Delete the exported `MGL.p12` file.

The workflow imports it into a temporary keychain on the runner ([scripts/ci-import-identity.sh](../scripts/ci-import-identity.sh)). The private key then lives in your GitHub secrets: anyone with admin access to the repository could use it to sign code as "MGL Local Code Signing" (trusted by nobody but the Macs that already granted MGL Accessibility).

## Future: notarization

With a paid Apple Developer account: sign with a *Developer ID Application* certificate and `--options runtime`, submit app and DMG with `xcrun notarytool submit --wait`, then `xcrun stapler staple`. Users could then open MGL with a double click. See TODO.md.
