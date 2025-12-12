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
    m.timeSlotHeaders = m.top.findNode("timeSlotHeaders")
    m.multiviewGrid = m.top.findNode("multiviewGrid")
    m.videoInfoOverlay = m.top.findNode("videoInfoOverlay")
    
    ' Initialize UI colors
    m.uiColors = GetUIColors()
    
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

    ' Pre-create all timers in init() — CRITICAL: Prevents runtime crashes from createChild("Timer")
    m.clockTimer = createObject("roSGNode", "Timer")
    m.clockTimer.repeat = true
    m.clockTimer.duration = 60
    m.clockTimer.observeField("fire", "updateClock")

    m.retryTimer = createObject("roSGNode", "Timer")
    m.retryTimer.repeat = false
    m.retryTimer.observeField("fire", "onRetryTimer")
    
    m.bufferingTimer = createObject("roSGNode", "Timer")
    m.bufferingTimer.repeat = false
    m.bufferingTimer.duration = 10
    m.bufferingTimer.observeField("fire", "onBufferingTimeout")

    m.positionCheckTimer = createObject("roSGNode", "Timer")
    m.positionCheckTimer.repeat = false
    m.positionCheckTimer.duration = 3
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
    if m.isMultiviewMode
        m.multiviewGrid.setFocus(true)
    else if m.videoPlayer.visible
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
        
        ' Reset the switch flag
        m.hasSwitchedFromOriginal = false
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

    ' Mark that we've switched away from original
    m.hasSwitchedFromOriginal = true

    m.retryAttempts = 0
    m.currentChannelIndex = channelIdx
    channel = m.epgData.channels[channelIdx]
    
    ' Play channel in multiview size
    m.videoPlayer.translation = [0, 0]
    m.videoPlayer.width = 1540
    m.videoPlayer.height = 1080
    m.videoPlayer.visible = true
    
    content = createObject("roSGNode", "ContentNode")
    content.url = channel.url
    content.streamFormat = "hls"
    content.addField("preferredBitrate", "integer", false)
    content.preferredBitrate = 0
    content.addField("maxBandwidth", "integer", false)
    content.maxBandwidth = 0

    print "Playing channel: " + content.url

    m.videoPlayer.content = content
    m.videoPlayer.control = "play"
    m.videoPlayer.maxVideoDecodeResolution = "1920x1080"
    m.videoPlayer.enableTrickPlay = false
    
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

sub loadPlaylist()
    if not EPGNeedsUpdate(m.epgData)
        showGuide()
        return
    end if
    
    m.loadingLabel.text = "Loading TV Guide..."
    m.loadingLabel.visible = true
    hideGuideElements()
    
    m.epgData.isLoading = true
    m.epgData.pendingTasks = 3
    m.epgData.playlistData = invalid
    m.epgData.epgData = invalid
    m.epgData.logoFallbackData = invalid
    
    timestamp = CreateObject("roDateTime").AsSeconds().ToStr()
    
    ' Load main playlist
    m.epgData.playlistTask = createObject("roSGNode", "LoadPlaylistTask")
    m.epgData.playlistTask.url = m.apiUrls.TVPASS_PLAYLIST + "?t=" + timestamp
    m.epgData.playlistTask.observeField("response", "onTvpassPlaylistResponse")
    m.epgData.playlistTask.observeField("error", "onPlaylistError")
    m.epgData.playlistTask.control = "RUN"
    
    ' Load EPG XML
    m.epgData.epgTask = createObject("roSGNode", "LoadScheduleTask")
    m.epgData.epgTask.url = m.apiUrls.TVPASS_EPG + "?t=" + timestamp
    m.epgData.epgTask.observeField("response", "onScheduleResponse")
    m.epgData.epgTask.observeField("error", "onScheduleError")
    m.epgData.epgTask.control = "RUN"
    
    ' Load logo fallback
    m.epgData.logoTask = createObject("roSGNode", "LoadPlaylistTask")
    m.epgData.logoTask.url = m.apiUrls.TVPASS_HD_FALLBACK + "?t=" + timestamp
    m.epgData.logoTask.observeField("response", "onLogoPlaylistResponse")
    m.epgData.logoTask.observeField("error", "onLogoPlaylistError")
    m.epgData.logoTask.control = "RUN"
