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
    
    ' Initialize UI colors
    m.uiColors = GetUIColors()
    
    ' Initialize EPG data with forced refresh on startup
    m.epgData = CreateEPGData()
    m.epgData.lastUpdate = 0  ' Force refresh on first load
    
    ' Track state
    m.isBackgroundPlayback = false
    m.currentChannelIndex = -1
    m.lastChannelIndex = 0
    m.isMultiviewMode = false
    
    ' Long press detection
    m.longPressThreshold = 500
    m.leftButtonPressTime = 0
    m.rightButtonPressTime = 0
    m.isLongPressing = false
    
    ' Retry logic
    m.retryAttempts = 0
    m.maxRetryAttempts = 10
    m.retryDelay = 2
    m.bufferingTimer = invalid
    m.positionCheckTimer = invalid
    m.lastPosition = 0

    ' Observe events
    m.channelList.observeField("itemSelected", "onChannelSelected")
    m.channelList.observeField("itemFocused", "onChannelFocused")
    m.videoPlayer.observeField("state", "onVideoStateChanged")
    m.channelMenu.observeField("selectedChannel", "onMenuChannelSelected")
    m.channelMenu.observeField("launchMultiview", "onLaunchMultiview")
    m.multiviewGrid.observeField("visible", "onPiPVisibleChanged")

    ' Start clock update timer
    m.clockTimer = createObject("roSGNode", "Timer")
    m.clockTimer.repeat = true
    m.clockTimer.duration = 60
    m.clockTimer.observeField("fire", "updateClock")
    m.clockTimer.control = "start"
    
    ' Retry timer
    m.retryTimer = createObject("roSGNode", "Timer")
    m.retryTimer.repeat = false
    m.retryTimer.observeField("fire", "onRetryTimer")
    
    ' App lifecycle observer to clear cache on exit
    m.top.observeField("focusedChild", "onFocusChanged")
    
    updateClock()
    loadPlaylist()
end sub

sub onFocusChanged()
    ' Clear EPG cache when app loses focus
    if m.top.focusedChild = invalid then
        if m.epgData <> invalid then
            m.epgData.lastUpdate = 0
        end if
    end if
end sub

sub onLaunchMultiview()
    selectedChannels = m.channelMenu.launchMultiview
    print "MainScene: onLaunchMultiview called"
    print "MainScene: selectedChannels = "; selectedChannels

    if selectedChannels = invalid or selectedChannels.count() = 0 then
        print "MainScene: No channels selected or invalid"
        return
    end if

    print "MainScene: Building PiP view with " + str(selectedChannels.count()) + " channels"

    pipChannels = []
    now = CreateObject("roDateTime").AsSeconds()

    for each channelIdx in selectedChannels
        if channelIdx >= 0 and channelIdx < m.epgData.channels.count() then
            channel = m.epgData.channels[channelIdx]
            print "MainScene: Adding channel " + str(channelIdx) + ": " + channel.title

            pipChannel = {
                title: channel.title,
                url: channel.url,
                logo: channel.logo,
                tvgId: channel.tvgId,
                nowPlaying: ""
            }

            pipChannel.nowPlaying = GetNowPlayingForChannel(channel, now)
            pipChannels.push(pipChannel)
        end if
    end for

    if pipChannels.count() = 0 then
        print "MainScene: No valid channels to show in PiP"
        return
    end if

    print "MainScene: Starting PiP view with " + str(pipChannels.count()) + " channels"

    m.videoPlayer.visible = false
    m.videoPlayer.control = "stop"
    hideGuideElements()

    m.isMultiviewMode = true
    m.multiviewGrid.visible = true
    m.multiviewGrid.channels = pipChannels
    m.multiviewGrid.setFocus(true)
end sub

sub onPiPVisibleChanged()
    ' When PiP is hidden, exit multiview mode
    if not m.multiviewGrid.visible and m.isMultiviewMode then
        print "MainScene: PiP hidden, exiting multiview mode"
        m.isMultiviewMode = false
        loadPlaylist()
    end if
end sub

