sub init()
    m.overlay = m.top.findNode("overlay")
    m.menuBackground = m.top.findNode("menuBackground")
    m.menuTitle = m.top.findNode("menuTitle")
    m.channelList = m.top.findNode("channelList")
    m.instructionLabel = m.top.findNode("instructionLabel")
    
    ' Don't observe itemSelected initially - we'll handle it manually
    ' m.channelList.observeField("itemSelected", "onChannelSelected")
    
    ' Multiview state
    m.selectedChannels = []
    m.maxMultiviewChannels = 6
    m.okButtonPressTime = 0
    m.longPressThreshold = 500
    m.isLongPress = false
    
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
        ' Reset multiview selection when menu opens
        m.selectedChannels = []
        m.isLongPress = false
        updateInstructionLabel()
        
        ' When menu becomes visible, jump to current channel
        if m.top.currentChannelIndex >= 0 and m.channelList.content <> invalid
            itemCount = m.channelList.content.getChildCount()
            if m.top.currentChannelIndex < itemCount
                m.channelList.jumpToItem = m.top.currentChannelIndex
                m.channelList.animateToItem = m.top.currentChannelIndex
            end if
        end if
        
        ' Make sure menu component itself can receive key events
        m.top.setFocus(true)
        m.channelList.setFocus(true)
    end if
end sub

sub updateInstructionLabel()
    numSelected = m.selectedChannels.count()
    if numSelected = 0
        m.instructionLabel.text = "Select channel or long-press OK for Picture-in-Picture"
    else if numSelected < m.maxMultiviewChannels
        m.instructionLabel.text = "Selected " + str(numSelected) + "/" + str(m.maxMultiviewChannels) + " - Press Back for PiP mode"
    else
        m.instructionLabel.text = "Max channels selected - Press Back for PiP mode"
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
            item.addField("programDetails", "string", false)
            item.programDetails = channel.programDetails
        else
            item.addField("programDetails", "string", false)
            item.programDetails = "Unavailable"
        end if
        
        item.addField("channelIndex", "integer", false)
        item.channelIndex = i
        
        item.addField("isSelected", "boolean", false)
        item.isSelected = false
    end for
    
    m.channelList.content = content
    
    ' Jump to current channel after content is set
    if m.top.currentChannelIndex >= 0 and m.top.currentChannelIndex < channels.count()
        m.channelList.jumpToItem = m.top.currentChannelIndex
        m.channelList.itemFocused = m.top.currentChannelIndex
    end if
end sub

sub playSelectedChannel()
    focusedIdx = m.channelList.itemFocused
    if focusedIdx >= 0
        item = m.channelList.content.getChild(focusedIdx)
        if item <> invalid and item.channelIndex <> invalid
            m.top.selectedChannel = item.channelIndex
        end if
    end if
end sub

sub toggleChannelSelection(channelIndex as Integer)
    ' Check if already selected
    alreadySelected = false
    selectedIndex = -1
    
    for i = 0 to m.selectedChannels.count() - 1
        if m.selectedChannels[i] = channelIndex
            alreadySelected = true
            selectedIndex = i
            exit for
        end if
    end for
    
    if alreadySelected
        ' Remove from selection
        newSelection = []
        for i = 0 to m.selectedChannels.count() - 1
            if i <> selectedIndex
                newSelection.push(m.selectedChannels[i])
            end if
        end for
        m.selectedChannels = newSelection
    else
        ' Add to selection if under limit
        if m.selectedChannels.count() < m.maxMultiviewChannels
            m.selectedChannels.push(channelIndex)
        end if
    end if
    
    updateInstructionLabel()
    updateSelectionIndicators()
end sub

sub updateSelectionIndicators()
    ' Update visual indicators for all items
    if m.channelList.content = invalid then return
    
    itemCount = m.channelList.content.getChildCount()
    for i = 0 to itemCount - 1
        item = m.channelList.content.getChild(i)
        if item <> invalid and item.channelIndex <> invalid
            isSelected = false
            for each selectedIdx in m.selectedChannels
                if selectedIdx = item.channelIndex
                    isSelected = true
                    exit for
                end if
            end for
            
            if item.doesExist("isSelected")
                item.isSelected = isSelected
            end if
        end if
    end for
    
    ' Force list to refresh items
    m.channelList.itemFocused = m.channelList.itemFocused
end sub

sub show()
    m.top.visible = true
    m.top.setFocus(true)  ' Set focus on the menu itself
    m.channelList.setFocus(true)  ' Then set focus on the list
end sub

sub hide()
    m.top.visible = false
end sub

function onKeyEvent(key as String, press as Boolean) as Boolean
    dt = CreateObject("roDateTime")
    currentTime& = dt.AsSeconds()
    currentTimeMs& = (currentTime& * 1000) + dt.GetMilliseconds()
    
    ' Only handle key press, not release for most keys
    if key = "back"
        if press
            ' If channels are selected, launch multiview
            if m.selectedChannels.count() > 0
                print "SlideChannelMenu: Launching multiview with " + str(m.selectedChannels.count()) + " selected channels"
                
                ' Build final list including initial channel if not already selected
                finalChannels = []
                
                ' Add initial channel first (the one that was playing when menu opened)
                if m.top.initialChannelIndex >= 0
                    alreadyIncluded = false
                    for each idx in m.selectedChannels
                        if idx = m.top.initialChannelIndex
                            alreadyIncluded = true
                            exit for
                        end if
                    end for
                    if not alreadyIncluded
                        finalChannels.push(m.top.initialChannelIndex)
                        print "SlideChannelMenu: Adding initial channel " + str(m.top.initialChannelIndex)
                    end if
                end if
                
                ' Add all selected channels
                for each idx in m.selectedChannels
                    finalChannels.push(idx)
                end for
                
                print "SlideChannelMenu: Final multiview channels: "; finalChannels
                m.top.launchMultiview = finalChannels
                m.top.visible = false
                return true
            else
                print "SlideChannelMenu: No channels selected, closing menu"
                m.top.visible = false
                return true
            end if
        end if
        return false
    end if
    
    if press
        if key = "OK"
            m.okButtonPressTime = currentTimeMs&
            m.isLongPress = false
            return true ' Consume the key press
        end if
    else
        if key = "OK" and m.okButtonPressTime > 0
            duration = currentTimeMs& - m.okButtonPressTime
            m.okButtonPressTime = 0
            
            if duration >= m.longPressThreshold
                ' Long press - toggle multiview selection
                print "SlideChannelMenu: Long press detected"
                m.isLongPress = true
                focusedIdx = m.channelList.itemFocused
                if focusedIdx >= 0
                    item = m.channelList.content.getChild(focusedIdx)
                    if item <> invalid and item.channelIndex <> invalid
                        toggleChannelSelection(item.channelIndex)
                    end if
                end if
                return true
            else
                ' Short press - play the selected channel
                print "SlideChannelMenu: Short press detected"
                if not m.isLongPress
                    playSelectedChannel()
                end if
                return true
            end if
        end if
    end if
    
    ' Let the list handle navigation keys
    if key = "up" or key = "down"
        return false
    end if
    
    return false
end function