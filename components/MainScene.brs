sub init()
    m.top.backgroundURI = "pkg:/images/background.jpg"
    m.top.backgroundColor = "0x000000"

    m.loadingLabel = m.top.findNode("loadingLabel")
    m.channelList = m.top.findNode("channelList")
    m.videoPlayer = m.top.findNode("videoPlayer")

    if m.channelList <> invalid
        m.channelList.observeField("rowItemSelected", "onChannelSelected")
    end if
    
    if m.videoPlayer <> invalid
        m.videoPlayer.observeField("state", "onVideoStateChanged")
    end if

    m.channels = []
    loadPlaylist()
end sub

sub loadPlaylist()
    if m.loadingLabel <> invalid
        m.loadingLabel.visible = true
    end if

    ' Create and setup the task
    m.playlistTask = CreateObject("roSGNode", "LoadPlaylistTask")
    if m.playlistTask <> invalid
        m.playlistTask.url = "https://tvpass.org/playlist/m3u"
        m.playlistTask.observeField("response", "onPlaylistResponse")
        m.playlistTask.observeField("error", "onPlaylistError")
        m.playlistTask.control = "RUN"
    else
        showError("Failed to create playlist task")
    end if
end sub

sub onPlaylistResponse()
    if m.playlistTask = invalid
        print "Error: playlist task is invalid"
        return
    end if
    
    response = m.playlistTask.response
    if response <> invalid and response <> ""
        print "Received playlist response, length: " + Str(Len(response))
        parseM3U(response)
        if m.channels <> invalid and m.channels.Count() > 0
            showChannelList()
        else
            showError("No channels found in playlist")
        end if
    else
        print "Error: Empty response from playlist task"
        showError("Empty playlist response")
    end if
    
    ' Clean up task
    m.playlistTask = invalid
end sub

sub onPlaylistError()
    if m.playlistTask = invalid
        return
    end if
    
    error = m.playlistTask.error
    showError("Failed to load playlist: " + error)
    ' Clean up task
    m.playlistTask = invalid
end sub

sub parseM3U(content as String)
    m.channels = []
    
    if content = invalid or content = ""
        print "Error: Empty content"
        return
    end if
    
    ' Handle different line endings
    content = content.Replace(chr(13) + chr(10), chr(10)) ' Replace CRLF with LF
    content = content.Replace(chr(13), chr(10)) ' Replace CR with LF
    
    lines = content.Split(chr(10))
    print "Starting M3U parsing, total lines: " + lines.Count().ToStr()
    
    ' Debug first few lines
    if lines.Count() > 0 then print "Line 0: " + lines[0]
    if lines.Count() > 1 then print "Line 1: " + lines[1]
    if lines.Count() > 2 then print "Line 2: " + lines[2]

    currentChannel = invalid
    channelCount = 0

    for each line in lines
        line = line.Trim()
        if line = "" then goto nextLine
        
        if line.StartsWith("#EXTINF:")
            ' Start a new channel entry
            currentChannel = {}
            
            ' Parse the EXTINF line
            commaParts = line.Split(",")
            if commaParts.Count() > 1
                currentChannel.title = commaParts[commaParts.Count() - 1].Trim()
                print "Found channel: " + currentChannel.title
                
                ' Extract tvg-logo if present
                logoPos = line.Instr("tvg-logo=")
                if logoPos >= 0
                    logoStart = logoPos + 10 ' Length of 'tvg-logo="'
                    logoEnd = line.Instr(logoStart, chr(34))
                    if logoEnd > logoStart
                        currentChannel.logo = line.Mid(logoStart, logoEnd - logoStart)
                        print "  Logo: " + currentChannel.logo
                    end if
                end if
            end if

        else if not line.StartsWith("#") and currentChannel <> invalid
            ' This should be a URL line
            currentChannel.url = line
            print "  URL: " + line
            m.channels.Push(currentChannel)
            channelCount = channelCount + 1
            print "Added channel " + Str(channelCount) + ": " + currentChannel.title
            currentChannel = invalid
        end if
        
        nextLine:
    end for

    print "Finished parsing. Found " + m.channels.Count().ToStr() + " channels"
end sub

