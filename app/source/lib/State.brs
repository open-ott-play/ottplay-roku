function defaultPlayerState() as object
    return {version: 1, playlistUrl: "demo", category: "all", selectedKey: "", favorites: [], mode: "playlist", localEndpoint: "", localSourceId: "", localSourceName: "", localShuffle: false}
end function

function validChannel(value as dynamic) as boolean
    if Type(value) <> "roAssociativeArray" then return false
    if not isText(value.title) or not isText(value.group) or not isText(value.id) then return false
    if not safePlaylistUrl(value.url) then return false
    if Len(value.title) > 512 or Len(value.group) > 256 or Len(value.id) > 512 then return false
    return true
end function

function readPlayerState(raw as string) as object
    state = defaultPlayerState()
    if Len(raw) = 0 or Len(raw) > 24576 then return state
    parsed = ParseJson(raw)
    if Type(parsed) <> "roAssociativeArray" then return state
    if parsed.version <> 1 then return state
    state.localEndpoint = localEndpoint(parsed.localEndpoint)
    if state.localEndpoint <> "" and localId(parsed.localSourceId)
        state.localSourceId = parsed.localSourceId
        if isText(parsed.localSourceName) then state.localSourceName = Left(parsed.localSourceName, 256)
        if parsed.mode = "local" then state.mode = "local"
    end if
    if parsed.localShuffle = true then state.localShuffle = true
    if isText(parsed.playlistUrl)
        if parsed.playlistUrl = "demo" or safePlaylistUrl(parsed.playlistUrl) then state.playlistUrl = parsed.playlistUrl
    end if
    if isText(parsed.category)
        if Len(parsed.category) <= 300 then state.category = parsed.category
    end if
    if isText(parsed.selectedKey)
        if Len(parsed.selectedKey) <= 10000 then state.selectedKey = parsed.selectedKey
    end if
    if Type(parsed.favorites) = "roArray"
        seen = {}
        seen.SetModeCaseSensitive()
        for each entry in parsed.favorites
            if Type(entry) = "roAssociativeArray"
                if isText(entry.source) and validChannel(entry.channel)
                    if entry.source = "demo" or safePlaylistUrl(entry.source)
                        key = channelIdentity(entry.source, entry.channel)
                        if not seen.DoesExist(key)
                            seen[key] = true
                            state.favorites.Push({source: entry.source, channel: compactChannel(entry.channel)})
                        end if
                    end if
                end if
            end if
            if state.favorites.Count() >= 100 then exit for
        end for
    end if
    return state
end function

function compactChannel(channel as object) as object
    return {title: channel.title, group: channel.group, id: channel.id, url: channel.url, logo: "", streamFormat: mediaFormat(channel.url)}
end function

function channelIdentity(source as string, channel as object) as string
    ' Never use row numbers. URL also disambiguates duplicate tvg-ids.
    return FormatJson([source, channel.id, channel.group, channel.title, channel.url])
end function

function favoriteIndex(favorites as object, source as string, channel as object) as integer
    key = channelIdentity(source, channel)
    for i = 0 to favorites.Count() - 1
        entry = favorites[i]
        if channelIdentity(entry.source, entry.channel) = key then return i
    end for
    return -1
end function

function stateFitsRegistry(state as object) as boolean
    return Len(FormatJson(state)) <= 24576
end function
