sub init()
    m.thumbnailContainer = m.top.findNode("thumbnailContainer")
    m.mainChannelLabel = m.top.findNode("mainChannelLabel")
    
    m.uiColors = GetUIColors()
    m.thumbnails = []
    m.thumbnailChannelIndices = []
    m.channels = []
    m.currentMainIndex = 0
    m.selectedThumbnailIndex = 0
    m.visibleThumbnailCount = 0
    m.usingOriginalPlayer = false
    m.originalVideoPlayer = invalid
    m.wasPlayingBeforeMultiview = false

    ' Pre-compute ALL team logo URLs and colors at startup
    m.teamLogoCache = {}
    m.teamColorCache = {}
    m.leagueMaps = {
        NFL: GetNFLTeams()
        NBA: GetNBATeams()
        MLB: GetMLBTeams()
        NHL: GetNHLTeams()
    }
    m.colorPalette = GetTeamColorPalette()
    m.logoBaseUrl = GetLogoUrls().TEAM_LOGOS_BASE
    
    ' Pre-compile matchup parsing regex patterns
    m.separatorPatterns = [" vs ", " vs. ", " @ ", " at "]
    
    ' Cache for parsed matchups to avoid re-parsing
    m.matchupCache = {}
    
    ' Sports keywords for detection
    m.sportsKeywords = ["College Basketball", "College Football", "College Baseball", "NFL Football", "NBA Basketball", "NBA G League Basketball", "MLB Baseball", "NHL Hockey"]
    
    precomputeTeamData()
    
    m.lastMainChannelLabel = ""
    
    m.top.observeField("channels", "onChannelsChanged")
    m.top.observeField("visible", "onVisibleChanged")
    m.top.observeField("originalVideoPlayer", "onOriginalVideoPlayerChanged")
    m.top.observeField("wasPlayingBeforeMultiview", "onWasPlayingBeforeMultiviewChanged")
    m.top.observeField("epgData", "onEPGDataChanged")
    
    ' Fields for communicating with MainScene
    m.top.addField("shouldRestoreVideo", "boolean", false)
    m.top.addField("switchToChannelIndex", "integer", false)
    m.top.shouldRestoreVideo = false
    m.top.switchToChannelIndex = -1
end sub

sub onOriginalVideoPlayerChanged()
    m.originalVideoPlayer = m.top.originalVideoPlayer
end sub

sub onWasPlayingBeforeMultiviewChanged()
    m.wasPlayingBeforeMultiview = m.top.wasPlayingBeforeMultiview
end sub

sub onEPGDataChanged()
    ' When EPG data arrives, preload sports logos based on actual matchups in EPG
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
    print "MultiviewGrid: Preloading " + Stri(teamsToPreload.count()) + " sports team logos"
    
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
            m.thumbnailContainer.appendChild(preloadPoster)
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

sub precomputeTeamData()
    leagues = ["NFL", "NBA", "MLB", "NHL"]
    
    for each leagueName in leagues
        if not m.leagueMaps.doesExist(leagueName) then goto nextLeague
        
        teams = m.leagueMaps[leagueName]
        
        for each teamName in teams
            teamCode = teams[teamName]
            cacheKey = leagueName + ":" + teamCode
            
            logoUrl = m.logoBaseUrl + leagueName + "/" + teamCode + ".png"
            m.teamLogoCache[cacheKey] = logoUrl
            
            if m.colorPalette.doesExist(leagueName)
                leagueColors = m.colorPalette[leagueName]
                if leagueColors.doesExist(teamCode)
                    m.teamColorCache[cacheKey] = leagueColors[teamCode]
                else
                    m.teamColorCache[cacheKey] = m.uiColors.BLACK26
                end if
            else
                m.teamColorCache[cacheKey] = m.uiColors.BLACK26
            end if
        end for
        
        nextLeague:
    end for
end sub