sub updateClock()
    now = CreateObject("roDateTime")
    now.ToLocalTime()
    hour = now.GetHours()
    minute = now.GetMinutes()
    ampm = "am"
    
    if hour >= 12 then
        ampm = "pm"
        if hour > 12 then
            hour = hour - 12
        end if
    end if
    if hour = 0 then hour = 12
    
    timeStr = str(hour) + ":" + right("0" + str(minute), 2) + " " + ampm
    m.currentTimeLabel.text = timeStr
end sub

sub loadPlaylist()
    if not EPGNeedsUpdate(m.epgData)
        print "EPG data is fresh, using cache"
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
    apiUrls = GetTVPassUrls()
    
    ' Load main playlist
    m.epgData.playlistTask = createObject("roSGNode", "LoadPlaylistTask")
    m.epgData.playlistTask.url = apiUrls.TVPASS_PLAYLIST + "?t=" + timestamp
    m.epgData.playlistTask.observeField("response", "onTvpassPlaylistResponse")
    m.epgData.playlistTask.observeField("error", "onPlaylistError")
    m.epgData.playlistTask.control = "RUN"
    
    ' Load EPG XML
    m.epgData.epgTask = createObject("roSGNode", "LoadScheduleTask")
    m.epgData.epgTask.url = apiUrls.TVPASS_EPG + "?t=" + timestamp
    m.epgData.epgTask.observeField("response", "onScheduleResponse")
    m.epgData.epgTask.observeField("error", "onScheduleError")
    m.epgData.epgTask.control = "RUN"
    
    ' Load logo fallback
    m.epgData.logoTask = createObject("roSGNode", "LoadPlaylistTask")
    m.epgData.logoTask.url = apiUrls.TVPASS_HD_FALLBACK + "?t=" + timestamp
    m.epgData.logoTask.observeField("response", "onLogoPlaylistResponse")
    m.epgData.logoTask.observeField("error", "onLogoPlaylistError")
    m.epgData.logoTask.control = "RUN"
end sub

sub onTvpassPlaylistResponse()
    m.epgData.playlistData = EPGParsePlaylist(m.epgData.playlistTask.response)
    print "Parsed " + str(m.epgData.playlistData.count()) + " channels from main playlist"
    m.epgData.playlistTask = invalid
    checkPlaylistsComplete()
end sub

sub onLogoPlaylistResponse()
    m.epgData.logoFallbackData = EPGParsePlaylist(m.epgData.logoTask.response)
    print "Parsed " + str(m.epgData.logoFallbackData.count()) + " fallback logos"
    m.epgData.logoTask = invalid
    checkPlaylistsComplete()
end sub

sub onLogoPlaylistError()
    print "Logo fallback load failed (non-critical)"
    m.epgData.logoTask = invalid
    checkPlaylistsComplete()
end sub

sub onScheduleResponse()
    if m.epgData.epgTask.response = invalid or m.epgData.epgTask.response = ""
        print "onScheduleResponse: Empty EPG response received"
        m.epgData.schedules = {}
        m.epgData.programsByChannel = {}
    else
        print "onScheduleResponse: Processing " + str(len(m.epgData.epgTask.response)) + " bytes of EPG data"
        epgResult = EPGParseXML(m.epgData.epgTask.response)
        m.epgData.schedules = epgResult.schedules
        m.epgData.programsByChannel = epgResult.programsByChannel
        print "Parsed EPG for " + str(m.epgData.schedules.count()) + " scheduled channels and " + str(m.epgData.programsByChannel.count()) + " program channels"
    end if
    m.epgData.epgTask = invalid
    checkPlaylistsComplete()
end sub

sub onScheduleError()
    print "EPG load failed, continuing without schedule data"
    m.epgData.schedules = {}
    m.epgData.programsByChannel = {}
    m.epgData.epgTask = invalid
    checkPlaylistsComplete()
end sub

sub onPlaylistError()
    print "Main playlist load failed"
    m.epgData.playlistTask = invalid
    m.epgData.isLoading = false
    showError("Failed to load channel list")
