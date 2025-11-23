sub init()
    m.top.backgroundURI = "pkg:/images/background.jpg"
    m.top.backgroundColor = "0x1A1A1A"

    ' Find UI elements
    m.loadingLabel = m.top.findNode("loadingLabel")
    m.channelList = m.top.findNode("channelList")
    m.videoPlayer = m.top.findNode("videoPlayer")
    m.videoOverlay = m.top.findNode("videoOverlay")
    m.channelMenu = m.top.findNode("channelMenu")
    
    ' Long press detection
    m.longPressThreshold = 500 ' milliseconds
    m.leftButtonPressTime = 0
    m.rightButtonPressTime = 0
    m.isLongPressing = false
    
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
    
    ' Retry logic for full servers
    m.retryAttempts = 0
    m.maxRetryAttempts = 10
    m.retryDelay = 2
    m.bufferingTimer = invalid
    m.positionCheckTimer = invalid
    m.lastPosition = 0

    ' Observe selection and focus
    m.channelList.observeField("itemSelected", "onChannelSelected")
    m.channelList.observeField("itemFocused", "onChannelFocused")
    m.videoPlayer.observeField("state", "onVideoStateChanged")
    m.channelMenu.observeField("selectedChannel", "onMenuChannelSelected")

    ' Start clock update timer
    m.clockTimer = createObject("roSGNode", "Timer")
    m.clockTimer.repeat = true
    m.clockTimer.duration = 60
    m.clockTimer.observeField("fire", "updateClock")
    m.clockTimer.control = "start"
    
    ' Retry timer for failed streams
    m.retryTimer = createObject("roSGNode", "Timer")
    m.retryTimer.repeat = false
    m.retryTimer.observeField("fire", "onRetryTimer")
    
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
    
    ' Load logo playlist for tvg-logo info as fallback
    logoUrl = "https://raw.githubusercontent.com/phosani/tvpass/refs/heads/main/tvpasshd.m3u?t=" + timestamp
    print "Loading fallback logo playlist from: " + logoUrl
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
        print "Loaded " + str(m.logoChannels.count()) + " logo entries as fallback"
    end if
    m.logoTask = invalid
    checkPlaylistsComplete()
end sub

sub onLogoPlaylistError()
    print "Logo playlist load failed (non-critical): " + m.logoTask.error
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
    ' Create lookup map for fallback logos by tvg-id
    fallbackLogoMap = {}
    for each logoChannel in m.logoChannels
        if logoChannel.tvgId <> invalid and logoChannel.logo <> invalid
            fallbackLogoMap[logoChannel.tvgId] = logoChannel.logo
        end if
    end for
    
    print "Created fallback logo map with " + str(fallbackLogoMap.count()) + " entries"
    
    m.channels = []
    tvlogoCount = 0
    fallbackCount = 0
    
    for i = 0 to m.tvpassChannels.count() - 1
        channel = m.tvpassChannels[i]
        if channel.title <> invalid and channel.title <> ""
            ' First try fallback from phosani playlist (most reliable)
            if channel.tvgId <> invalid and fallbackLogoMap.doesExist(channel.tvgId)
                channel.logo = fallbackLogoMap[channel.tvgId]
                fallbackCount = fallbackCount + 1
                if i < 10
                    print "fallback logo " + str(i) + " for '" + channel.title + "' -> " + channel.logo
                end if
            end if
            
            ' Try skydrome tvg-logos as secondary (has affiliate station logos for ABC/NBC/CBS/FOX)
            if channel.logo = invalid
                ' Skip skydrome for networks that don't have good affiliate coverage
                useSkydrome = true
                if channel.title.Instr("CW ") = 1 or channel.title.Instr("CW(") > 0
                    useSkydrome = false
                end if
                
                if useSkydrome
                    skydromeUrl = getTvgLogoUrl(channel.title)
                    if skydromeUrl <> invalid and skydromeUrl <> ""
                        channel.logo = skydromeUrl
                        tvlogoCount = tvlogoCount + 1
                        if i < 10
                            print "skydrome logo " + str(i) + " for '" + channel.title + "' -> " + channel.logo
                        end if
                    end if
                end if
            end if
            
            ' For CW, use network-only logo
            isCW = channel.title.Left(2) = "CW" and channel.title.Len() > 2 and (channel.title.Mid(2, 1) = " " or channel.title.Mid(2, 1) = "(")
            if isCW
                channel.logo = "https://raw.githubusercontent.com/skydrome/tvg-logos/master/cw.us.png"
                tvlogoCount = tvlogoCount + 1
            end if
            
            ' Try tv-logos repository as tertiary option
            if channel.logo = invalid
                logoUrl = generateTvLogoUrl(channel.title)
                if logoUrl <> invalid
                    channel.logo = logoUrl
                    tvlogoCount = tvlogoCount + 1
                    if i < 10
                        print "tv-logo " + str(i) + " for '" + channel.title + "' -> " + channel.logo
                    end if
                else
                    ' Try network-only logo as final fallback
                    networkLogo = getNetworkLogoUrl(channel.title)
                    if networkLogo <> invalid and networkLogo <> ""
                        channel.logo = networkLogo
                        tvlogoCount = tvlogoCount + 1
                        if i < 10
                            print "network logo " + str(i) + " for '" + channel.title + "' -> " + channel.logo
                        end if
                    else
                        if i < 10 and channel.title.Instr("(W") > 0
                            print "NO LOGO for " + str(i) + " '" + channel.title + "' (tvgId: " + str(channel.tvgId) + ")"
                        end if
                    end if
                end if
            end if
        end if
        m.channels.push(channel)
    end for
    
    print "Total logos: " + str(tvlogoCount) + " from tv-logos, " + str(fallbackCount) + " from fallback, out of " + str(m.tvpassChannels.count())
