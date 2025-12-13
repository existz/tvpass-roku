sub init()
    m.overlay = m.top.findNode("overlay")
    m.menuBackground = m.top.findNode("menuBackground")
    m.menuTitle = m.top.findNode("menuTitle")
    m.channelList = m.top.findNode("channelList")
    m.preloadContainer = m.top.findNode("preloadContainer")

    ' Multiview state
    m.selectedChannels = []
    m.maxMultiviewChannels = 6
    m.okButtonPressTime = 0
    m.longPressThreshold = 500
    m.isLongPress = false

    ' Track if we've already preloaded current EPG data
    m.epgDataPreloaded = false

    ' Bitmap cache for image preloading
    m.bitmapCache = invalid

    ' Sports detection - use shared utilities
    m.sportsKeywords = GetSportsKeywords()
    m.separatorPatterns = GetSeparatorPatterns()
    m.leagueMaps = GetLeagueMaps()
    m.logoBaseUrl = GetLogoUrls().TEAM_LOGOS_BASE

    m.top.observeField("channels", "onChannelsChanged")
    m.top.observeField("visible", "onVisibleChanged")
    m.top.observeField("currentChannelIndex", "onCurrentChannelIndexChanged")
    m.top.observeField("epgData", "onEPGDataChanged")
    m.top.observeField("bitmapCache", "onBitmapCacheChanged")

    ' Initialize menuClosed field
    m.top.menuClosed = false
end sub

sub onVisibleChanged()
    isVisible = m.top.visible
    if isVisible
        m.selectedChannels = []
        m.isLongPress = false

        ' Preload sports logos if EPG data arrived before menu opened
        if m.top.epgData <> invalid and not m.epgDataPreloaded
            preloadSportsLogosFromEPG(m.top.epgData)
            m.epgDataPreloaded = true
        end if

        if m.top.currentChannelIndex >= 0 and m.channelList.content <> invalid
            itemCount = m.channelList.content.getChildCount()
            if m.top.currentChannelIndex < itemCount
                m.channelList.jumpToItem = m.top.currentChannelIndex
                m.channelList.animateToItem = m.top.currentChannelIndex
            end if
        end if

        m.top.setFocus(true)
        m.channelList.setFocus(true)
    else
        ' Clear selected channels when menu closes
        m.selectedChannels = []
    end if
end sub

sub onCurrentChannelIndexChanged()
    if m.top.visible and m.top.currentChannelIndex >= 0 and m.channelList.content <> invalid
        itemCount = m.channelList.content.getChildCount()
        if m.top.currentChannelIndex < itemCount
            m.channelList.jumpToItem = m.top.currentChannelIndex
        end if
    end if
end sub

sub onEPGDataChanged()
    ' When EPG data arrives, preload sports logos immediately
    epgData = m.top.epgData
    if epgData = invalid or epgData.channels = invalid then return

    ' Reset preload flag since we have new EPG data
    m.epgDataPreloaded = false

    ' Preload immediately when EPG data arrives
    preloadSportsLogosFromEPG(epgData)
    m.epgDataPreloaded = true
end sub

sub preloadSportsLogosFromEPG(epgData as Object)
    ' Collect unique team codes from EPG programs
    teamsToPreload = {}

    for each channel in epgData.channels
        if channel.tvgId = invalid then continue for

        programs = EPGGetPrograms(epgData, channel.tvgId)
        if programs = invalid then continue for

        for each program in programs
            if program.title = invalid then continue for

            ' Check if it's a sports program
            if not IsSportsProgram(program.title, m.sportsKeywords) then continue for

            ' Use subtitle for sports programs if available
            displayText = program.title
            if program.subTitle <> invalid and program.subTitle <> ""
                displayText = program.subTitle
            end if

            ' Parse matchup
            matchup = ParseTeamMatchupFast(displayText, m.separatorPatterns, m.leagueMaps)
            if matchup <> invalid
                ' Add both teams to preload list
                key1 = matchup.league + ":" + matchup.team1
                key2 = matchup.league + ":" + matchup.team2
                teamsToPreload[key1] = true
                teamsToPreload[key2] = true
            end if
        end for
    end for

    ' Now preload all unique team logos
    if teamsToPreload.count() > 0
        print "SlideChannelMenu: Preloading " + Stri(teamsToPreload.count()) + " sports team logos"

        for each teamKey in teamsToPreload
            ' Parse league and team code from key
            parts = teamKey.Split(":")
            if parts.count() = 2
                league = parts[0]
                teamCode = parts[1]

                ' Create a hidden poster to trigger download
                preloadPoster = createObject("roSGNode", "Poster")
                preloadPoster.uri = GetTeamLogoUrlFast(teamCode, league, m.logoBaseUrl)
                preloadPoster.loadWidth = 130
                preloadPoster.loadHeight = 120
                preloadPoster.visible = false
                m.preloadContainer.appendChild(preloadPoster)
            end if
        end for
    end if
end sub

sub onChannelsChanged()
    channels = m.top.channels
    if channels = invalid or channels.count() = 0 then return

    content = createObject("roSGNode", "ContentNode")

    for i = 0 to channels.count() - 1
        channel = channels[i]
        item = content.createChild("ContentNode")

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

        if channel.isSports <> invalid
            item.addField("isSports", "boolean", false)
            item.isSports = channel.isSports
        else
            item.addField("isSports", "boolean", false)
            item.isSports = false
        end if

        item.addField("channelIndex", "integer", false)
        item.channelIndex = i

        item.addField("isSelected", "boolean", false)
        item.isSelected = false
    end for

    m.channelList.content = content

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
        newSelection = []
        for i = 0 to m.selectedChannels.count() - 1
            if i <> selectedIndex
                newSelection.push(m.selectedChannels[i])
            end if
        end for
        m.selectedChannels = newSelection
    else
        if m.selectedChannels.count() < m.maxMultiviewChannels
            m.selectedChannels.push(channelIndex)
        end if
    end if

    updateSelectionIndicators()
end sub

sub updateSelectionIndicators()
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

    m.channelList.itemFocused = m.channelList.itemFocused
end sub

sub show()
    m.top.visible = true
    m.top.setFocus(true)
    m.channelList.setFocus(true)
end sub

sub hide()
    m.top.visible = false
end sub

function onKeyEvent(key as String, press as Boolean) as Boolean
    dt = CreateObject("roDateTime")
    currentTime& = dt.AsSeconds()
    currentTimeMs& = (currentTime& * 1000) + dt.GetMilliseconds()

    if key = "back"
        ' Handle both press and release to consume the entire back button event
        if press
            if m.selectedChannels.count() > 0
                finalChannels = []

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
                    end if
                end if

                for each idx in m.selectedChannels
                    finalChannels.push(idx)
                end for

                m.top.launchMultiview = finalChannels
                m.top.visible = false
                m.top.menuClosed = true
                return true
            else
                m.top.visible = false
                m.top.menuClosed = true
                return true
            end if
        end if
        ' Also consume the release event
        return true
    end if

    if press
        if key = "OK"
            m.okButtonPressTime = currentTimeMs&
            m.isLongPress = false
            return true
        end if
    else
        if key = "OK" and m.okButtonPressTime > 0
            duration = currentTimeMs& - m.okButtonPressTime
            m.okButtonPressTime = 0

            if duration >= m.longPressThreshold
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
                if not m.isLongPress
                    playSelectedChannel()
                end if
                return true
            end if
        end if
    end if

    if key = "up" or key = "down"
        return false
    end if

    return false
end function