function getTeamLogoUrlFast(teamCode as String, league as String) as String
    cacheKey = league + ":" + teamCode
    if m.teamLogoCache.doesExist(cacheKey)
        return m.teamLogoCache[cacheKey]
    end if
    return m.logoBaseUrl + league + "/" + teamCode + ".png"
end function

function getTeamColorFast(teamCode as String, league as String) as String
    cacheKey = league + ":" + teamCode
    if m.teamColorCache.doesExist(cacheKey)
        return m.teamColorCache[cacheKey]
    end if
    if m.colorPalette.doesExist(league)
        leagueColors = m.colorPalette[league]
        if leagueColors.doesExist(teamCode)
            return leagueColors[teamCode]
        end if
    end if
    return m.uiColors.BLACK26
end function

function createThumbnail(index as Integer) as Object
    yPos = 10 + (index * 165)
    
    container = createObject("roSGNode", "Group")
    container.translation = [10, yPos]
    
    thumb = {
        index: index
        yPos: yPos
        container: container
        background: invalid
        logo: invalid
        team1Background: invalid
        team2Background: invalid
        teamLogo1: invalid
        teamLogo2: invalid
        label: invalid
        borderTop: invalid
        borderBottom: invalid
        borderLeft: invalid
        borderRight: invalid
        lastLogoUri: ""
        lastTeam1LogoUri: ""
        lastTeam2LogoUri: ""
        lastTeam1Color: ""
        lastTeam2Color: ""
        lastLabelText: ""
        lastIsSports: invalid
    }

    bg = createObject("roSGNode", "Rectangle")
    bg.translation = [0, 0]
    bg.width = 360
    bg.height = 140
    bg.color = m.uiColors.BLACK26
    bg.visible = false
    container.appendChild(bg)
    thumb.background = bg

    team1Bg = createObject("roSGNode", "Rectangle")
    team1Bg.translation = [0, 0]
    team1Bg.width = 180
    team1Bg.height = 140
    team1Bg.color = m.uiColors.BLACK
    team1Bg.visible = false
    container.appendChild(team1Bg)
    thumb.team1Background = team1Bg

    team2Bg = createObject("roSGNode", "Rectangle")
    team2Bg.translation = [180, 0]
    team2Bg.width = 180
    team2Bg.height = 140
    team2Bg.color = m.uiColors.BLACK
    team2Bg.visible = false
    container.appendChild(team2Bg)
    thumb.team2Background = team2Bg

    logo = createObject("roSGNode", "Poster")
    logo.translation = [90, 10]
    logo.width = 180
    logo.height = 80
    logo.loadDisplayMode = "scaleToFit"
    logo.visible = false
    container.appendChild(logo)
    thumb.logo = logo

    teamLogo1 = createObject("roSGNode", "Poster")
    teamLogo1.translation = [25, 10]
    teamLogo1.loadWidth = 130
    teamLogo1.loadHeight = 120
    teamLogo1.width = 130
    teamLogo1.height = 120
    teamLogo1.loadDisplayMode = "scaleToFit"
    teamLogo1.visible = false
    container.appendChild(teamLogo1)
    thumb.teamLogo1 = teamLogo1

    teamLogo2 = createObject("roSGNode", "Poster")
    teamLogo2.translation = [205, 10]
    teamLogo2.loadWidth = 130
    teamLogo2.loadHeight = 120
    teamLogo2.width = 130
    teamLogo2.height = 120
    teamLogo2.loadDisplayMode = "scaleToFit"
    teamLogo2.visible = false
    container.appendChild(teamLogo2)
    thumb.teamLogo2 = teamLogo2

    label = createObject("roSGNode", "Label")
    label.translation = [0, 95]
    label.width = 360
    label.height = 40
    label.font = "font:SmallBoldSystemFont"
    label.font.size = 22
    label.color = m.uiColors.LIGHT_GRAY
    label.horizAlign = "center"
    label.vertAlign = "center"
    label.wrap = true
    label.visible = false
    container.appendChild(label)
    thumb.label = label

    borderTop = createObject("roSGNode", "Rectangle")
    borderTop.translation = [0, 0]
    borderTop.width = 360
    borderTop.height = 4
    borderTop.color = m.uiColors.WHITE
    borderTop.opacity = 0
    container.appendChild(borderTop)
    thumb.borderTop = borderTop

    borderBottom = createObject("roSGNode", "Rectangle")
    borderBottom.translation = [0, 136]
    borderBottom.width = 360
    borderBottom.height = 4
    borderBottom.color = m.uiColors.WHITE
    borderBottom.opacity = 0
    container.appendChild(borderBottom)
    thumb.borderBottom = borderBottom

    borderLeft = createObject("roSGNode", "Rectangle")
    borderLeft.translation = [0, 0]
    borderLeft.width = 4
    borderLeft.height = 140
    borderLeft.color = m.uiColors.WHITE
    borderLeft.opacity = 0
    container.appendChild(borderLeft)
    thumb.borderLeft = borderLeft

    borderRight = createObject("roSGNode", "Rectangle")
    borderRight.translation = [356, 0]
    borderRight.width = 4
    borderRight.height = 140
    borderRight.color = m.uiColors.WHITE
    borderRight.opacity = 0
    container.appendChild(borderRight)
    thumb.borderRight = borderRight

    m.thumbnailContainer.appendChild(container)

    return thumb
