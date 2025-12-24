sub init()
    m.background = m.top.findNode("background")
    m.channelLogo = m.top.findNode("channelLogo")
    m.nowPlaying = m.top.findNode("nowPlaying")
    m.programDetails = m.top.findNode("programDetails")

    m.uiColors = GetUIColors()
    m.isVisible = false

    ' Animation timer for slide down/up
    m.animationTimer = createObject("roSGNode", "Timer")
    m.animationTimer.repeat = true
    m.animationTimer.duration = 0.016  ' ~60 FPS
    m.animationTimer.observeField("fire", "onAnimationTick")

    ' Auto-hide timer
    m.hideTimer = createObject("roSGNode", "Timer")
    m.hideTimer.repeat = false
    m.hideTimer.duration = 10  ' Hide after 10 seconds
    m.hideTimer.observeField("fire", "onHideTimer")

    m.targetY = 0
    m.currentY = -270
    m.animationSpeed = 15  ' Pixels per frame

    m.top.observeField("channelData", "onChannelDataChanged")
    m.top.observeField("showOverlay", "onShowOverlayChanged")
end sub

sub onChannelDataChanged()
    data = m.top.channelData
    if data <> invalid

        ' Set channel logo/artwork
        if data.logo <> invalid and data.logo <> ""
            print "VideoInfoOverlay: Setting logo to: " + data.logo

            ' Detect if this is poster artwork (from fanart.tv) vs channel logo
            isPosterArt = (data.logo.Instr("fanart.tv") >= 0 or data.logo.Instr("tmdb.org") >= 0 or data.logo.Instr("tvmaze.com") >= 0)

            if isPosterArt
                ' Larger size for poster artwork
                m.channelLogo.width = 200
                m.channelLogo.height = 200
                m.channelLogo.loadWidth = 200
                m.channelLogo.loadHeight = 200
            else
                ' Original size for channel logos
                m.channelLogo.width = 150
                m.channelLogo.height = 150
                m.channelLogo.loadWidth = 150
                m.channelLogo.loadHeight = 150
            end if

            m.channelLogo.uri = data.logo
        else
            print "VideoInfoOverlay: No logo available"
            ' Reset to original channel logo size
            m.channelLogo.width = 150
            m.channelLogo.height = 150
            m.channelLogo.loadWidth = 150
            m.channelLogo.loadHeight = 150
            m.channelLogo.uri = ""
        end if

        ' Set now playing
        if data.nowPlaying <> invalid and data.nowPlaying <> ""
            m.nowPlaying.text = data.nowPlaying
        else if data.title <> invalid
            m.nowPlaying.text = data.title
        else
            m.nowPlaying.text = ""
        end if

        ' Set program details
        if data.programDetails <> invalid and data.programDetails <> ""
            m.programDetails.text = data.programDetails
            m.programDetails.font.size = 28
        else
            m.programDetails.text = ""
        end if
    end if
end sub

sub onShowOverlayChanged()
    shouldShow = m.top.showOverlay

    if shouldShow and not m.isVisible
        ' Slide down
        m.isVisible = true
        m.targetY = 0
        m.animationTimer.control = "start"
        m.hideTimer.control = "stop"
    else if not shouldShow and m.isVisible
        ' Slide up
        m.isVisible = false
        m.targetY = -270
        m.animationTimer.control = "start"
        m.hideTimer.control = "stop"
    else if shouldShow and m.isVisible
        ' Reset hide timer if already visible
        m.hideTimer.control = "stop"
        m.hideTimer.control = "start"
    end if
end sub

sub onAnimationTick()
    ' Animate towards target position
    if m.currentY < m.targetY
        m.currentY = m.currentY + m.animationSpeed
        if m.currentY >= m.targetY
            m.currentY = m.targetY
            m.animationTimer.control = "stop"

            ' Start hide timer if we just finished sliding down
            if m.isVisible and m.targetY = 0
                m.hideTimer.control = "start"
            end if
        end if
    else if m.currentY > m.targetY
        m.currentY = m.currentY - m.animationSpeed
        if m.currentY <= m.targetY
            m.currentY = m.targetY
            m.animationTimer.control = "stop"
        end if
    end if

    ' Update positions of all elements
    m.background.translation = [0, m.currentY]
    m.channelLogo.translation = [1700, m.currentY + 50]
    m.nowPlaying.translation = [60, m.currentY + 40]
    m.programDetails.translation = [60, m.currentY + 110]
end sub

sub onHideTimer()
    ' Auto-hide after 10 seconds
    m.top.showOverlay = false
end sub