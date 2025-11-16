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

    ' Observe selection and focus
    m.channelList.observeField("itemSelected", "onChannelSelected")
    m.channelList.observeField("itemFocused", "onChannelFocused")
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
    
    ' Extract call letters from parentheses if present
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
    
    normalized = normalized.Replace(" US ", " ")
    normalized = normalized.Replace(" us ", " ")
    normalized = normalized.Replace(" US-", "-")
    normalized = normalized.Replace(" us-", "-")
    normalized = normalized.Replace(" HD ", " ")
    normalized = normalized.Replace(" hd ", " ")
    normalized = normalized.Replace(" SD ", " ")
    normalized = normalized.Replace(" sd ", " ")
    normalized = normalized.Replace(" Eastern ", " ")
    normalized = normalized.Replace(" eastern ", " ")
    normalized = normalized.Replace(" Western ", " ")
    normalized = normalized.Replace(" western ", " ")
    normalized = normalized.Replace(" Central ", " ")
    normalized = normalized.Replace(" central ", " ")
    normalized = normalized.Replace(" Mountain ", " ")
    normalized = normalized.Replace(" mountain ", " ")
    normalized = normalized.Replace(" Feed", "")
    normalized = normalized.Replace(" feed", "")
    normalized = normalized.Replace(" Extra", "")
    normalized = normalized.Replace(" extra", "")
    normalized = normalized.Replace(" Plus", "")
    normalized = normalized.Replace(" plus", "")
    normalized = normalized.Replace(" New York", "")
    normalized = normalized.Replace(" new york", "")
    normalized = normalized.Replace(" Los Angeles", "")
    normalized = normalized.Replace(" los angeles", "")
    normalized = normalized.Replace(" Chicago", "")
    normalized = normalized.Replace(" chicago", "")
    normalized = normalized.Replace(" Dallas", "")
    normalized = normalized.Replace(" dallas", "")
    normalized = normalized.Replace(" Houston", "")
    normalized = normalized.Replace(" houston", "")
    normalized = normalized.Replace(" Denver", "")
    normalized = normalized.Replace(" denver", "")
    normalized = normalized.Trim()
    
    normalized = normalized.Replace("&", " and ")
    normalized = normalized.Replace("&", " and ")
    normalized = normalized.Replace("A&E", "aande")
    normalized = normalized.Replace("a&e", "aande")
    normalized = normalized.Replace(" ", "-")
    normalized = normalized.Replace("_", "-")
    normalized = normalized.Replace(".", "-")
    normalized = normalized.Replace(",", "")
    normalized = normalized.Replace("'", "")
    normalized = normalized.Replace("A", "a").Replace("B", "b").Replace("C", "c").Replace("D", "d").Replace("E", "e").Replace("F", "f").Replace("G", "g").Replace("H", "h").Replace("I", "i").Replace("J", "j").Replace("K", "k").Replace("L", "l").Replace("M", "m").Replace("N", "n").Replace("O", "o").Replace("P", "p").Replace("Q", "q").Replace("R", "r").Replace("S", "s").Replace("T", "t").Replace("U", "u").Replace("V", "v").Replace("W", "w").Replace("X", "x").Replace("Y", "y").Replace("Z", "z")
    
    while normalized.Instr("--") > 0
        normalized = normalized.Replace("--", "-")
    end while
    
    if normalized.Len() > 0
        while normalized.Len() > 0 and (normalized.Left(1) = "-" or normalized.Left(1) = "0" or normalized.Left(1) = "1" or normalized.Left(1) = "2" or normalized.Left(1) = "3" or normalized.Left(1) = "4" or normalized.Left(1) = "5" or normalized.Left(1) = "6" or normalized.Left(1) = "7" or normalized.Left(1) = "8" or normalized.Left(1) = "9")
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
    
    ' If call letters exist, try network-callletters first, then fallback to network only
    if callLetters <> "" and callLetters <> invalid
        callLettersNorm = callLetters.Replace(" ", "").Replace("_", "").Replace(".", "").Replace(",", "")
        callLettersNorm = callLettersNorm.Replace("A", "a").Replace("B", "b").Replace("C", "c").Replace("D", "d").Replace("E", "e")
        callLettersNorm = callLettersNorm.Replace("F", "f").Replace("G", "g").Replace("H", "h").Replace("I", "i").Replace("J", "j")
        callLettersNorm = callLettersNorm.Replace("K", "k").Replace("L", "l").Replace("M", "m").Replace("N", "n").Replace("O", "o")
        callLettersNorm = callLettersNorm.Replace("P", "p").Replace("Q", "q").Replace("R", "r").Replace("S", "s").Replace("T", "t")
        callLettersNorm = callLettersNorm.Replace("U", "u").Replace("V", "v").Replace("W", "w").Replace("X", "x").Replace("Y", "y").Replace("Z", "z")
        if callLettersNorm <> "" and callLettersNorm <> invalid
            return baseUrl + normalized + "-" + callLettersNorm + "-us.png"
        end if
    end if
    
    logoFileName = normalized + "-us.png"
    
    return baseUrl + logoFileName
