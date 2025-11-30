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

    ' Create 5 thumbnail slots
    for i = 0 to 4
        thumb = createThumbnail(i)
        m.thumbnails.push(thumb)
        m.thumbnailChannelIndices.push(-1)
    end for
    
    m.mainVideo.observeField("state", "onMainVideoStateChange")
    m.top.observeField("channels", "onChannelsChanged")
    m.top.observeField("visible", "onVisibleChanged")
end sub

function createThumbnail(index as Integer) as Object
    yPos = 10 + (index * 185)
    thumb = {
        index: index
        yPos: yPos
        background: invalid
        border: invalid
        logo: invalid
        teamLogo1: invalid
        teamLogo2: invalid
        vsLabel: invalid
        label: invalid
    }

    ' Background
    bg = createObject("roSGNode", "Rectangle")
    bg.translation = [10, yPos]
    bg.width = 360
    bg.height = 180
    bg.color = "0x1A1A1AFF"
    bg.visible = false
    m.thumbnailContainer.appendChild(bg)
    thumb.background = bg

    ' Border
    border = createObject("roSGNode", "Rectangle")
    border.translation = [10, yPos]
    border.width = 360
    border.height = 180
    border.color = "0x0078D4FF"
    border.opacity = 0
    border.visible = false
    m.thumbnailContainer.appendChild(border)
    thumb.border = border

    ' Channel logo (for non-sports)
    logo = createObject("roSGNode", "Poster")
    logo.translation = [10 + 90, yPos + 15]
    logo.width = 180
    logo.height = 100
    logo.horizAlign = "center"
    logo.vertAlign = "center"
    logo.loadDisplayMode = "scaleToFit"
    logo.visible = false
    m.thumbnailContainer.appendChild(logo)
    thumb.logo = logo

    ' Team Logo 1 (left side)
    teamLogo1 = createObject("roSGNode", "Poster")
    teamLogo1.translation = [10 + 20, yPos + 10]
    teamLogo1.width = 120
    teamLogo1.height = 120
    teamLogo1.horizAlign = "center"
    teamLogo1.vertAlign = "center"
    teamLogo1.loadDisplayMode = "scaleToFit"
    teamLogo1.visible = false
    m.thumbnailContainer.appendChild(teamLogo1)
    thumb.teamLogo1 = teamLogo1

    ' VS Label
    vsLabel = createObject("roSGNode", "Label")
    vsLabel.translation = [10 + 150, yPos + 50]
    vsLabel.width = 60
    vsLabel.height = 40
    vsLabel.text = "vs"
    vsLabel.font = "font:MediumBoldSystemFont"
    vsLabel.color = "0xCCCCCCFF"
    vsLabel.horizAlign = "center"
    vsLabel.vertAlign = "center"
    vsLabel.visible = false
    m.thumbnailContainer.appendChild(vsLabel)
    thumb.vsLabel = vsLabel

    ' Team Logo 2 (right side)
    teamLogo2 = createObject("roSGNode", "Poster")
    teamLogo2.translation = [10 + 220, yPos + 10]
    teamLogo2.width = 120
    teamLogo2.height = 120
    teamLogo2.horizAlign = "center"
    teamLogo2.vertAlign = "center"
    teamLogo2.loadDisplayMode = "scaleToFit"
    teamLogo2.visible = false
    m.thumbnailContainer.appendChild(teamLogo2)
    thumb.teamLogo2 = teamLogo2

    ' Now Playing label
    label = createObject("roSGNode", "Label")
    label.translation = [10, yPos + 125]
    label.width = 360
    label.height = 50
    label.font = "font:SmallBoldSystemFont"
    label.font.size = 26
    label.color = "0xCCCCCCFF"
    label.horizAlign = "center"
    label.vertAlign = "center"
    label.wrap = true
    label.visible = false
    m.thumbnailContainer.appendChild(label)
    thumb.label = label

    return thumb
