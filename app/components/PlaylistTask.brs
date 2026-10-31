sub init()
    m.top.functionName = "loadPlaylist"
end sub

sub loadPlaylist()
    source = m.top.url
    if source = "demo"
        parsed = parseM3u(ReadAsciiFile("pkg:/data/demo.m3u"), "https://devstreaming-cdn.apple.com/")
        publishResult(parsed)
        return
    end if
    if not safePlaylistUrl(source)
        publishResult({channels: [], error: "Enter a valid HTTP or HTTPS playlist URL.", skipped: 0, truncated: false})
        return
    end if
    port = CreateObject("roMessagePort")
    request = CreateObject("roUrlTransfer")
    request.SetMessagePort(port)
    request.SetCertificatesFile("common:/certs/ca-bundle.crt")
    request.InitClientCertificates()
    request.SetUrl(source)
    request.AddHeader("Accept", "application/x-mpegURL, application/vnd.apple.mpegurl, text/plain, */*")
    request.SetMinimumTransferRate(1, 15)
    path = "tmp:/ottplay-playlist-" + m.top.requestId.ToStr() + ".m3u"
    DeleteFile(path)
    filesystem = CreateObject("roFileSystem")
    if not request.AsyncGetToFile(path)
        DeleteFile(path)
        publishResult({channels: [], error: "The playlist request could not start.", skipped: 0, truncated: false})
        return
    end if
    timer = CreateObject("roTimespan")
    timer.Mark()
    while timer.TotalMilliseconds() < 20000
        if m.top.cancelled
            request.AsyncCancel()
            DeleteFile(path)
            return
        end if
        info = filesystem.Stat(path)
        if info <> invalid
            if info.size > 8388608
                request.AsyncCancel()
                DeleteFile(path)
                publishResult({channels: [], error: "Playlist is larger than 8 MiB. Use a smaller playlist.", skipped: 0, truncated: false})
                return
            end if
        end if
        event = Wait(200, port)
        if Type(event) = "roUrlEvent"
            if event.GetSourceIdentity() = request.GetIdentity()
                code = event.GetResponseCode()
                if code >= 200 and code < 300
                    info = filesystem.Stat(path)
                    if info <> invalid
                        if info.size <= 8388608
                            text = ReadAsciiFile(path)
                            DeleteFile(path)
                            publishResult(parseM3u(text, source))
                        else
                            publishResult({channels: [], error: "Playlist is larger than 8 MiB. Use a smaller playlist.", skipped: 0, truncated: false})
                        end if
                    else
                        publishResult({channels: [], error: "The downloaded playlist could not be read.", skipped: 0, truncated: false})
                    end if
                else if code = 401 or code = 403
                    publishResult({channels: [], error: "Playlist access was refused. Check the link and its access permissions.", skipped: 0, truncated: false})
                else if code < 0
                    publishResult({channels: [], error: "Could not connect securely to the playlist server. Check its address and your network.", skipped: 0, truncated: false})
                else
                    publishResult({channels: [], error: "The playlist server returned HTTP " + code.ToStr() + ".", skipped: 0, truncated: false})
                end if
                DeleteFile(path)
                return
            end if
        end if
    end while
    request.AsyncCancel()
    DeleteFile(path)
    publishResult({channels: [], error: "The playlist request timed out. Press Options to retry.", skipped: 0, truncated: false})
end sub

sub publishResult(value as object)
    if m.top.cancelled then return
    value.requestId = m.top.requestId
    value.source = m.top.url
    m.top.result = value
end sub