end sub

function generateTvLogoUrl(channelTitle as String) as String
    baseUrl = "https://raw.githubusercontent.com/tv-logo/tv-logos/main/countries/united-states/"
    original = channelTitle.Trim()
    callLetters = ""
    parenPos = original.Instr("(")
    if parenPos > 0
        endParenPos = original.Instr(")")
        if endParenPos > parenPos
            callLetters = original.Mid(parenPos + 1, endParenPos - parenPos - 1).Trim()
        end if
    end if
    normalized = original
    parenPos = normalized.Instr("(")
    if parenPos > 0
        normalized = normalized.Left(parenPos - 1).Trim()
    end if
    parenPos = normalized.Instr("[")
    if parenPos > 0
        normalized = normalized.Left(parenPos - 1).Trim()
    end if
    dashPos = normalized.Instr(" - ")
    if dashPos > 0
        normalized = normalized.Left(dashPos - 1).Trim()
    end if
    normalized = normalized.Replace(" US ", " ").Replace(" us ", " ").Replace(" US-", "-").Replace(" us-", "-").Replace(" HD ", " ").Replace(" hd ", " ").Replace(" SD ", " ").Replace(" sd ", " ").Replace(" Eastern ", " ").Replace(" eastern ", " ").Replace(" Western ", " ").Replace(" western ", " ").Replace(" Central ", " ").Replace(" central ", " ").Replace(" Mountain ", " ").Replace(" mountain ", " ").Replace(" Feed", "").Replace(" feed", "").Replace(" Extra", "").Replace(" extra", "").Replace(" Plus", "").Replace(" plus", "").Replace(" New York", "").Replace(" new york", "").Replace(" Los Angeles", "").Replace(" los angeles", "").Replace(" Chicago", "").Replace(" chicago", "").Replace(" Dallas", "").Replace(" dallas", "").Replace(" Houston", "").Replace(" houston", "").Replace(" Denver", "").Replace(" denver", "").Trim()
    normalized = normalized.Replace("&", " and ").Replace("&", " and ").Replace("A&E", "aande").Replace("a&e", "aande").Replace(" ", "-").Replace("_", "-").Replace(".", "-").Replace(",", "").Replace("'", "")
    normalized = normalized.Replace("A","a").Replace("B","b").Replace("C","c").Replace("D","d").Replace("E","e").Replace("F","f").Replace("G","g").Replace("H","h").Replace("I","i").Replace("J","j").Replace("K","k").Replace("L","l").Replace("M","m").Replace("N","n").Replace("O","o").Replace("P","p").Replace("Q","q").Replace("R","r").Replace("S","s").Replace("T","t").Replace("U","u").Replace("V","v").Replace("W","w").Replace("X","x").Replace("Y","y").Replace("Z","z")
    while normalized.Instr("--") > 0
        normalized = normalized.Replace("--", "-")
    end while
    if normalized.Len() > 0
        while normalized.Len() > 0 and (normalized.Left(1) = "-" or normalized.Left(1) >= "0" and normalized.Left(1) <= "9")
            normalized = normalized.Mid(1)
            if normalized.Len() = 0 then exit while
        end while
        while normalized.Len() > 0 and normalized.Right(1) = "-"
            if normalized.Len() <= 1
                normalized = ""
                exit while
            end if
            normalized = normalized.Left(normalized.Len() - 1)
        end while
    end if
    if normalized = "" then return ""
    if callLetters <> "" and callLetters <> invalid
        callLettersNorm = callLetters.Replace(" ","").Replace("_","").Replace(".","").Replace(",","")
        callLettersNorm = callLettersNorm.Replace("A","a").Replace("B","b").Replace("C","c").Replace("D","d").Replace("E","e").Replace("F","f").Replace("G","g").Replace("H","h").Replace("I","i").Replace("J","j").Replace("K","k").Replace("L","l").Replace("M","m").Replace("N","n").Replace("O","o").Replace("P","p").Replace("Q","q").Replace("R","r").Replace("S","s").Replace("T","t").Replace("U","u").Replace("V","v").Replace("W","w").Replace("X","x").Replace("Y","y").Replace("Z","z")
        if callLettersNorm <> "" and callLettersNorm <> invalid
            return baseUrl + normalized + "-" + callLettersNorm + "-us.png"
        end if
    end if
    return baseUrl + normalized + "-us.png"
