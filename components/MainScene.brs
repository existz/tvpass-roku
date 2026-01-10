sub init()
    m.top.backgroundURI = "pkg:/images/background.jpg"
    m.top.backgroundColor = "0x1A1A1A"

    ' Find UI elements
    m.loadingLabel = m.top.findNode("loadingLabel")
    m.channelList = m.top.findNode("channelList")
    m.videoPlayer = m.top.findNode("videoPlayer")
    m.videoOverlay = m.top.findNode("videoOverlay")
    m.channelMenu = m.top.findNode("channelMenu")
    m.guideBackground = m.top.findNode("guideBackground")
    m.headerBackground = m.top.findNode("headerBackground")
    m.featuredLogo = m.top.findNode("featuredLogo")
    m.featuredTitle = m.top.findNode("featuredTitle")
    m.featuredTime = m.top.findNode("featuredTime")
    m.featuredDescription = m.top.findNode("featuredDescription")
    m.currentTimeLabel = m.top.findNode("currentTimeLabel")
    m.guideHeaderLabel = m.top.findNode("guideHeaderLabel")
    m.allChannelsLabel = m.top.findNode("allChannelsLabel")
    m.timeSlotHeadersContainer = m.top.findNode("timeSlotHeadersContainer")
    m.timeSlotHeaders = m.top.findNode("timeSlotHeaders")
    m.multiviewGrid = m.top.findNode("multiviewGrid")
    m.videoInfoOverlay = m.top.findNode("videoInfoOverlay")
    m.preloadContainer = m.top.findNode("preloadContainer")

    ' Initialize UI colors
    m.uiColors = GetUIColors()

    ' Initialize black loading overlay
    m.blackFlashOverlay = m.top.findNode("blackFlashOverlay")

    ' Initialize bitmap cache for image preloading
    m.bitmapCache = CreateBitmapCache()

    ' Pre-load all URL configs once
    m.apiUrls = GetTVPassUrls()
    m.logoUrls = GetLogoUrls()

    ' Pre-compute network logo mappings
    m.networkLogoPatterns = {
        abc: "abc-7-"
        cbs: "cbs-2-"
    }

    ' Pre-compile sports keywords for faster matching - use shared function
    m.sportsKeywords = GetSportsKeywords()

    ' Initialize EPG data with forced refresh on startup
    m.epgData = CreateEPGData()
    m.epgData.lastUpdate = 0

    ' Pass EPG data reference to multiview for logo preloading
    m.multiviewGrid.epgData = m.epgData

    ' Track state
    m.isBackgroundPlayback = false
    m.currentChannelIndex = -1
    m.lastChannelIndex = 0
    m.isMultiviewMode = false
    m.wasPlayingBeforeMultiview = false
    m.hasSwitchedFromOriginal = false
    m.pendingChannel = invalid
    m.pendingChannelIsMultiview = false

    ' Prevent retry spam during rapid state changes
    m.isRetrying = false
    m.retryInProgress = false

    ' Fanart artwork cache
    m.artworkCache = {}
    m.currentArtworkTask = invalid
    m.overlayArtworkTask = invalid
    ' Store original logo position and dimensions
    m.logoOriginalTranslation = m.featuredLogo.translation  ' e.g., [100, 50]
    m.defaultLogoWidth = 125 ' featuredLogo default width
    m.defaultLogoHeight = 125 ' featuredLogo default height
    m.posterArtWidth = 175    ' featuredLogo poster art width
    m.posterArtHeight = 175   ' featuredLogo poster art height

    ' Cache of resolved TVPass URLs: channelIndex -> finalUrl
    m.resolvedUrlCache = {}

    ' Race condition prevention flags
    m.isMenuTransitioning = false
    m.isReturningToGuide = false

    ' Long press detection
    m.longPressThreshold = 500
    m.leftButtonPressTime = 0
    m.rightButtonPressTime = 0
    m.upButtonPressTime = 0

    ' Retry logic
    m.retryAttempts = 0
    m.maxRetryAttempts = 10
    m.retryDelay = 2
    m.lastPosition = 0
    m.streamEstablished = false  ' Track if stream successfully connected

    ' Pre-create all timers in init() — Prevents runtime crashes
    m.clockTimer = createObject("roSGNode", "Timer")
    m.clockTimer.repeat = true
    m.clockTimer.duration = 60
    m.clockTimer.observeField("fire", "updateClock")

    ' Create dedicated timers - NEVER reuse timers with different observers
    m.retryTimer = createObject("roSGNode", "Timer")
    m.retryTimer.repeat = false
    m.retryTimer.observeField("fire", "onRetryTimer")

    m.returnToGuideTimer = createObject("roSGNode", "Timer")
    m.returnToGuideTimer.repeat = false
    m.returnToGuideTimer.duration = 5
    m.returnToGuideTimer.observeField("fire", "returnToGuide")

    m.bufferingTimer = createObject("roSGNode", "Timer")
    m.bufferingTimer.repeat = false
    m.bufferingTimer.duration = 30
    m.bufferingTimer.observeField("fire", "onBufferingTimeout")

    m.positionCheckTimer = createObject("roSGNode", "Timer")
    m.positionCheckTimer.repeat = false
    m.positionCheckTimer.duration = 8
    m.positionCheckTimer.observeField("fire", "onPositionCheck")

    ' Observe events
    m.channelList.observeField("itemSelected", "onChannelSelected")
    m.channelList.observeField("itemFocused", "onChannelFocused")
    m.videoPlayer.observeField("state", "onVideoStateChanged")
    m.channelMenu.observeField("selectedChannel", "onMenuChannelSelected")
    m.channelMenu.observeField("launchMultiview", "onLaunchMultiview")
    m.channelMenu.observeField("menuClosed", "onMenuClosed")
    m.multiviewGrid.observeField("visible", "onPiPVisibleChanged")
    m.multiviewGrid.observeField("switchToChannelIndex", "onMultiviewChannelSwitch")
    m.multiviewGrid.observeField("exitMultiview", "onMultiviewExit")

    ' App lifecycle observer to clear cache on exit
    m.top.observeField("focusedChild", "onFocusChanged")

    m.clockTimer.control = "start"
    updateClock()
    loadPlaylist()
end sub

sub onFocusChanged()
    if m.top.focusedChild = invalid then
        if m.epgData <> invalid then
            m.epgData.lastUpdate = 0
        end if
    end if
end sub

sub onMenuClosed()
    ' Add a small delay to ensure menu is fully closed before restoring focus
    if m.isMultiviewMode
        m.multiviewGrid.setFocus(true)
    else if m.videoPlayer.visible
        ' Use a flag to prevent race conditions
        m.isMenuTransitioning = false
        m.videoPlayer.setFocus(true)
    end if
end sub

