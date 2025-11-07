sub init()
    m.top.backgroundURI = "pkg:/images/background.jpg"
    m.top.backgroundColor = "0x000000"

    m.loadingLabel = m.top.findNode("loadingLabel")
    m.channelList = m.top.findNode("channelList")
    m.videoPlayer = m.top.findNode("videoPlayer")

    m.channels = []
    m.schedules = {}
    m.playlistLoaded = false
    m.schedulesLoaded = false

    ' Observe selection and video state
    m.channelList.observeField("itemSelected", "onChannelSelected")
    m.videoPlayer.observeField("state", "onVideoStateChanged")

    ' Load playlist only once on startup
    loadPlaylist()
end sub

sub loadPlaylist()
    ' Allow manual refresh but log it
    if m.playlistLoaded
        print "Manual playlist refresh requested"
    end if

    m.loadingLabel.text = "Loading Channels..."
    m.loadingLabel.visible = true
    m.channelList.visible = false

    ' Add timestamp to prevent caching
    timestamp = CreateObject("roDateTime").AsSeconds().ToStr()
    playlistUrl = "https://tvpass.org/playlist/m3u?t=" + timestamp
    
    print "Loading playlist from: " + playlistUrl

    m.playlistTask = createObject("roSGNode", "LoadPlaylistTask")
    m.playlistTask.url = playlistUrl
    m.playlistTask.observeField("response", "onPlaylistResponse")
    m.playlistTask.observeField("error", "onPlaylistError")
    m.playlistTask.control = "RUN"
end sub

sub onPlaylistResponse()
    response = m.playlistTask.response
    if response <> invalid and response <> ""
        parseM3U(response)
        if m.channels.count() > 0
            m.playlistLoaded = true
            print "Playlist loaded successfully with " + str(m.channels.count()) + " channels"
            ' Now load the schedules
            loadSchedules()
        else
            showError("No channels found in playlist")
        end if
    else
        showError("Empty playlist response")
    end if
    m.playlistTask = invalid
end sub

sub onPlaylistError()
    showError("Load failed: " + m.playlistTask.error)
    m.playlistTask = invalid
end sub

sub loadSchedules()
    m.loadingLabel.text = "Loading TV Guide..."
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
        print "Schedules loaded successfully"
    else
        print "Empty schedule response, continuing without schedules"
    end if
    m.scheduleTask = invalid
    
    ' Show channel list regardless of schedule load success
    showChannelList()
end sub

sub onScheduleError()
    print "Schedule load failed: " + m.scheduleTask.error + ", continuing without schedules"
    m.scheduleTask = invalid
    
    ' Show channel list even if schedules fail
    showChannelList()
end sub

sub parseSchedules(xmlString as String)
    xml = CreateObject("roXMLElement")
    if not xml.Parse(xmlString)
        print "Failed to parse EPG XML"
        return
    end if
    
    print "Parsing EPG XML"
    
    ' Get current time for filtering
    now = CreateObject("roDateTime")
    currentTime = now.AsSeconds()
    
    ' Parse programmes and build lookup by channel id
    programmes = xml.GetNamedElements("programme")
    channelsWithData = {}
    scheduleCount = 0
    
    for each programme in programmes
        channel = programme@channel
        startTime = programme@start
        stopTime = programme@stop
        
        if channel <> invalid and startTime <> invalid and stopTime <> invalid
            ' Parse XMLTV datetime (format: YYYYMMDDHHmmss +0000)
            startSec = parseXmltvTime(startTime)
            stopSec = parseXmltvTime(stopTime)
            
            ' Include programs starting within the next hour
            ' More lenient time window - include programs up to 2 hours ahead
            if startSec <= (currentTime + 7200) and stopSec > currentTime
                titleNode = programme.GetNamedElements("title")
                descNode = programme.GetNamedElements("desc")
                subTitleNode = programme.GetNamedElements("sub-title")
                
                if titleNode.Count() > 0
                    programTitle = titleNode[0].GetText()
                    
                    ' Add subtitle if available
                    if subTitleNode.Count() > 0 and subTitleNode[0].GetText() <> invalid
                        programTitle = programTitle + " - " + subTitleNode[0].GetText()
                    end if
                    
                    ' If no subtitle but has description, try to use that
                    if subTitleNode.Count() = 0 and descNode.Count() > 0 and descNode[0].GetText() <> invalid
                        description = descNode[0].GetText()
                        ' Only add description if it's different from the title
                        if description <> programTitle and description <> ""
                            programTitle = programTitle + " - " + description
                        end if
                    end if
                    
                    if programTitle <> invalid and programTitle <> ""
                        m.schedules[channel] = programTitle
                        scheduleCount = scheduleCount + 1
                    end if
                end if
            end if
        end if
    end for
    
    print "Parsed " + str(m.schedules.count()) + " current programs from EPG"
end sub

function parseXmltvTime(xmltvTime as String) as LongInteger
    ' Parse XMLTV format: YYYYMMDDHHmmss +0000
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

