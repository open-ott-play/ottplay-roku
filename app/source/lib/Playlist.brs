' Small, pure M3U adapter. No network, registry, or SceneGraph calls.
' The shared ES5 player core cannot execute inside the BrightScript runtime.
function safePlaylistUrl(value as dynamic) as boolean
    if not isText(value) then return false
    if Len(value) = 0 or Len(value) > 4096 then return false
    if value <> value.Trim() then return false
    if CreateObject("roRegex", "[\x00-\x20\x7f]", "").IsMatch(value) then return false
    parts = splitHttpUrl(value)
    if parts = invalid then return false
    authority = parts.authority
    if Instr(1, authority, "@") > 0 then return false
    if not CreateObject("roRegex", "^([A-Za-z0-9.-]+|\[[0-9A-Fa-f:]+\])(:[0-9]{1,5})?$", "").IsMatch(authority) then return false
    if Left(authority, 1) = "." or Left(authority, 1) = "-" then return false
    return true
end function

function isText(value as dynamic) as boolean
    return Type(value) = "roString" or Type(value) = "String"
end function

function splitHttpUrl(value as string) as dynamic
    parts = CreateObject("roRegex", "^(https?)://([^/?#]+)([^?#]*)(\?[^#]*)?(#.*)?$", "i").Match(value)
    if parts.Count() < 4 then return invalid
    query = ""
    if parts.Count() > 4 then query = parts[4]
    return {scheme: LCase(parts[1]), authority: parts[2], path: parts[3], query: query}
end function

function resolveMediaUrl(baseUrl as string, value as string) as string
    value = value.Trim()
    if value = "" then return ""
    if safePlaylistUrl(value) then return value
    if not safePlaylistUrl(baseUrl) then return ""
    base = splitHttpUrl(baseUrl)
    if Left(value, 2) = "//"
        candidate = base.scheme + ":" + value
        if safePlaylistUrl(candidate) then return candidate
        return ""
    end if
    if CreateObject("roRegex", "^[A-Za-z][A-Za-z0-9+.-]*:", "").IsMatch(value) then return ""
    origin = base.scheme + "://" + base.authority
    if Left(value, 1) = "?"
        candidate = origin + base.path + value
    else if Left(value, 1) = "#"
        candidate = origin + base.path + base.query + value
    else
        suffix = ""
        delimiter = Len(value) + 1
        question = Instr(1, value, "?")
        fragment = Instr(1, value, "#")
        if question > 0 and question < delimiter then delimiter = question
        if fragment > 0 and fragment < delimiter then delimiter = fragment
        if delimiter <= Len(value)
            suffix = Mid(value, delimiter)
            value = Left(value, delimiter - 1)
        end if
        if Left(value, 1) = "/"
            path = value
        else
            basePath = base.path
            lastSlash = 0
            for i = 1 to Len(basePath)
                if Mid(basePath, i, 1) = "/" then lastSlash = i
            end for
            path = Left(basePath, lastSlash) + value
            if Left(path, 1) <> "/" then path = "/" + path
        end if
        candidate = origin + normalizeUrlPath(path) + suffix
    end if
    if safePlaylistUrl(candidate) then return candidate
    return ""
end function

function normalizeUrlPath(path as string) as string
    segments = path.Split("/")
    result = []
    for each segment in segments
        if segment = ".."
            if result.Count() > 0 then result.Pop()
        else if segment <> "." and segment <> ""
            result.Push(segment)
        end if
    end for
    normalized = "/" + result.Join("/")
    if Right(path, 1) = "/" and normalized <> "/" then normalized = normalized + "/"
    return normalized
end function

function m3uAttribute(line as string, name as string) as string
    quoted = CreateObject("roRegex", "(?:^|\s)" + name + "\s*=\s*""([^""]*)""", "i").Match(line)
    if quoted.Count() > 1 then return quoted[1].Trim()
    single = CreateObject("roRegex", "(?:^|\s)" + name + "\s*=\s*'([^']*)'", "i").Match(line)
    if single.Count() > 1 then return single[1].Trim()
    bare = CreateObject("roRegex", "(?:^|\s)" + name + "\s*=\s*([^\s,]+)", "i").Match(line)
    if bare.Count() > 1 then return bare[1].Trim()
    return ""
end function

function m3uTitle(line as string) as string
    quote = ""
    for i = 1 to Len(line)
        letter = Mid(line, i, 1)
        if letter = """" or letter = "'"
            if quote = ""
                quote = letter
            else if quote = letter
                quote = ""
            end if
        else if letter = "," and quote = ""
            return Mid(line, i + 1).Trim()
        end if
    end for
    return ""
end function

function mediaFormat(url as string) as string
    path = LCase(url.Tokenize("?")[0])
    path = path.Tokenize("#")[0]
    if Right(path, 5) = ".m3u8" or Right(path, 4) = ".m3u" then return "hls"
    if Right(path, 4) = ".mpd" then return "dash"
    if Right(path, 4) = ".mp4" or Right(path, 4) = ".m4v" or Right(path, 4) = ".mov" then return "mp4"
    if Right(path, 4) = ".mkv" then return "mkv"
    return ""
end function

function parseM3u(text as string, baseUrl as string) as object
    result = {channels: [], error: "", skipped: 0, truncated: false}
    if Len(text) > 8388608
        result.error = "Playlist is larger than 8 MiB. Use a smaller playlist."
        return result
    end if
    if Instr(1, text, "#EXT-X-") > 0
        result.error = "This is a video stream, not a channel playlist. Enter an M3U channel list."
        return result
    end if
    beginning = LCase(Left(text.Trim(), 256))
    if Instr(1, beginning, "<html") > 0 or Instr(1, beginning, "<!doctype") > 0
        result.error = "The server returned a web page instead of a playlist."
        return result
    end if
    pending = invalid
    group = ""
    lines = text.Tokenize(Chr(10))
    for each rawLine in lines
        line = rawLine.Replace(Chr(13), "").Trim()
        if Left(line, 1) = Chr(65279) then line = Mid(line, 2)
        upper = UCase(line)
        if Left(upper, 8) = "#EXTINF:"
            pending = {title: m3uTitle(line), id: m3uAttribute(line, "tvg-id"), logo: m3uAttribute(line, "tvg-logo"), group: m3uAttribute(line, "group-title")}
            if pending.title = "" then pending.title = m3uAttribute(line, "tvg-name")
        else if Left(upper, 8) = "#EXTGRP:"
            group = Mid(line, 9).Trim()
            if pending <> invalid then pending.group = group
        else if line <> "" and Left(line, 1) <> "#"
            url = resolveMediaUrl(baseUrl, line)
            if url <> ""
                if pending = invalid then pending = {title: "", id: "", logo: "", group: ""}
                if pending.title = "" then pending.title = "Channel " + (result.channels.Count() + 1).ToStr()
                if pending.group = "" then pending.group = group
                if pending.group = "" then pending.group = "Other"
                pending.title = Left(pending.title, 512)
                pending.group = Left(pending.group, 256)
                pending.id = Left(pending.id, 512)
                pending.logo = resolveMediaUrl(baseUrl, pending.logo)
                pending.url = url
                pending.streamFormat = mediaFormat(url)
                result.channels.Push(pending)
                if result.channels.Count() >= 20000
                    result.truncated = true
                    exit for
                end if
            else
                result.skipped = result.skipped + 1
            end if
            pending = invalid
        end if
    end for
    if result.channels.Count() = 0 then result.error = "No HTTP or HTTPS channels were found in this playlist."
    return result
end function
