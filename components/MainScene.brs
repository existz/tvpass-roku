sub init()
    m.top.backgroundURI = "pkg:/images/background.jpg"
    m.top.backgroundColor = "0x1A1A1A"

    ' Find UI elements
    m.loadingLabel = m.top.findNode("loadingLabel")
    m.channelList = m.top.findNode("channelList")
    m.videoPlayer = m.top.findNode("videoPlayer")
    m.videoOverlay = m.top.findNode("videoOverlay")
    
    ' Guide UI elements
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
    
    ' Track state
    m.isBackgroundPlayback = false
    m.currentChannelIndex = -1
    m.channels = []
    m.schedules = {}
    m.programsByChannel = {}
    m.playlistLoaded = false
    m.schedulesLoaded = false
    m.lastScheduleUpdate = 0
    m.lastChannelIndex = 0
    m.pendingTasks = 0
    m.tvpassChannels = []
    m.logoChannels = []

    ' Observe selection
    m.channelList.observeField("itemSelected", "onChannelSelected")
    m.videoPlayer.observeField("state", "onVideoStateChanged")

    ' Start clock update timer
    m.clockTimer = createObject("roSGNode", "Timer")
    m.clockTimer.repeat = true
    m.clockTimer.duration = 60
    m.clockTimer.observeField("fire", "updateClock")
    m.clockTimer.control = "start"
    
    updateClock()
    loadPlaylist()
end sub

sub updateClock()
    now = CreateObject("roDateTime")
    now.ToLocalTime()
    hour = now.GetHours()
    minute = now.GetMinutes()
    ampm = "am"
    
    if hour >= 12
        ampm = "pm"
        if hour > 12
            hour = hour - 12
        end if
    end if
    if hour = 0 then hour = 12
    
    timeStr = str(hour) + ":" + right("0" + str(minute), 2) + " " + ampm
    m.currentTimeLabel.text = timeStr
end sub

sub loadPlaylist()
    if m.playlistLoaded
        print "Manual playlist refresh requested"
    end if

    m.loadingLabel.text = "Loading TV Guide..."
    m.loadingLabel.visible = true
    hideGuideElements()

    timestamp = CreateObject("roDateTime").AsSeconds().ToStr()
    
    ' Load both playlists
    m.pendingTasks = 2
    m.tvpassChannels = []
    m.logoChannels = []
    
    ' Load tvpass playlist for channels and URLs
    tvpassUrl = "https://tvpass.org/playlist/m3u?t=" + timestamp
    print "Loading tvpass playlist from: " + tvpassUrl
    m.playlistTask = createObject("roSGNode", "LoadPlaylistTask")
    m.playlistTask.url = tvpassUrl
    m.playlistTask.observeField("response", "onTvpassPlaylistResponse")
    m.playlistTask.observeField("error", "onPlaylistError")
    m.playlistTask.control = "RUN"
    
    ' Load logo playlist for tvg-logo info
    logoUrl = "https://raw.githubusercontent.com/phosani/tvpass/refs/heads/main/tvpasshd.m3u?t=" + timestamp
    print "Loading logo playlist from: " + logoUrl
    m.logoTask = createObject("roSGNode", "LoadPlaylistTask")
    m.logoTask.url = logoUrl
    m.logoTask.observeField("response", "onLogoPlaylistResponse")
    m.logoTask.observeField("error", "onLogoPlaylistError")
    m.logoTask.control = "RUN"
end sub

sub onTvpassPlaylistResponse()
    response = m.playlistTask.response
    if response <> invalid and response <> ""
        m.tvpassChannels = parseM3UData(response)
        print "Loaded " + str(m.tvpassChannels.count()) + " channels from tvpass (response size: " + str(len(response)) + " bytes)"
        if m.tvpassChannels.count() > 0
            print "First channel: " + m.tvpassChannels[0].title
            print "Last channel: " + m.tvpassChannels[m.tvpassChannels.count() - 1].title
        end if
    end if
    m.playlistTask = invalid
    checkPlaylistsComplete()
end sub

sub onLogoPlaylistResponse()
    response = m.logoTask.response
    if response <> invalid and response <> ""
        m.logoChannels = parseM3UData(response)
        print "Loaded " + str(m.logoChannels.count()) + " logo entries"
    end if
    m.logoTask = invalid
    checkPlaylistsComplete()
end sub

sub onLogoPlaylistError()
    print "Logo playlist load failed: " + m.logoTask.error
    m.logoTask = invalid
    checkPlaylistsComplete()
end sub

sub checkPlaylistsComplete()
    m.pendingTasks = m.pendingTasks - 1
    if m.pendingTasks = 0
        ' Merge the data
        mergePlaylists()
        if m.channels.count() > 0
            m.playlistLoaded = true
            print "Playlists merged successfully with " + str(m.channels.count()) + " channels"
            loadSchedules()
        else
            showError("No channels found in playlist")
        end if
    end if