end sub

sub onTvpassPlaylistResponse()
    m.epgData.playlistData = EPGParsePlaylist(m.epgData.playlistTask.response)
    m.epgData.playlistTask = invalid
    checkPlaylistsComplete()
end sub

sub onLogoPlaylistResponse()
    m.epgData.logoFallbackData = EPGParsePlaylist(m.epgData.logoTask.response)
    m.epgData.logoTask = invalid
    checkPlaylistsComplete()
end sub

sub onLogoPlaylistError()
    m.epgData.logoTask = invalid
    checkPlaylistsComplete()
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
    checkPlaylistsComplete()
end sub

sub onScheduleError()
    m.epgData.schedules = {}
    m.epgData.programsByChannel = {}
    m.epgData.epgTask = invalid
    checkPlaylistsComplete()
end sub

sub onPlaylistError()
    m.epgData.playlistTask = invalid
    m.epgData.isLoading = false
    showError("Failed to load channel list")
end sub

sub checkPlaylistsComplete()
    m.epgData.pendingTasks = m.epgData.pendingTasks - 1
    if m.epgData.pendingTasks = 0
        EPGEnrichWithLogosFast(m.epgData.playlistData, m.epgData.logoFallbackData, m.logoUrls, m.networkLogoPatterns)
        m.epgData.channels = m.epgData.playlistData
        m.epgData.isLoading = false
        m.epgData.lastUpdate = CreateObject("roDateTime").AsSeconds()
        
        ' Update multiview's EPG data reference for logo preloading
        m.multiviewGrid.epgData = m.epgData
        
        if m.epgData.channels.count() > 0
            showGuide()
        else
            showError("No channels found")
        end if
    end if
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
    
    slotWidth = 517
    
    for i = 0 to 2
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
        
        if len(channel.title) > 30
            item.title = "Ch " + Stri(i + 1)
            item.addField("nowPlaying", "string", false)
            item.nowPlaying = channel.title
            item.isLongChannelName = true
        else
            item.title = channel.title
            item.addField("nowPlaying", "string", false)
            item.isLongChannelName = false
            if channel.tvgId <> invalid
                item.nowPlaying = EPGGetCurrentProgram(m.epgData, channel.tvgId)
            else
                item.nowPlaying = ""
            end if
        end if
        
        item.addField("streamUrl", "string", false)
        item.streamUrl = channel.url
        
        if channel.logo <> invalid and channel.logo <> ""
            item.addField("logo", "string", false)
            item.logo = channel.logo
        end if
        
        item.addField("programs", "array", false)
        if channel.tvgId <> invalid
            item.programs = EPGGetPrograms(m.epgData, channel.tvgId)
        else
            item.programs = []
        end if
    end for
    
    m.channelList.content = root
    
    if m.lastChannelIndex >= 0 and m.lastChannelIndex < m.epgData.channels.count()
        updateFeaturedProgram(m.lastChannelIndex)
        m.channelList.jumpToItem = m.lastChannelIndex
        m.channelList.animateToItem = m.lastChannelIndex
    else if m.epgData.channels.count() > 0
        updateFeaturedProgram(0)
    end if
    
    showGuideElements()
    m.channelList.setFocus(true)
end sub

