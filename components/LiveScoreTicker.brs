sub init()
    m.tickerBackground = m.top.findNode("tickerBackground")
    m.scrollContainer = m.top.findNode("scrollContainer")
    m.contentGroup = m.top.findNode("contentGroup")

    m.uiColors = GetUIColors()

    ' Animation state
    m.scrollX = 1540
    m.scrollSpeed = 1.5
    m.contentWidth = 0
    m.isFirstLoad = true

    ' Animation timer (60 FPS)
    m.animationTimer = createObject("roSGNode", "Timer")
    m.animationTimer.repeat = true
    m.animationTimer.duration = 0.016
    m.animationTimer.observeField("fire", "onAnimationTick")

    ' API refresh timer (update scores every 30 seconds)
    m.refreshTimer = createObject("roSGNode", "Timer")
    m.refreshTimer.repeat = true
    m.refreshTimer.duration = 30
    m.refreshTimer.observeField("fire", "fetchLiveScores")

    ' Current scores data
    m.scoresData = []
    m.scoreItems = []
    m.currentTask = invalid

    ' ESPN API URLs - no parameters returns today's games only
    m.apiUrls = {
        NBA: "http://site.api.espn.com/apis/site/v2/sports/basketball/nba/scoreboard"
        NFL: "http://site.api.espn.com/apis/site/v2/sports/football/nfl/scoreboard"
        MLB: "http://site.api.espn.com/apis/site/v2/sports/baseball/mlb/scoreboard"
    }

    m.top.observeField("visible", "onVisibleChanged")
end sub

sub onVisibleChanged()
    if m.top.visible then
        fetchLiveScores()
        m.animationTimer.control = "start"
        m.refreshTimer.control = "start"
    else
        m.animationTimer.control = "stop"
        m.refreshTimer.control = "stop"
        if m.currentTask <> invalid then
            m.currentTask.control = "stop"
            m.currentTask = invalid
        end if
    end if
end sub

sub fetchLiveScores()
    ' Cancel any existing task
    if m.currentTask <> invalid then
        m.currentTask.control = "stop"
        m.currentTask = invalid
    end if

    ' Create new fetch task
    m.currentTask = createObject("roSGNode", "LiveScoreTask")
    m.currentTask.apiUrls = m.apiUrls
    m.currentTask.observeField("scoresData", "onScoresReceived")
    m.currentTask.control = "RUN"
end sub

sub onScoresReceived()
    if m.currentTask = invalid then return

    scoresData = m.currentTask.scoresData
    if scoresData = invalid or scoresData.count() = 0 then
        ' No games at all - hide the entire ticker
        m.top.visible = false
        return
    end if

    m.scoresData = scoresData
    createScoreItems()
end sub

sub clearScrollContainer()
    ' Remove all existing children from contentGroup
    count = m.contentGroup.getChildCount()
    if count > 0
        m.contentGroup.removeChildrenIndex(count, 0)
    end if
    m.scoreItems = []
end sub

