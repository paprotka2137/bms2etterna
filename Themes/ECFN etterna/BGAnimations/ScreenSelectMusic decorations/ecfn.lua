-- 7k song select panels laid out like the beatoraja ECFN skin (select/select.lua).
-- Everything is placed in the skin's 1920x1080 space and scaled to the screen.
-- The skin counts y from the bottom, the numbers here are already the top
-- edges (1080 - y - h). The wheel is the engine's (metrics.ini, Graphics/
-- MusicWheelItem Song NormalPart.lua), the Til Death tabs stay usable and
-- the other tabs slide their windows over the panels.

-- the theme directory comes without the leading slash, and a path without it
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
	data.o2jam = isO2JamSteps(steps)
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
end

---------------------------------------------------------------------------
-- drawing helpers, all of them read `data` on Refresh
---------------------------------------------------------------------------

local function Img(file, x, y, w, h, extra)
	local a = Def.Sprite {
		Texture = dir .. file,
		InitCommand = function(self)
			self:halign(0):valign(0):xy(x, y)
			if w then
				self:zoomto(w, h)
			end
		end,
	}
	if extra then
		for k, v in pairs(extra) do
			a[k] = v
		end
	end
	return a
end

-- bitmap number of `digits` glyphs of gw x gh. get() returns the value or nil.
-- opts.align "right" (default), "left" or "center"; opts.pad "zero" fills the
-- empty places with 0, "dim" with the faded 0 of the sheet (frame 10), which
-- also stands for a missing value. opts.signed uses the 12x2 sign sheet: the
-- first row ends with "-", the second with "+", the sign goes in front.
local function Num(file, x, y, gw, gh, digits, get, opts)
	opts = opts or {}
	local f = Def.ActorFrame {
		InitCommand = function(self)
			self:xy(x, y)
		end,
		RefreshCommand = function(self)
			local value = get()
			local glyphs = {}
			local offset = 0
			if value == nil and opts.signed then
				for i = 1, digits do
					glyphs[i] = false
				end
			elseif value == nil then
				for i = 1, digits do
					glyphs[i] = opts.pad == "dim" and 10 or false
				end
			else
				local row = 0
				local slots = digits
				if opts.signed then
					row = value < 0 and 0 or 12
					slots = digits - 1
				end
				local str = tostring(math.floor(math.abs(value) + 0.5))
				if #str > slots then
					str = str:sub(-slots)
				end
				local used = #str + (opts.signed and 1 or 0)
				local start = 1
				if opts.align == "left" then
					start = 1
				elseif opts.align == "center" then
					offset = (digits - used) * gw / 2
					start = 1
				else
					start = digits - used + 1
				end
				for i = 1, digits do
					if opts.align == "right" or opts.align == nil then
						if i < start then
							if opts.pad == "zero" then
								glyphs[i] = row
							elseif opts.pad == "dim" then
								glyphs[i] = row + 10
							else
								glyphs[i] = false
							end
						end
					else
						glyphs[i] = false
					end
				end
				local p = start
				if opts.signed then
					glyphs[p] = row + 11
					p = p + 1
				end
				for k = 1, #str do
					glyphs[p] = row + tonumber(str:sub(k, k))
					p = p + 1
				end
			end
			for i = 1, digits do
				local d = self:GetChild("d" .. i)
				if glyphs[i] then
					d:visible(true):setstate(glyphs[i]):x(offset + (i - 1) * gw)
				else
					d:visible(false)
				end
			end
		end,
	}
	for i = 1, digits do
		f[#f + 1] = Def.Sprite {
			Name = "d" .. i,
			Texture = dir .. file,
			InitCommand = function(self)
				self:animate(false):halign(0):valign(0):zoomto(gw, gh):visible(false)
			end,
		}
	end
	return f
end

-- text fitted to a height in skin pixels, y is its middle
local function Text(x, y, h, align, maxw, get, c, font)
	return LoadFont(font or "ECFN Normal") .. {
		InitCommand = function(self)
			self:xy(x, y):halign(align):valign(0.5)
			self:settext("Ag")
			local z = h / self:GetHeight() * 1.25
			self:zoom(z)
			if maxw then
				self:maxwidth(maxw / z)
			end
			self:diffuse(c or color("1,1,1,1"))
			self:settext("")
		end,
		RefreshCommand = function(self)
			self:settext(get() or "")
		end,
	}
