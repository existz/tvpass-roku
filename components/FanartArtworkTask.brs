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

    cleanName = CleanShowName(showName)

    ' PRIORITY 1: Try OMDB (IMDB data) - best quality posters
    print "FanartArtworkTask: Trying OMDB (IMDB) for: " + cleanName
    artworkUrl = GetOMDBArtwork(cleanName, isMovie)
    if artworkUrl <> invalid and artworkUrl <> "" then
        print "FanartArtworkTask: Found OMDB artwork: " + artworkUrl
        m.top.artworkUrl = artworkUrl
        return
    end if

    ' PRIORITY 2: Try TMDB - good quality and coverage
    print "FanartArtworkTask: No OMDB result, trying TMDB..."
    artworkUrl = GetTMDBArtwork(cleanName, isMovie)
    if artworkUrl <> invalid and artworkUrl <> "" then
        print "FanartArtworkTask: Found TMDB artwork: " + artworkUrl
        m.top.artworkUrl = artworkUrl
        return
    end if

    ' PRIORITY 3: Try fanart.tv via TVmaze ID - high quality but limited coverage
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

    print "FanartArtworkTask: No artwork found for: " + cleanName
    m.top.error = "No artwork found"
end function

' NEW FUNCTION: Get artwork from OMDB (uses IMDB data)
function GetOMDBArtwork(title as String, isMovie as Boolean) as Dynamic
    ' OMDB API (uses IMDB data) - FREE but requires API key
    ' Get free key at: http://www.omdbapi.com/apikey.aspx
    omdbApiKey = "77eb6b72"

    ' URL encode the title
    encodedTitle = title.Replace(" ", "+")

    ' Build search URL - specify type (movie or series)
    mediaType = "series"
    if isMovie then mediaType = "movie"

    searchUrl = "http://www.omdbapi.com/?apikey=" + omdbApiKey + "&t=" + encodedTitle + "&type=" + mediaType

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
                            return json.Poster
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

' UPDATED FUNCTION: Get artwork from TMDB (now handles both movies and TV)
function GetTMDBArtwork(title as String, isMovie as Boolean) as Dynamic
    ' TMDB API - Get free key from themoviedb.org
    tmdbApiKey = "66822e40a6a5a1ee3b39e0fcac1fc59f"  ' Replace with free key

    encodedTitle = title.Replace(" ", "%20")

    ' Use different endpoints for movies vs TV shows
    searchType = "tv"
    if isMovie then searchType = "movie"

    searchUrl = "https://api.themoviedb.org/3/search/" + searchType + "?api_key=" + tmdbApiKey + "&query=" + encodedTitle

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

    ' Keep years in parentheses (2024) but remove other parenthetical content
    ' Only remove parentheses if they don't contain a 4-digit year
    parenPos = cleaned.Instr("(")
    if parenPos > 0
        closeParenPos = cleaned.Instr(")")
        if closeParenPos > parenPos
            parenContent = cleaned.Mid(parenPos + 1, closeParenPos - parenPos - 1).Trim()

            ' Check if content is a 4-digit year
            if parenContent.Len() = 4 and IsNumeric(parenContent)
                yearVal = val(parenContent)
                if yearVal >= 1950 and yearVal <= 2030
                    ' This is a year - keep it
                else
                    ' Not a valid year - remove parentheses
                    cleaned = cleaned.Left(parenPos).Trim()
                end if
            else
                ' Not a year - remove parentheses
                cleaned = cleaned.Left(parenPos).Trim()
            end if
        end if
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