end sub

sub checkPlaylistsComplete()
    m.epgData.pendingTasks = m.epgData.pendingTasks - 1
    if m.epgData.pendingTasks = 0
        ' Enrich channels with logos
        EPGEnrichWithLogos(m.epgData.playlistData, m.epgData.logoFallbackData)
        m.epgData.channels = m.epgData.playlistData
        m.epgData.isLoading = false
        m.epgData.lastUpdate = CreateObject("roDateTime").AsSeconds()
        
        if m.epgData.channels.count() > 0
            showGuide()
        else
            showError("No channels found")
        end if
    end if
end sub

sub createTimeSlotHeaders()
    m.timeSlotHeaders.removeChildrenIndex(m.timeSlotHeaders.getChildCount(), 0)
    now = CreateObject("roDateTime")
    currentTime = now.AsSeconds()
    roundedTime = int(currentTime / 1800) * 1800
    slotWidth = 517
    
    for i = 0 to 2
        slotTime = roundedTime + (i * 1800)
        slotDateTime = CreateObject("roDateTime")
        slotDateTime.FromSeconds(slotTime)
        slotDateTime.ToLocalTime()
        hours = slotDateTime.GetHours()
        minutes = slotDateTime.GetMinutes()
        displayHour = hours
        ampm = "am"
        if hours >= 12
            ampm = "pm"
            if hours > 12
                displayHour = hours - 12
            end if
        end if
        if displayHour = 0 then displayHour = 12
        minutesStr = StrI(minutes).Trim()
        if minutes < 10 then minutesStr = "0" + minutesStr
        hourStr = StrI(displayHour).Trim()
        timeStr = hourStr + ":" + minutesStr + " " + ampm
        
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
            item.title = "Ch " + str(i + 1)
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
    m.guideBackground.visible = true
    m.headerBackground.visible = true
    m.featuredLogo.visible = true
    m.featuredTitle.visible = true
    m.featuredTime.visible = true
    m.featuredDescription.visible = true
    m.currentTimeLabel.visible = true
    m.guideHeaderLabel.visible = true
    m.allChannelsLabel.visible = true
    m.timeSlotHeaders.visible = true
    m.channelList.visible = true
end sub

sub hideGuideElements()
    m.guideBackground.visible = false
    m.headerBackground.visible = false
    m.featuredLogo.visible = false
    m.featuredTitle.visible = false
    m.featuredTime.visible = false
    m.featuredDescription.visible = false
    m.currentTimeLabel.visible = false
    m.guideHeaderLabel.visible = false
    m.allChannelsLabel.visible = false
    m.timeSlotHeaders.visible = false
    m.channelList.visible = false
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
            print "Playing channel: " + channel.title
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
        print "Playing channel from menu: " + channel.title
        m.channelMenu.visible = false
        playChannel(channel)
        m.isBackgroundPlayback = false
    end if
end sub

sub playChannel(channel as Object)
    m.videoPlayer.opacity = 1.0
    m.videoPlayer.visible = true
    m.videoOverlay.visible = false
    hideGuideElements()
    content = createObject("roSGNode", "ContentNode")
    content.url = channel.url
    content.streamFormat = "hls"

    ' Force HD quality settings
    content.addField("preferredBitrate", "integer", false)
    content.preferredBitrate = 0  ' 0 = highest available
    content.addField("maxBandwidth", "integer", false)
    content.maxBandwidth = 0  ' 0 = no limit

    m.videoPlayer.content = content
    m.videoPlayer.control = "play"

    ' Set video player to prefer highest quality
    m.videoPlayer.maxVideoDecodeResolution = "1920x1080"

    m.videoPlayer.enableTrickPlay = false
    m.top.setFocus(true)
end sub

