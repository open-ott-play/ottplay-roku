sub init()
    m.top.functionName = "loadLocal"
end sub

sub loadLocal()
    endpoint = localEndpoint(m.top.endpoint)
    sourceId = m.top.sourceId
    if endpoint = "" then return
    if sourceId = ""
        response = localGet(endpoint + "/sources")
        result = localInventory(response.value)
        if response.error <> "" then result.error = response.error
        result.kind = "inventory"
        publishLocal(result)
        return
    end if
    if not localId(sourceId) then return
    generation = ""
    refresh = m.top.refresh
    progressClock = CreateObject("roTimespan")
    progressClock.Mark()
    progress = localProgressWatch(0)
    lastResult = invalid
    while not m.top.cancelled
        if lastResult <> invalid and localProgressExpired(progress, progressClock.TotalMilliseconds())
            publishLocal(localProgressTimeout(lastResult))
            return
        end if
        url = endpoint + "?sourceId=" + sourceId
        if refresh then url = url + "&refresh=true"
        refresh = false
        response = localGet(url)
        result = localCatalog(response.value, endpoint, sourceId)
        result.kind = "catalog"
        if response.error <> "" then result.error = response.error
        if generation <> "" and result.generation <> "" and result.generation <> generation
            result.error = "This folder changed during discovery. Reload Local folder to start a new session."
            result.channels = []
            result.pending = false
        end if
        if result.generation <> "" then generation = result.generation
        if result.error = ""
            localProgressObserved(progress, result, progressClock.TotalMilliseconds())
            if result.pending and localProgressExpired(progress, progressClock.TotalMilliseconds()) then result = localProgressTimeout(result)
        end if
        lastResult = result
        publishLocal(result)
        if response.error <> "" or result.error <> "" or not result.pending then return
        delay = 1000
        if result.channels.Count() > 0 then delay = 15000
        clock = CreateObject("roTimespan")
        clock.Mark()
        ' Keep cancellation responsive between bounded, non-overlapping polls.
        while clock.TotalMilliseconds() < delay
            if m.top.cancelled then return
            if localProgressExpired(progress, progressClock.TotalMilliseconds()) then exit while
            if m.top.urgent and clock.TotalMilliseconds() >= 1000 then exit while
            Sleep(100)
        end while
    end while
end sub

sub publishLocal(value as object)
    if m.top.cancelled then return
    value.requestId = m.top.requestId
    value.sourceId = m.top.sourceId
    m.top.result = value
end sub

function localGet(url as string) as object
    result = {value: invalid, error: "Could not connect to the Local server. Check its address and the network, then reload."}
    port = CreateObject("roMessagePort")
    request = CreateObject("roUrlTransfer")
    request.SetMessagePort(port)
    request.SetCertificatesFile("common:/certs/ca-bundle.crt")
    request.InitClientCertificates()
    request.SetUrl(url)
    request.AddHeader("Accept", "application/json")
    request.SetMinimumTransferRate(1, 30)
    path = "tmp:/ottplay-local-" + m.top.requestId.ToStr() + ".json"
    DeleteFile(path)
    filesystem = CreateObject("roFileSystem")
    if not request.AsyncGetToFile(path)
        DeleteFile(path)
        return result
    end if
    clock = CreateObject("roTimespan")
    clock.Mark()
    while clock.TotalMilliseconds() < 45000
        if m.top.cancelled
            request.AsyncCancel()
            DeleteFile(path)
            return result
        end if
        info = filesystem.Stat(path)
        if info <> invalid
            if info.size > 8388608
                request.AsyncCancel()
                DeleteFile(path)
                result.error = "Local catalog exceeds 8 MiB. Share a smaller folder."
                return result
            end if
        end if
        event = Wait(100, port)
        if Type(event) = "roUrlEvent"
            if event.GetSourceIdentity() = request.GetIdentity()
                code = event.GetResponseCode()
                if code >= 200 and code < 300
                    info = filesystem.Stat(path)
                    if info <> invalid
                        if info.size <= 8388608
                            result.value = ParseJson(ReadAsciiFile(path))
                            result.error = ""
                        else
                            result.error = "Local catalog exceeds 8 MiB. Share a smaller folder."
                        end if
                    end if
                else if code = 401 or code = 403
                    result.error = "Local server access was refused. Enter its current private link."
                else if code = 404
                    result.error = "Local folder or inventory is unavailable. Check the helper version and shared folders."
                else if code > 0
                    result.error = "Local server returned HTTP " + code.ToStr() + ". Reload to retry."
                end if
                DeleteFile(path)
                return result
            end if
        end if
    end while
    request.AsyncCancel()
    DeleteFile(path)
    result.error = "Local server did not answer within 45 seconds. Reload to retry."
    return result
end function