end function

function getTvgLogoUrl(channelTitle as String) as String
    baseUrl = "https://raw.githubusercontent.com/skydrome/tvg-logos/master/"
    normalized = channelTitle.Trim()
    normalized = normalized.Replace(" US "," ").Replace(" us "," ").Replace(" HD "," ").Replace(" hd "," ").Replace(" SD "," ").Replace(" sd "," ").Replace(" Feed","").Replace(" feed","").Replace(" Extra","").Replace(" extra","").Replace(" Plus","").Replace(" plus","").Trim()
    normalized = normalized.Replace(", NY","").Replace(", CA","").Replace(", TX","").Replace(", CO","").Replace(", PA","").Replace(", AZ","").Replace(", MA","").Replace(", DC","").Replace(", FL","").Replace(", MI","").Replace(", WA","").Replace(", GA","").Replace(", IL","").Replace(", NV","").Replace(", MD","").Replace(", OH","").Replace(", MN","").Trim()
    normalized = normalized.Replace(" Los Angeles"," los angeles ca").Replace(" New York"," new york ny").Replace(" Chicago"," chicago il").Replace(" Dallas"," dallas tx").Replace(" Houston"," houston tx").Replace(" Denver"," denver co").Replace(" Philadelphia"," philadelphia pa").Replace(" Phoenix"," phoenix az").Replace(" San Francisco"," san francisco ca").Replace(" San Diego"," san diego ca").Replace(" Boston"," boston ma").Replace(" Washington"," washington dc").Replace(" Miami"," miami fl").Replace(" Detroit"," detroit mi").Replace(" Seattle"," seattle wa").Replace(" Atlanta"," atlanta ga").Replace(" Las Vegas"," las vegas nv").Replace(" Baltimore"," baltimore md").Replace(" Cleveland"," cleveland oh").Replace(" Minneapolis"," minneapolis mn").Trim()
    parenPos = normalized.Instr("(")
    endParenPos = normalized.Instr(")")
    if parenPos > 0 and endParenPos > parenPos
        before = normalized.Left(parenPos - 1).Trim()
        extracted = normalized.Mid(parenPos).Left(endParenPos - parenPos + 1).Replace("(","").Replace(")","").Trim()
        extracted = extracted.Replace("-TV2","").Replace("-TV","").Replace("-tv2","").Replace("-tv","").Replace("TV2","").Replace("tv2","").Trim()
        after = ""
        if endParenPos < normalized.Len()
            after = normalized.Mid(endParenPos + 1).Trim()
        end if
        normalized = before + " " + extracted + " " + after
        normalized = normalized.Replace("  "," ").Trim()
    end if
    normalized = normalized.Replace(",","").Replace("&","and").Replace("_",".").Replace("-",".").Replace(" ",".").Replace("'","")
    normalized = normalized.Replace("A","a").Replace("B","b").Replace("C","c").Replace("D","d").Replace("E","e").Replace("F","f").Replace("G","g").Replace("H","h").Replace("I","i").Replace("J","j").Replace("K","k").Replace("L","l").Replace("M","m").Replace("N","n").Replace("O","o").Replace("P","p").Replace("Q","q").Replace("R","r").Replace("S","s").Replace("T","t").Replace("U","u").Replace("V","v").Replace("W","w").Replace("X","x").Replace("Y","y").Replace("Z","z")
    while normalized.Instr("..") > 0
        normalized = normalized.Replace("..",".") 
    end while
    if normalized.Len() > 0
        while normalized.Len() > 0 and normalized.Left(1) = "."
            normalized = normalized.Mid(1)
        end while
        while normalized.Len() > 0 and normalized.Right(1) = "."
            if normalized.Len() <= 1
                normalized = ""
                exit while
            end if
            normalized = normalized.Left(normalized.Len() - 1)
        end while
    end if
    if normalized = "" then return ""
    return baseUrl + normalized + ".us.png"
