sub init()
    m.top.functionName = "runTask"
end sub

function runTask() as Void
    url = m.top.url
    if url = invalid or url = "" then
        m.top.error = "Invalid URL"
        return
    end if

    ' Create HTTP object
    http = createObject("roUrlTransfer")
    http.setUrl(url)
    http.setCertificatesFile("common:/certs/ca-bundle.crt")
    http.addHeader("User-Agent", "Roku/IPTV-Client")
    http.initClientCertificates()

    ' Perform request
    port = createObject("roMessagePort")
    http.setPort(port)

    if http.asyncGetToString()
        ' Wait for response
        msg = wait(10000, port) ' 10 second timeout
        if type(msg) = "roUrlEvent"
            responseCode = msg.getResponseCode()
            if responseCode = 200
                m.top.response = msg.getString()
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
