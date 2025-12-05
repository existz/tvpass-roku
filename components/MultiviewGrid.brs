sub init()
    m.mainVideo = m.top.findNode("mainVideo")
    m.thumbnailContainer = m.top.findNode("thumbnailContainer")
    m.mainChannelLabel = m.top.findNode("mainChannelLabel")
    
    m.uiColors = GetUIColors()
    m.thumbnails = []
    m.thumbnailChannelIndices = []
    m.channels = []
    m.currentMainIndex = 0
    m.selectedThumbnailIndex = 0
    m.visibleThumbnailCount = 0

    ' Pre-compute ALL team logo URLs and colors at startup for instant O(1) lookups
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
    
    ' Pre-compute ALL team logo URLs and colors for all leagues
    precomputeTeamData()
    
    ' Track last state to avoid redundant updates
    m.lastMainChannelLabel = ""
    
    ' Don't create thumbnails here - they'll be created when needed
    ' This ensures they have all the latest properties
    m.mainVideo.observeField("state", "onMainVideoStateChange")
    m.top.observeField("channels", "onChannelsChanged")
    m.top.observeField("visible", "onVisibleChanged")
end sub

sub precomputeTeamData()
    ' For each league, pre-compute logo URLs and colors for all teams
    leagues = ["NFL", "NBA", "MLB", "NHL"]
    
    for each leagueName in leagues
        if not m.leagueMaps.doesExist(leagueName)
            print "MultiviewGrid: League not found in maps: "; leagueName
            goto nextLeague
        end if
        
        teams = m.leagueMaps[leagueName]
        
        for each teamName in teams
            teamCode = teams[teamName]
            ' Use uppercase league name for cache key to match what parseTeamMatchupFast generates
            cacheKey = leagueName + ":" + teamCode
            
            ' Pre-compute logo URL
            logoUrl = m.logoBaseUrl + leagueName + "/" + teamCode + ".png"
            m.teamLogoCache[cacheKey] = logoUrl
            
            ' Pre-compute color - check both the league name and team code exist
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
    
    ' Cache built successfully - ready for fast lookups
end sub

' Fast lookup using pre-computed cache
function getTeamLogoUrlFast(teamCode as String, league as String) as String
    cacheKey = league + ":" + teamCode
    if m.teamLogoCache.doesExist(cacheKey)
        return m.teamLogoCache[cacheKey]
    end if
    ' Fallback: construct URL directly if not in cache
    return m.logoBaseUrl + league + "/" + teamCode + ".png"
end function

function getTeamColorFast(teamCode as String, league as String) as String
    cacheKey = league + ":" + teamCode
    if m.teamColorCache.doesExist(cacheKey)
        return m.teamColorCache[cacheKey]
    end if
    ' Fallback: try to get color directly
    if m.colorPalette.doesExist(league)
        leagueColors = m.colorPalette[league]
        if leagueColors.doesExist(teamCode)
            return leagueColors[teamCode]
        end if
    end if
    return m.uiColors.BLACK26
end function

function createThumbnail(index as Integer) as Object
    ' Reduced height from 180 to 140, increased spacing from 185 to 165
    yPos = 10 + (index * 165)
    
    ' Create a single container group for this thumbnail
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

    ' Background (for non-sports)
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
    logo.loadWidth = 180
    logo.loadHeight = 60
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

    ' Border outline (4 rectangles forming a frame)
    ' Top border
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

    ' Append the entire container at once to thumbnailContainer
    m.thumbnailContainer.appendChild(container)

    return thumb
end function

sub onVisibleChanged()
    if m.top.visible
        ' Force recreation of thumbnails when multiview becomes visible
        m.thumbnails = []
        m.thumbnailChannelIndices = []
        
        if m.channels.count() > 0
            m.selectedThumbnailIndex = 0
            playMainChannel(0)
        end if
        m.top.setFocus(true)
    else
        stopPlayback()
    end if
end sub

