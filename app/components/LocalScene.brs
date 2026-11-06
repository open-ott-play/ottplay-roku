' Render-thread Local controller. Networking is confined to LocalTask.
sub showLocalOptions()
    label = "Shuffle all videos"
    if m.state.localShuffle then label = "Play all in order"
    dialog = CreateObject("roSGNode", "Dialog")
    dialog.title = "Local videos"
    dialog.message = "MP4 and MKV playback uses this Roku's supported codecs."
    dialog.buttons = ["Local folders", label, "Next video", "Reload Local folder", "Server settings", "M3U playlists", "Close"]
    m.optionActions = ["local", "localPlay", "localNext", "localReload", "localSettings", "playlistOptions", "close"]
    dialog.ObserveField("buttonSelected", "onOptionSelected")
    attachDialog(dialog, "options")
end sub

sub showLocalSettings()
    dialog = CreateObject("roSGNode", "Dialog")
    dialog.title = "Local server settings"
    dialog.message = "The private link is saved only in this app's Roku registry. Forget removes it from these settings."
    dialog.buttons = ["Change Local server", "Forget Local server", "Close"]
    m.optionActions = ["localUrl", "localForget", "close"]
    dialog.ObserveField("buttonSelected", "onOptionSelected")
    attachDialog(dialog, "options")
end sub

sub showLocalUrlDialog()
    dialog = CreateObject("roSGNode", "StandardKeyboardDialog")
    dialog.title = "Private Local helper URL"
    dialog.message = ["Enter the helper link ending /offline-media/token. It will be saved on this Roku."]
    dialog.textEditBox.secureMode = true
    dialog.textEditBox.maxTextLength = 4096
    dialog.buttons = ["Connect", "Cancel"]
    ' Never echo a saved access token into a dialog or error.
    dialog.ObserveField("buttonSelected", "onLocalUrlSelected")
    attachDialog(dialog, "localUrl")
end sub

sub onLocalUrlSelected()
    selected = m.activeDialog.buttonSelected
    value = localEndpoint(m.activeDialog.text.Trim())
    closeDialog()
    if selected = 0
        if value = ""
            m.status.text = "Enter an HTTP(S) helper link ending /offline-media/token, without query, fragment or username/password."
        else
            loadLocalFolders(value)
        end if
    end if
    playNextLocal()
    restoreBrowserFocus()
end sub

sub loadLocalFolders(endpoint as string)
    stopVideo(true)
    cancelLoad(false)
    m.localChoosingSources = false
    m.localProposedEndpoint = endpoint
    m.status.text = "Loading shared Local folders... Back cancels."
    startLocalTask(endpoint, "", false)
end sub

sub startLocalTask(endpoint as string, sourceId as string, refresh as boolean)
    m.requestId = m.requestId + 1
    m.loading = true
    task = CreateObject("roSGNode", "LocalTask")
    task.endpoint = endpoint
    task.sourceId = sourceId
    task.requestId = m.requestId
    task.refresh = refresh
    task.ObserveField("result", "onLocalResult")
    m.task = task
    task.control = "run"
end sub

sub startLocalSource(endpoint as string, source as object, refresh as boolean)
    cancelLoad(false)
    stopVideo(false)
    m.browser.visible = true
    m.localChoosingSources = false
    m.state.mode = "local"
    m.state.localEndpoint = endpoint
    m.state.localSourceId = source.id
    m.state.localSourceName = source.name
    m.localPlayed = {}
    m.localGeneration = ""
    m.localFailures = 0
    m.localDiscoveryError = ""
    m.localAuto = true
    m.localPending = true
    m.catalog = []
    renderCategories()
    renderChannels()
    m.sourceLabel.text = "Local: " + source.name
    m.status.text = "Finding the first playable video... Back cancels."
    persist()
    startLocalTask(endpoint, source.id, refresh)
    restoreBrowserFocus()
end sub

