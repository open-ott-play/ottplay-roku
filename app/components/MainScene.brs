sub init()
    m.top.backgroundColor = "#10151F"
    m.browser = m.top.FindNode("browser")
    m.categories = m.top.FindNode("categories")
    m.channels = m.top.FindNode("channels")
    m.status = m.top.FindNode("status")
    m.sourceLabel = m.top.FindNode("sourceLabel")
    m.listTitle = m.top.FindNode("listTitle")
    m.emptyLabel = m.top.FindNode("emptyLabel")
    m.videoLayer = m.top.FindNode("videoLayer")
    m.video = m.top.FindNode("video")
    m.startupTimer = m.top.FindNode("startupTimer")
    m.startupTimer.ObserveField("fire", "onVideoTimeout")
    m.categories.ObserveField("itemSelected", "onCategorySelected")
    m.channels.ObserveField("itemSelected", "onChannelSelected")
    m.state = defaultPlayerState()
    m.catalog = []
    m.visibleEntries = []
    m.categoryKeys = []
    m.loading = false
    m.task = invalid
    m.requestId = 0
    m.playbackId = 0
    m.playingEntry = invalid
    m.focusArea = "channels"
    m.dialogKind = ""
    m.initialized = false
    m.localChoosingSources = false
    m.localSources = []
    m.localAuto = false
    m.localPending = false
    m.localGeneration = ""
    m.localPlayed = {}
    m.localFailures = 0
end sub

sub onInitialState()
    if m.initialized then return
    m.initialized = true
    m.state = readPlayerState(m.top.initialState)
    renderCategories()
    renderChannels()
    if m.state.mode = "local"
        startLocalSource(m.state.localEndpoint, {id: m.state.localSourceId, name: m.state.localSourceName}, false)
    else
        loadSource(m.state.playlistUrl)
    end if
end sub

sub persist()
    if stateFitsRegistry(m.state)
        m.top.persistState = FormatJson(m.state)
    else
        m.status.text = "Storage is full. Remove a favorite before saving more."
    end if
end sub

sub onPersistenceResult()
    if not m.top.persistenceOk then m.status.text = "The Roku could not save settings. Changes may be lost after exit."
end sub

sub loadSource(source as string)
    cancelLoad(false)
    m.localChoosingSources = false
    m.requestId = m.requestId + 1
    m.loading = true
    m.status.text = "Loading playlist... Back cancels; the previous list remains available."
    task = CreateObject("roSGNode", "PlaylistTask")
    task.url = source
    task.requestId = m.requestId
    task.ObserveField("result", "onPlaylistResult")
    m.task = task
    task.control = "run"
    restoreBrowserFocus()
end sub



sub onPlaylistResult(event as object)
    result = event.GetData()
    if result.requestId <> m.requestId then return
    m.loading = false
    m.task = invalid
    if result.error <> ""
        m.status.text = result.error
        restoreBrowserFocus()
        return
    end if
    m.catalog = result.channels
    m.state.mode = "playlist"
    m.state.playlistUrl = result.source
    renderCategories()
    renderChannels()
    persist()
    label = "Saved M3U playlist"
    if result.source = "demo" then label = "Demo - Apple streaming test"
    m.sourceLabel.text = label
    m.status.text = m.catalog.Count().ToStr() + " channels. Select a channel and press OK to play."
    if result.skipped > 0 then m.status.text = m.status.text + " Skipped unsupported entries: " + result.skipped.ToStr() + "."
    if result.truncated then m.status.text = "Showing the first 20,000 channels. Use a smaller playlist to see every channel."
    restoreBrowserFocus()
end sub

