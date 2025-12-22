sub init()
    m.thumbnailContainer = m.top.findNode("thumbnailContainer")
    m.mainChannelLabel = m.top.findNode("mainChannelLabel")
    m.preloadContainer = m.top.findNode("preloadContainer")

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

    ' Track which channel is actually playing in MainScene
    m.currentlyPlayingChannelIndex = -1

    ' Add field for original channel index so MainScene can access it
    m.top.addField("originalChannelIndex", "integer", false)
    m.top.originalChannelIndex = -1

    ' Pre-compute ALL team logo URLs and colors at startup
    m.teamLogoCache = {}
    m.teamColorCache = {}
    m.leagueMaps = GetLeagueMaps()
    m.colorPalette = GetTeamColorPalette()
    m.logoBaseUrl = GetLogoUrls().TEAM_LOGOS_BASE

    ' Pre-compile matchup parsing regex patterns
    m.separatorPatterns = GetSeparatorPatterns()

    ' Cache for parsed matchups to avoid re-parsing
    m.matchupCache = {}

    ' Sports keywords for detection
    m.sportsKeywords = GetSportsKeywords()

    ' Track if we've already preloaded current EPG data
    m.epgDataPreloaded = false

    ' Bitmap cache for image preloading
    m.bitmapCache = invalid

    precomputeTeamData()

    m.lastMainChannelLabel = ""

    m.top.observeField("channels", "onChannelsChanged")
    m.top.observeField("visible", "onVisibleChanged")
    m.top.observeField("originalVideoPlayer", "onOriginalVideoPlayerChanged")
    m.top.observeField("wasPlayingBeforeMultiview", "onWasPlayingBeforeMultiviewChanged")
    m.top.observeField("epgData", "onEPGDataChanged")
    m.top.observeField("bitmapCache", "onBitmapCacheChanged")
    m.top.observeField("focusedChild", "onFocusedChildChanged")

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

sub onBitmapCacheChanged()
    m.bitmapCache = m.top.bitmapCache
end sub

sub onEPGDataChanged()
    ' When EPG data arrives, preload sports logos based on actual matchups in EPG
    epgData = m.top.epgData
    if epgData = invalid or epgData.channels = invalid then return

    ' Only preload if we haven't done it yet for this EPG data
    if not m.epgDataPreloaded then
        preloadSportsLogosFromEPG(epgData)
        m.epgDataPreloaded = true
    end if
end sub

sub preloadSportsLogosFromEPG(epgData as Object)
    ' Collect unique team logo URIs from EPG programs
    teamLogosToPreload = {}

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
                ' Collect logo URIs for both teams
                logoUrl1 = GetTeamLogoUrlFast(matchup.team1, matchup.league, m.logoBaseUrl)
                logoUrl2 = GetTeamLogoUrlFast(matchup.team2, matchup.league, m.logoBaseUrl)

                if logoUrl1 <> invalid and logoUrl1 <> ""
                    teamLogosToPreload[logoUrl1] = true
                end if
                if logoUrl2 <> invalid and logoUrl2 <> ""
                    teamLogosToPreload[logoUrl2] = true
                end if
            end if
        end for
    end for

    ' Only preload if we have new logos and bitmap cache is available
    if m.bitmapCache <> invalid and teamLogosToPreload.count() > 0
        if type(m.bitmapCache) = "roAssociativeArray" and m.bitmapCache.doesExist("preload")
            ' Filter out already cached logos
            newLogos = {}
            for each uri in teamLogosToPreload
                if not m.bitmapCache.isCached(uri) then
                    newLogos[uri] = true
                end if
            end for

            if newLogos.count() > 0 then
                m.bitmapCache.preload(newLogos, m.preloadContainer)
            else
                print "MultiviewGrid: All team logos already cached"
            end if
        end if
    end if
end sub

