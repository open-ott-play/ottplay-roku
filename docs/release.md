# Release, signing, and Beta distribution

The `0.1.0-beta.1` preview prepares a reproducible sideload ZIP without requiring
a Roku device. It does **not** include a signed `.pkg`, a Roku Beta access code,
or a claim of hardware validation. GitHub's prerelease label and Roku's Beta
app program are separate things.

## Host-side release checks

Use the repository's pinned dependencies:

```sh
npm ci
npm run verify
```

The checks compile/validate BrightScript and SceneGraph sources, exercise
host-side tests, and verify package reproducibility. The application tree must
contain no private source URLs, provider credentials, device passwords, or
signing secrets. Publish these three files together:

- `dist/ottplay-roku-sideload.zip`: the native application with a root manifest.
- `dist/SHA256SUMS`: the ZIP's SHA-256 checksum.
- `dist/release.json`: package identity and build provenance.

A release must correspond to a reviewed source revision and pass the required
CI checks. Keep the source revision and package identity visible in release
metadata. The public download site must link to the actual release artifacts;
it must not imply that ZIP availability also means a Roku Beta app exists.

## Required device validation

Before inviting Roku Beta testers, test the exact release archive on a real
device and record the model, firmware, package hash, and result. At minimum:

- Install and launch, including the one-slot replacement behavior.
- Load the public demonstration playlist and a user-entered M3U URL.
- Navigate categories and channel selections using the physical remote.
- Start, stop, and switch supported streams; recover from a failing source.
- Save and restore settings, favorites, and selections across application exit.
- Verify that diagnostics do not expose private playlist or stream credentials.

Expand that evidence across supported models before claiming broad device
compatibility. Passing a compiler or a host-side BrightScript interpreter is
not a substitute for these checks.

## Produce the signed package later

Roku's documented signing process uses cryptographic hardware on a physical
Roku. The development device must be linked to the developer account and
connected to the internet. Signing happens through its Development Application
Installer; the GitHub ZIP itself is not a signed distributable package. See
[Packaging Roku apps](https://developer.roku.com/dev/docs/packaging-channels).

1. Use a device you control with Developer Mode enabled, and install the exact
   ZIP that passed testing. Installing a different source revision invalidates
   the relationship between the test result and the package being signed.
2. For a new application, create its signing identity using Roku's documented
   `genkey` procedure. For an existing application, retain its identity or use
   the documented rekey procedure with the previous `.pkg` and its password.
3. Store the signing password, Dev ID, and recovery package securely. Do not
   add them to the repository, public release, download page, or build logs.
4. Use the device's Packager to generate and download the signed `.pkg`.
5. Record the resulting package hash, matching source ZIP hash, app version,
   and signing identity in private release evidence before upload.

**Keep the same signing identity for updates.** Roku associates registry data
with the signing identity; changing it can discard access to saved app data.
Do not run `genkey` for every release. The
[official key-management guidance](https://developer.roku.com/dev/docs/packaging-channels)
also explains recovery through rekeying.

The Roku Cloud Emulator cannot replace the physical signing device. Its devices
are not keyed and the package-signing operation is unavailable. It can support
additional runtime testing, but cannot validate a companion service on the
same local network as a physical player. See
[RCE tooling limitations](https://developer.roku.com/dev/docs/rsg-sdk-standing-docs-advanced-rk-rce)
and [RCE known issues](https://developer.roku.com/dev/docs/rce-release-notes).

## Create and update a Roku Beta app

Use the publisher's own Roku developer account. Creating the app requires the
root account or Administrator; the App management role can manage package
uploads for an app already assigned to that user. See
[Roku roles and permissions](https://developer.roku.com/dev/docs/user-access-management).

After signing and device validation, create a Beta app in the Developer
Dashboard, complete the requested app details, and upload the `.pkg`. Only then
copy its real installation link/access code to the download page. Record the
creation date, expiry date, app identity, and uploaded package hash. Follow the
[official publishing procedure](https://developer.roku.com/dev/docs/channel-publishing-guide).

Roku's Beta program is temporary QA distribution:

- A Beta app expires **120 days after creation** and then stops working for
  installed users.
- Each app supports **20 test users**. This is a user limit, not a documented
  promise of twenty devices.
- An account can have **10 concurrent Beta apps**.
- Package updates within the same Beta app reach existing testers without
  issuing a new access code. Deleting and recreating the app needs a new code;
  it is not a seamless extension of the old installation.

These limits and the lack of required certification for Beta apps are specified
in [Roku's Beta rules](https://developer.roku.com/dev/docs/channel-publishing-guide).
Public Store distribution is a later, separate process requiring Roku review
and certification. A Beta app should not be presented as permanent private
distribution.

## Automation boundary

CI can prepare and verify the ZIP without device credentials. A future signing
job needs an explicitly selected, trusted physical device and secret handling;
it must preserve the exact tested input and existing signing identity.

Dashboard publication remains an explicit publisher operation in this preview.
No undocumented upload endpoint or browser-session credential is embedded in
the release tooling. Roku's current SDK configuration documentation states that
its `publishing` block is not consumed and directs Beta publication to the
[Developer Dashboard](https://developer.roku.com/dev/docs/rsg-sdk-standing-docs-core-concepts-app-configuration).
Do not mistake a successfully built ZIP for successful publication.

Official platform guidance in this document was checked on 2026-10-30. Recheck
the linked sources before expanding distribution or changing the signing flow.
