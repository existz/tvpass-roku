sub init()
    m.overlay = m.top.findNode("overlay")
    m.menuBackground = m.top.findNode("menuBackground")
    m.menuTitle = m.top.findNode("menuTitle")
    m.channelList = m.top.findNode("channelList")
    
    m.channelList.observeField("itemSelected", "onChannelSelected")
    
    ' Observe channels field
    m.top.observeField("channels", "onChannelsChanged")
    m.top.observeField("visible", "onVisibleChanged")
    m.top.observeField("currentChannelIndex", "onCurrentChannelIndexChanged")
    
    ' Animate in from right
    m.slideAnimation = createObject("roSGNode", "Animation")
    m.slideAnimation.duration = 0.3
    m.slideAnimation.easeFunction = "outCubic"
    
    m.fadeAnimation = createObject("roSGNode", "Animation")
    m.fadeAnimation.duration = 0.3
    m.fadeAnimation.easeFunction = "linear"
end sub

sub onVisibleChanged()
    isVisible = m.top.visible
    if isVisible
        ' When menu becomes visible, jump to current channel
        if m.top.currentChannelIndex >= 0 and m.channelList.content <> invalid
            itemCount = m.channelList.content.getChildCount()
            if m.top.currentChannelIndex < itemCount
                m.channelList.jumpToItem = m.top.currentChannelIndex
                m.channelList.animateToItem = m.top.currentChannelIndex
            end if
        end if
        m.channelList.setFocus(true)
    end if
end sub

sub onCurrentChannelIndexChanged()
    ' When current channel changes, update the jump position if menu is visible
    if m.top.visible and m.top.currentChannelIndex >= 0 and m.channelList.content <> invalid
        itemCount = m.channelList.content.getChildCount()
        if m.top.currentChannelIndex < itemCount
            m.channelList.jumpToItem = m.top.currentChannelIndex
        end if
    end if
end sub

sub onChannelsChanged()
    channels = m.top.channels
    if channels = invalid or channels.count() = 0 then
        return
    end if
    
    content = createObject("roSGNode", "ContentNode")
    
    for i = 0 to channels.count() - 1
        channel = channels[i]
        item = content.createChild("ContentNode")
        
        ' Use nowPlaying if available, otherwise use title
        if channel.nowPlaying <> invalid and channel.nowPlaying <> ""
            item.title = channel.nowPlaying
        else
            item.title = channel.title
        end if
        
        if channel.logo <> invalid and channel.logo <> ""
            item.addField("logo", "string", false)
            item.logo = channel.logo
        else
            print "ChannelMenu: Channel " + str(i) + " NO logo"
        end if
        
        if channel.channelNumber <> invalid
            item.addField("channelNumber", "integer", false)
            item.channelNumber = channel.channelNumber
        end if
        
        if channel.nowPlaying <> invalid
            item.addField("nowPlaying", "string", false)
            item.nowPlaying = channel.nowPlaying
        end if

        if channel.programDetails <> invalid and channel.programDetails <> ""
            ' Add program details if available
            item.addField("programDetails", "string", false)
            item.programDetails = channel.programDetails
        else
            item.addField("programDetails", "string", false)
            item.programDetails = "Unavailable"
        end if
        
        item.addField("channelIndex", "integer", false)
        item.channelIndex = i
    end for
    
    m.channelList.content = content
    
    ' Jump to current channel after content is set
    if m.top.currentChannelIndex >= 0 and m.top.currentChannelIndex < channels.count()
        m.channelList.jumpToItem = m.top.currentChannelIndex
        ' Force the item to be focused to trigger visual feedback
        m.channelList.itemFocused = m.top.currentChannelIndex
    end if
end sub

sub onChannelSelected()
    selectedIdx = m.channelList.itemSelected
    if selectedIdx >= 0
        ' Get the actual channel index from content
        item = m.channelList.content.getChild(selectedIdx)
        if item <> invalid and item.channelIndex <> invalid
            m.top.selectedChannel = item.channelIndex
        end if
    end if
end sub

sub show()
    m.top.visible = true
    ' Force focus on the channel list
    m.channelList.setFocus(true)
end sub

sub hide()
    m.top.visible = false
end sub

function onKeyEvent(key as String, press as Boolean) as Boolean
    if not press then return false
    
    ' Let the list handle navigation keys
    if key = "up" or key = "down"
        return false ' Let the list handle it
    end if
    
    if key = "OK"
        return false ' Let the list handle selection
    end if
    
    return false
end function