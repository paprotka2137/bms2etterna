-- Res Extensa mono song select (7k). The chart reading is the ECFN one (ecfn.lua),
-- the drawing is the res extensa website's look.
-- is taken as relative to this file
local dir = THEME:GetCurrentThemeDirectory()
if dir:sub(1, 1) ~= "/" then
	dir = "/" .. dir
end
dir = dir .. "BGAnimations/ScreenSelectMusic decorations/ecfn/"
local W, H = 1920, 1080
local scale = ecfnScale()
-- the skin's top 200px are its title bar, the panels move up under the Til
-- Death top bar so the bottom windows end above the tabs
local shiftY = -123

-- lamps of the wheel bars, filled by the wheel items
ecfnLampCache = {}
-- level and LN label of the wheel bars, filled by the wheel items
ecfnBarCache = {}

-- the heavy reads (densities, FAST/SLOW from the replay) kept while the
-- screen is up, so going back to a chart does not read it again
local densityCache = {}
local replayCache = {}

---------------------------------------------------------------------------
-- chart and score data
---------------------------------------------------------------------------

local data = {}

local function tns(s, x)
	return s:GetTapNoteScore("TapNoteScore_" .. x)
end

-- LR2 judgments of a score: PGREAT GREAT GOOD BAD POOR
local function judgeCounts(s)
	return {tns(s, "W1"), tns(s, "W2"), tns(s, "W3"), tns(s, "W4") + tns(s, "W5"), tns(s, "Miss")}
end

-- O2Jam scores are compared by their DMJam score, kept in thousandths
local function exScore(s)
	if data.o2jam then
		return math.floor(getO2JamScore(s) * 1000 + 0.5)
	end
	return tns(s, "W1") * 2 + tns(s, "W2")
end

local function missCount(s)
	return getBMSMissCount(s)
end

local function comboBreaks(s)
	-- a long note let go early is already one of the BADs
	return tns(s, "W4") + tns(s, "W5") + tns(s, "Miss")
end

local function currentRate()
	return GAMESTATE:GetSongOptionsObject("ModsLevel_Preferred"):MusicRate()
end

-- DJ levels are ninths of the max EX score: index 1 AAA .. 8 F
local function djLevel(ex, maxEx)
	local r = ex / maxEx
	for i = 1, 7 do
		if r >= (9 - i) / 9 then
			return i
		end
	end
	return 8
end

local function djBorder(i, maxEx)
	return math.ceil(maxEx * (9 - i) / 9)
end