end sub

sub mergePlaylists()
    ' Create lookup map for logos by tvg-id
    logoMap = {}
    for each logoChannel in m.logoChannels
        if logoChannel.tvgId <> invalid and logoChannel.logo <> invalid
            logoMap[logoChannel.tvgId] = logoChannel.logo
        end if
    end for
    
    print "Created logo map with " + str(logoMap.count()) + " entries"
    
    ' Use tvpass channels as base and add logos from logo playlist
    m.channels = []
    for each channel in m.tvpassChannels
        ' Only add logo from logo playlist if channel doesn't have one
        if channel.logo = invalid and channel.tvgId <> invalid and logoMap.doesExist(channel.tvgId)
            channel.logo = logoMap[channel.tvgId]
            print "Updated logo for " + channel.tvgId + ": " + channel.logo
        end if
        m.channels.push(channel)
    end for
end sub

sub onPlaylistError()
    print "Playlist load failed: " + m.playlistTask.error
    m.playlistTask = invalid
    checkPlaylistsComplete()
end sub

function shouldUpdateSchedules() as Boolean
    currentTime = CreateObject("roDateTime").AsSeconds()
    return m.lastScheduleUpdate = 0 or (currentTime - m.lastScheduleUpdate) >= 300
end function

sub loadSchedules()
    if not shouldUpdateSchedules()
        print "Skipping EPG update - last update was less than 5 minutes ago"
        showGuide()
        return
    end if

    m.loadingLabel.text = "Loading Program Guide..."
    m.loadingLabel.visible = true

    timestamp = CreateObject("roDateTime").AsSeconds().ToStr()
    epgUrl = "https://tvpass.org/epg.xml?t=" + timestamp
    
    print "Loading EPG from: " + epgUrl

    m.scheduleTask = createObject("roSGNode", "LoadScheduleTask")
    m.scheduleTask.url = epgUrl
    m.scheduleTask.observeField("response", "onScheduleResponse")
    m.scheduleTask.observeField("error", "onScheduleError")
    m.scheduleTask.control = "RUN"
end sub

sub onScheduleResponse()
    response = m.scheduleTask.response
    if response <> invalid and response <> ""
        parseSchedules(response)
        m.schedulesLoaded = true
        m.lastScheduleUpdate = CreateObject("roDateTime").AsSeconds()
        print "Schedules loaded successfully"
    else
        print "Empty schedule response, continuing without schedules"
    end if
    m.scheduleTask = invalid
    showGuide()
end sub

sub onScheduleError()
    print "Schedule load failed: " + m.scheduleTask.error + ", continuing without schedules"
    m.scheduleTask = invalid
    showGuide()
end sub

sub parseSchedules(xmlString as String)
    xml = CreateObject("roXMLElement")
    if not xml.Parse(xmlString)
        print "Failed to parse EPG XML"
        return
    end if
    
    print "Parsing EPG XML"
    
    now = CreateObject("roDateTime")
    currentTime = now.AsSeconds()
    
    ' Parse programmes
    programmes = xml.GetNamedElements("programme")
    m.programsByChannel = {}
    
    for each programme in programmes
        channel = programme@channel
        startTime = programme@start
        stopTime = programme@stop
        
        if channel <> invalid and startTime <> invalid and stopTime <> invalid
            normalizedChannel = normalizeChannelId(channel)
            startSec = parseXmltvTime(startTime)
            stopSec = parseXmltvTime(stopTime)
            
            ' Store all programs for next 2 hours
            if startSec <= (currentTime + 7200) and stopSec > currentTime
                titleNode = programme.GetNamedElements("title")
                descNode = programme.GetNamedElements("desc")
                subTitleNode = programme.GetNamedElements("sub-title")
                
                if titleNode.Count() > 0
                    programTitle = titleNode[0].GetText()
                    programDesc = ""
                    programSubTitle = ""
                    
                    if descNode.Count() > 0
                        programDesc = descNode[0].GetText()
                    end if
                    
                    if subTitleNode.Count() > 0
                        programSubTitle = subTitleNode[0].GetText()
                    end if
                    
                    ' Use subtitle if title is just "Movie"
                    if programTitle = "Movie" and programSubTitle <> ""
                        programTitle = programSubTitle
                    end if
                    
                    ' Initialize channel array if needed
                    if not m.programsByChannel.doesExist(normalizedChannel)
                        m.programsByChannel[normalizedChannel] = []
                    end if
                    
                    ' Add program to channel
                    programInfo = {
                        title: programTitle,
                        description: programDesc,
                        startTime: startSec,
                        endTime: stopSec
                    }
                    m.programsByChannel[normalizedChannel].push(programInfo)
                    
                    ' Also store current program in schedules
                    if startSec <= currentTime and stopSec > currentTime
                        m.schedules[normalizedChannel] = programTitle
                    end if
                end if
            end if
        end if
    end for
    
    print "Parsed programs for " + str(m.programsByChannel.count()) + " channels"