sub onLaunchMultiview()
    selectedChannels = m.channelMenu.launchMultiview

    if selectedChannels = invalid or selectedChannels.count() = 0 then
        return
    end if

    if m.isMultiviewMode then
        return
    end if

    pipChannels = []
    now = CreateObject("roDateTime").AsSeconds()

    ' Add current playing channel first if video is playing
    if m.videoPlayer.visible and m.currentChannelIndex >= 0 and m.currentChannelIndex < m.epgData.channels.count()
        currentChannel = m.epgData.channels[m.currentChannelIndex]
        pipChannel = {
            title: currentChannel.title,
            url: currentChannel.url,
            logo: currentChannel.logo,
            tvgId: currentChannel.tvgId,
            channelIndex: m.currentChannelIndex,
            nowPlaying: GetNowPlayingForChannel(currentChannel, now),
            isOriginalStream: true
        }
        pipChannels.push(pipChannel)
        m.wasPlayingBeforeMultiview = true

        ' Track that we haven't switched away yet
        m.hasSwitchedFromOriginal = false

        ' Resize the video player for multiview mode WITHOUT stopping it
        m.videoPlayer.translation = [0, 0]
        m.videoPlayer.width = 1540
        m.videoPlayer.height = 1080
        m.videoPlayer.visible = true
    else
        m.wasPlayingBeforeMultiview = false
        m.hasSwitchedFromOriginal = false
    end if

    ' Add selected channels
    for each channelIdx in selectedChannels
        if channelIdx >= 0 and channelIdx < m.epgData.channels.count() then
            if channelIdx = m.currentChannelIndex then continue for

            channel = m.epgData.channels[channelIdx]
            pipChannel = {
                title: channel.title,
                url: channel.url,
                logo: channel.logo,
                tvgId: channel.tvgId,
                channelIndex: channelIdx,
                nowPlaying: GetNowPlayingForChannel(channel, now),
                isOriginalStream: false
            }
            pipChannels.push(pipChannel)
        end if
    end for

    if pipChannels.count() = 0 then return

    hideGuideElements()
    m.channelMenu.visible = false
    m.videoInfoOverlay.showOverlay = false

    m.isMultiviewMode = true
    m.multiviewGrid.visible = true

    m.multiviewGrid.originalVideoPlayer = m.videoPlayer
    m.multiviewGrid.wasPlayingBeforeMultiview = m.wasPlayingBeforeMultiview

    m.multiviewGrid.channels = pipChannels

    m.multiviewGrid.setFocus(true)
end sub

sub onPiPVisibleChanged()

    if not m.multiviewGrid.visible and m.isMultiviewMode then
        m.isMultiviewMode = false

        ' Ensure loading state is reset when exiting multiview
        m.loadingLabel.visible = false
        m.loadingLabel.text = ""

        if m.multiviewGrid.shouldRestoreVideo then
            m.videoPlayer.setFocus(true)
            m.wasPlayingBeforeMultiview = false
        else
            m.videoPlayer.control = "stop"
            m.videoPlayer.visible = false
            m.videoPlayer.translation = [0, 0]
            m.videoPlayer.width = 1920
            m.videoPlayer.height = 1080
            m.wasPlayingBeforeMultiview = false
            loadPlaylist()
        end if

        ' Sync guide selection with currently playing channel
        if m.currentChannelIndex >= 0
            m.lastChannelIndex = m.currentChannelIndex
        end if

        ' Reset the switch flag
        m.hasSwitchedFromOriginal = false
    end if
end sub

sub onMultiviewExit()
    ' Immediately reset multiview mode when exit signal is received
    ' This prevents race conditions with the visible field observer
    if m.multiviewGrid.exitMultiview = true then
        m.isMultiviewMode = false
    end if
end sub

sub onMultiviewChannelSwitch()
    channelIdx = m.multiviewGrid.switchToChannelIndex

    ' Special case: -999 means it's the original stream channel
    if channelIdx = -999
        ' Only keep using the original player if we haven't switched away yet
        if not m.hasSwitchedFromOriginal and m.wasPlayingBeforeMultiview
            m.videoPlayer.setFocus(true)
            return
        else
            ' We've switched away before, so reload like any other channel
            ' Get the original channel index from multiview grid
            channelIdx = m.multiviewGrid.originalChannelIndex
        end if
    end if

    if channelIdx < 0 or channelIdx >= m.epgData.channels.count() then
        return
    end if

    m.blackFlashOverlay.visible = true

    ' Mark that we've switched away from original
    m.hasSwitchedFromOriginal = true

    m.retryAttempts = 0
    m.currentChannelIndex = channelIdx
    channel = m.epgData.channels[channelIdx]

    ' Set multiview size
    m.videoPlayer.translation = [0, 0]
    m.videoPlayer.width = 1540
    m.videoPlayer.height = 1080
    m.videoPlayer.visible = true

    ' Check if this is a TVPass channel that needs URL resolution
    if channel.url.Instr("tvpass.org/live/") >= 0 and channel.id <> invalid
        ' Clear cache + force fresh redirect on retry**
        if m.isRetrying or m.retryAttempts > 0
            m.resolvedUrlCache[channel.id] = invalid
        end if

        cachedUrl = invalid
        if m.resolvedUrlCache <> invalid and m.resolvedUrlCache.doesExist(channel.id) then
            cachedUrl = m.resolvedUrlCache[channel.id]
        end if

        ' Use cached final URL immediately
        if cachedUrl <> invalid and cachedUrl <> "" then
            playMultiviewChannel(channel, cachedUrl)
        else
            ' Store channel and mode for later playback
            m.pendingChannel = channel
            m.pendingChannelIsMultiview = true
            m.loadingLabel.visible = false

            ' Resolve the URL asynchronously
            resolveTask = createObject("roSGNode", "ResolveUrlTask")
            resolveTask.url = channel.url  ' Fresh from original TVPass URL
            resolveTask.observeField("resolvedUrl", "onUrlResolvedMultiview")
            resolveTask.control = "RUN"
        end if
    else
        ' Play directly for non-TVPass channels
        playMultiviewChannel(channel, channel.url)
    end if
end sub

sub onUrlResolvedMultiview(event as Object)
    resolveTask = event.getRoSGNode()
    resolvedUrl = resolveTask.resolvedUrl

    if resolvedUrl <> invalid and resolvedUrl <> "" and m.pendingChannel <> invalid and m.pendingChannel.id <> invalid
        ' Cache by stable channel.id
        m.resolvedUrlCache[m.pendingChannel.id] = resolvedUrl
        playMultiviewChannel(m.pendingChannel, resolvedUrl)
    else
        ' Fall back to original URL
        if m.pendingChannel <> invalid then
            playMultiviewChannel(m.pendingChannel, m.pendingChannel.url)
        end if
    end if

    m.pendingChannel = invalid
    m.pendingChannelIsMultiview = false
end sub

sub playMultiviewChannel(channel as Object, url as String)
    content = createObject("roSGNode", "ContentNode")
    content.url = url
    content.streamFormat = "hls"
    content.addField("preferredBitrate", "integer", false)
    content.preferredBitrate = 0
    content.addField("maxBandwidth", "integer", false)
    content.maxBandwidth = 0

    m.videoPlayer.content = content
    m.videoPlayer.control = "play"
    m.videoPlayer.maxVideoDecodeResolution = "1920x1080"
    m.videoPlayer.enableTrickPlay = false

     ' Hide black flash when new content is queued
    m.blackFlashOverlay.visible = false

    ' Update that we're no longer using the original stream
    m.wasPlayingBeforeMultiview = false
end sub

sub updateClock()
    now = CreateObject("roDateTime")
    now.ToLocalTime()
    hour = now.GetHours()
    minute = now.GetMinutes()
    ampm = "am"

    if hour >= 12 then
        ampm = "pm"
        if hour > 12 then hour = hour - 12
    end if
    if hour = 0 then hour = 12

    ' Format hour and minute strings properly
    hourStr = stri(hour).Trim()
    minuteStr = stri(minute).Trim()
    minuteStr = right("0" + minuteStr, 2)  ' Zero-pad minutes to 2 digits

    timeStr = hourStr + ":" + minuteStr + " " + ampm
    m.currentTimeLabel.text = timeStr
end sub

' Helper: Sort channels alphabetically by title
function SortChannelsAlphabetically(channels as Object) as Object
    n = channels.Count()
    for i = 0 to n-2
        for j = i+1 to n-1
            if LCase(channels[i].title) > LCase(channels[j].title)
                temp = channels[i]
                channels[i] = channels[j]
                channels[j] = temp
            end if
        end for
    end for
    return channels
end function

