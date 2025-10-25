sub init()
    m.top.functionName = "loadPlaylist"
end sub

sub loadPlaylist()
    url = m.top.url
    
    if url = invalid or url = ""
        m.top.error = "Invalid URL provided"
        return
    end if
    
    ' Create URL transfer object (now on the correct thread)
    request = CreateObject("roUrlTransfer")
    request.SetUrl(url)
    request.EnablePeerVerification(false)
    request.EnableHostVerification(false)
    request.RetainBodyOnError(true)

    port = CreateObject("roMessagePort")
    request.SetPort(port)

    if request.AsyncGetToString()
        while true
            msg = wait(5000, port)
            if msg <> invalid
                if type(msg) = "roUrlEvent"
                    if msg.GetResponseCode() = 200
                        response = msg.GetString()
                        print "LoadPlaylistTask: Received response length: " + len(response).ToStr()
                        print "LoadPlaylistTask: First 500 chars: " + left(response, 500)
                        m.top.response = response
                    else
                        print "LoadPlaylistTask: Error response code: " + msg.GetResponseCode().ToStr()
                        m.top.error = msg.GetFailureReason()
                    end if
                    exit while
                end if
            else
                m.top.error = "Request timed out"
                exit while
            end if
        end while
    else
        m.top.error = "Failed to start request"
    end if
end sub