sub updateFeaturedProgram(index as Integer)
    if index < 0 or index >= m.epgData.channels.count() then return
    channel = m.epgData.channels[index]
    
    if channel.logo <> invalid and channel.logo <> ""
        m.featuredLogo.uri = channel.logo
    end if
    
    m.featuredTitle.text = channel.title
    
    if channel.tvgId <> invalid
        currentProgram = EPGGetCurrentProgram(m.epgData, channel.tvgId)
        if currentProgram <> ""
            m.featuredTime.text = "Now Playing"
            m.featuredDescription.text = currentProgram
        else
            m.featuredTime.text = ""
            m.featuredDescription.text = "No program information available"
        end if
    else
        m.featuredTime.text = ""
        m.featuredDescription.text = "No program information available"
    end if
end sub

sub showGuideElements()
    elements = [m.guideBackground, m.headerBackground, m.featuredLogo, m.featuredTitle, m.featuredTime, m.featuredDescription, m.currentTimeLabel, m.guideHeaderLabel, m.allChannelsLabel, m.timeSlotHeaders, m.channelList]
    for each element in elements
        element.visible = true
    end for
end sub

sub hideGuideElements()
    elements = [m.guideBackground, m.headerBackground, m.featuredLogo, m.featuredTitle, m.featuredTime, m.featuredDescription, m.currentTimeLabel, m.guideHeaderLabel, m.allChannelsLabel, m.timeSlotHeaders, m.channelList]
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
    m.videoPlayer.opacity = 1.0
    m.videoPlayer.visible = true
    m.videoOverlay.visible = false
    m.videoInfoOverlay.showOverlay = false
    hideGuideElements()
    content = createObject("roSGNode", "ContentNode")
    content.url = channel.url
    content.streamFormat = "hls"
    content.addField("preferredBitrate", "integer", false)
    content.preferredBitrate = 0
    content.addField("maxBandwidth", "integer", false)
    content.maxBandwidth = 0

    print "Playing channel: " + content.url

    m.videoPlayer.content = content
    m.videoPlayer.control = "play"
    m.videoPlayer.maxVideoDecodeResolution = "1920x1080"
    m.videoPlayer.enableTrickPlay = false
    m.videoPlayer.setFocus(true)

    ' Update overlay data
    updateVideoOverlay()
end sub

sub updateVideoOverlay()
    if m.currentChannelIndex < 0 or m.currentChannelIndex >= m.epgData.channels.count() then return

    channel = m.epgData.channels[m.currentChannelIndex]
    now = CreateObject("roDateTime").AsSeconds()

    overlayData = {
        channelNumber: m.currentChannelIndex + 1
        logo: channel.logo
        title: channel.title
        nowPlaying: ""
        programDetails: ""
    }

    if channel.tvgId <> invalid
        currentProgram = EPGGetCurrentProgram(m.epgData, channel.tvgId)
        if currentProgram <> ""
            overlayData.nowPlaying = currentProgram
        else
            overlayData.nowPlaying = channel.title
        end if

        programs = EPGGetPrograms(m.epgData, channel.tvgId)
        if programs.count() > 0
            for each prog in programs
                if prog.startTime <= now and prog.endTime > now
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
        overlayData.nowPlaying = channel.title
    end if

    m.videoInfoOverlay.channelData = overlayData
end sub

sub onVideoStateChanged()
    state = m.videoPlayer.state
    errorCode = m.videoPlayer.errorCode
    hasError = (errorCode <> invalid and errorCode <> 0)
    
    if state = "error" or hasError
        if m.retryAttempts < m.maxRetryAttempts and m.currentChannelIndex >= 0
            m.retryAttempts = m.retryAttempts + 1
            m.loadingLabel.text = "Server full, retrying... (" + Stri(m.retryAttempts) + "/" + Stri(m.maxRetryAttempts) + ")"
            m.loadingLabel.visible = true
            m.videoPlayer.control = "stop"
            m.retryTimer.duration = m.retryDelay
            m.retryTimer.control = "start"
        else
            m.loadingLabel.text = "Unable to connect - Server full"
            m.loadingLabel.visible = true
            m.videoPlayer.control = "stop"
            m.videoPlayer.visible = false
            ' Reuse timer
            m.retryTimer.duration = 3
            m.retryTimer.unobserveFieldScoped("fire")
            m.retryTimer.observeFieldScoped("fire", "returnToGuide")
            m.retryTimer.control = "start"
        end if
        return
    end if
    
    if state = "finished" or state = "stopped"
        m.videoPlayer.control = "stop"
        m.videoPlayer.visible = false
        loadPlaylist()
    end if
    
    if state = "playing"
        m.retryAttempts = 0
        m.loadingLabel.visible = false
        if m.bufferingTimer <> invalid
            m.bufferingTimer.control = "stop"
        end if
        if m.positionCheckTimer = invalid
            m.lastPosition = m.videoPlayer.position
            m.positionCheckTimer.control = "start"
        end if
    end if
    
    if state = "buffering"
        m.bufferingTimer.control = "start"
    end if
