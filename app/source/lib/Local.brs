' Pure helper contract and playback queue. The token never enters a display label.
function localEndpoint(value as dynamic) as string
    if not safePlaylistUrl(value) then return ""
    if Instr(1, value, "?") > 0 or Instr(1, value, "#") > 0 then return ""
    if Right(value, 1) = "/" then value = Left(value, Len(value) - 1)
    parts = splitHttpUrl(value)
    if not CreateObject("roRegex", "^(/[A-Za-z0-9_-]+)*/offline-media/[A-Za-z0-9_-]{32,512}$", "").IsMatch(parts.path) then return ""
    return value
end function

function localId(value as dynamic) as boolean
    if not isText(value) then return false
    return CreateObject("roRegex", "^[A-Fa-f0-9]{32}$", "").IsMatch(value)
end function

function localInventory(value as dynamic) as object
    result = {sources: [], error: "The server did not return a Local folder inventory."}
    if Type(value) <> "roAssociativeArray" then return result
    if Type(value.sources) <> "roArray" then return result
    seen = {}
    seen.SetModeCaseSensitive()
    for each source in value.sources
        if Type(source) = "roAssociativeArray"
            if localId(source.id) and isText(source.name) and isText(source.kind)
                if source.kind = "folder" and not seen.DoesExist(source.id)
                    seen[source.id] = true
                    result.sources.Push({id: source.id, name: Left(source.name, 256), kind: "folder"})
                end if
            end if
        end if
        if result.sources.Count() >= 256 then exit for
    end for
    result.error = ""
    return result
end function

function localCatalog(value as dynamic, endpoint as string, sourceId as string) as object
    result = {channels: [], error: "The server did not return a progressive Local catalog.", pending: false, generation: "", skipped: 0, truncated: false, scanState: "", scanned: -1, foundCount: 0}
    if localEndpoint(endpoint) = "" or not localId(sourceId) then return result
    if Type(value) <> "roAssociativeArray" then return result
    if not localTrue(value.available) or Type(value.items) <> "roArray" or Type(value.sourceScans) <> "roArray" then return result
    selected = invalid
    for each scan in value.sourceScans
        if Type(scan) = "roAssociativeArray"
            if isText(scan.sourceId)
                if scan.sourceId = sourceId then selected = scan
            end if
        end if
    end for
    if selected = invalid then return result
    if not isText(selected.state) then return result
    if selected.state <> "pending" and selected.state <> "scanning" and selected.state <> "complete" and selected.state <> "error" then return result
    if not isLocalNumber(selected.generation) then return result
    result.generation = selected.generation.ToStr()
    result.scanState = selected.state
    ' Some helpers expose only library-wide scan work. Count that real progress
    ' too, so traversing a large tree of unsupported files has no total cap.
    if isLocalNumber(selected.scanned)
        result.scanned = selected.scanned
    else if isLocalNumber(value.scanned)
        result.scanned = value.scanned
    end if
    result.pending = selected.state = "pending" or selected.state = "scanning"
    result.error = ""
    if selected.state = "error" then result.error = "Folder discovery stopped. Available videos can still play; use Reload Local folder to retry."
    seen = {}
    seen.SetModeCaseSensitive()
    found = {}
    found.SetModeCaseSensitive()
    for each item in value.items
        if Type(item) = "roAssociativeArray"
            if isText(item.sourceId) and localId(item.id)
                if item.sourceId = sourceId and not found.DoesExist(item.id)
                    found[item.id] = true
                    result.foundCount = result.foundCount + 1
                end if
            end if
            if isText(item.sourceId) and localTrue(item.available) and localId(item.id) and isText(item.name) and isText(item.mime)
                if item.sourceId = sourceId
                    format = ""
                    if item.mime = "video/mp4" then format = "mp4"
                    if item.mime = "video/x-matroska" then format = "mkv"
                    if format <> ""
                        if not seen.DoesExist(item.id)
                            seen[item.id] = true
                            result.channels.Push({id: item.id, title: Left(item.name, 512), group: "Local videos", url: endpoint + "/" + item.id, logo: "", streamFormat: format})
                        end if
                    else
                        result.skipped = result.skipped + 1
                    end if
                end if
            end if
        end if
        if result.channels.Count() >= 20000
            result.truncated = true
            result.pending = false
            exit for
        end if
    end for
    return result
end function

function localProgressWatch(nowMs as integer) as object
    return {lastMs: nowMs, rank: -1, scanned: -1, count: -1}
end function

sub localProgressObserved(watch as object, snapshot as object, nowMs as integer)
    rank = 0
    if snapshot.scanState = "scanning" then rank = 1
    if snapshot.scanState = "complete" or snapshot.scanState = "error" then rank = 2
    changed = false
    if rank > watch.rank
        watch.rank = rank
        changed = true
    end if
    if snapshot.scanned > watch.scanned
        watch.scanned = snapshot.scanned
        changed = true
    end if
    if snapshot.foundCount > watch.count
        watch.count = snapshot.foundCount
        changed = true
    end if
    if changed then watch.lastMs = nowMs
end sub

function localProgressExpired(watch as object, nowMs as integer) as boolean
    return nowMs - watch.lastMs >= 300000
end function

function localProgressTimeout(snapshot as object) as object
    snapshot.pending = false
    snapshot.error = "No folder discovery progress for 5 minutes. Available videos remain; check the source and use Reload Local folder to retry."
    return snapshot
end function

function localTrue(value as dynamic) as boolean
    if Type(value) = "Boolean" or Type(value) = "roBoolean" then return value
    return false
end function

function isLocalNumber(value as dynamic) as boolean
    kind = Type(value)
    return kind = "Integer" or kind = "roInt" or kind = "LongInteger" or kind = "roLongInteger" or kind = "Double" or kind = "roDouble" or kind = "Float" or kind = "roFloat"
end function

function localNext(channels as object, played as object, shuffle as boolean, draw as float) as dynamic
    candidates = []
    for each channel in channels
        if not played.DoesExist(channel.id) then candidates.Push(channel)
    end for
    if candidates.Count() = 0 then return invalid
    index = 0
    if shuffle
        if draw < 0 then draw = 0
        if draw >= 1 then draw = 0.999999
        index = Int(draw * candidates.Count())
    end if
    return candidates[index]
end function

function localResultCurrent(result as dynamic, requestId as integer, sourceId as string, generation as string) as boolean
    if Type(result) <> "roAssociativeArray" then return false
    if result.requestId <> requestId or result.sourceId <> sourceId then return false
    if generation <> "" and result.generation <> generation then return false
    return true
end function
