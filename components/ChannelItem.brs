sub init()
    ' Find and store UI components
    m.poster = m.top.findNode("poster")
    m.title = m.top.findNode("title")

    ' Set default properties
    if m.poster <> invalid
        m.poster.opacity = 0.5
    end if
    if m.title <> invalid
        m.title.opacity = 0.5
    end if
end sub

sub onContentChanged()
    if m.poster = invalid or m.title = invalid
        print "Error: Required nodes not found in ChannelItem"
        return
    end if

    content = m.top.itemContent
    if content = invalid
        print "Warning: Invalid content in ChannelItem"
        return
    end if

    ' Update poster image
    if content.hdPosterUrl <> invalid and content.hdPosterUrl <> ""
        m.poster.uri = content.hdPosterUrl
        print "Setting channel logo: " + content.hdPosterUrl
    else
        print "No logo available for channel"
    end if
    
    ' Update title
    if content.title <> invalid
        m.title.text = content.title
        print "Setting channel title: " + content.title
    else
        print "No title available for channel"
    end if
end sub

sub onFocusPercentChanged()
    if m.poster = invalid or m.title = invalid
        return
    end if

    focusPercent = m.top.focusPercent
    if focusPercent > 0.5
        m.poster.opacity = 1.0
        m.title.opacity = 1.0
    else
        m.poster.opacity = 0.5
        m.title.opacity = 0.5
    end if
end sub