sub onChannelsChanged()
    m.channels = m.top.channels
    if m.channels = invalid or m.channels.count() = 0 then return

    ' Cache channel metadata for fast access
    for i = 0 to m.channels.count() - 1
        channel = m.channels[i]
        
        ' Cache logo
        if channel.doesExist("logo") and channel.logo <> invalid
            channel.cachedLogo = channel.logo
        else
            channel.cachedLogo = ""
        end if
        
        ' Cache nowPlaying
        if channel.doesExist("nowPlaying") and channel.nowPlaying <> invalid
            channel.cachedNowPlaying = channel.nowPlaying
        else
            channel.cachedNowPlaying = ""
        end if
        
        ' Cache title
        if channel.doesExist("title") and channel.title <> invalid
            channel.cachedTitle = channel.title
        else
            channel.cachedTitle = ""
        end if
    end for

    if m.top.visible
        m.currentMainIndex = 0
        m.selectedThumbnailIndex = 0
        playMainChannel(0)
    end if
end sub

sub playMainChannel(index as Integer)
    if index < 0 or index >= m.channels.count() then return

    m.currentMainIndex = index
    channel = m.channels[index]

    ' Update main video
    content = createObject("roSGNode", "ContentNode")
    content.url = channel.url
    content.title = ""  ' Don't show the built-in title overlay
    content.streamFormat = "hls"

    ' Force HD quality settings
    content.addField("preferredBitrate", "integer", false)
    content.preferredBitrate = 0  ' 0 = highest available
    content.addField("maxBandwidth", "integer", false)
    content.maxBandwidth = 0  ' 0 = no limit

    m.mainVideo.content = content
    m.mainVideo.control = "play"

    ' Set video player to prefer highest quality
    m.mainVideo.maxVideoDecodeResolution = "1920x1080"

    ' Update label with nowPlaying if available - use cached values
    labelText = channel.cachedTitle
    if channel.cachedNowPlaying <> invalid and channel.cachedNowPlaying <> ""
        labelText = channel.cachedNowPlaying
    end if
    
    if labelText <> m.lastMainChannelLabel
        m.mainChannelLabel.text = labelText
        m.lastMainChannelLabel = labelText
    end if

    ' Update thumbnails
    updateThumbnails()
end sub

sub updateThumbnails()
    ' Create thumbnails if they don't exist yet
    if m.thumbnails.count() = 0
        for i = 0 to 4
            thumb = createThumbnail(i)
            m.thumbnails.push(thumb)
            m.thumbnailChannelIndices.push(-1)
        end for
    end if
    
    thumbIndex = 0

    ' Loop through channels and fill up to 5 thumbnails
    for i = 0 to m.channels.count() - 1
        ' Skip main channel and limit to 5 thumbnails
        if i <> m.currentMainIndex and thumbIndex <= 4 then

            channel = m.channels[i]
            thumb = m.thumbnails[thumbIndex]

            ' Get now playing text - use cached values
            nowPlaying = channel.cachedTitle
            if channel.cachedNowPlaying <> invalid and channel.cachedNowPlaying <> ""
                nowPlaying = channel.cachedNowPlaying
            end if

            ' Check if this is a sports matchup
            matchup = parseTeamMatchupFast(nowPlaying)
            
            isSports = (matchup <> invalid)

            needsUpdate = (thumb.lastIsSports = invalid or thumb.lastIsSports <> isSports)
            
            if isSports 
                team1Url = getTeamLogoUrlFast(matchup.team1, matchup.league)
                team2Url = getTeamLogoUrlFast(matchup.team2, matchup.league)
                team1Color = getTeamColorFast(matchup.team1, matchup.league)
                team2Color = getTeamColorFast(matchup.team2, matchup.league)

                if team1Color <> thumb.lastTeam1Color
                    thumb.team1Background.color = team1Color
                    thumb.lastTeam1Color = team1Color
                    needsUpdate = true
                end if
                
                if team2Color <> thumb.lastTeam2Color
                    thumb.team2Background.color = team2Color
                    thumb.lastTeam2Color = team2Color
                    needsUpdate = true
                end if
                
                if team1Url <> thumb.lastTeam1LogoUri
                    thumb.teamLogo1.uri = team1Url
                    thumb.lastTeam1LogoUri = team1Url
                    needsUpdate = true
                end if
                
                if team2Url <> thumb.lastTeam2LogoUri
                    thumb.teamLogo2.uri = team2Url
                    thumb.lastTeam2LogoUri = team2Url
                    needsUpdate = true
                end if
                
            else
                ' Show channel logo (non-sports) - use cached value
                logoUrl = channel.cachedLogo

                if logoUrl <> thumb.lastLogoUri
                    if logoUrl <> invalid and logoUrl <> ""
                        thumb.logo.uri = logoUrl
                    else
                        thumb.logo.uri = ""
                    end if
                    thumb.lastLogoUri = logoUrl
                    needsUpdate = true
                end if
                
                ' Update label for non-sports
                if nowPlaying <> thumb.lastLabelText
                    thumb.label.text = nowPlaying
                    thumb.lastLabelText = nowPlaying
                    needsUpdate = true
                end if
            end if

            ' Batch visibility update
            if needsUpdate or thumb.lastIsSports <> isSports
                sportsVisible = isSports
                nonSportsVisible = not isSports
                
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

            thumb.borderTop.opacity = borderOpacity
            thumb.borderBottom.opacity = borderOpacity
            thumb.borderLeft.opacity = borderOpacity
            thumb.borderRight.opacity = borderOpacity

            thumbIndex = thumbIndex + 1
        end if

        ' Stop if we filled all 5 thumbnails
        if thumbIndex > 4 then exit for
    end for

    ' Hide any remaining unused thumbnails - batch visibility
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

    ' Cache count of visible thumbnails
    m.visibleThumbnailCount = thumbIndex