' Helper: Read additional playlist safely in SceneGraph
function LoadAdditionalPlaylist() as Object
    fileContent = invalid
    bytes = CreateObject("roByteArray")

    if bytes.ReadFile("pkg:/source/custom_playlist.m3u") then
        fileContent = bytes.ToAsciiString() ' SceneGraph-safe conversion
    end if

    return fileContent
end function

' Main: load playlists and other async tasks
sub loadPlaylist()
    if not EPGNeedsUpdate(m.epgData)
        m.loadingLabel.visible = false
        m.loadingLabel.text = ""
        showGuide()
        return
    end if

    m.loadingLabel.text = "Loading TV Guide..."
    m.loadingLabel.visible = true
    hideGuideElements()

    m.epgData.isLoading = true
    m.epgData.pendingTasks = 2  ' Only wait for playlist and EPG, not logo fallback
    m.epgData.playlistData = invalid
    m.epgData.epgData = invalid
    m.epgData.logoFallbackData = invalid

    timestamp = CreateObject("roDateTime").AsSeconds().ToStr()

    ' Load main TVPass playlist
    m.epgData.playlistTask = createObject("roSGNode", "LoadPlaylistTask")
    m.epgData.playlistTask.url = m.apiUrls.TVPASS_PLAYLIST + "?t=" + timestamp
    m.epgData.playlistTask.observeField("response", "onTvpassPlaylistResponse")
    m.epgData.playlistTask.observeField("error", "onPlaylistError")
    m.epgData.playlistTask.control = "RUN"

    ' Load additional local playlist
    playlistData = LoadAdditionalPlaylist()
    if playlistData <> invalid
        m.epgData.additionalChannels = EPGParsePlaylist(playlistData)
    else
        m.epgData.additionalChannels = []
    end if

    ' Load EPG XML
    m.epgData.epgTask = createObject("roSGNode", "LoadScheduleTask")
    m.epgData.epgTask.url = m.apiUrls.TVPASS_EPG + "?t=" + timestamp
    m.epgData.epgTask.observeField("response", "onScheduleResponse")
    m.epgData.epgTask.observeField("error", "onScheduleError")
    m.epgData.epgTask.control = "RUN"

    ' Load logo fallback in background - don't wait for it
    m.epgData.logoTask = createObject("roSGNode", "LoadPlaylistTask")
    m.epgData.logoTask.url = m.apiUrls.TVPASS_HD_FALLBACK + "?t=" + timestamp
    m.epgData.logoTask.observeField("response", "onLogoPlaylistResponse")
    m.epgData.logoTask.observeField("error", "onLogoPlaylistError")
    m.epgData.logoTask.control = "RUN"
end sub

' Response: handle main playlist, merge additional channels, and sort
sub onTvpassPlaylistResponse()
    ' Parse main playlist - keep original order
    mainChannels = EPGParsePlaylist(m.epgData.playlistTask.response)

    ' Merge custom channels alphabetically into main list
    if m.epgData.additionalChannels <> invalid
        for each ch in m.epgData.additionalChannels
            duplicate = false
            for each mainCh in mainChannels
                if ch.url = mainCh.url or (ch.tvgId <> "" and ch.tvgId = mainCh.tvgId)
                    duplicate = true
                    exit for
                end if
            end for
            if not duplicate then
                ' Find the position to insert this custom channel alphabetically
                insertPos = mainChannels.count()
                for i = 0 to mainChannels.count() - 1
                    if LCase(ch.title) < LCase(mainChannels[i].title)
                        insertPos = i
                        exit for
                    end if
                end for

                ' Insert at the found position
                newList = []
                for i = 0 to insertPos - 1
                    newList.push(mainChannels[i])
                end for
                newList.push(ch)
                for i = insertPos to mainChannels.count() - 1
                    newList.push(mainChannels[i])
                end for
                mainChannels = newList
            else
                ' Find and replace the duplicate
                for i = 0 to mainChannels.count() - 1
                    mainCh = mainChannels[i]
                    if (ch.url <> invalid and mainCh.url <> invalid and ch.url = mainCh.url) or (ch.tvgId <> invalid and ch.tvgId <> "" and mainCh.tvgId <> invalid and ch.tvgId = mainCh.tvgId)
                        ' Replace the main channel with custom channel
                        mainChannels[i] = ch
                        exit for
                    end if
                end for
            end if
        end for
    end if

    ' Ensure each channel has a stable id for URL caching
    for each channel in mainChannels
        if channel.id = invalid then
            if channel.tvgId <> invalid and channel.tvgId <> ""
                channel.id = channel.tvgId
            else
                channel.id = "ch_" + LCase(Left(channel.title, 20)).Replace(" ", "_")
            end if
        end if
    end for

    ' Assign merged channels
    m.epgData.channels = mainChannels
    m.epgData.playlistData = mainChannels

    ' Continue normal async flow
    m.epgData.pendingTasks = m.epgData.pendingTasks - 1

    ' If EPG is done, show guide immediately without waiting for logos
    if m.epgData.pendingTasks = 0
        ' Apply logos if fallback already loaded
        if m.epgData.logoFallbackData <> invalid
            EPGEnrichWithLogosFast(m.epgData.playlistData, m.epgData.logoFallbackData, m.logoUrls, m.networkLogoPatterns)
        end if
        finishLoading()
    end if
end sub

sub onLogoPlaylistResponse()
    m.epgData.logoFallbackData = EPGParsePlaylist(m.epgData.logoTask.response)
    m.epgData.logoTask = invalid

    ' If guide is already shown, apply logos now
    if m.epgData.pendingTasks = 0 and m.epgData.playlistData <> invalid
        EPGEnrichWithLogosFast(m.epgData.playlistData, m.epgData.logoFallbackData, m.logoUrls, m.networkLogoPatterns)
        ' Refresh the guide to show updated logos
        if m.channelList.content <> invalid
            m.channelList.content.notifyUpdate()
        end if
    end if
end sub

sub onLogoPlaylistError()
    m.epgData.logoTask = invalid
    ' Don't block loading - logos are optional
end sub

sub onScheduleResponse()
    if m.epgData.epgTask.response = invalid or m.epgData.epgTask.response = ""
        m.epgData.schedules = {}
        m.epgData.programsByChannel = {}
    else
        epgResult = EPGParseXMLOptimized(m.epgData.epgTask.response)
        m.epgData.schedules = epgResult.schedules
        m.epgData.programsByChannel = epgResult.programsByChannel
    end if
    m.epgData.epgTask = invalid

    m.epgData.pendingTasks = m.epgData.pendingTasks - 1

    ' If playlist is done, show guide immediately
    if m.epgData.pendingTasks = 0
        ' Apply logos if fallback already loaded
        if m.epgData.logoFallbackData <> invalid
            EPGEnrichWithLogosFast(m.epgData.playlistData, m.epgData.logoFallbackData, m.logoUrls, m.networkLogoPatterns)
        end if
        finishLoading()
    end if
end sub

sub onScheduleError()
    m.epgData.schedules = {}
    m.epgData.programsByChannel = {}
    m.epgData.epgTask = invalid

    m.epgData.pendingTasks = m.epgData.pendingTasks - 1

    if m.epgData.pendingTasks = 0
        if m.epgData.logoFallbackData <> invalid
            EPGEnrichWithLogosFast(m.epgData.playlistData, m.epgData.logoFallbackData, m.logoUrls, m.networkLogoPatterns)
        end if
        finishLoading()
    end if
end sub

sub onPlaylistError()
    m.epgData.playlistTask = invalid
    m.epgData.isLoading = false
    showError("Failed to load channel list")
end sub

