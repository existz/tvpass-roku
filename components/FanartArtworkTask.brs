sub init()
    m.top.functionName = "runTask"
end sub

function runTask() as Void
    showName = m.top.showName
    isMovie = m.top.isMovie

    if showName = invalid or showName = "" then
        m.top.error = "Invalid show name"
        return
    end if

    ' Try with original name first (more specific)
    originalName = showName
    cleanName = CleanShowName(showName)

    ' PRIORITY 1: Try OMDB (IMDB data) with original name first
    print "FanartArtworkTask: Trying OMDB (IMDB) for original: " + originalName
    artworkUrl = GetOMDBArtwork(originalName, isMovie)
    if artworkUrl <> invalid and artworkUrl <> "" then
        print "FanartArtworkTask: Found OMDB artwork with original name: " + artworkUrl
        m.top.artworkUrl = artworkUrl
        return
    end if

    ' Try OMDB with cleaned name if original fails
    if cleanName <> originalName
        print "FanartArtworkTask: Trying OMDB (IMDB) for cleaned: " + cleanName
        artworkUrl = GetOMDBArtwork(cleanName, isMovie)
        if artworkUrl <> invalid and artworkUrl <> "" then
            print "FanartArtworkTask: Found OMDB artwork with cleaned name: " + artworkUrl
            m.top.artworkUrl = artworkUrl
            return
        end if
    end if

    ' PRIORITY 2: Try TMDB with original name first
    print "FanartArtworkTask: No OMDB result, trying TMDB with original name..."
    artworkUrl = GetTMDBArtwork(originalName, isMovie)
    if artworkUrl <> invalid and artworkUrl <> "" then
        print "FanartArtworkTask: Found TMDB artwork with original name: " + artworkUrl
        m.top.artworkUrl = artworkUrl
        return
    end if

    ' Try TMDB with cleaned name
    if cleanName <> originalName
        print "FanartArtworkTask: Trying TMDB with cleaned name..."
        artworkUrl = GetTMDBArtwork(cleanName, isMovie)
        if artworkUrl <> invalid and artworkUrl <> "" then
            print "FanartArtworkTask: Found TMDB artwork with cleaned name: " + artworkUrl
            m.top.artworkUrl = artworkUrl
            return
        end if
    end if

    ' PRIORITY 3: Try fanart.tv via TVmaze ID with cleaned name
    print "FanartArtworkTask: No TMDB result, trying fanart.tv..."
    tvdbId = SearchTVmaze(cleanName)
    if tvdbId <> invalid and tvdbId <> "" then
        print "FanartArtworkTask: Found TVDB ID: " + tvdbId

        ' Try TV artwork first
        artworkUrl = GetFanartArtwork(tvdbId, "23fc46a3d3003a3bc2ecdc34fbf079d0", false)
        if artworkUrl <> invalid and artworkUrl <> "" then
            print "FanartArtworkTask: Found fanart.tv TV artwork: " + artworkUrl
            m.top.artworkUrl = artworkUrl
            return
        end if

        ' Try as movie if TV fails
        if isMovie then
            artworkUrl = GetFanartArtwork(tvdbId, "23fc46a3d3003a3bc2ecdc34fbf079d0", true)
            if artworkUrl <> invalid and artworkUrl <> "" then
                print "FanartArtworkTask: Found fanart.tv movie artwork: " + artworkUrl
                m.top.artworkUrl = artworkUrl
                return
            end if
        end if
    end if

    ' PRIORITY 4: Fallback to TVmaze poster (lowest priority)
    print "FanartArtworkTask: No fanart.tv result, trying TVmaze..."
    artworkUrl = GetTVmazePoster(cleanName)
    if artworkUrl <> invalid and artworkUrl <> "" then
        print "FanartArtworkTask: Found TVmaze poster: " + artworkUrl
        m.top.artworkUrl = artworkUrl
        return
    end if

    print "FanartArtworkTask: No artwork found for: " + showName
    m.top.error = "No artwork found"
end function

' NEW FUNCTION: Get artwork from OMDB (uses IMDB data)
function GetOMDBArtwork(title as String, isMovie as Boolean) as Dynamic
    ' OMDB API (uses IMDB data) - FREE but requires API key
    ' Get free key at: http://www.omdbapi.com/apikey.aspx
    omdbApiKey = "77eb6b72"

    ' Extract year from title if present (e.g., "Show Name (2020)")
    year = ExtractYear(title)
    titleWithoutYear = RemoveYearFromTitle(title)

    ' URL encode the title
    encodedTitle = titleWithoutYear.Replace(" ", "+")

    ' Build search URL - specify type (movie or series)
    mediaType = "series"
    if isMovie then mediaType = "movie"

    searchUrl = "http://www.omdbapi.com/?apikey=" + omdbApiKey + "&t=" + encodedTitle + "&type=" + mediaType

    ' Add year parameter if we found one (helps narrow results)
    if year <> ""
        searchUrl = searchUrl + "&y=" + year
    end if

    print "GetOMDBArtwork: Searching with URL: " + searchUrl

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
                    ' Check if search was successful
                    if json.DoesExist("Response") and json.Response = "True"
                        if json.DoesExist("Poster") and json.Poster <> invalid and json.Poster <> "N/A"
                            print "GetOMDBArtwork: Found poster: " + json.Poster
                            ' Log what we matched
                            if json.DoesExist("Title") and json.DoesExist("Year")
                                print "GetOMDBArtwork: Matched - Title: " + json.Title + ", Year: " + json.Year
                            end if
                            return json.Poster
                        end if
                    else if json.DoesExist("Error")
                        print "GetOMDBArtwork: API Error: " + json.Error
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
                    ' This is a year - remove it
                    return title.Left(parenPos).Trim()
                end if
            end if
        end if
    end if

    return title