end sub

sub swapToThumbnail(thumbIndex as Integer)
    if thumbIndex < 0 or thumbIndex >= m.visibleThumbnailCount then return

    newChannelIndex = m.thumbnailChannelIndices[thumbIndex]
    if newChannelIndex < 0 or newChannelIndex >= m.channels.count() then return

    ' Update border selection
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

    ' Play new main channel
    m.mainVideo.control = "stop"
    playMainChannel(newChannelIndex)
end sub

sub onMainVideoStateChange()
end sub

sub stopPlayback()
    m.mainVideo.control = "stop"
end sub

function parseTeamMatchupFast(programTitle as String) as Object
    ' Returns { league: "NFL/NBA/MLB/NHL", team1: "BUF", team2: "ARI" } or invalid
    if programTitle = invalid or programTitle = "" then return invalid
    
    ' Check for "vs" or "@" pattern
    hasVs = (programTitle.Instr(" vs ") >= 0 or programTitle.Instr(" vs. ") >= 0)
    hasAt = (programTitle.Instr(" @ ") >= 0 or programTitle.Instr(" at ") >= 0)
    
    if not hasVs and not hasAt then return invalid
    
    ' Extract team names first
    teams = invalid
    if hasVs
        if programTitle.Instr(" vs ") >= 0
            teams = programTitle.Split(" vs ")
        else
            teams = programTitle.Split(" vs. ")
        end if
    else if hasAt
        if programTitle.Instr(" @ ") >= 0
            teams = programTitle.Split(" @ ")
        else
            teams = programTitle.Split(" at ")
        end if
    end if
    
    if teams = invalid or teams.count() < 2 then return invalid
    
    team1Name = teams[0].Trim()
    team2Name = teams[1].Trim()
    
    ' Remove date/time info from team2Name (e.g., "(11/30 1:00 PM ET)")
    parenPos = team2Name.Instr("(")
    if parenPos >= 0
        team2Name = team2Name.Left(parenPos).Trim()
    end if
    
    ' Determine league by checking team names against known teams
    league = detectLeagueFromTeamsFast(team1Name, team2Name)
    if league = invalid then return invalid
    
    ' Get team codes
    team1Code = getTeamCodeFast(team1Name, league)
    team2Code = getTeamCodeFast(team2Name, league)
    
    if team1Code = invalid or team2Code = invalid then return invalid
    
    return {
        league: league
        team1: team1Code
        team2: team2Code
    }
end function

' Use cached league maps instead of function calls
function detectLeagueFromTeamsFast(team1 as String, team2 as String) as Dynamic
    ' Try each league using pre-loaded maps - use explicit league names
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
        m.top.visible = false
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