end function

function getSkydromeNetworkLogoUrl(channelTitle as String) as String
    baseUrl = "https://raw.githubusercontent.com/skydrome/tvg-logos/master/"
    networkName = channelTitle.Trim()
    parenPos = networkName.Instr("(")
    if parenPos > 0
        networkName = networkName.Left(parenPos - 1).Trim()
    end if
    networkName = networkName.Replace(" New York","").Replace(" Los Angeles","").Replace(" Chicago","").Replace(" Dallas","").Replace(" Houston","").Replace(", NY","").Replace(", CA","").Replace(", TX","").Trim()
    if networkName = "" then return ""
    normalized = networkName.Replace("A&E","aande").Replace("&","-and-").Replace(" ","-").Replace("_","-").Replace(".","-").Replace(",","").Replace("'","")
    normalized = normalized.Replace("A","a").Replace("B","b").Replace("C","c").Replace("D","d").Replace("E","e").Replace("F","f").Replace("G","g").Replace("H","h").Replace("I","i").Replace("J","j").Replace("K","k").Replace("L","l").Replace("M","m").Replace("N","n").Replace("O","o").Replace("P","p").Replace("Q","q").Replace("R","r").Replace("S","s").Replace("T","t").Replace("U","u").Replace("V","v").Replace("W","w").Replace("X","x").Replace("Y","y").Replace("Z","z")
    while normalized.Instr("--") > 0
        normalized = normalized.Replace("--","-")
    end while
    while normalized.Len() > 0 and (normalized.Left(1) = "-" or (normalized.Left(1) >= "0" and normalized.Left(1) <= "9"))
        normalized = normalized.Mid(1)
    end while
    while normalized.Len() > 0 and normalized.Right(1) = "-"
        normalized = normalized.Left(normalized.Len() - 1)
    end while
    if normalized = "" then return ""
    return baseUrl + normalized + ".us.png"
end function

function getNetworkLogoUrl(channelTitle as String) as String
    baseUrl = "https://raw.githubusercontent.com/tv-logo/tv-logos/main/countries/united-states/"
    networkName = channelTitle.Trim()
    parenPos = networkName.Instr("(")
    if parenPos > 0
        networkName = networkName.Left(parenPos - 1).Trim()
    end if
    networkName = networkName.Replace(" New York","").Replace(" Los Angeles","").Replace(" Chicago","").Replace(" Dallas","").Replace(", NY","").Replace(", CA","").Trim()
    if networkName = "" then return ""
    normalized = networkName.Replace("A&E","aande").Replace("&"," and ").Replace(" ","-").Replace("_","-").Replace(".","-").Replace(",","").Replace("'","")
    normalized = normalized.Replace("A","a").Replace("B","b").Replace("C","c").Replace("D","d").Replace("E","e").Replace("F","f").Replace("G","g").Replace("H","h").Replace("I","i").Replace("J","j").Replace("K","k").Replace("L","l").Replace("M","m").Replace("N","n").Replace("O","o").Replace("P","p").Replace("Q","q").Replace("R","r").Replace("S","s").Replace("T","t").Replace("U","u").Replace("V","v").Replace("W","w").Replace("X","x").Replace("Y","y").Replace("Z","z")
    while normalized.Instr("--") > 0
        normalized = normalized.Replace("--","-")
    end while
    while normalized.Len() > 0 and (normalized.Left(1) = "-" or (normalized.Left(1) >= "0" and normalized.Left(1) <= "9"))
        normalized = normalized.Mid(1)
    end while
    while normalized.Len() > 0 and normalized.Right(1) = "-"
        normalized = normalized.Left(normalized.Len() - 1)
    end while
    if normalized = "" then return ""
    return baseUrl + normalized + "-us.png"
end function

