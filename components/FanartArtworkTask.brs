sub init()
    m.top.functionName = "runTask"
    m.lookupCache = {}
end sub

function runTask() as Void
    showName = m.top.showName
    channelName = m.top.channelName  ' NEW: Get channel name

    if showName = invalid or showName = "" then
        m.top.error = "Invalid show name"
        return
    end if

    ' NEW: Handle invalid channelName
    if channelName = invalid then channelName = ""

    originalName = showName
    cleanName = CleanShowName(showName)

    isLikelyMovie = false

    if HasValidEPGTimes()
        durationSeconds = calculateDurationFromEPG(m.top.startTime, m.top.stopTime)
        durationMinutes = durationSeconds / 60

        if durationMinutes >= 90
            isLikelyMovie = true
        end if
    else
        isLikelyMovie = DetectLikelyMovie(originalName)
    end if

    cacheKey = originalName + "|" + (isLikelyMovie = true).ToStr() + "|" + channelName
    if m.lookupCache.DoesExist(cacheKey)
        m.top.artworkUrl = m.lookupCache[cacheKey]
        return
    end if

    success = false

    if isLikelyMovie
        success = tryAsMovie(originalName, cleanName, channelName)
        if not success then success = tryAsTV(originalName, cleanName, channelName)
    else
        success = tryAsTV(originalName, cleanName, channelName)
        if not success then success = tryAsMovie(originalName, cleanName, channelName)
    end if

    if success
        m.lookupCache[cacheKey] = m.top.artworkUrl
        return
    end if

    m.lookupCache[cacheKey] = invalid
end function

' Helper: Try to find artwork as TV series
function tryAsTV(originalName as String, cleanName as String, channelName as String) as Boolean
    artworkUrl = GetOMDBArtwork(originalName, false, channelName)
    if artworkUrl <> invalid and artworkUrl <> "" then
        m.top.artworkUrl = artworkUrl
        return true
    end if

    if cleanName <> originalName
        artworkUrl = GetOMDBArtwork(cleanName, false, channelName)
        if artworkUrl <> invalid and artworkUrl <> "" then
            m.top.artworkUrl = artworkUrl
            return true
        end if
    end if

    artworkUrl = GetTMDBArtwork(originalName, false, channelName)
    if artworkUrl <> invalid and artworkUrl <> "" then
        m.top.artworkUrl = artworkUrl
        return true
    end if

    if cleanName <> originalName
        artworkUrl = GetTMDBArtwork(cleanName, false, channelName)
        if artworkUrl <> invalid and artworkUrl <> "" then
            m.top.artworkUrl = artworkUrl
            return true
        end if
    end if

    return false
end function

function tryAsMovie(originalName as String, cleanName as String, channelName as String) as Boolean
    artworkUrl = GetOMDBArtwork(originalName, true, channelName)
    if artworkUrl <> invalid and artworkUrl <> "" then
        m.top.artworkUrl = artworkUrl
        return true
    end if

    if cleanName <> originalName
        artworkUrl = GetOMDBArtwork(cleanName, true, channelName)
        if artworkUrl <> invalid and artworkUrl <> "" then
            m.top.artworkUrl = artworkUrl
            return true
        end if
    end if

    artworkUrl = GetTMDBArtwork(originalName, true, channelName)
    if artworkUrl <> invalid and artworkUrl <> "" then
        m.top.artworkUrl = artworkUrl
        return true
    end if

    if cleanName <> originalName
        artworkUrl = GetTMDBArtwork(cleanName, true, channelName)
        if artworkUrl <> invalid and artworkUrl <> "" then
            m.top.artworkUrl = artworkUrl
            return true
        end if
    end if

    return false
end function

function HasValidEPGTimes() as Boolean
    isValid = true

    if m.top.startTime = invalid or m.top.startTime = "" then
        isValid = false
    end if

    if m.top.stopTime = invalid or m.top.stopTime = "" then
        isValid = false
    end if

    return isValid
end function