end sub

function normalizeChannelId(id as String) as String
    if id = invalid then return ""
    id = id.Trim()
    if id.StartsWith("channel")
        return id.Mid(7)
    else if id.Instr(".") > 0
        return Left(id, id.Instr(".") - 1)
    else
        return id
    end if
end function

function parseXmltvTime(xmltvTime as String) as LongInteger
    if xmltvTime.Len() < 14 then return 0
    
    year = val(xmltvTime.Mid(0, 4))
    month = val(xmltvTime.Mid(4, 2))
    day = val(xmltvTime.Mid(6, 2))
    hour = val(xmltvTime.Mid(8, 2))
    minute = val(xmltvTime.Mid(10, 2))
    second = val(xmltvTime.Mid(12, 2))
    
    dt = CreateObject("roDateTime")
    dt.FromISO8601String(stri(year).Trim() + "-" + right("0" + stri(month).Trim(), 2) + "-" + right("0" + stri(day).Trim(), 2) + "T" + right("0" + stri(hour).Trim(), 2) + ":" + right("0" + stri(minute).Trim(), 2) + ":" + right("0" + stri(second).Trim(), 2) + "Z")
    
    return dt.AsSeconds()
end function

function parseM3UData(content as String) as Object
    channels = []
    content = content.Replace(chr(13), chr(10)).Replace(chr(10)+chr(10), chr(10))
    lines = content.Split(chr(10))

    current = invalid
    for each line in lines
        line = line.Trim()
        if line = "" then goto nextLine

        if line.StartsWith("#EXTINF:")
            if current <> invalid and current.url <> invalid
                channels.push(current)
            end if
            
            current = {}
            parts = line.Split(",")
            if parts.count() > 1
                current.title = parts[parts.count() - 1].Trim()
            end if

            tvgIdPos = line.Instr("tvg-id=")
            if tvgIdPos > 0
                tvgIdStart = tvgIdPos + 8
                tvgIdEnd = line.Instr(tvgIdStart, chr(34))
                if tvgIdEnd > tvgIdStart
                    current.tvgId = line.Mid(tvgIdStart, tvgIdEnd - tvgIdStart)
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
                current.url = Left(line, Len(line) - 3) + "/hd"
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

sub createTimeSlotHeaders()
    ' Clear existing headers
    m.timeSlotHeaders.removeChildrenIndex(m.timeSlotHeaders.getChildCount(), 0)
    
    now = CreateObject("roDateTime")
    now.ToLocalTime()
    
    ' Create 3 time slot headers (30-minute intervals) for viewing window
    slotWidth = 517
    currentHour = now.GetHours()
    currentMinute = now.GetMinutes()
    
    ' Round down to nearest 30-minute interval
    if currentMinute >= 30
        startMinute = 30
    else
        startMinute = 0
    end if
    
    for i = 0 to 2
        totalMinutes = (startMinute + (i * 30))
        hours = currentHour + int(totalMinutes / 60)
        minutes = totalMinutes mod 60
        
        if hours >= 24 then hours = hours - 24
        
        ' Format time
        displayHour = hours
        ampm = "am"
        if hours >= 12
            ampm = "pm"
            if hours > 12
                displayHour = hours - 12
            end if
        end if
        if displayHour = 0 then displayHour = 12
        
        minuteStr = ""
        if minutes > 0
            minuteStr = ":" + right("0" + str(minutes), 2)
        end if
        timeStr = str(displayHour) + minuteStr + ampm
        
        ' Create time label
        timeLabel = createObject("roSGNode", "Label")
        timeLabel.width = slotWidth
        timeLabel.height = 40
        timeLabel.text = timeStr
        timeLabel.font = "font:SmallBoldSystemFont"
        timeLabel.color = "0x888888FF"
        timeLabel.horizAlign = "center"
        
        m.timeSlotHeaders.appendChild(timeLabel)
    end for
end sub