sub finishLoading()
    m.epgData.isLoading = false
    m.epgData.lastUpdate = CreateObject("roDateTime").AsSeconds()

    ' Invalidate URL cache on EPG refresh
    m.resolvedUrlCache = {}

    ' Preload channel logos if needed
    if m.epgData.channels.count() > 0
        currentCacheSize = m.bitmapCache.getCacheSize()

        if currentCacheSize = 0 then
            logoUris = m.bitmapCache.collectUrisFromChannels(m.epgData.channels)
            if logoUris.count() > 0
                m.bitmapCache.preload(logoUris, m.preloadContainer)
            end if
        else
            logoUris = m.bitmapCache.collectUrisFromChannels(m.epgData.channels)
            newLogos = 0
            for each uri in logoUris
                if not m.bitmapCache.isCached(uri) then
                    newLogos++
                end if
            end for

            if newLogos > 0 then
                m.bitmapCache.preload(logoUris, m.preloadContainer)
            else
                print "BitmapCache: All channel logos already cached"
            end if
        end if
    end if

    ' Update multiview's EPG data reference
    m.multiviewGrid.epgData = m.epgData
    m.multiviewGrid.bitmapCache = m.bitmapCache

    ' Kick off background prefetch of TVPass redirect URLs
    PrefetchTvpassUrls()

    if m.epgData.channels.count() > 0
        showGuide()
    else
        showError("No channels found")
    end if
end sub

sub PrefetchTvpassUrls()
     ' Ensure epgData and channels are valid
    if m.epgData = invalid or m.epgData.channels = invalid then return

    tvpassUrls = {}   ' channel.id (string) -> url

    ' Iterate channels by index
    channelCount = m.epgData.channels.count()
    for i = 0 to channelCount - 1
        ch = m.epgData.channels[i]
        if ch <> invalid and ch.id <> invalid and ch.url <> invalid and ch.url.Instr("tvpass.org/live/") >= 0 then
            tvpassUrls[ch.id] = ch.url
        end if
    end for

    if tvpassUrls.count() = 0 then return

    m.prefetchTask = createObject("roSGNode", "ResolveUrlTask")
    m.prefetchTask.inputUrls = tvpassUrls
    m.prefetchTask.functionName = "runBatch"
    m.prefetchTask.observeField("resolvedUrls", "OnPrefetchResolved")
    m.prefetchTask.control = "run"
end sub

sub OnPrefetchResolved()
    if m.prefetchTask = invalid then return

    result = m.prefetchTask.resolvedUrls
    if result = invalid then return

    ' Keys are channel.id strings - store directly
    for each channelId in result
        m.resolvedUrlCache[channelId] = result[channelId]
    end for
end sub

sub createTimeSlotHeaders()
    m.timeSlotHeaders.removeChildrenIndex(m.timeSlotHeaders.getChildCount(), 0)

    ' Get current time in LOCAL timezone
    now = CreateObject("roDateTime")
    now.ToLocalTime()

    ' Get seconds AFTER converting to local time
    currentTime = now.AsSeconds()

    ' Round down to nearest 30 minutes
    roundedTime& = int(currentTime / 1800) * 1800

    slotWidth = 487

    for i = 0 to 2
        ' Add left border for this time block
        leftBorder = createObject("roSGNode", "Rectangle")
        leftBorder.width = 2
        leftBorder.height = 40
        leftBorder.color = m.uiColors.BLACK42
        m.timeSlotHeaders.appendChild(leftBorder)

        ' Calculate slot time - explicitly use Long Integer to avoid overflow
        slotTime& = roundedTime& + (i * 1800)

        ' Create new DateTime object for this slot
        slotDateTime = CreateObject("roDateTime")
        slotDateTime.FromSeconds(slotTime&)
        ' DON'T call ToLocalTime() here - the seconds are already in local context!

        hours = slotDateTime.GetHours()
        minutes = slotDateTime.GetMinutes()

        ' Convert to 12-hour format
        displayHour = hours
        ampm = "am"
        if hours >= 12
            ampm = "pm"
            if hours > 12
                displayHour = hours - 12
            end if
        end if
        if displayHour = 0 then displayHour = 12

        ' Format time string
        hourStr = stri(displayHour).Trim()
        minuteStr = stri(minutes).Trim()
        minuteStr = right("0" + minuteStr, 2)
        timeStr = hourStr + ":" + minuteStr + " " + ampm

        timeLabel = createObject("roSGNode", "Label")
        timeLabel.width = slotWidth
        timeLabel.height = 40
        timeLabel.font = "font:SmallBoldSystemFont"
        timeLabel.color = m.uiColors.GRAY88
        timeLabel.horizAlign = "center"
        timeLabel.vertAlign = "center"
        timeLabel.text = timeStr
        m.timeSlotHeaders.appendChild(timeLabel)
    end for

    ' Add right border after the last time block
    rightBorder = createObject("roSGNode", "Rectangle")
    rightBorder.width = 2
    rightBorder.height = 40
    rightBorder.color = m.uiColors.BLACK42
    m.timeSlotHeaders.appendChild(rightBorder)
end sub

sub showGuide()
    m.loadingLabel.visible = false
    createTimeSlotHeaders()

    root = createObject("roSGNode", "ContentNode")
    for i = 0 to m.epgData.channels.count() - 1
        channel = m.epgData.channels[i]
        item = root.createChild("ContentNode")
        item.addField("channelNumber", "integer", false)
        item.channelNumber = i + 1
        item.addField("isLongChannelName", "boolean", false)

        ' Determine if channel name is long
        isLongName = len(channel.title) > 30

        if isLongName
            item.title = "Ch " + Stri(i + 1)
            item.addField("nowPlaying", "string", false)
            item.nowPlaying = channel.title
            item.isLongChannelName = true
        else
            item.title = channel.title
            item.addField("nowPlaying", "string", false)
            item.isLongChannelName = false

            ' Check if channel has EPG data (tvgId exists and is not empty)
            if channel.tvgId <> invalid and channel.tvgId <> ""
                ' Has EPG data - get current program
                currentProgram = EPGGetCurrentProgram(m.epgData, channel.tvgId)
                if currentProgram <> ""
                    item.nowPlaying = currentProgram
                else
                    item.nowPlaying = channel.title
                end if
            else
                ' No EPG data (custom playlist) - use tvg-name (title) as nowPlaying
                item.nowPlaying = channel.title
            end if
        end if

        item.addField("streamUrl", "string", false)
        item.streamUrl = channel.url

        if channel.logo <> invalid and channel.logo <> ""
            item.addField("logo", "string", false)
            item.logo = channel.logo
        end if

        item.addField("programs", "array", false)
        if channel.tvgId <> invalid and channel.tvgId <> ""
            item.programs = EPGGetPrograms(m.epgData, channel.tvgId)
        else
            item.programs = []
        end if
    end for

    m.channelList.content = root

    ' Force Roku page size
    visibleHeight = 1080 - 310
    rowHeight = 119
    visibleRows = int(visibleHeight / rowHeight)

    if visibleRows < 1 then visibleRows = 1

    m.channelList.numRows = visibleRows

    restoreIndex = m.currentChannelIndex
    if restoreIndex < 0 or restoreIndex >= m.epgData.channels.count()
        restoreIndex = m.lastChannelIndex
    end if

    if restoreIndex >= 0 and restoreIndex < m.epgData.channels.count()
        updateFeaturedProgram(restoreIndex)
        m.channelList.jumpToItem = restoreIndex
        m.channelList.animateToItem = restoreIndex
    else if m.epgData.channels.count() > 0
        updateFeaturedProgram(0)
    end if

    showGuideElements()

    ' Clear the returning to guide flag now that we're fully loaded
    m.isReturningToGuide = false

    m.channelList.setFocus(true)
end sub