sub onPlaylistError()
    errorMsg = ""
    if m.playlistTask.error <> invalid
        errorMsg = str(m.playlistTask.error)
    end if
    print "Playlist load failed: " + errorMsg
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
    errorMsg = ""
    if m.scheduleTask.error <> invalid
        errorMsg = str(m.scheduleTask.error)
    end if
    print "Schedule load failed: " + errorMsg + ", continuing without schedules"
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
                    if programTitle = "Movie" and programSubTitle <> ""
                        programTitle = programSubTitle
                    end if
                    if not m.programsByChannel.doesExist(normalizedChannel)
                        m.programsByChannel[normalizedChannel] = []
                    end if
                    programInfo = {title: programTitle, description: programDesc, startTime: startSec, endTime: stopSec}
                    m.programsByChannel[normalizedChannel].push(programInfo)
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
    tzStr = "Z"
    if xmltvTime.Len() >= 19
        tzPart = xmltvTime.Mid(14)
        if tzPart.Left(1) = "+" or tzPart.Left(1) = "-"
            if tzPart.Len() >= 5
                tzStr = tzPart.Mid(0, 3) + ":" + tzPart.Mid(3, 2)
            end if
        end if
    end if
    iso8601Str = stri(year).Trim() + "-" + right("0" + stri(month).Trim(), 2) + "-" + right("0" + stri(day).Trim(), 2) + "T" + right("0" + stri(hour).Trim(), 2) + ":" + right("0" + stri(minute).Trim(), 2) + ":" + right("0" + stri(second).Trim(), 2) + tzStr
    dt = CreateObject("roDateTime")
    dt.FromISO8601String(iso8601Str)
    return dt.AsSeconds()
end function

function parseM3UData(content as String) as Object
    channels = []
    content = content.Replace(chr(13), chr(10)).Replace(chr(10)+chr(10), chr(10))
    lines = content.Split(chr(10))
    current = invalid
    lineNum = 0
    for each line in lines
        lineNum = lineNum + 1
        line = line.Trim()
        if line = "" then goto nextLine
        if line.StartsWith("#EXTINF:")
            if current <> invalid and current.url <> invalid
                channels.push(current)
            end if
            current = {}
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
        minutesInt = int(minutes)
        minutesStr = StrI(minutesInt).Trim()
        if minutesInt < 10
            minutesStr = "0" + minutesStr
        end if
        timeStr = StrI(displayHour).Trim() + ":" + minutesStr + " " + ampm
        timeLabel = createObject("roSGNode", "Label")
        timeLabel.width = slotWidth
        timeLabel.height = 40
        timeLabel.font = "font:SmallBoldSystemFont"
        timeLabel.color = "0x888888FF"
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
    for i = 0 to m.channels.count() - 1
        channel = m.channels[i]
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
    if m.channels.count() > 0 and m.lastChannelIndex >= 0 and m.lastChannelIndex < m.channels.count()
        updateFeaturedProgram(m.lastChannelIndex)
    else if m.channels.count() > 0
        updateFeaturedProgram(0)
    end if
    showGuideElements()
    if m.lastChannelIndex >= 0 and m.lastChannelIndex < m.channels.count()
        m.channelList.jumpToItem = m.lastChannelIndex
        m.channelList.animateToItem = m.lastChannelIndex
    end if
    m.channelList.setFocus(true)
end sub

sub updateFeaturedProgram(index as Integer)
    if index < 0 or index >= m.channels.count() then return
    channel = m.channels[index]
    if channel.logo <> invalid and channel.logo <> ""
        m.featuredLogo.uri = channel.logo
    end if
    m.featuredTitle.text = channel.title
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
            m.isBackgroundPlayback = false
            m.videoPlayer.opacity = 1.0
            m.videoOverlay.visible = false
            hideGuideElements()
            m.videoPlayer.setFocus(true)
        else
            m.retryAttempts = 0
            m.lastChannelIndex = idx
            m.currentChannelIndex = idx
            channel = m.channels[idx]
            print "Playing channel: " + channel.title
            playChannel(channel)
            m.isBackgroundPlayback = false
            updateFeaturedProgram(idx)
        end if
    end if
end sub

sub onMenuChannelSelected()
    ' Channel selected from the menu
    idx = m.channelMenu.selectedChannel
    if idx >= 0 and idx < m.channels.count()
        m.retryAttempts = 0
        m.lastChannelIndex = idx
        m.currentChannelIndex = idx
        channel = m.channels[idx]
        print "Playing channel from menu: " + channel.title
        
        ' Hide menu and play channel
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
    content.title = channel.title
    content.streamFormat = "hls"
    m.videoPlayer.content = content
    m.videoPlayer.control = "play"
    
    ' Disable video player's built-in trick play controls
    m.videoPlayer.enableTrickPlay = false
    
    ' Give focus to MainScene, not video player directly
    m.top.setFocus(true)
