sub init()
    m.background = m.top.findNode("background")
    m.logo = m.top.findNode("logo")
    m.channelNumber = m.top.findNode("channelNumber")
    m.programTitle = m.top.findNode("programTitle")
    m.selectionIndicator = m.top.findNode("selectionIndicator")
    m.selectionIndicator.visible = false
    m.uiColors = GetUIColors()
    
    m.top.observeField("isSelected", "onSelectedChanged")
    setUnfocusedState()
end sub

sub onSelectedChanged()
    m.selectionIndicator.visible = m.top.isSelected
    if m.top.isSelected
        m.background.color = "0x0078D4FF"
    else
        if m.top.focusPercent = 0
            setUnfocusedState()
        end if
    end if
end sub

sub onContentChanged()
    content = m.top.itemContent
    if content <> invalid
        if content.doesExist("channelNumber") and content.channelNumber <> invalid
            m.channelNumber.horizAlign = "center"
            m.channelNumber.vertAlign = "center"
            m.channelNumber.font.size = 32
            m.channelNumber.text = str(content.channelNumber)
        else
            m.channelNumber.text = ""
        end if
        
        if content.logo <> invalid and content.logo <> ""
            m.logo.uri = content.logo
            m.logo.visible = true
        else
            m.logo.visible = false
        end if
        
        if content.doesExist("nowPlaying") and content.nowPlaying <> invalid and content.nowPlaying <> ""
            m.programTitle.text = content.nowPlaying
        else if content.title <> invalid
            m.programTitle.text = content.title
        else
            m.programTitle.text = ""
        end if
        
        if content.doesExist("isSelected") and content.isSelected <> invalid
            m.top.isSelected = content.isSelected
            content.observeField("isSelected", "onContentSelectedChanged")
        end if
    else
        m.channelNumber.text = ""
        m.programTitle.text = ""
    end if
    setUnfocusedState()
end sub

sub onContentSelectedChanged()
    content = m.top.itemContent
    if content <> invalid and content.doesExist("isSelected")
        m.top.isSelected = content.isSelected
    end if
end sub

sub onFocusPercentChanged()
    fp = m.top.focusPercent
    if fp > 0
        setFocusedState(fp)
    else
        setUnfocusedState()
    end if
end sub

sub setFocusedState(p as Float)
    if not m.top.isSelected
        bg = interpolateColor(&h2A2A2AFF, &h0078D4FF, p)
        m.background.color = bg
    end if
    
    numColor = interpolateColor(&hCCCCCCFF, &hFFFFFFFF, p)
    titleColor = interpolateColor(&hFFFFFFFF, &hFFFFFFFF, p)
    
    m.channelNumber.color = numColor
    m.programTitle.color = titleColor
end sub

sub setUnfocusedState()
    if not m.top.isSelected
        m.background.color = m.uiColors.BLACK42
    end if
    m.channelNumber.color = m.uiColors.LIGHT_GRAY
    m.programTitle.color = m.uiColors.WHITE
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