sub onVideoStateChanged()
    state = m.videoPlayer.state
    print "Video state: " + state
    errorCode = m.videoPlayer.errorCode
    if errorCode <> invalid and errorCode <> 0
        print "Error code: " + str(errorCode)
    end if
    
    hasError = (errorCode <> invalid and errorCode <> 0)
    
    if state = "error" or hasError
        if m.retryAttempts < m.maxRetryAttempts and m.currentChannelIndex >= 0
            m.retryAttempts = m.retryAttempts + 1
            print "Retry " + str(m.retryAttempts) + "/" + str(m.maxRetryAttempts)
            m.loadingLabel.text = "Server full, retrying... (" + str(m.retryAttempts) + "/" + str(m.maxRetryAttempts) + ")"
            m.loadingLabel.visible = true
            m.videoPlayer.control = "stop"
            m.retryTimer.duration = m.retryDelay
            m.retryTimer.control = "start"
        else
            m.loadingLabel.text = "Unable to connect - Server full"
            m.loadingLabel.visible = true
            m.videoPlayer.control = "stop"
            m.videoPlayer.visible = false
            returnTimer = createObject("roSGNode", "Timer")
            returnTimer.duration = 3
            returnTimer.repeat = false
            returnTimer.observeField("fire", "returnToGuide")
            returnTimer.control = "start"
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
            m.bufferingTimer = invalid
        end if
        if m.positionCheckTimer = invalid or not m.positionCheckTimer.isSubtype("Timer")
            m.positionCheckTimer = m.top.createChild("Timer")
            m.positionCheckTimer.duration = 3
            m.positionCheckTimer.repeat = false
            m.positionCheckTimer.observeField("fire", "onPositionCheck")
            m.lastPosition = m.videoPlayer.position
        end if
        m.positionCheckTimer.control = "start"
    end if
    
    if state = "buffering"
        if m.bufferingTimer = invalid or not m.bufferingTimer.isSubtype("Timer")
            m.bufferingTimer = m.top.createChild("Timer")
            m.bufferingTimer.duration = 10
            m.bufferingTimer.repeat = false
            m.bufferingTimer.observeField("fire", "onBufferingTimeout")
        end if
        m.bufferingTimer.control = "start"
    end if
end sub

sub onBufferingTimeout()
    if m.videoPlayer.state = "buffering"
        print "Buffering timeout"
        m.videoPlayer.control = "stop"
        m.videoPlayer.visible = false
        if m.retryAttempts < m.maxRetryAttempts and m.currentChannelIndex >= 0
            m.retryAttempts = m.retryAttempts + 1
            m.loadingLabel.text = "Timeout, retrying... (" + str(m.retryAttempts) + "/" + str(m.maxRetryAttempts) + ")"
            m.loadingLabel.visible = true
            m.retryTimer.duration = m.retryDelay
            m.retryTimer.control = "start"
        else
            m.loadingLabel.text = "Connection timeout"
            m.loadingLabel.visible = true
            returnTimer = createObject("roSGNode", "Timer")
            returnTimer.duration = 3
            returnTimer.repeat = false
            returnTimer.observeField("fire", "returnToGuide")
            returnTimer.control = "start"
        end if
    end if
    m.bufferingTimer = invalid
end sub

sub onPositionCheck()
    currentPosition = m.videoPlayer.position
    if currentPosition = m.lastPosition or currentPosition < 1
        print "Video not progressing"
        m.videoPlayer.control = "stop"
        m.videoPlayer.visible = false
        if m.retryAttempts < m.maxRetryAttempts and m.currentChannelIndex >= 0
            m.retryAttempts = m.retryAttempts + 1
            m.loadingLabel.text = "Server full, retrying... (" + str(m.retryAttempts) + "/" + str(m.maxRetryAttempts) + ")"
            m.loadingLabel.visible = true
            m.retryTimer.duration = m.retryDelay
            m.retryTimer.control = "start"
        else
            m.loadingLabel.text = "Unable to connect"
            m.loadingLabel.visible = true
            returnTimer = m.top.createChild("Timer")
            returnTimer.duration = 3
            returnTimer.repeat = false
            returnTimer.observeField("fire", "returnToGuide")
            returnTimer.control = "start"
        end if
    end if
    m.positionCheckTimer = invalid
end sub