end sub

sub onBufferingTimeout()
    if m.videoPlayer.state = "buffering"
        m.videoPlayer.control = "stop"
        m.videoPlayer.visible = false
        if m.retryAttempts < m.maxRetryAttempts and m.currentChannelIndex >= 0
            m.retryAttempts = m.retryAttempts + 1
            m.loadingLabel.text = "Timeout, retrying... (" + Stri(m.retryAttempts) + "/" + Stri(m.maxRetryAttempts) + ")"
            m.loadingLabel.visible = true
            m.retryTimer.duration = m.retryDelay
            m.retryTimer.control = "start"
        else
            m.loadingLabel.text = "Connection timeout"
            m.loadingLabel.visible = true
            ' Reuse timer
            m.retryTimer.duration = 3
            m.retryTimer.unobserveFieldScoped("fire")
            m.retryTimer.observeFieldScoped("fire", "returnToGuide")
            m.retryTimer.control = "start"
        end if
    end if
end sub

sub onPositionCheck()
    currentPosition = m.videoPlayer.position
    if currentPosition = m.lastPosition or currentPosition < 1
        m.videoPlayer.control = "stop"
        m.videoPlayer.visible = false
        if m.retryAttempts < m.maxRetryAttempts and m.currentChannelIndex >= 0
            m.retryAttempts = m.retryAttempts + 1
            m.loadingLabel.text = "Server full, retrying... (" + Stri(m.retryAttempts) + "/" + Stri(m.maxRetryAttempts) + ")"
            m.loadingLabel.visible = true
            m.retryTimer.duration = m.retryDelay
            m.retryTimer.control = "start"
        else
            m.loadingLabel.text = "Unable to connect"
            m.loadingLabel.visible = true
            ' Reuse timer
            m.retryTimer.duration = 3
            m.retryTimer.unobserveFieldScoped("fire")
            m.retryTimer.observeFieldScoped("fire", "returnToGuide")
            m.retryTimer.control = "start"
        end if
    end if
end sub

sub onRetryTimer()
    if m.currentChannelIndex >= 0 and m.currentChannelIndex < m.epgData.channels.count()
        channel = m.epgData.channels[m.currentChannelIndex]
        playChannel(channel)
    end if
end sub

sub returnToGuide()
    m.loadingLabel.visible = false
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
        }
        
        if channel.tvgId <> invalid
            currentProgram = EPGGetCurrentProgram(m.epgData, channel.tvgId)
            if currentProgram <> ""
                channelData.nowPlaying = currentProgram
            else
                channelData.nowPlaying = channel.title
            end if
            
            programs = EPGGetPrograms(m.epgData, channel.tvgId)
            if programs.count() > 0
                now = CreateObject("roDateTime").AsSeconds()
                for each prog in programs
                    if prog.startTime <= now and prog.endTime > now
                        isSportsProgram = IsSportsProgram(prog.title, m.sportsKeywords)
                        channelData.isSports = isSportsProgram
                        
                        if isSportsProgram and prog.subTitle <> invalid and prog.subTitle <> ""
                            channelData.programDetails = prog.subTitle
                        else if prog.description <> invalid and prog.description <> ""
                            channelData.programDetails = prog.description
                        end if
                        exit for
                    end if
                end for
            end if
        else
            channelData.nowPlaying = channel.title
        end if
        
        channelsWithInfo.push(channelData)
    end for
    
    m.channelMenu.currentChannelIndex = m.currentChannelIndex
    m.channelMenu.initialChannelIndex = m.currentChannelIndex
    m.channelMenu.epgData = m.epgData
    m.channelMenu.channels = channelsWithInfo
    m.channelMenu.visible = true
    m.channelMenu.setFocus(true)
