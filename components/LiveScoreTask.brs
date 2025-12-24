sub init()
    m.top.functionName = "runTask"
end sub

function runTask() as Void
    apiUrls = m.top.apiUrls
    if apiUrls = invalid then
        return
    end if

    allScores = []

    ' Fetch NBA scores
    if apiUrls.doesExist("NBA")
        nbaScores = fetchLeagueScores(apiUrls.NBA, "NBA")
        if nbaScores <> invalid and nbaScores.count() > 0
            allScores.append(nbaScores)
        end if
    end if

    ' Fetch NFL scores
    if apiUrls.doesExist("NFL")
        nflScores = fetchLeagueScores(apiUrls.NFL, "NFL")
        if nflScores <> invalid and nflScores.count() > 0
            allScores.append(nflScores)
        end if
    end if

    ' Fetch MLB scores
    if apiUrls.doesExist("MLB")
        mlbScores = fetchLeagueScores(apiUrls.MLB, "MLB")
        if mlbScores <> invalid and mlbScores.count() > 0
            allScores.append(mlbScores)
        end if
    end if

    ' Filter out TBD games
    filteredScores = []
    for each score in allScores
        if score.status <> "TBD" and score.status.Instr("TBD") < 0
            filteredScores.push(score)
        end if
    end for

    m.top.scoresData = filteredScores
end function

function fetchLeagueScores(url as String, league as String) as Object
    scores = []

    http = createObject("roUrlTransfer")
    http.setUrl(url)
    http.setCertificatesFile("common:/certs/ca-bundle.crt")
    http.addHeader("User-Agent", "Roku/TVPass-Client")
    http.initClientCertificates()

    port = createObject("roMessagePort")
    http.setPort(port)

    if http.asyncGetToString()
        msg = wait(15000, port)
        if type(msg) = "roUrlEvent"
            responseCode = msg.getResponseCode()

            if responseCode = 200
                response = msg.getString()
                json = ParseJson(response)

                if json <> invalid and json.doesExist("events")
                    events = json.events

                    if events <> invalid
                        for each event in events
                            score = parseGameScore(event, league)
                            if score <> invalid
                                scores.push(score)
                            end if
                        end for
                    end if
                else
                    print league; " API response has no events"
                end if
            else
                print league; " API returned error code: "; responseCode
            end if
        else
            print league; " API request timed out"
            http.asyncCancel()
        end if
    else
        print league; " Failed to start async request"
    end if

    return scores
end function

function parseGameScore(event as Object, league as String) as Object
    if event = invalid then return invalid

    ' Get competitions (games)
    if not event.doesExist("competitions") or event.competitions = invalid
        return invalid
    end if

    competitions = event.competitions
    if competitions.count() = 0 then return invalid

    competition = competitions[0]

    ' Get competitors (teams)
    if not competition.doesExist("competitors") or competition.competitors = invalid
        return invalid
    end if

    competitors = competition.competitors
    if competitors.count() < 2 then return invalid

    ' Find home and away teams
    homeTeam = invalid
    awayTeam = invalid

    for each competitor in competitors
        if competitor.doesExist("homeAway")
            if competitor.homeAway = "home"
                homeTeam = competitor
            else if competitor.homeAway = "away"
                awayTeam = competitor
            end if
        end if
    end for

    if homeTeam = invalid or awayTeam = invalid then return invalid

    ' Get team names and scores
    homeTeamName = getTeamAbbreviation(homeTeam)
    awayTeamName = getTeamAbbreviation(awayTeam)
    homeScore = getTeamScore(homeTeam)
    awayScore = getTeamScore(awayTeam)

    ' Get game status
    status = getGameStatus(competition)

    score = {
        league: league
        homeTeam: homeTeamName
        awayTeam: awayTeamName
        homeScore: homeScore
        awayScore: awayScore
        status: status
    }

    return score
end function

function getTeamAbbreviation(team as Object) as String
    if team = invalid then return ""

    ' Try to get abbreviation first
    if team.doesExist("team") and team.team <> invalid
        if team.team.doesExist("abbreviation") and team.team.abbreviation <> invalid
            return team.team.abbreviation
        end if

        ' Fall back to display name if no abbreviation
        if team.team.doesExist("displayName") and team.team.displayName <> invalid
            return team.team.displayName
        end if
    end if

    return ""