sub updateFeaturedProgram(index as Integer)
    if index < 0 or index >= m.epgData.channels.count() then return
    channel = m.epgData.channels[index]

    ' Set default channel logo with default dimensions
    if channel.logo <> invalid and channel.logo <> ""
        ' Reset to default centered position
        m.featuredLogo.translation = m.logoOriginalTranslation
        m.featuredLogo.width = m.defaultLogoWidth
        m.featuredLogo.height = m.defaultLogoHeight
        m.featuredLogo.uri = channel.logo
    end if

    m.featuredTitle.text = channel.title

    if channel.tvgId <> invalid and channel.tvgId <> ""
        currentProgram = EPGGetCurrentProgram(m.epgData, channel.tvgId)
        if currentProgram <> ""
            m.featuredTime.text = "Now Playing:"
            m.featuredDescription.text = currentProgram

            ' Check if this is a sports program
            isSports = IsSportsProgram(currentProgram, m.sportsKeywords)

            ' Only fetch artwork for non-sports programs
            if not isSports
                ' Get program duration to determine if movie or TV show
                programDuration = GetProgramDuration(m.epgData, channel.tvgId)
                ' NEW: Pass tvgId for EPG time lookup
                fetchShowArtwork(currentProgram, programDuration, channel.tvgId)
            end if
        else
            m.featuredTime.text = ""
            m.featuredDescription.text = "No program information available"
        end if
    else
        ' For custom playlist channels, show tvg-name
        m.featuredTime.text = "Now Playing:"
        m.featuredDescription.text = channel.title
    end if
end sub

function GetProgramDuration(epgData as Object, tvgId as String) as Integer
    ' Get the duration in seconds of the current program
    if tvgId = invalid then return 0

    normalizedId = EPGNormalizeChannelId(tvgId)

    if not epgData.programsByChannel.doesExist(normalizedId) then return 0

    programs = epgData.programsByChannel[normalizedId]
    if programs = invalid or programs.count() = 0 then return 0

    now = CreateObject("roDateTime").AsSeconds()

    for each program in programs
        if program.startTime <= now and program.endTime > now
            return program.endTime - program.startTime
        end if
    end for

    return 0
end function

sub fetchShowArtwork(showName as String, durationSeconds as Integer, tvgId as String)
    if showName = invalid or showName = "" then return

    ' Check cache first
    if m.artworkCache.doesExist(showName)
        cachedUrl = m.artworkCache[showName]
        if cachedUrl <> invalid and cachedUrl <> ""
            m.featuredLogo.uri = cachedUrl
        end if
        return
    end if

    ' Cancel any existing task
    if m.currentArtworkTask <> invalid
        m.currentArtworkTask.control = "stop"
        m.currentArtworkTask.unobserveField("artworkUrl")
        m.currentArtworkTask = invalid
    end if

    ' Create new artwork fetch task
    m.currentArtworkTask = createObject("roSGNode", "FanartArtworkTask")
    m.currentArtworkTask.showName = showName

    ' Try to get EPG times first
    if tvgId <> invalid and tvgId <> ""
        epgTimes = GetCurrentProgramTimes(m.epgData, tvgId)
        if epgTimes <> invalid
            m.currentArtworkTask.startTime = epgTimes.startTime
            m.currentArtworkTask.stopTime = epgTimes.stopTime
        end if
    end if

    m.currentArtworkTask.observeField("artworkUrl", "onArtworkReceived")
    m.currentArtworkTask.control = "RUN"
end sub

sub onArtworkReceived(event as Object)
    task = event.getRoSGNode()
    artworkUrl = task.artworkUrl
    showName = task.showName

    if artworkUrl <> invalid and artworkUrl <> ""
        ' Cache the artwork URL
        m.artworkCache[showName] = artworkUrl

        if m.featuredDescription.text = showName or m.featuredDescription.text.Instr(showName) >= 0
            ' Calculate centered position for poster art
            offsetX = (m.defaultLogoWidth - m.posterArtWidth) / 2
            offsetY = (m.defaultLogoHeight - m.posterArtHeight) / 2

            newTranslation = [
                m.logoOriginalTranslation[0] + offsetX,
                m.logoOriginalTranslation[1] + offsetY
            ]

            m.featuredLogo.translation = newTranslation
            m.featuredLogo.width = m.posterArtWidth
            m.featuredLogo.height = m.posterArtHeight
            m.featuredLogo.uri = artworkUrl
        end if
    else
        ' Cache empty result to avoid repeated failed requests
        m.artworkCache[showName] = ""
    end if

    ' Clean up task
    m.currentArtworkTask = invalid
end sub

sub showGuideElements()
    elements = [m.guideBackground, m.headerBackground, m.featuredLogo, m.featuredTitle, m.featuredTime, m.featuredDescription, m.currentTimeLabel, m.guideHeaderLabel, m.allChannelsLabel, m.timeSlotHeadersContainer, m.channelList]
    for each element in elements
        element.visible = true
    end for
end sub

sub hideGuideElements()
    elements = [m.guideBackground, m.headerBackground, m.featuredLogo, m.featuredTitle, m.featuredTime, m.featuredDescription, m.currentTimeLabel, m.guideHeaderLabel, m.allChannelsLabel, m.timeSlotHeadersContainer, m.channelList]
    for each element in elements
        element.visible = false
    end for
end sub

sub onChannelSelected()
    idx = m.channelList.itemSelected
    if idx >= 0 and idx < m.epgData.channels.count()
        if m.isBackgroundPlayback and idx = m.currentChannelIndex
            m.isBackgroundPlayback = false
            m.videoPlayer.opacity = 1.0
            m.videoOverlay.visible = false
            hideGuideElements()
            m.videoPlayer.setFocus(true)
        else
            m.retryAttempts = 0
            m.lastChannelIndex = idx
            m.currentChannelIndex = idx
            channel = m.epgData.channels[idx]
            playChannel(channel)
            m.isBackgroundPlayback = false
            updateFeaturedProgram(idx)
        end if
    end if
end sub

sub onMenuChannelSelected()
    idx = m.channelMenu.selectedChannel
    if idx >= 0 and idx < m.epgData.channels.count()
        m.retryAttempts = 0
        m.lastChannelIndex = idx
        m.currentChannelIndex = idx
        channel = m.epgData.channels[idx]
        m.channelMenu.visible = false
        playChannel(channel)
        m.isBackgroundPlayback = false
    end if
end sub

sub playChannel(channel as Object)
    m.blackFlashOverlay.visible = true

    ' Stop all timers before starting new playback
    m.bufferingTimer.control = "stop"
    m.positionCheckTimer.control = "stop"
    m.retryTimer.control = "stop"
    m.returnToGuideTimer.control = "stop"

    ' Reset position tracking and stream establishment flag
    m.lastPosition = 0
    m.streamEstablished = false

    m.videoPlayer.opacity = 1.0
    m.videoPlayer.visible = true
    m.videoOverlay.visible = false
    m.videoInfoOverlay.showOverlay = false
    hideGuideElements()

    ' Check if this is a TVPass channel that needs URL resolution
    if channel.url.Instr("tvpass.org/live/") >= 0 and channel.id <> invalid
        ' Clear cache + force FRESH redirect on EVERY retry
        if m.isRetrying or m.retryAttempts > 0
            m.resolvedUrlCache[channel.id] = invalid
        end if

        cachedUrl = invalid
        if m.resolvedUrlCache <> invalid and m.resolvedUrlCache.doesExist(channel.id) then
            cachedUrl = m.resolvedUrlCache[channel.id]
        end if

        if cachedUrl <> invalid and cachedUrl <> "" then
            ' Use cached final URL immediately
            playChannelWithUrl(channel, cachedUrl)
        else
            ' Store channel for later playback after fresh resolution
            m.pendingChannel = channel
            resolveTask = createObject("roSGNode", "ResolveUrlTask")
            resolveTask.url = channel.url ' Original TVPass URL → fresh redirect
            resolveTask.observeField("resolvedUrl", "onUrlResolved")
            resolveTask.control = "RUN"
        end if
    else
        ' Play directly for non-TVPass channels
        playChannelWithUrl(channel, channel.url)
    end if
