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
-- gd, bd, pr, combo, gauge, date}}, me = my row or nil, err = message}
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
					lane = R.shortLane(f[14] or ""),
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
	end
end
