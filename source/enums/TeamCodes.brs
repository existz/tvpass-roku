function GetNFLTeams() as Object
    return {
        "Cardinals": "cardinals", "Arizona Cardinals": "cardinals"
        "Falcons": "falcons", "Atlanta Falcons": "falcons"
        "Ravens": "ravens", "Baltimore Ravens": "ravens"
        "Bills": "bills", "Buffalo Bills": "bills"
        "Panthers": "panthers", "Carolina Panthers": "panthers"
        "Bears": "bears", "Chicago Bears": "bears"
        "Bengals": "bengals", "Cincinnati Bengals": "bengals"
        "Browns": "browns", "Cleveland Browns": "browns"
        "Cowboys": "cowboys", "Dallas Cowboys": "cowboys"
        "Broncos": "broncos", "Denver Broncos": "broncos"
        "Lions": "lions", "Detroit Lions": "lions"
        "Packers": "packers", "Green Bay Packers": "packers"
        "Texans": "texans", "Houston Texans": "texans"
        "Colts": "colts", "Indianapolis Colts": "colts"
        "Jaguars": "jaguars", "Jacksonville Jaguars": "jaguars"
        "Chiefs": "chiefs", "Kansas City Chiefs": "chiefs"
        "Raiders": "raiders", "Las Vegas Raiders": "raiders"
        "Chargers": "chargers", "Los Angeles Chargers": "chargers"
        "Rams": "rams", "Los Angeles Rams": "rams"
        "Dolphins": "dolphins", "Miami Dolphins": "dolphins"
        "Vikings": "vikings", "Minnesota Vikings": "vikings"
        "Patriots": "patriots", "New England Patriots": "patriots"
        "Saints": "saints", "New Orleans Saints": "saints"
        "Giants": "giants", "New York Giants": "giants"
        "Jets": "jets", "New York Jets": "jets"
        "Eagles": "eagles", "Philadelphia Eagles": "eagles"
        "Steelers": "steelers", "Pittsburgh Steelers": "steelers"
        "49ers": "49ers", "San Francisco 49ers": "49ers"
        "Seahawks": "seahawks", "Seattle Seahawks": "seahawks"
        "Buccaneers": "buccaneers", "Tampa Bay Buccaneers": "buccaneers"
        "Titans": "titans", "Tennessee Titans": "titans"
        "Commanders": "commanders", "Washington Commanders": "commanders"
    }
end function

function GetNBATeams() as Object
    return {
        "Hawks": "hawks", "Atlanta Hawks": "hawks"
        "Celtics": "celtics", "Boston Celtics": "celtics"
        "Nets": "nets", "Brooklyn Nets": "nets"
        "Hornets": "hornets", "Charlotte Hornets": "hornets"
        "Bulls": "bulls", "Chicago Bulls": "bulls"
        "Cavaliers": "cavaliers", "Cleveland Cavaliers": "cavaliers"
        "Mavericks": "mavericks", "Dallas Mavericks": "mavericks"
        "Nuggets": "nuggets", "Denver Nuggets": "nuggets"
        "Pistons": "pistons", "Detroit Pistons": "pistons"
        "Warriors": "warriors", "Golden State Warriors": "warriors"
        "Rockets": "rockets", "Houston Rockets": "rockets"
        "Pacers": "pacers", "Indiana Pacers": "pacers"
        "Clippers": "clippers", "LA Clippers": "clippers", "Los Angeles Clippers": "clippers"
        "Lakers": "lakers", "LA Lakers": "lakers", "Los Angeles Lakers": "lakers"
        "Grizzlies": "grizzlies", "Memphis Grizzlies": "grizzlies"
        "Heat": "heat", "Miami Heat": "heat"
        "Bucks": "bucks", "Milwaukee Bucks": "bucks"
        "Timberwolves": "timberwolves", "Minnesota Timberwolves": "timberwolves"
        "Pelicans": "pelicans", "New Orleans Pelicans": "pelicans"
        "Knicks": "knicks", "New York Knicks": "knicks"
        "Thunder": "thunder", "Oklahoma City Thunder": "thunder"
        "Magic": "magic", "Orlando Magic": "magic"
        "76ers": "76ers", "Philadelphia 76ers": "76ers"
        "Suns": "suns", "Phoenix Suns": "suns"
        "Trail Blazers": "trailblazers", "Portland Trail Blazers": "trailblazers"
        "Kings": "kings", "Sacramento Kings": "kings"
        "Spurs": "spurs", "San Antonio Spurs": "spurs"
        "Raptors": "raptors", "Toronto Raptors": "raptors"
        "Jazz": "jazz", "Utah Jazz": "jazz"
        "Wizards": "wizards", "Washington Wizards": "wizards"
    }