' Detect if title is likely a movie based on patterns
function DetectLikelyMovie(title as String) as Boolean
    if title = invalid or title = "" then return false

    t = LCase(title)

    ' --- TV indicators ---
    regexSeasonEpisode = CreateObject("roRegex", "s[0-9]{1,2}e[0-9]{1,2}", "i")
    if regexSeasonEpisode.IsMatch(t) then return false

    regexEpisode = CreateObject("roRegex", "episode\s+[0-9]+", "i")
    if regexEpisode.IsMatch(t) then return false

    regexSeason = CreateObject("roRegex", "season\s+[0-9]+", "i")
    if regexSeason.IsMatch(t) then return false

    ' --- Movie indicators ---
    regexYear = CreateObject("roRegex", "\([0-9]{4}\)", "i")
    if regexYear.IsMatch(t) then return true

    regexMovieWords = CreateObject("roRegex", "(the movie|the film|: the movie)", "i")
    if regexMovieWords.IsMatch(t) then return true

    franchises = [
        "star wars","harry potter","lord of the rings","jurassic",
        "avengers","spider-man","batman","superman",
        "mission impossible","fast and furious","transformers",
        "matrix","terminator","alien","predator"
    ]

    for each f in franchises
        if InStr(t, f) >= 0 then return true
    end for

    return false
end function

' UPDATED: Get artwork from OMDB with exact title matching
function GetOMDBArtwork(title as String, isMovie as Boolean, channelName as String) as Dynamic
    omdbApiKey = "77eb6b72"

    ' Extract year from title if present
    year = ExtractYear(title)
    titleWithoutYear = RemoveYearFromTitle(title)

    ' URL encode the title
    encodedTitle = titleWithoutYear.Replace(" ", "+")

    ' Build search URL - specify type (movie or series)
    mediaType = "series"
    if isMovie then mediaType = "movie"

    searchUrl = "http://www.omdbapi.com/?apikey=" + omdbApiKey + "&t=" + encodedTitle + "&type=" + mediaType

    ' Add year parameter if we found one
    if year <> ""
        searchUrl = searchUrl + "&y=" + year
    end if

    http = createObject("roUrlTransfer")
    http.setUrl(searchUrl)
    http.setCertificatesFile("common:/certs/ca-bundle.crt")
    http.addHeader("User-Agent", "Roku/TVPass-Client")
    http.initClientCertificates()

    port = createObject("roMessagePort")
    http.setPort(port)

    if http.asyncGetToString()
        msg = wait(10000, port)
        if type(msg) = "roUrlEvent"
            responseCode = msg.getResponseCode()
            if responseCode = 200
                response = msg.getString()
                json = ParseJson(response)

                if json <> invalid
                    if json.DoesExist("Response") and json.Response = "True"
                        ' NEW: Exact title match validation
                        if json.DoesExist("Title")
                            resultTitle = json.Title
                            ' Compare titles case-insensitively
                            if LCase(resultTitle.Trim()) = LCase(titleWithoutYear.Trim())
                                if json.DoesExist("Poster") and json.Poster <> invalid and json.Poster <> "N/A"
                                    return json.Poster
                                end if
                            end if
                        end if
                    end if
                end if
            end if
        else
            http.asyncCancel()
        end if
    end if

    return invalid
end function

' Helper function to extract year from title
function ExtractYear(title as String) as String
    if title = invalid or title = "" then return ""

    ' Look for (YYYY) pattern
    parenPos = title.Instr("(")
    if parenPos > 0
        closeParenPos = title.Instr(")")
        if closeParenPos > parenPos
            content = title.Mid(parenPos + 1, closeParenPos - parenPos - 1).Trim()
            if content.Len() = 4 and IsNumeric(content)
                yearVal = val(content)
                if yearVal >= 1950 and yearVal <= 2030
                    return content
                end if
            end if
        end if
    end if

    return ""
end function