end function

sub onVisibleChanged()
    if m.top.visible
        m.thumbnails = []
        m.thumbnailChannelIndices = []
        
        ' Pre-parse all channel matchups before displaying
        if m.channels.count() > 0
            preParseAllMatchups()
            m.selectedThumbnailIndex = 0
            setupMainChannel(0)
        end if
        m.top.setFocus(true)
    else
        ' Clean up when hiding - make sure label is cleared
        m.mainChannelLabel.text = ""
    end if
end sub

' Pre-parse all sports matchups when entering multiview
sub preParseAllMatchups()
    for i = 0 to m.channels.count() - 1
        channel = m.channels[i]
        
        nowPlaying = channel.cachedTitle
        if channel.cachedNowPlaying <> invalid and channel.cachedNowPlaying <> ""
            nowPlaying = channel.cachedNowPlaying
        end if
        
        ' Parse and cache immediately
        if not m.matchupCache.doesExist(nowPlaying)
            matchup = parseTeamMatchupFast(nowPlaying)
            m.matchupCache[nowPlaying] = matchup
        end if
    end for
end sub

sub onChannelsChanged()
    m.channels = m.top.channels
    if m.channels = invalid or m.channels.count() = 0 then return

    ' Cache channel metadata
    for i = 0 to m.channels.count() - 1
        channel = m.channels[i]
        
        if channel.doesExist("logo") and channel.logo <> invalid
            channel.cachedLogo = channel.logo
        else
            channel.cachedLogo = ""
        end if
        
        if channel.doesExist("nowPlaying") and channel.nowPlaying <> invalid
            channel.cachedNowPlaying = channel.nowPlaying
        else
            channel.cachedNowPlaying = ""
        end if
        
        if channel.doesExist("title") and channel.title <> invalid
            channel.cachedTitle = channel.title
        else
            channel.cachedTitle = ""
        end if
        
        ' Check if this is the original stream
        if channel.doesExist("isOriginalStream")
            channel.cachedIsOriginal = channel.isOriginalStream
        else
            channel.cachedIsOriginal = false
        end if
    end for

    if m.top.visible
        m.currentMainIndex = 0
        m.selectedThumbnailIndex = 0
        setupMainChannel(0)
    end if
end sub

