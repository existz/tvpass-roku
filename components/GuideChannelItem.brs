sub init()
    m.background = m.top.findNode("background")
    m.channelNumber = m.top.findNode("channelNumber")
    m.channelLogo = m.top.findNode("channelLogo")
    m.programSlots = m.top.findNode("programSlots")
    m.uiColors = GetUIColors()

    ' Pre-compile sports keywords for faster matching - use shared function
    m.sportsKeywords = GetSportsKeywords()

    setUnfocusedState()
end sub

sub onContentChanged()
    content = m.top.itemContent
    if content <> invalid
        if content.channelNumber <> invalid
            m.channelNumber.text = str(content.channelNumber)
            m.channelNumber.horizAlign = "center"
        end if

        if content.logo <> invalid and content.logo <> ""
            m.channelLogo.uri = content.logo
            m.channelLogo.visible = true
        else
            m.channelLogo.uri = ""
            m.channelLogo.visible = false
        end if

        isLongName = false
        if content.doesExist("isLongChannelName")
            isLongName = content.isLongChannelName
        end if
        createProgramSlots(content, isLongName)
    end if
    setUnfocusedState()
end sub

sub createProgramSlots(content as Object, isLongName as Boolean)
    m.programSlots.removeChildrenIndex(m.programSlots.getChildCount(), 0)

    now = CreateObject("roDateTime")
    currentTime = now.AsSeconds()

    windowStartTime = int(currentTime / 1800) * 1800
    windowEndTime = windowStartTime + 5400  ' 1.5 hours
    slotWidth = 517
    totalWidth = slotWidth * 3

    ' Pre-calculate time scale factor
    timeScale = totalWidth / 5400.0

    programs = []
    if content.programs <> invalid
        programs = content.programs
    end if

    if programs.count() = 0 and content.nowPlaying <> invalid and content.nowPlaying <> ""
        syntheticProgram = {
            title: content.nowPlaying,
            startTime: windowStartTime,
            endTime: windowEndTime
        }
        programs.push(syntheticProgram)
    end if

    for each program in programs
        if program <> invalid and program.title <> invalid
            progStart = program.startTime
            progEnd = program.endTime

            if progStart = invalid or progEnd = invalid then goto nextProgram

            if progStart < windowEndTime and progEnd > windowStartTime
                displayStart = progStart
                displayEnd = progEnd
                if displayStart < windowStartTime then displayStart = windowStartTime
                if displayEnd > windowEndTime then displayEnd = windowEndTime

                ' Use pre-calculated time scale
                offset = (displayStart - windowStartTime) * timeScale
                width = (displayEnd - displayStart) * timeScale

                slot = createObject("roSGNode", "Rectangle")
                slot.translation = [offset, 0]
                slot.width = width
                slot.height = 75
                slot.color = m.uiColors.BLACK26

                displayText = program.title
                isSportsProgram = IsSportsProgram(program.title, m.sportsKeywords)

                if isSportsProgram and program.subTitle <> invalid and program.subTitle <> ""
                    displayText = program.subTitle
                end if

                label = createObject("roSGNode", "Label")
                slotHeight = 75
                labelHeight = 30
                verticalPadding = (slotHeight - labelHeight) / 2
                label.translation = [5, verticalPadding]
                labelWidth = width - 10
                if labelWidth < 1 then labelWidth = 1
                label.width = labelWidth
                label.height = labelHeight
                label.text = displayText
                label.font = "font:SmallSystemFont"
                label.color = m.uiColors.LIGHT_GRAY
                label.horizAlign = "left"
                label.vertAlign = "center"
                label.wrap = false

                maxChars = int((width / 517.0) * 35)
                if maxChars < 10 then maxChars = 10
                if len(displayText) > maxChars
                    label.text = left(displayText, maxChars - 3) + "..."
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
    m.background.color = m.uiColors.BLACK26
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

    ' Use array join instead of concatenation
    colorParts = ["0x", byteToHex(a), byteToHex(r), byteToHex(g), byteToHex(b)]
    return colorParts.Join("")
end function

function byteToHex(b as Integer) as String
    hex = "0123456789ABCDEF"
    return mid(hex, (b \ 16) + 1, 1) + mid(hex, (b mod 16) + 1, 1)
end function