' Helper function to remove year from title
function RemoveYearFromTitle(title as String) as String
    if title = invalid or title = "" then return ""

    parenPos = title.Instr("(")
    if parenPos > 0
        closeParenPos = title.Instr(")")
        if closeParenPos > parenPos
            content = title.Mid(parenPos + 1, closeParenPos - parenPos - 1).Trim()
            if content.Len() = 4 and IsNumeric(content)
                yearVal = val(content)
                if yearVal >= 1950 and yearVal <= 2030
                    return title.Left(parenPos).Trim()
                end if
            end if
        end if
    end if

    return title
end function

' UPDATED: Get artwork from TMDB with exact title matching and optional network validation
function GetTMDBArtwork(title as String, isMovie as Boolean, channelName as String) as Dynamic
    tmdbApiKey = "66822e40a6a5a1ee3b39e0fcac1fc59f"

    ' Extract year if present
    year = ExtractYear(title)
    titleWithoutYear = RemoveYearFromTitle(title)

    encodedTitle = titleWithoutYear.Replace(" ", "%20")

    ' Use different endpoints for movies vs TV shows
    searchType = "tv"
    yearParam = "first_air_date_year"
    if isMovie
        searchType = "movie"
        yearParam = "year"
    end if

    searchUrl = "https://api.themoviedb.org/3/search/" + searchType + "?api_key=" + tmdbApiKey + "&query=" + encodedTitle

    ' Add year if available
    if year <> ""
        searchUrl = searchUrl + "&" + yearParam + "=" + year
    end if

    http = createObject("roUrlTransfer")
    http.setUrl(searchUrl)
    http.setCertificatesFile("common:/certs/ca-bundle.crt")
    http.addHeader("User-Agent", "Roku/TVPass-Client")
    http.initClientCertificates()

    port = createObject("roMessagePort")
    http.setPort(port)

    if http.asyncGetToString()
        msg = wait(10000, port)
        if type(msg) = "roUrlEvent"
            responseCode = msg.getResponseCode()
            if responseCode = 200
                response = msg.getString()
                json = ParseJson(response)

                if json <> invalid and json.DoesExist("results") and json.results.Count() > 0
                    ' NEW: Loop through results to find exact match
                    for each result in json.results
                        resultTitle = invalid

                        ' Get the title based on media type
                        if isMovie and result.DoesExist("title")
                            resultTitle = result.title
                        else if not isMovie and result.DoesExist("name")
                            resultTitle = result.name
                        end if

                        ' NEW: Exact title match check (case-insensitive)
                        if resultTitle <> invalid and LCase(resultTitle.Trim()) = LCase(titleWithoutYear.Trim())
                            ' For TV shows, optionally validate network
                            if not isMovie and channelName <> invalid and channelName <> "" and result.DoesExist("id")
                                ' Check network match for TV shows
                                if ValidateNetwork(result.id, channelName, tmdbApiKey)
                                    if result.DoesExist("poster_path") and result.poster_path <> invalid
                                        return "https://image.tmdb.org/t/p/w500" + result.poster_path
                                    end if
                                end if
                            else
                                ' For movies or when network not provided, accept exact title match
                                if result.DoesExist("poster_path") and result.poster_path <> invalid
                                    return "https://image.tmdb.org/t/p/w500" + result.poster_path
                                end if
                            end if
                        end if
                    end for
                end if
            end if
        else
            http.asyncCancel()
        end if
    end if

    return invalid
end function

