''' EPG Data Management Functions '''

function CreateEPGData() as Object
    epgData = {
        channels: []
        schedules: {}
        programsByChannel: {}
        lastUpdate: 0
        updateInterval: 300
        isLoading: false
        pendingTasks: 0
        playlistData: invalid
        epgData: invalid
        logoFallbackData: invalid
        playlistTask: invalid
        epgTask: invalid
        logoTask: invalid
    }
    return epgData
end function

function EPGNeedsUpdate(epg as Object) as Boolean
    if epg.lastUpdate = 0 then return true
    currentTime = CreateObject("roDateTime").AsSeconds()
    elapsed = currentTime - epg.lastUpdate
    return (elapsed >= epg.updateInterval)
end function

function EPGParsePlaylist(content as String) as Object
    channels = []
    content = content.Replace(chr(13), "").Replace(chr(10)+chr(10), chr(10))
    lines = content.Split(chr(10))
    current = invalid

    for each line in lines
        line = line.Trim()
        if line = "" then continue for

        if line.StartsWith("#EXTINF:")
            if current <> invalid and current.url <> invalid
                channels.push(current)
            end if
            current = {}

            tvgIdPos = line.Instr("tvg-id=")
            if tvgIdPos > 0
                tvgIdStart = tvgIdPos + 8
                tvgIdEnd = line.Instr(tvgIdStart, chr(34))
                if tvgIdEnd > tvgIdStart
                    current.tvgId = line.Mid(tvgIdStart, tvgIdEnd - tvgIdStart)
                end if
            end if

            tvgNamePos = line.Instr("tvg-name=")
            if tvgNamePos > 0
                tvgNameStart = tvgNamePos + 10
                tvgNameEnd = line.Instr(tvgNameStart, chr(34))
                if tvgNameEnd > tvgNameStart
                    current.title = line.Mid(tvgNameStart, tvgNameEnd - tvgNameStart).Trim()
                end if
            end if

            if current.title = invalid or current.title = ""
                parts = line.Split(",")
                if parts.count() > 1
                    current.title = parts[parts.count() - 1].Trim()
                end if
            end if

            logoPos = line.Instr("tvg-logo=")
            if logoPos > 0
                logoStart = logoPos + 10
                logoEnd = line.Instr(logoStart, chr(34))
                if logoEnd > logoStart
                    current.logo = line.Mid(logoStart, logoEnd - logoStart)
                end if
            end if

        else if not line.StartsWith("#") and current <> invalid
            if line.EndsWith("/sd")
                current.url = Left(line, Len(line) - 2) + "hd"
            else
                current.url = line
            end if
        end if
    end for

    if current <> invalid and current.url <> invalid
        channels.push(current)
    end if

    return channels
end function

function EPGParseXMLOptimized(xmlString as String) as Object
    result = {
        schedules: {}
        programsByChannel: {}
    }

    if xmlString = invalid or xmlString = "" then return result

    xml = CreateObject("roXMLElement")
    if not xml.Parse(xmlString) then return result

    now = CreateObject("roDateTime")
    currentTime = now.AsSeconds()
    windowStart = currentTime - 7200
    windowEnd = currentTime + 7200

    programmes = xml.GetNamedElements("programme")
    if programmes.count() = 0 then return result

    for each programme in programmes
        ' Quick time check first before parsing
        startTime = programme@start
        stopTime = programme@stop

        if startTime = invalid or stopTime = invalid then continue for

        startSec = EPGParseXmltvTime(startTime)
        stopSec = EPGParseXmltvTime(stopTime)

        ' Skip if completely outside time window (include programs from 2 hours in the past)
        if startSec > windowEnd or stopSec < windowStart then continue for

        ' NOW parse remaining fields
        channel = programme@channel
        if channel = invalid then continue for

        normalizedChannel = EPGNormalizeChannelId(channel)

        titleNode = programme.GetNamedElements("title")
        if titleNode.Count() = 0 then continue for

        programTitle = titleNode[0].GetText()

        programDesc = ""
        descNode = programme.GetNamedElements("desc")
        if descNode.Count() > 0
            programDesc = descNode[0].GetText()
        end if

        programSubTitle = ""
        subTitleNode = programme.GetNamedElements("sub-title")
        if subTitleNode.Count() > 0
            programSubTitle = subTitleNode[0].GetText()
        end if

        if programTitle = "Movie" and programSubTitle <> ""
            programTitle = programSubTitle
        end if

        ' For current programs, store the appropriate display text
        if startSec <= currentTime and stopSec > currentTime
            ' Check if this is a sports program
            isSports = false
            for each keyword in ["College Basketball", "College Football", "College Baseball", "NFL Football", "NBA Basketball", "NBA G League Basketball", "MLB Baseball", "NHL Hockey"]
                if programTitle.Instr(keyword) >= 0
                    isSports = true
                    exit for
                end if
            end for

            ' For sports, use subtitle if available; otherwise use title
            if isSports and programSubTitle <> ""
                result.schedules[normalizedChannel] = programSubTitle
            else
                result.schedules[normalizedChannel] = programTitle
            end if
        end if

        if not result.programsByChannel.doesExist(normalizedChannel)
            result.programsByChannel[normalizedChannel] = []
        end if

        programInfo = {
            title: programTitle
            description: programDesc
            subTitle: programSubTitle
            startTime: startSec
            endTime: stopSec
        }
        result.programsByChannel[normalizedChannel].push(programInfo)
    end for

    return result