sub onRetryTimer()
    print "Retrying playback"
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
    print "Error: " + msg
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
        }
        
        ' Get current program info
        if channel.tvgId <> invalid
            currentProgram = EPGGetCurrentProgram(m.epgData, channel.tvgId)
            if currentProgram <> ""
                channelData.nowPlaying = currentProgram
            else
                channelData.nowPlaying = channel.title
            end if
            
            ' Get program details (episode info)
            programs = EPGGetPrograms(m.epgData, channel.tvgId)
            if programs.count() > 0
                ' Find current program for details
                now = CreateObject("roDateTime").AsSeconds()
                for each prog in programs
                    if prog.startTime <= now and prog.endTime > now
                        ' Check if this is a sports program by looking at the title
                        programTitle = prog.title
                        isSportsProgram = false
                        
                        ' List of sports program titles to check
                        sportsKeywords = ["College Basketball", "College Football", "College Baseball", "NFL Football", "NBA Basketball", "NBA G League Basketball", "MLB Baseball", "NHL Hockey"]
                        
                        for each keyword in sportsKeywords
                            if programTitle.Instr(keyword) >= 0
                                isSportsProgram = true
                                exit for
                            end if
                        end for
                        
                        ' Use sub-title for sports, description for others
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
    m.channelMenu.initialChannelIndex = m.currentChannelIndex  ' Add this to track the initially playing channel
    m.channelMenu.channels = channelsWithInfo
    m.channelMenu.visible = true
    m.channelMenu.setFocus(true)
end sub

function onKeyEvent(key as String, press as Boolean) as Boolean
    dt = CreateObject("roDateTime")
    currentTime& = dt.AsSeconds()
    currentTimeMs& = (currentTime& * 1000) + dt.GetMilliseconds()

    ' Handle multiview mode (PiP)
    if m.isMultiviewMode
        ' Let the PiP component handle ALL keys
        return false
    end if

    if m.channelMenu.visible
        if (key = "back" or key = "left") and press
            m.channelMenu.visible = false
            m.top.setFocus(true)
            return true
        end if
        return false
    end if
    
    if press
        if key = "left" and m.videoPlayer.visible
            m.leftButtonPressTime = currentTimeMs&
            return true
        end if
        if key = "right" and m.videoPlayer.visible
            m.rightButtonPressTime = currentTimeMs&
            return true
        end if
        if (key = "up" or key = "down") and m.videoPlayer.visible
            showChannelMenu()
            return true
        end if
        if key = "back" and m.videoPlayer.visible
            m.isBackgroundPlayback = true
            m.videoPlayer.opacity = 1.0
            m.videoPlayer.visible = true
            m.videoOverlay.visible = true
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
            duration = currentTimeMs& - m.leftButtonPressTime
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
            duration = currentTimeMs& - m.rightButtonPressTime
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
        if newPos < 0
            newPos = 0
        end if
        m.videoPlayer.seek = newPos
    end if
end sub

sub seekForward()
    if m.videoPlayer.content <> invalid
        newPos = m.videoPlayer.position + 10
        dur = m.videoPlayer.duration
        if dur > 0 and newPos > dur
            newPos = dur
        end if
        m.videoPlayer.seek = newPos
    end if
end sub

' ============================================================================
' EPG DATA FUNCTIONS
' ============================================================================

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
    if epg.lastUpdate = 0
        return true
    end if

    currentTime = CreateObject("roDateTime").AsSeconds()
    elapsed = currentTime - epg.lastUpdate
    if elapsed >= epg.updateInterval
        return true
    end if

    return false
end function

function EPGParsePlaylist(content as String) as Object
    channels = []
    content = content.Replace(chr(13), "")
    content = content.Replace(chr(10)+chr(10), chr(10))
    lines = content.Split(chr(10))
    current = invalid
    
    for each line in lines
        line = line.Trim()
        if line = ""
            goto nextLine
        end if
        
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
        
        nextLine:
    end for
    
    if current <> invalid and current.url <> invalid
        channels.push(current)
    end if
    
    return channels
end function