end function

function getTvgLogoUrl(channelTitle as String) as String
    baseUrl = "https://raw.githubusercontent.com/skydrome/tvg-logos/master/"
    
    normalized = channelTitle.Trim()
    
    ' Strip only qualifiers, keep location info for skydrome
    normalized = normalized.Replace(" US ", " ")
    normalized = normalized.Replace(" us ", " ")
    normalized = normalized.Replace(" HD ", " ")
    normalized = normalized.Replace(" hd ", " ")
    normalized = normalized.Replace(" SD ", " ")
    normalized = normalized.Replace(" sd ", " ")
    normalized = normalized.Replace(" Feed", "")
    normalized = normalized.Replace(" feed", "")
    normalized = normalized.Replace(" Extra", "")
    normalized = normalized.Replace(" extra", "")
    normalized = normalized.Replace(" Plus", "")
    normalized = normalized.Replace(" plus", "")
    normalized = normalized.Trim()
    
    ' Remove state abbreviations to avoid duplicates
    normalized = normalized.Replace(", NY", "")
    normalized = normalized.Replace(", CA", "")
    normalized = normalized.Replace(", TX", "")
    normalized = normalized.Replace(", CO", "")
    normalized = normalized.Replace(", PA", "")
    normalized = normalized.Replace(", AZ", "")
    normalized = normalized.Replace(", MA", "")
    normalized = normalized.Replace(", DC", "")
    normalized = normalized.Replace(", FL", "")
    normalized = normalized.Replace(", MI", "")
    normalized = normalized.Replace(", WA", "")
    normalized = normalized.Replace(", GA", "")
    normalized = normalized.Replace(", IL", "")
    normalized = normalized.Replace(", NV", "")
    normalized = normalized.Replace(", MD", "")
    normalized = normalized.Replace(", OH", "")
    normalized = normalized.Replace(", MN", "")
    normalized = normalized.Trim()
    
    ' Map city names to state abbreviations for skydrome filenames
    normalized = normalized.Replace(" Los Angeles", " los angeles ca")
    normalized = normalized.Replace(" New York", " new york ny")
    normalized = normalized.Replace(" Chicago", " chicago il")
    normalized = normalized.Replace(" Dallas", " dallas tx")
    normalized = normalized.Replace(" Houston", " houston tx")
    normalized = normalized.Replace(" Denver", " denver co")
    normalized = normalized.Replace(" Philadelphia", " philadelphia pa")
    normalized = normalized.Replace(" Phoenix", " phoenix az")
    normalized = normalized.Replace(" San Francisco", " san francisco ca")
    normalized = normalized.Replace(" San Diego", " san diego ca")
    normalized = normalized.Replace(" Boston", " boston ma")
    normalized = normalized.Replace(" Washington", " washington dc")
    normalized = normalized.Replace(" Miami", " miami fl")
    normalized = normalized.Replace(" Detroit", " detroit mi")
    normalized = normalized.Replace(" Seattle", " seattle wa")
    normalized = normalized.Replace(" Atlanta", " atlanta ga")
    normalized = normalized.Replace(" Las Vegas", " las vegas nv")
    normalized = normalized.Replace(" Baltimore", " baltimore md")
    normalized = normalized.Replace(" Cleveland", " cleveland oh")
    normalized = normalized.Replace(" Minneapolis", " minneapolis mn")
    normalized = normalized.Trim()
    
    ' Extract text in parentheses - keep call letters with network
    ' For "ABC (WABC) New York, NY" -> "abc wabc new york ny"
    parenPos = normalized.Instr("(")
    endParenPos = normalized.Instr(")")
    if parenPos > 0 and endParenPos > parenPos
        before = normalized.Left(parenPos - 1).Trim()
        extracted = normalized.Mid(parenPos)
        extracted = extracted.Left(endParenPos - parenPos + 1)
        extracted = extracted.Replace("(", "").Replace(")", "").Trim()
        
        ' Remove TV channel numbers from call letters (e.g., "KFMB-TV2" -> "KFMB")
        ' Only remove when prefixed with dash, not standalone TV (e.g., keep KTTV)
        extracted = extracted.Replace("-TV2", "").Replace("-TV", "").Replace("-tv2", "").Replace("-tv", "")
        extracted = extracted.Replace("TV2", "").Replace("tv2", "")
        extracted = extracted.Trim()
        
        after = ""
        if endParenPos < normalized.Len()
            after = normalized.Mid(endParenPos + 1).Trim()
        end if
        normalized = before + " " + extracted + " " + after
        normalized = normalized.Replace("  ", " ").Trim()
    end if
    
    ' Replace punctuation and spaces with dots
    normalized = normalized.Replace(",", "")
    normalized = normalized.Replace("&", "and")
    normalized = normalized.Replace("_", ".")
    normalized = normalized.Replace("-", ".")
    normalized = normalized.Replace(" ", ".")
    normalized = normalized.Replace("'", "")
    normalized = normalized.Replace("A", "a").Replace("B", "b").Replace("C", "c").Replace("D", "d").Replace("E", "e").Replace("F", "f").Replace("G", "g").Replace("H", "h").Replace("I", "i").Replace("J", "j").Replace("K", "k").Replace("L", "l").Replace("M", "m").Replace("N", "n").Replace("O", "o").Replace("P", "p").Replace("Q", "q").Replace("R", "r").Replace("S", "s").Replace("T", "t").Replace("U", "u").Replace("V", "v").Replace("W", "w").Replace("X", "x").Replace("Y", "y").Replace("Z", "z")
    
    ' Remove consecutive dots
    while normalized.Instr("..") > 0
        normalized = normalized.Replace("..", ".")
    end while
    
    ' Remove leading/trailing dots
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
    
    logoFileName = normalized + ".us.png"
    
    return baseUrl + logoFileName
