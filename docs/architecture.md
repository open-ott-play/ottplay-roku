# Architecture and repository decision

Status: accepted for the initial `0.1.0-beta.1` developer preview.

## One native application, two distribution formats

OTT Play for Roku uses conventional BrightScript and SceneGraph. Its first
scope is a user-supplied M3U playlist, a native channel list, categories,
device-local favorites, saved settings, and Roku's native Video playback.
The application is not a browser wrapper around the existing web player.

The same source tree produces a sideload ZIP and can later be signed on a
physical Roku to produce a distributable `.pkg`. These are different packaging
steps, not separate implementations. The initial preview provides the ZIP;
it does not claim a signed package or an active Roku Beta app.

RSG 2.0 is not the baseline for this client. At the time of this decision its
public beta is restricted to sideloading, while BrightScript remains supported.
RSG 2.0 also renders SceneGraph nodes rather than HTML/CSS, so adopting it would
not make the existing web player run unchanged. Revisit that choice when its
distribution support and our requirements justify a migration. See the
[official SDK overview](https://developer.roku.com/dev/docs/rsg-sdk-standing-docs-getting-started-overview).

## Why a separate repository

The application lives in `open-ott-play/ottplay-roku`, rather than adding
`native/roku` to the web player repository.

- Roku has its own runtime, input model, playback engine, signing identity,
  installation procedure, and device verification requirements.
- A Roku fix can ship independently of a web, desktop, or Android release.
- A missing Roku signer must not block an otherwise valid web player release.
- The shared core and other native clients already have separate ownership
  boundaries; Roku follows that structure.

The cost is explicit compatibility management across repositories. We accept
that cost rather than copying web implementation details into BrightScript.
The Roku package version is independent of the web player's package version.
Source revision and archive hashes identify an exact Roku build.

## Runtime boundaries

The UI uses SceneGraph components. Network loading and playlist parsing belong
in a Task so that a slow playlist does not intentionally block UI navigation.
The parsed list becomes native content items; the Video node owns playback.
The application stores its source and selection settings in its own Roku
registry. The download site does not receive these settings or stream video.

The packaged demonstration content is public sample material. A private source
is entered on the device after installation. Do not embed personal playlists,
device tokens, provider passwords, or signing credentials in the package.
Registry storage should not be treated as a dedicated encrypted secret vault.

The first preview has device-local favorites shared across M3U sources used
within this Roku client. It accepts at most 100 entries, and the complete saved
state must also fit its 24 KiB registry budget; long source URLs can reach that
budget before the entry limit. These favorites are not yet the shared
cross-provider favorites format of the other OTT players. Importing a complete
OTT profile, pairing with the controller, and `ott` CLI control are not
implemented. Plex, VPortal, Stalker, DRM, local-folder access, and an on-device
torrent engine are outside this preview's implemented scope. A NAS-hosted HTTP
playlist or video is a network source, not local-folder support.

## Shared-contract roadmap

Integration with `ottplay-core` and the controller should exchange data through
versioned JSON contracts, not load their browser implementation into Roku.
The next adapters need all of the following before being advertised:

1. A pinned upstream contract revision, explicit schema version, and shared
   valid/invalid fixture cases exercised by the BrightScript implementation.
2. Capability reporting that distinguishes supported M3U playback from
   unsupported provider types and commands.
3. Stable source and content identities for profile imports and favorites;
   a channel's current list number is not a portable identity.
4. Resolution of an imported favorite through its provider/profile context,
   including an actionable failure when that context is unavailable.
5. Authenticated pairing, bounded requests, cancellation, and deliberate
   credential storage before remote-control support is enabled.

These are follow-up compatibility requirements, not capabilities of the first
ZIP. Until adapters pass their fixtures and device checks, unsupported imports
must be rejected or remain unavailable rather than silently treated as M3U.

## Verification boundary

Compiler checks, host-side pure-function tests, packaging checks, and archive
reproducibility can run without a Roku. They do not validate the Video decoder,
remote key handling, SceneGraph focus, registry persistence across real device
restarts, or firmware-specific network behavior. The first preview has not been
validated on hardware. The [release guide](release.md) records the additional
checks required before a Roku Beta app is offered to testers.
