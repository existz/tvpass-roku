''' Shared utility functions and data structures '''

function GetLeagueMaps() as Object
    return {
        NFL: GetNFLTeams()
        NBA: GetNBATeams()
        MLB: GetMLBTeams()
        NHL: GetNHLTeams()
        NCAAF: GetNCAAFTeams()
    }
end function

function GetSportsKeywords() as Object
    return ["College Basketball", "College Football", "College Baseball", "NFL Football", "NBA Basketball", "NBA G League Basketball", "MLB Baseball", "NHL Hockey"]
end function

function GetSeparatorPatterns() as Object
    return [" vs ", " vs. ", " @ ", " at "]
end function

function IsSportsProgram(title as String, keywords as Object) as Boolean
    for each keyword in keywords
        if title.Instr(keyword) >= 0 then return true
    end for
    return false
end function

function ParseTeamMatchupFast(programTitle as String, separatorPatterns as Object, leagueMaps as Object) as Object
    if programTitle = invalid or programTitle = "" then return invalid

    ' Quick check for any separator
    hasSeparator = false
    separatorFound = ""
    for each sep in separatorPatterns
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

    league = DetectLeagueFromTeamsFast(team1Name, team2Name, leagueMaps)
    if league = invalid then return invalid

    team1Code = GetTeamCodeFast(team1Name, league, leagueMaps)
    team2Code = GetTeamCodeFast(team2Name, league, leagueMaps)

    if team1Code = invalid or team2Code = invalid then return invalid

    return {
        league: league
        team1: team1Code
        team2: team2Code
    }
end function

function DetectLeagueFromTeamsFast(team1 as String, team2 as String, leagueMaps as Object) as Dynamic
    leagues = ["NCAAF", "NFL", "NBA", "MLB", "NHL"]

    for each leagueName in leagues
        if not leagueMaps.doesExist(leagueName) then goto nextLeague

        teams = leagueMaps[leagueName]
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

function GetTeamCodeFast(teamName as String, league as String, leagueMaps as Object) as Dynamic
    if not leagueMaps.doesExist(league) then return invalid

    teams = leagueMaps[league]
    for each key in teams
        if teamName.Instr(key) >= 0
            return teams[key]
        end if
    end for

    return invalid
end function

function GetTeamLogoUrlFast(teamCode as String, league as String, logoBaseUrl as String) as String
    ' NCAAF uses ESPN CDN with numeric IDs
    if league = "NCAAF"
        ' Get the numeric ID for this team
        teamId = GetNCAAFTeamId(teamCode)
        if teamId <> invalid and teamId <> ""
            return "https://a.espncdn.com/i/teamlogos/ncaa/500-dark/" + teamId + ".png"
        end if
        return ""
    end if

    ' Other leagues use the GitHub repo
    urlParts = [logoBaseUrl, league, "/", teamCode, ".png"]
    return urlParts.Join("")
end function

function GetNCAAFTeamId(teamCode as String) as String
    ' Map team codes to ESPN numeric IDs from the gist
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