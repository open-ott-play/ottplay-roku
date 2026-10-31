# OTT Play for Roku

A native BrightScript / SceneGraph client for user-supplied M3U playlists.
This repository has its own release cycle and produces a sideload ZIP. The
same app can be packaged on a physical Roku for a temporary Roku Beta app.

**Initial developer preview.** Automated compilation and host-side tests do
not establish playback or remote-control correctness on real hardware. A
device test is required before creating a Roku Beta app.

- [Downloads and installation](https://roku.ottplay.here.now/)
- [Installation guide](docs/installation.md)
- [Release and signing guide](docs/release.md)
- [Architecture and repository decision](docs/architecture.md)

## First preview

- Native SceneGraph channel list, categories, and Roku Video playback.
- An editable playlist URL and a bundled demonstration playlist.
- Persistent local favorites, source URL, selected category, and channel.
- A reproducible sideload ZIP, checksum file, and release provenance.

This is a separate native client, not a website in a Roku browser. The here.now
site hosts downloads and instructions. It does not run the player on Roku.
Media support depends on the Roku model and its native decoders.

## Develop

```sh
npm ci
npm test
npm run build
```

The output is `dist/ottplay-roku-sideload.zip`. Upload it to the Development
Application Installer on a Roku with Developer Mode enabled. Roku has one
sideload slot; installing this preview replaces the app currently in that slot.
See the installation guide for the optional command-line installer.

## Scope

The first preview implements a local M3U client. Cross-player favorites import,
controller pairing, `ott` CLI commands, Plex, VPortal, Stalker, DRM, and an on-device
torrent engine are not implemented. Do not load a full OTT profile expecting all
providers to work. Future adapters must use versioned contracts and report their
actual capabilities; they must not silently treat an unsupported provider as M3U.

HTTPS is recommended for private playlist URLs. Source URLs and favorites are
stored in the Roku app registry, not uploaded to the download site. Do not put
private playlists, passwords, or signing keys in a public package or repository.

## Distribution

GitHub prereleases contain a **sideload ZIP**, not a signed Roku `.pkg` and not a
Roku Beta access code. Creating the signed package requires a physical Roku.
Roku Beta apps are temporary QA installations with platform limits; see the
release guide before inviting testers. Public Store distribution requires Roku
review and certification.

MIT licensed. Roku is a trademark of Roku, Inc. This community project is not
affiliated with or endorsed by Roku, Inc.
