function CreateBitmapCache() as Object
    cache = {
        cachedUris: {},
        preloadedPosters: [],
        failedUris: {},
        maxCacheSize: 150
    }

    cache.preload = function(uris as Object, parentNode as Object) as Void
        if uris = invalid or uris.count() = 0 then return

        m.DebugLog("BitmapCache: Preloading " + stri(uris.count()) + " URIs")

        loaded = 0

        for each uri in uris
            if uri = invalid or uri = "" then continue for
            if m.cachedUris.doesExist(uri) then continue for
            if m.failedUris.doesExist(uri) then continue for

            m.cachedUris[uri] = true
            loaded++

            if parentNode <> invalid
                m.createPreloadPoster(uri, parentNode)
            end if
        end for

        m.DebugLog("BitmapCache: Added " + stri(loaded) + " URIs to cache")
    end function

    cache.createPreloadPoster = function(uri as String, parentNode as Object) as Void
        if m.preloadedPosters.count() >= m.maxCacheSize then return

        poster = createObject("roSGNode", "Poster")
        poster.uri = uri
        poster.width = 1
        poster.height = 1
        poster.visible = false

        if parentNode <> invalid and parentNode.appendChild <> invalid
            parentNode.appendChild(poster)
            m.preloadedPosters.push(poster)
        end if
    end function

    cache.isCached = function(uri as String) as Boolean
        if uri = invalid or uri = "" then return false
        return m.cachedUris.doesExist(uri) or m.failedUris.doesExist(uri)
    end function

    cache.markFailed = function(uri as String) as Void
        if uri <> invalid and uri <> ""
            m.failedUris[uri] = true
            m.cachedUris.delete(uri)
        end if
    end function

    cache.collectUrisFromChannels = function(channels as Object) as Object
        uris = {}
        if channels = invalid then return uris

        for each channel in channels
            if channel.logo <> invalid and channel.logo <> ""
                uris[channel.logo] = true
            end if
        end for

        return uris
    end function

    cache.collectUrisFromEPG = function(epgData as Object) as Object
        uris = {}
        if epgData = invalid or epgData.channels = invalid then return uris

        for each channel in epgData.channels
            if channel.logo <> invalid and channel.logo <> ""
                uris[channel.logo] = true
            end if
        end for

        return uris
    end function

    cache.clear = function() as Void
        m.cachedUris.clear()
        m.failedUris.clear()

        for each poster in m.preloadedPosters
            parent = poster.getParent()
            if parent <> invalid
                parent.removeChild(poster)
            end if
        end for

        m.preloadedPosters.clear()
        m.DebugLog("BitmapCache: Cleared all cached bitmaps")
    end function

    cache.getCacheSize = function() as Integer
        return m.cachedUris.count()
    end function

    cache.DebugLog = function(message as String) as Void
        print "[BitmapCache] " + message
    end function

    return cache
end function