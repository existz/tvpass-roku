sub init()
    m.mainVideo = m.top.findNode("mainVideo")
    m.thumbnailContainer = m.top.findNode("thumbnailContainer")
    m.mainChannelLabel = m.top.findNode("mainChannelLabel")
    
    m.thumbnails = []
    m.thumbnailChannelIndices = []
    m.channels = []
    m.currentMainIndex = 0
    m.selectedThumbnailIndex = 0
    m.visibleThumbnailCount = 0

    ' Create 5 thumbnail slots
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
    yPos = 10 + (index * 185)
    thumb = {
        index: index
        yPos: yPos
        background: invalid
        border: invalid
        logo: invalid
        label: invalid
    }

    ' Background
    bg = createObject("roSGNode", "Rectangle")
    bg.translation = [10, yPos]
    bg.width = 360
    bg.height = 180
    bg.color = "0x1A1A1AFF"
    bg.visible = false
    m.thumbnailContainer.appendChild(bg)
    thumb.background = bg

    ' Border
    border = createObject("roSGNode", "Rectangle")
    border.translation = [10, yPos]
    border.width = 360
    border.height = 180
    border.color = "0x0078D4FF"
    border.opacity = 0
    border.visible = false
    m.thumbnailContainer.appendChild(border)
    thumb.border = border

    ' Channel logo
    logo = createObject("roSGNode", "Poster")
    logo.translation = [10 + 90, yPos + 15]
    logo.width = 180
    logo.height = 100
    logo.horizAlign = "center"
    logo.vertAlign = "center"
    logo.loadDisplayMode = "scaleToFit"
    logo.visible = false
    m.thumbnailContainer.appendChild(logo)
    thumb.logo = logo

    ' Now Playing label
    label = createObject("roSGNode", "Label")
    label.translation = [10, yPos + 125]
    label.width = 360
    label.height = 50
    label.font = "font:SmallBoldSystemFont"
    label.font.size = 26
    label.color = "0xCCCCCCFF"
    label.horizAlign = "center"
    label.vertAlign = "center"
    label.wrap = true
    label.visible = false
    m.thumbnailContainer.appendChild(label)
    thumb.label = label

    return thumb
end function

sub onVisibleChanged()
    if m.top.visible
        if m.channels.count() > 0
            m.selectedThumbnailIndex = 0
            playMainChannel(0)
        end if
        m.top.setFocus(true)
    else
        stopPlayback()
    end if
end sub

sub onChannelsChanged()
    m.channels = m.top.channels
    if m.channels = invalid or m.channels.count() = 0 then return

    if m.top.visible
        m.currentMainIndex = 0
        m.selectedThumbnailIndex = 0
        playMainChannel(0)
    end if
end sub

sub playMainChannel(index as Integer)
    if index < 0 or index >= m.channels.count() then return

    m.currentMainIndex = index
    channel = m.channels[index]

    ' Update main video
    content = createObject("roSGNode", "ContentNode")
    content.url = channel.url
    content.streamFormat = "hls"
    m.mainVideo.content = content
    m.mainVideo.control = "play"

    ' Update label with nowPlaying if available
    labelText = channel.title
    if channel.doesExist("nowPlaying") and channel.nowPlaying <> invalid and channel.nowPlaying <> ""
        labelText = channel.nowPlaying
    end if
    m.mainChannelLabel.text = labelText

    ' Update thumbnails
    updateThumbnails()
end sub

sub updateThumbnails()
    thumbIndex = 0

    ' Loop through channels and fill up to 5 thumbnails
    for i = 0 to m.channels.count() - 1
        ' Skip main channel and limit to 5 thumbnails
        if i <> m.currentMainIndex and thumbIndex <= 4 then

            channel = m.channels[i]
            thumb = m.thumbnails[thumbIndex]

            ' --- Update logo ---
            if channel.doesExist("logo") and channel.logo <> invalid and channel.logo <> "" then
                if thumb.logo.uri <> channel.logo then thumb.logo.uri = channel.logo
            else
                if thumb.logo.uri <> "" then thumb.logo.uri = ""
            end if

            ' --- Update label / Now Playing ---
            nowPlaying = channel.title
            if channel.doesExist("nowPlaying") then
                if channel.nowPlaying <> invalid and channel.nowPlaying <> "" then
                    nowPlaying = channel.nowPlaying
                end if
            end if
            if thumb.label.text <> nowPlaying then thumb.label.text = nowPlaying

            ' --- Store channel index ---
            m.thumbnailChannelIndices[thumbIndex] = i

            ' --- Update selection border ---
            if thumbIndex = m.selectedThumbnailIndex then
                thumb.border.opacity = 1.0
            else
                thumb.border.opacity = 0
            end if

            ' --- Show thumbnail components ---
            thumb.background.visible = true
            thumb.border.visible = true
            thumb.logo.visible = true
            thumb.label.visible = true

            thumbIndex = thumbIndex + 1
        end if

        ' Stop if we filled all 5 thumbnails
        if thumbIndex > 4 then exit for
    end for

    ' Hide any remaining unused thumbnails
    for i = thumbIndex to 4
        thumb = m.thumbnails[i]
        thumb.background.visible = false
        thumb.border.visible = false
        thumb.logo.visible = false
        thumb.label.visible = false
        m.thumbnailChannelIndices[i] = -1
    end for

    ' Cache count of visible thumbnails
    m.visibleThumbnailCount = thumbIndex
end sub

sub swapToThumbnail(thumbIndex as Integer)
    if thumbIndex < 0 or thumbIndex >= m.visibleThumbnailCount then return

    newChannelIndex = m.thumbnailChannelIndices[thumbIndex]
    if newChannelIndex < 0 or newChannelIndex >= m.channels.count() then return

    ' Update border selection
    m.thumbnails[m.selectedThumbnailIndex].border.opacity = 0
    m.selectedThumbnailIndex = thumbIndex
    m.thumbnails[m.selectedThumbnailIndex].border.opacity = 1

    ' Play new main channel
    m.mainVideo.control = "stop"
    playMainChannel(newChannelIndex)
end sub

sub onMainVideoStateChange()
    if m.mainVideo.state = "error"
        errorCode = m.mainVideo.errorCode
    end if
end sub

sub stopPlayback()
    m.mainVideo.control = "stop"
end sub

sub selectPreviousThumbnail()
    if m.selectedThumbnailIndex > 0
        m.selectedThumbnailIndex = m.selectedThumbnailIndex - 1
        updateThumbnails()
    end if
end sub

sub selectNextThumbnail()
    if m.selectedThumbnailIndex < m.visibleThumbnailCount - 1
        m.selectedThumbnailIndex = m.selectedThumbnailIndex + 1
        updateThumbnails()
    end if
end sub

function onKeyEvent(key as String, press as Boolean) as Boolean
    if not press then return false

    if key = "back"
        m.top.visible = false
        return true
    else if key = "up"
        selectPreviousThumbnail()
        return true
    else if key = "down"
        selectNextThumbnail()
        return true
    else if key = "OK" or key = "right"
        swapToThumbnail(m.selectedThumbnailIndex)
        return true
    end if

    return false
end function