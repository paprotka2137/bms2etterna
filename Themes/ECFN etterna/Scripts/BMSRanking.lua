-- BMS 7k ranking site: logging in from the game and the chart rankings.
-- The game sends every 1.0x kb7 play by itself once logged in (C++ side,
-- DLMAN:BMSUploadScore after each song). The site answers in plain text:
-- the first line is "OK ..." or "ERR <message>", fields split by tabs.

BMSRanking = BMSRanking or {}
local R = BMSRanking
R.cache = {}

local function split(s, sep)
	local out = {}
	local start = 1
	while true do
		local i = s:find(sep, start, true)
		if not i then
			out[#out + 1] = s:sub(start)
			return out
		end
		out[#out + 1] = s:sub(start, i - 1)
		start = i + #sep
	end
end

local function parse(body)
	local lines = {}
	local text = (body or ""):gsub("\r", "")
	for _, l in ipairs(split(text, "\n")) do
		if l ~= "" then
			lines[#lines + 1] = split(l, "\t")
		end
	end
	return lines
end

-- false on a game built without the ranking code
function R.available()
	return DLMAN ~= nil and DLMAN.BMSRequest ~= nil
end

function R.loggedIn()
	return R.available() and DLMAN:BMSIsLoggedIn()
end

function R.name()
	return R.available() and DLMAN:BMSGetName() or ""
end

local function errorOf(status, lines)
	if status == 0 then
		return "no connection to the ranking site"
	end
	if lines[1] and lines[1][1] == "ERR" then
		return lines[1][2] or "error"
	end
	return "site error " .. tostring(status)
end

-- the ranking of a chart: returns the cached board, or nil and asks the
-- site, which broadcasts BMSBoardLoaded {chartkey} when it answers (actors
-- listen for that instead of getting a callback, so an answer that comes
-- after the screen is gone touches nothing).
-- board = {notes, players, rows = {{rank, name, lamp, ex, judged, pg, gr,
-- gd, bd, pr, combo, gauge, date, lane, key}}, me = my row or nil, err = message}
R.pending = {}
function R.chart(ck, force)
	if not ck then
		return nil
	end
	if not R.available() then
		return {err = "this build of the game has no ranking support", rows = {}}
	end
	local c = R.cache[ck]
	if c and not force and GetTimeSinceStart() - c.t < (c.board.err and 5 or 60) then
		return c.board
	end
	if R.pending[ck] then
		return nil
	end
	R.pending[ck] = true
	DLMAN:BMSRequest("GET", "/api/game/chart/" .. ck, {}, function(status, body)
		R.pending[ck] = nil
		local lines = parse(body)
		local board = {rows = {}}
		if status ~= 200 or not lines[1] or lines[1][1] ~= "OK" then
			board.err = errorOf(status, lines)
		else
			board.notes = tonumber(lines[1][2]) or 0
			board.players = tonumber(lines[1][3]) or 0
			local me = string.lower(R.name())
			for i = 2, #lines do
				local f = lines[i]
				local row = {
					rank = tonumber(f[1]) or i - 1,
					name = f[2] or "?",
					lamp = tonumber(f[3]) or 6,
					ex = tonumber(f[4]) or 0,
					judged = tonumber(f[5]) or 0,
					pg = tonumber(f[6]) or 0,
					gr = tonumber(f[7]) or 0,
					gd = tonumber(f[8]) or 0,
					bd = tonumber(f[9]) or 0,
					pr = tonumber(f[10]) or 0,
					combo = tonumber(f[11]) or 0,
					gauge = f[12] or "",
					date = f[13] or "",
					-- "RANDOM 3527164": newer sites add the lane order of the play
					lane = R.shortLane(((f[14] or ""):gsub(" %d+$", ""))),
					laneOrder = (f[14] or ""):match("^%S+ (%d%d%d%d%d%d%d)$"),
					-- the play's key on the site, sent by newer versions of the site
					key = (f[15] and f[15] ~= "") and f[15] or nil,
				}
				row.bp = row.bd + row.pr
				board.rows[#board.rows + 1] = row
				if me ~= "" and string.lower(row.name) == me then
					board.me = row
				end
			end
		end
		R.cache[ck] = {t = GetTimeSinceStart(), board = board}
		MESSAGEMAN:Broadcast("BMSBoardLoaded", {chartkey = ck})
	end)
	return nil
end

-- lane option of a score from its modifiers, the same names as the site:
-- OFF, RANDOM, R-RANDOM, S-RANDOM, H-RANDOM, MIRROR or the lane order ("2143657")
function R.laneOf(mods)
	for t in string.gmatch(string.lower(mods or ""), "[^,]+") do
		t = t:gsub("^%s+", ""):gsub("%s+$", "")
		if t == "bmsrandom" or t == "random" then
			return "RANDOM"
		elseif t == "srandom" or t == "s-random" or t == "bmssrandom" then
			return "S-RANDOM"
		elseif t == "hrandom" or t == "h-random" or t == "bmshrandom" then
			return "H-RANDOM"
		elseif t == "rrandom" or t == "r-random" or t == "bmsrrandom" then
			return "R-RANDOM"
		elseif t == "mirror" or t == "bmsmirror" then
			return "MIRROR"
		end
	end
	for t in string.gmatch(string.lower(mods or ""), "[^,]+") do
		local order = t:match("^%s*lanes(%d%d%d%d%d%d%d)%s*$")
		if order then
			return order == "1234567" and "OFF" or order
		end
	end
	return "OFF"
end

-- the lane order a RANDOM / R-RANDOM / MIRROR score was played on
-- ("3527164": lane 1 had the chart's lane 3...), nil for other options and
-- on a game built without it
function R.laneOrderOf(score)
	if not score or not score.GetBMSLaneOrder then
		return nil
	end
	local lane = R.laneOf(score:GetModifiers())
	if lane ~= "RANDOM" and lane ~= "R-RANDOM" and lane ~= "MIRROR" then
		return nil
	end
	local order = score:GetBMSLaneOrder()
	return (order and #order == 7) and order or nil
end

-- short form for the narrow column
function R.shortLane(lane)
	local short = {["RANDOM"] = "RAN", ["S-RANDOM"] = "S-RAN", ["H-RANDOM"] = "H-RAN", ["R-RANDOM"] = "R-RAN", ["MIRROR"] = "MIR", [""] = "-"}
	return short[lane] or lane
end

-- "93.21%" of the chart's max EX (2 per note), "-" before anyone clears it
-- notes: the chart's own note count from the game, so failed plays get a
-- rate too before anyone has cleared the chart (the site only knows the
-- note count from a clear)
function R.rate(board, row, notes)
	-- O2Jam charts: the site keeps the DMJam score in thousandths
	if isO2JamPlay() then
		local v = row.ex / 1000
		return string.format("%.3f %s", v, getO2JamGrade(v))
	end
	local n = (notes and notes > 0) and notes or board.notes
	if not n or n <= 0 then
		return "-"
	end
	return string.format("%.2f%%", row.ex / (2 * n) * 100)
end

-- note count of the selected chart
function R.chartNotes()
	local steps = GAMESTATE:GetCurrentSteps()
	if not steps then
		return 0
	end
	return steps:GetRadarValues(PLAYER_1):GetValue("RadarCategory_Notes") or 0
end

function R.login(name, password, cb)
	DLMAN:BMSRequest("POST", "/api/game/login", {name = name, password = password}, function(status, body)
		local lines = parse(body)
		if status == 200 and lines[1] and lines[1][1] == "OK" and lines[1][2] then
			R.cache = {}
			DLMAN:BMSSetLogin(lines[1][3] or name, lines[1][2])
			cb(true, lines[1][3] or name)
		else
			cb(false, errorOf(status, lines))
		end
	end)
end

function R.logout()
	if R.loggedIn() then
		DLMAN:BMSRequest("POST", "/api/game/logout", {}, function() end)
	end
	R.cache = {}
	DLMAN:BMSSetLogin("", "")
end

-- asks for the nick and the password in two text boxes, then logs in.
-- `stepper` is any actor, it waits a moment between the two boxes like
-- the Etterna Online login does
function R.askLogin(stepper)
	if not R.available() then
		ms.ok("This build of the game has no ranking support")
		return
	end
	local redir = SCREENMAN:get_input_redirected(PLAYER_1)
	local function setRedir(v)
		if redir then
			SCREENMAN:set_input_redirected(PLAYER_1, v)
		end
	end
	setRedir(false)
	local trim = function(s)
		return (s:gsub("^%s*(.-)%s*$", "%1"))
	end
	easyInputStringOKCancel("Ranking nick or email:", 255, false, function(name)
		name = trim(name)
		if name == "" then
			setRedir(true)
			return
		end
		R.pendingName = name
		stepper:stoptweening():sleep(0.04):queuecommand("BMSLoginStep2")
	end, function()
		setRedir(true)
	end)
	-- the actor runs this from BMSLoginStep2Command
	R.step2 = function()
		easyInputStringOKCancel("Ranking password:", 255, true, function(password)
			local name = R.pendingName
			R.pendingName = nil
			setRedir(true)
			if password == "" then
				return
			end
			ms.ok("Logging in to the ranking...")
			R.login(name, password, function(ok, msg)
				if ok then
					ms.ok("Ranking: logged in as " .. msg)
				else
					ms.ok("Ranking login failed: " .. msg)
				end
			end)
		end, function()
			R.pendingName = nil
			setRedir(true)
		end)
	end
end

-- drop cached rankings when a play was sent or the login changed
function R.forget(ck)
	if ck then
		R.cache[ck] = nil
		R.pending[ck] = nil
	else
		R.cache = {}
		R.pending = {}
		R.details = {}
	end
end

-- ---------------------------------------------------------------- one play
-- clicking a player's row in the Ranking window shows that play like the
-- site's score window: judgments come with the board, the gauge graph,
-- modifiers and judge come from the site's /api/score (the same one the
-- site's own page uses), found by the play's key.

-- a small JSON reader for the site's /api answers (the game has none)
function R.json(str)
	local pos = 1
	local function ws()
		pos = str:find("[^ \t\r\n]", pos) or #str + 1
	end
	local value
	local function utf8(c)
		if c < 0x80 then
			return string.char(c)
		elseif c < 0x800 then
			return string.char(0xC0 + math.floor(c / 64), 0x80 + c % 64)
		end
		return string.char(0xE0 + math.floor(c / 4096), 0x80 + math.floor(c / 64) % 64, 0x80 + c % 64)
	end
	local esc = {b = "\b", f = "\f", n = "\n", r = "\r", t = "\t"}
	local function str_()
		local out = {}
		pos = pos + 1
		while true do
			local c = str:sub(pos, pos)
			if c == "" then
				error("unfinished string")
			elseif c == '"' then
				pos = pos + 1
				return table.concat(out)
			elseif c == "\\" then
				local e = str:sub(pos + 1, pos + 1)
				if e == "u" then
					local code = tonumber(str:sub(pos + 2, pos + 5), 16) or 63
					pos = pos + 6
					-- a surrogate pair: one character outside the BMP
					if code >= 0xD800 and code <= 0xDBFF and str:sub(pos, pos + 1) == "\\u" then
						local lo = tonumber(str:sub(pos + 2, pos + 5), 16) or 0
						pos = pos + 6
						code = 0x10000 + (code - 0xD800) * 1024 + (lo - 0xDC00)
						out[#out + 1] = string.char(0xF0 + math.floor(code / 262144), 0x80 + math.floor(code / 4096) % 64,
							0x80 + math.floor(code / 64) % 64, 0x80 + code % 64)
					else
						out[#out + 1] = utf8(code)
					end
				else
					out[#out + 1] = esc[e] or e
					pos = pos + 2
				end
			else
				local j = str:find('["\\]', pos)
				if not j then
					error("unfinished string")
				end
				out[#out + 1] = str:sub(pos, j - 1)
				pos = j
			end
		end
	end
	value = function()
		ws()
		local c = str:sub(pos, pos)
		if c == "{" then
			local o = {}
			pos = pos + 1
			ws()
			if str:sub(pos, pos) == "}" then
				pos = pos + 1
				return o
			end
			while true do
				ws()
				local k = str_()
				ws()
				pos = pos + 1 -- :
				o[k] = value()
				ws()
				local d = str:sub(pos, pos)
				pos = pos + 1
				if d == "}" then
					return o
				elseif d ~= "," then
					error("bad object")
				end
			end
		elseif c == "[" then
			local a = {}
			pos = pos + 1
			ws()
			if str:sub(pos, pos) == "]" then
				pos = pos + 1
				return a
			end
			while true do
				a[#a + 1] = value()
				ws()
				local d = str:sub(pos, pos)
				pos = pos + 1
				if d == "]" then
					return a
				elseif d ~= "," then
					error("bad array")
				end
			end
		elseif c == '"' then
			return str_()
		elseif str:sub(pos, pos + 3) == "true" then
			pos = pos + 4
			return true
		elseif str:sub(pos, pos + 4) == "false" then
			pos = pos + 5
			return false
		elseif str:sub(pos, pos + 3) == "null" then
			pos = pos + 4
			return nil
		end
		local num = str:match("^-?%d+%.?%d*[eE]?[-+]?%d*", pos)
		if not num or num == "" then
			error("bad value at " .. pos)
		end
		pos = pos + #num
		return tonumber(num)
	end
	local ok, v = pcall(value)
	if ok then
		return v
	end
	return nil
end

function R.urlEncode(s)
	return (tostring(s):gsub("[^%w%-%._~]", function(c)
		return string.format("%%%02X", string.byte(c))
	end))
end

-- details of one board row: returns them when cached, else nil and asks the
-- site, which broadcasts BMSScoreDetailLoaded {chartkey, name} when done.
-- detail = {err = message} or the site's score: lamp, gauge, judge, lanes,
-- modifiers, played_at, has_replay, score_key, graph = {0-100, ...} or nil
R.details = {}
local function detailId(ck, name)
	return ck .. "|" .. string.lower(name)
end
function R.scoreDetail(ck, row)
	if not ck or not row or not R.available() then
		return {err = "this build of the game has no ranking support"}
	end
	local id = detailId(ck, row.name)
	local d = R.details[id]
	if d and (d.ex == row.ex) and (not d.detail.err or GetTimeSinceStart() - d.t < 5) then
		return d.detail
	end
	if R.pending[id] then
		return nil
	end
	R.pending[id] = true
	local function done(detail)
		R.pending[id] = nil
		R.details[id] = {t = GetTimeSinceStart(), ex = row.ex, detail = detail}
		MESSAGEMAN:Broadcast("BMSScoreDetailLoaded", {chartkey = ck, name = row.name})
	end
	local function fetchScore(key)
		DLMAN:BMSRequest("GET", "/api/score/" .. R.urlEncode(row.name) .. "/" .. R.urlEncode(key), {}, function(status, body)
			local j = R.json(body or "")
			if status ~= 200 or type(j) ~= "table" or type(j.score) ~= "table" then
				local msg = type(j) == "table" and j.error or nil
				done({err = msg or (status == 0 and "no connection to the ranking site" or "site error " .. tostring(status))})
				return
			end
			local s = j.score
			local g = s.gauge_graph
			s.graph = (type(g) == "table" and #g > 1) and g or nil
			done(s)
		end)
	end
	if row.key then
		fetchScore(row.key)
		return nil
	end
	-- an older site sends no key with the board: find the play in the
	-- chart's list of every play (same player, EX and date)
	DLMAN:BMSRequest("GET", "/api/chart/" .. R.urlEncode(ck), {}, function(status, body)
		local j = R.json(body or "")
		if status ~= 200 or type(j) ~= "table" or type(j.all) ~= "table" then
			R.pending[id] = nil
			done({err = status == 0 and "no connection to the ranking site" or "could not find this play on the site"})
			return
		end
		local name = string.lower(row.name)
		local key, bestEx
		for _, s in ipairs(j.all) do
			if type(s) == "table" and string.lower(tostring(s.player)) == name then
				if s.ex == row.ex and tostring(s.played_at) == row.date then
					key = s.score_key
					break
				end
				if s.ex == row.ex and not bestEx then
					key, bestEx = s.score_key, s.ex
				end
			end
		end
		if not key then
			done({err = "could not find this play on the site"})
			return
		end
		row.key = key
		fetchScore(key)
	end)
	return nil
end

-- this profile's own copy of a play, when it is on this computer
function R.localScore(ck, key)
	local rates = ck and key and SCOREMAN:GetScoresByKey(ck)
	if not rates then
		return nil
	end
	for _, hsl in pairs(rates) do
		for _, sc in ipairs(hsl:GetScores()) do
			if sc:GetScoreKey() == key then
				return sc
			end
		end
	end
	return nil
end

-- DJ level of a rate (0-1), like the site
function R.djLevel(r)
	local n = r * 9
	local levels = {"F", "F", "E", "D", "C", "B", "A", "AA", "AAA"}
	return levels[math.max(1, math.min(9, math.floor(n) + 1))]
end
