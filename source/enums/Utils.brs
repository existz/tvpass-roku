''' Shared utility functions and data structures '''

function GetLeagueMaps() as Object
    return {
        NFL: GetNFLTeams()
        NBA: GetNBATeams()
        MLB: GetMLBTeams()
        NHL: GetNHLTeams()
        NCAA: GetNCAATeams()
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
    ' PRIORITIZE pro leagues over college (NFL > NBA > MLB > NHL > NCAA)
    proLeagues = ["NFL", "NBA", "MLB", "NHL"]
    collegeLeagues = ["NCAA"]

    ' Check pro leagues first
    for each leagueName in proLeagues
        if not leagueMaps.doesExist(leagueName) then goto nextProLeague
        teams = leagueMaps[leagueName]
        found1 = false
        found2 = false

        for each teamKey in teams
            if LCase(team1).Instr(LCase(teamKey)) >= 0 or LCase(teamKey).Instr(LCase(team1)) >= 0 then found1 = true
            if LCase(team2).Instr(LCase(teamKey)) >= 0 or LCase(teamKey).Instr(LCase(team2)) >= 0 then found2 = true
            if found1 and found2 then return leagueName
        end for

        nextProLeague:
    end for

    ' Only check NCAA if no pro league match
    for each leagueName in collegeLeagues
        if not leagueMaps.doesExist(leagueName) then goto nextCollegeLeague
        teams = leagueMaps[leagueName]
        found1 = false
        found2 = false

        for each teamKey in teams
            if LCase(team1).Instr(LCase(teamKey)) >= 0 or LCase(teamKey).Instr(LCase(team1)) >= 0 then found1 = true
            if LCase(team2).Instr(LCase(teamKey)) >= 0 or LCase(teamKey).Instr(LCase(team2)) >= 0 then found2 = true
            if found1 and found2 then return leagueName
        end for

        nextCollegeLeague:
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
    ' Try ESPN CDN first for all leagues
    espnUrl = GetESPNLogoUrlFast(teamCode, league)
    if espnUrl <> "" then return espnUrl

    ' Fallback to GitHub logos
    if logoBaseUrl <> "" and teamCode <> invalid and teamCode <> ""
        urlParts = [logoBaseUrl, league, "/", teamCode, ".png"]
        return urlParts.Join("")
    end if

    return ""
end function

function GetESPNLogoUrlFast(teamName as String, league as String) as String
    logoUrls = GetLogoUrls()
    espnCdnBase = logoUrls.ESPNCDN_LOGOS_BASE

    ' NCAA: Use existing numeric ID logic
    if league = "NCAA"
        teamCode = GetTeamCodeByLeague(teamName, league)
        if teamCode <> invalid and teamCode <> ""
            teamId = GetNCAATeamId(teamCode)
            if teamId <> "" then
                return espnCdnBase + "ncaa/500/" + teamId + ".png"
            end if
        end if
        return ""
    end if

    ' Pro leagues: ESPN abbr + league path
    espnAbbr = GetESPNAbbrByLeague(teamName, league)
    if espnAbbr <> invalid and espnAbbr <> ""
        leaguePaths = {
            NFL: "nfl",
            NBA: "nba",
            MLB: "mlb",
            NHL: "nhl"
        }
        if leaguePaths.DoesExist(league)
            return espnCdnBase + leaguePaths[league] + "/500/" + espnAbbr + ".png"
        end if
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