end function

sub EPGEnrichWithLogosFast(channels as Object, fallbackData as Object, logoUrls as Object, networkPatterns as Object)
    fallbackMap = {}
    localUrl = logoUrls.TV_LOGOS_LOCAL
    baseUrl  = logoUrls.TV_LOGOS_BASE

    ' Build fallback map from HD fallback playlist
    if fallbackData <> invalid
        for each ch in fallbackData
            if ch.tvgId <> invalid and ch.logo <> invalid and ch.logo <> ""
                fallbackMap[ch.tvgId] = ch.logo
            end if
        end for
    end if

    for each channel in channels
        title = channel.title
        lowerTitle = LCase(title)

        ' Force NBC Sports Regional logos
        if lowerTitle.StartsWith("nbc sports ") or lowerTitle.InStr("nbc sports") > 0
            regionPart = title.Mid(11).Trim()

            ' Exact matches
            regionMap = {
                "boston":        "nbc-sports-boston-us.png",
                "bay area":      "nbc-sports-bay-area-us.png",
                "california":    "nbc-sports-california-us.png",
                "chicago":       "nbc-sports-chicago-us.png",
                "philadelphia":  "nbc-sports-philadelphia-us.png",
                "washington":    "nbc-sports-washington-us.png",
                "northwest":     "nbc-sports-northwest-us.png",
                "new england":   "nbc-sports-boston-us.png"
            }

            matched = false
            for each key in regionMap
                if Instr(lowerTitle, key) > 0
                    channel.logo = localUrl + regionMap[key]
                    matched = true
                    exit for
                end if
            end for

            ' Auto-generate if not in map
            if not matched
                clean = regionPart.Replace(" ", "-").Replace("&", "-and-")
                clean = LCase(clean)
                clean = clean.RegexReplace("--+", "-")
                channel.logo = localUrl + "nbc-sports-" + clean + "-us.png"
            end if

            ' We forced it — skip all other logic
            continue for
        end if

        ' Use fallback playlist logo if available
        if channel.tvgId <> invalid and fallbackMap.doesExist(channel.tvgId)
            channel.logo = fallbackMap[channel.tvgId]
            continue for
        end if

        if channel.logo = invalid or channel.logo = ""
            channel.logo = EPGGenerateLogoUrlFast(title, logoUrls, networkPatterns)
        end if
    end for
end sub

function EPGGenerateLogoUrlFast(title as String, logoUrls as Object, networkPatterns as Object) as String
    if title = invalid or title = "" then return ""
    networkLogo = EPGGetNetworkLogoFast(title, logoUrls, networkPatterns)
    return networkLogo
end function

function EPGGetNetworkLogoFast(title as String, logoUrls as Object, networkPatterns as Object) as String
    baseUrl = logoUrls.TV_LOGOS_BASE
    networkName = title.Trim()
    parenPos = networkName.Instr("(")
    if parenPos > 0
        networkName = networkName.Left(parenPos - 1).Trim()
    end if

    for each key in networkPatterns
        if networkName.StartsWith(UCase(key))
            openParen = title.Instr("(")
            closeParen = title.Instr(")")
            if openParen > 0 and closeParen > openParen
                callLetters = LCase(title.Mid(openParen + 1, closeParen - openParen - 1))
                ' Use array join for URL construction
                urlParts = [logoUrls.TV_LOGOS_LOCAL, networkPatterns[key], callLetters, "-us.png"]
                return urlParts.Join("")
            end if
        end if
    end for

    ' Chain multiple replacements
    networkName = networkName.Replace(" New York", "").Replace(" Los Angeles", "").Replace(" Chicago", "").Replace(", LA", "").Replace(", NY", "").Replace(", CA", "").Trim()

    if networkName = "" then return ""

    normalized = networkName.Replace("&", "-and-").Replace(" ", "-").Replace("'", "").Replace(",", "")
    normalized = LCase(normalized)

    ' Clean up double dashes - more efficient with single pass
    while normalized.Instr("--") >= 0
        normalized = normalized.Replace("--", "-")
    end while

    ' Trim leading numbers/dashes - optimized
    while normalized.Len() > 0
        firstChar = normalized.Left(1)
        if firstChar = "-" or (firstChar >= "0" and firstChar <= "9")
            normalized = normalized.Mid(1)
        else
            exit while
        end if
    end while

    ' Trim trailing dashes - optimized
    while normalized.Len() > 0 and normalized.Right(1) = "-"
        normalized = normalized.Left(normalized.Len() - 1)
    end while

    if normalized = "" then return ""

    ' Use array join for final URL
    urlParts = [baseUrl, normalized, "-us.png"]
    return urlParts.Join("")