end sub

function GetCurrentProgramTimes(epgData as Object, tvgId as String) as Object
    ' Returns {startTime: "YYYYMMDDHHMMSS +0000", stopTime: "YYYYMMDDHHMMSS +0000"}
    if tvgId = invalid then return invalid

    normalizedId = EPGNormalizeChannelId(tvgId)

    if not epgData.programsByChannel.doesExist(normalizedId) then return invalid

    programs = epgData.programsByChannel[normalizedId]
    if programs = invalid or programs.count() = 0 then return invalid

    now = CreateObject("roDateTime").AsSeconds()

    for each program in programs
        if program.startTime <= now and program.endTime > now
            ' Return the original EPG time strings if they exist
            if program.startTimeStr <> invalid and program.stopTimeStr <> invalid
                return {
                    startTime: program.startTimeStr
                    stopTime: program.stopTimeStr
                }
            end if
        end if
    end for

    return invalid
end function

sub onUrlResolved(event as Object)
    resolveTask = event.getRoSGNode()
    resolvedUrl = resolveTask.resolvedUrl

    if resolvedUrl <> invalid and resolvedUrl <> "" and m.pendingChannel <> invalid and m.pendingChannel.id <> invalid
        ' Cache by stable channel.id
        m.resolvedUrlCache[m.pendingChannel.id] = resolvedUrl
        playChannelWithUrl(m.pendingChannel, resolvedUrl)
    else
        ' Fall back to original URL
        if m.pendingChannel <> invalid then
            playChannelWithUrl(m.pendingChannel, m.pendingChannel.url)
        end if
    end if

    m.pendingChannel = invalid
end sub

sub playChannelWithUrl(channel as Object, url as String)
    m.loadingLabel.visible = false

    content = createObject("roSGNode", "ContentNode")
    content.url = url
    content.streamFormat = "hls"
    content.addField("preferredBitrate", "integer", false)
    content.preferredBitrate = 0
    content.addField("maxBandwidth", "integer", false)
    content.maxBandwidth = 0

    m.videoPlayer.content = content
    m.videoPlayer.control = "play"
    m.videoPlayer.maxVideoDecodeResolution = "1920x1080"
    m.videoPlayer.enableTrickPlay = false
    m.videoPlayer.setFocus(true)

    ' Hide black flash when new content is queued
    m.blackFlashOverlay.visible = false

    ' Update overlay data
    updateVideoOverlay()
end sub

sub updateVideoOverlay()
    if m.currentChannelIndex < 0 or m.currentChannelIndex >= m.epgData.channels.count() then return

    channel = m.epgData.channels[m.currentChannelIndex]
    now = CreateObject("roDateTime").AsSeconds()

    overlayData = {
        channelNumber: m.currentChannelIndex + 1
        logo: channel.logo  ' Start with channel logo
        title: channel.title
        nowPlaying: ""
        programDetails: ""
    }

    ' NEW: Track current show name for artwork fetching
    currentShowName = ""
    programDuration = 0

    if channel.tvgId <> invalid and channel.tvgId <> ""
        currentProgram = EPGGetCurrentProgram(m.epgData, channel.tvgId)
        if currentProgram <> ""
            overlayData.nowPlaying = currentProgram
            currentShowName = currentProgram  ' NEW: Store for artwork fetch
        else
            overlayData.nowPlaying = channel.title
        end if

        programs = EPGGetPrograms(m.epgData, channel.tvgId)
        if programs.count() > 0
            for each prog in programs
                if prog.startTime <= now and prog.endTime > now
                    ' NEW: Get program duration for movie detection
                    programDuration = prog.endTime - prog.startTime

                    isSportsProgram = IsSportsProgram(prog.title, m.sportsKeywords)

                    if isSportsProgram and prog.subTitle <> invalid and prog.subTitle <> ""
                        overlayData.programDetails = prog.subTitle
                    else if prog.description <> invalid and prog.description <> ""
                        overlayData.programDetails = prog.description
                    end if
                    exit for
                end if
            end for
        end if
    else
        ' For custom playlist channels, show tvg-name
        overlayData.nowPlaying = channel.title
    end if

    ' Set overlay data first (with channel logo)
    m.videoInfoOverlay.channelData = overlayData

    ' NEW: Fetch artwork for the current show (if not sports)
    if currentShowName <> ""
        isSports = IsSportsProgram(currentShowName, m.sportsKeywords)
        if not isSports
            fetchVideoOverlayArtwork(currentShowName, programDuration, channel.tvgId)
        end if
    end if
end sub

sub fetchVideoOverlayArtwork(showName as String, durationSeconds as Integer, tvgId as String)
    if showName = invalid or showName = "" then return

    ' Check cache first
    if m.artworkCache.doesExist(showName)
        cachedUrl = m.artworkCache[showName]
        if cachedUrl <> invalid and cachedUrl <> ""
            updateVideoOverlayWithArtwork(cachedUrl)
        end if
        return
    end if

    ' Cancel any existing overlay artwork task
    if m.overlayArtworkTask <> invalid
        m.overlayArtworkTask.control = "stop"
        m.overlayArtworkTask.unobserveField("artworkUrl")
        m.overlayArtworkTask = invalid
    end if

    ' Create new artwork fetch task
    m.overlayArtworkTask = createObject("roSGNode", "FanartArtworkTask")
    m.overlayArtworkTask.showName = showName

    ' Try to get EPG times first
    if tvgId <> invalid and tvgId <> ""
        epgTimes = GetCurrentProgramTimes(m.epgData, tvgId)
        if epgTimes <> invalid
            m.overlayArtworkTask.startTime = epgTimes.startTime
            m.overlayArtworkTask.stopTime = epgTimes.stopTime
        end if
    end if

    m.overlayArtworkTask.observeField("artworkUrl", "onOverlayArtworkReceived")
    m.overlayArtworkTask.control = "RUN"
end sub

sub onOverlayArtworkReceived(event as Object)
    task = event.getRoSGNode()
    artworkUrl = task.artworkUrl
    showName = task.showName

    if artworkUrl <> invalid and artworkUrl <> ""
        ' Cache the artwork URL
        m.artworkCache[showName] = artworkUrl
        updateVideoOverlayWithArtwork(artworkUrl)
    else
        ' Cache empty result to avoid repeated failed requests
        m.artworkCache[showName] = ""
    end if

    ' Clean up task
    m.overlayArtworkTask = invalid
end sub

sub updateVideoOverlayWithArtwork(artworkUrl as String)
    if artworkUrl = invalid or artworkUrl = "" then return

    ' Update the overlay's logo with the fetched artwork
    currentData = m.videoInfoOverlay.channelData
    if currentData <> invalid
        currentData.logo = artworkUrl
        m.videoInfoOverlay.channelData = currentData
    end if
end sub

