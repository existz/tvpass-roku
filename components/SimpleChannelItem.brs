sub init()
    m.background = m.top.findNode("background")
    m.channelLabel = m.top.findNode("channelLabel")
    m.nowPlayingLabel = m.top.findNode("nowPlayingLabel")
    setUnfocusedState()
end sub

sub onContentChanged()
    content = m.top.itemContent
    if content <> invalid
        m.channelLabel.text = content.title
        
        ' Display nowPlaying if available
        if content.nowPlaying <> invalid and content.nowPlaying <> ""
            m.nowPlayingLabel.text = content.nowPlaying
            
            ' Position is now fixed in the XML layout
        else
            m.nowPlayingLabel.text = ""
        end if
    else
        m.channelLabel.text = ""
        m.nowPlayingLabel.text = ""
    end if
    setUnfocusedState()
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
    m.channelLabel.width = w - 40
end sub

sub setFocusedState(p as Float)
    bg = interpolateColor(&h000000FF, &h0078D4FF, p)  ' Softer blue
    label = interpolateColor(&hDDDDDDFF, &hFFFFFFFF, p)
    nowPlaying = interpolateColor(&h999999FF, &hCCCCCCFF, p)
    m.background.color = bg
    m.channelLabel.color = label
    m.nowPlayingLabel.color = nowPlaying
end sub

sub setUnfocusedState()
    m.background.color = "0x000000FF"
    m.channelLabel.color = "0xDDDDDDFF"
    m.nowPlayingLabel.color = "0x999999FF"
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
