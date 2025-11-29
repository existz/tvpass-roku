sub init()
    m.mainVideo = m.top.findNode("mainVideo")
    m.thumbnailContainer = m.top.findNode("thumbnailContainer")
    m.mainChannelLabel = m.top.findNode("mainChannelLabel")
    
    m.thumbnails = []
    m.thumbnailChannelIndices = []
    m.channels = []
    m.currentMainIndex = 0
    m.selectedThumbnailIndex = 0
    
    ' Create 5 thumbnail slots - with absolute positioning
    for i = 0 to 4
        thumb = createThumbnail(i)
        m.thumbnails.push(thumb)
        m.thumbnailChannelIndices.push(-1)
    end for
    
    m.mainVideo.observeField("state", "onMainVideoStateChange")
    
    m.top.observeField("channels", "onChannelsChanged")
    m.top.observeField("visible", "onVisibleChanged")
end sub

function createThumbnail(index as Integer) as Object
    ' Calculate position for this thumbnail
    yPos = 10 + (index * 185)
    
    ' Create a structure to hold all the nodes for this thumbnail
    thumb = {
        index: index
        yPos: yPos
        background: invalid
        border: invalid
        logoBg: invalid
        logo: invalid
        label: invalid
        visible: false
    }
    
    ' Background rectangle
    bg = createObject("roSGNode", "Rectangle")
    bg.translation = [10, yPos]
    bg.width = 360
    bg.height = 180
    bg.color = "0x1A1A1AFF"
    bg.id = "bg_" + str(index)
    bg.visible = false
    m.thumbnailContainer.appendChild(bg)
    thumb.background = bg
    
    ' Border for selection
    border = createObject("roSGNode", "Rectangle")
    border.translation = [10, yPos]
    border.width = 360
    border.height = 180
    border.color = "0x0078D4FF"
    border.opacity = 0
    border.id = "border_" + str(index)
    border.visible = false
    m.thumbnailContainer.appendChild(border)
    thumb.border = border
    
    ' Channel logo - centered horizontally in the 360px box
    logo = createObject("roSGNode", "Poster")
    logo.translation = [10 + 90, yPos + 15]  ' 10px left margin + (360-180)/2 = 100 for centering 180px logo
    logo.width = 180
    logo.height = 100
    logo.horizAlign = "center"
    logo.vertAlign = "center"
    logo.loadDisplayMode = "scaleToFit"
    logo.id = "logo_" + str(index)
    logo.visible = false
    m.thumbnailContainer.appendChild(logo)
    thumb.logo = logo
    thumb.logoBg = invalid  ' Don't need background anymore
    
    ' Now Playing label - centered below logo
    label = createObject("roSGNode", "Label")
    label.translation = [10, yPos + 125]  ' Start after logo (15 + 100 + 10 spacing)
    label.width = 360
    label.height = 50
    label.font = "font:SmallBoldSystemFont"
    label.font.size = 26
    label.color = "0xCCCCCCFF"
    label.horizAlign = "center"
    label.vertAlign = "center"
    label.wrap = true
    label.id = "label_" + str(index)
    label.visible = false
    m.thumbnailContainer.appendChild(label)
    thumb.label = label
    
    print "MultiviewGrid: Created thumbnail "; index; " at y="; yPos
    
    return thumb
end function

sub onVisibleChanged()
    print "MultiviewGrid: onVisibleChanged - visible = "; m.top.visible
    if m.top.visible
        if m.channels.count() > 0
            m.selectedThumbnailIndex = 0
            playMainChannel(0)
            updateThumbnails()
        end if
        m.top.setFocus(true)
        print "MultiviewGrid: Focus set, ready for key events"
    else
        stopPlayback()
    end if
end sub

sub onChannelsChanged()
    m.channels = m.top.channels
    print "MultiviewGrid: onChannelsChanged - received "; m.channels.count(); " channels"
    
    if m.channels = invalid or m.channels.count() = 0 then
        print "MultiviewGrid: No channels to display"
        return
    end if
    
    ' Debug: Print channel data
    for i = 0 to m.channels.count() - 1
        channel = m.channels[i]
        print "MultiviewGrid: Channel "; i; ": title="; channel.title
        if channel.logo <> invalid then
            print "MultiviewGrid: Channel "; i; " logo="; channel.logo
        else
            print "MultiviewGrid: Channel "; i; " has no logo"
        end if
    end for
    
    if m.top.visible
        m.currentMainIndex = 0
        m.selectedThumbnailIndex = 0
        playMainChannel(0)
        updateThumbnails()
    end if
end sub

sub playMainChannel(index as Integer)
    if index < 0 or index >= m.channels.count() then return
    
    m.currentMainIndex = index
    channel = m.channels[index]
    
    print "MultiviewGrid: Playing main channel: "; channel.title
    
    ' Update main video
    content = createObject("roSGNode", "ContentNode")
    content.url = channel.url
    content.title = channel.title
    content.streamFormat = "hls"
    
    m.mainVideo.content = content
    m.mainVideo.control = "play"
    
    ' Update main label
    m.mainChannelLabel.text = channel.title
    
    ' Update thumbnails to reflect current main
    updateThumbnails()
end sub