end sub

function onKeyEvent(key as String, press as Boolean) as Boolean
    dt = CreateObject("roDateTime")
    currentTime = dt.AsSeconds()
    currentTimeMs = (currentTime * 1000) + dt.GetMilliseconds()

    ' Let multiview handle its own keys
    if m.isMultiviewMode
        return false
    end if

    if m.channelMenu.visible
        if (key = "back" or key = "left") and press
            m.channelMenu.visible = false
            ' Give focus back to video player
            m.videoPlayer.setFocus(true)
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
            m.rightButtonPressTime = currentTimeMs
            showChannelMenu()
            return true
        end if
        if key = "back" and m.videoPlayer.visible
            ' Back button from full screen video - return to guide
            m.isBackgroundPlayback = true
            m.videoPlayer.opacity = 1.0
            m.videoPlayer.visible = true
            m.videoOverlay.visible = true
            m.videoInfoOverlay.showOverlay = false
            showGuideElements()
            loadPlaylist()
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

function CreateEPGData() as Object
    epgData = {
        channels: []
        schedules: {}
        programsByChannel: {}
        lastUpdate: 0
        updateInterval: 300
        isLoading: false
        pendingTasks: 0
        playlistData: invalid
        epgData: invalid
        logoFallbackData: invalid
        playlistTask: invalid
        epgTask: invalid
        logoTask: invalid
    }
    return epgData
end function

function EPGNeedsUpdate(epg as Object) as Boolean
    if epg.lastUpdate = 0 then return true
    currentTime = CreateObject("roDateTime").AsSeconds()
    elapsed = currentTime - epg.lastUpdate
    return (elapsed >= epg.updateInterval)
end function

function EPGParsePlaylist(content as String) as Object
    channels = []
    content = content.Replace(chr(13), "").Replace(chr(10)+chr(10), chr(10))
    lines = content.Split(chr(10))
    current = invalid
    
    for each line in lines
        line = line.Trim()
        if line = "" then continue for
        
        if line.StartsWith("#EXTINF:")
            if current <> invalid and current.url <> invalid
                channels.push(current)
            end if
            current = {}
            
            tvgIdPos = line.Instr("tvg-id=")
            if tvgIdPos > 0
                tvgIdStart = tvgIdPos + 8
                tvgIdEnd = line.Instr(tvgIdStart, chr(34))
                if tvgIdEnd > tvgIdStart
                    current.tvgId = line.Mid(tvgIdStart, tvgIdEnd - tvgIdStart)
                end if
            end if
            
            tvgNamePos = line.Instr("tvg-name=")
            if tvgNamePos > 0
                tvgNameStart = tvgNamePos + 10
                tvgNameEnd = line.Instr(tvgNameStart, chr(34))
                if tvgNameEnd > tvgNameStart
                    current.title = line.Mid(tvgNameStart, tvgNameEnd - tvgNameStart).Trim()
                end if
            end if
            
            if current.title = invalid or current.title = ""
                parts = line.Split(",")
                if parts.count() > 1
                    current.title = parts[parts.count() - 1].Trim()
                end if
            end if
            
            logoPos = line.Instr("tvg-logo=")
            if logoPos > 0
                logoStart = logoPos + 10
                logoEnd = line.Instr(logoStart, chr(34))
                if logoEnd > logoStart
                    current.logo = line.Mid(logoStart, logoEnd - logoStart)
                end if
            end if
            
        else if not line.StartsWith("#") and current <> invalid
            if line.EndsWith("/sd")
                current.url = Left(line, Len(line) - 2) + "hd"
            else
                current.url = line
            end if
        end if
    end for
    
    if current <> invalid and current.url <> invalid
        channels.push(current)
    end if
    
    return channels