sub renderCategories()
    if m.localChoosingSources then return
    content = CreateObject("roSGNode", "ContentNode")
    if m.state.mode = "local"
        m.categoryKeys = ["all"]
        node = content.CreateChild("ContentNode")
        node.title = "Local videos"
        m.categories.content = content
        m.categories.jumpToItem = 0
        return
    end if
    m.categoryKeys = ["all", "favorites"]
    node = content.CreateChild("ContentNode")
    node.title = "All"
    node = content.CreateChild("ContentNode")
    node.title = "Favorites (" + m.state.favorites.Count().ToStr() + ")"
    seen = {}
    seen.SetModeCaseSensitive()
    for each channel in m.catalog
        if not seen.DoesExist(channel.group)
            seen[channel.group] = true
            m.categoryKeys.Push("group:" + channel.group)
            node = content.CreateChild("ContentNode")
            node.title = channel.group
        end if
    end for
    selected = 0
    for i = 0 to m.categoryKeys.Count() - 1
        if m.categoryKeys[i] = m.state.category then selected = i
    end for
    ' Do not discard a saved category before its playlist has arrived.
    if m.catalog.Count() > 0 then m.state.category = m.categoryKeys[selected]
    m.categories.content = content
    m.categories.jumpToItem = selected
end sub

sub renderChannels()
    if m.localChoosingSources then return
    focusedLocalId = ""
    if m.state.mode = "local"
        index = m.channels.itemFocused
        if index >= 0 and index < m.visibleEntries.Count() then focusedLocalId = m.visibleEntries[index].channel.id
    end if
    m.visibleEntries = []
    if m.state.mode = "local"
        for each channel in m.catalog
            m.visibleEntries.Push({source: "local:" + m.state.localSourceId, channel: channel, local: true})
        end for
    else if m.state.category = "favorites"
        for each entry in m.state.favorites
            m.visibleEntries.Push(entry)
        end for
    else
        for each channel in m.catalog
            if m.state.category = "all" or m.state.category = "group:" + channel.group
                m.visibleEntries.Push({source: m.state.playlistUrl, channel: channel})
            end if
        end for
    end if
    content = CreateObject("roSGNode", "ContentNode")
    selected = 0
    favoriteKeys = {}
    favoriteKeys.SetModeCaseSensitive()
    for each favorite in m.state.favorites
        favoriteKeys[channelIdentity(favorite.source, favorite.channel)] = true
    end for
    for i = 0 to m.visibleEntries.Count() - 1
        entry = m.visibleEntries[i]
        node = content.CreateChild("ContentNode")
        marker = ""
        key = channelIdentity(entry.source, entry.channel)
        if favoriteKeys.DoesExist(key) then marker = "* "
        node.title = (i + 1).ToStr() + "  " + marker + entry.channel.title
        if key = m.state.selectedKey then selected = i
        if m.state.mode = "local" and entry.channel.id = focusedLocalId then selected = i
    end for
    m.channels.content = content
    if m.visibleEntries.Count() > 0 then m.channels.jumpToItem = selected
    m.emptyLabel.visible = m.visibleEntries.Count() = 0
    m.emptyLabel.text = "No channels yet. Press * and choose Playlist URL or Demo playlist."
    if m.state.category = "favorites" then m.emptyLabel.text = "No favorites yet. Select a channel, press *, and choose Add to favorites."
    m.listTitle.text = "Channels (" + m.visibleEntries.Count().ToStr() + ")"
    if m.state.category = "favorites" then m.listTitle.text = "Favorites (" + m.visibleEntries.Count().ToStr() + ")"
    if m.state.mode = "local"
        m.listTitle.text = "Local videos (" + m.visibleEntries.Count().ToStr() + ")"
        m.emptyLabel.text = "Waiting for the first MP4 or MKV video. Back cancels; Options selects another folder."
    end if
end sub

sub onCategorySelected()
    selectCategory(m.categories.itemSelected)
end sub

sub selectCategory(index as integer)
    if m.localChoosingSources or m.state.mode = "local"
        m.focusArea = "channels"
        restoreBrowserFocus()
        return
    end if
    if index < 0 or index >= m.categoryKeys.Count() then return
    m.state.category = m.categoryKeys[index]
    renderChannels()
    persist()
    m.focusArea = "channels"
    restoreBrowserFocus()
end sub

sub onChannelSelected()
    index = m.channels.itemSelected
    if m.localChoosingSources
        if index >= 0 and index < m.localSources.Count() then startLocalSource(m.localProposedEndpoint, m.localSources[index], false)
        return
    end if
    if index < 0 or index >= m.visibleEntries.Count() then return
    if m.state.mode = "local"
        m.localAuto = true
        m.localFailures = 0
        m.localPlayed = {}
    end if
    playEntry(m.visibleEntries[index])