sub onLocalResult(event as object)
    result = event.GetData()
    if result.requestId <> m.requestId then return
    if result.kind = "inventory"
        m.loading = false
        m.task = invalid
        if result.error <> ""
            m.status.text = result.error
            return
        end if
        m.localSources = result.sources
        m.localChoosingSources = true
        m.visibleEntries = []
        content = CreateObject("roSGNode", "ContentNode")
        for each source in m.localSources
            node = content.CreateChild("ContentNode")
            node.title = source.name
        end for
        m.channels.content = content
        m.listTitle.text = "Shared Local folders (" + m.localSources.Count().ToStr() + ")"
        m.sourceLabel.text = "Local server"
        m.emptyLabel.visible = m.localSources.Count() = 0
        m.emptyLabel.text = "No folders are shared by this helper. Configure a folder on the server, then connect again."
        categories = CreateObject("roSGNode", "ContentNode")
        node = categories.CreateChild("ContentNode")
        node.title = "Shared folders"
        m.categories.content = categories
        m.status.text = "Select a folder to play. The first available video starts while discovery continues."
        m.focusArea = "channels"
        if m.localSources.Count() > 0 then m.channels.SetFocus(true)
        return
    end if
    if not localResultCurrent(result, m.requestId, m.state.localSourceId, "") or m.state.mode <> "local" then return
    if m.localGeneration <> "" and result.generation <> "" and result.generation <> m.localGeneration
        cancelLoad(false)
        stopVideo(true)
        m.status.text = "Folder discovery changed. Use Reload Local folder to start again."
        return
    end if
    if result.generation <> "" then m.localGeneration = result.generation
    m.localPending = result.pending and result.error = ""
    m.localDiscoveryError = result.error
    m.loading = m.localPending
    if not m.localPending then m.task = invalid
    ' A transport error has no snapshot; preserve already received entries.
    if result.generation <> "" then m.catalog = result.channels
    renderChannels()
    suffix = " Discovery complete."
    if m.localPending then suffix = " Finding more in the background; Back cancels."
    m.status.text = m.catalog.Count().ToStr() + " Local videos." + suffix
    if result.skipped > 0 then m.status.text = m.status.text + " Other formats skipped: " + result.skipped.ToStr() + "."
    if result.truncated then m.status.text = "Showing the first 20,000 Local videos. Share a smaller folder for a complete list."
    if result.error <> "" then m.status.text = result.error
    if m.localAuto and m.playingEntry = invalid
        if result.error <> "" and m.catalog.Count() = 0
            m.localAuto = false
        else
            playNextLocal()
        end if
    end if
end sub

sub playNextLocal()
    if not m.localAuto or m.state.mode <> "local" then return
    if m.playingEntry <> invalid then return
    if m.dialogKind <> "" then return
    channel = localNext(m.catalog, m.localPlayed, m.state.localShuffle, Rnd(0))
    if channel <> invalid
        playEntry({source: "local:" + m.state.localSourceId, channel: channel, local: true})
    else if m.localPending
        if m.task <> invalid then m.task.urgent = true
        m.status.text = "Waiting for the next playable video while discovery continues. Back cancels."
    else
        m.localAuto = false
        if m.localDiscoveryError <> ""
            m.status.text = m.localDiscoveryError
        else if m.catalog.Count() > 0
            m.status.text = "Local playback complete. Select a video or use Options to play again."
        else
            m.status.text = "No playable MP4 or MKV videos are available. Check the folder or reload from Options."
        end if
    end if
end sub

sub localPlaybackEnded(failed as boolean)
    stopVideo(true)
    if failed then m.localFailures = m.localFailures + 1
    if m.localFailures >= 3
        m.localAuto = false
        m.status.text = "Three videos could not start. Check the connection and Roku codec support, then select a video to retry."
        return
    end if
    playNextLocal()
end sub

sub forgetLocalServer()
    cancelLoad(false)
    stopVideo(true)
    m.localChoosingSources = false
    m.localSources = []
    m.localProposedEndpoint = ""
    m.state.localEndpoint = ""
    m.state.localSourceId = ""
    m.state.localSourceName = ""
    m.state.mode = "playlist"
    m.catalog = []
    persist()
    renderCategories()
    renderChannels()
    loadSource(m.state.playlistUrl)
end sub

sub cancelLoad(showMessage as boolean)
    m.localAuto = false
    m.localPending = false
    if m.task <> invalid
        m.task.cancelled = true
        m.task.UnobserveField("result")
        m.task = invalid
    end if
    if m.loading
        m.requestId = m.requestId + 1
        m.loading = false
        if showMessage then m.status.text = "Loading cancelled. Available entries remain; use Options to reload."
    end if
end sub
