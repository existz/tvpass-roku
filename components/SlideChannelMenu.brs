sub init()
    m.overlay = m.top.findNode("overlay")
    m.menuBackground = m.top.findNode("menuBackground")
    m.menuTitle = m.top.findNode("menuTitle")
    m.channelList = m.top.findNode("channelList")
    
    ' Multiview state
    m.selectedChannels = []
    m.maxMultiviewChannels = 6
    m.okButtonPressTime = 0
    m.longPressThreshold = 500
    m.isLongPress = false
    
    ' Sports detection
    m.sportsKeywords = ["College Basketball", "College Football", "College Baseball", "NFL Football", "NBA Basketball", "NBA G League Basketball", "MLB Baseball", "NHL Hockey"]
    m.separatorPatterns = [" vs ", " vs. ", " @ ", " at "]
    
    ' Team data for preloading
    m.leagueMaps = {
        NFL: GetNFLTeams()
        NBA: GetNBATeams()
        MLB: GetMLBTeams()
        NHL: GetNHLTeams()
    }
    m.logoBaseUrl = GetLogoUrls().TEAM_LOGOS_BASE
    
    m.top.observeField("channels", "onChannelsChanged")
    m.top.observeField("visible", "onVisibleChanged")
    m.top.observeField("currentChannelIndex", "onCurrentChannelIndexChanged")
    m.top.observeField("epgData", "onEPGDataChanged")
    
    ' Initialize menuClosed field
    m.top.menuClosed = false
end sub

sub onVisibleChanged()
    isVisible = m.top.visible
    if isVisible
        m.selectedChannels = []
        m.isLongPress = false
        
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
    ' When EPG data arrives, preload sports logos
    epgData = m.top.epgData
    if epgData = invalid or epgData.channels = invalid then return
    
    preloadSportsLogosFromEPG(epgData)
end sub

function IsSportsProgram(title as String) as Boolean
    for each keyword in m.sportsKeywords
        if title.Instr(keyword) >= 0 then return true
    end for
    return false
end function

function parseTeamMatchupFast(programTitle as String) as Object
    if programTitle = invalid or programTitle = "" then return invalid
    
    ' Quick check for any separator
    hasSeparator = false
    separatorFound = ""
    for each sep in m.separatorPatterns
        if programTitle.Instr(sep) >= 0
            hasSeparator = true
            separatorFound = sep
            exit for
        end if
    end for
    
    if not hasSeparator then return invalid
    
    ' Split on found separator
    teams = programTitle.Split(separatorFound)
    
    if teams = invalid or teams.count() < 2 then return invalid
    
    team1Name = teams[0].Trim()
    team2Name = teams[1].Trim()
    
    ' Quick parenthesis removal
    parenPos = team2Name.Instr("(")
    if parenPos >= 0
        team2Name = team2Name.Left(parenPos).Trim()
    end if
    
    league = detectLeagueFromTeamsFast(team1Name, team2Name)
    if league = invalid then return invalid
    
    team1Code = getTeamCodeFast(team1Name, league)
    team2Code = getTeamCodeFast(team2Name, league)
    
    if team1Code = invalid or team2Code = invalid then return invalid
    
    return {
        league: league
        team1: team1Code
        team2: team2Code
    }
end function

function detectLeagueFromTeamsFast(team1 as String, team2 as String) as Dynamic
    leagues = ["NFL", "NBA", "MLB", "NHL"]
    
    for each leagueName in leagues
        if not m.leagueMaps.doesExist(leagueName) then goto nextLeague
        
        teams = m.leagueMaps[leagueName]
        found1 = false
        found2 = false
        
        for each teamKey in teams
            if team1.Instr(teamKey) >= 0 then found1 = true
            if team2.Instr(teamKey) >= 0 then found2 = true
            if found1 and found2 then return leagueName
        end for
        
        nextLeague:
    end for
    
    return invalid
end function

function getTeamCodeFast(teamName as String, league as String) as Dynamic
    if not m.leagueMaps.doesExist(league) then return invalid
    
    teams = m.leagueMaps[league]
    for each key in teams
        if teamName.Instr(key) >= 0
            return teams[key]
        end if
    end for
    
    return invalid
end function

function getTeamLogoUrlFast(teamCode as String, league as String) as String
    return m.logoBaseUrl + league + "/" + teamCode + ".png"
end function

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
            if not IsSportsProgram(program.title) then continue for
            
            ' Use subtitle for sports programs if available
            displayText = program.title
            if program.subTitle <> invalid and program.subTitle <> ""
                displayText = program.subTitle
            end if
            
            ' Parse matchup
            matchup = parseTeamMatchupFast(displayText)
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
    print "SlideChannelMenu: Preloading " + Stri(teamsToPreload.count()) + " sports team logos"
    
    for each teamKey in teamsToPreload
        ' Parse league and team code from key
        parts = teamKey.Split(":")
        if parts.count() = 2
            league = parts[0]
            teamCode = parts[1]
            
            ' Create a hidden poster to trigger download
            preloadPoster = createObject("roSGNode", "Poster")
            preloadPoster.uri = getTeamLogoUrlFast(teamCode, league)
            preloadPoster.loadWidth = 1
            preloadPoster.loadHeight = 1
            preloadPoster.visible = false
            m.channelList.appendChild(preloadPoster)
        end if
    end for
end sub

function EPGGetPrograms(epg as Object, tvgId as String) as Object
    if tvgId = invalid then return []
    
    normalizedId = EPGNormalizeChannelId(tvgId)
    
    if epg.programsByChannel.doesExist(normalizedId)
        return epg.programsByChannel[normalizedId]
    end if
    
    return []
end function

function EPGNormalizeChannelId(id as String) as String
    if id = invalid then return ""
    
    id = id.Trim()
    
    if id.StartsWith("channel")
        return id.Mid(7)
    end if
    
    dotPos = id.Instr(".")
    if dotPos > 0
        return Left(id, dotPos - 1)
    end if
    
    return id
end function

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