end sub

sub onVideoStateChanged()
    state = m.videoPlayer.state
    print "Video state changed: " + state
    
    ' Also check for error info
    errorCode = m.videoPlayer.errorCode
    errorMsg = m.videoPlayer.errorMsg
    errorStr = m.videoPlayer.errorStr
    
    print "  errorCode: " + str(errorCode)
    if errorMsg <> invalid and errorMsg <> ""
        print "  errorMsg: " + errorMsg
    end if
    if errorStr <> invalid and errorStr <> ""
        print "  errorStr: " + errorStr
    end if
    
    ' Check if we have an actual error even if state isn't "error"
    hasError = false
    if errorCode <> invalid and errorCode <> 0
        hasError = true
        print "  ERROR DETECTED via errorCode!"
    end if
    
    if state = "error" or hasError
        if m.retryAttempts < m.maxRetryAttempts and m.currentChannelIndex >= 0 and m.currentChannelIndex < m.channels.count()
            m.retryAttempts = m.retryAttempts + 1
            print "Retry attempt " + str(m.retryAttempts) + " of " + str(m.maxRetryAttempts) + " in " + str(m.retryDelay) + " seconds..."
            m.loadingLabel.text = "Server full, retrying... (Attempt " + str(m.retryAttempts) + "/" + str(m.maxRetryAttempts) + ")"
            m.loadingLabel.visible = true
            m.videoPlayer.control = "stop"
            m.retryTimer.duration = m.retryDelay
            m.retryTimer.control = "start"
        else
            if m.retryAttempts >= m.maxRetryAttempts
                print "Max retry attempts reached"
                m.loadingLabel.text = "Unable to connect - Server full. Please try again later."
            else
                m.loadingLabel.text = "Playback error"
            end if
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
        if shouldUpdateSchedules()
            m.schedulesLoaded = false
            loadSchedules()
        else
            showGuide()
            m.channelList.setFocus(true)
        end if
    end if
    if state = "playing"
        m.retryAttempts = 0
        m.loadingLabel.visible = false
        if m.bufferingTimer <> invalid
            m.bufferingTimer.control = "stop"
            m.bufferingTimer = invalid
        end if
        
        ' Check if we're actually playing or just stuck on the "server full" screen
        ' Start a position check timer to verify playback is progressing
        if m.positionCheckTimer = invalid or not m.positionCheckTimer.isSubtype("Timer")
            print "Creating position check timer"
            m.positionCheckTimer = m.top.createChild("Timer")
            m.positionCheckTimer.id = "positionCheckTimer"
            m.positionCheckTimer.duration = 3
            m.positionCheckTimer.repeat = false
            m.positionCheckTimer.observeField("fire", "onPositionCheck")
            m.lastPosition = m.videoPlayer.position
            print "Initial position: " + str(m.lastPosition)
        end if
        m.positionCheckTimer.control = "start"
    end if
    if state = "buffering"
        print "Video entered buffering state"
        ' Start a timer to detect if buffering takes too long (potential server full issue)
        if m.bufferingTimer = invalid or not m.bufferingTimer.isSubtype("Timer")
            print "Creating buffering timeout timer (10 seconds)"
            m.bufferingTimer = m.top.createChild("Timer")
            m.bufferingTimer.id = "bufferingTimeoutTimer"
            m.bufferingTimer.duration = 10
            m.bufferingTimer.repeat = false
            m.bufferingTimer.observeField("fire", "onBufferingTimeout")
            print "Timer created and configured"
        else
            print "Reusing existing buffering timer"
        end if
        print "Starting buffering timer..."
        m.bufferingTimer.control = "start"
        print "Buffering timer started, control set to 'start'"
    end if
end sub