sub updateThumbnails()
    print "MultiviewGrid: updateThumbnails START"
    print "MultiviewGrid: Main index = "; m.currentMainIndex
    print "MultiviewGrid: Total channels = "; m.channels.count()
    print "MultiviewGrid: Selected thumbnail = "; m.selectedThumbnailIndex
    
    ' Hide all thumbnails first
    for i = 0 to 4
        thumb = m.thumbnails[i]
        thumb.background.visible = false
        thumb.border.visible = false
        if thumb.logoBg <> invalid then thumb.logoBg.visible = false
        thumb.logo.visible = false
        thumb.label.visible = false
        thumb.visible = false
        m.thumbnailChannelIndices[i] = -1
    end for
    
    ' Show thumbnails for other channels (not the main one)
    thumbIndex = 0
    for i = 0 to m.channels.count() - 1
        if i <> m.currentMainIndex and thumbIndex < 5
            channel = m.channels[i]
            thumb = m.thumbnails[thumbIndex]
            
            print "MultiviewGrid: Setting up thumbnail "; thumbIndex; " for channel "; i
            
            ' Set logo
            if channel.logo <> invalid and channel.logo <> ""
                print "MultiviewGrid: Setting logo: "; channel.logo
                thumb.logo.uri = channel.logo
            else
                print "MultiviewGrid: No logo for this channel"
                thumb.logo.uri = ""
            end if
            
            ' Set label to show what's currently playing
            ' Get the "nowPlaying" field from the channel if it exists
            nowPlaying = ""
            if channel.doesExist("nowPlaying") and channel.nowPlaying <> invalid and channel.nowPlaying <> ""
                nowPlaying = channel.nowPlaying
            else if channel.doesExist("title")
                nowPlaying = channel.title
            end if
            
            thumb.label.text = nowPlaying
            print "MultiviewGrid: Set now playing: "; nowPlaying
            
            ' Store channel index
            m.thumbnailChannelIndices[thumbIndex] = i
            
            ' Update selection border
            if thumbIndex = m.selectedThumbnailIndex
                thumb.border.opacity = 1.0
                print "MultiviewGrid: Thumbnail "; thumbIndex; " is SELECTED"
            else
                thumb.border.opacity = 0
            end if
            
            ' Show all components (no red background anymore)
            thumb.background.visible = true
            thumb.border.visible = true
            thumb.logo.visible = true
            thumb.label.visible = true
            thumb.visible = true
            
            print "MultiviewGrid: Thumbnail "; thumbIndex; " made visible at y="; thumb.yPos
            
            thumbIndex = thumbIndex + 1
        end if
    end for
    
    print "MultiviewGrid: updateThumbnails END - displayed "; thumbIndex; " thumbnails"
end sub

sub swapToThumbnail(thumbIndex as Integer)
    print "MultiviewGrid: swapToThumbnail("; thumbIndex; ")"
    
    if thumbIndex < 0 or thumbIndex >= 5 then
        print "MultiviewGrid: Invalid thumb index"
        return
    end if
    
    thumb = m.thumbnails[thumbIndex]
    if not thumb.visible then
        print "MultiviewGrid: Thumbnail not visible"
        return
    end if
    
    ' Get channel index
    channelIndex = m.thumbnailChannelIndices[thumbIndex]
    if channelIndex < 0 or channelIndex >= m.channels.count() then
        print "MultiviewGrid: Invalid channel index: "; channelIndex
        return
    end if
    
    print "MultiviewGrid: Swapping to channel "; channelIndex
    
    ' Reset selection to top BEFORE playing
    m.selectedThumbnailIndex = 0
    
    ' Stop current playback
    m.mainVideo.control = "stop"
    
    ' Play the selected channel (this will call updateThumbnails)
    playMainChannel(channelIndex)
end sub

sub onMainVideoStateChange()
    state = m.mainVideo.state
    print "MultiviewGrid: Main video state: "; state
    
    if state = "error"
        errorCode = m.mainVideo.errorCode
        print "MultiviewGrid: Main video error code: "; errorCode
    end if
end sub

sub stopPlayback()
    print "MultiviewGrid: Stopping playback"
    m.mainVideo.control = "stop"
end sub

sub selectPreviousThumbnail()
    print "MultiviewGrid: selectPreviousThumbnail - current="; m.selectedThumbnailIndex
    if m.selectedThumbnailIndex > 0
        m.selectedThumbnailIndex = m.selectedThumbnailIndex - 1
        print "MultiviewGrid: Moving to thumbnail "; m.selectedThumbnailIndex
        updateThumbnails()
    else
        print "MultiviewGrid: Already at first thumbnail"
    end if
end sub

sub selectNextThumbnail()
    ' Count visible thumbnails
    visibleCount = 0
    for each thumb in m.thumbnails
        if thumb.visible then visibleCount = visibleCount + 1
    end for
    
    print "MultiviewGrid: selectNextThumbnail - current="; m.selectedThumbnailIndex; " visibleCount="; visibleCount
    
    if visibleCount > 0 and m.selectedThumbnailIndex < visibleCount - 1
        m.selectedThumbnailIndex = m.selectedThumbnailIndex + 1
        print "MultiviewGrid: Moving to thumbnail "; m.selectedThumbnailIndex
        updateThumbnails()
    else
        print "MultiviewGrid: Already at last thumbnail"
    end if
end sub

function onKeyEvent(key as String, press as Boolean) as Boolean
    if not press then return false
    
    print "MultiviewGrid: Key pressed: "; key; " (focus="; m.top.hasFocus(); ")"
    
    if key = "back"
        print "MultiviewGrid: Back pressed, hiding"
        m.top.visible = false
        return true
    end if
    
    if key = "up"
        print "MultiviewGrid: Up pressed"
        selectPreviousThumbnail()
        return true
    end if
    
    if key = "down"
        print "MultiviewGrid: Down pressed"
        selectNextThumbnail()
        return true
    end if
    
    if key = "OK" or key = "right"
        print "MultiviewGrid: OK/Right pressed, swapping thumbnail "; m.selectedThumbnailIndex
        swapToThumbnail(m.selectedThumbnailIndex)
        return true
    end if
    
    print "MultiviewGrid: Unhandled key: "; key
    return false
end function