' NEW: Validate that the show's network matches the channel name
function ValidateNetwork(showId as Integer, channelName as String, apiKey as String) as Boolean
    if channelName = invalid or channelName = "" then return true

    detailsUrl = "https://api.themoviedb.org/3/tv/" + showId.ToStr() + "?api_key=" + apiKey

    http = createObject("roUrlTransfer")
    http.setUrl(detailsUrl)
    http.setCertificatesFile("common:/certs/ca-bundle.crt")
    http.addHeader("User-Agent", "Roku/TVPass-Client")
    http.initClientCertificates()

    port = createObject("roMessagePort")
    http.setPort(port)

    if http.asyncGetToString()
        msg = wait(10000, port)
        if type(msg) = "roUrlEvent"
            responseCode = msg.getResponseCode()
            if responseCode = 200
                response = msg.getString()
                json = ParseJson(response)

                if json <> invalid and json.DoesExist("networks") and json.networks <> invalid
                    channelLower = LCase(channelName)

                    ' Check if any network name matches the channel
                    for each network in json.networks
                        if network.DoesExist("name") and network.name <> invalid
                            networkLower = LCase(network.name)

                            ' Flexible matching: check if channel name is in network name or vice versa
                            if networkLower.Instr(channelLower) >= 0 or channelLower.Instr(networkLower) >= 0
                                return true
                            end if
                        end if
                    end for

                    ' No match found - reject this result
                    return false
                end if
            end if
        else
            http.asyncCancel()
        end if
    end if

    ' If we can't validate, accept it (network data might not be available)
    return true
end function

function SearchTVmaze(showName as String) as Dynamic
    encodedName = showName.Replace(" ", "%20")
    searchUrl = "https://api.tvmaze.com/search/shows?q=" + encodedName

    http = createObject("roUrlTransfer")
    http.setUrl(searchUrl)
    http.setCertificatesFile("common:/certs/ca-bundle.crt")
    http.addHeader("User-Agent", "Roku/TVPass-Client")
    http.initClientCertificates()

    port = createObject("roMessagePort")
    http.setPort(port)

    if http.asyncGetToString()
        msg = wait(10000, port)
        if type(msg) = "roUrlEvent"
            responseCode = msg.getResponseCode()
            if responseCode = 200
                response = msg.getString()
                json = ParseJson(response)

                if json <> invalid and json.Count() > 0
                    firstResult = json[0]
                    if firstResult.DoesExist("show") and firstResult.show <> invalid
                        show = firstResult.show

                        if show.DoesExist("externals") and show.externals <> invalid
                            if show.externals.DoesExist("thetvdb") and show.externals.thetvdb <> invalid
                                return Str(show.externals.thetvdb).Trim()
                            end if
                        end if
                    end if
                end if
            end if
        else
            http.asyncCancel()
        end if
    end if

    return invalid
end function

function GetFanartArtwork(tvdbId as String, apiKey as String, isMovie as Boolean) as Dynamic
    tvdbId = tvdbId.Trim()

    mediaType = "tv"
    if isMovie then mediaType = "movies"

    fanartUrl = "https://webservice.fanart.tv/v3/" + mediaType + "/" + tvdbId + "?api_key=" + apiKey

    http = createObject("roUrlTransfer")
    http.setUrl(fanartUrl)
    http.setCertificatesFile("common:/certs/ca-bundle.crt")
    http.addHeader("User-Agent", "Roku/TVPass-Client")
    http.initClientCertificates()

    port = createObject("roMessagePort")
    http.setPort(port)

    if http.asyncGetToString()
        msg = wait(10000, port)
        if type(msg) = "roUrlEvent"
            responseCode = msg.getResponseCode()

            if responseCode = 200
                response = msg.getString()
                json = ParseJson(response)

                if json <> invalid
                    artworkUrl = ExtractArtwork(json, isMovie)
                    if artworkUrl <> invalid and artworkUrl <> ""
                        return artworkUrl
                    end if
                end if
            end if
        else
            http.asyncCancel()
        end if
    end if

    return invalid
end function

function ExtractArtwork(json as Object, isMovie as Boolean) as Dynamic
    if isMovie
        artworkTypes = ["movieposter", "moviethumb", "hdmovielogo", "movielogo"]
    else
        artworkTypes = ["tvposter", "tvthumb", "hdclearlogo", "clearlogo", "hdtvlogo"]
    end if

    for each artworkType in artworkTypes
        if json.DoesExist(artworkType) and json[artworkType] <> invalid
            if json[artworkType].Count() > 0
                url = json[artworkType][0].url
                if url <> invalid and url <> ""
                    return url
                end if
            end if
        end if
    end for
    return invalid