sub parseM3U(content as String)
    m.channels = []
    content = content.Replace(chr(13), chr(10)).Replace(chr(10)+chr(10), chr(10))
    lines = content.Split(chr(10))

    current = invalid
    for each line in lines
        line = line.Trim()
        if line = "" then goto nextLine

        if line.StartsWith("#EXTINF:")
            current = {}
            parts = line.Split(",")
            if parts.count() > 1
                current.title = parts[parts.count() - 1].Trim()
            end if

            ' Extract tvg-id
            tvgIdPos = line.Instr("tvg-id=")
            if tvgIdPos >= 0
                tvgIdStart = tvgIdPos + 8
                tvgIdEnd = line.Instr(tvgIdStart, chr(34))
                if tvgIdEnd > tvgIdStart
                    current.tvgId = line.Mid(tvgIdStart, tvgIdEnd - tvgIdStart)
                end if
            end if

            ' Extract tvg-logo
            logoPos = line.Instr("tvg-logo=")
            if logoPos >= 0
                logoStart = logoPos + 10
                logoEnd = line.Instr(logoStart, chr(34))
                if logoEnd > logoStart
                    current.logo = line.Mid(logoStart, logoEnd - logoStart)
                end if
            end if

        else if not line.StartsWith("#") and current <> invalid
            ' Replace /sd with /hd at the end of the URL
            if line.EndsWith("/sd")
                current.url = Left(line, Len(line) - 3) + "/hd"
                print "Converted SD to HD: " + current.url
            else
                current.url = line
            end if
            m.channels.push(current)
            current = invalid
        end if
        
        nextLine:
    end for
    
    print "Parsed " + str(m.channels.count()) + " channels from playlist"
end sub

sub showChannelList()
    m.loadingLabel.visible = false

    ' Create vertical list: One root with many items
    root = createObject("roSGNode", "ContentNode")

    matchCount = 0
    for i = 0 to m.channels.count() - 1
        channel = m.channels[i]
        item = root.createChild("ContentNode")
        item.title = str(i + 1) + ". " + channel.title
        item.addField("streamUrl", "string", false)
        item.streamUrl = channel.url
        if channel.logo <> invalid
            item.addField("logo", "string", false)
            item.logo = channel.logo
        end if
        
        ' Add nowPlaying from schedules if available (match by tvg-id)
        item.addField("nowPlaying", "string", false)
        if channel.tvgId <> invalid
            if m.schedules.doesExist(channel.tvgId)
                item.nowPlaying = m.schedules[channel.tvgId]
                matchCount = matchCount + 1
            else
                item.nowPlaying = ""
            end if
        else
            item.nowPlaying = ""
            ' Log first few mismatches for debugging
            if i < 5 and channel.tvgId <> invalid
                print "No EPG match for tvg-id: '" + channel.tvgId + "' (" + channel.title + ")"
            end if
        end if
    end for
    
    print "Matched " + str(matchCount) + " of " + str(m.channels.count()) + " channels to EPG"

    m.channelList.content = root
    m.channelList.visible = true
    m.channelList.setFocus(true)
    
    print "Channel list displayed with " + str(root.getChildCount()) + " items"
end sub

sub onChannelSelected()
    idx = m.channelList.itemSelected
    if idx >= 0 and idx < m.channels.count()
        channel = m.channels[idx]
        print "Playing channel: " + channel.title
        playChannel(channel)
    end if
end sub

sub playChannel(channel as Object)
    m.channelList.visible = false
    m.videoPlayer.visible = true

    content = createObject("roSGNode", "ContentNode")
    content.url = channel.url
    content.title = channel.title
    content.streamFormat = "hls"

    m.videoPlayer.content = content
    m.videoPlayer.control = "play"
    m.videoPlayer.setFocus(true)
    
    print "Starting playback: " + channel.url
end sub

sub onVideoStateChanged()
    state = m.videoPlayer.state
    print "Video state changed: " + state
    
    if state = "error" or state = "finished" or state = "stopped"
        m.videoPlayer.control = "stop"
        m.videoPlayer.visible = false
        m.channelList.visible = true
        m.channelList.setFocus(true)
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
    
    ' Back button - return to channel list from video
    if key = "back" and m.videoPlayer.visible
        print "Back button pressed - returning to channel list"
        m.videoPlayer.control = "stop"
        m.videoPlayer.visible = false
        m.channelList.visible = true
        m.channelList.setFocus(true)
        return true
    end if

    ' Star button (*) - refresh playlist
    if key = "options" or key = "*" or key = "instantreplay"
        if not m.videoPlayer.visible
            print "Star/Options button pressed - refreshing playlist"
            ' Reset the loaded flag to allow refresh
            m.playlistLoaded = false
            ' Show refresh message
            m.loadingLabel.text = "Refreshing Channels..."
            loadPlaylist()
            return true
        end if
    end if

    return false
end function