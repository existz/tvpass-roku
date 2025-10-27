sub init()
    m.top.backgroundURI = "pkg:/images/background.jpg"
    m.top.backgroundColor = "0x000000"

    m.loadingLabel = m.top.findNode("loadingLabel")
    m.channelList = m.top.findNode("channelList")
    m.videoPlayer = m.top.findNode("videoPlayer")

    m.channels = []
    m.playlistLoaded = false

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
            showChannelList()
            m.playlistLoaded = true
            print "Playlist loaded successfully with " + str(m.channels.count()) + " channels"
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

    for i = 0 to m.channels.count() - 1
        channel = m.channels[i]
        item = root.createChild("ContentNode")
        item.title = str(i + 1) + ". " + channel.title
        item.streamUrl = channel.url
        if channel.logo <> invalid
            item.logo = channel.logo
        end if
    end for

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