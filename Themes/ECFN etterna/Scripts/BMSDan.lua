-- BMS dan courses (段位認定, e.g. GENOSIDE 2018) for 7k.
-- Courses come from the json files in Assets/BMSCourses/ (format 1, see
-- genoside2018.json). Charts are found among the loaded 7k songs by title:
-- converted charts have no bms md5, so each course chart lists the titles it
-- can go by (local_title = the BMS2SM convert's #TITLE + #SUBTITLE,
-- table_title = the difficulty table's, title = the course file's).
-- The engine plays the course (ScreenSelectMusic:StartBMSCourse) on a course
-- gauge, the eval screen saves the result here and sends it to the ranking
-- site (BMSDan.finish).

BMSDan = BMSDan or {}
local D = BMSDan
local COURSE_DIR = "/Assets/BMSCourses/"

---------------------------------------------------------------------------
-- a small json reader (the course files only)
---------------------------------------------------------------------------

local function jsonDecode(str)
	local pos = 1
	local value

	local function ws()
		pos = str:find("[^ \t\r\n]", pos) or #str + 1
	end

	local function utf8(cp)
		if cp < 0x80 then
			return string.char(cp)
		elseif cp < 0x800 then
			return string.char(0xC0 + math.floor(cp / 0x40), 0x80 + cp % 0x40)
		end
		return string.char(0xE0 + math.floor(cp / 0x1000), 0x80 + math.floor(cp / 0x40) % 0x40, 0x80 + cp % 0x40)
	end

	local function str_()
		local out = {}
		pos = pos + 1 -- opening quote
		while true do
			local c = str:sub(pos, pos)
			if c == "" then
				error("unterminated string")
			elseif c == '"' then
				pos = pos + 1
				return table.concat(out)
			elseif c == "\\" then
				local e = str:sub(pos + 1, pos + 1)
				local map = {b = "\b", f = "\f", n = "\n", r = "\r", t = "\t"}
				if e == "u" then
					out[#out + 1] = utf8(tonumber(str:sub(pos + 2, pos + 5), 16) or 63)
					pos = pos + 6
				else
					out[#out + 1] = map[e] or e
					pos = pos + 2
				end
			else
				local s, e = str:find('^[^"\\]+', pos)
				out[#out + 1] = str:sub(s, e)
				pos = e + 1
			end
		end
	end

	function value()
		ws()
		local c = str:sub(pos, pos)
		if c == "{" then
			local obj = {}
			pos = pos + 1
			ws()
			if str:sub(pos, pos) == "}" then
				pos = pos + 1
				return obj
			end
			while true do
				ws()
				local k = str_()
				ws()
				pos = pos + 1 -- :
				obj[k] = value()
				ws()
				local d = str:sub(pos, pos)
				pos = pos + 1
				if d == "}" then
					return obj
				end
			end
		elseif c == "[" then
			local arr = {}
			pos = pos + 1
			ws()
			if str:sub(pos, pos) == "]" then
				pos = pos + 1
				return arr
			end
			while true do
				arr[#arr + 1] = value()
				ws()
				local d = str:sub(pos, pos)
				pos = pos + 1
				if d == "]" then
					return arr
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
		local s, e = str:find("^-?[%d%.eE+-]+", pos)
		if not s then
			error("bad json at " .. pos)
		end
		pos = e + 1
		return tonumber(str:sub(s, e))
	end

	return value()
end

local function readFile(path)
	local f = RageFileUtil.CreateRageFile()
	if not f:Open(path, 1) then
		f:destroy()
		return nil
	end
	local s = f:Read()
	f:Close()
	f:destroy()
	return s
end

---------------------------------------------------------------------------
-- courses
---------------------------------------------------------------------------

-- D.sets = {{name, courses = {{id, name, short, rank, constraint, charts}}}}
function D.load(force)
	if D.sets and not force then
		return D.sets
	end
	D.sets = {}
	local files = FILEMAN:GetDirListing(COURSE_DIR .. "*.json", false, false) or {}
	table.sort(files)
	for _, f in ipairs(files) do
		local text = readFile(COURSE_DIR .. f)
		local ok, data = pcall(jsonDecode, text or "")
		if ok and type(data) == "table" and type(data.courses) == "table" then
			D.sets[#D.sets + 1] = {name = data.set or f, file = f, courses = data.courses}
		else
			Trace("BMS dan: could not read " .. f .. ": " .. tostring(data))
		end
	end
	return D.sets
end

function D.allCourses()
	local out = {}
	for _, set in ipairs(D.load()) do
		for _, c in ipairs(set.courses) do
			c.set = set.name
			out[#out + 1] = c
		end
	end
	return out
end

function D.byId(id)
	for _, c in ipairs(D.allCourses()) do
		if c.id == id then
			return c
		end
	end
end

-- titles compared without case, ASCII spaces / punctuation and the
-- ideographic space, so "SOLROS [MX]" finds "SOLROS[MX]"
local function norm(s)
	s = string.lower(s or "")
	s = s:gsub("%s", ""):gsub("%p", ""):gsub("\227\128\128", "")
	return s
end

local songIndex
local function index()
	if songIndex then
		return songIndex
	end
	songIndex = {}
	for _, song in ipairs(SONGMAN:GetAllSongs()) do
		local st = getBMSSongSteps(song)
		if st then
			local keys = {
				norm(song:GetDisplayMainTitle() .. song:GetDisplaySubTitle()),
				norm(song:GetTranslitMainTitle() .. song:GetTranslitSubTitle()),
				norm(song:GetDisplayMainTitle()),
			}
			for _, k in ipairs(keys) do
				if k ~= "" and songIndex[k] == nil then
					songIndex[k] = {song = song, steps = st}
				end
			end
		end
	end
	return songIndex
end

-- songs added or reloaded: look again
function D.reindex()
	songIndex = nil
end

-- {song, steps, chartkey} per course chart, nil where it is missing;
-- second value: how many were found
function D.resolve(course)
	local idx = index()
	local out, found = {}, 0
	for i, ch in ipairs(course.charts or {}) do
		local hit
		for _, t in ipairs({ch.local_title, ch.table_title, ch.title}) do
			if t and idx[norm(t)] then
				hit = idx[norm(t)]
				break
			end
		end
		if hit then
			out[i] = {song = hit.song, steps = hit.steps, chartkey = hit.steps:GetChartKey()}
			found = found + 1
		end
	end
	return out, found
end

-- starts the course from song select; returns ok, reason
function D.start(course)
	local res, found = D.resolve(course)
	if found < #course.charts then
		return false, (#course.charts - found) .. " chart(s) of the course are missing"
	end
	local keys = {}
	for i, r in ipairs(res) do
		keys[i] = r.chartkey
	end
	local top = SCREENMAN:GetTopScreen()
	if not top or not top.StartBMSCourse then
		return false, "this build of the game has no dan courses"
	end
	return top:StartBMSCourse(course.id, course.name, keys)
end

---------------------------------------------------------------------------
-- records (BMSDan.ini in the profile folder)
---------------------------------------------------------------------------

local function recordPath()
	return PROFILEMAN:GetProfileDir("ProfileSlot_Player1") .. "BMSDan.ini"
end

function D.records()
	if not D.rec then
		local ok, r = pcall(IniFile.ReadFile, recordPath())
		D.rec = ok and r or {}
	end
	return D.rec
end

-- course gauges from weakest to strongest
D.gaugeRank = {Class = 1, ExClass = 2, ExHardClass = 3}
D.gaugeNames = {Class = "CLASS", ExClass = "EX CLASS", ExHardClass = "EX HARD CLASS"}

function D.record(id)
	return D.records()[id]
end

-- the hardest cleared course: course table (with .rank) or nil
function D.best()
	local best
	for _, c in ipairs(D.allCourses()) do
		local r = D.record(c.id)
		if r and tonumber(r.cleared) == 1 and (best == nil or (c.rank or 0) > (best.rank or 0)) then
			best = c
		end
	end
	return best
end

local function judgeText(j)
	local t = {}
	for i = 1, 6 do
		t[i] = tostring(j[i] or 0)
	end
	return table.concat(t, ",")
end

-- called once by the eval screen with SONGMAN:GetBMSCourseResult()
function D.finish(res)
	if not res or not res.finished then
		return
	end
	local key = res.id .. ":" .. table.concat(res.scoreKeys or {}, ",")
	if D.lastFinished == key then
		return -- the eval screen was loaded again
	end
	D.lastFinished = key

	local recs = D.records()
	local r = recs[res.id] or {}
	r.name = res.name
	r.attempts = (tonumber(r.attempts) or 0) + 1
	r.best_songs = math.max(tonumber(r.best_songs) or 0, res.songsPlayed)
	if res.cleared then
		local old = D.gaugeRank[r.gauge_type or ""] or 0
		local new = D.gaugeRank[res.classGauge] or 0
		if tonumber(r.cleared) ~= 1 or new > old or (new == old and res.gauge > (tonumber(r.gauge) or 0)) then
			r.gauge_type = res.classGauge
			r.gauge = string.format("%.1f", res.gauge)
			r.judges = judgeText(res.judges)
			r.date = os and os.date and os.date("%Y-%m-%d %H:%M:%S") or ""
		end
		r.cleared = 1
	else
		r.cleared = r.cleared or 0
	end
	recs[res.id] = r
	pcall(IniFile.WriteFile, recordPath(), recs)

	-- the ranking site keeps every attempt, the profile shows the best clear
	if BMSRanking and BMSRanking.loggedIn and BMSRanking.loggedIn() then
		local c = D.byId(res.id) or {}
		local j = res.judges or {}
		DLMAN:BMSRequest("POST", "/api/game/dan", {
			course_id = res.id,
			course_name = res.name,
			course_set = c.set or "",
			course_rank = tostring(c.rank or 0),
			cleared = res.cleared and "1" or "0",
			gauge_type = res.classGauge,
			gauge = string.format("%.1f", res.gauge),
			songs = tostring(res.songsPlayed),
			songs_total = tostring(res.songsTotal),
			pg = tostring(j[1] or 0), gr = tostring(j[2] or 0), gd = tostring(j[3] or 0),
			bd = tostring(j[4] or 0), pr = tostring(j[5] or 0), ep = tostring(j[6] or 0),
			max_combo = tostring(res.maxCombo or 0),
			notes = tostring(res.notes or 0),
			score_keys = table.concat(res.scoreKeys or {}, ","),
		}, function(status, body)
			MESSAGEMAN:Broadcast("BMSDanUploaded", {ok = status == 200, body = body})
		end)
	end
end