end function

' Parse XML more efficiently by filtering early
function EPGParseXMLOptimized(xmlString as String) as Object
    result = {
        schedules: {}
        programsByChannel: {}
    }
    
    if xmlString = invalid or xmlString = "" then return result
    
    xml = CreateObject("roXMLElement")
    if not xml.Parse(xmlString) then return result
    
    now = CreateObject("roDateTime")
    currentTime = now.AsSeconds()
    windowStart = currentTime - 7200
    windowEnd = currentTime + 7200
    
    programmes = xml.GetNamedElements("programme")
    if programmes.count() = 0 then return result
    
    for each programme in programmes
        ' Quick time check first before parsing
        startTime = programme@start
        stopTime = programme@stop
        
        if startTime = invalid or stopTime = invalid then continue for

        startSec = EPGParseXmltvTime(startTime)
        stopSec = EPGParseXmltvTime(stopTime)
        
        ' Skip if completely outside time window (include programs from 2 hours in the past)
        if startSec > windowEnd or stopSec < windowStart then continue for
        
        ' NOW parse remaining fields
        channel = programme@channel
        if channel = invalid then continue for
        
        normalizedChannel = EPGNormalizeChannelId(channel)
        
        titleNode = programme.GetNamedElements("title")
        if titleNode.Count() = 0 then continue for
        
        programTitle = titleNode[0].GetText()
        
        programDesc = ""
        descNode = programme.GetNamedElements("desc")
        if descNode.Count() > 0
            programDesc = descNode[0].GetText()
        end if
        
        programSubTitle = ""
        subTitleNode = programme.GetNamedElements("sub-title")
        if subTitleNode.Count() > 0
            programSubTitle = subTitleNode[0].GetText()
        end if
        
        if programTitle = "Movie" and programSubTitle <> ""
            programTitle = programSubTitle
        end if
        
        if startSec <= currentTime and stopSec > currentTime
            result.schedules[normalizedChannel] = programTitle
        end if
        
        if not result.programsByChannel.doesExist(normalizedChannel)
            result.programsByChannel[normalizedChannel] = []
        end if
        
        programInfo = {
            title: programTitle
            description: programDesc
            subTitle: programSubTitle
            startTime: startSec
            endTime: stopSec
        }
        result.programsByChannel[normalizedChannel].push(programInfo)
    end for
    
    return result
end function

sub EPGEnrichWithLogosFast(channels as Object, fallbackData as Object, logoUrls as Object, networkPatterns as Object)
    fallbackMap = {}
    
    if fallbackData <> invalid
        for each ch in fallbackData
            if ch.tvgId <> invalid and ch.logo <> invalid
                fallbackMap[ch.tvgId] = ch.logo
            end if
        end for
    end if
    
    for each channel in channels
        if channel.logo <> invalid and channel.logo <> "" then continue for
        
        if channel.tvgId <> invalid and fallbackMap.doesExist(channel.tvgId)
            channel.logo = fallbackMap[channel.tvgId]
            continue for
        end if
        
        channel.logo = EPGGenerateLogoUrlFast(channel.title, logoUrls, networkPatterns)
    end for
end sub

function EPGGenerateLogoUrlFast(title as String, logoUrls as Object, networkPatterns as Object) as String
    if title = invalid or title = "" then return ""
    networkLogo = EPGGetNetworkLogoFast(title, logoUrls, networkPatterns)
    return networkLogo
end function