sub checkStreamQuality()
    ' Add this inside onVideoStateChanged when state = "playing"
    if m.videoPlayer.state = "playing"
        streamInfo = m.videoPlayer.streamInfo
        if streamInfo <> invalid
            print "=== Stream Quality Info ==="
            if streamInfo.doesExist("bitrate") and streamInfo.bitrate <> invalid
                print "Current bitrate: " + str(streamInfo.bitrate)
            end if
            if streamInfo.doesExist("measuredBitrate") and streamInfo.measuredBitrate <> invalid
                print "Measured bitrate: " + str(streamInfo.measuredBitrate)
            end if
            if streamInfo.doesExist("videoWidth") and streamInfo.videoWidth <> invalid
                print "Video width: " + str(streamInfo.videoWidth)
            end if
            if streamInfo.doesExist("videoHeight") and streamInfo.videoHeight <> invalid
                print "Video height: " + str(streamInfo.videoHeight)
            end if
            print "=========================="
        else
            print "Stream info not available yet"
        end if
    end if
end sub

sub onVideoStateChanged()
    state = m.videoPlayer.state
    errorCode = m.videoPlayer.errorCode
    hasError = (errorCode <> invalid and errorCode <> 0)

    if state = "error" or hasError or state = "finished" or state = "stopped"
        m.blackFlashOverlay.visible = false
        msgParts = ["Video state changed: ", state, " errorCode: ", str(errorCode)]
        print msgParts.Join("")
    end if

    if state = "error" or hasError
        ' PREVENT RETRY SPAM: ignore if already retrying
        if m.retryInProgress then return

        msgParts = ["Video error detected (code: ", str(errorCode), "). Retry attempt ", str(m.retryAttempts + 1), "/", str(m.maxRetryAttempts)]
        print msgParts.Join("")

        m.bufferingTimer.control = "stop"
        m.positionCheckTimer.control = "stop"
        m.retryTimer.control = "stop"
        m.returnToGuideTimer.control = "stop"

        if m.retryAttempts < m.maxRetryAttempts and m.currentChannelIndex >= 0
            m.retryAttempts = m.retryAttempts + 1
            m.isRetrying = true
            m.retryInProgress = true

            msgParts = ["Server full, retrying... (", Stri(m.retryAttempts), "/", Stri(m.maxRetryAttempts), ")"]
            m.loadingLabel.text = msgParts.Join("")

            if not m.isMultiviewMode
                m.loadingLabel.visible = true
                m.videoPlayer.control = "stop"
                m.videoPlayer.visible = false
            else
                m.loadingLabel.visible = false
                m.videoPlayer.control = "stop"
            end if

            m.retryTimer.duration = m.retryDelay
            m.retryTimer.control = "start"
        else
            m.retryInProgress = false
            msgParts = ["Max retries reached or no channel selected"]
            print msgParts.Join("")
            m.loadingLabel.text = "Unable to connect - Server full"

            if not m.isMultiviewMode
                m.loadingLabel.visible = true
                m.videoPlayer.control = "stop"
                m.videoPlayer.visible = false
            else
                m.loadingLabel.visible = false
                m.videoPlayer.control = "stop"
            end if

            m.returnToGuideTimer.control = "start"
        end if
        return
    end if

    if state = "finished" or state = "stopped"
        if m.isRetrying then return
        if m.isMultiviewMode then return

        m.bufferingTimer.control = "stop"
        m.positionCheckTimer.control = "stop"
        m.retryTimer.control = "stop"
        m.returnToGuideTimer.control = "stop"

        m.videoPlayer.control = "stop"
        m.videoPlayer.visible = false
        loadPlaylist()
        return
    end if

    if state = "playing"
        m.blackFlashOverlay.visible = false
        m.retryInProgress = false
        m.retryAttempts = 0
        m.isRetrying = false
        m.streamEstablished = true  ' Mark stream as successfully established

        m.loadingLabel.visible = false

        m.bufferingTimer.control = "stop"
        m.retryTimer.control = "stop"
        m.returnToGuideTimer.control = "stop"

        checkStreamQuality()

        ' Only start position check if stream not yet established
        ' Once established, we don't need to check for "server full"
        if not m.streamEstablished then
            m.lastPosition = m.videoPlayer.position
            m.positionCheckTimer.control = "stop"
            m.positionCheckTimer.control = "start"
        end if

        if m.isMultiviewMode
            m.multiviewGrid.visible = true
            m.multiviewGrid.setFocus(false)
            m.multiviewGrid.setFocus(true)
            m.videoPlayer.setFocus(false)
        end if
    end if

    if state = "buffering"
        m.bufferingTimer.control = "stop"
        m.bufferingTimer.control = "start"
    end if
end sub

sub onBufferingTimeout()
    if m.retryInProgress then return

    ' If stream was already established, don't treat buffering as a failure
    if m.streamEstablished then
        print "Stream established - ignoring buffering timeout"
        return
    end if

    if m.videoPlayer.state = "buffering"
        msgParts = ["Still buffering after timeout. Retry attempt ", str(m.retryAttempts + 1), "/", str(m.maxRetryAttempts)]
        print msgParts.Join("")

        m.positionCheckTimer.control = "stop"
        m.retryTimer.control = "stop"
        m.returnToGuideTimer.control = "stop"

        if m.retryAttempts < m.maxRetryAttempts and m.currentChannelIndex >= 0
            m.retryAttempts = m.retryAttempts + 1
            m.isRetrying = true

            msgParts = ["Timeout, retrying... (", Stri(m.retryAttempts), "/", Stri(m.maxRetryAttempts), ")"]
            m.loadingLabel.text = msgParts.Join("")

            if not m.isMultiviewMode
                m.loadingLabel.visible = true
                m.videoPlayer.visible = false
            else
                m.loadingLabel.visible = false
            end if

            m.videoPlayer.control = "stop"

            m.retryTimer.duration = m.retryDelay
            m.retryTimer.control = "start"
        else
            m.loadingLabel.text = "Connection timeout"

            if not m.isMultiviewMode
                m.loadingLabel.visible = true
                m.videoPlayer.visible = false
            else
                m.loadingLabel.visible = false
            end if

            m.videoPlayer.control = "stop"
            m.returnToGuideTimer.control = "start"
        end if
    else
        msgParts = ["Buffering timeout fired but state is now: ", m.videoPlayer.state]
        print msgParts.Join("")
    end if
end sub

sub onPositionCheck()
    if m.retryInProgress then return

    ' If stream was already established, don't check for stuck position
    if m.streamEstablished then
        return
    end if

    currentPosition = m.videoPlayer.position

    if currentPosition = m.lastPosition or currentPosition < 1
        msgParts = ["Stream appears stuck at position ", str(currentPosition), ". Retry attempt ", str(m.retryAttempts + 1), "/", str(m.maxRetryAttempts)]
        print msgParts.Join("")

        m.bufferingTimer.control = "stop"
        m.retryTimer.control = "stop"
        m.returnToGuideTimer.control = "stop"

        if m.retryAttempts < m.maxRetryAttempts and m.currentChannelIndex >= 0
            m.retryAttempts = m.retryAttempts + 1
            m.isRetrying = true

            msgParts = ["Server full, retrying... (", Stri(m.retryAttempts), "/", Stri(m.maxRetryAttempts), ")"]
            m.loadingLabel.text = msgParts.Join("")

            if not m.isMultiviewMode
                m.loadingLabel.visible = true
                m.videoPlayer.visible = false
            else
                m.loadingLabel.visible = false
            end if

            m.videoPlayer.control = "stop"

            m.retryTimer.duration = m.retryDelay
            m.retryTimer.control = "start"
        else
            print "Max retries reached"
            m.loadingLabel.text = "Unable to connect"

            if not m.isMultiviewMode
                m.loadingLabel.visible = true
                m.videoPlayer.visible = false
            else
                m.loadingLabel.visible = false
            end if

            m.videoPlayer.control = "stop"
            m.returnToGuideTimer.control = "start"
        end if
    else
        m.lastPosition = currentPosition
        m.positionCheckTimer.control = "stop"
        m.positionCheckTimer.control = "start"
    end if
end sub

