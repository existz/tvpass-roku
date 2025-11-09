sub init()
    m.top.functionName = "runTask"
end sub

function runTask() as Void
    url = m.top.url
    if url = invalid or url = "" then
        m.top.error = "Invalid URL"
        return
    end if

    print "LoadPlaylistTask: Fetching " + url

    ' Create HTTP object
    http = createObject("roUrlTransfer")
    http.setUrl(url)
    http.setCertificatesFile("common:/certs/ca-bundle.crt")
    http.addHeader("User-Agent", "Roku/IPTV-Client")
    http.addHeader("Cache-Control", "no-cache, no-store, must-revalidate")
    http.addHeader("Pragma", "no-cache")
    http.addHeader("Expires", "0")
    http.initClientCertificates()
    
    ' Disable any internal caching
    http.EnableFreshConnection(true)

    ' Perform request
    port = createObject("roMessagePort")
    http.setPort(port)

    if http.asyncGetToString()
        ' Wait for response (30 second timeout for large playlists)
        msg = wait(30000, port)
        if type(msg) = "roUrlEvent"
            responseCode = msg.getResponseCode()
            print "LoadPlaylistTask: Response code " + str(responseCode)
            if responseCode = 200
                response = msg.getString()
                print "LoadPlaylistTask: Received " + str(len(response)) + " bytes"
                lineCount = response.Split(chr(10)).count()
                print "LoadPlaylistTask: Response contains " + str(lineCount) + " lines"
                m.top.response = response
            else
                m.top.error = "HTTP " + str(responseCode)
            end if
        else if msg = invalid
            http.asyncCancel()
            m.top.error = "Request timeout (30s)"
        else
            http.asyncCancel()
            m.top.error = "Request cancelled"
        end if
    else
        m.top.error = "Failed to start request"
    end if
end function