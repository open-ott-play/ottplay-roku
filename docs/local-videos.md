# Local videos on Roku

Local videos plays folders shared by an OTT read-only media helper. The helper
owns folder permissions and scans the files; Roku browses its catalog and streams
available MP4/MKV files with its native Video decoder. Roku does not mount AFP,
SMB or USB folders through this feature. A supported container still needs audio
and video codecs supported by the particular Roku model.

## Connect a folder

1. Configure your OTT helper with the folders you intend to share. It must include
   the lightweight `/sources` inventory and selected-source progressive catalog
   described below. Older helper builds without that inventory report an error.
2. Make the helper endpoint reachable from the Roku. A helper build supporting
   private-LAN opt-in can bind the Mac's specific private interface using
   `--listen-address <private-IP> --allow-lan` in its installer. Loopback remains
   the default. With an older loopback-only helper, use an operator-controlled
   HTTPS reverse proxy preserving token authentication, streaming and byte ranges,
   with catalog caching disabled. A `127.0.0.1` URL alone cannot work on a Roku.
3. Open **Options → Local videos** and enter the private URL ending in
   `/offline-media/<token>`. Select the shared folder. The first available video
   starts without waiting for discovery to finish.

The URL is a credential. It is entered in a masked field, saved in the app's
registry and omitted from status/error labels. **Server settings → Forget Local
server** removes the saved endpoint and folder and returns to M3U. The registry
is not an encrypted secret vault. Do not post the URL in screenshots or logs.
HTTP works on a trusted local network if intentionally configured, but does not
encrypt the credential or video traffic. No gateway is installed by the Roku app.

The helper configuration and loopback restriction are documented in
[OTT's helper guide](https://github.com/open-ott-play/ottplay-foss/blob/main/docs/local-media-helper.md).

## Playback and slow connections

- A folder selection starts a new session. Its folder, endpoint and shuffle
  preference are saved; reopening the app starts that folder again. Playback
  position and the completed session's history are not persisted.
- **Shuffle all videos** starts a random order over files already available.
  Files discovered later join the session without replaying finished files.
  **Play all in order** returns to the server's catalog order.
- EOF advances to an unplayed file. If none is ready but discovery is still
  running, the list displays a waiting message and starts the next arrival.
  Once discovery and the queue finish, playback stops.
- **Next video** skips the current file. Three consecutive startup failures stop
  automatic advancement so an incompatible folder does not retry indefinitely.
- **Back** stops playback and cancels this app's outstanding catalog request and
  automatic advancement. Available entries remain selectable. It does not cancel
  shared work used by other helper clients or delete server files.
- **Reload Local folder** explicitly retries discovery. Ordinary polling does
  not restart the scan. Changing folders or leaving rejects late results from
  the previous request.

Only catalog JSON is downloaded into a temporary file, limited to 8 MiB and
45 seconds per request; size can briefly exceed the cap between checks. There is
one request at a time. Empty queues poll after one second; while video is
available, polls wait fifteen seconds to leave bandwidth for playback. An empty
queue at EOF can shorten that delay. Five minutes with no increasing scanned or
discovered count, or forward scan-state transition, ends polling and displays
retry guidance. Already playable entries remain available. There is no fixed
total timeout for a progressing folder; a helper's library-wide scan counter can
also renew this window while another folder advances. The UI retains at most 20,000 playable
entries and reports truncation. Use smaller shared folders for larger catalogs.

AVI, WebM, Ogg and audio-only files are skipped. This version uses direct MP4/MKV
streaming, not the helper's optional transcoding leases. An unsupported codec
produces a playback error even if its MP4/MKV container is listed. M3U favorites
remain separate from Local videos.

## Contract used by this adapter

The contract is the shared `ottplay-core` offline-media library, reviewed from
FOSS base `2ff0d957511d4f1be39e80b99f40f3706f684dfc` plus its progressive startup
and source-inventory changes. It does not have a numeric schema-version field.
The adapter checks required structures and rejects missing/unknown scan states;
it does not silently fall back to a blocking full-library scan.

- `GET <endpoint>/sources` returns `sources` with opaque `id`, display `name` and
  `kind`. Only `folder` bindings appear in the picker. Availability and private
  paths are not required or copied.
- `GET <endpoint>?sourceId=<id>` returns `available`, `items` and `sourceScans`.
  `refresh=true` is sent only on the first poll of an explicit reload. Item fields
  used are `id`, `sourceId`, `name`, `mime` and `available`. IDs must be 32 hex
  characters. Media addresses are constructed as `<endpoint>/<id>`.
- The selected source's `generation` is retained for the request; its `state`
  is `pending`, `scanning`, `complete` or `error`. Unrelated stalled sources do
  not prevent completion. A changed generation ends the old session.
- Every endpoint includes the private capability token. Refused authentication,
  missing inventory, a disconnected binding or invalid JSON produce an actionable
  error. No request uploads files, changes permissions or deletes data.

## Qualification

Host checks run production BrightScript parsing, filtering, identity, incremental
queue, shuffle and persistence helpers. An executable fixture calls the actual
Local controller with stub render/video boundaries to verify first-item adoption,
later batches, EOF, cancellation, source generation and inactivity errors. Checks
also compile SceneGraph components and verify package structure. They do not
emulate firmware's Video, HTTP transfer cancellation,
secure text box or registry behavior. Before offering a tested Roku package, use
a real device with a controlled helper:

1. Make one MP4 available while a sibling scan is gated. Confirm video begins
   before releasing the sibling, including a nested-only ready directory.
2. Append a second file while the first plays; verify EOF/Next and shuffle play
   each ID once, wait while the selected scan is pending, and stop at completion
   even if another source remains blocked.
3. Press Back during a pending transfer, change folders quickly and exit/reopen.
   Confirm old results never play and the saved folder/shuffle setting returns.
4. Verify invalid token, removed binding, missing file, malformed response,
   changed generation, timeout, range/seek and three unsupported-codec failures.
5. Verify Options/folder navigation, masked entry, registry persistence, Forget
   and existing M3U/favorites. Keep private URLs out of recordings.

Roku API references: [Task](https://developer.roku.com/dev/docs/task),
[asynchronous transfers](https://developer.roku.com/dev/docs/ifurltransfer),
[native video](https://developer.roku.com/dev/docs/playing-videos),
[keyboard dialog](https://developer.roku.com/dev/docs/standard-keyboard-dialog),
[registry limits](https://developer.roku.com/dev/docs/roregistry).