function GetNCAAFTeamIdLocal(teamCode as String) as String
    ' Map team codes to ESPN numeric IDs
    idMap = {
        "air-force": "2005"
        "akron": "2006"
        "alabama": "333"
        "appalachian-state": "2026"
        "arizona": "12"
        "arizona-state": "9"
        "arkansas": "8"
        "arkansas-state": "2032"
        "army": "349"
        "auburn": "2"
        "ball-state": "2050"
        "baylor": "239"
        "boise-state": "68"
        "boston-college": "103"
        "bowling-green": "189"
        "buffalo": "2084"
        "byu": "252"
        "california": "25"
        "central-michigan": "2117"
        "charlotte": "2429"
        "cincinnati": "2132"
        "clemson": "228"
        "coastal-carolina": "324"
        "colorado": "38"
        "colorado-state": "36"
        "connecticut": "41"
        "duke": "150"
        "east-carolina": "151"
        "eastern-michigan": "2199"
        "florida": "57"
        "florida-atlantic": "2226"
        "florida-international": "2229"
        "florida-state": "52"
        "fresno-state": "278"
        "georgia": "61"
        "georgia-southern": "290"
        "georgia-state": "2247"
        "georgia-tech": "59"
        "hawaii": "62"
        "houston": "248"
        "illinois": "356"
        "indiana": "84"
        "iowa": "2294"
        "iowa-state": "66"
        "james-madison": "256"
        "kansas": "2305"
        "kansas-state": "2306"
        "kent-state": "2309"
        "kentucky": "96"
        "liberty": "2335"
        "louisiana": "309"
        "louisiana-monroe": "2433"
        "louisiana-tech": "2348"
        "louisville": "97"
        "lsu": "99"
        "marshall": "276"
        "maryland": "120"
        "memphis": "235"
        "miami": "2390"
        "miami-oh": "193"
        "michigan": "130"
        "michigan-state": "127"
        "middle-tennessee": "2393"
        "minnesota": "135"
        "mississippi-state": "344"
        "missouri": "142"
        "navy": "2426"
        "nc-state": "152"
        "nebraska": "158"
        "nevada": "2440"
        "new-mexico": "167"
        "new-mexico-state": "166"
        "north-carolina": "153"
        "north-texas": "249"
        "northern-illinois": "2459"
        "northwestern": "77"
        "notre-dame": "87"
        "ohio": "195"
        "ohio-state": "194"
        "oklahoma": "201"
        "oklahoma-state": "197"
        "old-dominion": "295"
        "ole-miss": "145"
        "oregon": "2483"
        "oregon-state": "204"
        "penn-state": "213"
        "pittsburgh": "221"
        "purdue": "2509"
        "rice": "242"
        "rutgers": "164"
        "sam-houston": "2534"
        "san-diego-state": "21"
        "san-jose-state": "23"
        "smu": "2567"
        "south-alabama": "6"
        "south-carolina": "2579"
        "south-florida": "58"
        "southern-miss": "2582"
        "stanford": "24"
        "syracuse": "183"
        "tcu": "2628"
        "temple": "218"
        "tennessee": "2633"
        "texas": "251"
        "texas-am": "245"
        "texas-state": "326"
        "texas-tech": "2641"
        "toledo": "2649"
        "troy": "2653"
        "tulane": "2655"
        "tulsa": "202"
        "uab": "5"
        "ucf": "2116"
        "ucla": "26"
        "umass": "113"
        "unlv": "2439"
        "usc": "30"
        "utah": "254"
        "utah-state": "328"
        "utep": "2638"
        "utsa": "2636"
        "vanderbilt": "238"
        "virginia": "258"
        "virginia-tech": "259"
        "wake-forest": "154"
        "washington": "264"
        "washington-state": "265"
        "west-virginia": "277"
        "western-kentucky": "98"
        "western-michigan": "2711"
        "wisconsin": "275"
        "wyoming": "2750"
    }

    if idMap.doesExist(teamCode)
        return idMap[teamCode]
    end if

    return ""
end function

sub precomputeTeamData()
    leagues = ["NCAAF", "NFL", "NBA", "MLB", "NHL"]

    for each leagueName in leagues
        if not m.leagueMaps.doesExist(leagueName) then goto nextLeague

        teams = m.leagueMaps[leagueName]

        for each teamName in teams
            teamCode = teams[teamName]
            cacheKey = leagueName + ":" + teamCode

            ' Use unified ESPN logo function for ALL leagues
            espnLogoUrl = GetESPNLogoUrlFast(teamName, leagueName)
            if espnLogoUrl <> ""
                m.teamLogoCache[cacheKey] = espnLogoUrl
            else
                ' Fallback to GitHub (if ESPN fails)
                githubLogoUrl = m.logoBaseUrl + LCase(leagueName) + "/" + teamCode + ".png"
                m.teamLogoCache[cacheKey] = githubLogoUrl
            end if

            ' Team colors (unchanged)
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