sub setupMainChannel(index as Integer)
    if index < 0 or index >= m.channels.count() then return

    m.currentMainIndex = index
    channel = m.channels[index]

    ' Check if this is the original stream
    if channel.cachedIsOriginal = true and m.wasPlayingBeforeMultiview = true
        ' Original stream is already playing and resized - don't do anything
        m.usingOriginalPlayer = true
    else
        ' Tell MainScene to switch to a different channel
        m.usingOriginalPlayer = false
        
        ' Find the actual channel index in the full channel list
        channelIndex = -1
        if channel.doesExist("channelIndex")
            channelIndex = channel.channelIndex
        end if

        m.top.switchToChannelIndex = channelIndex
    end if

    labelText = channel.cachedTitle
    if channel.cachedNowPlaying <> invalid and channel.cachedNowPlaying <> ""
        labelText = channel.cachedNowPlaying
    end if
    
    if labelText <> m.lastMainChannelLabel
        m.mainChannelLabel.text = labelText
        m.lastMainChannelLabel = labelText
    end if

    updateThumbnails()
end sub

sub updateThumbnails()
    ' Create thumbnails if needed
    if m.thumbnails.count() = 0
        for i = 0 to 4
            thumb = createThumbnail(i)
            m.thumbnails.push(thumb)
            m.thumbnailChannelIndices.push(-1)
        end for
    end if
    
    thumbIndex = 0

    for i = 0 to m.channels.count() - 1
        if i <> m.currentMainIndex and thumbIndex <= 4 then
            channel = m.channels[i]
            thumb = m.thumbnails[thumbIndex]

            nowPlaying = channel.cachedTitle
            if channel.cachedNowPlaying <> invalid and channel.cachedNowPlaying <> ""
                nowPlaying = channel.cachedNowPlaying
            end if

            ' Use cached matchup data
            matchup = invalid
            if m.matchupCache.doesExist(nowPlaying)
                matchup = m.matchupCache[nowPlaying]
            else
                matchup = parseTeamMatchupFast(nowPlaying)
                m.matchupCache[nowPlaying] = matchup
            end if
            
            isSports = (matchup <> invalid)
            needsUpdate = (thumb.lastIsSports = invalid or thumb.lastIsSports <> isSports)
            
            if isSports 
                team1Url = getTeamLogoUrlFast(matchup.team1, matchup.league)
                team2Url = getTeamLogoUrlFast(matchup.team2, matchup.league)
                team1Color = getTeamColorFast(matchup.team1, matchup.league)
                team2Color = getTeamColorFast(matchup.team2, matchup.league)

                ' Batch all updates together to minimize render cycles
                if team1Color <> thumb.lastTeam1Color or team2Color <> thumb.lastTeam2Color or team1Url <> thumb.lastTeam1LogoUri or team2Url <> thumb.lastTeam2LogoUri or needsUpdate
                    thumb.team1Background.color = team1Color
                    thumb.team2Background.color = team2Color
                    thumb.teamLogo1.uri = team1Url
                    thumb.teamLogo2.uri = team2Url
                    
                    thumb.lastTeam1Color = team1Color
                    thumb.lastTeam2Color = team2Color
                    thumb.lastTeam1LogoUri = team1Url
                    thumb.lastTeam2LogoUri = team2Url
                    needsUpdate = true
                end if
            else
                logoUrl = channel.cachedLogo

                if logoUrl <> thumb.lastLogoUri or nowPlaying <> thumb.lastLabelText or needsUpdate
                    if logoUrl <> invalid and logoUrl <> ""
                        thumb.logo.uri = logoUrl
                    else
                        thumb.logo.uri = ""
                    end if
                    thumb.label.text = nowPlaying
                    
                    thumb.lastLogoUri = logoUrl
                    thumb.lastLabelText = nowPlaying
                    needsUpdate = true
                end if
            end if

            ' Only update visibility if state changed
            if needsUpdate or thumb.lastIsSports <> isSports
                sportsVisible = isSports
                nonSportsVisible = not isSports
                
                ' Batch visibility updates
                thumb.team1Background.visible = sportsVisible
                thumb.team2Background.visible = sportsVisible
                thumb.teamLogo1.visible = sportsVisible
                thumb.teamLogo2.visible = sportsVisible
                thumb.background.visible = nonSportsVisible
                thumb.logo.visible = nonSportsVisible
                thumb.label.visible = nonSportsVisible
                
                thumb.lastIsSports = isSports
            end if

            m.thumbnailChannelIndices[thumbIndex] = i

            isSelected = (thumbIndex = m.selectedThumbnailIndex)
            borderOpacity = 0
            if isSelected then borderOpacity = 1

            ' Only update border if selection changed
            if thumb.borderTop.opacity <> borderOpacity
                thumb.borderTop.opacity = borderOpacity
                thumb.borderBottom.opacity = borderOpacity
                thumb.borderLeft.opacity = borderOpacity
                thumb.borderRight.opacity = borderOpacity
            end if

            thumbIndex = thumbIndex + 1
        end if

        if thumbIndex > 4 then exit for
    end for

    ' Batch hide unused thumbnails
    for i = thumbIndex to 4
        thumb = m.thumbnails[i]
        thumb.background.visible = false
        thumb.logo.visible = false
        thumb.team1Background.visible = false
        thumb.team2Background.visible = false
        thumb.teamLogo1.visible = false
        thumb.teamLogo2.visible = false
        thumb.label.visible = false
        thumb.borderTop.opacity = 0
        thumb.borderBottom.opacity = 0
        thumb.borderLeft.opacity = 0
        thumb.borderRight.opacity = 0
        m.thumbnailChannelIndices[i] = -1
    end for

    m.visibleThumbnailCount = thumbIndex
