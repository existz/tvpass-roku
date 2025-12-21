function GetTVPassUrls() as Object
    return {
        TVPASS_PLAYLIST: "https://tvpass.org/playlist/m3u"
        TVPASS_EPG: "https://tvpass.org/epg.xml"
        TVPASS_HD_FALLBACK: "https://raw.githubusercontent.com/existz/tvpass/refs/heads/main/tvpasshd.m3u"
    }
end function

function GetLogoUrls() as Object
    return {
        TEAM_LOGOS_BASE: "https://raw.githubusercontent.com/existz/team-logos/master/"
        NCAAF_LOGOS_BASE: "https://a.espncdn.com/i/teamlogos/ncaa/500-dark/"
        TV_LOGOS_BASE: "https://raw.githubusercontent.com/existz/tv-logos/main/countries/united-states/"
        TV_LOGOS_LOCAL: "https://raw.githubusercontent.com/existz/tv-logos/main/countries/united-states/us-local/"
    }
end function