sub showGuide()
    m.loadingLabel.visible = false
    
    ' Create time slot headers
    createTimeSlotHeaders()
    
    ' Create channel list content
    root = createObject("roSGNode", "ContentNode")
    
    for i = 0 to m.channels.count() - 1
        channel = m.channels[i]
        item = root.createChild("ContentNode")
        
        item.addField("channelNumber", "integer", false)
        item.channelNumber = i + 1
        
        ' If title is too long, move to nowPlaying
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
            normalizedId = invalid
            if channel.tvgId <> invalid
                normalizedId = normalizeChannelId(channel.tvgId)
            end if
            if normalizedId <> invalid and m.schedules.doesExist(normalizedId)
                item.nowPlaying = m.schedules[normalizedId]
            else
                item.nowPlaying = ""
            end if
        end if
        
        item.addField("streamUrl", "string", false)
        item.streamUrl = channel.url
        
        if channel.logo <> invalid
            item.addField("logo", "string", false)
            item.logo = channel.logo
        end if
        
        ' Add upcoming programs
        item.addField("programs", "array", false)
        normalizedId = invalid
        if channel.tvgId <> invalid
            normalizedId = normalizeChannelId(channel.tvgId)
        end if
        
        if normalizedId <> invalid and m.programsByChannel.doesExist(normalizedId)
            item.programs = m.programsByChannel[normalizedId]
        else
            item.programs = []
        end if
    end for
    
    m.channelList.content = root
    
    ' Update featured program with first channel
    if m.channels.count() > 0 and m.lastChannelIndex >= 0 and m.lastChannelIndex < m.channels.count()
        updateFeaturedProgram(m.lastChannelIndex)
    else if m.channels.count() > 0
        updateFeaturedProgram(0)
    end if
    
    showGuideElements()
    m.channelList.setFocus(true)
    
    ' Restore position
    if m.lastChannelIndex >= 0 and m.lastChannelIndex < m.channels.count()
        m.channelList.jumpToItem = m.lastChannelIndex
    end if
end sub

sub updateFeaturedProgram(index as Integer)
    if index < 0 or index >= m.channels.count() then return
    
    channel = m.channels[index]
    
    ' Set logo
    if channel.logo <> invalid and channel.logo <> ""
        m.featuredLogo.uri = channel.logo
    end if
    
    ' Set title
    m.featuredTitle.text = channel.title
    
    ' Set current program info
    normalizedId = invalid
    if channel.tvgId <> invalid
        normalizedId = normalizeChannelId(channel.tvgId)
    end if
    
    if normalizedId <> invalid and m.schedules.doesExist(normalizedId)
        m.featuredTime.text = "Now Playing"
        m.featuredDescription.text = m.schedules[normalizedId]
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
    if idx >= 0 and idx < m.channels.count()
        if m.isBackgroundPlayback and idx = m.currentChannelIndex
            ' Return to full screen
            m.isBackgroundPlayback = false
            m.videoPlayer.opacity = 1.0
            m.videoOverlay.visible = false
            hideGuideElements()
            m.videoPlayer.setFocus(true)
        else
            ' Play new channel
            m.lastChannelIndex = idx
            m.currentChannelIndex = idx
            channel = m.channels[idx]
            print "Playing channel: " + channel.title
            playChannel(channel)
            m.isBackgroundPlayback = false
        end if
    end if
end sub

sub playChannel(channel as Object)
    m.videoPlayer.opacity = 1.0
    m.videoPlayer.visible = true
    m.videoOverlay.visible = false
    hideGuideElements()

    content = createObject("roSGNode", "ContentNode")
    content.url = channel.url
    content.title = channel.title
    content.streamFormat = "hls"

    m.videoPlayer.content = content
    m.videoPlayer.control = "play"
    m.videoPlayer.setFocus(true)
end sub

sub onVideoStateChanged()
    state = m.videoPlayer.state
    print "Video state changed: " + state
    
    if state = "error" or state = "finished" or state = "stopped"
        m.videoPlayer.control = "stop"
        m.videoPlayer.visible = false
        
        if shouldUpdateSchedules()
            m.schedulesLoaded = false
            loadSchedules()
        else
            showGuide()
            m.channelList.setFocus(true)
        end if
    end if
end sub

sub showError(msg as String)
    m.loadingLabel.text = "Error: " + msg
    m.loadingLabel.visible = true
    print "Error: " + msg
end sub

function onKeyEvent(key as String, press as Boolean) as Boolean
    if not press then return false

    print "Key pressed: " + key
    
    ' Back button
    if key = "back" and m.videoPlayer.visible
        print "Back button pressed - showing guide with background playback"
        m.isBackgroundPlayback = true
        m.videoPlayer.opacity = 1.0
        m.videoPlayer.visible = true
        m.videoOverlay.visible = true
        showGuideElements()
        m.channelList.setFocus(true)
        
        if m.lastChannelIndex >= 0
            m.channelList.jumpToItem = m.lastChannelIndex
        end if
        
        if shouldUpdateSchedules()
            m.schedulesLoaded = false
            loadSchedules()
        end if
        
        return true
    end if

    ' Refresh
    if key = "options" or key = "*" or key = "instantreplay"
        if not m.videoPlayer.visible
            print "Refresh button pressed"
            m.playlistLoaded = false
            loadPlaylist()
            return true
        end if
    end if

    return false
end function