function getCachedTeamLogoUrl(teamCode as String, league as String) as String
    cacheKey = league + ":" + teamCode
    if m.teamLogoCache.doesExist(cacheKey)
        return m.teamLogoCache[cacheKey]
    end if
    return GetTeamLogoUrlFast(teamCode, league, m.logoBaseUrl)
end function

function getCachedTeamColor(teamCode as String, league as String) as String
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
    logo.loadWidth = 180
    logo.loadHeight = 80
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

sub onFocusedChildChanged()
    ' This fires when focus changes within the multiview component
    focusedChild = m.top.focusedChild

    if focusedChild = invalid
        ' Lost focus - try to reclaim it if we're supposed to be visible
        if m.top.visible
            m.top.setFocus(true)
        end if
    else
    end if
end sub

sub onVisibleChanged()
    if m.top.visible
        m.thumbnails = []
        m.thumbnailChannelIndices = []

        ' Don't preload again if already done
        if m.top.epgData <> invalid and not m.epgDataPreloaded then
            preloadSportsLogosFromEPG(m.top.epgData)
            m.epgDataPreloaded = true
        end if

        ' Pre-parse all channel matchups before displaying
        if m.channels.count() > 0
            preParseAllMatchups()
            m.selectedThumbnailIndex = 0
            setupMainChannel(0)
        end if

        ' Force focus after everything is set up
        m.top.setFocus(false)  ' Clear any stale focus
        m.top.setFocus(true)   ' Set fresh focus
    else
        ' Don't reset the preload flag when hiding
        ' Only reset when EPG data actually changes (handled in onEPGDataChanged)

        ' Clear label
        m.mainChannelLabel.text = ""
    end if
end sub

sub preParseAllMatchups()
    for i = 0 to m.channels.count() - 1
        channel = m.channels[i]

        nowPlaying = channel.cachedTitle
        if channel.cachedNowPlaying <> invalid and channel.cachedNowPlaying <> ""
            nowPlaying = channel.cachedNowPlaying
        end if

        ' Parse and cache immediately
        if not m.matchupCache.doesExist(nowPlaying)
            matchup = ParseTeamMatchupFast(nowPlaying, m.separatorPatterns, m.leagueMaps)
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

        ' Store the channelIndex for tracking
        if channel.doesExist("channelIndex")
            channel.cachedChannelIndex = channel.channelIndex
        else
            channel.cachedChannelIndex = -1
        end if
    end for

    if m.top.visible
        ' Reset tracking
        m.lastMainChannelLabel = ""
        m.currentlyPlayingChannelIndex = -1
        m.currentMainIndex = 0
        m.selectedThumbnailIndex = 0
        setupMainChannel(0)
    end if
end sub

