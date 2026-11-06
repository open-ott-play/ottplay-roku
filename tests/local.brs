sub localTests()
    endpoint = "http://192.168.1.10:8090/offline-media/" + String(32, "t")
    source = String(32, "a")
    other = String(32, "b")
    first = String(32, "c")
    second = String(32, "d")
    eq(localEndpoint(endpoint + "/"), endpoint, "Local endpoint normalized")
    eq(localEndpoint(endpoint + "?secret=x"), "", "Local endpoint rejects query")
    eq(localEndpoint(endpoint + "/../../file"), "", "Local endpoint rejects traversal")
    eq(localEndpoint("http://user:secret@host/offline-media/" + String(32, "t")), "", "Local endpoint rejects userinfo")
    eq(localEndpoint("http://host/offline-media/short"), "", "Local endpoint rejects short token")
    eq(localEndpoint(invalid), "", "Missing Local endpoint rejected")
    check(not localId("../private"), "Only opaque Local IDs accepted")
    inventory = localInventory({sources: [{id: source, name: "Movies", kind: "folder", path: "/private"}, {id: other, name: "File", kind: "file"}, {id: source, name: "Duplicate", kind: "folder"}]})
    eq(inventory.sources.Count(), 1, "Only unique folder bindings exposed")
    check(not inventory.sources[0].DoesExist("path"), "Private fields never copied from descriptors")
    check(localInventory({items: []}).error <> "", "Legacy endpoint without inventory rejected")
    eq(localInventory({sources: [{id: source, name: "Bad", kind: {}}]}).sources.Count(), 0, "Malformed descriptor kind ignored")
    firstItem = {id: first, sourceId: source, name: "First.mp4", mime: "video/mp4", available: true, url: "http://evil.example/"}
    secondItem = {id: second, sourceId: source, name: "Second.mkv", mime: "video/x-matroska", available: true}
    snapshot = {available: true, items: [firstItem], sourceScans: [{sourceId: source, generation: 7, state: "scanning"}, {sourceId: other, generation: 1, state: "scanning"}]}
    result = localCatalog(snapshot, endpoint, source)
    eq(result.channels.Count(), 1, "First video published while scan is unfinished")
    check(result.pending, "Selected source pending state retained")
    eq(result.channels[0].url, endpoint + "/" + first, "Media stays on configured authenticated endpoint")
    eq(result.channels[0].streamFormat, "mp4", "Extensionless endpoint gets native MP4 format")
    played = {}
    eq(localNext(result.channels, played, true, 0.9).id, first, "First item immediately eligible for shuffle")
    played[first] = true
    check(localNext(result.channels, played, true, 0.4) = invalid, "EOF does not repeat while waiting for discovery")
    snapshot.items.Push(secondItem)
    result = localCatalog(snapshot, endpoint, source)
    eq(localNext(result.channels, played, true, 0.1).id, second, "New file joins ongoing shuffle without replay")
    eq(result.channels[1].streamFormat, "mkv", "MKV format comes from MIME")
    snapshot.sourceScans[0].state = "complete"
    result = localCatalog(snapshot, endpoint, source)
    check(not result.pending, "Other stalled source cannot prolong selected source playback")
    played[second] = true
    check(localNext(result.channels, played, false, 0) = invalid, "Completed queue ends without cycling")
    played = {}
    eq(localNext(result.channels, played, false, 0.9).id, first, "Sequential order remains stable")
    eq(localNext(result.channels, played, true, 0.9).id, second, "Shuffle can choose later ready file")
    snapshot.items.Push({id: String(32, "e"), sourceId: other, name: "Foreign", mime: "video/mp4", available: true})
    snapshot.items.Push({id: String(32, "f"), sourceId: source, name: "Unavailable", mime: "video/mp4", available: false})
    snapshot.items.Push({id: "../secret", sourceId: source, name: "Invalid", mime: "video/mp4", available: true})
    snapshot.items.Push({id: String(32, "1"), sourceId: source, name: "AVI", mime: "video/x-msvideo", available: true})
    snapshot.items.Push(firstItem)
    result = localCatalog(snapshot, endpoint, source)
    eq(result.channels.Count(), 2, "Filter source availability ID format and duplicates")
    eq(result.skipped, 1, "Unsupported video format counted")
    snapshot.sourceScans[0].state = "error"
    result = localCatalog(snapshot, endpoint, source)
    check(result.error <> "" and not result.pending, "Scan error ends polling but keeps ready videos")
    eq(result.channels.Count(), 2, "Ready files survive source scan error")
    check(localCatalog({available: true, items: []}, endpoint, source).error <> "", "Full scan legacy catalog not silently accepted")
    check(localCatalog({available: {}, items: [], sourceScans: []}, endpoint, source).error <> "", "Malformed availability rejected")
    check(localCatalog({available: true, items: [], sourceScans: [{sourceId: source, state: {}, generation: 1}]}, endpoint, source).error <> "", "Malformed scan state rejected")
    malformed = {available: true, items: [{id: first, sourceId: source, name: "Bad", available: true, mime: {}}], sourceScans: [{sourceId: source, state: "complete", generation: 1}]}
    eq(localCatalog(malformed, endpoint, source).channels.Count(), 0, "Malformed MIME ignored")
    check(localCatalog(snapshot, endpoint, String(32, "9")).error <> "", "Missing source state cannot broaden selection")
    current = {requestId: 10, sourceId: source, generation: "7"}
    check(localResultCurrent(current, 10, source, "7"), "Current source generation accepted")
    check(not localResultCurrent(current, 11, source, "7"), "Cancelled old request cannot publish")
    check(not localResultCurrent(current, 10, other, "7"), "Old folder cannot publish after switch")
    check(not localResultCurrent(current, 10, source, "8"), "Stale generation rejected")
    raw = "{""version"":1,""mode"":""local"",""localEndpoint"":""" + endpoint + """,""localSourceId"":""" + source + """,""localSourceName"":""Movies"",""localShuffle"":true}"
    state = readPlayerState(raw)
    eq(state.mode, "local", "Local mode restored")
    eq(state.localEndpoint, endpoint, "Private endpoint restored only in app state")
    eq(state.localSourceId, source, "Stable selected folder restored")
    check(state.localShuffle, "Shuffle choice restored")
    eq(readPlayerState("{""version"":1,""mode"":""local""}").mode, "playlist", "Incomplete Local state safely falls back")
    watch = localProgressWatch(0)
    progress = {scanState: "pending", scanned: 0, foundCount: 0}
    localProgressObserved(watch, progress, 0)
    localProgressObserved(watch, progress, 299999)
    check(not localProgressExpired(watch, 299999), "Unchanged catalog remains within inactivity window")
    check(localProgressExpired(watch, 300000), "Unchanged successful catalog has bounded wait")
    progress.scanState = "scanning"
    localProgressObserved(watch, progress, 300000)
    check(not localProgressExpired(watch, 599999), "Forward scan state renews inactivity window")
    progress.foundCount = 1
    localProgressObserved(watch, progress, 590000)
    check(not localProgressExpired(watch, 880000), "Discovered file renews inactivity window")
    progress.scanned = 100
    localProgressObserved(watch, progress, 880000)
    check(not localProgressExpired(watch, 1170000), "Real scan counter progress renews window")
    progress.scanned = 90
    progress.foundCount = 0
    progress.scanState = "pending"
    localProgressObserved(watch, progress, 1170000)
    check(localProgressExpired(watch, 1180000), "Regressing counters and state cannot renew window")
    watch = localProgressWatch(0)
    for i = 0 to 40
        progress = {scanState: "scanning", scanned: i, foundCount: 0}
        localProgressObserved(watch, progress, i * 240000)
        check(not localProgressExpired(watch, i * 240000 + 239999), "Progressing folder has no total duration cap")
    end for
    snapshot.sourceScans[0].state = "scanning"
    snapshot.scanned = 123
    result = localCatalog(snapshot, endpoint, source)
    eq(result.scanned, 123, "Library scan progress renews work even without new playable files")
    snapshot.sourceScans = [snapshot.sourceScans[0]]
    result = localCatalog(snapshot, endpoint, source)
    eq(result.scanned, 123, "Single selected source can use global scan counter")
    timed = localProgressTimeout(result)
    eq(timed.channels.Count(), 2, "Timeout preserves ready catalog")
    check(not timed.pending and timed.error <> "", "Timeout ends pending state with retry guidance")
end sub