end

local function Box(x, y, w, h, c)
	return Def.Quad {
		InitCommand = function(self)
			self:halign(0):valign(0):xy(x, y):zoomto(w, h):diffuse(c)
		end,
	}
end

local function quad(verts, x1, y1, x2, y2, c)
	verts[#verts + 1] = {{x1, y1, 0}, c}
	verts[#verts + 1] = {{x2, y1, 0}, c}
	verts[#verts + 1] = {{x2, y2, 0}, c}
	verts[#verts + 1] = {{x1, y2, 0}, c}
end

-- quads rebuilt by build(verts) on the given command
local function Quads(x, y, cmd, build)
	local a = Def.ActorMultiVertex {
		InitCommand = function(self)
			self:xy(x, y)
		end,
	}
	a[cmd .. "Command"] = function(self)
		local verts = {}
		build(verts)
		if #verts == 0 then
			self:visible(false)
			return
		end
		self:visible(true)
		self:SetVertices(verts)
		self:SetDrawState {Mode = "DrawMode_Quads", First = 1, Num = #verts}
	end
	return a
end

-- a clickable area for the 7k options
local function Click(x, y, w, h, onClick)
	return UIElements.QuadButton(1, 1) .. {
		InitCommand = function(self)
			self:halign(0):valign(0):xy(x, y):zoomto(w, h):diffusealpha(0)
		end,
		MouseDownCommand = function(self, params)
			-- not through a tab window lying over it
			if getTabIndex() == 0 then
				onClick(params.event)
			end
		end,
	}
end

---------------------------------------------------------------------------
-- layout
---------------------------------------------------------------------------

local t = Def.ActorFrame {
	Name = "ECFNSelect",
	BeginCommand = function(self)
		self:queuecommand("Chart")
	end,
	CurrentSongChangedMessageCommand = function(self)
		self:queuecommand("Chart")
	end,
	CurrentStepsChangedMessageCommand = function(self)
		self:queuecommand("Chart")
	end,
	CurrentRateChangedMessageCommand = function(self)
		self:queuecommand("Heavy")
	end,
	-- the heavy parts wait for the wheel to stop
	DelayedChartUpdateMessageCommand = function(self)
		self:queuecommand("Heavy")
	end,
	BMSOptionChangedMessageCommand = function(self)
		self:playcommand("Refresh")
	end,
	ChartCommand = function(self)
		readChart()
		-- the densities need to wait for the wheel, until then they are blank
		data.density = nil
		self:playcommand("Refresh")
	end,
	HeavyCommand = function(self)
		readChart()
		readDensity()
		readReplay()
		self:playcommand("Refresh")
		self:playcommand("Graph")
	end,
}

-- the decide screen's pictures, loaded here (never shown) so that screen
-- comes up without waiting for them
do
	local decide = THEME:GetCurrentThemeDirectory()
	if decide:sub(1, 1) ~= "/" then
		decide = "/" .. decide
	end
	decide = decide .. "BGAnimations/ScreenStageInformation decorations/"
	local preload = Def.ActorFrame {
		InitCommand = function(self)
			self:visible(false)
		end,
	}
	for _, f in ipairs({"smoke0 3x5.png", "smoke1 3x5.png", "smoke2 3x5.png", "smoke3 3x5.png", "background.png"}) do
		preload[#preload + 1] = Def.Sprite {Texture = decide .. f}
	end
	t[#t + 1] = preload
end

-- the vignette over the wheel
t[#t + 1] = Def.Sprite {
	Texture = dir .. "shadow.png",
	InitCommand = function(self)
		self:halign(0):valign(0):zoomto(SCREEN_WIDTH, SCREEN_HEIGHT)
	end,
}

-- the wheel's slider, lined up with the wheel (its middle bar at skin y 516)
do
	local slider = Def.ActorFrame {
		InitCommand = function(self)
			self:xy((SCREEN_WIDTH - W * scale) / 2, SCREEN_CENTER_Y - 6 - 516 * scale):zoom(scale)
		end,
	}
	slider[#slider + 1] = Img("song_slider.png", 1855, 129, 65, 764)
	-- the thumb follows the wheel position every frame (only frames have
	-- update functions)
	slider[#slider + 1] = Def.ActorFrame {
		InitCommand = function(self)
			self:SetUpdateFunction(function(a)
				local top = SCREENMAN:GetTopScreen()
				local wheel = top and top.GetMusicWheel and top:GetMusicWheel()
				if not wheel then
					return
				end
				local n = wheel:GetNumItems()
				local pos = n > 1 and wheel:GetCurrentIndex() / (n - 1) or 0
				a:y(522 * math.max(0, math.min(1, pos)))
			end)
		end,
		Img("song_slider_main.png", 1851, 227, 69, 48, {
			InitCommand = function(self)
				self:halign(0):valign(0):xy(1851, 227):zoomto(69, 48):blend("BlendMode_Add")
			end,
		}),
	}
	t[#t + 1] = slider
end

local tabWindows
-- the Til Death tab panels sit on the same backdrop as the Dan window
-- (dan.lua, which draws its own): near-opaque dark blue from under the top
-- bar down to just above the window strip. Their own backgrounds are
-- see-through on 7k (getMainColor "tabs").
do
	local wide = SCREEN_WIDTH * 0.56
	local narrow = capWideScale(360, 400)
	local top, bottom = 41, SCREEN_HEIGHT - 82
	local widths = {
		[2] = wide, -- Scores
		[10] = narrow, -- Ranking (Profile, Goals, Playlists and Dan draw their own)
	}
	local f = Def.ActorFrame {
		BeginCommand = function(self)
			self:playcommand("Place")
		end,
		TabChangedMessageCommand = function(self)
			self:playcommand("Place")
		end,
	}
	-- slides in and out with the Til Death panel on it (bouncebegin 0.2 from
	-- 500 to the left)
	f[#f + 1] = Def.Quad {
		InitCommand = function(self)
			self:visible(false):halign(0):valign(0)
		end,
		PlaceCommand = function(self)
			local w = widths[getTabIndex()]
			if w then
				self:stoptweening():visible(true):zoomto(w, bottom - top):xy(10 - 500, top)
				self:diffuse(color("0.02,0.03,0.06,0")):bouncebegin(0.2):x(10):diffusealpha(0.92)
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

-- the panels, scaled on an inner frame since the screen may move the decorations
local p = Def.ActorFrame {
	Name = "Panels",
	InitCommand = function(self)
		self:xy((SCREEN_WIDTH - W * scale) / 2, shiftY * scale):zoom(scale)
	end,
	-- the chart preview (space, or a click on the stage picture) takes the
	-- left side like in Til Death, the panels hide while it is up
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
	OnCommand = function(self)
		self:xy((SCREEN_WIDTH - W * scale) / 2, shiftY * scale):zoom(scale)
	end,
	-- the tab windows are see-through and slide over these, they stay up
	TabChangedMessageCommand = function(self)
		self:visible(not self.preview)
	end,
}
t[#t + 1] = p

local function songOnly(get)
	return function()
		if data.song then
			return get()
		end
		return nil
	end
end

---------------------------------------------------------------------------
-- BMS data: stage picture, 7KEY header, judge rank, BGA/TXT, NOTES TOTAL TIME
---------------------------------------------------------------------------

p[#p + 1] = Img("line.png", 424, 222, 2, 453)
p[#p + 1] = Img("bms_info.png", 30, 222, 384, 453)

-- stage picture: background, jacket or banner of the song
p[#p + 1] = Def.Sprite {
	RefreshCommand = function(self)
		local song = data.song
		local pic = song and (song:GetBackgroundPath() or song:GetJacketPath() or song:GetBannerPath())
		if pic == self.pic then
			return
		end
		self.pic = pic
		self:finishtweening()
		if pic then
			self:visible(true)
			self:LoadBackground(pic)
			self:scaletofit(30, 279, 30 + 384, 279 + 288)
			self:diffusealpha(0):linear(0.15):diffusealpha(1)
		else
			self:visible(false)
		end
	end,
}
p[#p + 1] = Click(30, 279, 384, 288, function(event)
	if event == "DeviceButton_left mouse button" then
		MESSAGEMAN:Broadcast("ECFNTogglePreview")
	end
end)
p[#p + 1] = Img("7keys_info.png", 30, 222, 384, 57)

-- judge rank, picked here or in the bottom bar
for i = 1, 4 do
	p[#p + 1] = Img("jud_" .. i .. ".png", 223, 573, 78, 22, {
		RefreshCommand = function(self)
			self:visible(getBMSEffectiveJudgeRank() == i and not data.o2jam)
		end,
	})
end
p[#p + 1] = Click(223, 573, 78, 22, function(event)
	if event == "DeviceButton_left mouse button" then
		changeBMSOption("JudgeRank", 1)
	elseif event == "DeviceButton_right mouse button" then
		changeBMSOption("JudgeRank", -1)
	end
end)
p[#p + 1] = Img("bga_ico.png", 305, 573, 44, 22, {
	RefreshCommand = function(self)
		self:diffusealpha(data.bga and 230 / 255 or 60 / 255)
	end,
})
p[#p + 1] = Img("txt_ico.png", 353, 573, 50, 22, {
	RefreshCommand = function(self)
		self:diffusealpha(data.txt and 230 / 255 or 60 / 255)
	end,
})

p[#p + 1] = Img("bms_data_detail.png", 221, 601, 80, 68)
p[#p + 1] = Num("num_data 11x1.png", 320, 603, 18, 18, 2, function()
	return data.length and math.floor(data.length / 60)
end)
p[#p + 1] = Img("time_dot.png", 357, 605, 9, 14)
p[#p + 1] = Num("num_data 11x1.png", 367, 603, 18, 18, 2, function()
	return data.length and data.length % 60
end, {pad = "zero"})
p[#p + 1] = Num("num_data 11x1.png", 331, 626, 18, 18, 4, function()
	return data.total and math.floor(data.total + 0.5)
end, {align = "left"})
p[#p + 1] = Num("num_data 11x1.png", 331, 649, 18, 18, 4, function()
	return data.notes
end, {align = "left"})

-- the 7k options where ECFN has its play buttons: lanes, gauge, gauge auto
-- shift. Left click goes forward, right click back, middle click on the
-- lanes asks for a custom order.
do
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
			label = THEME:GetString("GeneralInfo", "ProfileGauge"),
			value = function()
				-- O2Jam charts always play on the O2Jam hard gauge
				if data.o2jam then
					return "O2Jam Hard"
				end
				return getBMSOptionName("Gauge")
			end,
			click = function(event)
				if event == "DeviceButton_left mouse button" then
					changeBMSOption("Gauge", 1)
				elseif event == "DeviceButton_right mouse button" then
					changeBMSOption("Gauge", -1)
				end
			end,
		},
		{
			label = THEME:GetString("GeneralInfo", "ProfileAutoShift"),
			value = function()
				if data.o2jam then
					return "-"
				end
				return getBMSAutoShiftText()
			end,
			click = function(event)
				if event == "DeviceButton_left mouse button" or event == "DeviceButton_right mouse button" then
					toggleBMSAutoShift()
				end
			end,
		},
	}
	for i, o in ipairs(options) do
		local y = 596 + 26 * (i - 1)
		p[#p + 1] = Text(42, y, 16, 0, 64, function()
			return string.upper(o.label)
		end, color("#9fb8d8"))
		p[#p + 1] = Text(205, y, 16, 1, 92, function()
			return string.upper(o.value())
		end)
		p[#p + 1] = Click(36, y - 12, 172, 24, o.click)
	end
end

---------------------------------------------------------------------------
-- folder, genre, title, subtitle, artist, BPM
---------------------------------------------------------------------------

p[#p + 1] = Text(451, 233, 20, 0, 640, songOnly(function()
	return data.song:GetGroupName() .. " >"
end), color("#ffc040"))
p[#p + 1] = Text(451, 284, 22, 0, 640, songOnly(function()
	return data.song:GetGenre()
end))
p[#p + 1] = Text(451, 338, 38, 0, 680, songOnly(function()
	-- one line, some titles carry line breaks
	return (data.song:GetDisplayMainTitle():gsub("[\r\n]+", " "))
end), nil, "ECFN Large")
p[#p + 1] = Text(451, 382, 22, 0, 640, songOnly(function()
	return data.song:GetDisplaySubTitle()
end))
p[#p + 1] = Text(451, 421, 22, 0, 640, songOnly(function()
	return data.song:GetDisplayArtist()
end))

-- BPM: the lowest and highest, the highest alone when it never changes
p[#p + 1] = Img("bpm.png", 741, 463, 118, 28, {
	RefreshCommand = function(self)
		self:visible(data.maxBpm ~= nil)
	end,
})
p[#p + 1] = Num("num_bpm 10x1.png", 447, 463, 39, 28, 3, function()
	return data.minBpm ~= data.maxBpm and data.minBpm or nil
end)
p[#p + 1] = Img("bpm_bar.png", 577, 473, 23, 10, {
	RefreshCommand = function(self)
		self:visible(data.minBpm ~= nil and data.minBpm ~= data.maxBpm)
	end,
})
p[#p + 1] = Num("num_bpm 10x1.png", 611, 463, 39, 28, 3, function()
	return data.maxBpm
end)
-- the music rate, LR2 has none so it only shows when it is not 1.0x
p[#p + 1] = Text(872, 477, 22, 0, 180, function()
	if data.rate and math.abs(data.rate - 1) > 0.001 then
		return getRateString(notShit.round(data.rate, 3))
	end
	return nil
end, color("#ffb070"))

---------------------------------------------------------------------------
-- MAIN BPM & TOTALNOTES, densities, note counts and the notes graph
---------------------------------------------------------------------------

p[#p + 1] = Img("pattern_info.png", 441, 510, 620, 165, {
	RefreshCommand = function(self)
		self:visible(data.steps ~= nil)
	end,
})
local function stepsOnly(get)
	return function()
		if data.steps then
			return get()
		end
		return nil
	end
end
p[#p + 1] = Num("num_small 11x1.png", 553, 535, 13, 15, 3, stepsOnly(function()
	return data.mainBpm
end))
p[#p + 1] = Num("num_small 11x1.png", 540, 559, 13, 15, 4, stepsOnly(function()
	return data.notes
end))
p[#p + 1] = Num("num_small 11x1.png", 553, 603, 13, 15, 3, stepsOnly(function()
	return data.density and math.floor(data.peak + 0.5)
end))
p[#p + 1] = Num("num_small 11x1.png", 553, 627, 13, 15, 3, stepsOnly(function()
	return data.density and math.floor(data.endDensity + 0.5)
end))
p[#p + 1] = Num("num_small 11x1.png", 553, 651, 13, 15, 3, stepsOnly(function()
	return data.density and math.floor(data.average + 0.5)
end))
-- NOTE LONG SCRATCH BSS MINES, 7k charts have no scratch lane
do
	local counts = {
		function() return data.taps end,
		function() return data.longs end,
		function() return 0 end,
		function() return 0 end,
		function() return data.mines end,
	}
	for i, get in ipairs(counts) do
		p[#p + 1] = Num("num_small 11x1.png", 618 + 91 * (i - 1), 651, 15, 15, 4, stepsOnly(get), {align = "center"})
	end
end

-- notes per second: normal notes, long notes and mines stacked, the BPM line over them
do
	local gx, gy, gw, gh = 606, 516, 448, 106
	local noteColor = color("#d8d8d8")
	local longColor = color("#40e060")
	local mineColor = color("#c050ff")
	local graph = Quads(gx, gy, "Graph", function(v)
		local d = data.density
		if not d then
			return
		end
		local n = #d.nps
		local bars = math.min(n, 224)
		local bw = gw / bars
		local sums = {}
		local cnt = {}
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
					quad(v, (i - 1) * bw, y - h, i * bw - 0.5, y, cols[j])
					y = y - h
				end
			end
		end
		-- BPM changes as a line between 10% and 90% of the height
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
					local x1 = (i - 1) / n * gw
					local x2 = i / n * gw
					quad(v, x1, y - 1, x2, y + 1, color("#ffd040"))
				end
			end
		end
	end)
	-- blank until the wheel stops and the densities are read
	graph.RefreshCommand = function(self)
		if not data.density then
			self:visible(false)
		end
	end
	graph.InitCommand = function(self)
		self:xy(gx, gy):diffusealpha(200 / 255)
	end
	p[#p + 1] = graph
end

---------------------------------------------------------------------------
-- SCORE DATA
---------------------------------------------------------------------------

local function played()
	return data.best ~= nil
end

p[#p + 1] = Img("score_window.png", 30, 819, 584, 183)
p[#p + 1] = Img("score_bar.png", 315, 857, 15, 98)
p[#p + 1] = Img("score_center_bar.png", 453, 853, 1, 101, {
	InitCommand = function(self)
		self:halign(0):valign(0):xy(453, 853):zoomto(1, 101):diffusealpha(140 / 255)
	end,
})
p[#p + 1] = Img("label_score.png", 45, 854, 145, 22)
p[#p + 1] = Img("label_miss.png", 45, 880, 145, 22)
p[#p + 1] = Img("label_combo.png", 45, 906, 145, 22)
p[#p + 1] = Img("label_playcount.png", 45, 932, 145, 22)

local big = "num_big 11x1.png"
p[#p + 1] = Num(big, 203, 853, 26, 24, 4, function() return not data.o2jam and data.bestEx or nil end, {pad = "dim"})
p[#p + 1] = Num(big, 338, 853, 26, 24, 4, function() return data.steps and not data.o2jam and data.maxEx or nil end, {pad = "dim"})
p[#p + 1] = Num(big, 203, 879, 26, 24, 4, function() return data.minMiss end, {pad = "dim"})
p[#p + 1] = Num(big, 338, 879, 26, 24, 4, function() return data.minCB end, {pad = "dim"})
p[#p + 1] = Num(big, 203, 905, 26, 24, 4, function() return data.maxCombo end, {pad = "dim"})
p[#p + 1] = Num(big, 338, 905, 26, 24, 4, function() return data.steps and data.judged end, {pad = "dim"})
p[#p + 1] = Num(big, 203, 931, 26, 24, 4, function() return data.steps and data.clears end, {pad = "dim"})
p[#p + 1] = Num(big, 338, 931, 26, 24, 4, function() return data.steps and data.plays end, {pad = "dim"})

-- clear lamp name, it cycles through the three frames of its row
p[#p + 1] = Def.Sprite {
	Texture = dir .. "state_clear 3x11.png",
	InitCommand = function(self)
		self:animate(false):halign(0):valign(0):xy(475, 914):zoomto(109, 19)
		self.col = 0
		self:queuecommand("Cycle")
	end,
	RefreshCommand = function(self)
		self.row = data.steps and data.lamp or 0
		self:setstate(self.row * 3 + self.col)
	end,
	CycleCommand = function(self)
		self.col = (self.col + 1) % 3
		self:setstate((self.row or 0) * 3 + self.col)
		self:sleep(0.2 / 3):queuecommand("Cycle")
	end,
}

-- DJ level, the next one up and how far it is
p[#p + 1] = Def.Sprite {
	Texture = dir .. "rank_b 1x8.png",
	InitCommand = function(self)
		self:animate(false):halign(0):valign(0):xy(468, 871):zoomto(122, 39)
	end,
	RefreshCommand = function(self)
		self:finishtweening()
		if data.dj then
			self:visible(true):setstate(8 - data.dj)
			self:diffusealpha(0):y(881):linear(0.2):diffusealpha(1):y(871)
		else
			self:visible(false)
		end
	end,
}
p[#p + 1] = Def.Sprite {
	Texture = dir .. "rank_s 1x9.png",
	InitCommand = function(self)
		self:animate(false):halign(0):valign(0):xy(470, 936):zoomto(45, 19)
	end,
	RefreshCommand = function(self)
		if data.dj then
			self:visible(true):setstate(data.dj - 1)
		else
			self:visible(false)
		end
	end,
}
p[#p + 1] = Num("num_sign 12x2.png", 516, 937, 18, 18, 5, function()
	return data.dj and (data.bestEx - data.nextEx)
end, {signed = true, pad = "dim"})
-- O2Jam: the O2Jam grade where the DJ level is
do
	local g = Text(529, 891, 34, 0.5, 120, function()
		return data.o2jam and data.grade or nil
	end)
	g.RefreshCommand = function(self)
		local grade = data.o2jam and data.grade or nil
		self:settext(grade or "")
		if grade then
			self:diffuse(getO2JamGradeColor(grade))
		end
	end
	p[#p + 1] = g
end
p[#p + 1] = Text(529, 946, 13, 0.5, 120, function()
	return data.o2jam and data.steps and "O2JAM" or nil
end, color("#8fd4ff"))

-- score rate
p[#p + 1] = Num("num_rate 11x1.png", 490, 958, 15, 14, 3, function()
	return data.bestEx and math.floor(math.max(data.bestEx, 0) / data.maxEx * 100)
end)
p[#p + 1] = Img("score_per.png", 537, 958, 57, 14, {
	RefreshCommand = function(self)
		self:visible(played())
	end,
})
p[#p + 1] = Num("num_rate 11x1.png", 545, 958, 15, 14, 2, function()
	if not data.bestEx then
		return nil
	end
	local pct = math.max(data.bestEx, 0) / data.maxEx * 100
	return math.floor((pct - math.floor(pct)) * 100)
end, {pad = "zero"})

-- score graph with the DJ level borders on its frame
p[#p + 1] = Img("score_graph_back.png", 60, 968, 381, 16)
p[#p + 1] = Img("score_graph.png", 60, 968, 381, 16, {
	InitCommand = function(self)
		self:halign(0):valign(0):xy(60, 968):zoomto(381, 16):blend("BlendMode_Add"):diffusealpha(60 / 255)
	end,
	RefreshCommand = function(self)
		self:finishtweening()
		local r = data.bestEx and math.max(data.bestEx, 0) / data.maxEx or 0
		-- short tweens: picking a song waits for every tween on the screen
		self:cropright(1):diffusealpha(90 / 255):decelerate(0.15):cropright(1 - r)
	end,
})
p[#p + 1] = Img("score_graph_frame.png", 41, 961, 415, 30)

---------------------------------------------------------------------------
-- PLAY DATA: judgments and FAST/SLOW of the best play
---------------------------------------------------------------------------

p[#p + 1] = Img("playdata_window.png", 614, 819, 281, 183)
do
	local rows = {}
	for k = 1, 5 do
		rows[k] = {top = 850 + 20 * (k - 1), get = function()
			return data.bestCounts and data.bestCounts[k]
		end}
	end
	rows[6] = {top = 954, get = function() return data.fast end}
	rows[7] = {top = 974, get = function() return data.slow end}
	for k, r in ipairs(rows) do
		p[#p + 1] = Num("num_pd 11x1.png", 708, r.top, 17, 17, 4, r.get)
		p[#p + 1] = Img("pd_graph_" .. (k - 1) .. ".png", 786, r.top + 3, 94, 10, {
			RefreshCommand = function(self)
				self:finishtweening()
				local v = r.get()
				local total = 0
				if k <= 5 then
					total = data.judged or 0
				else
					total = (data.fast or 0) + (data.slow or 0)
				end
				local ratio = (v and total > 0) and math.min(1, v / total) or 0
				-- no long glow tween, picking a song waits for every tween on the screen
				self:cropright(1 - ratio):diffusealpha(180 / 255)
			end,
		})
	end
end

---------------------------------------------------------------------------
-- LOCAL DATA in place of the IR window: the five best plays by EX score,
-- where the latest play ranks among all of them and the clear rate
---------------------------------------------------------------------------

p[#p + 1] = Img("irdata_window.png", 895, 819, 261, 183)
-- its "LOCAL DATA" and "LATEST" labels are in the picture, put together from
-- the letters of the skin's own PLAY DATA / SCORE DATA / CLEAR RATE / FAST
for k = 1, 5 do
	local top = 852 + 20 * (k - 1)
	p[#p + 1] = Text(958, top + 7, 14, 0, 93, function()
		local s = data.ranking and data.ranking[k]
		if not s then
			return nil
		end
		local label = s:GetDate():sub(3, 10)
		if math.abs(s:GetMusicRate() - 1) > 0.001 then
			label = label .. " " .. getRateString(notShit.round(s:GetMusicRate(), 3))
		end
		return label
	end, color("1,1,1,0.9"))
	p[#p + 1] = Num("num_pd 11x1.png", 1074, top - 2, 17, 17, 4, function()
		local s = data.ranking and data.ranking[k]
		return s and not data.o2jam and exScore(s) or nil
	end)
	-- O2Jam: the DMJam score
	p[#p + 1] = Text(1142, top + 7, 15, 1, 70, function()
		local s = data.o2jam and data.ranking and data.ranking[k]
		return s and string.format("%.3f", exScore(s) / 1000) or nil
	end)
end
p[#p + 1] = Num("num_pd 11x1.png", 995, 954, 17, 17, 4, function()
	return data.latestPos
end)
p[#p + 1] = Num("num_pd 11x1.png", 1074, 954, 17, 17, 4, function()
	return data.steps and data.plays
end)
p[#p + 1] = Num("num_pd 11x1.png", 1039, 974, 17, 17, 3, function()
	if not data.plays or data.plays == 0 then
		return nil
	end
	return math.floor(data.clears / data.plays * 100)
end)
p[#p + 1] = Num("num_pd 11x1.png", 1095, 974, 17, 17, 2, function()
	if not data.plays or data.plays == 0 then
		return nil
	end
	local pct = data.clears / data.plays * 100
	return math.floor((pct - math.floor(pct)) * 100)
end, {pad = "zero"})

---------------------------------------------------------------------------
-- O2Jam names and numbers over the LR2 ones
---------------------------------------------------------------------------

local function O2Box(x, y, w, h)
	local b = Box(x, y, w, h, color("0.02,0.03,0.07,1"))
	b.RefreshCommand = function(self)
		self:visible(data.o2jam == true)
	end
	return b
end
local function o2Text(x, y, h, align, maxw, get, c)
	return Text(x, y, h, align, maxw, function()
		if data.o2jam then
			return get()
		end
		return nil
	end, c)
end
-- judge rank: O2Jam has its own windows
p[#p + 1] = o2Text(262, 584, 15, 0.5, 76, function() return "O2JAM" end, color("#8fd4ff"))
-- SCORE DATA: DMJam score in place of the EX score
p[#p + 1] = O2Box(42, 850, 400, 28)
p[#p + 1] = o2Text(48, 865, 15, 0, 150, function() return "SCORE" end)
p[#p + 1] = o2Text(306, 865, 19, 1, 150, function()
	return data.bestEx and string.format("%.3f", data.bestEx / 1000) or "-"
end, color("#66ffff"))
p[#p + 1] = o2Text(436, 865, 16, 1, 120, function() return "%" end, color("1,1,1,0.6"))
-- PLAY DATA: COOL, (no GREAT), GOOD, BAD, MISS
do
	local labels = {
		{"COOL", "TapNoteScore_W1"}, {"-", nil}, {"GOOD", "TapNoteScore_W3"},
		{"BAD", "TapNoteScore_W4"}, {"MISS", "TapNoteScore_Miss"},
	}
	for k, l in ipairs(labels) do
		local top = 850 + 20 * (k - 1)
		p[#p + 1] = O2Box(624, top, 78, 18)
		p[#p + 1] = o2Text(628, top + 9, 15, 0, 72, function() return l[1] end,
			l[2] and getBMSJudgeColor(l[2]) or color("1,1,1,0.4"))
	end
end

-- the tab windows go over the panels (the Til Death panels on them are in
-- later decoration files, so they draw on top)
t[#t + 1] = tabWindows

return t
