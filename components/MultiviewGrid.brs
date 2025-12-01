sub init()
    m.mainVideo = m.top.findNode("mainVideo")
    m.thumbnailContainer = m.top.findNode("thumbnailContainer")
    m.mainChannelLabel = m.top.findNode("mainChannelLabel")
    
    m.thumbnails = []
    m.thumbnailChannelIndices = []
    m.channels = []
    m.currentMainIndex = 0
    m.selectedThumbnailIndex = 0
    m.visibleThumbnailCount = 0

    ' Don't create thumbnails here - they'll be created when needed
    ' This ensures they have all the latest properties
    
    m.mainVideo.observeField("state", "onMainVideoStateChange")
    m.top.observeField("channels", "onChannelsChanged")
    m.top.observeField("visible", "onVisibleChanged")
end sub

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
        vsLabel: invalid
        label: invalid
        borderTop: invalid
        borderBottom: invalid
        borderLeft: invalid
        borderRight: invalid
    }

    ' Background (for non-sports)
    bg = createObject("roSGNode", "Rectangle")
    bg.translation = [0, 0]
    bg.width = 360
    bg.height = 140
    bg.color = "0x1A1A1AFF"
    bg.visible = false
    container.appendChild(bg)
    thumb.background = bg

    ' Team 1 Background (left half)
    team1Bg = createObject("roSGNode", "Rectangle")
    team1Bg.translation = [0, 0]
    team1Bg.width = 180
    team1Bg.height = 140
    team1Bg.color = "0x000000FF"
    team1Bg.visible = false
    container.appendChild(team1Bg)
    thumb.team1Background = team1Bg

    ' Team 2 Background (right half)
    team2Bg = createObject("roSGNode", "Rectangle")
    team2Bg.translation = [180, 0]
    team2Bg.width = 180
    team2Bg.height = 140
    team2Bg.color = "0x000000FF"
    team2Bg.visible = false
    container.appendChild(team2Bg)
    thumb.team2Background = team2Bg

    ' Channel logo (for non-sports)
    logo = createObject("roSGNode", "Poster")
    logo.translation = [90, 10]
    logo.width = 180
    logo.height = 80
    logo.loadDisplayMode = "scaleToFit"
    logo.visible = false
    container.appendChild(logo)
    thumb.logo = logo

    ' Team Logo 1 (left side, centered on team background)
    teamLogo1 = createObject("roSGNode", "Poster")
    teamLogo1.translation = [40, 20]
    teamLogo1.width = 100
    teamLogo1.height = 100
    teamLogo1.loadDisplayMode = "scaleToFit"
    teamLogo1.visible = false
    container.appendChild(teamLogo1)
    thumb.teamLogo1 = teamLogo1

    ' Team Logo 2 (right side, centered on team background)
    teamLogo2 = createObject("roSGNode", "Poster")
    teamLogo2.translation = [220, 20]
    teamLogo2.width = 100
    teamLogo2.height = 100
    teamLogo2.loadDisplayMode = "scaleToFit"
    teamLogo2.visible = false
    container.appendChild(teamLogo2)
    thumb.teamLogo2 = teamLogo2

    ' VS Label (removed for sports)
    vsLabel = createObject("roSGNode", "Label")
    vsLabel.translation = [150, 40]
    vsLabel.width = 60
    vsLabel.height = 40
    vsLabel.text = ""
    vsLabel.font = "font:MediumBoldSystemFont"
    vsLabel.color = "0xCCCCCCFF"
    vsLabel.horizAlign = "center"
    vsLabel.vertAlign = "center"
    vsLabel.visible = false
    container.appendChild(vsLabel)
    thumb.vsLabel = vsLabel

    ' Now Playing label
    label = createObject("roSGNode", "Label")
    label.translation = [0, 95]
    label.width = 360
    label.height = 40
    label.font = "font:SmallBoldSystemFont"
    label.font.size = 22
    label.color = "0xCCCCCCFF"
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
    borderTop.color = "0xFFFFFFFF"
    borderTop.opacity = 0
    container.appendChild(borderTop)
    thumb.borderTop = borderTop

    ' Bottom border
    borderBottom = createObject("roSGNode", "Rectangle")
    borderBottom.translation = [0, 136]
    borderBottom.width = 360
    borderBottom.height = 4
    borderBottom.color = "0xFFFFFFFF"
    borderBottom.opacity = 0
    container.appendChild(borderBottom)
    thumb.borderBottom = borderBottom

    ' Left border
    borderLeft = createObject("roSGNode", "Rectangle")
    borderLeft.translation = [0, 0]
    borderLeft.width = 4
    borderLeft.height = 140
    borderLeft.color = "0xFFFFFFFF"
    borderLeft.opacity = 0
    container.appendChild(borderLeft)
    thumb.borderLeft = borderLeft

    ' Right border
    borderRight = createObject("roSGNode", "Rectangle")
    borderRight.translation = [356, 0]
    borderRight.width = 4
    borderRight.height = 140
    borderRight.color = "0xFFFFFFFF"
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
    m.mainChannelLabel.text = labelText

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
            matchup = parseTeamMatchup(nowPlaying)
            
            isSports = (matchup <> invalid)
            
            if isSports 
                ' Show team backgrounds and logos
                team1Url = getTeamLogoUrl(matchup.team1, matchup.league)
                team2Url = getTeamLogoUrl(matchup.team2, matchup.league)
                
                ' Get team colors
                team1Color = getTeamColor(matchup.team1, matchup.league)
                team2Color = getTeamColor(matchup.team2, matchup.league)
                
                ' Set background colors
                thumb.team1Background.color = team1Color
                thumb.team2Background.color = team2Color
                
                ' Set logos only if changed
                if thumb.teamLogo1.uri <> team1Url then thumb.teamLogo1.uri = team1Url
                if thumb.teamLogo2.uri <> team2Url then thumb.teamLogo2.uri = team2Url
                
            else
                ' Show channel logo (non-sports) - use cached value
                logoUrl = channel.cachedLogo
                if logoUrl <> invalid and logoUrl <> "" then
                    if thumb.logo.uri <> logoUrl then thumb.logo.uri = logoUrl
                else
                    if thumb.logo.uri <> "" then thumb.logo.uri = ""
                end if
                
                ' Update label for non-sports
                if thumb.label.text <> nowPlaying then thumb.label.text = nowPlaying
            end if

            ' Batch visibility updates
            sportsVisible = isSports
            nonSportsVisible = not isSports
            
            thumb.team1Background.visible = sportsVisible
            thumb.team2Background.visible = sportsVisible
            thumb.teamLogo1.visible = sportsVisible
            thumb.teamLogo2.visible = sportsVisible
            thumb.background.visible = nonSportsVisible
            thumb.logo.visible = nonSportsVisible
            thumb.label.visible = nonSportsVisible
            thumb.vsLabel.visible = false

            ' --- Store channel index ---
            m.thumbnailChannelIndices[thumbIndex] = i

            ' --- Update selection border outline ---
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
        thumb.vsLabel.visible = false
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

