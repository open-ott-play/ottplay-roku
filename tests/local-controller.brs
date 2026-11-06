' Executes the actual LocalScene controller. Only UI/video boundaries are stubs.
sub Main()
    m.assertions = 0
    m.failures = 0
    resetController()
    first = String(32, "c")
    second = String(32, "d")
    third = String(32, "e")
    onLocalResult(controllerEvent(controllerSnapshot([first], "scanning")))
    eq(m.started.Count(), 1, "First partial catalog immediately starts playback")
    eq(m.started[0], first, "First available ID adopted")
    onLocalResult(controllerEvent(controllerSnapshot([first], "scanning")))
    eq(m.started.Count(), 1, "Repeated partial catalog does not restart playback")
    onLocalResult(controllerEvent(controllerSnapshot([first, second], "scanning")))
    eq(m.started.Count(), 1, "Later batch does not interrupt current file")
    eq(m.catalog.Count(), 2, "Later batch joins controller catalog")
    localPlaybackEnded(false)
    eq(m.started.Count(), 2, "EOF advances to newly discovered file")
    eq(m.started[1], second, "EOF avoids already played ID")
    localPlaybackEnded(false)
    check(m.playingEntry = invalid and m.localAuto, "EOF keeps pending session waiting")
    check(m.task.urgent, "Empty queue requests prompt next catalog poll")
    onLocalResult(controllerEvent(controllerSnapshot([first, second, third], "scanning")))
    eq(m.started.Count(), 3, "Append after pending EOF resumes playback")
    eq(m.started[2], third, "Append selects unplayed file")
    onLocalResult(controllerEvent(controllerSnapshot([first, second, third], "complete")))
    eq(m.started.Count(), 3, "Completion snapshot does not restart current file")
    localPlaybackEnded(false)
    check(m.playingEntry = invalid and not m.localAuto, "Completed source ends exhausted session")

    resetController()
    old = controllerSnapshot([first], "scanning")
    heldTask = m.task
    cancelLoad(false)
    check(heldTask.cancelled, "Actual cancellation notifies outstanding task")
    check(m.task = invalid and not m.loading, "Actual cancellation drops task and loading state")
    onLocalResult(controllerEvent(old))
    eq(m.started.Count(), 0, "Late cancelled callback cannot start playback")
    eq(m.catalog.Count(), 0, "Late cancelled callback cannot replace catalog")

    resetController()
    old = controllerSnapshot([first], "scanning")
    m.state.localSourceId = String(32, "b")
    onLocalResult(controllerEvent(old))
    eq(m.started.Count(), 0, "Previous source callback cannot start new source session")

    resetController()
    onLocalResult(controllerEvent(controllerSnapshot([first], "scanning")))
    changed = controllerSnapshot([second], "scanning")
    changed.generation = "2"
    onLocalResult(controllerEvent(changed))
    eq(m.started.Count(), 1, "Changed generation cannot adopt another file")
    check(not m.localAuto and m.playingEntry = invalid, "Changed generation cancels current session")
    check(Instr(1, m.status.text, "Reload") > 0, "Changed generation provides recovery action")

    resetController()
    m.dialogKind = "options"
    onLocalResult(controllerEvent(controllerSnapshot([first], "scanning")))
    eq(m.started.Count(), 0, "Catalog adoption cannot steal focus from options")
    m.dialogKind = ""
    playNextLocal()
    eq(m.started.Count(), 1, "Closing options can resume pending queue exactly once")
    playNextLocal()
    eq(m.started.Count(), 1, "Repeated queue wake does not restart current video")
    timed = localProgressTimeout(controllerSnapshot([first], "scanning"))
    onLocalResult(controllerEvent(timed))
    eq(m.catalog.Count(), 1, "Inactivity timeout retains available video")
    check(not m.loading and not m.localPending, "Inactivity timeout ends catalog polling state")
    eq(m.started.Count(), 1, "Inactivity timeout does not interrupt ready playback")
    localPlaybackEnded(false)
    check(Instr(1, m.status.text, "5 minutes") > 0, "EOF preserves actionable discovery timeout")

    resetController()
    onLocalResult(controllerEvent(controllerSnapshot([first, second, third, String(32, "f")], "complete")))
    localPlaybackEnded(true)
    localPlaybackEnded(true)
    localPlaybackEnded(true)
    eq(m.started.Count(), 3, "Three failed files stop automatic attempts")
    check(not m.localAuto and m.playingEntry = invalid, "Failure limit returns to stopped session")
    if m.failures = 0
        print "[OTT CONTROLLER RESULT] PASS "; m.assertions
    else
        print "[OTT CONTROLLER RESULT] FAIL "; m.failures
    end if
end sub

sub resetController()
    m.state = {mode: "local", localSourceId: String(32, "a"), localShuffle: false}
    m.requestId = 7
    m.localGeneration = ""
    m.localPending = true
    m.localAuto = true
    m.localPlayed = {}
    m.localFailures = 0
    m.localDiscoveryError = ""
    m.playingEntry = invalid
    m.loading = true
    m.task = {cancelled: false, urgent: false, UnobserveField: sub(field as string)
    end sub}
    m.catalog = []
    m.started = []
    m.status = {text: ""}
    m.dialogKind = ""
end sub

function controllerSnapshot(ids as object, state as string) as object
    source = String(32, "a")
    value = {available: true, items: [], sourceScans: [{sourceId: source, state: state, generation: 1}]}
    for each id in ids
        value.items.Push({id: id, sourceId: source, name: "Video", mime: "video/mp4", available: true})
    end for
    result = localCatalog(value, "http://192.168.1.2/offline-media/" + String(32, "t"), source)
    result.kind = "catalog"
    result.sourceId = source
    result.requestId = 7
    return result
end function

function controllerEvent(payload as object) as object
    return {payload: payload, GetData: function() as object
        return m.payload
    end function}
end function

' Stub only the Video/render boundary, preserving its visible bookkeeping.
sub playEntry(entry as object)
    m.started.Push(entry.channel.id)
    m.playingEntry = entry
    m.localPlayed[entry.channel.id] = true
    if m.task <> invalid then m.task.urgent = false
end sub

sub stopVideo(restore as boolean)
    m.playingEntry = invalid
end sub

sub renderChannels()
end sub

sub check(condition as boolean, label as string)
    m.assertions = m.assertions + 1
    if not condition
        m.failures = m.failures + 1
        print "[FAIL] "; label
    end if
end sub

sub eq(actual as dynamic, expected as dynamic, label as string)
    check(actual = expected, label)
end sub