sub createScoreItems()
    ' Clear existing items
    clearScrollContainer()

    if m.scoresData.count() = 0 then
        ' No games - hide ticker
        m.top.visible = false
        return
    end if

    ' Show ticker since we have games
    m.top.visible = true

    totalWidth = 0
    spacing = 60

    for each score in m.scoresData
        ' Check if game has started (not scheduled)
        isScheduled = (score.status.Instr("AM") >= 0 or score.status.Instr("PM") >= 0 or score.status = "Scheduled" or score.status.Instr("SUN") >= 0 or score.status.Instr("MON") >= 0 or score.status.Instr("TUE") >= 0 or score.status.Instr("WED") >= 0 or score.status.Instr("THU") >= 0 or score.status.Instr("FRI") >= 0 or score.status.Instr("SAT") >= 0)

        ' Determine if game is finished and who won
        isFinal = (score.status = "Final" or score.status.Instr("Final") >= 0)
        awayWon = false
        homeWon = false
        if isFinal
            if score.awayScore > score.homeScore
                awayWon = true
            else if score.homeScore > score.awayScore
                homeWon = true
            end if
        end if

        ' Create game container
        gameGroup = createObject("roSGNode", "Group")
        gameGroup.translation = [totalWidth, 0]

        ' Sport league badge (NBA/NFL/MLB) - with text adjusted down
        leagueBadge = createObject("roSGNode", "Rectangle")
        leagueBadge.translation = [0, 7]  ' Keep at 7
        leagueBadge.width = 80
        leagueBadge.height = 34
        leagueBadge.color = GetLeagueColor(score.league)
        gameGroup.appendChild(leagueBadge)

        leagueLabel = createObject("roSGNode", "Label")
        leagueLabel.translation = [0, 8]
        leagueLabel.width = 80
        leagueLabel.height = 34
        leagueLabel.text = score.league
        leagueLabel.font = "font:SmallBoldSystemFont"
        leagueLabel.color = m.uiColors.LIGHT_GRAY
        leagueLabel.font.size = 26
        leagueLabel.horizAlign = "center"
        leagueLabel.vertAlign = "center"
        gameGroup.appendChild(leagueLabel)

        ' Away team - adjusted position for wider badge
        awayLabel = createObject("roSGNode", "Label")
        awayLabel.translation = [90, 13]
        awayLabel.width = 85
        awayLabel.height = 30
        awayLabel.text = score.awayTeam
        awayLabel.font = "font:SmallBoldSystemFont"
        awayLabel.color = m.uiColors.LIGHT_GRAY
        awayLabel.horizAlign = "right"
        awayLabel.vertAlign = "center"
        gameGroup.appendChild(awayLabel)

        ' Calculate dynamic positioning based on score digits
        awayScoreDigits = 0
        homeScoreDigits = 0
        homeTeamPos = 195
        homeScorePos = 295
        statusPos = 370
        separatorPos = 630
        gameWidth = 640

        if not isScheduled then
            ' Count digits in scores for dynamic spacing
            awayScoreDigits = len(stri(score.awayScore).trim())
            homeScoreDigits = len(stri(score.homeScore).trim())

            ' Away score - HIGHLIGHT WINNER'S SCORE IN YELLOW
            awayScore = createObject("roSGNode", "Label")
            awayScore.translation = [191, 13]
            awayScore.width = 75
            awayScore.height = 30
            awayScore.text = stri(score.awayScore).trim()
            awayScore.font = "font:MediumBoldSystemFont"
            ' Highlight winner's score in yellow
            if awayWon
                awayScore.color = m.uiColors.YELLOW
            else
                awayScore.color = m.uiColors.WHITE
            end if
            awayScore.horizAlign = "left"
            awayScore.vertAlign = "center"
            gameGroup.appendChild(awayScore)

            ' Adjust home team position based on away score digits
            if awayScoreDigits = 2 then
                homeTeamPos = 268  ' 8px closer for 2-digit scores
            else
                homeTeamPos = 276  ' Normal (3 digits)
            end if

            ' Adjust home score position based on home team position
            homeScorePos = homeTeamPos + 101

            ' Adjust status position based on home score digits
            if homeScoreDigits = 2 then
                statusPos = homeScorePos + 75 + 12  ' 8px closer to status
            else
                statusPos = homeScorePos + 75 + 20  ' Normal gap
            end if

            separatorPos = 682
            gameWidth = 692
        else
            ' Scheduled game - closer spacing
            homeTeamPos = 195
            statusPos = 355
            separatorPos = 615
            gameWidth = 625
        end if

        ' Home team - dynamic position
        homeLabel = createObject("roSGNode", "Label")
        homeLabel.translation = [homeTeamPos, 13]
        homeLabel.width = 85
        homeLabel.height = 30
        homeLabel.text = score.homeTeam
        homeLabel.font = "font:SmallBoldSystemFont"
        homeLabel.color = m.uiColors.LIGHT_GRAY
        homeLabel.horizAlign = "right"
        homeLabel.vertAlign = "center"
        gameGroup.appendChild(homeLabel)

        if not isScheduled then
            ' Home score - dynamic position - HIGHLIGHT WINNER'S SCORE IN YELLOW
            homeScore = createObject("roSGNode", "Label")
            homeScore.translation = [homeScorePos, 13]
            homeScore.width = 75
            homeScore.height = 30
            homeScore.text = stri(score.homeScore).trim()
            homeScore.font = "font:MediumBoldSystemFont"
            ' Highlight winner's score in yellow
            if homeWon
                homeScore.color = m.uiColors.YELLOW
            else
                homeScore.color = m.uiColors.WHITE
            end if
            homeScore.horizAlign = "left"
            homeScore.vertAlign = "center"
            gameGroup.appendChild(homeScore)
        end if

        ' Game status - dynamic position
        statusLabel = createObject("roSGNode", "Label")
        statusLabel.translation = [statusPos, 13]
        if isScheduled then
            statusLabel.width = 250
        else
            statusLabel.width = 200
        end if
        statusLabel.height = 30
        statusLabel.text = score.status
        statusLabel.font = "font:SmallBoldSystemFont"
        statusLabel.font.size = 28
        statusLabel.color = GetStatusColor(score.status)
        statusLabel.horizAlign = "left"
        statusLabel.vertAlign = "center"
        gameGroup.appendChild(statusLabel)

        ' Separator line - dynamic position
        separatorLine = createObject("roSGNode", "Rectangle")
        separatorLine.translation = [separatorPos, 8]
        separatorLine.width = 2
        separatorLine.height = 40
        separatorLine.color = m.uiColors.DARK_GRAY
        gameGroup.appendChild(separatorLine)

        m.contentGroup.appendChild(gameGroup)
        m.scoreItems.push(gameGroup)

        totalWidth = totalWidth + gameWidth + spacing
    end for

    ' Store total width for scrolling
    m.contentWidth = totalWidth

    ' Only reset scroll position on first load
    if m.isFirstLoad then
        m.scrollX = 1540
        m.isFirstLoad = false
    end if
end sub

function GetLeagueColor(league as String) as String
    return m.uiColors.BLACK
end function

function GetStatusColor(status as String) as String
    ' Live games in red
    if status.Instr("Q") >= 0 or status.Instr("Half") >= 0 or status.Instr("Inning") >= 0 or status = "Live" then
        return "0xFF0000FF"  ' Red for live
    end if

    ' Final games in gray
    if status = "Final" or status.Instr("Final") >= 0 then
        return m.uiColors.GRAY
    end if

    ' Scheduled games in light gray
    return m.uiColors.LIGHT_GRAY
end function

sub onAnimationTick()
    ' Animate scrolling
    m.scrollX = m.scrollX - m.scrollSpeed

    if m.scrollX <= -m.contentWidth then
        m.scrollX = 1540  ' Reset to full right edge
    end if

    ' Update only the contentGroup position, not scrollContainer
    m.contentGroup.translation = [m.scrollX, 0]
end sub