function parseTeamMatchup(programTitle as String) as Object
    ' Returns { league: "NFL/MLB/NBA", team1: "BUF", team2: "ARI" } or invalid
    if programTitle = invalid or programTitle = "" then return invalid
    
    print "parseTeamMatchup: Analyzing: "; programTitle
    
    ' Check for "vs" or "@" pattern
    hasVs = (programTitle.Instr(" vs ") >= 0 or programTitle.Instr(" vs. ") >= 0)
    hasAt = (programTitle.Instr(" @ ") >= 0 or programTitle.Instr(" at ") >= 0)
    
    if not hasVs and not hasAt then 
        print "parseTeamMatchup: No vs/@ found"
        return invalid
    end if
    
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
    
    if teams = invalid or teams.count() < 2 then 
        print "parseTeamMatchup: Failed to split teams"
        return invalid
    end if
    
    team1Name = teams[0].Trim()
    team2Name = teams[1].Trim()
    
    ' Remove date/time info from team2Name (e.g., "(11/30 1:00 PM ET)")
    parenPos = team2Name.Instr("(")
    if parenPos >= 0
        team2Name = team2Name.Left(parenPos).Trim()
    end if
    
    print "parseTeamMatchup: Team 1 name: "; team1Name
    print "parseTeamMatchup: Team 2 name: "; team2Name
    
    ' Determine league by checking team names against known teams
    league = detectLeagueFromTeams(team1Name, team2Name)
    
    if league = invalid then 
        print "parseTeamMatchup: No league identified"
        return invalid
    end if
    
    print "parseTeamMatchup: League: "; league
    
    ' Get team codes
    team1Code = getTeamCode(team1Name, league)
    team2Code = getTeamCode(team2Name, league)
    
    print "parseTeamMatchup: Team 1 code: "; team1Code
    print "parseTeamMatchup: Team 2 code: "; team2Code
    
    if team1Code = invalid or team2Code = invalid then 
        print "parseTeamMatchup: Failed to get team codes"
        return invalid
    end if
    
    return {
        league: league
        team1: team1Code
        team2: team2Code
    }
