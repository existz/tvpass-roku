sub init()
    m.top.functionName = "runTask"
end sub

function runTask() as Void
    url = m.top.url
    if url = invalid or url = "" then
        m.top.error = "Invalid URL"
        return
    end if

    print "LoadScheduleTask: Fetching " + url

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
        ' Wait for response
        msg = wait(10000, port) ' 10 second timeout
        if type(msg) = "roUrlEvent"
            responseCode = msg.getResponseCode()
            print "LoadScheduleTask: Response code " + str(responseCode)
            if responseCode = 200
                response = msg.getString()
                print "LoadScheduleTask: Received " + str(len(response)) + " bytes"
                m.top.response = response
            else
                m.top.error = "HTTP " + str(responseCode)
            end if
        else if msg = invalid
            http.asyncCancel()
            m.top.error = "Request timeout"
        else
            http.asyncCancel()
            m.top.error = "Request cancelled"
        end if
    else
        m.top.error = "Failed to start request"
    end if
end function