function EPGParseXML(xmlString as String) as Object
    result = {}
    result.schedules = {}
    result.programsByChannel = {}
    
    if xmlString = invalid or xmlString = ""
        print "EPGParseXML: Empty XML string received"
        return result
    end if
    
    print "EPGParseXML: Parsing " + str(len(xmlString)) + " bytes"
    
    xml = CreateObject("roXMLElement")
    parseSuccess = xml.Parse(xmlString)
    if not parseSuccess
        print "EPGParseXML: XML parse failed"
        return result
    end if
    
    now = CreateObject("roDateTime")
    currentTime = now.AsSeconds()
    programmes = xml.GetNamedElements("programme")
    
    print "EPGParseXML: Found " + str(programmes.count()) + " programme elements"
    
    if programmes.count() = 0
        print "EPGParseXML: No programmes found in XML"
        return result
    end if
    
    for each programme in programmes
        channel = programme@channel
        startTime = programme@start
        stopTime = programme@stop
        
        if channel = invalid or startTime = invalid or stopTime = invalid
            goto nextProg
        end if
        
        normalizedChannel = EPGNormalizeChannelId(channel)
        startSec = EPGParseXmltvTime(startTime)
        stopSec = EPGParseXmltvTime(stopTime)
        
        if startSec > (currentTime + 7200) or stopSec < currentTime
            goto nextProg
        end if
        
        titleNode = programme.GetNamedElements("title")
        if titleNode.Count() = 0
            goto nextProg
        end if
        
        programTitle = titleNode[0].GetText()
        
        programDesc = ""
        descNode = programme.GetNamedElements("desc")
        if descNode.Count() > 0
            programDesc = descNode[0].GetText()
        end if
        
        ' Capture sub-title
        programSubTitle = ""
        subTitleNode = programme.GetNamedElements("sub-title")
        if subTitleNode.Count() > 0
            programSubTitle = subTitleNode[0].GetText()
        end if
        
        ' Handle Movie special case
        if programTitle = "Movie" and programSubTitle <> ""
            programTitle = programSubTitle
        end if
        
        if startSec <= currentTime and stopSec > currentTime
            result.schedules[normalizedChannel] = programTitle
        end if
        
        if not result.programsByChannel.doesExist(normalizedChannel)
            result.programsByChannel[normalizedChannel] = []
        end if
        
        programInfo = {}
        programInfo.title = programTitle
        programInfo.description = programDesc
        programInfo.subTitle = programSubTitle
        programInfo.startTime = startSec
        programInfo.endTime = stopSec
        result.programsByChannel[normalizedChannel].push(programInfo)
        
        nextProg:
    end for
    
    return result
end function

sub EPGEnrichWithLogos(channels as Object, fallbackData as Object)
    fallbackMap = {}
    
    if fallbackData <> invalid
        for each ch in fallbackData
            if ch.tvgId <> invalid and ch.logo <> invalid
                fallbackMap[ch.tvgId] = ch.logo
            end if
        end for
    end if
    
    for each channel in channels
        if channel.logo <> invalid and channel.logo <> ""
            goto nextCh
        end if
        
        if channel.tvgId <> invalid and fallbackMap.doesExist(channel.tvgId)
            channel.logo = fallbackMap[channel.tvgId]
            goto nextCh
        end if
        
        channel.logo = EPGGenerateLogoUrl(channel.title)
        
        nextCh:
    end for
end sub

function EPGGenerateLogoUrl(title as String) as String
    if title = invalid or title = ""
        return ""
    end if
    networkLogo = EPGGetNetworkLogo(title)
    if networkLogo <> ""
        return networkLogo
    end if
    return ""
end function