end function

function detectLeagueFromTeams(team1 as String, team2 as String) as Dynamic
    ' Try NFL first
    if getTeamCode(team1, "NFL") <> invalid and getTeamCode(team2, "NFL") <> invalid
        return "NFL"
    end if
    
    ' Try NBA
    if getTeamCode(team1, "NBA") <> invalid and getTeamCode(team2, "NBA") <> invalid
        return "NBA"
    end if
    
    ' Try MLB
    if getTeamCode(team1, "MLB") <> invalid and getTeamCode(team2, "MLB") <> invalid
        return "MLB"
    end if
    
    return invalid
end function

function getTeamCode(teamName as String, league as String) as Dynamic
    print "getTeamCode: Looking for '"; teamName; "' in league "; league
    
    ' NFL Teams - return lowercase team name for URL
    if league = "NFL"
        nflTeams = {
            "Cardinals": "cardinals", "Arizona Cardinals": "cardinals"
            "Falcons": "falcons", "Atlanta Falcons": "falcons"
            "Ravens": "ravens", "Baltimore Ravens": "ravens"
            "Bills": "bills", "Buffalo Bills": "bills"
            "Panthers": "panthers", "Carolina Panthers": "panthers"
            "Bears": "bears", "Chicago Bears": "bears"
            "Bengals": "bengals", "Cincinnati Bengals": "bengals"
            "Browns": "browns", "Cleveland Browns": "browns"
            "Cowboys": "cowboys", "Dallas Cowboys": "cowboys"
            "Broncos": "broncos", "Denver Broncos": "broncos"
            "Lions": "lions", "Detroit Lions": "lions"
            "Packers": "packers", "Green Bay Packers": "packers"
            "Texans": "texans", "Houston Texans": "texans"
            "Colts": "colts", "Indianapolis Colts": "colts"
            "Jaguars": "jaguars", "Jacksonville Jaguars": "jaguars"
            "Chiefs": "chiefs", "Kansas City Chiefs": "chiefs"
            "Raiders": "raiders", "Las Vegas Raiders": "raiders"
            "Chargers": "chargers", "Los Angeles Chargers": "chargers"
            "Rams": "rams", "Los Angeles Rams": "rams"
            "Dolphins": "dolphins", "Miami Dolphins": "dolphins"
            "Vikings": "vikings", "Minnesota Vikings": "vikings"
            "Patriots": "patriots", "New England Patriots": "patriots"
            "Saints": "saints", "New Orleans Saints": "saints"
            "Giants": "giants", "New York Giants": "giants"
            "Jets": "jets", "New York Jets": "jets"
            "Eagles": "eagles", "Philadelphia Eagles": "eagles"
            "Steelers": "steelers", "Pittsburgh Steelers": "steelers"
            "49ers": "49ers", "San Francisco 49ers": "49ers"
            "Seahawks": "seahawks", "Seattle Seahawks": "seahawks"
            "Buccaneers": "buccaneers", "Tampa Bay Buccaneers": "buccaneers"
            "Titans": "titans", "Tennessee Titans": "titans"
            "Commanders": "commanders", "Washington Commanders": "commanders"
        }
        
        for each key in nflTeams
            if teamName.Instr(key) >= 0
                print "getTeamCode: Found match for '"; key; "' -> "; nflTeams[key]
                return nflTeams[key]
            end if
        end for
    end if
    
    ' NBA Teams - return lowercase team name for URL
    if league = "NBA"
        nbaTeams = {
            "Hawks": "hawks", "Atlanta Hawks": "hawks"
            "Celtics": "celtics", "Boston Celtics": "celtics"
            "Nets": "nets", "Brooklyn Nets": "nets"
            "Hornets": "hornets", "Charlotte Hornets": "hornets"
            "Bulls": "bulls", "Chicago Bulls": "bulls"
            "Cavaliers": "cavaliers", "Cleveland Cavaliers": "cavaliers"
            "Mavericks": "mavericks", "Dallas Mavericks": "mavericks"
            "Nuggets": "nuggets", "Denver Nuggets": "nuggets"
            "Pistons": "pistons", "Detroit Pistons": "pistons"
            "Warriors": "warriors", "Golden State Warriors": "warriors"
            "Rockets": "rockets", "Houston Rockets": "rockets"
            "Pacers": "pacers", "Indiana Pacers": "pacers"
            "Clippers": "clippers", "LA Clippers": "clippers", "Los Angeles Clippers": "clippers"
            "Lakers": "lakers", "LA Lakers": "lakers", "Los Angeles Lakers": "lakers"
            "Grizzlies": "grizzlies", "Memphis Grizzlies": "grizzlies"
            "Heat": "heat", "Miami Heat": "heat"
            "Bucks": "bucks", "Milwaukee Bucks": "bucks"
            "Timberwolves": "timberwolves", "Minnesota Timberwolves": "timberwolves"
            "Pelicans": "pelicans", "New Orleans Pelicans": "pelicans"
            "Knicks": "knicks", "New York Knicks": "knicks"
            "Thunder": "thunder", "Oklahoma City Thunder": "thunder"
            "Magic": "magic", "Orlando Magic": "magic"
            "76ers": "76ers", "Philadelphia 76ers": "76ers"
            "Suns": "suns", "Phoenix Suns": "suns"
            "Trail Blazers": "trailblazers", "Portland Trail Blazers": "trailblazers"
            "Kings": "kings", "Sacramento Kings": "kings"
            "Spurs": "spurs", "San Antonio Spurs": "spurs"
            "Raptors": "raptors", "Toronto Raptors": "raptors"
            "Jazz": "jazz", "Utah Jazz": "jazz"
            "Wizards": "wizards", "Washington Wizards": "wizards"
        }
        
        for each key in nbaTeams
            if teamName.Instr(key) >= 0
                print "getTeamCode: Found match for '"; key; "' -> "; nbaTeams[key]
                return nbaTeams[key]
            end if
        end for
    end if
    
    ' MLB Teams - return lowercase team name for URL
    if league = "MLB"
        mlbTeams = {
            "Diamondbacks": "diamondbacks", "Arizona Diamondbacks": "diamondbacks"
            "Braves": "braves", "Atlanta Braves": "braves"
            "Orioles": "orioles", "Baltimore Orioles": "orioles"
            "Red Sox": "red-sox", "Boston Red Sox": "red-sox"
            "Cubs": "cubs", "Chicago Cubs": "cubs"
            "White Sox": "white-sox", "Chicago White Sox": "white-sox"
            "Reds": "reds", "Cincinnati Reds": "reds"
            "Guardians": "guardians", "Cleveland Guardians": "guardians"
            "Rockies": "rockies", "Colorado Rockies": "rockies"
            "Tigers": "tigers", "Detroit Tigers": "tigers"
            "Astros": "astros", "Houston Astros": "astros"
            "Royals": "royals", "Kansas City Royals": "royals"
            "Angels": "angels", "Los Angeles Angels": "angels"
            "Dodgers": "dodgers", "Los Angeles Dodgers": "dodgers"
            "Marlins": "marlins", "Miami Marlins": "marlins"
            "Brewers": "brewers", "Milwaukee Brewers": "brewers"
            "Twins": "twins", "Minnesota Twins": "twins"
            "Mets": "mets", "New York Mets": "mets"
            "Yankees": "yankees", "New York Yankees": "yankees"
            "Athletics": "athletics", "Oakland Athletics": "athletics"
            "Phillies": "phillies", "Philadelphia Phillies": "phillies"
            "Pirates": "pirates", "Pittsburgh Pirates": "pirates"
            "Padres": "padres", "San Diego Padres": "padres"
            "Giants": "giants", "San Francisco Giants": "giants"
            "Mariners": "mariners", "Seattle Mariners": "mariners"
            "Cardinals": "cardinals", "St. Louis Cardinals": "cardinals"
            "Rays": "rays", "Tampa Bay Rays": "rays"
            "Rangers": "rangers", "Texas Rangers": "rangers"
            "Blue Jays": "blue-jays", "Toronto Blue Jays": "blue-jays"
            "Nationals": "nationals", "Washington Nationals": "nationals"
        }
        
        for each key in mlbTeams
            if teamName.Instr(key) >= 0
                print "getTeamCode: Found match for '"; key; "' -> "; mlbTeams[key]
                return mlbTeams[key]
            end if
        end for
    end if
    
    print "getTeamCode: No match found for '"; teamName; "'"
    return invalid