end function

function getSkydromeNetworkLogoUrl(channelTitle as String) as String
    baseUrl = "https://raw.githubusercontent.com/skydrome/tvg-logos/master/"
    
    ' Extract network name (before parentheses or common location indicators)
    networkName = channelTitle.Trim()
    
    ' Remove text in parentheses
    parenPos = networkName.Instr("(")
    if parenPos > 0
        networkName = networkName.Left(parenPos - 1).Trim()
    end if
    
    ' Remove common location suffixes
    networkName = networkName.Replace(" New York", "").Replace(" new york", "").Replace(" Los Angeles", "").Replace(" los angeles", "").Replace(" Chicago", "").Replace(" chicago", "").Replace(" Dallas", "").Replace(" dallas", "").Replace(" Houston", "").Replace(" houston", "").Replace(" Atlanta", "").Replace(" atlanta", "").Replace(" Philadelphia", "").Replace(" philadelphia", "").Replace(" Phoenix", "").Replace(" phoenix", "").Replace(" San Francisco", "").Replace(" san francisco", "").Replace(" San Diego", "").Replace(" san diego", "").Replace(" Boston", "").Replace(" boston", "").Replace(" Washington", "").Replace(" washington", "").Replace(" Miami", "").Replace(" miami", "").Replace(" Detroit", "").Replace(" detroit", "").Replace(" Seattle", "").Replace(" seattle", "").Replace(" Denver", "").Replace(" denver", "").Replace(" Las Vegas", "").Replace(" las vegas", "").Replace(" Baltimore", "").Replace(" baltimore", "").Replace(" Cleveland", "").Replace(" cleveland", "").Replace(" Minneapolis", "").Replace(" minneapolis", "").Replace(", NY", "").Replace(", ny", "").Replace(", CA", "").Replace(", ca", "").Replace(", TX", "").Replace(", tx", "").Replace(", SD", "").Replace(", sd", "").Replace(" NY", "").Replace(" ny", "").Replace(" CA", "").Replace(" ca", "").Replace(" TX", "").Replace(" tx", "").Replace(" SD", "").Replace(" sd", "").Trim()
    
    if networkName = "" then return ""
    
    ' Normalize for skydrome format
    normalized = networkName
    normalized = normalized.Replace("A&E", "aande")
    normalized = normalized.Replace("a&e", "aande")
    normalized = normalized.Replace("&", "-and-")
    normalized = normalized.Replace(" ", "-")
    normalized = normalized.Replace("_", "-")
    normalized = normalized.Replace(".", "-")
    normalized = normalized.Replace(",", "")
    normalized = normalized.Replace("'", "")
    normalized = normalized.Replace("A", "a").Replace("B", "b").Replace("C", "c").Replace("D", "d").Replace("E", "e").Replace("F", "f").Replace("G", "g").Replace("H", "h").Replace("I", "i").Replace("J", "j").Replace("K", "k").Replace("L", "l").Replace("M", "m").Replace("N", "n").Replace("O", "o").Replace("P", "p").Replace("Q", "q").Replace("R", "r").Replace("S", "s").Replace("T", "t").Replace("U", "u").Replace("V", "v").Replace("W", "w").Replace("X", "x").Replace("Y", "y").Replace("Z", "z")
    
    ' Remove consecutive hyphens
    while normalized.Instr("--") > 0
        normalized = normalized.Replace("--", "-")
    end while
    
    ' Remove leading/trailing hyphens
    while normalized.Len() > 0 and (normalized.Left(1) = "-" or normalized.Left(1) = "0" or normalized.Left(1) = "1" or normalized.Left(1) = "2" or normalized.Left(1) = "3" or normalized.Left(1) = "4" or normalized.Left(1) = "5" or normalized.Left(1) = "6" or normalized.Left(1) = "7" or normalized.Left(1) = "8" or normalized.Left(1) = "9")
        normalized = normalized.Mid(1)
    end while
    while normalized.Len() > 0 and normalized.Right(1) = "-"
        normalized = normalized.Left(normalized.Len() - 1)
    end while
    
    if normalized = "" then return ""
    
    logoFileName = normalized + ".us.png"
    
    return baseUrl + logoFileName
