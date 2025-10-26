sub init()
    m.top.backgroundURI = "pkg:/images/background.jpg"
    m.top.backgroundColor = "0x000000"

    m.loadingLabel = m.top.findNode("loadingLabel")
    m.channelList = m.top.findNode("channelList")
    m.videoPlayer = m.top.findNode("videoPlayer")

    m.channels = []

    ' Observe selection and video state
    m.channelList.observeField("itemSelected", "onChannelSelected")
    m.videoPlayer.observeField("state", "onVideoStateChanged")

    loadPlaylist()
end sub

sub loadPlaylist()
    m.loadingLabel.text = "Loading Channels..."
    m.loadingLabel.visible = true

    m.playlistTask = createObject("roSGNode", "LoadPlaylistTask")
    m.playlistTask.url = "https://tvpass.org/playlist/m3u"
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
        if line = "" then continue for

        if line.StartsWith("#EXTINF:")
            current = {}
            parts = line.Split(",")
            if parts.count() > 1
                current.title = parts[parts.count() - 1].Trim()
            end if

            ' Extract tvg-logo
            logoPos = line.Instr("tvg-logo=")
            if logoPos >= 0
                q1 = line.Instr(logoPos + 10, chr(34))
                q2 = line.Instr(q1 + 1, chr(34))
                if q2 > q1
                    current.logo = line.Mid(q1 + 1, q2 - q1 - 1)
                end if
            end if

        else if not line.StartsWith("#") and current <> invalid
            current.url = line
            m.channels.push(current)
            current = invalid
        end if
    end for
end sub

sub showChannelList()
    m.loadingLabel.visible = false

    ' === VERTICAL LIST: One root with many items ===
    root = createObject("roSGNode", "ContentNode")

    for i = 0 to m.channels.count() - 1
        channel = m.channels[i]
        item = root.createChild("ContentNode")
        item.title = str(i + 1) + ". " + channel.title
        item.streamUrl = channel.url
        item.logo = channel.logo
    end for

    m.channelList.content = root
    m.channelList.visible = true
    m.channelList.setFocus(true)
end sub

sub onChannelSelected()
    idx = m.channelList.itemSelected
    if idx >= 0 and idx < m.channels.count()
        playChannel(m.channels[idx])
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
end sub

sub onVideoStateChanged()
    state = m.videoPlayer.state
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
end sub

function onKeyEvent(key as String, press as Boolean) as Boolean
    if not press then return false

    if key = "back" and m.videoPlayer.visible
        m.videoPlayer.control = "stop"
        m.videoPlayer.visible = false
        m.channelList.visible = true
        m.channelList.setFocus(true)
        return true
    end if

    return false
end function
