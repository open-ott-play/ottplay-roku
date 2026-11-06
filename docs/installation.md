# Install the Roku developer preview

The initial preview is a native M3U player packaged as a **sideload ZIP**.
It has not been tested on a physical Roku. A GitHub prerelease does not mean
that a signed Roku Beta app is available.

The separate [download site](https://roku.ottplay.here.now/) provides installation
instructions and release downloads. It does not install itself by opening that
URL on a television, and it does not replace the existing web player site.

## Download and verify

Download `ottplay-roku-sideload.zip`, `SHA256SUMS`, and `release.json` from the
same release of [the repository](https://github.com/open-ott-play/ottplay-roku/releases).
Keep them together. `release.json` records the build identity; `SHA256SUMS`
allows you to check that the downloaded archive matches the release bytes.

On macOS:

```sh
shasum -a 256 -c SHA256SUMS
```

On a system with GNU coreutils:

```sh
sha256sum -c SHA256SUMS
```

Do not unpack and re-zip the release before installation. The archive contains
the application manifest at its root, which the Roku installer expects.

## Sideload on your own Roku

You need a Roku enrolled for development, a computer that can reach it on the
local network, and the developer installer password that you set on that Roku.
**There is only one sideload slot per device. Installing this preview replaces
the application currently using that slot.** Roku documents this behavior in
its [developer setup guide](https://developer.roku.com/dev/docs/developer-setup).

1. Enable Developer Mode using Roku's
   [official instructions](https://developer.roku.com/dev/docs/developer-setup).
   Record the local installer address and choose a private developer password.
2. Open that local address from your computer. Sign in as `rokudev` with the
   password you selected on the Roku.
3. In the Development Application Installer, upload
   `ottplay-roku-sideload.zip` and install it.
4. The preview should launch. Use its playlist setting to enter a supported
   M3U URL, or start with the bundled demonstration playlist.

Keep the developer installer on a trusted local network. Do not forward its
port to the internet, enter its password into the public download site, or
include that password in an issue report.

Roku may reject reinstalling an identical archive. That alone is not evidence
of a broken build. Confirm the installed version and the intended ZIP before
replacing or deleting anything. The official setup guide describes this case.

## Sources and settings

Use Left/Right to move between categories and channels, Up/Down to move within
a list, and OK to select a category or play a channel. Press `*` for Options:
add/remove the selected or playing channel from Favorites, edit the playlist
URL, reload it, or return to the demo. Groups come from the M3U's `group-title`
or `#EXTGRP` metadata; entries without a group appear under Other.

Back stops video and returns to the list. From the browser it cancels an active
load, returns to categories, or opens the exit confirmation. During playback,
transport controls use the native Video component's behavior; successful
seeking depends on the stream. Physical-remote behavior still needs device
validation.

The last M3U selection is saved without automatically resuming it at startup.
When Local is the saved source, reopening starts a new session in its saved
folder as soon as a playable video arrives. Favorites stay available across
this client's M3U sources. The maximum is 100 entries within a 24 KiB budget for all saved state;
long URLs may fill that budget earlier.

The preview reads a playlist URL and plays supported HTTP/HTTPS media using
Roku's native playback engine. A playable URL on a computer is not proof that
its container, video codec, audio codec, authentication scheme, or DRM is
supported by your Roku model. Use a simple known-compatible source first.

Playlist downloads have a 20-second timeout and are written to a temporary
file. The app checks its size periodically and refuses to parse more than
8 MiB; a transfer can briefly exceed that size between checks. It displays at
most 20,000 entries and reports truncation. It does not yet stream a partial
catalog into the list while parsing.

**Local videos** in Options is a separate progressive folder source. Connect an
OTT media helper through a Roku-reachable endpoint, select a folder, and the
first available MP4/MKV video starts while discovery continues. See
[Local videos setup](local-videos.md), including the loopback helper's gateway
requirement, shuffle controls and cancellation behavior.

Relative media URLs resolve against the playlist address you entered. If a
provider redirects that address to another directory or host, use its final
playlist URL or a playlist containing absolute media URLs. The preview does
not discover a different final base URL after redirects.

For a NAS-hosted source, the Roku must be able to reach the NAS address in both
the playlist URL and each media entry. `localhost` on a Roku refers to the Roku,
not your Mac or NAS. Mount paths such as `/Volumes/Movies` and SMB/AFP shares are
not media URLs understood by this preview. Publish supported files through a
server you control if network playback is needed.

Favorites and settings belong to this client. Importing another player's full
profile or shared favorites is not implemented. See
[the architecture scope](architecture.md) before expecting provider parity.
EPG data and playlist poster artwork are not displayed in this preview.

HTTPS is recommended for private sources. The playlist address and saved
favorites may contain access credentials; keep screenshots and diagnostic
reports free of complete private URLs. Credentials are entered at runtime and
must not be put into a redistributable ZIP.

## Building without a device

From a checkout with Node.js 22 or 24 and Python 3 installed:

```sh
npm ci
npm run verify
```

The release files are written under `dist/`. This verifies source and packaging
on the host; it does not simulate a complete Roku or establish hardware
playback compatibility. See [release and signing](release.md) for the later
device-validation and signed-package steps.

### Optional command-line sideload, when a device is available

The repository includes an explicit opt-in installer. Set `ROKU_HOST` to your
device's IP address or hostname, and supply `ROKU_PASSWORD` through your local
secret environment. It is the Developer Mode password, not your Roku account
password. Then run:

```sh
npm run sideload -- --confirm
```

This uploads the built ZIP directly to that one device and replaces its
existing sideloaded app. `--archive /path/to/ottplay-roku-sideload.zip` selects
another downloaded build. Do not run it until you intend that replacement.
An installer success response still requires checking startup and playback on
the Roku; no command-line installation has been performed for the initial
device-free preview.

## Future Beta app installation

There is no Beta access code in the initial ZIP release. After device testing,
signing, and creation of a Beta app in the publisher's Roku Dashboard, the
download site can provide its actual installation link. Testers then use that
link with their Roku account instead of the developer sideload installer.
That future route has Roku's time and tester limits, described in the
[release guide](release.md).