end function

function getNetworkLogoUrl(channelTitle as String) as String
    baseUrl = "https://raw.githubusercontent.com/tv-logo/tv-logos/main/countries/united-states/"
    
    ' Extract network name (before parentheses or common location indicators)
    networkName = channelTitle.Trim()
    
    ' Remove text in parentheses
    parenPos = networkName.Instr("(")
    if parenPos > 0
        networkName = networkName.Left(parenPos - 1).Trim()
    end if
    
    ' Remove common location suffixes
    networkName = networkName.Replace(" New York", "").Replace(" new york", "").Replace(" Los Angeles", "").Replace(" los angeles", "").Replace(" Chicago", "").Replace(" chicago", "").Replace(" Dallas", "").Replace(" dallas", "").Replace(" Houston", "").Replace(" houston", "").Replace(" Atlanta", "").Replace(" atlanta", "").Replace(" Philadelphia", "").Replace(" philadelphia", "").Replace(" Phoenix", "").Replace(" phoenix", "").Replace(" San Francisco", "").Replace(" san francisco", "").Replace(" San Diego", "").Replace(" san diego", "").Replace(" Boston", "").Replace(" boston", "").Replace(" Washington", "").Replace(" washington", "").Replace(" Miami", "").Replace(" miami", "").Replace(" Detroit", "").Replace(" detroit", "").Replace(" Seattle", "").Replace(" seattle", "").Replace(" Denver", "").Replace(" denver", "").Replace(" Las Vegas", "").Replace(" las vegas", "").Replace(" Baltimore", "").Replace(" baltimore", "").Replace(" Cleveland", "").Replace(" cleveland", "").Replace(" Minneapolis", "").Replace(" minneapolis", "").Replace(", NY", "").Replace(", ny", "").Replace(", CA", "").Replace(", ca", "").Replace(", TX", "").Replace(", tx", "").Replace(", SD", "").Replace(", sd", "").Replace(" NY", "").Replace(" ny", "").Replace(" CA", "").Replace(" ca", "").Replace(" TX", "").Replace(" tx", "").Replace(" SD", "").Replace(" sd", "").Trim()
    
    if networkName = "" then return ""
    
    ' Normalize same as generateTvLogoUrl
    normalized = networkName
    normalized = normalized.Replace("A&E", "aande")
    normalized = normalized.Replace("a&e", "aande")
    normalized = normalized.Replace("&", " and ")
    normalized = normalized.Replace(" ", "-")
    normalized = normalized.Replace("_", "-")
    normalized = normalized.Replace(".", "-")
    normalized = normalized.Replace(",", "")
    normalized = normalized.Replace("'", "")
    normalized = normalized.Replace("A", "a").Replace("B", "b").Replace("C", "c").Replace("D", "d").Replace("E", "e").Replace("F", "f").Replace("G", "g").Replace("H", "h").Replace("I", "i").Replace("J", "j").Replace("K", "k").Replace("L", "l").Replace("M", "m").Replace("N", "n").Replace("O", "o").Replace("P", "p").Replace("Q", "q").Replace("R", "r").Replace("S", "s").Replace("T", "t").Replace("U", "u").Replace("V", "v").Replace("W", "w").Replace("X", "x").Replace("Y", "y").Replace("Z", "z")
    
    ' Remove consecutive hyphens
    while normalized.Instr("--") > 0
        normalized = normalized.Replace("--", "-")
    end while
    
    ' Remove leading/trailing hyphens
    while normalized.Len() > 0 and (normalized.Left(1) = "-" or normalized.Left(1) = "0" or normalized.Left(1) = "1" or normalized.Left(1) = "2" or normalized.Left(1) = "3" or normalized.Left(1) = "4" or normalized.Left(1) = "5" or normalized.Left(1) = "6" or normalized.Left(1) = "7" or normalized.Left(1) = "8" or normalized.Left(1) = "9")
        normalized = normalized.Mid(1)
    end while
    while normalized.Len() > 0 and normalized.Right(1) = "-"
        normalized = normalized.Left(normalized.Len() - 1)
    end while
    
    if normalized = "" then return ""
    
    logoFileName = normalized + "-us.png"
    
    return baseUrl + logoFileName
end function

sub onPlaylistError()
    errorMsg = ""
    if m.playlistTask.error <> invalid
        errorMsg = m.playlistTask.error.ToString()
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
        errorMsg = m.scheduleTask.error.ToString()
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
            
            ' Try to extract title from tvg-name first (handles commas in names)
            tvgNamePos = line.Instr("tvg-name=")
            if tvgNamePos > 0
                tvgNameStart = tvgNamePos + 10
                tvgNameEnd = line.Instr(tvgNameStart, chr(34))
                if tvgNameEnd > tvgNameStart
                    current.title = line.Mid(tvgNameStart, tvgNameEnd - tvgNameStart).Trim()
                end if
            end if
            
            ' Fallback: extract from text after last comma
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
        
        minutesInt = int(minutes)
        if minutesInt < 10
            timeStr = StrI(displayHour).Trim() + ":0" + StrI(minutesInt).Trim() + " " + ampm
        else
            timeStr = StrI(displayHour).Trim() + ":" + StrI(minutesInt).Trim() + " " + ampm
        end if
        
        ' Create time label
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
        print "Featured logo set to: " + channel.logo
    else
        print "No logo available for channel: " + channel.title
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
            updateFeaturedProgram(idx)
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