sub onBufferingTimeout()
    ' Buffering has taken too long, treat it as an error
    print "!!! BUFFERING TIMEOUT TRIGGERED !!!"
    state = m.videoPlayer.state
    print "Current video state: " + state
    if state = "buffering"
        print "Still buffering after timeout - initiating retry"
        ' Force trigger the error handling
        m.videoPlayer.control = "stop"
        m.videoPlayer.visible = false
        hideGuideElements()
        
        if m.retryAttempts < m.maxRetryAttempts and m.currentChannelIndex >= 0 and m.currentChannelIndex < m.channels.count()
            m.retryAttempts = m.retryAttempts + 1
            print "Retry attempt " + str(m.retryAttempts) + " of " + str(m.maxRetryAttempts) + " due to buffering timeout..."
            m.loadingLabel.text = "Connection timeout, retrying... (Attempt " + str(m.retryAttempts) + "/" + str(m.maxRetryAttempts) + ")"
            m.loadingLabel.visible = true
            m.retryTimer.duration = m.retryDelay
            m.retryTimer.control = "start"
        else
            if m.retryAttempts >= m.maxRetryAttempts
                print "Max retry attempts reached"
                m.loadingLabel.text = "Unable to connect - Server may be full. Please try again later."
            else
                m.loadingLabel.text = "Connection timeout"
            end if
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
    ' Check if video position has progressed
    currentPosition = m.videoPlayer.position
    print "Position check: last=" + str(m.lastPosition) + " current=" + str(currentPosition)
    
    ' If position hasn't changed after 3 seconds of "playing", it's likely stuck on server full screen
    if currentPosition = m.lastPosition or currentPosition < 1
        print "!!! VIDEO NOT PROGRESSING - Server likely full !!!"
        ' Trigger retry logic
        m.videoPlayer.control = "stop"
        m.videoPlayer.visible = false
        hideGuideElements()
        
        if m.retryAttempts < m.maxRetryAttempts and m.currentChannelIndex >= 0 and m.currentChannelIndex < m.channels.count()
            m.retryAttempts = m.retryAttempts + 1
            print "Retry attempt " + str(m.retryAttempts) + " of " + str(m.maxRetryAttempts) + " due to stuck playback..."
            m.loadingLabel.text = "Server full, retrying... (Attempt " + str(m.retryAttempts) + "/" + str(m.maxRetryAttempts) + ")"
            m.loadingLabel.visible = true
            m.retryTimer.duration = m.retryDelay
            m.retryTimer.control = "start"
        else
            if m.retryAttempts >= m.maxRetryAttempts
                print "Max retry attempts reached"
                m.loadingLabel.text = "Unable to connect - Server full. Please try again later."
            else
                m.loadingLabel.text = "Playback error"
            end if
            m.loadingLabel.visible = true
            returnTimer = m.top.createChild("Timer")
            returnTimer.duration = 3
            returnTimer.repeat = false
            returnTimer.observeField("fire", "returnToGuide")
            returnTimer.control = "start"
        end if
    else
        print "Video is progressing normally"
    end if
    m.positionCheckTimer = invalid
end sub

sub onRetryTimer()
    print "Retrying channel playback..."
    if m.currentChannelIndex >= 0 and m.currentChannelIndex < m.channels.count()
        channel = m.channels[m.currentChannelIndex]
        playChannel(channel)
    end if
end sub

sub returnToGuide()
    m.loadingLabel.visible = false
    if shouldUpdateSchedules()
        m.schedulesLoaded = false
        loadSchedules()
    else
        showGuide()
        m.channelList.setFocus(true)
    end if
end sub

sub onChannelFocused()
    idx = m.channelList.itemFocused
    if idx >= 0 and idx < m.channels.count()
        updateFeaturedProgram(idx)
    end if
end sub

sub showError(msg as String)
    m.loadingLabel.text = "Error: " + msg
    m.loadingLabel.visible = true
    print "Error: " + msg
end sub

sub showChannelMenu()
    ' Build channel data with now playing info
    channelsWithNowPlaying = []
    for i = 0 to m.channels.count() - 1
        channel = m.channels[i]
        channelData = {
            title: channel.title,
            logo: channel.logo,
            url: channel.url,
            tvgId: channel.tvgId
        }
        
        ' Get now playing info
        normalizedId = invalid
        if channel.tvgId <> invalid
            normalizedId = normalizeChannelId(channel.tvgId)
        end if
        if normalizedId <> invalid and m.schedules.doesExist(normalizedId)
            channelData.nowPlaying = m.schedules[normalizedId]
        else
            channelData.nowPlaying = ""
        end if
        
        channelsWithNowPlaying.push(channelData)
    end for
    
    ' Set menu properties - order matters!
    print "Setting channels array with " + str(channelsWithNowPlaying.count()) + " channels"
    print "Current channel index: " + str(m.currentChannelIndex)
    
    ' Set currentChannelIndex BEFORE setting channels
    m.channelMenu.currentChannelIndex = m.currentChannelIndex
    m.channelMenu.channels = channelsWithNowPlaying
    m.channelMenu.visible = true
    
    ' Set focus
    print "MainScene: Setting focus to channel menu"
    m.channelMenu.setFocus(true)