sub onRetryTimer()
    ' Reset retry lock BEFORE attempting new playback
    m.retryInProgress = false

    if m.currentChannelIndex >= 0 and m.currentChannelIndex < m.epgData.channels.count()
        channel = m.epgData.channels[m.currentChannelIndex]
        playChannel(channel)
    else
        returnToGuide()
    end if
end sub

sub returnToGuide()
    ' Stop all timers
    m.bufferingTimer.control = "stop"
    m.positionCheckTimer.control = "stop"
    m.retryTimer.control = "stop"
    m.returnToGuideTimer.control = "stop"

    m.loadingLabel.visible = false
    m.retryAttempts = 0
    loadPlaylist()
end sub

sub onChannelFocused()
    idx = m.channelList.itemFocused
    if idx >= 0 and idx < m.epgData.channels.count()
        updateFeaturedProgram(idx)
    end if
end sub

sub showError(msg as String)
    m.loadingLabel.text = "Error: " + msg
    m.loadingLabel.visible = true
end sub

sub showChannelMenu()
    channelsWithInfo = []
    for i = 0 to m.epgData.channels.count() - 1
        channel = m.epgData.channels[i]
        channelData = {
            title: channel.title
            logo: channel.logo
            url: channel.url
            tvgId: channel.tvgId
            channelNumber: i + 1
            nowPlaying: ""
            programDetails: ""
            isSports: false
            timeSlots: invalid
        }

        if channel.tvgId <> invalid and channel.tvgId <> ""
            ' Get programs for all 3 time slots
            timeSlots = EPGGetProgramsForTimeSlots(m.epgData, channel.tvgId)
            channelData.timeSlots = timeSlots

            ' Set nowPlaying to current slot (slot1)
            if timeSlots.slot1 <> ""
                channelData.nowPlaying = timeSlots.slot1
            else
                channelData.nowPlaying = channel.title
            end if

            ' Get description for current program
            programs = EPGGetPrograms(m.epgData, channel.tvgId)
            if programs.count() > 0
                now = CreateObject("roDateTime").AsSeconds()
                for each prog in programs
                    if prog.startTime <= now and prog.endTime > now
                        isSportsProgram = IsSportsProgram(prog.title, m.sportsKeywords)
                        channelData.isSports = isSportsProgram

                        if prog.description <> invalid and prog.description <> ""
                            channelData.programDetails = prog.description
                        end if
                        exit for
                    end if
                end for
            end if
        else
            ' For custom playlist channels, show tvg-name
            channelData.nowPlaying = channel.title
        end if

        channelsWithInfo.push(channelData)
    end for

    restoreIndex = m.currentChannelIndex
    if restoreIndex < 0 or restoreIndex >= m.epgData.channels.count()
        restoreIndex = m.lastChannelIndex
    end if

    m.channelMenu.currentChannelIndex = restoreIndex
    m.channelMenu.initialChannelIndex = restoreIndex
    m.channelMenu.epgData = m.epgData
    m.channelMenu.channels = channelsWithInfo
    m.channelMenu.visible = true
    m.channelMenu.setFocus(true)
end sub

function onKeyEvent(key as String, press as Boolean) as Boolean
    dt = CreateObject("roDateTime")
    currentTime = dt.AsSeconds()
    currentTimeMs = (currentTime * 1000) + dt.GetMilliseconds()

    ' Let multiview handle its own keys FIRST
    if m.isMultiviewMode
        ' If in multiview mode, don't let MainScene handle any keys
        ' MultiviewGrid will handle them all, including back button
        return false
    end if

    if m.channelMenu.visible
        if (key = "back" or key = "left") and press
            ' Set transitioning flag to prevent race conditions
            m.isMenuTransitioning = true
            m.channelMenu.visible = false
            ' Give focus back to video player
            m.videoPlayer.setFocus(true)
            ' Clear flag after a brief delay
            m.isMenuTransitioning = false
            return true
        end if
        return false
    end if

    if press
        if key = "up" and m.videoPlayer.visible and not m.channelMenu.visible
            ' Show video info overlay
            m.upButtonPressTime = currentTimeMs
            m.videoInfoOverlay.showOverlay = true
            return true
        end if
        if key = "down" and m.videoPlayer.visible and not m.channelMenu.visible
            ' Close video info overlay
            m.videoInfoOverlay.showOverlay = false
            return true
        end if
        if key = "left" and m.videoPlayer.visible
            m.leftButtonPressTime = currentTimeMs
            m.channelMenu.visible = false
            return true
        end if
        if key = "right" and m.videoPlayer.visible
            ' Don't allow menu to open if we're transitioning
            if m.isMenuTransitioning then return true
            m.rightButtonPressTime = currentTimeMs
            showChannelMenu()
            return true
        end if
        if key = "back" and m.videoPlayer.visible
            ' Prevent multiple rapid back presses from causing race conditions
            if m.isMenuTransitioning or m.isReturningToGuide then return true

            ' Set flag to prevent duplicate back button handling
            m.isReturningToGuide = true

            ' Ensure multiview state is cleared
            if m.isMultiviewMode then
                m.isMultiviewMode = false
            end if

            ' Close any open overlays
            m.videoInfoOverlay.showOverlay = false
            m.channelMenu.visible = false

            m.isBackgroundPlayback = true
            m.videoPlayer.opacity = 1.0
            m.videoPlayer.visible = true
            m.videoOverlay.visible = true
            showGuideElements()
            loadPlaylist()

            ' Clear the flag after a delay to allow the transition to complete
            ' This will be reset when the guide is fully loaded
            return true
        end if
        if key = "options" or key = "*"
            if not m.videoPlayer.visible
                m.epgData.lastUpdate = 0
                loadPlaylist()
                return true
            end if
        end if
    else
        if key = "left" and m.leftButtonPressTime > 0
            duration = currentTimeMs - m.leftButtonPressTime
            m.leftButtonPressTime = 0
            if duration >= m.longPressThreshold and m.videoPlayer.visible
                seekBackward()
                return true
            else if m.videoPlayer.visible
                ' Don't allow menu to open if we're transitioning
                if m.isMenuTransitioning then return true
                showChannelMenu()
                return true
            end if
        end if
        if key = "right" and m.rightButtonPressTime > 0
            duration = currentTimeMs - m.rightButtonPressTime
            m.rightButtonPressTime = 0
            if duration >= m.longPressThreshold and m.videoPlayer.visible
                seekForward()
                return true
            else if m.videoPlayer.visible
                ' Don't allow menu to open if we're transitioning
                if m.isMenuTransitioning then return true
                showChannelMenu()
                return true
            end if
        end if
    end if
    return false
end function

sub seekBackward()
    if m.videoPlayer.content <> invalid
        newPos = m.videoPlayer.position - 10
        if newPos < 0 then newPos = 0
        m.videoPlayer.seek = newPos
    end if
end sub

sub seekForward()
    if m.videoPlayer.content <> invalid
        newPos = m.videoPlayer.position + 10
        dur = m.videoPlayer.duration
        if dur > 0 and newPos > dur then newPos = dur
        m.videoPlayer.seek = newPos
    end if
end sub

function GetNowPlayingForChannel(channel as Object, now as Integer) as String
    if channel.tvgId = invalid or channel.tvgId = "" then return channel.title

    programs = EPGGetPrograms(m.epgData, channel.tvgId)
    if programs = invalid or programs.count() = 0 then return channel.title

    for each prog in programs
        if prog.startTime <= now and prog.endTime > now then
            programTitle = prog.title

            isSports = IsSportsProgram(programTitle, m.sportsKeywords)

            if isSports and prog.subTitle <> invalid and prog.subTitle <> ""
                return prog.subTitle
            end if

            return programTitle
        end if
    end for

    return channel.title
end function