end function

function getTeamScore(team as Object) as Integer
    if team = invalid then return 0

    if team.doesExist("score") and team.score <> invalid
        scoreStr = team.score
        return val(scoreStr)
    end if

    return 0
end function

function getGameStatus(competition as Object) as String
    if competition = invalid then return "Unknown"

    if competition.doesExist("status") and competition.status <> invalid
        status = competition.status

        ' Get status type
        if status.doesExist("type") and status.type <> invalid
            statusType = status.type
            if statusType.doesExist("name") and statusType.name <> invalid
                statusName = statusType.name

                ' Handle different status types
                if statusName = "STATUS_FINAL" then return "Final"

                if statusName = "STATUS_SCHEDULED" then
                    ' Get date/time from shortDetail
                    if statusType.doesExist("shortDetail") and statusType.shortDetail <> invalid
                        fullDetail = statusType.shortDetail

                        ' Check for TBD
                        if fullDetail = "TBD" or fullDetail.Instr("TBD") >= 0
                            return "TBD"
                        end if

                        ' Parse date and time - look for format "MM/DD H:MM AM/PM"
                        if fullDetail.Instr("/") >= 0
                            ' Split by spaces
                            parts = fullDetail.Split(" ")

                            if parts.count() >= 3
                                ' parts[0] = date (e.g., "12/27")
                                ' parts[1] = time (e.g., "8:00" or might be "-8:00")
                                ' parts[2] = AM/PM (e.g., "PM")

                                dateStr = parts[0]
                                timeWithColon = parts[1]
                                ampm = parts[2]

                                ' Remove any leading hyphens from time
                                if timeWithColon.Left(1) = "-"
                                    timeWithColon = timeWithColon.Mid(1)  ' Remove first character
                                end if

                                ' Parse date
                                dateParts = dateStr.Split("/")
                                if dateParts.count() = 2
                                    month = val(dateParts[0])
                                    day = val(dateParts[1])

                                    ' Get current year
                                    now = CreateObject("roDateTime")
                                    year = now.getYear()

                                    ' Create date object
                                    gameDate = CreateObject("roDateTime")
                                    gameDate.fromISO8601String(stri(year).trim() + "-" + padZero(month) + "-" + padZero(day) + "T00:00:00")

                                    ' Get day of week
                                    dayOfWeek = gameDate.getDayOfWeek()
                                    dayNames = ["SUN", "MON", "TUE", "WED", "THU", "FRI", "SAT"]
                                    dayStr = dayNames[dayOfWeek]

                                    ' Format time
                                    timeStr = ""
                                    if timeWithColon.Instr(":") >= 0
                                        timeParts = timeWithColon.Split(":")
                                        hourStr = timeParts[0]
                                        minuteStr = timeParts[1]

                                        if minuteStr = "00"
                                            timeStr = hourStr + ampm  ' e.g., "8PM"
                                        else
                                            timeStr = hourStr + ":" + minuteStr + ampm  ' e.g., "10:30PM"
                                        end if
                                    else
                                        timeStr = timeWithColon + ampm
                                    end if

                                    result = dayStr + " " + " " + timeStr
                                    return result
                                end if
                            end if
                        end if

                        return fullDetail
                    end if
                    return "Scheduled"
                end if

                ' For in-progress games
                if statusName = "STATUS_IN_PROGRESS"
                    if statusType.doesExist("shortDetail") and statusType.shortDetail <> invalid
                        statusDetail = statusType.shortDetail

                        ' Check for halftime
                        if statusDetail.Instr("Halftime") >= 0 or statusDetail.Instr("Half") >= 0 or statusDetail.Instr("HALFTIME") >= 0
                            return "HALFTIME"
                        end if

                        return statusDetail
                    end if
                    return "Live"
                end if
            end if
        end if
    end if

    return ""
end function

' Helper function to pad single digit with zero
function padZero(num as Integer) as String
    numStr = stri(num).trim()
    if numStr.len() = 1
        return "0" + numStr
    end if
    return numStr
end function