function EPGGetNetworkLogoFast(title as String, logoUrls as Object, networkPatterns as Object) as String
    baseUrl = logoUrls.TV_LOGOS_BASE
    networkName = title.Trim()
    parenPos = networkName.Instr("(")
    if parenPos > 0
        networkName = networkName.Left(parenPos - 1).Trim()
    end if

    for each key in networkPatterns
        if networkName.StartsWith(UCase(key))
            openParen = title.Instr("(")
            closeParen = title.Instr(")")
            if openParen > 0 and closeParen > openParen
                callLetters = LCase(title.Mid(openParen + 1, closeParen - openParen - 1))
                return logoUrls.TV_LOGOS_LOCAL + networkPatterns[key] + callLetters + "-us.png"
            end if
        end if
    end for
    
    ' Chain multiple replacements
    networkName = networkName.Replace(" New York", "").Replace(" Los Angeles", "").Replace(" Chicago", "").Replace(", LA", "").Replace(", NY", "").Replace(", CA", "").Trim()
    
    if networkName = "" then return ""

    normalized = networkName.Replace("&", "-and-").Replace(" ", "-").Replace("'", "").Replace(",", "")
    normalized = LCase(normalized)
    
    ' Clean up double dashes
    keepCleaning = true
    while keepCleaning
        if normalized.Instr("--") > 0
            normalized = normalized.Replace("--", "-")
        else
            keepCleaning = false
        end if
    end while
    
    ' Trim leading numbers/dashes
    keepTrimming = true
    while keepTrimming and normalized.Len() > 0
        firstChar = normalized.Left(1)
        if firstChar = "-" or (firstChar >= "0" and firstChar <= "9")
            normalized = normalized.Mid(1)
        else
            keepTrimming = false
        end if
    end while
    
    ' Trim trailing dashes
    keepTrimming = true
    while keepTrimming and normalized.Len() > 0
        if normalized.Right(1) = "-"
            normalized = normalized.Left(normalized.Len() - 1)
        else
            keepTrimming = false
        end if
    end while
    
    if normalized = "" then return ""
    
    return baseUrl + normalized + "-us.png"
end function

function EPGParseXmltvTime(xmltvTime as String) as LongInteger
    if xmltvTime.Len() < 14 then return 0
    
    year = val(xmltvTime.Mid(0, 4))
    month = val(xmltvTime.Mid(4, 2))
    day = val(xmltvTime.Mid(6, 2))
    hour = val(xmltvTime.Mid(8, 2))
    minute = val(xmltvTime.Mid(10, 2))
    second = val(xmltvTime.Mid(12, 2))
    
    tzStr = "Z"
    if xmltvTime.Len() >= 19
        tzPart = xmltvTime.Mid(14)
        firstChar = tzPart.Left(1)
        if firstChar = "+" or firstChar = "-"
            if tzPart.Len() >= 5
                tzStr = tzPart.Mid(0, 3) + ":" + tzPart.Mid(3, 2)
            end if
        end if
    end if
    
    iso8601 = stri(year).Trim() + "-"
    iso8601 = iso8601 + right("0" + stri(month).Trim(), 2) + "-"
    iso8601 = iso8601 + right("0" + stri(day).Trim(), 2) + "T"
    iso8601 = iso8601 + right("0" + stri(hour).Trim(), 2) + ":"
    iso8601 = iso8601 + right("0" + stri(minute).Trim(), 2) + ":"
    iso8601 = iso8601 + right("0" + stri(second).Trim(), 2) + tzStr
    
    dt = CreateObject("roDateTime")
    dt.FromISO8601String(iso8601)
    return dt.AsSeconds()
end function

function EPGGetCurrentProgram(epg as Object, tvgId as String) as String
    if tvgId = invalid then return ""
    
    normalizedId = EPGNormalizeChannelId(tvgId)
    
    if epg.schedules.doesExist(normalizedId)
        return epg.schedules[normalizedId]
    end if
    
    return ""
end function

function GetNowPlayingForChannel(channel as Object, now as Integer) as String
    if channel.tvgId = invalid then return channel.title

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