sub showChannelList()
    print "=== Starting showChannelList ==="
    
    if m.loadingLabel <> invalid
        m.loadingLabel.visible = false
    end if
    
    if m.channelList = invalid
        print "Error: channelList is invalid"
        return
    end if
    
    if m.channels = invalid
        print "Error: channels array is invalid"
        return
    end if
    
    numChannels = m.channels.Count()
    if numChannels = 0
        print "Error: No channels to display"
        return
    end if
    
    print "Found " + Str(numChannels) + " channels to display"
    
    ' Create root content node
    contentNode = CreateObject("roSGNode", "ContentNode")
    if contentNode = invalid
        print "Error: Failed to create root ContentNode"
        return
    end if
    
    ' Calculate how many channels per row (3 columns)
    channelsPerRow = 3
    numRows = Int(numChannels / channelsPerRow)
    if numChannels Mod channelsPerRow > 0 then numRows = numRows + 1
    
    print "Creating " + Str(numRows) + " rows with " + Str(channelsPerRow) + " channels per row"
    
    ' Add all channels to rows
    channelsAdded = 0
    currentRow = invalid
    
    for i = 0 to numChannels - 1
        ' Create a new row every channelsPerRow items
        if i Mod channelsPerRow = 0
            currentRow = contentNode.createChild("ContentNode")
            if currentRow = invalid
                print "Error: Failed to create row ContentNode"
                goto nextChannel
            end if
        end if
        
        channel = m.channels[i]
        if channel = invalid
            print "Warning: Invalid channel at index " + Str(i)
            goto nextChannel
        end if
        
        if channel.title = invalid or channel.url = invalid
            print "Warning: Channel at index " + Str(i) + " missing title or URL"
            goto nextChannel
        end if
        
        item = currentRow.createChild("ContentNode")
        if item = invalid
            print "Error: Failed to create channel item node"
            goto nextChannel
        end if
        
        item.title = channel.title
        item.url = channel.url
        if channel.logo <> invalid
            item.hdPosterUrl = channel.logo
            item.sdPosterUrl = channel.logo
        end if
        
        channelsAdded = channelsAdded + 1
        
        nextChannel:
    end for
    
    ' Debug: how many rows and items did we create
    if contentNode <> invalid then
        print "Total rows created: " + Str(contentNode.getChildCount())
        print "Total channels added: " + Str(channelsAdded)
    end if

    print "Successfully added " + Str(channelsAdded) + " channels to row"
    
    ' Only show and set focus if we added channels successfully
    if channelsAdded > 0
        m.channelList.visible = true
        m.channelList.content = contentNode
        m.channelList.setFocus(true)
        print "Channel list populated and focused"
    else
        print "Error: No valid channels were added"
        if m.loadingLabel <> invalid
            m.loadingLabel.text = "No channels available"
            m.loadingLabel.visible = true
        end if
    end if
end sub

sub onChannelSelected(event as Object)
    if event = invalid
        print "Error: Invalid selection event"
        return
    end if
    
    ' RowList returns [rowIndex, itemIndex] array
    selection = event.getData()
    print "=== Channel Selection Event ==="
    print "Selection data: " + FormatJson(selection)
    
    if m.channels = invalid
        print "Error: Channels array is invalid"
        return
    end if
    
    channelCount = m.channels.Count()
    print "Total channels available: " + Str(channelCount)
    
    ' Calculate the actual channel index from row and column
    ' We have 3 channels per row
    channelsPerRow = 3
    rowIndex = selection[0]
    itemIndex = selection[1]
    selectedIndex = (rowIndex * channelsPerRow) + itemIndex
    
    print "Row: " + Str(rowIndex) + ", Item: " + Str(itemIndex)
    print "Calculated channel index: " + Str(selectedIndex)
    
    if selectedIndex >= 0 and selectedIndex < channelCount
        channel = m.channels[selectedIndex]
        if channel <> invalid and channel.title <> invalid
            print "Playing channel " + Str(selectedIndex) + ": " + channel.title
            print "Channel URL: " + channel.url
            playChannel(channel)
        else
            print "Error: Invalid channel data at index " + Str(selectedIndex)
        end if
    else
        print "Error: Index " + Str(selectedIndex) + " out of range (0-" + Str(channelCount - 1) + ")"
    end if
end sub

sub playChannel(channel as Object)
    print "=== Starting playChannel ==="
    print "Channel title: " + channel.title
    print "Channel URL: " + channel.url
    
    m.channelList.visible = false
    m.videoPlayer.visible = true

    videoContent = CreateObject("roSGNode", "ContentNode")
    videoContent.title = channel.title
    videoContent.url = channel.url
    videoContent.streamFormat = "hls"

    print "Setting video content and starting playback"
    m.videoPlayer.content = videoContent
    m.videoPlayer.control = "play"
    m.videoPlayer.setFocus(true)
    print "Video player started"
end sub

sub onVideoStateChanged(event as Object)
    state = event.getData()
    print "Video state changed to: " + state

    if state = "error"
        showError("Playback error")
        m.videoPlayer.visible = false
        m.channelList.visible = true
        m.channelList.setFocus(true)
    end if
end sub

sub showError(message as String)
    print "=== ERROR: " + message + " ==="
    m.loadingLabel.text = "Error: " + message
    m.loadingLabel.visible = true
end sub

function onKeyEvent(key as String, press as Boolean) as Boolean
    if press
        if key = "back"
            if m.videoPlayer.visible
                print "Back button pressed - stopping video"
                m.videoPlayer.control = "stop"
                m.videoPlayer.visible = false
                m.channelList.visible = true
                m.channelList.setFocus(true)
                return true
            end if
        end if
    end if
    return false
end function