sub setupMainChannel(index as Integer)
    if index < 0 or index >= m.channels.count() then return

    m.currentMainIndex = index
    channel = m.channels[index]

    ' Always update the label text
    labelText = channel.cachedTitle
    if channel.cachedNowPlaying <> invalid and channel.cachedNowPlaying <> ""
        labelText = channel.cachedNowPlaying
    end if

    m.mainChannelLabel.text = labelText
    m.lastMainChannelLabel = labelText

    ' Determine which channel we're switching to
    targetChannelIndex = -1
    if channel.doesExist("channelIndex")
        targetChannelIndex = channel.channelIndex
    else if channel.doesExist("cachedChannelIndex")
        targetChannelIndex = channel.cachedChannelIndex
    end if

    ' Check if we're already playing this channel
    if targetChannelIndex = m.currentlyPlayingChannelIndex
        updateThumbnails()
        return
    end if

    ' Check if this is the original stream
    if channel.cachedIsOriginal = true
        m.usingOriginalPlayer = true
        ' Send -999 to indicate original stream, but MainScene will decide
        ' whether to keep using it or reload based on m.hasSwitchedFromOriginal
        m.top.switchToChannelIndex = -999
        ' Store the actual channel index so MainScene can reload if needed
        m.top.originalChannelIndex = targetChannelIndex
        m.currentlyPlayingChannelIndex = targetChannelIndex
    else
        m.usingOriginalPlayer = false
        m.top.switchToChannelIndex = targetChannelIndex
        m.currentlyPlayingChannelIndex = targetChannelIndex
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
                matchup = ParseTeamMatchupFast(nowPlaying, m.separatorPatterns, m.leagueMaps)
                m.matchupCache[nowPlaying] = matchup
            end if

            isSports = (matchup <> invalid)
            needsUpdate = (thumb.lastIsSports = invalid or thumb.lastIsSports <> isSports)

            if isSports
                team1Url = getCachedTeamLogoUrl(matchup.team1, matchup.league)
                team2Url = getCachedTeamLogoUrl(matchup.team2, matchup.league)
                team1Color = getCachedTeamColor(matchup.team1, matchup.league)
                team2Color = getCachedTeamColor(matchup.team2, matchup.league)

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

    ' Get the channel index in the m.channels array that this thumbnail represents
    newMainChannelIndex = m.thumbnailChannelIndices[thumbIndex]
    if newMainChannelIndex < 0 or newMainChannelIndex >= m.channels.count() then return

    ' Don't swap if already the main channel
    if newMainChannelIndex = m.currentMainIndex then
        return
    end if

    ' Save the current main and selected channels
    oldMainChannel = m.channels[m.currentMainIndex]
    newMainChannel = m.channels[newMainChannelIndex]

    ' Build new channel order:
    ' 1. New main channel goes first
    ' 2. Old main channel goes where the new main was
    ' 3. Everything else stays in order
    newChannelOrder = []

    ' Add new main channel first
    newChannelOrder.push(newMainChannel)

    ' Add all other channels, replacing the old position with old main
    for i = 0 to m.channels.count() - 1
        if i = m.currentMainIndex then
            ' Skip old main, we'll add it in the right spot
            continue for
        else if i = newMainChannelIndex then
            ' Replace new main's old position with old main
            newChannelOrder.push(oldMainChannel)
        else
            ' Keep all other channels in order
            newChannelOrder.push(m.channels[i])
        end if
    end for

    ' Update the channels array
    m.channels = newChannelOrder

    ' Clear the selection highlight on the old thumbnail position
    oldThumb = m.thumbnails[m.selectedThumbnailIndex]
    oldThumb.borderTop.opacity = 0
    oldThumb.borderBottom.opacity = 0
    oldThumb.borderLeft.opacity = 0
    oldThumb.borderRight.opacity = 0

    ' Keep the selector at the same thumbnail position
    ' (which now shows the old main channel after the swap)
    ' Don't change m.selectedThumbnailIndex - it stays at thumbIndex

    ' The new main is now always at index 0
    setupMainChannel(0)

    ' Re-apply the border to the same thumbnail position
    ' (updateThumbnails is called by setupMainChannel, which will set borders)
end sub

sub restoreOriginalVideo()
    if m.originalVideoPlayer <> invalid
        ' Restore original video player to full screen
        ' Don't touch visibility - it should already be visible
        m.originalVideoPlayer.translation = [0, 0]
        m.originalVideoPlayer.width = 1920
        m.originalVideoPlayer.height = 1080
    end if
end sub

sub resetMultiviewState()
    m.channels = []
    m.thumbnailChannelIndices = []
    m.selectedThumbnailIndex = 0
    m.currentMainIndex = 0

    ' Clear thumbnails visually
    for each thumb in m.thumbnails
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
    end for

    ' Clear matchup cache
    m.matchupCache = {}

    ' Reset count
    m.visibleThumbnailCount = 0
end sub

function onKeyEvent(key as String, press as Boolean) as Boolean
    if not press then return false

    if key = "back"
        ' Resize the video BEFORE hiding multiview to avoid black screen
        restoreOriginalVideo()
        m.top.shouldRestoreVideo = true

        ' Clear all multiview data so it does not persist
        resetMultiviewState()

        ' Hide multiview after resize
        m.top.visible = false

        ' IMPORTANT: Signal MainScene to reset isMultiviewMode immediately
        ' Using a new field so MainScene can reset the flag right away
        m.top.addField("exitMultiview", "boolean", true)
        m.top.exitMultiview = true

        return true
    else if key = "up"
        if m.selectedThumbnailIndex > 0
            m.selectedThumbnailIndex = m.selectedThumbnailIndex - 1
            updateThumbnails()
        end if
        return true
    else if key = "down"
        if m.selectedThumbnailIndex < m.visibleThumbnailCount - 1
            m.selectedThumbnailIndex = m.selectedThumbnailIndex + 1
            updateThumbnails()
        end if
        return true
    else if key = "OK" or key = "right"
        swapToThumbnail(m.selectedThumbnailIndex)
        return true
    end if

    return false
end function