end function

function GetMLBTeams() as Object
    return {
        "Diamondbacks": "diamondbacks", "Arizona Diamondbacks": "diamondbacks"
        "Braves": "braves", "Atlanta Braves": "braves"
        "Orioles": "orioles", "Baltimore Orioles": "orioles"
        "Red Sox": "red-sox", "Boston Red Sox": "red-sox"
        "Cubs": "cubs", "Chicago Cubs": "cubs"
        "White Sox": "white-sox", "Chicago White Sox": "white-sox"
        "Reds": "reds", "Cincinnati Reds": "reds"
        "Guardians": "guardians", "Cleveland Guardians": "guardians"
        "Rockies": "rockies", "Colorado Rockies": "rockies"
        "Tigers": "tigers", "Detroit Tigers": "tigers"
        "Astros": "astros", "Houston Astros": "astros"
        "Royals": "royals", "Kansas City Royals": "royals"
        "Angels": "angels", "Los Angeles Angels": "angels"
        "Dodgers": "dodgers", "Los Angeles Dodgers": "dodgers"
        "Marlins": "marlins", "Miami Marlins": "marlins"
        "Brewers": "brewers", "Milwaukee Brewers": "brewers"
        "Twins": "twins", "Minnesota Twins": "twins"
        "Mets": "mets", "New York Mets": "mets"
        "Yankees": "yankees", "New York Yankees": "yankees"
        "Athletics": "athletics", "Oakland Athletics": "athletics"
        "Phillies": "phillies", "Philadelphia Phillies": "phillies"
        "Pirates": "pirates", "Pittsburgh Pirates": "pirates"
        "Padres": "padres", "San Diego Padres": "padres"
        "Giants": "giants", "San Francisco Giants": "giants"
        "Mariners": "mariners", "Seattle Mariners": "mariners"
        "Cardinals": "cardinals", "St. Louis Cardinals": "cardinals"
        "Rays": "rays", "Tampa Bay Rays": "rays"
        "Rangers": "rangers", "Texas Rangers": "rangers"
        "Blue Jays": "blue-jays", "Toronto Blue Jays": "blue-jays"
        "Nationals": "nationals", "Washington Nationals": "nationals"
    }
end function

function GetTeamCodeByLeague(teamName as String, league as String) as Dynamic
    print "GetTeamCodeByLeague: Looking for '"; teamName; "' in league "; league
    
    if league = "NFL"
        teams = GetNFLTeams()
        for each key in teams
            if teamName.Instr(key) >= 0
                print "GetTeamCodeByLeague: Found match for '"; key; "' -> "; teams[key]
                return teams[key]
            end if
        end for
    else if league = "NBA"
        teams = GetNBATeams()
        for each key in teams
            if teamName.Instr(key) >= 0
                print "GetTeamCodeByLeague: Found match for '"; key; "' -> "; teams[key]
                return teams[key]
            end if
        end for
    else if league = "MLB"
        teams = GetMLBTeams()
        for each key in teams
            if teamName.Instr(key) >= 0
                print "GetTeamCodeByLeague: Found match for '"; key; "' -> "; teams[key]
                return teams[key]
            end if
        end for
    end if
    
    print "GetTeamCodeByLeague: No match found for '"; teamName; "'"
    return invalid
end function