function EPGGetNetworkLogo(title as String) as String
    logoUrls = GetLogoUrls()
    baseUrl = logoUrls.TV_LOGOS_BASE
    networkName = title.Trim()
    parenPos = networkName.Instr("(")
    if parenPos > 0
        networkName = networkName.Left(parenPos - 1).Trim()
    end if

    ' Local ABC and CBS affiliate logos
    netMap = {
        abc: "abc-7-"
        cbs: "cbs-2-"
    }

    for each key in netMap
        if networkName.StartsWith(UCase(key))
            openParen = title.Instr("(")
            closeParen = title.Instr(")")
            if openParen > 0 and closeParen > openParen
                callLetters = LCase(title.Mid(openParen + 1, closeParen - openParen - 1))
                return logoUrls.TV_LOGOS_LOCAL + netMap[key] + callLetters + "-us.png"
            end if
        end if
    end for
    
    networkName = networkName.Replace(" New York", "")
    networkName = networkName.Replace(" Los Angeles", "")
    networkName = networkName.Replace(" Chicago", "")
    networkName = networkName.Replace(", LA", "")
    networkName = networkName.Replace(", NY", "")
    networkName = networkName.Replace(", CA", "")
    networkName = networkName.Trim()
    
    if networkName = ""
        return ""
    end if
    
    normalized = networkName.Replace("&", "-and-")
    normalized = normalized.Replace(" ", "-")
    normalized = normalized.Replace("'", "")
    normalized = normalized.Replace(",", "")
    normalized = LCase(normalized)
    
    keepCleaning = true
    while keepCleaning
        if normalized.Instr("--") > 0
            normalized = normalized.Replace("--", "-")
        else
            keepCleaning = false
        end if
    end while
    
    keepTrimming = true
    while keepTrimming and normalized.Len() > 0
        firstChar = normalized.Left(1)
        if firstChar = "-" or (firstChar >= "0" and firstChar <= "9")
            normalized = normalized.Mid(1)
        else
            keepTrimming = false
        end if
    end while
    
    keepTrimming = true
    while keepTrimming and normalized.Len() > 0
        if normalized.Right(1) = "-"
            normalized = normalized.Left(normalized.Len() - 1)
        else
            keepTrimming = false
        end if
    end while
    
    if normalized = ""
        return ""
    end if
    
    return baseUrl + normalized + "-us.png"
end function

function EPGNormalizeChannelId(id as String) as String
    if id = invalid
        return ""
    end if
    
    id = id.Trim()
    
    if id.StartsWith("channel")
        return id.Mid(7)
    end if
    
    dotPos = id.Instr(".")
    if dotPos > 0
        return Left(id, dotPos - 1)
    end if
    
    return id
end function

function EPGParseXmltvTime(xmltvTime as String) as LongInteger
    if xmltvTime.Len() < 14
        return 0
    end if
    
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
    if tvgId = invalid
        return ""
    end if
    
    normalizedId = EPGNormalizeChannelId(tvgId)
    
    if epg.schedules.doesExist(normalizedId)
        return epg.schedules[normalizedId]
    end if
    
    return ""
end function

function EPGGetPrograms(epg as Object, tvgId as String) as Object
    if tvgId = invalid
        return []
    end if
    
    normalizedId = EPGNormalizeChannelId(tvgId)
    
    if epg.programsByChannel.doesExist(normalizedId)
        return epg.programsByChannel[normalizedId]
    end if
    
    return []
end function

function GetNowPlayingForChannel(channel as Object, now as Integer) as String
    if channel.tvgId = invalid
        return channel.title
    end if

    programs = EPGGetPrograms(m.epgData, channel.tvgId)
    if programs = invalid or programs.count() = 0
        return channel.title
    end if

    for each prog in programs
        if prog.startTime <= now and prog.endTime > now then
            programTitle = prog.title
            sportsKeywords = [
                "College Basketball", "College Football", "College Baseball",
                "NFL Football", "NBA Basketball", "NBA G League Basketball", "MLB Baseball", "NHL Hockey"
            ]

            isSports = false
            for each keyword in sportsKeywords
                if programTitle.Instr(keyword) >= 0
                    isSports = true
                    exit for
                end if
            end for

            if isSports and prog.subTitle <> invalid and prog.subTitle <> ""
                print "MainScene: Sports program, using subtitle: " + prog.subTitle
                return prog.subTitle
            end if

            print "MainScene: Now playing: " + programTitle
            return programTitle
        end if
    end for

    return channel.title
end function