' Production BrightScript logic executed by the pinned off-device interpreter.
sub Main()
    m.assertions = 0
    m.failures = 0
    base = "https://media.example/lists/home.m3u?auth=test"
    check(safePlaylistUrl(base), "HTTPS playlist accepted")
    check(safePlaylistUrl("http://192.168.1.2:8080/list.m3u"), "LAN HTTP playlist accepted")
    check(not safePlaylistUrl("file:///etc/passwd"), "File URLs rejected")
    check(not safePlaylistUrl("javascript:alert(1)"), "Script URLs rejected")
    check(not safePlaylistUrl("https://user:pass@media.example/list"), "URL credentials rejected")
    check(not safePlaylistUrl(" https://media.example/list"), "Leading whitespace rejected")
    check(not safePlaylistUrl("https://media.example/" + Chr(10) + "x"), "Control characters rejected")
    check(not safePlaylistUrl(invalid), "Missing URL rejected")
    eq(resolveMediaUrl(base, "../video/movie.mp4"), "https://media.example/video/movie.mp4", "Relative path resolution")
    eq(resolveMediaUrl(base, "/live/one.m3u8"), "https://media.example/live/one.m3u8", "Root path resolution")
    eq(resolveMediaUrl(base, "//cdn.example/two.m3u8"), "https://cdn.example/two.m3u8", "Protocol-relative URL")
    eq(resolveMediaUrl(base, "?fresh=1"), "https://media.example/lists/home.m3u?fresh=1", "Query replacement")
    eq(resolveMediaUrl(base, "javascript:bad"), "", "Unsafe relative scheme rejected")
    eq(resolveMediaUrl(base, "file:///movie.mp4"), "", "Local file scheme rejected")
    eq(resolveMediaUrl(base, "../../../movie.mp4"), "https://media.example/movie.mp4", "Parent segments stay at root")
    eq(mediaFormat("https://cdn.example/a.M3U8?x=1"), "hls", "HLS format with query")
    eq(mediaFormat("https://cdn.example/a.mpd"), "dash", "DASH format")
    eq(mediaFormat("https://cdn.example/a.mp4#t=3"), "mp4", "MP4 format with fragment")
    eq(mediaFormat("https://cdn.example/live"), "", "Extensionless format not invented")
    newline = Chr(13) + Chr(10)
    text = "#EXTM3U" + newline
    text = text + "#EXTINF:-1 tvg-id=""one"" tvg-logo=""../art/one.png"" group-title=""News, world"",News, one" + newline
    text = text + "../live/one.m3u8" + newline
    text = text + "#EXTINF:-1 tvg-name='Second' group-title='Movies'," + newline
    text = text + "https://cdn.example/two.mp4" + newline
    result = parseM3u(text, base)
    eq(result.error, "", "Valid M3U accepted")
    eq(result.channels.Count(), 2, "Two channels parsed")
    eq(result.channels[0].title, "News, one", "Comma in display title retained")
    eq(result.channels[0].group, "News, world", "Comma in quoted group retained")
    eq(result.channels[0].id, "one", "Stable provider id retained")
    eq(result.channels[0].logo, "https://media.example/art/one.png", "Relative logo resolved")
    eq(result.channels[1].title, "Second", "Name fallback")
    eq(result.channels[1].streamFormat, "mp4", "Stream format projected")
    check(not result.truncated, "Small list not truncated")
    group = parseM3u("#EXTM3U" + newline + "#EXTINF:-1,Grouped" + newline + "#EXTGRP:Family" + newline + "https://cdn.example/f.mp4", base)
    eq(group.channels[0].group, "Family", "EXTGRP category")
    plain = parseM3u("https://cdn.example/a.mp4" + newline + "javascript:bad" + newline + "https://cdn.example/b.m3u8", base)
    eq(plain.channels.Count(), 2, "Plain URL list supported")
    eq(plain.skipped, 1, "Unsafe entry skipped")
    eq(plain.channels[0].title, "Channel 1", "Unnamed channel fallback")
    check(parseM3u("#EXTM3U" + newline + "#EXT-X-TARGETDURATION:10" + newline + "segment.ts", base).error <> "", "HLS segments cannot become channels")
    check(parseM3u("<!doctype html><html>Denied</html>", base).error <> "", "HTML error page rejected")
    check(parseM3u("", base).error <> "", "Empty playlist rejected")
    check(parseM3u(String(8388609, "a"), base).error <> "", "Oversized playlist rejected")
    channel = result.channels[0]
    other = {title: channel.title, group: channel.group, id: channel.id, url: "https://cdn.example/different.m3u8"}
    check(channelIdentity(base, channel) <> channelIdentity(base, other), "Duplicate ids with different URLs remain distinct")
    check(channelIdentity(base, channel) <> channelIdentity("https://other.example/list", channel), "Favorite identity includes source")
    favorites = [{source: base, channel: channel}]
    eq(favoriteIndex(favorites, base, channel), 0, "Favorite lookup uses stable identity")
    eq(favoriteIndex(favorites, base, other), -1, "Different favorite not matched")
    state = defaultPlayerState()
    state.playlistUrl = base
    state.category = "favorites"
    state.selectedKey = channelIdentity(base, channel)
    state.favorites = [{source: base, channel: compactChannel(channel)}, {source: base, channel: compactChannel(channel)}, {source: "file:///secret", channel: compactChannel(channel)}]
    restored = readPlayerState(ReadAsciiFile("pkg:/state-fixture.json"))
    eq(restored.playlistUrl, base, "Playlist restored from stored state")
    eq(restored.category, "favorites", "Favorite category restored from stored state")
    eq(restored.selectedKey, state.selectedKey, "Selected escaped identity restored from stored state")
    eq(restored.favorites.Count(), 1, "Stored favorites deduplicated and unsafe source rejected")
    check(stateFitsRegistry(restored), "Compact favorite fits registry budget")
    eq(readPlayerState("not-json").playlistUrl, "demo", "Corrupt registry safely resets")
    eq(readPlayerState("{""version"":99}").playlistUrl, "demo", "Unknown state version safely resets")
    eq(readPlayerState(String(24577, "a")).playlistUrl, "demo", "Oversized stored state safely resets")
    state.selectedKey = String(25000, "a")
    check(not stateFitsRegistry(state), "Registry budget enforced")
    if m.failures = 0
        print "[OTT TEST RESULT] PASS "; m.assertions
    else
        print "[OTT TEST RESULT] FAIL "; m.failures
    end if
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