-- everything shown for the chart that does not need the replays
local function readChart()
	local song = GAMESTATE:GetCurrentSong()
	local steps = GAMESTATE:GetCurrentSteps()
	data = {song = song, steps = steps}
	if not song then
		return
	end
	data.level, data.levelRow = getBMSLevelDisplay(song, steps)
	data.bga = song:HasBGChanges()
	data.txt = song:HasLyrics()
	if not steps then
		return
	end

	local rate = currentRate()
	data.rate = rate
	local rv = steps:GetRadarValues(PLAYER_1)
	local notes = rv:GetValue("RadarCategory_Notes")
	local longs = rv:GetValue("RadarCategory_Holds") + rv:GetValue("RadarCategory_Rolls")
	data.notes = notes
	data.longs = longs
	data.taps = math.max(0, notes - longs)
	data.mines = rv:GetValue("RadarCategory_Mines")
	data.maxEx = math.max(notes * 2, 1)
	local total = steps:GetBMSTotal()
	data.total = (total and total > 0) and total or nil
	-- O2Jam charts: a long note is judged twice, the score is the DMJam
	-- score (100.000 at most, kept in thousandths) and there is no TOTAL
	data.o2jam = isO2JamPlayOf(steps)
	data.judged = notes
	if data.o2jam then
		data.judged = notes + rv:GetValue("RadarCategory_Holds")
		data.maxEx = 100000
		data.total = nil
	end
	local len = steps:GetLengthSeconds()
	if not len or len <= 0 then
		len = song:MusicLengthSeconds()
	end
	data.length = math.floor(len / rate)
	local bpms = steps:GetDisplayBpms()
	-- the display BPMs already have the music rate in them
	data.minBpm = math.floor(bpms[1] + 0.5)
	data.maxBpm = math.floor(bpms[2] + 0.5)

	-- scores: lamps and best values from plays at 1.0x or faster like the
	-- result screen, play counts and the local ranking from every play
	local all = {}
	local rates = SCOREMAN:GetScoresByKey(steps:GetChartKey())
	if rates then
		for _, hsl in pairs(rates) do
			for _, s in ipairs(hsl:GetScores()) do
				all[#all + 1] = s
			end
		end
	end
	data.plays = #all
	data.clears = 0
	data.lamp = 0
	for _, s in ipairs(all) do
		if s:GetWifeGrade() ~= "Grade_Failed" then
			data.clears = data.clears + 1
		end
		if s:GetMusicRate() > 0.999 then
			local ex = exScore(s)
			if data.best == nil or ex > data.bestEx then
				data.best = s
				data.bestEx = ex
			end
			local m = missCount(s)
			if data.minMiss == nil or m < data.minMiss then
				data.minMiss = m
				data.minCB = comboBreaks(s)
			end
			data.maxCombo = math.max(data.maxCombo or 0, s:GetMaxCombo())
			data.lamp = math.max(data.lamp, getBMSLampFrame(s))
		end
	end
	if data.best and data.o2jam then
		data.bestCounts = judgeCounts(data.best)
		data.grade = getO2JamGrade(data.bestEx / 1000)
	elseif data.best then
		data.bestCounts = judgeCounts(data.best)
		data.dj = djLevel(data.bestEx, data.maxEx)
		data.nextEx = data.dj == 1 and data.maxEx or djBorder(data.dj - 1, data.maxEx)
	end

	table.sort(all, function(a, b)
		local ea, eb = exScore(a), exScore(b)
		if ea ~= eb then
			return ea > eb
		end
		return a:GetDate() < b:GetDate()
	end)
	data.ranking = all
	local latest, latestPos
	for i, s in ipairs(all) do
		if latest == nil or s:GetDate() > latest:GetDate() then
			latest = s
			latestPos = i
		end
	end
	data.latestPos = latestPos
end

-- FAST/SLOW of the best play from its replay, on the LR2 windows it was
-- played on. Missed notes count as slow like beatoraja, PGREATs not at all.
local function readReplay()
	data.fast, data.slow = nil, nil
	local s = data.best
	if not s then
		return
	end
	local key = s:GetScoreKey()
	local hit = key and replayCache[key]
	if hit then
		data.fast, data.slow = hit.fast, hit.slow
		return
	end
	-- a play without replay data is remembered too
	if key then
		replayCache[key] = {}
	end
	local replay = s:GetReplay()
	if not replay then
		return
	end
	replay:LoadAllData()
	local offsets = replay:GetOffsetVector()
	if not offsets or #offsets == 0 then
		return
	end
	local types = replay:GetTapNoteTypeVector() or {}
	local windows = getBMSWindowsMs(getBMSJudgeRankIndexFromScore(s))
	-- O2Jam windows follow the bpm of each note
	local rows, td
	if data.o2jam and data.steps then
		rows = replay:GetNoteRowVector() or {}
		td = data.steps:GetTimingData()
	end
	local fast, slow = 0, 0
	for i, o in ipairs(offsets) do
		local ty = types[i]
		if rows and rows[i] then
			windows = getO2JamWindowsMs(td:GetBPMAtBeat(rows[i] / 48), s:GetMusicRate())
		end
		if ty == nil or ty == "TapNoteType_Tap" or ty == "TapNoteType_HoldHead" or ty == "TapNoteType_Lift" then
			local a = math.abs(o)
			if a > windows[1] then
				if a > windows[4] or o > 0 then
					slow = slow + 1
				else
					fast = fast + 1
				end
			end
		end
	end
	data.fast, data.slow = fast, slow
	if key then
		replayCache[key] = {fast = fast, slow = slow}
	end
end

-- notes per second for the graph and the densities, the BPM at every second
local function readDensity()
	data.density = nil
	data.bpmLine = nil
	local steps = data.steps
	if not steps then
		return
	end
	local rate = data.rate or 1
	local key = steps:GetChartKey() .. "@" .. string.format("%.3f", rate)
	local hit = densityCache[key]
	if hit then
		if hit.density then
			data.density = hit.density
			data.peak, data.average, data.endDensity = hit.peak, hit.average, hit.endDensity
			data.mainBpm, data.bpmLine = hit.mainBpm, hit.bpmLine
		end
		return
	end
	densityCache[key] = {}
	local all = steps:GetCDGraphVectors(rate)
	if not all or not all[1] or #all[1] == 0 then
		return
	end
	local nps = all[1]
	local longs = steps:GetCDGraphVectors(rate, "TapNoteType_HoldHead") or {}
	local mines = steps:GetCDGraphVectors(rate, "TapNoteType_Mine") or {}
	local n = #nps
	local peak, sum = 0, 0
	for i = 1, n do
		peak = math.max(peak, nps[i])
		sum = sum + nps[i]
	end
	-- the chart's first second with notes to its end
	local first = 1
	while first < n and nps[first] == 0 do
		first = first + 1
	end
	local seconds = math.max(n - first + 1, 1)
	local endLen = math.max(math.floor(seconds / 10), math.min(5, seconds))
	local endSum = 0
	for i = n - endLen + 1, n do
		endSum = endSum + nps[i]
	end
	data.density = {nps = nps, longs = longs, mines = mines, first = first}
	data.peak = peak
	data.average = sum / seconds
	data.endDensity = endSum / endLen

	-- main BPM: the one the chart spends the most time at
	local td = steps:GetTimingData()
	local time = {}
	local line = {}
	for i = 1, n do
		local t = (i - 0.5) * rate
		local bpm = td:GetBPMAtBeat(td:GetBeatFromElapsedTime(t)) * rate
		line[i] = bpm
		local b = math.floor(bpm + 0.5)
		if i >= first then
			time[b] = (time[b] or 0) + 1
		end
	end
	local mainBpm, most = nil, -1
	for b, c in pairs(time) do
		if c > most then
			mainBpm, most = b, c
		end
	end
	data.mainBpm = mainBpm
	data.bpmLine = line
	densityCache[key] = {
		density = data.density, peak = data.peak, average = data.average,
		endDensity = data.endDensity, mainBpm = mainBpm, bpmLine = line,
	}
end

-- how hard the chart is to EASY clear and HARD clear, on the scale of the
-- chart's table: sl, st, oj or insane ★ (Scripts/BMSClearCalc.lua). Waits for the wheel like the densities.
local function readClearDifficulty()
	data.easyClear, data.hardClear, data.clearPrefix, data.hardPrefix = nil, nil, nil, nil
	if not data.steps or data.o2jam or not getBMSClearDifficulty then
		return
	end
	local ok, e, _, h, pe, ph = pcall(getBMSClearDifficulty, data.steps, data.rate or 1)
	if ok then
		data.easyClear, data.hardClear, data.clearPrefix, data.hardPrefix = e, h, pe, ph or pe
	end
end

---------------------------------------------------------------------------
-- Res Extensa mono layout, in the same 1920x1080 space as the ECFN one
-- (scaled to the screen height and centered). The left panel runs from x 48
-- to 900, the wheel from 960 to the right edge (metrics.ini).
---------------------------------------------------------------------------

-- three columns: the chart's card on the left, the player's options and best
-- score in the middle, the wheel on the right (x 1264 to 1904, metrics.ini)
local L, R = 48, 600
local RL, RR = 680, 1200

-- the chart under the wheel as a string (song folder and chart key)
local function currentChartId()
	local song = GAMESTATE:GetCurrentSong()
	local steps = GAMESTATE:GetCurrentSteps()
	return (song and song:GetSongDir() or "") .. "|" .. (steps and steps:GetChartKey() or "")
end

-- a wheel move changes the song and the steps, both messages come in the
-- same frame: the chart is read once for them
local function queueChart(self)
	if not self.chartQueued then
		self.chartQueued = true
		self:queuecommand("Chart")
	end
end
local PW = R - L

local function songOnly(get)
	return function()
		if data.song then
			return get()
		end
		return nil
	end
end
local function stepsOnly(get)
	return function()
		if data.steps then
			return get()
		end
		return nil
	end
end
local function noTab()
	return getTabIndex() ~= 0
end
local function fmtInt(v)
	if v == nil then
		return nil
	end
	return tostring(math.floor(v + 0.5))
end

local t = Def.ActorFrame {
	Name = "RXSelect",
	BeginCommand = function(self)
		queueChart(self)
		self:queuecommand("Picture")
		self:GetChild("HeavyTimer"):playcommand("Wait")
	end,
	CurrentSongChangedMessageCommand = function(self)
		queueChart(self)
	end,
	CurrentStepsChangedMessageCommand = function(self)
		queueChart(self)
	end,
	CurrentRateChangedMessageCommand = function(self)
		self:queuecommand("Heavy")
	end,
	DelayedChartUpdateMessageCommand = function(self)
		self:GetChild("HeavyTimer"):playcommand("Wait")
	end,
	BMSChartTablesMessageCommand = function(self)
		self:playcommand("Refresh")
	end,
	BMSOptionChangedMessageCommand = function(self, params)
		-- another mode reads the chart again (rules, scores)
		if params and params.kind == "PlayMode" then
			self:playcommand("Heavy")
			return
		end
		self:playcommand("Refresh")
	end,
	BMSClearScaleChangedMessageCommand = function(self)
		readClearDifficulty()
		self:playcommand("Refresh")
	end,
	ChartCommand = function(self)
		self.chartQueued = false
		readChart()
		data.density = nil
		self:playcommand("Refresh")
		self:playcommand("Graph")
	end,
	HeavyCommand = function(self)
		readChart()
		if rxRequestChartTables then
			rxRequestChartTables(data.steps)
		end
		readDensity()
		readReplay()
		readClearDifficulty()
		self:playcommand("Refresh")
		self:playcommand("Graph")
		self:playcommand("Picture")
	end,
	Def.Actor {
		Name = "HeavyTimer",
		WaitCommand = function(self)
			self.chart = currentChartId()
			self:stoptweening():sleep(0.08):queuecommand("Go")
		end,
		GoCommand = function(self)
			if currentChartId() ~= self.chart then
				return
			end
			self:GetParent():playcommand("Heavy")
		end,
	},
}

-- the wheel's scroll position: a 1px rail at the right edge and its thumb
do
	local top, h = 80, 820
	-- only an ActorFrame has an update function: the frame moves its thumb
	local f = Def.ActorFrame {
		InitCommand = function(self)
			self:xy((SCREEN_WIDTH - W * scale) / 2, 0):zoom(scale)
			self:SetUpdateFunction(function(af)
				local scr = SCREENMAN:GetTopScreen()
				local wheel = scr and scr.GetMusicWheel and scr:GetMusicWheel()
				local thumb = af:GetChild("Thumb")
				if not wheel or not thumb then
					return
				end
				local n = wheel:GetNumItems()
				local pos = n > 1 and wheel:GetCurrentIndex() / (n - 1) or 0
				thumb:y(top + (h - 48) * math.max(0, math.min(1, pos)))
			end)
			self:SetUpdateFunctionInterval(0.05)
		end,
	}
	f[#f + 1] = rxVLine(1912, top, h, rxColor("white", 0.1))
	f[#f + 1] = Def.Quad {
		Name = "Thumb",
		InitCommand = function(self)
			self:halign(0):valign(0):xy(1911, top):zoomto(3, 48):diffuse(rxColor("muted"))
		end,
	}
	t[#t + 1] = f
end

local tabWindows
-- the Til Death tab panels slide in over the left panel on a near-opaque
-- backdrop in the site's ground color
do
	local wide = SCREEN_WIDTH * 0.56
	local narrow = capWideScale(360, 400)
	local top, bottom = 41, SCREEN_HEIGHT - 82
	local widths = {
		[2] = wide, -- Scores
		[10] = narrow, -- Ranking
	}
	local f = Def.ActorFrame {
		BeginCommand = function(self)
			self:playcommand("Place")
		end,
		TabChangedMessageCommand = function(self)
			self:playcommand("Place")
		end,
	}
	f[#f + 1] = Def.Quad {
		InitCommand = function(self)
			self:visible(false):halign(0):valign(0)
		end,
		PlaceCommand = function(self)
			local w = widths[getTabIndex()]
			if w then
				self:stoptweening():visible(true):zoomto(w, bottom - top):xy(10 - 500, top)
				self:diffuse(rxColor("bg", 0)):bouncebegin(0.2):x(10):diffusealpha(0.96)
			elseif self:GetVisible() then
				self:stoptweening():bouncebegin(0.2):addx(-500):diffusealpha(0)
				self:sleep(0.04):queuecommand("Hide")
			end
		end,
		HideCommand = function(self)
			self:visible(false)
		end,
	}
	tabWindows = f
end

local p = Def.ActorFrame {
	Name = "Panels",
	InitCommand = function(self)
		self:xy((SCREEN_WIDTH - W * scale) / 2, 0):zoom(scale)
	end,
	BeginCommand = function(self)
		self.preview = false
		self:visible(true)
	end,
	ChartPreviewOnMessageCommand = function(self)
		self.preview = true
		self:visible(false)
	end,
	ChartPreviewOffMessageCommand = function(self)
		self.preview = false
		self:visible(true)
	end,
	-- a tab window (Profile, Goals, Ranking...) hides the panels so its
	-- rows don't sit over the song's text; the search tab types in the top bar
	TabChangedMessageCommand = function(self)
		local i = getTabIndex()
		self:visible(not self.preview and (i == 0 or i == 3))
	end,
}
t[#t + 1] = p

-- glass cards behind the chart facts and the best score, over the song's
-- picture (the underlay draws it)
local function card(x, y, w, h)
	p[#p + 1] = rxBox(x, y, w, h, rxColor("bg", 0.6))
	p[#p + 1] = rxBox(x, y, w, 1, rxColor("white", 0.1))
	p[#p + 1] = rxBox(x, y + h - 1, w, 1, rxColor("white", 0.1))
	p[#p + 1] = rxBox(x, y, 1, h, rxColor("white", 0.1))
	p[#p + 1] = rxBox(x + w - 1, y, 1, h, rxColor("white", 0.1))
end
card(L - 20, 312, PW + 40, 236)
card(RL - 20, 312, RR - RL + 40, 330)

---------------------------------------------------------------------------
-- header: level and genre, the title big, subtitle, artist (the folder is in
-- the wheel). The
-- song's picture is the screen's background now; a click here still opens
-- the chart preview.
---------------------------------------------------------------------------

-- the music rate, only when it is not 1.0x
p[#p + 1] = rxText(rxFont.semibold, R, 104, 17, 1, 120, function()
	if data.rate and math.abs(data.rate - 1) > 0.001 then
		return getRateString(notShit.round(data.rate, 3))
	end
	return nil
end, rxColor("slow"))
-- the tables the chart is in, from the ranking site (rxChartTables), in the
-- level's accent; until the site answers, the table of the chart's pack
p[#p + 1] = rxText(rxFont.semibold, L, 104, 20, 0, PW - 130, stepsOnly(function()
	return rxChartTablesText and rxChartTablesText(data.steps, data.song) or nil
end), rxColor("muted"))
p[#p + 1] = rxText(rxFont.normal, L, 146, 18, 0, PW, songOnly(function()
	return string.upper(data.song:GetGenre() or "")
end), rxColor("muted"))
p[#p + 1] = rxText(rxFont.bold, L, 204, 42, 0, PW, songOnly(function()
	return (data.song:GetDisplayMainTitle():gsub("[\r\n]+", " "))
end), rxColor("white"))
p[#p + 1] = rxText(rxFont.normal, L, 248, 20, 0, PW, songOnly(function()
	return data.song:GetDisplaySubTitle()
end), rxColor("muted"))
p[#p + 1] = rxText(rxFont.semibold, L, 282, 22, 0, PW, songOnly(function()
	return data.song:GetDisplayArtist()
end), rxColor("text"))

-- a click on the title types it into the search (overlay/ecfnsearch.lua shows it)
local function searchTitle()
	local song = GAMESTATE:GetCurrentSong()
	if not song then
		return
	end
	local title = (song:GetDisplayMainTitle():gsub("[\r\n]+", " "))
	MESSAGEMAN:Broadcast("SetSearchString", {searchstring = title})
	local top = SCREENMAN:GetTopScreen()
	local wheel = top and top.GetMusicWheel and top:GetMusicWheel()
	if wheel then
		wheel:SongSearch(title)
	end
end
local function togglePreview(event)
	if event == "DeviceButton_left mouse button" then
		MESSAGEMAN:Broadcast("ECFNTogglePreview")
	end
end
-- genre and subtitle/artist rows toggle the preview, the title row searches
p[#p + 1] = rxClick(L, 120, PW, 62, togglePreview, noTab)
p[#p + 1] = rxClick(L, 182, PW, 44, function(event)
	if event == "DeviceButton_left mouse button" then
		searchTitle()
	end
end, noTab)
p[#p + 1] = rxClick(L, 226, PW, 74, togglePreview, noTab)

---------------------------------------------------------------------------
-- facts: BPM, notes, length, total
---------------------------------------------------------------------------

do
	local y0 = 316
	local facts = {
		{"BPM", stepsOnly(function()
			if data.minBpm and data.minBpm ~= data.maxBpm then
				return data.minBpm .. "–" .. data.maxBpm
			end
			return fmtInt(data.maxBpm)
		end)},
		{"NOTES", stepsOnly(function() return fmtInt(data.judged) end)},
		{"TIME", stepsOnly(function()
			return data.length and string.format("%d:%02d", math.floor(data.length / 60), data.length % 60)
		end)},
		{"TOTAL", stepsOnly(function() return data.total and fmtInt(data.total) or "–" end)},
	}
	local cw = PW / #facts
	for i, f in ipairs(facts) do
		local x = L + (i - 1) * cw
		p[#p + 1] = rxText(rxFont.semibold, x, y0 + 34, 28, 0, cw - 12, f[2], rxColor("white"))
		p[#p + 1] = rxLabel(rxFont.normal, x, y0 + 62, 13, 0, f[1], rxColor("muted"))
	end
end

---------------------------------------------------------------------------
-- notes per second (long notes and mines stacked, the BPM line) with the
-- clear difficulty next to its label
---------------------------------------------------------------------------

do
	local gx, gy, gw, gh = L, 474, PW, 52
	p[#p + 1] = rxHLine(L, 392, PW, rxColor("white", 0.08))
	p[#p + 1] = rxHLine(gx, gy + gh, gw, rxColor("line2"))
	local noteColor = rxColor("text", 0.7)
	local longColor = rxColor("dim")
	local mineColor = rxColor("pr")
	local bpmColor = rxColor("exhard")
	local graph = rxQuads(gx, gy, "Graph", function(v)
		local d = data.density
		if not d then
			return
		end
		local n = #d.nps
		local bars = math.min(n, 160)
		local bw = gw / bars
		local sums, cnt = {}, {}
		for i = 1, bars do
			sums[i] = {0, 0, 0}
			cnt[i] = 0
		end
		for i = 1, n do
			local b = math.min(bars, math.floor((i - 1) / n * bars) + 1)
			local long = d.longs[i] or 0
			sums[b][1] = sums[b][1] + d.nps[i] - long
			sums[b][2] = sums[b][2] + long
			sums[b][3] = sums[b][3] + (d.mines[i] or 0)
			cnt[b] = cnt[b] + 1
		end
		local top = math.max(data.peak, 10)
		local cols = {noteColor, longColor, mineColor}
		for i = 1, bars do
			local y = gh
			for j = 1, 3 do
				local h = sums[i][j] / math.max(cnt[i], 1) / top * gh
				if h > 0 then
					rxQuad(v, (i - 1) * bw, y - h, i * bw - 1, y, cols[j])
					y = y - h
				end
			end
		end
		local line = data.bpmLine
		if line and data.minBpm and data.maxBpm and data.maxBpm > data.minBpm then
			local lo, hi = math.huge, -math.huge
			for i = 1, n do
				lo = math.min(lo, line[i])
				hi = math.max(hi, line[i])
			end
			if hi > lo then
				for i = 1, n do
					local r = (line[i] - lo) / (hi - lo)
					local y = gh * (0.9 - 0.8 * r)
					rxQuad(v, (i - 1) / n * gw, y - 1, i / n * gw, y + 1, bpmColor)
				end
			end
		end
	end)
	graph.RefreshCommand = function(self)
		if not data.density then
			self:visible(false)
		end
	end
	p[#p + 1] = graph

	-- the clear difficulty, right of the label. Click for another table's
	-- scale: left forward, right back
	local function stars(v, prefix)
		if v == nil then
			return "–"
		end
		return (prefix or "") .. string.format("%.1f", math.max(v, -9.9))
	end
	-- good enough rating: the level the chart is to EASY and to HARD clear,
	-- big, the HARD one in red
	local half = PW / 2
	p[#p + 1] = rxText(rxFont.bold, L, 426, 40, 0, half - 16, stepsOnly(function()
		if data.o2jam then
			return nil
		end
		return stars(data.easyClear, data.clearPrefix)
	end), rxColor("easy"))
	p[#p + 1] = rxText(rxFont.normal, L, 456, 13, 0, half - 16, stepsOnly(function()
		return not data.o2jam and "EASY CLEAR" or nil
	end), rxColor("muted"))
	p[#p + 1] = rxText(rxFont.bold, L + half, 426, 40, 0, half - 16, stepsOnly(function()
		if data.o2jam then
			return nil
		end
		return stars(data.hardClear, data.hardPrefix)
	end), rxColor("#ff4545"))
	p[#p + 1] = rxText(rxFont.normal, L + half, 456, 13, 0, half - 16, stepsOnly(function()
		return not data.o2jam and "HARD CLEAR" or nil
	end), rxColor("muted"))
	p[#p + 1] = rxText(rxFont.normal, R, 456, 12, 1, 200, stepsOnly(function()
		return not data.o2jam and "good enough rating" or nil
	end), rxColor("dim"))
	local scaleNames = {insane = "insane (sp)", satellite = "Satellite (sl)", stella = "Stella (st)", overjoy = "Overjoy (oj)"}
	p[#p + 1] = rxClick(L, 396, PW, 70, function(event)
		local dir
		if event == "DeviceButton_left mouse button" then
			dir = 1
		elseif event == "DeviceButton_right mouse button" then
			dir = -1
		end
		if not dir or not cycleBMSClearScale or not data.steps or data.o2jam then
			return
		end
		local s = cycleBMSClearScale(dir)
		SCREENMAN:SystemMessage("Clear ratings on " .. (s and scaleNames[s] or "the chart's own table") .. " scale")
		MESSAGEMAN:Broadcast("BMSClearScaleChanged")
	end, noTab)
end

---------------------------------------------------------------------------
-- 7k options as one quiet row: lanes, gauge, gauge auto shift, judge rank.
-- Left click forward, right back, middle click on the lanes asks for a
-- custom order.
---------------------------------------------------------------------------

do
	local y0 = 104
	local options = {
		{
			label = THEME:GetString("GeneralInfo", "ProfileArrange"),
			value = getBMSArrangeText,
			click = function(event)
				if event == "DeviceButton_left mouse button" then
					changeBMSOption("Arrange", 1)
				elseif event == "DeviceButton_right mouse button" then
					changeBMSOption("Arrange", -1)
				elseif event == "DeviceButton_middle mouse button" then
					editBMSLanes()
					return
				else
					return
				end
				if isBMSCustomArrange() then
					editBMSLanes()
				end
			end,
		},
		{
			-- O2Jam plays on the O2Jam hard gauge, its cell picks FLN / SLN
			label = function()
				if data.o2jam then
					return "LN"
				end
				return THEME:GetString("GeneralInfo", "ProfileGauge")
			end,
			value = function()
				if data.o2jam then
					return getBMSOptionName("LNMod")
				end
				return getBMSOptionName("Gauge")
			end,
			click = function(event)
				local kind = data.o2jam and "LNMod" or "Gauge"
				if event == "DeviceButton_left mouse button" then
					changeBMSOption(kind, 1)
				elseif event == "DeviceButton_right mouse button" then
					changeBMSOption(kind, -1)
				end
			end,
		},
		{
			-- O2Jam has no auto shift, its cell sets the FLN gap / SLN length
			label = function()
				if data.o2jam then
					return "LN " .. getBMSLNValueLabel()
				end
				return THEME:GetString("GeneralInfo", "ProfileAutoShift")
			end,
			value = function()
				if data.o2jam then
					return getBMSLNValueText()
				end
				return getBMSAutoShiftText()
			end,
			click = function(event)
				if data.o2jam then
					if event == "DeviceButton_left mouse button" then
						changeBMSLNValue(1)
					elseif event == "DeviceButton_right mouse button" then
						changeBMSLNValue(-1)
					end
					return
				end
				if event == "DeviceButton_left mouse button" or event == "DeviceButton_right mouse button" then
					toggleBMSAutoShift()
				end
			end,
		},
		{
			label = "Judge",
			value = function()
				if not data.steps then
					return nil
				end
				if data.o2jam then
					return "O2Jam"
				end
				return getBMSJudgeRankName()
			end,
			click = function(event)
				if event == "DeviceButton_left mouse button" then
					changeBMSOption("JudgeRank", 1)
				elseif event == "DeviceButton_right mouse button" then
					changeBMSOption("JudgeRank", -1)
				end
			end,
		},
	}
	-- a 2x2 grid in the right column, over the best score
	local cw = (RR - RL) / 2
	for i, o in ipairs(options) do
		local x = RL + ((i - 1) % 2) * cw
		local y0 = y0 + math.floor((i - 1) / 2) * 92
		if type(o.label) == "function" then
			p[#p + 1] = rxText(rxFont.normal, x, y0 + 14, 13, 0, cw - 16, function()
				return string.upper(o.label())
			end, rxColor("muted"))
		else
			p[#p + 1] = rxLabel(rxFont.normal, x, y0 + 14, 13, 0, string.upper(o.label), rxColor("muted"), cw - 16)
		end
		p[#p + 1] = rxText(rxFont.semibold, x, y0 + 44, 26, 0, cw - 16, function()
			return o.value()
		end, rxColor("text"))
		p[#p + 1] = rxClick(x, y0, cw - 8, 70, o.click, noTab)
	end
	-- the play mode, one line under the grid: BMS or O2Jam rules, Auto lets
	-- the chart decide
	local my = y0 + 184
	p[#p + 1] = rxLabel(rxFont.normal, RL, my, 13, 0, "MODE", rxColor("muted"), 80)
	p[#p + 1] = rxText(rxFont.semibold, RL + 80, my, 20, 0, RR - RL - 96, function()
		if not data.steps then
			return nil
		end
		return getBMSPlayModeText(data.steps)
	end, rxColor("text"))
	p[#p + 1] = rxClick(RL, my - 14, RR - RL - 8, 28, function(event)
		if event == "DeviceButton_left mouse button" then
			changeBMSOption("PlayMode", 1)
		elseif event == "DeviceButton_right mouse button" then
			changeBMSOption("PlayMode", -1)
		end
	end, noTab)
end

---------------------------------------------------------------------------
-- best score: lamp and DJ level, the EX score with its rate, the DJ level
-- bar, and one line of counts. A chart never played shows only NO PLAY.
---------------------------------------------------------------------------

do
	local y0 = 328
	-- the right column
	local L, R = RL, RR
	local PW = R - L
	p[#p + 1] = rxLampChip(L, y0, 150, 28, 15, function()
		if not data.steps then
			return nil
		end
		return data.lamp or 0
	end)
	-- DJ level (O2Jam grade) and the way to the next one
	p[#p + 1] = rxText(rxFont.bold, L + 172, y0 + 14, 30, 0, 120, function()
		if data.o2jam then
			return data.grade
		end
		local names = {"AAA", "AA", "A", "B", "C", "D", "E", "F"}
		return data.dj and names[data.dj] or nil
	end, function()
		if data.o2jam and data.grade then
			return getO2JamGradeColor(data.grade)
		end
		return rxColor("white")
	end)

	-- EX rate big (DMJam score on O2Jam), the EX score beside it
	p[#p + 1] = rxText(rxFont.large, L, y0 + 84, 56, 0, 260, function()
		if not data.bestEx then
			return nil
		end
		if data.o2jam then
			return string.format("%.3f", data.bestEx / 1000)
		end
		return string.format("%.2f%%", math.max(data.bestEx, 0) / data.maxEx * 100)
	end, rxColor("white"))
	p[#p + 1] = rxText(rxFont.normal, L + 280, y0 + 76, 22, 0, 200, function()
		if not data.bestEx or data.o2jam then
			return nil
		end
		return tostring(data.bestEx)
	end, rxColor("text"))
	p[#p + 1] = rxText(rxFont.normal, L + 280, y0 + 100, 15, 0, 300, function()
		if not data.dj or data.o2jam or not data.bestEx then
			return nil
		end
		local names = {"AAA", "AA", "A", "B", "C", "D", "E", "F"}
		local diff = data.bestEx - data.nextEx
		if data.dj == 1 then
			return string.format("MAX %+d", diff)
		end
		return string.format("%s %+d", names[data.dj - 1] or "", diff)
	end, rxColor("muted"))

	-- the EX score bar with the A, AA and AAA borders
	local by = y0 + 136
	local bw = PW
	p[#p + 1] = Def.ActorFrame {
		RefreshCommand = function(self)
			self:visible(data.bestEx ~= nil and not data.o2jam)
		end,
		rxBox(L, by, bw, 4, rxColor("line")),
		Def.Quad {
			InitCommand = function(self)
				self:halign(0):valign(0):xy(L, by):zoomto(bw, 4):diffuse(rxColor("text"))
			end,
			RefreshCommand = function(self)
				local r = (data.bestEx and not data.o2jam) and math.max(data.bestEx, 0) / data.maxEx or 0
				self:finishtweening():cropright(1 - r)
			end,
		},
		rxBox(L + bw * 6 / 9, by - 3, 1, 10, rxColor("muted")),
		rxBox(L + bw * 7 / 9, by - 3, 1, 10, rxColor("muted")),
		rxBox(L + bw * 8 / 9, by - 3, 1, 10, rxColor("muted")),
	}

	-- one line: miss count, max combo, clears
	p[#p + 1] = rxText(rxFont.normal, L, by + 36, 16, 0, PW, function()
		if not data.bestEx then
			return nil
		end
		local parts = {}
		if data.minMiss then
			parts[#parts + 1] = "miss " .. data.minMiss
		end
		if data.maxCombo then
			parts[#parts + 1] = "combo " .. data.maxCombo .. " / " .. (data.judged or 0)
		end
		parts[#parts + 1] = "clears " .. (data.clears or 0) .. " / " .. (data.plays or 0)
		return table.concat(parts, "     ")
	end, rxColor("muted"))

	-- the best score's judgments: PGREAT GREAT GOOD BAD POOR
	local jn = {"PGREAT", "GREAT", "GOOD", "BAD", "POOR"}
	local jc = {"pg", "gr", "gd", "bd", "pr"}
	local cw = PW / 5
	for i = 1, 5 do
		local x = L + (i - 1) * cw
		p[#p + 1] = rxText(rxFont.semibold, x, by + 82, 14, 0, cw - 8, function()
			return data.bestCounts and jn[i] or nil
		end, rxColor(jc[i]))
		p[#p + 1] = rxText(rxFont.bold, x, by + 112, 28, 0, cw - 8, function()
			return data.bestCounts and tostring(data.bestCounts[i]) or nil
		end, rxColor("white"))
	end
end

-- the tab windows go over the panels
t[#t + 1] = tabWindows

-- Enter in the lane picker: start the song with the picked lanes once the
-- picker has closed
t[#t + 1] = Def.Actor {
	BMSLanesStartMessageCommand = function(self)
		self:stoptweening():sleep(0.1):queuecommand("BMSLanesGo")
	end,
	BMSLanesGoCommand = function(self)
		local top = SCREENMAN:GetTopScreen()
		if top and top:GetName() == "ScreenSelectMusic" and top.SelectCurrent then
			top:SelectCurrent()
		elseif top and top:GetName() == "ScreenBMSLanes" then
			self:sleep(0.05):queuecommand("BMSLanesGo")
		end
	end,
}

return t