end sub

function focusedEntry() as dynamic
    if m.localChoosingSources then return invalid
    if m.playingEntry <> invalid then return m.playingEntry
    index = m.channels.itemFocused
    if index >= 0 and index < m.visibleEntries.Count() then return m.visibleEntries[index]
    return invalid
end function

sub playEntry(entry as object)
    if not validChannel(entry.channel)
        m.status.text = "This entry has no supported HTTP or HTTPS video address."
        return
    end if
    stopVideo(false)
    m.playbackId = m.playbackId + 1
    m.playingEntry = entry
    if entry.local = true
        m.localPlayed[entry.channel.id] = true
        if m.task <> invalid then m.task.urgent = false
    else
        m.state.selectedKey = channelIdentity(entry.source, entry.channel)
    end if
    persist()
    ' New nodes isolate delayed events from a previously stopped stream.
    m.videoLayer.RemoveChild(m.video)
    m.video = CreateObject("roSGNode", "PlayerVideo")
    m.video.id = "playback-" + m.playbackId.ToStr()
    m.video.width = 1280
    m.video.height = 720
    m.video.ObserveField("state", "onVideoState")
    m.video.ObserveField("backRequested", "onVideoBack")
    m.video.ObserveField("optionsRequested", "onVideoOptions")
    m.videoLayer.AppendChild(m.video)
    content = CreateObject("roSGNode", "ContentNode")
    content.url = entry.channel.url
    content.title = entry.channel.title
    format = mediaFormat(entry.channel.url)
    if entry.local = true then format = entry.channel.streamFormat
    if format <> "" then content.streamFormat = format
    content.HttpCertificatesFile = "common:/certs/ca-bundle.crt"
    m.video.content = content
    m.video.visible = true
    m.browser.visible = false
    m.video.SetFocus(true)
    m.playbackClock = CreateObject("roTimespan")
    m.playbackClock.Mark()
    m.video.control = "play"
    m.startupTimer.control = "start"
end sub

sub stopVideo(restore as boolean)
    m.startupTimer.control = "stop"
    if m.video <> invalid
        m.video.UnobserveField("state")
        m.video.UnobserveField("backRequested")
        m.video.UnobserveField("optionsRequested")
        m.video.control = "stop"
        m.video.visible = false
    end if
    m.playingEntry = invalid
    if restore
        m.browser.visible = true
        renderChannels()
        restoreBrowserFocus()
    end if
end sub

sub onVideoState(event as object)
    if event.GetRoSGNode().id <> m.video.id or m.playingEntry = invalid then return
    state = event.GetData()
    if state = "playing" or state = "paused"
        m.startupTimer.control = "stop"
        m.localFailures = 0
    else if state = "error"
        if m.playingEntry.local = true
            localPlaybackEnded(true)
            return
        end if
        stopVideo(true)
        m.status.text = "Roku could not play this stream. Its format, codec, access rules, or network may be unsupported. Select it to retry."
    else if state = "finished"
        if m.playingEntry.local = true
            localPlaybackEnded(false)
            return
        end if
        stopVideo(true)
        m.status.text = "Playback finished. Choose another channel or play this video again."
    end if
end sub

sub onVideoTimeout()
    if m.playingEntry = invalid then return
    if m.playbackClock.TotalMilliseconds() < 30000 then return
    if m.video.state = "playing" or m.video.state = "paused" then return
    if m.playingEntry.local = true
        localPlaybackEnded(true)
        return
    end if
    stopVideo(true)
    m.status.text = "Video did not start within 30 seconds. Check the connection or select another channel."
end sub

sub onVideoBack()
    if m.state.mode = "local" then cancelLoad(false)
    stopVideo(true)
end sub

sub onVideoOptions()
    showOptions()
end sub