end function

function EPGParseXmltvTime(xmltvTime as String) as LongInteger
    if xmltvTime.Len() < 14 then return 0

    year = val(xmltvTime.Mid(0, 4))
    month = val(xmltvTime.Mid(4, 2))
    day = val(xmltvTime.Mid(6, 2))
    hour = val(xmltvTime.Mid(8, 2))
    minute = val(xmltvTime.Mid(10, 2))
    second = val(xmltvTime.Mid(12, 2))

    tzStr = "Z"
    if xmltvTime.Len() >= 19
        tzPart = xmltvTime.Mid(14)
        firstChar = tzPart.Left(1)
        if firstChar = "+" or firstChar = "-"
            if tzPart.Len() >= 5
                ' Pre-allocate array for join
                tzParts = [tzPart.Mid(0, 3), ":", tzPart.Mid(3, 2)]
                tzStr = tzParts.Join("")
            end if
        end if
    end if

    ' Use array join instead of string concatenation
    yearStr = stri(year).Trim()
    monthStr = right("0" + stri(month).Trim(), 2)
    dayStr = right("0" + stri(day).Trim(), 2)
    hourStr = right("0" + stri(hour).Trim(), 2)
    minuteStr = right("0" + stri(minute).Trim(), 2)
    secondStr = right("0" + stri(second).Trim(), 2)

    iso8601Parts = [
        yearStr, "-",
        monthStr, "-",
        dayStr, "T",
        hourStr, ":",
        minuteStr, ":",
        secondStr,
        tzStr
    ]
    iso8601 = iso8601Parts.Join("")

    dt = CreateObject("roDateTime")
    dt.FromISO8601String(iso8601)
    return dt.AsSeconds()
end function

function EPGGetCurrentProgram(epg as Object, tvgId as String) as String
    if tvgId = invalid then return ""

    normalizedId = EPGNormalizeChannelId(tvgId)

    if epg.schedules.doesExist(normalizedId)
        return epg.schedules[normalizedId]
    end if

    return ""
end function

function EPGGetProgramsForTimeSlots(epg as Object, tvgId as String) as Object
    ''' Returns programs organized by 30-minute time slots
    ''' Returns: { slot1: programTitle, slot2: programTitle, slot3: programTitle }
    '''
    if tvgId = invalid then return { slot1: "", slot2: "", slot3: "" }

    normalizedId = EPGNormalizeChannelId(tvgId)

    ' Get current time and calculate 30-minute slots
    now = CreateObject("roDateTime")
    currentTime = now.AsSeconds()

    ' Round down to nearest 30 minutes
    slot1Start& = int(currentTime / 1800) * 1800
    slot1End& = slot1Start& + 1800
    slot2Start& = slot1End&
    slot2End& = slot2Start& + 1800
    slot3Start& = slot2End&
    slot3End& = slot3Start& + 1800

    result = {
        slot1: ""
        slot2: ""
        slot3: ""
    }

    ' Get all programs for this channel
    if not epg.programsByChannel.doesExist(normalizedId) then return result

    programs = epg.programsByChannel[normalizedId]
    if programs = invalid or programs.count() = 0 then return result

    ' Find programs for each slot
    for each program in programs
        if program = invalid or program.title = invalid then continue for

        progStart = program.startTime
        progEnd = program.endTime

        if progStart = invalid or progEnd = invalid then continue for

        ' Determine display text (handle sports programs)
        displayText = program.title
        isSports = IsSportsProgram(program.title, GetSportsKeywords())
        if isSports and program.subTitle <> invalid and program.subTitle <> ""
            displayText = program.subTitle
        end if

        ' Check if program overlaps with slot 1 (current slot)
        if progStart < slot1End& and progEnd > slot1Start& and result.slot1 = ""
            result.slot1 = displayText
        end if

        ' Check if program overlaps with slot 2
        if progStart < slot2End& and progEnd > slot2Start& and result.slot2 = ""
            result.slot2 = displayText
        end if

        ' Check if program overlaps with slot 3
        if progStart < slot3End& and progEnd > slot3Start& and result.slot3 = ""
            result.slot3 = displayText
        end if

        ' Early exit if all slots filled
        if result.slot1 <> "" and result.slot2 <> "" and result.slot3 <> ""
            exit for
        end if
    end for

    return result
end function