end function

sub onVisibleChanged()
    if m.top.visible
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

    ' Update label with nowPlaying if available
    labelText = channel.title
    if channel.doesExist("nowPlaying") and channel.nowPlaying <> invalid and channel.nowPlaying <> ""
        labelText = channel.nowPlaying
    end if
    m.mainChannelLabel.text = labelText

    ' Update thumbnails
    updateThumbnails()
end sub

sub updateThumbnails()
    thumbIndex = 0

    ' Loop through channels and fill up to 5 thumbnails
    for i = 0 to m.channels.count() - 1
        ' Skip main channel and limit to 5 thumbnails
        if i <> m.currentMainIndex and thumbIndex <= 4 then

            channel = m.channels[i]
            thumb = m.thumbnails[thumbIndex]

            ' Get now playing text
            nowPlaying = channel.title
            if channel.doesExist("nowPlaying") then
                if channel.nowPlaying <> invalid and channel.nowPlaying <> "" then
                    nowPlaying = channel.nowPlaying
                end if
            end if

            ' Check if this is a sports matchup
            matchup = parseTeamMatchup(nowPlaying)
            
            if matchup <> invalid
                ' Show team logos
                team1Url = getTeamLogoUrl(matchup.team1, matchup.league)
                team2Url = getTeamLogoUrl(matchup.team2, matchup.league)
                
                if thumb.teamLogo1.uri <> team1Url then thumb.teamLogo1.uri = team1Url
                if thumb.teamLogo2.uri <> team2Url then thumb.teamLogo2.uri = team2Url
                
                thumb.teamLogo1.visible = true
                thumb.teamLogo2.visible = true
                thumb.vsLabel.visible = true
                thumb.logo.visible = false
            else
                ' Show channel logo (non-sports)
                if channel.doesExist("logo") and channel.logo <> invalid and channel.logo <> "" then
                    if thumb.logo.uri <> channel.logo then thumb.logo.uri = channel.logo
                else
                    if thumb.logo.uri <> "" then thumb.logo.uri = ""
                end if
                
                thumb.logo.visible = true
                thumb.teamLogo1.visible = false
                thumb.teamLogo2.visible = false
                thumb.vsLabel.visible = false
            end if

            ' --- Update label / Now Playing ---
            if thumb.label.text <> nowPlaying then thumb.label.text = nowPlaying

            ' --- Store channel index ---
            m.thumbnailChannelIndices[thumbIndex] = i

            ' --- Update selection border ---
            if thumbIndex = m.selectedThumbnailIndex then
                thumb.border.opacity = 1.0
            else
                thumb.border.opacity = 0
            end if

            ' --- Show thumbnail components ---
            thumb.background.visible = true
            thumb.border.visible = true
            thumb.label.visible = true

            thumbIndex = thumbIndex + 1
        end if

        ' Stop if we filled all 5 thumbnails
        if thumbIndex > 4 then exit for
    end for

    ' Hide any remaining unused thumbnails
    for i = thumbIndex to 4
        thumb = m.thumbnails[i]
        thumb.background.visible = false
        thumb.border.visible = false
        thumb.logo.visible = false
        thumb.teamLogo1.visible = false
        thumb.teamLogo2.visible = false
        thumb.vsLabel.visible = false
        thumb.label.visible = false
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
    m.thumbnails[m.selectedThumbnailIndex].border.opacity = 0
    m.selectedThumbnailIndex = thumbIndex
    m.thumbnails[m.selectedThumbnailIndex].border.opacity = 1

    ' Play new main channel
    m.mainVideo.control = "stop"
    playMainChannel(newChannelIndex)
end sub

sub onMainVideoStateChange()
    if m.mainVideo.state = "error"
        errorCode = m.mainVideo.errorCode
    end if
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
            "Trail Blazers": "trail-blazers", "Portland Trail Blazers": "trail-blazers"
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