sub restoreBrowserFocus()
    if m.dialogKind <> "" then return
    if m.playingEntry <> invalid
        m.video.SetFocus(true)
    else if m.localChoosingSources and m.localSources.Count() > 0
        m.channels.SetFocus(true)
    else if m.focusArea = "categories" or m.visibleEntries.Count() = 0
        m.focusArea = "categories"
        m.categories.SetFocus(true)
    else
        m.channels.SetFocus(true)
    end if
end sub

sub showOptions()
    if m.dialogKind <> "" then return
    if m.state.mode = "local" and not m.localChoosingSources
        showLocalOptions()
        return
    end if
    showPlaylistOptions()
end sub

sub showPlaylistOptions()
    entry = focusedEntry()
    buttons = []
    m.optionActions = []
    if entry <> invalid and m.state.mode <> "local"
        label = "Add to favorites"
        if favoriteIndex(m.state.favorites, entry.source, entry.channel) >= 0 then label = "Remove from favorites"
        buttons.Push(label)
        m.optionActions.Push("favorite")
    end if
    buttons.Push("Local videos")
    m.optionActions.Push("local")
    if m.state.localEndpoint <> ""
        buttons.Push("Local server settings")
        m.optionActions.Push("localSettings")
    end if
    buttons.Push("Playlist URL")
    m.optionActions.Push("url")
    buttons.Push("Reload playlist")
    m.optionActions.Push("reload")
    buttons.Push("Demo playlist")
    m.optionActions.Push("demo")
    buttons.Push("Close")
    m.optionActions.Push("close")
    dialog = CreateObject("roSGNode", "Dialog")
    dialog.title = "OTTPlay options"
    dialog.message = "M3U playlists and shared Local folders. Settings stay on this Roku."
    dialog.buttons = buttons
    dialog.ObserveField("buttonSelected", "onOptionSelected")
    attachDialog(dialog, "options")
end sub

sub attachDialog(dialog as object, kind as string)
    m.dialogKind = kind
    m.activeDialog = dialog
    dialog.ObserveField("wasClosed", "onDialogClosed")
    m.top.dialog = dialog
    dialog.SetFocus(true)
end sub

sub closeDialog()
    if m.activeDialog <> invalid
        m.activeDialog.UnobserveField("wasClosed")
        m.activeDialog.UnobserveField("buttonSelected")
        m.activeDialog.close = true
        m.activeDialog = invalid
    end if
    m.dialogKind = ""
end sub

sub onDialogClosed()
    m.activeDialog = invalid
    m.dialogKind = ""
    playNextLocal()
    restoreBrowserFocus()
end sub

sub onOptionSelected()
    index = m.activeDialog.buttonSelected
    if index < 0 or index >= m.optionActions.Count() then return
    action = m.optionActions[index]
    closeDialog()
    if action = "favorite"
        toggleFavorite()
    else if action = "url"
        showUrlDialog()
        return
    else if action = "local"
        if m.state.localEndpoint = ""
            showLocalUrlDialog()
        else
            loadLocalFolders(m.state.localEndpoint)
        end if
    else if action = "localUrl"
        showLocalUrlDialog()
    else if action = "localSettings"
        showLocalSettings()
    else if action = "playlistOptions"
        showPlaylistOptions()
    else if action = "localForget"
        forgetLocalServer()
    else if action = "localReload"
        startLocalSource(m.state.localEndpoint, {id: m.state.localSourceId, name: m.state.localSourceName}, true)
    else if action = "localPlay"
        m.state.localShuffle = not m.state.localShuffle
        m.localPlayed = {}
        m.localFailures = 0
        m.localAuto = true
        stopVideo(true)
        persist()
        playNextLocal()
    else if action = "localNext"
        m.localAuto = true
        stopVideo(true)
        playNextLocal()
    else if action = "reload"
        stopVideo(true)
        loadSource(m.state.playlistUrl)
    else if action = "demo"
        stopVideo(true)
        loadSource("demo")
    end if
    playNextLocal()
    restoreBrowserFocus()
end sub

sub showUrlDialog()
    dialog = CreateObject("roSGNode", "StandardKeyboardDialog")
    dialog.title = "M3U playlist URL"
    dialog.buttons = ["Load", "Cancel"]
    if m.state.playlistUrl <> "demo" then dialog.text = m.state.playlistUrl
    dialog.ObserveField("buttonSelected", "onUrlSelected")
    attachDialog(dialog, "url")