end sub

function onKeyEvent(key as String, press as Boolean) as Boolean
    ' Get current time in milliseconds for long press detection
    dt = CreateObject("roDateTime")
    currentTime& = dt.AsSeconds()
    currentTimeMs& = (currentTime& * 1000) + dt.GetMilliseconds()

    ' If channel menu is visible, handle it FIRST before anything else
    if m.channelMenu.visible
        if key = "back" and press
            print "Closing channel menu"
            m.channelMenu.visible = false
            m.top.setFocus(true)
            return true
        end if
        ' Let the menu handle other keys
        return false
    end if
    
    ' Handle key press (button down)
    if press
        ' Track left button press time during video playback
        if key = "left" and m.videoPlayer.visible and not m.channelMenu.visible
            m.leftButtonPressTime = currentTimeMs&
            m.isLongPressing = false
            return true ' Consume the event, wait for release
        end if
        
        ' Track right button press time during video playback
        if key = "right" and m.videoPlayer.visible and not m.channelMenu.visible
            m.rightButtonPressTime = currentTimeMs&
            m.isLongPressing = false
            return true ' Consume the event, wait for release
        end if
        
        ' For up/down during video, let them through normally (no long press)
        if (key = "up" or key = "down") and m.videoPlayer.visible and not m.channelMenu.visible
            print key + " button pressed - showing channel menu"
            showChannelMenu()
            return true
        end if
        
        ' Back button during video playback - return to guide
        if key = "back" and m.videoPlayer.visible
            print "Back button pressed - showing guide with background playback"
            m.isBackgroundPlayback = true
            m.videoPlayer.opacity = 1.0
            m.videoPlayer.visible = true
            m.videoOverlay.visible = true
            showGuideElements()
            m.channelList.setFocus(true)
            if shouldUpdateSchedules()
                m.schedulesLoaded = false
                loadSchedules()
            else
                showGuide()
                m.channelList.setFocus(true)
            end if
            return true
        end if
        
        ' Refresh button
        if key = "options" or key = "*" or key = "instantreplay"
            if not m.videoPlayer.visible
                print "Refresh button pressed"
                m.playlistLoaded = false
                loadPlaylist()
                return true
            end if
        end if
    else
        ' Handle key release (button up)
        
        ' Check for long press left (rewind)
        if key = "left" and m.leftButtonPressTime > 0
            pressDuration = currentTimeMs& - m.leftButtonPressTime
            m.leftButtonPressTime = 0
            
            print "Left button released after " + str(pressDuration) + "ms"
            
            if pressDuration >= m.longPressThreshold and m.videoPlayer.visible and not m.channelMenu.visible
                print "Long press LEFT detected - seeking backward"
                m.isLongPressing = true
                seekBackward()
                return true
            else if m.videoPlayer.visible and not m.channelMenu.visible
                ' Short press - show menu
                print "Short press LEFT - showing channel menu"
                showChannelMenu()
                return true
            end if
        end if
        
        ' Check for long press right (fast forward)
        if key = "right" and m.rightButtonPressTime > 0
            pressDuration = currentTimeMs& - m.rightButtonPressTime
            m.rightButtonPressTime = 0
            
            print "Right button released after " + str(pressDuration) + "ms"
            
            if pressDuration >= m.longPressThreshold and m.videoPlayer.visible and not m.channelMenu.visible
                print "Long press RIGHT detected - seeking forward"
                m.isLongPressing = true
                seekForward()
                return true
            else if m.videoPlayer.visible and not m.channelMenu.visible
                ' Short press - show menu
                print "Short press RIGHT - showing channel menu"
                showChannelMenu()
                return true
            end if
        end if
        
        ' Reset long press flag on any key release
        m.isLongPressing = false
    end if
    
    return false
end function

sub seekBackward()
    ' Seek backward by 10 seconds
    if m.videoPlayer.content <> invalid
        currentPos = m.videoPlayer.position
        newPos = currentPos - 10
        if newPos < 0 then newPos = 0
        m.videoPlayer.seek = newPos
        print "Seeking backward to position: " + str(newPos)
    end if
end sub

sub seekForward()
    ' Seek forward by 10 seconds
    if m.videoPlayer.content <> invalid
        currentPos = m.videoPlayer.position
        duration = m.videoPlayer.duration
        newPos = currentPos + 10
        if duration > 0 and newPos > duration then newPos = duration
        m.videoPlayer.seek = newPos
        print "Seeking forward to position: " + str(newPos)
    end if
end sub