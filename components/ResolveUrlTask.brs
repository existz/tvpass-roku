sub init()
    ' Default entry point for single-URL resolution
    m.top.functionName = "runTask"
end sub

' Main single-URL entry point
function runTask() as Void
    url = m.top.url
    if url = invalid or url = "" then
        m.top.error = "Invalid URL"
        return
    end if

    ' Resolve with browser-like headers
    finalUrl = resolveWithHeaders(url)

    if finalUrl <> invalid and finalUrl <> "" and finalUrl <> url
        print "ResolveUrlTask: Resolved to dedicated server: " + finalUrl
        m.top.resolvedUrl = finalUrl
    else
        m.top.resolvedUrl = url
    end if
end function

' Batch entry point: resolve many TVPass URLs in one background task
' Expects m.top.inputUrls as an assocarray: key (string) -> originalUrl
' Outputs m.top.resolvedUrls as assocarray: key (string) -> finalUrl
function runBatch() as Void
    urls = m.top.inputUrls
    if urls = invalid then return

    resolved = {}

    for each key in urls
        origUrl = urls[key]
        if origUrl <> invalid and origUrl <> "" then
            ' Reuse the same logic used for single-URL resolution
            finalUrl = resolveWithHeaders(origUrl)

            if finalUrl <> invalid and finalUrl <> "" then
                ' Store final URL keyed by the same string key
                resolved[key] = finalUrl
            end if
        end if
    end for

    m.top.resolvedUrls = resolved
end function

' Perform HTTP HEAD request with browser-like headers to resolve redirect target
function resolveWithHeaders(url as String) as String
    ' Create HTTP transfer object
    http = createObject("roUrlTransfer")
    http.setUrl(url)
    http.setCertificatesFile("common:/certs/ca-bundle.crt")
    http.initClientCertificates()

    ' Set browser-like headers to mimic web request
    http.addHeader("User-Agent", "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36")
    http.addHeader("Referer", "https://tvpass.org/")
    http.addHeader("Origin", "https://tvpass.org")
    http.addHeader("Accept", "application/vnd.apple.mpegurl, */*")
    http.addHeader("Accept-Language", "en-US,en;q=0.9")

    ' Enable fresh connection to avoid cached responses
    http.EnableFreshConnection(true)
    http.EnablePeerVerification(false)
    http.EnableHostVerification(false)
    http.RetainBodyOnError(true)

    ' Set up message port
    port = createObject("roMessagePort")
    http.setPort(port)

    ' Make the request - use HEAD first to check for redirect without downloading
    if http.asyncHead()
        ' Wait for response (10 second timeout)
        msg = wait(10000, port)
        if type(msg) = "roUrlEvent"
            responseCode = msg.getResponseCode()

            ' Check response headers
            responseHeaders = msg.GetResponseHeaders()
            if responseHeaders <> invalid
                for each header in responseHeaders
                    headerLower = LCase(header)
                end for

                ' Check for Location header (redirect)
                if responseHeaders.DoesExist("location")
                    redirectUrl = responseHeaders["location"]
                    return redirectUrl
                else if responseHeaders.DoesExist("Location")
                    redirectUrl = responseHeaders["Location"]
                    return redirectUrl
                end if
            end if

            ' Check if roUrlTransfer followed redirects automatically
            finalUrl = http.GetUrl()
            if finalUrl <> url
                return finalUrl
            end if
        else
            http.asyncCancel()
        end if
    else
        print "ResolveUrlTask: Failed to start HEAD request"
    end if

    ' Return original URL on any failure
    return url
end function