end function

' UPDATED FUNCTION: Get artwork from TMDB (now handles both movies and TV)
function GetTMDBArtwork(title as String, isMovie as Boolean) as Dynamic
    ' TMDB API - Get free key from themoviedb.org
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

    print "GetTMDBArtwork: Searching with URL: " + searchUrl

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
                    firstResult = json.results[0]
                    if firstResult.DoesExist("poster_path") and firstResult.poster_path <> invalid
                        ' TMDB image base URL - use w500 for good quality
                        posterUrl = "https://image.tmdb.org/t/p/w500" + firstResult.poster_path
                        print "GetTMDBArtwork: Found poster: " + posterUrl
                        ' Log what we matched
                        if firstResult.DoesExist("name")
                            print "GetTMDBArtwork: Matched TV show: " + firstResult.name
                        else if firstResult.DoesExist("title")
                            print "GetTMDBArtwork: Matched movie: " + firstResult.title
                        end if
                        return posterUrl
                    end if
                end if
            end if
        else
            http.asyncCancel()
        end if
    end if

    return invalid
end function

function SearchTVmaze(showName as String) as Dynamic
    ' URL encode the show name
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

                        ' Get TVDB ID from externals
                        if show.DoesExist("externals") and show.externals <> invalid
                            if show.externals.DoesExist("thetvdb") and show.externals.thetvdb <> invalid
                                ' FIX: Trim whitespace and convert to string
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
    ' Ensure no whitespace in ID (safety check)
    tvdbId = tvdbId.Trim()

    ' Build fanart.tv URL
    mediaType = "tv"
    if isMovie then mediaType = "movies"

    fanartUrl = "https://webservice.fanart.tv/v3/" + mediaType + "/" + tvdbId + "?api_key=" + apiKey
    print "FanartArtworkTask: Fetching from: " + fanartUrl

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
            print "FanartArtworkTask: Response code: " + str(responseCode)

            if responseCode = 200
                response = msg.getString()
                print "FanartArtworkTask: Response length: " + str(len(response))

                json = ParseJson(response)

                if json <> invalid
                    print "FanartArtworkTask: JSON parsed successfully"
                    ' Print available artwork types
                    for each key in json
                        if type(json[key]) = "roArray" and json[key].Count() > 0
                            print "FanartArtworkTask: Found " + key + " (" + str(json[key].Count()) + " items)"
                        end if
                    end for

                    ' Try to get artwork
                    artworkUrl = ExtractArtwork(json, isMovie)
                    if artworkUrl <> invalid and artworkUrl <> ""
                        return artworkUrl
                    end if
                else
                    print "FanartArtworkTask: Failed to parse JSON"
                end if
            else
                print "FanartArtworkTask: HTTP error " + str(responseCode)
            end if
        else
            http.asyncCancel()
            print "FanartArtworkTask: Request timeout"
        end if
    end if

    return invalid
end function

function ExtractArtwork(json as Object, isMovie as Boolean) as Dynamic
    ' Try ALL available artwork types in priority order
    ' For TV shows: try tvposter, tvthumb, clearlogo, hdtvlogo
    ' For movies: try movieposter, moviethumb, hdmovielogo, movielogo

    if isMovie
        ' Movie artwork priority
        artworkTypes = ["movieposter", "moviethumb", "hdmovielogo", "movielogo"]
    else
        ' TV show artwork priority - logos and clear art work best
        artworkTypes = ["tvposter", "tvthumb", "hdclearlogo", "clearlogo", "hdtvlogo"]
    end if

    for each artworkType in artworkTypes
        if json.DoesExist(artworkType) and json[artworkType] <> invalid
            if json[artworkType].Count() > 0
                url = json[artworkType][0].url
                if url <> invalid and url <> ""
                    print "FanartArtworkTask: Using " + artworkType + ": " + url
                    return url
                end if
            end if
        end if
    end for

    print "FanartArtworkTask: No suitable artwork found"
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
    ' Remove sports prefixes
    cleaned = name
    cleaned = cleaned.Replace("NBA Basketball: ", "")
    cleaned = cleaned.Replace("NFL Football: ", "")
    cleaned = cleaned.Replace("College Basketball: ", "")
    cleaned = cleaned.Replace("College Football: ", "")
    cleaned = cleaned.Replace("MLB Baseball: ", "")
    cleaned = cleaned.Replace("NHL Hockey: ", "")

    ' Remove season/episode patterns
    cleaned = RemoveSeasonEpisode(cleaned)

    ' Remove brackets [like episode codes] but keep parentheses (including years)
    bracketPos = cleaned.Instr("[")
    if bracketPos > 0
        cleaned = cleaned.Left(bracketPos).Trim()
    end if

    ' Keep EVERYTHING in parentheses - don't remove any parenthetical content
    ' This preserves (US), (UK), years (2024), and other disambiguating info

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