end function

function getTeamLogoUrl(teamCode as String, league as String) as String
    baseUrl = "https://raw.githubusercontent.com/existz/team-logos/master/"
    return baseUrl + league + "/" + teamCode + ".png"
end function

function getTeamColor(teamCode as String, league as String) as String
    ' NFL Team Colors
    if league = "NFL"
        nflColors = {
            "cardinals": "0x97233FFF"
            "falcons": "0xA71930FF"
            "ravens": "0x241773FF"
            "bills": "0x00338DFF"
            "panthers": "0x0085CAFF"
            "bears": "0x0B162AFF"
            "bengals": "0xFB4F14FF"
            "browns": "0x311D00FF"
            "cowboys": "0x041E42FF"
            "broncos": "0xFB4F14FF"
            "lions": "0x0076B6FF"
            "packers": "0x203731FF"
            "texans": "0x03203FFF"
            "colts": "0x002C5FFF"
            "jaguars": "0x006778FF"
            "chiefs": "0xE31837FF"
            "raiders": "0x000000FF"
            "chargers": "0x0080C6FF"
            "rams": "0x003594FF"
            "dolphins": "0x008E97FF"
            "vikings": "0x4F2683FF"
            "patriots": "0x002244FF"
            "saints": "0x000000FF"
            "giants": "0x0D2266FF"
            "jets": "0x125740FF"
            "eagles": "0x004C54FF"
            "steelers": "0x000000FF"
            "49ers": "0xAA0000FF"
            "seahawks": "0x002244FF"
            "buccaneers": "0xA71930FF"
            "titans": "0x0C2340FF"
            "commanders": "0x5A1414FF"
        }
        
        if nflColors.doesExist(teamCode)
            return nflColors[teamCode]
        end if
    end if
    
    ' NBA Team Colors
    if league = "NBA"
        nbaColors = {
            "hawks": "0xE03C3CFF"
            "celtics": "0x007A33FF"
            "nets": "0x505050FF"
            "hornets": "0x00778DFF"
            "bulls": "0xCE1141FF"
            "cavaliers": "0x6F263DFF"
            "mavericks": "0x00538CFF"
            "nuggets": "0x0E2240FF"
            "pistons": "0x1D428AFF"
            "warriors": "0x1D428AFF"
            "rockets": "0xCE1141FF"
            "pacers": "0x002D62FF"
            "clippers": "0xC60C30FF"
            "lakers": "0xFFFFFFFF"
            "grizzlies": "0x12173FFF"
            "heat": "0x98002EFF"
            "bucks": "0x00471BFF"
            "timberwolves": "0x0C2C56FF"
            "pelicans": "0x0C2C56FF"
            "knicks": "0x006BB6FF"
            "thunder": "0x007DC5FF"
            "magic": "0x0072CEFF"
            "76ers": "0xED174CFF"
            "suns": "0xE56020FF"
            "trailblazers": "0xE03C3CFF"
            "kings": "0x5A2D81FF"
            "spurs": "0x000000FF"
            "raptors": "0xCE1141FF"
            "jazz": "0x00471BFF"
            "wizards": "0x002B81FF"
        }
        
        if nbaColors.doesExist(teamCode)
            return nbaColors[teamCode]
        end if
    end if
    
    ' MLB Team Colors
    if league = "MLB"
        mlbColors = {
            "diamondbacks": "0xA71930FF"
            "braves": "0x13274FFF"
            "orioles": "0xDF4601FF"
            "red-sox": "0xBD3039FF"
            "cubs": "0x0E3386FF"
            "white-sox": "0x27251FFF"
            "reds": "0xC6011FFF"
            "guardians": "0x00385DFF"
            "rockies": "0x333366FF"
            "tigers": "0x0C2340FF"
            "astros": "0x002D72FF"
            "royals": "0x005A9CFF"
            "angels": "0xBA0021FF"
            "dodgers": "0x005A9CFF"
            "marlins": "0x0077C0FF"
            "brewers": "0x0A2351FF"
            "twins": "0x002B5CFF"
            "mets": "0x005A9CFF"
            "yankees": "0x0C2340FF"
            "athletics": "0x004C38FF"
            "phillies": "0xE81828FF"
            "pirates": "0x000000FF"
            "padres": "0x2F241DFF"
            "giants": "0xFD5A1EFF"
            "mariners": "0x0C2C56FF"
            "cardinals": "0xC41E3AFF"
            "rays": "0x092C5CFF"
            "rangers": "0x003278FF"
            "blue-jays": "0x134A8EFF"
            "nationals": "0xAB0003FF"
        }
        
        if mlbColors.doesExist(teamCode)
            return mlbColors[teamCode]
        end if
    end if
    
    ' Default color if not found
    return "0x1A1A1AFF"
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