end sub

sub onUrlSelected()
    selected = m.activeDialog.buttonSelected
    value = m.activeDialog.text.Trim()
    closeDialog()
    if selected = 0
        if safePlaylistUrl(value)
            stopVideo(true)
            loadSource(value)
        else
            m.status.text = "Enter an HTTP or HTTPS playlist URL without spaces or embedded username/password. Press * to edit it."
        end if
    end if
    playNextLocal()
    restoreBrowserFocus()
end sub

sub toggleFavorite()
    entry = focusedEntry()
    if entry = invalid then return
    index = favoriteIndex(m.state.favorites, entry.source, entry.channel)
    nextState = ParseJson(FormatJson(m.state))
    if index >= 0
        nextState.favorites.Delete(index)
        notice = "Removed from favorites: " + entry.channel.title
    else
        if nextState.favorites.Count() >= 100
            m.status.text = "Favorites is full (100 entries). Remove an entry before adding another."
            return
        end if
        nextState.favorites.Push({source: entry.source, channel: compactChannel(entry.channel)})
        notice = "Added to favorites: " + entry.channel.title
    end if
    if not stateFitsRegistry(nextState)
        m.status.text = "Favorites storage is full. Remove an entry before adding another."
        return
    end if
    m.state = nextState
    persist()
    renderCategories()
    renderChannels()
    m.status.text = notice
    if m.playingEntry <> invalid
        dialog = CreateObject("roSGNode", "Dialog")
        dialog.title = "Favorites"
        dialog.message = notice
        dialog.buttons = ["Continue playing"]
        dialog.ObserveField("buttonSelected", "onNoticeSelected")
        attachDialog(dialog, "notice")
    end if
end sub

sub onNoticeSelected()
    closeDialog()
    restoreBrowserFocus()
end sub

sub showExitDialog()
    dialog = CreateObject("roSGNode", "Dialog")
    dialog.title = "Exit OTTPlay?"
    dialog.message = "Your saved playlist, selected category, and favorites stay on this Roku."
    dialog.buttons = ["Keep watching", "Exit"]
    dialog.ObserveField("buttonSelected", "onExitSelected")
    attachDialog(dialog, "exit")
end sub

sub onExitSelected()
    selected = m.activeDialog.buttonSelected
    closeDialog()
    if selected = 1
        cancelLoad(false)
        stopVideo(false)
        persist()
        m.top.exitRequested = true
    else
        playNextLocal()
        restoreBrowserFocus()
    end if
end sub

function onKeyEvent(key as string, press as boolean) as boolean
    if not press then return false
    if m.dialogKind <> ""
        if key = "back"
            closeDialog()
            playNextLocal()
            restoreBrowserFocus()
            return true
        end if
        return false
    end if
    if key = "options"
        showOptions()
        return true
    end if
    if key = "back"
        if m.localChoosingSources
            cancelLoad(false)
            m.localChoosingSources = false
            renderCategories()
            renderChannels()
            m.sourceLabel.text = "Saved M3U playlist"
            if m.state.mode = "local" then m.sourceLabel.text = "Local: " + m.state.localSourceName
            m.status.text = "Folder selection cancelled. Choose an entry or open Options."
            restoreBrowserFocus()
            return true
        end if
        if m.playingEntry <> invalid
            if m.state.mode = "local" then cancelLoad(false)
            stopVideo(true)
        else if m.loading
            cancelLoad(true)
        else if m.focusArea = "channels"
            m.focusArea = "categories"
            restoreBrowserFocus()
        else
            showExitDialog()
        end if
        return true
    end if
    if m.playingEntry <> invalid then return false
    if key = "left"
        m.focusArea = "categories"
        restoreBrowserFocus()
        return true
    else if key = "right"
        if m.focusArea = "categories"
            selectCategory(m.categories.itemFocused)
        else
            m.focusArea = "channels"
            restoreBrowserFocus()
        end if
        return true
    end if
    return false
end function