end sub

sub swapToThumbnail(thumbIndex as Integer)
    if thumbIndex < 0 or thumbIndex >= m.visibleThumbnailCount then return

    newChannelIndex = m.thumbnailChannelIndices[thumbIndex]
    if newChannelIndex < 0 or newChannelIndex >= m.channels.count() then return

    oldThumb = m.thumbnails[m.selectedThumbnailIndex]
    oldThumb.borderTop.opacity = 0
    oldThumb.borderBottom.opacity = 0
    oldThumb.borderLeft.opacity = 0
    oldThumb.borderRight.opacity = 0
    
    m.selectedThumbnailIndex = thumbIndex
    newThumb = m.thumbnails[m.selectedThumbnailIndex]
    newThumb.borderTop.opacity = 1
    newThumb.borderBottom.opacity = 1
    newThumb.borderLeft.opacity = 1
    newThumb.borderRight.opacity = 1

    setupMainChannel(newChannelIndex)
end sub

sub restoreOriginalVideo()
    if m.originalVideoPlayer <> invalid
        print "MultiviewGrid: Resizing video to full screen"
        ' Restore original video player to full screen
        ' Don't touch visibility - it should already be visible
        m.originalVideoPlayer.translation = [0, 0]
        m.originalVideoPlayer.width = 1920
        m.originalVideoPlayer.height = 1080
        print "MultiviewGrid: Video resized to 1920x1080"
    end if
end sub

' Faster parsing with early exits and cached patterns
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

sub selectPreviousThumbnail()
    if m.selectedThumbnailIndex > 0
        m.selectedThumbnailIndex = m.selectedThumbnailIndex - 1
        updateThumbnails()
    end if
end sub

sub selectNextThumbnail()
    if m.selectedThumbnailIndex < m.visibleThumbnailCount - 1
        m.selectedThumbnailIndex = m.selectedThumbnailIndex + 1
        updateThumbnails()
    end if
end sub

function onKeyEvent(key as String, press as Boolean) as Boolean
    if not press then return false

    if key = "back"
        ' Resize the video BEFORE hiding multiview to avoid black screen
        restoreOriginalVideo()
        m.top.shouldRestoreVideo = true

        ' Hide multiview after resize
        m.top.visible = false
        
        ' IMPORTANT: Signal MainScene to reset isMultiviewMode immediately
        ' Using a new field so MainScene can reset the flag right away
        m.top.addField("exitMultiview", "boolean", true)
        m.top.exitMultiview = true
        
        return true
    else if key = "up"
        selectPreviousThumbnail()
        return true
    else if key = "down"
        selectNextThumbnail()
        return true
    else if key = "OK" or key = "right"
        swapToThumbnail(m.selectedThumbnailIndex)
        return true
    end if

    return false
end function