end function

function GetTVmazePoster(showName as String) as Dynamic
    encodedName = showName.Replace(" ", "%20")
    searchUrl = "https://api.tvmaze.com/search/shows?q=" + encodedName

    http = createObject("roUrlTransfer")
    http.setUrl(searchUrl)
    http.setCertificatesFile("common:/certs/ca-bundle.crt")
    http.addHeader("User-Agent", "Roku/TVPass-Client")
    http.initClientCertificates()

    port = createObject("roMessagePort")
    http.setPort(port)

    if http.asyncGetToString()
        msg = wait(10000, port)
        if type(msg) = "roUrlEvent"
            responseCode = msg.getResponseCode()
            if responseCode = 200
                response = msg.getString()
                json = ParseJson(response)

                if json <> invalid and json.Count() > 0
                    firstResult = json[0]
                    if firstResult.DoesExist("show") and firstResult.show <> invalid
                        show = firstResult.show
                        if show.DoesExist("image") and show.image <> invalid
                            if show.image.DoesExist("original") and show.image.original <> invalid
                                return show.image.original
                            end if
                        end if
                    end if
                end if
            end if
        else
            http.asyncCancel()
        end if
    end if

    return invalid
end function

function CleanShowName(name as String) as String
    cleaned = name
    cleaned = cleaned.Replace("NBA Basketball: ", "")
    cleaned = cleaned.Replace("NFL Football: ", "")
    cleaned = cleaned.Replace("College Basketball: ", "")
    cleaned = cleaned.Replace("College Football: ", "")
    cleaned = cleaned.Replace("MLB Baseball: ", "")
    cleaned = cleaned.Replace("NHL Hockey: ", "")

    cleaned = RemoveSeasonEpisode(cleaned)

    bracketPos = cleaned.Instr("[")
    if bracketPos > 0
        cleaned = cleaned.Left(bracketPos).Trim()
    end if

    return cleaned.Trim()
end function

function RemoveSeasonEpisode(text as String) as String
    result = text

    if result.Instr("S") >= 0 and result.Instr("E") >= 0
        sPos = result.Instr("S")
        ePos = result.Instr("E")
        if ePos > sPos
            beforeS = result.Left(sPos).Trim()
            afterE = result.Mid(ePos + 1).Trim()

            if afterE = "" or not IsLetter(afterE.Left(1))
                result = beforeS
            end if
        end if
    end if

    return result.Trim()
end function

function IsLetter(char as String) as Boolean
    if char = "" then return false
    charCode = asc(char)
    return (charCode >= 65 and charCode <= 90) or (charCode >= 97 and charCode <= 122)
end function

function IsNumeric(text as String) as Boolean
    if text = "" then return false
    for i = 0 to text.Len() - 1
        char = text.Mid(i, 1)
        if char < "0" or char > "9"
            return false
        end if
    end for
    return true
end function

function calculateDurationFromEPG(startTime as String, stopTime as String) as Integer
    startDateTime = CreateObject("roDateTime")
    startDateTime.FromISO8601String(formatEPGTime(startTime))

    stopDateTime = CreateObject("roDateTime")
    stopDateTime.FromISO8601String(formatEPGTime(stopTime))

    durationSeconds = stopDateTime.AsSeconds() - startDateTime.AsSeconds()

    return durationSeconds
end function

function formatEPGTime(epgTime as String) as String
    timeStr = epgTime.Split(" ")[0]

    year = timeStr.Mid(0, 4)
    month = timeStr.Mid(4, 2)
    day = timeStr.Mid(6, 2)
    hour = timeStr.Mid(8, 2)
    minute = timeStr.Mid(10, 2)
    second = timeStr.Mid(12, 2)

    iso8601 = year + "-" + month + "-" + day + "T" + hour + ":" + minute + ":" + second + "Z"

    return iso8601
end function