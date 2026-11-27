-- The player's rating as the ranking site shows it on Players and on the
-- profile ("Good enough rating"): the average clear rating of the 20 best
-- charts, each at its best lamp (Hard value for FC / EX HARD / HARD, Easy
-- value for CLEAR / EASY), from the site's /calcrating.json and the best
-- lamps in /api/players, the same way public/app.js playerRating() does it
-- with every table on. Asked once per song select visit; the answer comes
-- as the BMSSiteRatingLoaded message.
--
-- By default the footer shows the same rating worked out from this
-- computer's scores (S.localRating): the best lamp of every 7k chart played
-- with BMS rules, its Easy / Hard value from calcrating.json on this computer,
-- else the game's clear calc, and the average of the 20 best. The site's
-- number is asked for and shown only while the Profile window's SITE switch
-- (BMSProfileSite) is on.

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

---------------------------------------------------------------------------
-- the local rating
---------------------------------------------------------------------------

local GR_FILE = "/leaderboard/site/public/calcrating.json"
-- chart key -> {easy, hard} from the site's file on this computer (shared
-- with the Profile window: the same global)
local function loadGR()
	if BMSGoodRatingFile then
		return BMSGoodRatingFile
	end
	local out = {}
	local f = RageFileUtil.CreateRageFile()
	if f:Open(GR_FILE, 1) then
		local str = f:Read() or ""
		f:Close()
		if BMSCalcFileCurrent and not BMSCalcFileCurrent(str) then
			str = ""
		end
		for k, e, h in str:gmatch('"([^"]+)":%[(-?[%d%.]+),(-?[%d%.]+)%]') do
			out[k] = {tonumber(e), tonumber(h)}
		end
	end
	f:destroy()
	BMSGoodRatingFile = out
	return out
end

-- the game's clear calc on the insane scale, kept for the whole game
BMSLocalGRCalc = BMSLocalGRCalc or {}
local function chartGR(ck, steps)
	local v = loadGR()[ck]
	if v then
		return v
	end
	local c = BMSLocalGRCalc[ck]
	if c ~= nil then
		return c or nil
	end
	BMSLocalGRCalc[ck] = false
	if steps and getBMSClearDifficulty then
		local was = BMSClearScale
		BMSClearScale = "insane"
		local ok, e, _, h = pcall(getBMSClearDifficulty, steps, 1)
		BMSClearScale = was
		if ok and e and h then
			BMSLocalGRCalc[ck] = {e, h}
		end
	end
	return BMSLocalGRCalc[ck] or nil
end

function S.computeLocal()
	if not (SCOREMAN and getBestBMSLamp) then
		return nil
	end
	local vals, seen = {}, {}
	SCOREMAN:SortRecentScoresForGame()
	local n = 1
	local hs = SCOREMAN:GetRecentScoreForGame(n)
	while hs do
		local ck = hs:GetChartKey()
		if not seen[ck] and not (isO2JamScore and isO2JamScore(hs)) then
			seen[ck] = true
			local steps = SONGMAN:GetStepsByChartKey(ck)
			if steps and steps:GetStepsType() == "StepsType_Kb7_Single" then
				local lamp = getBestBMSLamp(ck)
				if lamp and lamp >= 1 and lamp <= 5 then
					local g = chartGR(ck, steps)
					local v = g and (lamp <= 3 and g[2] or g[1])
					if v then
						vals[#vals + 1] = v
					end
				end
			end
		end
		n = n + 1
		hs = SCOREMAN:GetRecentScoreForGame(n)
	end
	table.sort(vals, function(a, b)
		return a > b
	end)
	local k = math.min(#vals, RATING_TOP)
	if k == 0 then
		return nil
	end
	local sum = 0
	for i = 1, k do
		sum = sum + vals[i]
	end
	return sum / k
end

local function done()
	MESSAGEMAN:Broadcast("BMSSiteRatingLoaded", {rating = S.rating})
end

-- only this player's lamps (?name=): the whole Players list reads every play
-- of every player from the site's database (an older site ignores ?name and
-- sends the whole list, which still works)
local function askPlayers(name)
	DLMAN:BMSRequest("GET", "/api/players", {name = name}, function(status, body)
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

-- work out the local rating, and ask the site again when SITE is on (the
-- cached value stays shown until it answers)
function S.refresh()
	local ok, v = pcall(S.computeLocal)
	S.localRating = ok and v or nil
	done()
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
	-- once per game start: after a calc update, send the unranked charts' ratings again
	if BMSRanking.resendCalc then
		BMSRanking.resendCalc()
	end
	if not BMSProfileSite then
		return
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

-- "12.34": the local rating, the site's while SITE is on ("-" before the
-- site answered); "-" with no rated clears
function S.text()
	local v = S.localRating
	if BMSProfileSite then
		v = S.rating
	end
	if v == nil then
		return "-"
	end
	return string.format("%.2f", v)
end
