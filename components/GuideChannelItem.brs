sub init()
    m.background = m.top.findNode("background")
    m.channelNumber = m.top.findNode("channelNumber")
    m.channelLogo = m.top.findNode("channelLogo")
    m.programSlots = m.top.findNode("programSlots")
    setUnfocusedState()
end sub

sub onContentChanged()
    content = m.top.itemContent
    if content <> invalid
        ' Set channel number
        if content.channelNumber <> invalid
            m.channelNumber.text = str(content.channelNumber)
        end if
        
        ' Set channel logo (larger, replaces name)
        if content.logo <> invalid and content.logo <> ""
            m.channelLogo.uri = content.logo
            m.channelLogo.visible = true
        else
            m.channelLogo.uri = ""
            m.channelLogo.visible = false
        end if
        
        ' Create program slots
        isLongName = false
        if content.doesExist("isLongChannelName")
            isLongName = content.isLongChannelName
        end if
        createProgramSlots(content, isLongName)
    end if
    setUnfocusedState()
end sub

sub createProgramSlots(content as Object, isLongName as Boolean)
    ' Clear existing slots
    m.programSlots.removeChildrenIndex(m.programSlots.getChildCount(), 0)
    
    ' Get current UTC time and calculate time window - match header logic
    ' Program times from EPG are in UTC seconds
    now = CreateObject("roDateTime")
    currentTime = now.AsSeconds()
    
    ' Round down to nearest 30-minute interval
    ' 1800 seconds = 30 minutes
    windowStartTime = int(currentTime / 1800) * 1800
    
    ' 1.5 hour window (3 x 30-minute blocks)
    windowEndTime = windowStartTime + (1.5 * 3600)
    slotWidth = 517
    totalWidth = slotWidth * 3
    
    ' Get programs for this channel
    programs = []
    if content.programs <> invalid
        programs = content.programs
    end if
    
    ' Initialize counters
    debugCount = 0
    totalProgramsChecked = 0
    totalProgramsRendered = 0
    
    ' If no programs but nowPlaying, create a synthetic program spanning the full window
    if programs.count() = 0 and content.nowPlaying <> invalid and content.nowPlaying <> ""
        syntheticProgram = {
            title: content.nowPlaying,
            startTime: windowStartTime,
            endTime: windowEndTime
        }
        programs.push(syntheticProgram)
    end if
    
    ' Create blocks for each program
    for each program in programs
        if program <> invalid and program.title <> invalid
            progStart = invalid
            progEnd = invalid
            
            ' Try to get time fields
            if program.startTime <> invalid
                progStart = program.startTime
            end if
            if program.endTime <> invalid
                progEnd = program.endTime
            end if
            
            if progStart = invalid or progEnd = invalid
                ' Skip programs without valid times
                goto nextProgram
            end if
            
            ' Show programs that overlap with the display window
            if progStart < windowEndTime and progEnd > windowStartTime
                
                ' Clamp to window
                displayStart = progStart
                displayEnd = progEnd
                if displayStart < windowStartTime
                    displayStart = windowStartTime
                end if
                if displayEnd > windowEndTime
                    displayEnd = windowEndTime
                end if
                
                ' Calculate position and width based on time
                offset = ((displayStart - windowStartTime) * totalWidth) / (1.5 * 3600)
                width = ((displayEnd - displayStart) * totalWidth) / (1.5 * 3600)
                
                ' Create program block
                slot = createObject("roSGNode", "Rectangle")
                slot.translation = [offset, 0]
                slot.width = width
                slot.height = 75
                slot.color = "0x2A2A2AFF"
                
                ' Create label for program
                label = createObject("roSGNode", "Label")
                slotHeight = 75
                labelHeight = 30
                verticalPadding = (slotHeight - labelHeight) / 2
                label.translation = [5, verticalPadding]
                labelWidth = width - 10
                if labelWidth < 1 then labelWidth = 1
                label.width = labelWidth
                label.height = labelHeight
                label.text = program.title
                label.font = "font:SmallSystemFont"
                label.color = "0xCCCCCCFF"
                label.horizAlign = "left"
                label.vertAlign = "center"
                label.wrap = false
                
                ' Truncate text based on block width (35 chars per 517px)
                maxChars = int((width / 517.0) * 35)
                if maxChars < 10 then maxChars = 10
                if len(program.title) > maxChars
                    label.text = left(program.title, maxChars - 3) + "..."
                end if
                
                slot.appendChild(label)
                m.programSlots.appendChild(slot)
            end if
            
            nextProgram:
        end if
    end for
    
end sub

sub onFocusPercentChanged()
    fp = m.top.focusPercent
    if fp > 0
        setFocusedState(fp)
    else
        setUnfocusedState()
    end if
end sub

sub onWidthChanged()
    w = m.top.width
    m.background.width = w
end sub

sub setFocusedState(p as Float)
    bg = interpolateColor(&h1A1A1AFF, &h0078D4FF, p)
    m.background.color = bg
end sub

sub setUnfocusedState()
    m.background.color = "0x1A1A1AFF"
end sub

function interpolateColor(c1 as Integer, c2 as Integer, t as Float) as String
    a1 = (c1 >> 24) and 255
    r1 = (c1 >> 16) and 255
    g1 = (c1 >> 8)  and 255
    b1 = c1 and 255

    a2 = (c2 >> 24) and 255
    r2 = (c2 >> 16) and 255
    g2 = (c2 >> 8)  and 255
    b2 = c2 and 255

    a = a1 + (a2 - a1) * t
    r = r1 + (r2 - r1) * t
    g = g1 + (g2 - g1) * t
    b = b1 + (b2 - b1) * t

    return "0x" + byteToHex(a) + byteToHex(r) + byteToHex(g) + byteToHex(b)
end function

function byteToHex(b as Integer) as String
    hex = "0123456789ABCDEF"
    return mid(hex, (b \ 16) + 1, 1) + mid(hex, (b mod 16) + 1, 1)
end function