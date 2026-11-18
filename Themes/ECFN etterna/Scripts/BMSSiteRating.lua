-- The player's rating as the ranking site shows it on Players and on the
-- profile ("Good enough rating"): the average clear rating of the 20 best
-- charts, each at its best lamp (Hard value for FC / EX HARD / HARD, Easy
-- value for CLEAR / EASY), from the site's /calcrating.json and the best
-- lamps in /api/players, the same way public/app.js playerRating() does it
-- with every table on. Asked once per song select visit; the answer comes
-- as the BMSSiteRatingLoaded message.

BMSSiteRating = BMSSiteRating or {}
local S = BMSSiteRating
local RATING_TOP = 20
-- unranked: 7k charts in no table, rated by the game's clear calc (/api/unranked-calc)
local TABLES = {insane = true, satellite = true, stella = true, overjoy = true, delay = true, delayjoy = true, dystopia = true, ude = true, gachimijoy = true, unranked = true}

-- chart key -> {easy, hard}, read with a pattern (the file is big)
local function parseCalc(body)
	local gr = {}
	for k, e, h in (body or ""):gmatch('"([^"]+)":%[(%-?[%d%.eE%-]+),(%-?[%d%.eE%-]+)%]') do
		gr[k] = {tonumber(e), tonumber(h)}
	end
	return gr
end

local function inTables(tbls)
	for t in tostring(tbls or ""):gmatch("[^,]+") do
		if TABLES[t] then
			return true
		end
	end
	return false
end

local function compute(best)
	local vals = {}
	for _, b in ipairs(best or {}) do
		local key, lamp, tbls = b[1], tonumber(b[2]), b[3]
		local g = S.calc and S.calc[key]
		if g and lamp and lamp >= 1 and lamp <= 5 and inTables(tbls) then
			vals[#vals + 1] = lamp <= 3 and g[2] or g[1]
		end
	end
	table.sort(vals, function(a, b)
		return a > b
	end)
	local n = math.min(#vals, RATING_TOP)
	if n == 0 then
		return nil
	end
	local sum = 0
	for i = 1, n do
		sum = sum + vals[i]
	end
	return sum / n
end

local function done()
	MESSAGEMAN:Broadcast("BMSSiteRatingLoaded", {rating = S.rating})
end

local function askPlayers(name)
	DLMAN:BMSRequest("GET", "/api/players", {}, function(status, body)
		if status ~= 200 then
			return
		end
		local ok, data = pcall(BMSRanking.json, body)
		if not ok or type(data) ~= "table" then
			return
		end
		local list = data.players or data
		local me = string.lower(name)
		for _, p in ipairs(list) do
			if type(p) == "table" and string.lower(tostring(p.name)) == me then
				S.rating = compute(p.best)
				S.name = name
				done()
				return
			end
		end
	end)
end

-- ask the site again (the cached value stays shown until it answers)
function S.refresh()
	if not (BMSRanking and BMSRanking.loggedIn and BMSRanking.loggedIn()) then
		return
	end
	local name = BMSRanking.name()
	if name == "" then
		return
	end
	if S.name ~= name then
		S.rating = nil
	end
	-- the unranked charts' ratings change as people play them: asked every time,
	-- calcrating.json wins where both have a chart
	local function withUnranked()
		DLMAN:BMSRequest("GET", "/api/unranked-calc", {}, function(status, body)
			S.calc = {}
			if status == 200 then
				for k, v in pairs(parseCalc(body)) do
					S.calc[k] = v
				end
			end
			for k, v in pairs(S.base) do
				S.calc[k] = v
			end
			askPlayers(name)
		end)
	end
	if S.base then
		withUnranked()
		return
	end
	DLMAN:BMSRequest("GET", "/calcrating.json", {}, function(status, body)
		if status ~= 200 then
			return
		end
		S.base = parseCalc(body)
		withUnranked()
	end)
end

-- "12.34", or "-" before the site answered / when not logged in
function S.text()
	if S.rating == nil then
		return "-"
	end
	return string.format("%.2f", S.rating)
end
