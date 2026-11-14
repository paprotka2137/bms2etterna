-- 7k result screen laid out like the beatoraja ECFN skin (RESULT/result.lua).
-- Everything is placed in the skin's 1920x1080 space and the whole frame is
-- scaled to the screen. The skin counts y from the bottom, top() converts it.

-- the theme directory comes without the leading slash, and a path without it
-- is taken as relative to this file
local dir = THEME:GetCurrentThemeDirectory()
if dir:sub(1, 1) ~= "/" then
	dir = "/" .. dir
end
dir = dir .. "BGAnimations/ScreenEvaluation decorations/ecfn/"
local W, H = 1920, 1080
local scale = SCREEN_HEIGHT / H

local function top(y, h)
	return H - y - h
end

---------------------------------------------------------------------------
-- score data
---------------------------------------------------------------------------

local pss = STATSMAN:GetCurStageStats():GetPlayerStageStats()
-- the play just finished is on the stage stats, the most recent score is the
-- fallback for replays and old score views
local score = pss:GetHighScore()
if score == nil or score:GetScoreKey() == "" then
	score = SCOREMAN:GetMostRecentScore() or SCOREMAN:GetTempReplayScore()
end
local song = GAMESTATE:GetCurrentSong()
local steps = GAMESTATE:GetCurrentSteps()
local isCurrentPlay = pss:GetHighScore() ~= nil and score:GetScoreKey() == pss:GetHighScore():GetScoreKey()

local function tns(s, x)
	return s:GetTapNoteScore("TapNoteScore_" .. x)
end

-- LR2 judgments of a score: PGREAT GREAT GOOD BAD POOR
local function judgeCounts(s)
	return {tns(s, "W1"), tns(s, "W2"), tns(s, "W3"), tns(s, "W4") + tns(s, "W5"), tns(s, "Miss")}
end

-- O2Jam scores are compared by their DMJam score, kept in thousandths
local function exScore(s)
	if isO2JamScore(s) then
		return math.floor(getO2JamScore(s) * 1000 + 0.5)
	end
	local c = judgeCounts(s)
	return c[1] * 2 + c[2]
end

local function missCount(s)
	return getBMSMissCount(s)
end

-- O2Jam charts play by O2Jam rules: COOL GOOD BAD MISS, DMJam score and
-- O2Jam grade, a long note is judged twice (head and tail)
local o2jam = isO2JamScore(score)

local counts = judgeCounts(score)
local emptyPoors = isCurrentPlay and pss:GetEmptyPoorCount() or score:GetEmptyPoorCount()
local notes = counts[1] + counts[2] + counts[3] + counts[4] + counts[5]
do
	local possible = pss:GetRadarPossible():GetValue("RadarCategory_Notes")
	if o2jam and possible then
		possible = possible + (pss:GetRadarPossible():GetValue("RadarCategory_Holds") or 0)
	end
	if possible and possible > notes then
		notes = possible
	end
end
local maxEx = math.max(notes * 2, 1)
local curEx = exScore(score)
local curMiss = getBMSMissCount(score)

-- DJ levels are ninths of the max EX score: index 1 AAA .. 8 F
local function djLevel(ex)
	local r = ex / maxEx
	for i = 1, 7 do
		if r >= (9 - i) / 9 then
			return i
		end
	end
	return 8
end
local function djBorder(i)
	return math.ceil(maxEx * (9 - i) / 9)
end

local function scoreGaugeName(s)
	local mods = string.lower(s:GetModifiers() or "")
	-- the O2Jam hard gauge is drawn as a survival gauge
	if mods:find("o2jamhard", 1, true) then
		return "Hard"
	end
	-- a dan course song (course gauge) is drawn as the nearest survival
	-- gauge; the course result panel shows the real course gauge
	if mods:find("exhardclassgauge", 1, true) then
		return "ExHard"
	elseif mods:find("classgauge", 1, true) then
		return "Hard"
	elseif mods:find("deathgauge", 1, true) then
		return "Death"
	elseif mods:find("exhardgauge", 1, true) then
		return "ExHard"
	elseif mods:find("hardgauge", 1, true) then
		return "Hard"
	elseif mods:find("easygauge", 1, true) then
		return "Easy"
	end
	return "Groove"
end

-- frame of the ECFN clear lamp sheet:
-- 0 NO PLAY 1 FAILED 4 E-CLEAR 5 CLEAR 6 H-CLEAR 7 EXH-CLEAR 8 F-COMBO 9 PERFECT 10 MAX
local function lampFrame(s)
	if s == nil then
		return 0
	end
	local lamp = getBMSLampFromScore(s)
	if lamp == 6 then
		return 1
	elseif lamp == 1 then
		local c = judgeCounts(s)
		if c[3] + c[4] + c[5] == 0 then
			return c[2] == 0 and 10 or 9
		end
		return 8
	elseif lamp == 2 then
		return 7
	elseif lamp == 3 then
		return 6
	elseif lamp == 4 then
		return 5
	end
	return 4
end

-- the previous best on this chart, from every other score at 1.0x or faster
local best = {ex = nil, miss = nil, lamp = 0, score = nil}
local localScores = {}
do
	local rates = SCOREMAN:GetScoresByKey(steps:GetChartKey())
	if rates then
		for _, hsl in pairs(rates) do
			for _, s in ipairs(hsl:GetScores()) do
				localScores[#localScores + 1] = s
				if s:GetScoreKey() ~= score:GetScoreKey() and s:GetMusicRate() > 0.999 then
					local ex = exScore(s)
					if best.ex == nil or ex > best.ex then
						best.ex = ex
						best.score = s
					end
					local m = missCount(s)
					if lampFrame(s) > 1 and (best.miss == nil or m < best.miss) then
						best.miss = m
					end
					best.lamp = math.max(best.lamp, lampFrame(s))
				end
			end
		end
	end
	local found = false
	for _, s in ipairs(localScores) do
		if s:GetScoreKey() == score:GetScoreKey() then
			found = true
		end
	end
	if not found then
		localScores[#localScores + 1] = score
	end
	table.sort(localScores, function(a, b)
		local ea, eb = exScore(a), exScore(b)
		if ea ~= eb then
			return ea > eb
		end
		return a:GetDate() < b:GetDate()
	end)
end

local curLamp = lampFrame(score)
local cleared = curLamp ~= 1
local curRank = djLevel(curEx)
if o2jam then
	-- O2Jam grade on the DJ level scale, for the background pictures
	local g = getO2JamGrade(getO2JamScore(score))
	curRank = ({P = 1, SS = 1, S = 2, A = 3, B = 4, C = 5, D = 6})[g] or 8
end
local bestRank = best.ex and djLevel(best.ex) or nil
-- target: the AAA border, or MAX once AAA is reached
local targetEx = curRank == 1 and maxEx or djBorder(1)

-- LR2 windows the score was judged on, and fast/slow per judgment from the replay
local judgeRank = getBMSJudgeRankIndexFromScore(score)
local windows = getBMSWindowsMs(judgeRank)
local finalSecond = math.max(steps:GetLastSecond(), 1)
local td = steps:GetTimingData()
-- O2Jam windows follow the bpm: each note by its own, the graphs by the
-- chart's starting bpm
local function o2jamWindowsAt(beat)
	return getO2JamWindowsMs(td:GetBPMAtBeat(beat or 0), score:GetMusicRate())
end
if o2jam then
	windows = o2jamWindowsAt(0)
end
local taps = {} -- {time, offset, judgment 1-5}
local fast = {0, 0, 0, 0, 0, 0}
local slow = {0, 0, 0, 0, 0, 0}
local function offsetJudgment(o, w)
	local a = math.abs(o)
	w = w or windows
	for i = 1, 4 do
		if a <= w[i] then
			return i
		end
	end
	return 5
end
do
	local replay = score:GetReplay()
	replay:LoadAllData()
	local dvt = replay:GetOffsetVector() or {}
	local nrt = replay:GetNoteRowVector() or {}
	local types = replay:GetTapNoteTypeVector() or {}
	for i, o in ipairs(dvt) do
		local ty = types[i]
		if ty == nil or ty == "TapNoteType_Tap" or ty == "TapNoteType_HoldHead" or ty == "TapNoteType_Lift" then
			local j = offsetJudgment(o, o2jam and nrt[i] and o2jamWindowsAt(nrt[i] / 48) or nil)
			local t = nrt[i] and td:GetElapsedTimeFromNoteRow(nrt[i]) or 0
			taps[#taps + 1] = {t, o, j}
			-- missed notes went by, beatoraja counts them as late
			if j == 5 or o > 0 then
				slow[j] = slow[j] + 1
			elseif o < 0 then
				fast[j] = fast[j] + 1
			end
		end
	end
	-- empty POORs are presses before the note
	fast[6] = emptyPoors
end

---------------------------------------------------------------------------
-- drawing helpers
---------------------------------------------------------------------------

local function fadeIn(self, delay, len)
	self:diffusealpha(0):sleep((delay or 0) / 1000):linear((len or 200) / 1000):diffusealpha(1)
end

local function Img(file, x, y, w, h, extra)
	local a = Def.Sprite {
		Texture = dir .. file,
		InitCommand = function(self)
			self:halign(0):valign(0):xy(x, y)
			if w then
				self:zoomto(w, h)
			end
		end,
		OnCommand = function(self)
			fadeIn(self, 0, 200)
		end,
	}
	if extra then
		for k, v in pairs(extra) do
			a[k] = v
		end
	end
	return a
end

-- a frame of a sprite sheet, shown only when visible is true
local function Frame(file, frame, x, y, w, h, visible, delay)
	return Def.Sprite {
		Texture = dir .. file,
		InitCommand = function(self)
			self:animate(false):setstate(frame):halign(0):valign(0):xy(x, y):zoomto(w, h)
			self:visible(visible and true or false)
		end,
		OnCommand = function(self)
			fadeIn(self, delay or 100, 200)
		end,
	}
end

-- bitmap number in the ECFN style: digits glyphs of gw x gh placed from x,
-- right aligned. pad "zero" fills with 0, "dim" with the faded 0 of the sheet
-- (frame 10), signed sheets have the sign as frame 11 in the first place.
local function Num(file, x, y, gw, gh, digits, value, opts)
	opts = opts or {}
	local f = Def.ActorFrame {
		InitCommand = function(self)
			self:xy(x, y)
		end,
		OnCommand = function(self)
			fadeIn(self, opts.delay or 100, 200)
		end,
	}
	if value == nil then
		return f
	end
	local signed = opts.signed
	local n = math.floor(math.abs(value) + 0.5)
	local s = tostring(n)
	local slots = signed and digits - 1 or digits
	if #s > slots then
		s = s:sub(-slots)
	end
	local glyphs = {}
	local first = slots - #s + 1
	for i = 1, slots do
		if i >= first then
			glyphs[i] = tonumber(s:sub(i - first + 1, i - first + 1))
		elseif opts.pad == "zero" then
			glyphs[i] = 0
		elseif opts.pad == "dim" or (opts.pad == nil and not file:find("10x1", 1, true)) then
			glyphs[i] = 10
		else
			glyphs[i] = false
		end
	end
	local col = 0
	if signed then
		local signFrame = 11
		f[#f + 1] = Def.Sprite {
			Texture = dir .. file,
			InitCommand = function(self)
				self:animate(false):setstate(signFrame):halign(0):valign(0):zoomto(gw, gh)
			end,
		}
		col = 1
	end
	for i = 1, slots do
		local g = glyphs[i]
		if g then
			local cx = (col + i - 1) * gw
			f[#f + 1] = Def.Sprite {
				Texture = dir .. file,
				InitCommand = function(self)
					self:animate(false):setstate(g):halign(0):valign(0):x(cx):zoomto(gw, gh)
				end,
			}
		end
	end
	return f
end

-- signed difference, + sheet for positive values and - sheet for negative
local function Diff(posFile, negFile, x, y, gw, gh, digits, value, opts)
	opts = opts or {}
	opts.signed = true
	opts.pad = opts.pad or "dim"
	return Num(value >= 0 and posFile or negFile, x, y, gw, gh, digits, value, opts)
end

-- text fitted to a height in skin pixels
local function Text(x, y, h, align, maxw, text, c, delay)
	return LoadFont("Common Normal") .. {
		InitCommand = function(self)
			self:xy(x, y):halign(align):valign(0.5)
			self:settext(text or "")
			local th = self:GetHeight()
			local z = th > 0 and h / th * 1.25 or 1
			self:zoom(z)
			if maxw then
				self:maxwidth(maxw / z)
			end
			self:diffuse(c or color("1,1,1,1"))
		end,
		OnCommand = function(self)
			local a = (c and c[4]) or 1
			self:diffusealpha(0):sleep((delay or 300) / 1000):linear(0.2):diffusealpha(a)
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

local function Quads(x, y, build, delay)
	return Def.ActorMultiVertex {
		InitCommand = function(self)
			self:xy(x, y)
			local verts = {}
			build(verts)
			self:SetVertices(verts)
			self:SetDrawState {Mode = "DrawMode_Quads", First = 1, Num = #verts}
		end,
		OnCommand = function(self)
			fadeIn(self, delay or 200, 200)
		end,
	}
end

local judgeColors = {
	getBMSJudgeColor("TapNoteScore_W1"),
	getBMSJudgeColor("TapNoteScore_W2"),
	getBMSJudgeColor("TapNoteScore_W3"),
	getBMSJudgeColor("TapNoteScore_W4"),
	getBMSJudgeColor("TapNoteScore_Miss"),
}
local fastColor = color("#5ab4ff")
local slowColor = color("#ffa050")

---------------------------------------------------------------------------
-- layout
---------------------------------------------------------------------------

-- the screen may reposition its decorations frame, so the scaling sits on an
-- inner frame
local t = Def.ActorFrame {
	Name = "ECFNResult",
	InitCommand = function(self)
		self:xy((SCREEN_WIDTH - W * scale) / 2, 0):zoom(scale)
	end,
	OnCommand = function(self)
		self:xy((SCREEN_WIDTH - W * scale) / 2, 0):zoom(scale)
	end,
}

-- background: the skin's clear/failed base, then like ECFN a random picture
-- for A and better clears (BG/AAA, BG/AA, BG/A) or the song background
local function rankPictures(rank)
	local name = ({"AAA", "AA", "A"})[rank]
	if not name then
		return nil
	end
	for _, d in ipairs({dir .. "BG/" .. name .. "/", "/Themes/ECFN/RESULT/BG/" .. name .. "/"}) do
		local files = {}
		for _, f in ipairs(FILEMAN:GetDirListing(d) or {}) do
			local ext = f:match("%.(%w+)$")
			ext = ext and ext:lower()
			if ext == "png" or ext == "jpg" or ext == "jpeg" then
				files[#files + 1] = d .. f
			end
		end
		if #files > 0 then
			return files[math.random(#files)]
		end
	end
	return nil
end

t[#t + 1] = Box(0, 0, W, H, color("0,0,0,1"))

-- the picture is stretched to fill the whole screen (nothing is cut off)
local picture = cleared and rankPictures(curRank) or nil
local songBG = song:GetBackgroundPath()
local function centerPicture(self)
	-- the layout is 1920x1080 zoomed to the screen height, so on wider
	-- screens the frame does not reach the edges: cover those too
	local side = math.max(0, (SCREEN_WIDTH / scale - W) / 2)
	self:stretchto(-side, 0, W + side, H)
end
if picture then
	t[#t + 1] = Def.Sprite {
		InitCommand = function(self)
			self:Load(picture)
			centerPicture(self)
		end,
		OnCommand = function(self)
			self:diffusealpha(0):linear(0.3):diffusealpha(1)
		end,
	}
elseif songBG and PREFSMAN:GetPreference("ShowBackgrounds") then
	t[#t + 1] = Def.Sprite {
		InitCommand = function(self)
			self:LoadBackground(songBG)
			-- song backgrounds are often tiny, those get fitted to the area
			self:scaletofit(600, 256, 1320, 823)
		end,
		OnCommand = function(self)
			self:diffusealpha(0):linear(0.3):diffusealpha(1)
		end,
	}
end

-- top and bottom bars
t[#t + 1] = Img(cleared and "upper.png" or "upper_f.png", 55, 0, 1811, 165, {
	OnCommand = function(self)
		fadeIn(self, 200, 300)
	end,
})
t[#t + 1] = Img(cleared and "stageresult.png" or "stageresult_f.png", 729, 13, 462, 24, {
	OnCommand = function(self)
		fadeIn(self, 200, 300)
	end,
})
t[#t + 1] = Img("under_base.png", 525, 1028, 870, 62, {
	OnCommand = function(self)
		self:diffusealpha(0):sleep(0.2):linear(0.3):diffusealpha(200 / 255)
	end,
})
t[#t + 1] = Img("name_line.png", 534, 1017, 853, 20, {
	OnCommand = function(self)
		self:diffusealpha(0):x(534 + 425):zoomx(0):linear(0.2):diffusealpha(1):x(534):zoomx(1)
	end,
})

---------------------------------------------------------------------------
-- groove gauge graph (top left)
---------------------------------------------------------------------------

local gaugeName = scoreGaugeName(score)
local gx, gy, gw, gh = 41, 71, 519, 259
t[#t + 1] = Img("groove_main.png", 13, 55, 565, 309)

local gaugeOrder = {"Easy", "Groove", "Hard", "ExHard", "Death"}
local gaugeIndex = {Easy = 1, Groove = 2, Hard = 3, ExHard = 4, Death = 5}
local usedGAS = string.lower(score:GetModifiers() or ""):find("gas", 1, true) ~= nil

-- with gauge auto shift the engine's life record follows whichever gauge is
-- shown at the moment, so it saw-tooths between gauges. The graph then shows
-- the gauge the play ended on: the cleared one, or the bottom one (EASY) when
-- every gauge failed, each gauge replayed on its own from the judgments.
local shownGauge = gaugeName
if usedGAS and not cleared then
	shownGauge = "Easy"
end

-- LR2 gauge tables (same as LifeMeterBar.cpp BMS_GAUGES):
-- survival, min, init, border, death, change PG GR GD BD PR, guts below/scale
local gaugeProps = {
	Easy = {false, 2, 20, 80, 0, {1.2, 1.2, 0.6, -3.2, -4.8}, 0, 1},
	Groove = {false, 2, 20, 80, 0, {1.0, 1.0, 0.5, -4.0, -6.0}, 0, 1},
	Hard = {true, 0, 100, 0, 2, {0.1, 0.1, 0.05, -6.0, -10.0}, 32, 0.6},
	ExHard = {true, 0, 100, 0, 2, {0.1, 0.1, 0.05, -12.0, -20.0}, 0, 1},
	Death = {true, 0, 100, 0, 2, {0.15, 0.06, 0, -100.0, -100.0}, 0, 1},
}

-- the O2Jam hard gauge: COOL +0.1, GOOD 0, BAD -0.5, MISS -3, dead at 0 (pills are not
-- in the replay, the recorded gauge graph has them)
if o2jam then
	gaugeProps.Hard = {true, 0, 100, 0, 0, {0.1, 0.1, 0, -0.5, -3}, 0, 1}
end

-- LR2 survival gauge damage multiplier from TOTAL and notes
local function lr2DamageScale(total, n)
	local fix1 = 10 / math.min(10, math.max(1, math.floor(total / 16) - 5))
	local fix2
	if n <= 20 then
		fix2 = 10
	elseif n < 30 then
		fix2 = 8 + 0.2 * (30 - n)
	elseif n < 60 then
		fix2 = 5 + 0.2 * (60 - n) / 3
	elseif n < 125 then
		fix2 = 4 + (125 - n) / 65
	elseif n < 250 then
		fix2 = 3 + 0.008 * (250 - n)
	elseif n < 500 then
		fix2 = 2 + 0.004 * (500 - n)
	elseif n < 1000 then
		fix2 = 1 + 0.002 * (1000 - n)
	else
		fix2 = 1
	end
	return math.max(fix1, fix2)
end

-- replays a gauge over the judgments of the replay, returns samples 0..1.
-- Empty POORs and dropped long notes aren't in the replay, so this can end a
-- bit higher than the real gauge did.
local function simulateGauge(name, samples)
	local p = gaugeProps[name]
	local total = steps:GetBMSTotal() or 0
	if total <= 0 then
		total = 160 + (notes + math.max(0, math.min(200, notes - 400))) * 0.16
	end
	local change = {}
	for j = 1, 5 do
		local f = p[6][j]
		if f > 0 and not p[1] then
			f = f * total / notes
		elseif f < 0 and (name == "Hard" or name == "ExHard") and not o2jam then
			f = f * lr2DamageScale(total, notes)
		end
		change[j] = f
	end
	local order = {}
	for i, tp in ipairs(taps) do
		order[i] = tp
	end
	table.sort(order, function(x, y) return x[1] < y[1] end)
	local out = {}
	local value = p[3]
	local k = 1
	for i = 1, samples do
		local tEnd = (i / samples) * finalSecond
		while k <= #order and order[k][1] <= tEnd do
			if value > 0 or not p[1] then
				local inc = change[order[k][3]]
				if inc < 0 and value < p[7] then
					inc = inc * p[8]
				end
				value = math.max(p[2], math.min(100, value + inc))
				if p[1] and value < p[5] then
					value = 0
				end
			end
			k = k + 1
		end
		out[i] = value / 100
	end
	return out
end

-- beatoraja gauge graph colors
local gaugeBG = {
	Easy = {color("#004444aa"), color("#440000aa")},
	Groove = {color("#004400aa"), color("#440000aa")},
	Hard = {color("#440000aa"), color("#440000aa")},
	ExHard = {color("#444400aa"), color("#444400aa")},
	Death = {color("#444444aa"), color("#444444aa")},
}
local gaugeLine = {
	Easy = {color("#00ffff"), color("#ff0000")},
	Groove = {color("#00ff00"), color("#ff0000")},
	Hard = {color("#ff0000"), color("#ff0000")},
	ExHard = {color("#ffff00"), color("#ffff00")},
	Death = {color("#cccccc"), color("#cccccc")},
}
-- gauges the graph can show, + and - switch between them: with auto shift
-- the ones that ran (the picked one and everything below), else all of them
local viewGauges = {}
if o2jam then
	viewGauges = {"Hard"}
elseif usedGAS then
	for g = 1, gaugeIndex[gaugeName] or 2 do
		viewGauges[#viewGauges + 1] = gaugeOrder[g]
	end
else
	viewGauges = gaugeOrder
end
local viewIndex = 1
for i, name in ipairs(viewGauges) do
	if name == shownGauge then
		viewIndex = i
	end
end

local lifeCache = {}
local function gaugeLife(name, samples)
	if lifeCache[name] then
		return lifeCache[name]
	end
	local life
	-- the engine keeps every gauge that ran on its own (empty POORs and
	-- dropped long notes included), but only for the play that just happened
	local rec = isCurrentPlay and pss.GetBMSGaugeRecord and
		pss:GetBMSGaugeRecord(gaugeIndex[name] - 1, finalSecond / math.max(score:GetMusicRate(), 0.01), samples)
	if rec then
		life = rec
	elseif not usedGAS and name == gaugeName and isCurrentPlay then
		-- the life record is kept in real seconds (chart time / rate)
		local rate = score:GetMusicRate()
		rate = rate > 0 and rate or 1
		life = pss:GetLifeRecord(finalSecond / rate, samples)
		-- the record starts with the engine's default life before the BMS
		-- gauge is set up, so everything before the first judgment takes the
		-- value right after it instead of sloping up from that default
		local firstTap = finalSecond
		for _, tp in ipairs(taps) do
			firstTap = math.min(firstTap, tp[1])
		end
		local firstSample = math.min(samples, math.floor(firstTap / finalSecond * (samples - 1)) + 2)
		for i = 1, firstSample - 1 do
			life[i] = life[firstSample]
		end
	else
		life = simulateGauge(name, samples)
	end
	lifeCache[name] = life
	return life
end

local function buildGaugeGraph(v, name)
	local border = (name == "Easy" or name == "Groove") and 0.8 or 0
	local bg = gaugeBG[name]
	local by = gh * (1 - border)
	quad(v, 0, by, gw, gh, bg[1])
	if border > 0 then
		quad(v, 0, 0, gw, by, bg[2])
		quad(v, 0, by - 1, gw, by + 1, color("#440000aa"))
	end
	local samples = gw
	-- keep a full gauge visible under the frame's top edge
	local function lifeY(l)
		l = math.max(0, math.min(1, l or 0))
		return math.max(2, math.min(gh - 2, gh * (1 - l))), l
	end
	local life = gaugeLife(name, samples)
	local lc = gaugeLine[name]
	for i = 1, samples do
		local y, l = lifeY(life[i])
		local c = l >= border and border > 0 and lc[2] or lc[1]
		local prev = i > 1 and lifeY(life[i - 1]) or y
		quad(v, i - 1, math.min(y, prev) - 1, i, math.max(y, prev) + 1, c)
	end
end

local plusKeys = {["DeviceButton_="] = 1, ["DeviceButton_KP +"] = 1, ["DeviceButton_-"] = -1, ["DeviceButton_KP -"] = -1}
t[#t + 1] = Def.ActorMultiVertex {
	InitCommand = function(self)
		self:xy(gx, gy)
		self:playcommand("Redraw")
	end,
	OnCommand = function(self)
		fadeIn(self, 200, 200)
		if #viewGauges > 1 then
			SCREENMAN:GetTopScreen():AddInputCallback(function(event)
				if event.type ~= "InputEventType_FirstPress" then
					return
				end
				local d = plusKeys[event.DeviceInput.button]
				if d then
					viewIndex = (viewIndex - 1 + d) % #viewGauges + 1
					MESSAGEMAN:Broadcast("ECFNGaugeView")
				end
			end)
		end
	end,
	RedrawCommand = function(self)
		local verts = {}
		buildGaugeGraph(verts, viewGauges[viewIndex])
		self:SetVertices(verts)
		self:SetDrawState {Mode = "DrawMode_Quads", First = 1, Num = #verts}
	end,
	ECFNGaugeViewMessageCommand = function(self)
		self:playcommand("Redraw")
	end,
}
t[#t + 1] = Img("gauge_frame.png", 37, 67, 527, 267, {
	OnCommand = function(self)
		self:diffusealpha(0):cropbottom(0.5):croptop(0.5):sleep(0.1):decelerate(0.2):diffusealpha(1):cropbottom(0):croptop(0)
	end,
})

-- lane option and gauge in the option information line
local arrangeFrames = {BMSMirror = 1, BMSRandom = 2, BMSRRandom = 3, BMSSRandom = 4, BMSHRandom = 6}
local arrange = 0
local customLanes
do
	local mods = score:GetModifiers() or ""
	for k, v in pairs(arrangeFrames) do
		for word in mods:gmatch("[^,%s]+") do
			if word == k then
				arrange = v
			end
		end
	end
	customLanes = mods:match("Lanes(%d%d%d%d%d%d%d)")
end
if customLanes then
	t[#t + 1] = Text(38, 349, 12, 0, 140, "LANES " .. customLanes)
else
	t[#t + 1] = Frame("random_op 1x10.png", arrange, 38, 343, 130, 12, true, 100)
end
do
	local names = {Easy = "EASY", Groove = "GROOVE", Hard = "HARD", ExHard = "EX-HARD", Death = "DEATH"}
	local function gaugeText()
		local text = names[gaugeName] .. " GAUGE"
		if usedGAS then
			text = text .. " (GAS)"
		end
		local view = viewGauges[viewIndex]
		if view ~= gaugeName then
			text = text .. " > " .. names[view]
		end
		if o2jam then
			text = "O2JAM HARD GAUGE  /  O2JAM JUDGE"
		else
			text = text .. "  /  " .. string.upper(getBMSJudgeRankFromScore(score)) .. " JUDGE"
		end
		local rate = score:GetMusicRate()
		if math.abs(rate - 1) > 0.001 then
			text = text .. "  /  " .. getRateString(notShit.round(rate, 3))
		end
		return text
	end
	local label = Text(560, 349, 12, 1, 360, gaugeText(), color("1,1,1,0.85"))
	label.ECFNGaugeViewMessageCommand = function(self)
		self:settext(gaugeText())
	end
	t[#t + 1] = label
end

-- big DJ level over the graph
t[#t + 1] = Def.Sprite {
	Texture = dir .. "rank_b 1x8.png",
	InitCommand = function(self)
		self:animate(false):setstate(curRank - 1):halign(0):valign(0):xy(116, 131):zoomto(369, 124)
		-- O2Jam plays show their O2Jam grade instead
		self:visible(not o2jam)
	end,
	OnCommand = function(self)
		self:diffusealpha(0):zoomto(396, 524 / 4):sleep(0.1):decelerate(0.2):diffusealpha(1):zoomto(369, 124)
	end,
}

---------------------------------------------------------------------------
-- score frame: clear type, DJ level, score, miss count, target
---------------------------------------------------------------------------

t[#t + 1] = Img("score_frame.png", 23, 373, 485, 345)

-- new record glows
local function NewRecord(file, y, h)
	return Img(file, 341, y, 166, h, {
		OnCommand = function(self)
			self:diffusealpha(0):linear(0.2):diffusealpha(1):sleep(0.4):queuecommand("Pulse")
		end,
		PulseCommand = function(self)
			self:linear(0.8):diffusealpha(0):linear(1):diffusealpha(1):queuecommand("Pulse")
		end,
	})
end
if curLamp > best.lamp and curLamp >= 2 then
	t[#t + 1] = NewRecord("newrecord_1.png", 374, 51)
end
if bestRank and curRank < bestRank then
	t[#t + 1] = NewRecord("newrecord_1.png", 423, 51)
end
if best.ex and curEx > best.ex then
	t[#t + 1] = NewRecord("newrecord_2.png", 495, 57)
end
if best.miss and cleared and curMiss < best.miss then
	t[#t + 1] = NewRecord("newrecord_1.png", 573, 51)
end

-- clear type
local function Lamp(frame, x)
	return Def.Sprite {
		Texture = dir .. "lamp" .. frame .. " 3x1.png",
		InitCommand = function(self)
			self:halign(0):valign(0):xy(x, 390):zoomto(109, 19)
			self:SetAllStateDelays(0.2 / 3)
		end,
		OnCommand = function(self)
			self:diffusealpha(0):zoomy(0):sleep(0.35):linear(0.05):diffusealpha(1):zoomy(1)
		end,
	}
end
t[#t + 1] = Lamp(best.lamp, 210)
t[#t + 1] = Lamp(curLamp, 362)

-- DJ level, best and now, and the way to the next one
if bestRank then
	t[#t + 1] = Frame("rank_m 1x8.png", bestRank - 1, 227, 437, 69, 23, true)
end
t[#t + 1] = Frame("rank_m 1x8.png", curRank - 1, 383, 437, 69, 23, true)
-- rank_s frames: MAX AAA AA A B C D E F, the next level up from the current one
t[#t + 1] = Frame("rank_s 1x9.png", curRank - 1, 321, 474, 45, 19, true)
do
	local nextEx = curRank == 1 and maxEx or djBorder(curRank - 1)
	t[#t + 1] = Diff("num_plus 12x1.png", "num_rankminus 12x1.png", 368, 475, 19, 18, 5, curEx - nextEx)
end

-- EX score and rate
local function Rate(intFile, perFile, x, ex)
	local f = Def.ActorFrame {}
	local pct = ex / maxEx * 100
	local int = math.floor(pct)
	local frac = math.floor((pct - int) * 100)
	f[#f + 1] = Num(intFile, x, 527, 13, 14, 3, int)
	f[#f + 1] = Img(perFile, x + 37, 528, 45, 13)
	f[#f + 1] = Num(intFile, x + 42, 527, 13, 14, 2, frac, {pad = "zero"})
	return f
end
if best.ex then
	t[#t + 1] = Num("num_white 11x1.png", 225, 507, 20, 20, 4, best.ex)
	t[#t + 1] = Rate("num_acc 11x1.png", "score_per.png", 225, best.ex)
end
t[#t + 1] = Num("num_cyan 11x1.png", 376, 507, 20, 20, 4, curEx)
t[#t + 1] = Rate("num_acc_cur 11x1.png", "score_per_cur.png", 376, curEx)
t[#t + 1] = Diff("num_plus 12x1.png", "num_minus 12x1.png", 368, 553, 19, 18, 5, curEx - (best.ex or 0))

-- miss count, empty POORs included like beatoraja
if best.miss then
	t[#t + 1] = Num("num_white 11x1.png", 225, 589, 20, 20, 4, best.miss)
	t[#t + 1] = Diff("num_missplus 12x1.png", "num_missminus 12x1.png", 368, 625, 19, 18, 5, curMiss - best.miss)
end
t[#t + 1] = Num("num_cyan 11x1.png", 376, 589, 20, 20, 4, curMiss)

-- target
do
	local pct = targetEx / maxEx * 100
	local int = math.floor(pct)
	local frac = math.floor((pct - int) * 100)
	t[#t + 1] = Num("num_orange 11x1.png", 233, 661, 20, 20, 4, targetEx)
	t[#t + 1] = Num("num_orange 11x1.png", 359, 661, 18, 20, 3, int)
	t[#t + 1] = Img("target_dot1.png", 411, 664, 8, 18)
	t[#t + 1] = Num("num_orange 11x1.png", 418, 661, 18, 20, 2, frac, {pad = "zero"})
	t[#t + 1] = Img("target_per1.png", 454, 662, 26, 18)
	t[#t + 1] = Text(214, 671, 14, 1, 120, curRank == 1 and "MAX" or "AAA", color("#ffb070"))

	local my = curEx / maxEx * 100
	local myInt = math.floor(my)
	local myFrac = math.floor((my - myInt) * 100)
	t[#t + 1] = Diff("num_plus 12x1.png", "num_minus 12x1.png", 214, 697, 19, 18, 5, curEx - targetEx)
	t[#t + 1] = Num("num_plus 12x1.png", 357, 697, 17, 18, 3, myInt)
	t[#t + 1] = Img("target_dot2.png", 404, 697, 7, 18)
	t[#t + 1] = Num("num_plus 12x1.png", 413, 697, 17, 18, 2, myFrac, {pad = "zero"})
	t[#t + 1] = Img("target_per2.png", 446, 697, 23, 18)
end

-- O2Jam: the score frame shows the O2Jam grade and the DMJam score
if o2jam then
	local dm = getO2JamScore(score)
	local grade = getO2JamGrade(dm)
	local bestDm
	for _, s in ipairs(localScores) do
		if s:GetScoreKey() ~= score:GetScoreKey() and s:GetMusicRate() > 0.999 then
			local v = getO2JamScore(s)
			if bestDm == nil or v > bestDm then
				bestDm = v
			end
		end
	end
	local dim = color("1,1,1,0.6")
	t[#t + 1] = Text(300, 193, 110, 0.5, 360, grade, getO2JamGradeColor(grade), 200)
	t[#t + 1] = Box(26, 420, 479, 295, color("0.02,0.03,0.07,0.95"))
	t[#t + 1] = Text(45, 445, 16, 0, 440, "O2JAM SCORE", color("#8fd4ff"))
	t[#t + 1] = Text(45, 490, 15, 0, 200, "GRADE")
	t[#t + 1] = Text(490, 490, 30, 1, 200, grade, getO2JamGradeColor(grade))
	t[#t + 1] = Text(45, 540, 15, 0, 200, "SCORE")
	t[#t + 1] = Text(490, 540, 28, 1, 260, string.format("%.3f", dm), color("#66ffff"))
	if bestDm then
		t[#t + 1] = Text(45, 580, 13, 0, 200, "BEST", dim)
		t[#t + 1] = Text(490, 580, 16, 1, 300,
			string.format("%.3f  (%s%.3f)", bestDm, dm >= bestDm and "+" or "", dm - bestDm), dim)
	end
	t[#t + 1] = Text(45, 620, 15, 0, 300, "NOTES (LONG NOTE = 2)")
	t[#t + 1] = Text(490, 620, 18, 1, 200, tostring(notes))
	t[#t + 1] = Text(45, 655, 15, 0, 300, "MAX COMBO")
	t[#t + 1] = Text(490, 655, 18, 1, 200, tostring(score:GetMaxCombo()))
	t[#t + 1] = Text(45, 693, 12, 0, 450, "SS > 99   S > 96   A > 90   B > 86   C > 78   D > 50", dim)
end

---------------------------------------------------------------------------
-- judge detail with FAST/SLOW
---------------------------------------------------------------------------

t[#t + 1] = Img("judge_detail.png", 3, 676, 514, 369, {
	OnCommand = function(self)
		fadeIn(self, 0, 100)
	end,
})
t[#t + 1] = Def.Sprite {
	Texture = dir .. "p_great 1x4.png",
	InitCommand = function(self)
		self:halign(0):valign(0):xy(55, 746):zoomto(91, 22)
		self:SetAllStateDelays(0.25 / 4)
	end,
	OnCommand = function(self)
		fadeIn(self, 0, 100)
	end,
}
t[#t + 1] = Img("detail_fast.png", 403, 732, 31, 8)
t[#t + 1] = Img("detail_slow.png", 317, 732, 36, 8)
do
	local rows = {counts[1], counts[2], counts[3], counts[4], counts[5], emptyPoors}
	for k = 1, 6 do
		local y = 34 * (k - 1)
		t[#t + 1] = Num("num_judge 11x1.png", 170, 747 + y, 22, 20, 4, rows[k])
		t[#t + 1] = Num("num_fast 11x1.png", 390, 750 + y, 14, 13, 4, fast[k])
		t[#t + 1] = Num("num_slow 11x1.png", 308, 750 + y, 14, 13, 4, slow[k])
	end
	local totalFast, totalSlow = 0, 0
	for k = 2, 6 do
		totalFast = totalFast + fast[k]
		totalSlow = totalSlow + slow[k]
	end
	t[#t + 1] = Num("num_small 11x1.png", 199, 954, 14, 13, 4, score:GetMaxCombo())
	t[#t + 1] = Num("num_small 11x1.png", 199, 977, 14, 13, 4, counts[4] + counts[5])
	t[#t + 1] = Num("num_small 11x1.png", 390, 954, 14, 13, 4, totalFast)
	t[#t + 1] = Num("num_small 11x1.png", 390, 977, 14, 13, 4, totalSlow)
end
-- O2Jam names over the LR2 ones: COOL, (no GREAT), GOOD, BAD, MISS, (no empty POOR)
if o2jam then
	local labels = {
		{"COOL", "TapNoteScore_W1"}, {"-", nil}, {"GOOD", "TapNoteScore_W3"},
		{"BAD", "TapNoteScore_W4"}, {"MISS", "TapNoteScore_Miss"}, {"-", nil},
	}
	for k, l in ipairs(labels) do
		local y = 744 + 34 * (k - 1)
		t[#t + 1] = Box(48, y, 112, 27, color("0.02,0.03,0.07,1"))
		t[#t + 1] = Text(55, y + 13, 18, 0, 100, l[1], l[2] and getBMSJudgeColor(l[2]) or color("1,1,1,0.4"), 100)
	end
end

---------------------------------------------------------------------------
-- right panel: BMS data, graphs, local ranking
---------------------------------------------------------------------------

t[#t + 1] = Img("extend_frame.png", 1365, 53, 550, 971)

-- stage picture
do
	local pic = song:GetBackgroundPath() or song:GetBannerPath() or song:GetJacketPath()
	if pic then
		t[#t + 1] = Def.Sprite {
			InitCommand = function(self)
				self:LoadBackground(pic)
				self:scaletofit(1381, 89, 1381 + 190, 89 + 142)
			end,
			OnCommand = function(self)
				self:diffusealpha(0):linear(0.2):diffusealpha(1)
			end,
		}
	end
end

t[#t + 1] = Text(1900, 103, 16, 1, 250, song:GetDisplayMainTitle())
t[#t + 1] = Text(1900, 131, 16, 1, 250, song:GetDisplayArtist())
do
	local bpms = steps:GetDisplayBpms()
	local lo, hi = math.floor(bpms[1] + 0.5), math.floor(bpms[2] + 0.5)
	t[#t + 1] = Num("num_white 11x1.png", 1847, 149, 18, 20, 3, hi)
	if lo ~= hi then
		t[#t + 1] = Img("bpm_bar.png", 1831, 156, 9, 6)
		t[#t + 1] = Num("num_white 11x1.png", 1766, 149, 18, 20, 3, lo)
	end
	local len = steps:GetLengthSeconds()
	if not len or len <= 0 then
		len = song:MusicLengthSeconds()
	end
	len = math.floor(len)
	t[#t + 1] = Num("num_info 11x1.png", 1817, 177, 18, 20, 2, math.floor(len / 60), {pad = "zero"})
	t[#t + 1] = Img("dot.png", 1856, 182, 7, 6)
	t[#t + 1] = Img("dot.png", 1856, 187, 7, 6)
	t[#t + 1] = Num("num_info 11x1.png", 1865, 177, 18, 20, 2, len % 60, {pad = "zero"})
	local total = steps:GetBMSTotal()
	if total and total > 0 then
		t[#t + 1] = Num("num_white 11x1.png", 1829, 205, 18, 20, 4, total)
	end
end

-- graph boxes
t[#t + 1] = Img("timing.png", 1380, 239, 522, 312)
local graphW, graphH = 520, 82
local bins = 104

-- judgments over time, stacked and scaled by note density
t[#t + 1] = Quads(1381, 258, function(v)
	local b = {}
	local most = 1
	for i = 1, bins do
		b[i] = {0, 0, 0, 0, 0}
	end
	for _, tp in ipairs(taps) do
		local i = math.max(1, math.min(bins, math.floor(tp[1] / finalSecond * bins) + 1))
		b[i][tp[3]] = b[i][tp[3]] + 1
	end
	for i = 1, bins do
		local n = b[i][1] + b[i][2] + b[i][3] + b[i][4] + b[i][5]
		most = math.max(most, n)
	end
	local bw = graphW / bins
	for i = 1, bins do
		local y = graphH
		for j = 5, 1, -1 do
			local h = b[i][j] / most * graphH
			if h > 0 then
				quad(v, (i - 1) * bw, y - h, i * bw - 1, y, judgeColors[j])
				y = y - h
			end
		end
	end
end)

-- fast/slow over time
t[#t + 1] = Quads(1381, 363, function(v)
	local b = {}
	local most = 1
	for i = 1, bins do
		b[i] = {0, 0, 0}
	end
	for _, tp in ipairs(taps) do
		local i = math.max(1, math.min(bins, math.floor(tp[1] / finalSecond * bins) + 1))
		if tp[3] == 1 then
			b[i][1] = b[i][1] + 1
		elseif tp[3] == 5 or tp[2] > 0 then
			b[i][3] = b[i][3] + 1
		else
			b[i][2] = b[i][2] + 1
		end
	end
	for i = 1, bins do
		most = math.max(most, b[i][1] + b[i][2] + b[i][3])
	end
	local bw = graphW / bins
	local cols = {color("#44dd44"), color("#2a6cff"), color("#ff4040")}
	for i = 1, bins do
		local y = graphH
		for j = 3, 1, -1 do
			local h = b[i][j] / most * graphH
			if h > 0 then
				quad(v, (i - 1) * bw, y - h, i * bw - 1, y, cols[j])
				y = y - h
			end
		end
	end
end)

-- timing distribution over the LR2 windows: PGREAT blue, GREAT green,
-- GOOD olive and BAD red bands under a 1ms histogram
local range = math.floor(windows[3] * 1.25)
t[#t + 1] = Quads(1381, 468, function(v)
	local hist = {}
	local most = 1
	for _, tp in ipairs(taps) do
		if tp[3] < 5 then
			local o = math.floor(tp[2] + 0.5)
			if math.abs(o) <= range then
				hist[o] = (hist[o] or 0) + 1
				most = math.max(most, hist[o])
			end
		end
	end
	local bw = graphW / (range * 2 + 1)
	local bands = {color("#000070"), color("#005000"), color("#4a4a00"), color("#6a0d0d")}
	local edges = {windows[1], windows[2], windows[3], range}
	quad(v, 0, 0, graphW, graphH, bands[4])
	for i = 3, 1, -1 do
		local x1 = (range - edges[i]) * bw
		local x2 = (range + edges[i] + 1) * bw
		quad(v, x1, 0, x2, graphH, bands[i])
	end
	local cx = range * bw
	quad(v, cx, 0, cx + 1, graphH, {1, 1, 1, 0.5})
	for o = -range, range do
		local n = hist[o]
		if n then
			local h = n / most * (graphH - 4)
			quad(v, (o + range) * bw, graphH - h, (o + range + 1) * bw, graphH, {0.85, 0.85, 0.85, 0.9})
		end
	end
end)
do
	local offs = {}
	for _, tp in ipairs(taps) do
		if tp[3] < 5 then
			offs[#offs + 1] = tp[2]
		end
	end
	if #offs > 0 then
		t[#t + 1] = Text(1898, 476, 12, 1, 300,
			string.format("AVG %+.1fms  SD %.1fms", wifeMean(offs), wifeSd(offs)), color("1,1,1,0.8"))
	end
	t[#t + 1] = Text(1384, 543, 11, 0, 60, "-" .. range .. "ms", color("1,1,1,0.5"))
	t[#t + 1] = Text(1898, 543, 11, 1, 60, "+" .. range .. "ms", color("1,1,1,0.5"))
end

-- local ranking in place of the internet ranking: every local score on this
-- chart by EX score, the summary line is best rank > this play's rank, total
do
	-- drawn on its own frame so the BMS 7k ranking (below) can take its place
	local outer = t
	local t = Def.ActorFrame {Name = "LocalRanking"}
	outer[#outer + 1] = t
	local curPos, bestPos
	for i, s in ipairs(localScores) do
		if s:GetScoreKey() == score:GetScoreKey() then
			curPos = i
		end
		if best.score and s:GetScoreKey() == best.score:GetScoreKey() then
			bestPos = i
		end
	end
	if bestPos and curPos and curPos <= bestPos then
		bestPos = bestPos + 1
	end
	t[#t + 1] = Box(1380, 562, 200, 15, color("#1b1b24"))
	t[#t + 1] = Text(1383, 570, 11, 0, 200, "LOCAL RANKING", color("#d8dce4"), 0)
	if bestPos then
		t[#t + 1] = Num("num_judge 11x1.png", 1424, 600, 22, 20, 4, bestPos)
	end
	t[#t + 1] = Num("num_judge 11x1.png", 1585, 600, 22, 20, 4, curPos)
	t[#t + 1] = Num("num_judge 11x1.png", 1764, 600, 22, 20, 4, #localScores)

	for k = 1, math.min(10, #localScores) do
		local s = localScores[k]
		local y = 663 + 35 * (k - 1)
		local mine = s:GetScoreKey() == score:GetScoreKey()
		t[#t + 1] = Img("ir_frame.png", 1380, y, 522, 34, {
			OnCommand = function(self)
				fadeIn(self, 100 + 20 * k, 100)
			end,
		})
		if mine then
			t[#t + 1] = Box(1382, y + 2, 518, 30, color("0.3,0.8,1,0.18"))
		end
		local lamp = getBMSLampFromScore(s)
		t[#t + 1] = Box(1381, y + 4, 4, 26, getBMSLampInfo(lamp, 2))
		t[#t + 1] = Num("num_white 11x1.png", 1388, y + 7, 17, 20, 4, k)
		local label = s:GetDate():sub(1, 16)
		if math.abs(s:GetMusicRate() - 1) > 0.001 then
			label = label .. "  " .. getRateString(notShit.round(s:GetMusicRate(), 3))
		end
		if o2jam then
			local v = getO2JamScore(s)
			label = label .. string.format("   %.3f  %s", v, getO2JamGrade(v))
		end
		t[#t + 1] = Text(1474, y + 17, 15, 0, 235, label, mine and color("#9fe8ff") or color("1,1,1,0.9"))
		if not o2jam then
			t[#t + 1] = Num("num_white 11x1.png", 1717, y + 7, 18, 20, 4, exScore(s))
			t[#t + 1] = Diff("num_plus 12x1.png", "num_minus 12x1.png", 1804, y + 7, 18, 20, 5, curEx - exScore(s))
		end
	end
end

-- the BMS 7k ranking site in the same place when logged in from the game
-- (Ranking window on song select). Clicking the header switches between it
-- and the local ranking. The game sends this play right after the song, the
-- board is asked again once the site has it.
if BMSRanking and BMSRanking.loggedIn() then
	local R = BMSRanking
	local ck = steps:GetChartKey()
	local board

	-- bitmap number that changes: digits slots, dim 0s in front, like Num
	local function LiveNum(file, x, y, gw, gh, digits, signed)
		local f = Def.ActorFrame {
			InitCommand = function(self)
				self:xy(x, y)
			end,
			SetNumCommand = function(self, p)
				local v = p.value
				self:visible(v ~= nil)
				if v == nil then
					return
				end
				local slots = signed and digits - 1 or digits
				local str = tostring(math.floor(math.abs(v) + 0.5))
				if #str > slots then
					str = str:sub(-slots)
				end
				local first = slots - #str + 1
				for i = 1, slots do
					local g = i >= first and tonumber(str:sub(i - first + 1, i - first + 1)) or 10
					self:GetChild("d" .. i):setstate(g)
				end
			end,
		}
		local col = 0
		if signed then
			f[#f + 1] = Def.Sprite {
				Texture = dir .. file,
				InitCommand = function(self)
					self:animate(false):setstate(11):halign(0):valign(0):zoomto(gw, gh)
				end,
			}
			col = 1
		end
		for i = 1, signed and digits - 1 or digits do
			local cx = (col + i - 1) * gw
			f[#f + 1] = Def.Sprite {
				Name = "d" .. i,
				Texture = dir .. file,
				InitCommand = function(self)
					self:animate(false):setstate(10):halign(0):valign(0):x(cx):zoomto(gw, gh)
				end,
			}
		end
		return f
	end

	local function setNum(actor, v)
		actor:playcommand("SetNum", {value = v})
	end

	local ir = Def.ActorFrame {
		Name = "IRRanking",
		BeginCommand = function(self)
			R.forget(ck)
			board = R.chart(ck)
			self:playcommand("Show")
		end,
		BMSBoardLoadedMessageCommand = function(self, params)
			if params.chartkey == ck then
				board = R.cache[ck] and R.cache[ck].board
				self:playcommand("Show")
			end
		end,
		BMSScoreUploadedMessageCommand = function(self, params)
			if params.chartkey == ck then
				R.forget(ck)
				board = R.chart(ck)
				self:playcommand("Show")
			end
		end,
	}
	ir[#ir + 1] = Box(1380, 562, 200, 15, color("#1b1b24"))
	ir[#ir + 1] = Text(1383, 570, 11, 0, 200, "IR RANKING", color("#9fe8ff"), 0)

	-- this play's place: how many players have more EX, plus one
	local function playPlace()
		if not board or board.err then
			return nil
		end
		local above = 0
		for _, r in ipairs(board.rows) do
			if r.ex > curEx and not (board.me == r) then
				above = above + 1
			end
		end
		return above + 1
	end

	ir[#ir + 1] = LiveNum("num_judge 11x1.png", 1424, 600, 22, 20, 4) .. {
		OnCommand = function(self)
			fadeIn(self, 100, 200)
		end,
		ShowCommand = function(self)
			setNum(self, board and board.me and board.me.rank or nil)
		end,
	}
	ir[#ir + 1] = LiveNum("num_judge 11x1.png", 1585, 600, 22, 20, 4) .. {
		OnCommand = function(self)
			fadeIn(self, 100, 200)
		end,
		ShowCommand = function(self)
			setNum(self, playPlace())
		end,
	}
	ir[#ir + 1] = LiveNum("num_judge 11x1.png", 1764, 600, 22, 20, 4) .. {
		OnCommand = function(self)
			fadeIn(self, 100, 200)
		end,
		ShowCommand = function(self)
			setNum(self, board and not board.err and board.players or nil)
		end,
	}
	-- loading, errors and empty boards
	ir[#ir + 1] = Text(1641, 680, 15, 0.5, 500, "Loading...", color("1,1,1,0.8"), 0) .. {
		ShowCommand = function(self)
			if not board then
				self:settext("Loading...")
			elseif board.err then
				self:settext(board.err)
			elseif #board.rows == 0 then
				self:settext("No scores yet, sending yours...")
			else
				self:settext("")
			end
		end,
	}

	-- ten places; the last one is you when you are further down
	local function rowFor(k)
		if not board or board.err then
			return nil
		end
		if k == 10 and board.me and board.me.rank > 10 then
			return board.me
		end
		return board.rows[k]
	end
	for k = 1, 10 do
		local y = 663 + 35 * (k - 1)
		local row = Def.ActorFrame {
			ShowCommand = function(self)
				local r = rowFor(k)
				self:visible(r ~= nil)
				if r then
					self:playcommand("Row", {row = r})
				end
			end,
		}
		row[#row + 1] = Img("ir_frame.png", 1380, y, 522, 34, {
			OnCommand = function(self)
				fadeIn(self, 100 + 20 * k, 100)
			end,
		})
		row[#row + 1] = Box(1382, y + 2, 518, 30, color("0.3,0.8,1,0.18")) .. {
			RowCommand = function(self, p)
				self:visible(board.me == p.row)
			end,
		}
		row[#row + 1] = Box(1381, y + 4, 4, 26, color("#ffffff")) .. {
			RowCommand = function(self, p)
				self:diffuse(getBMSLampInfo(p.row.lamp, 2))
			end,
		}
		row[#row + 1] = LiveNum("num_white 11x1.png", 1388, y + 7, 17, 20, 4) .. {
			RowCommand = function(self, p)
				setNum(self, p.row.rank)
			end,
		}
		row[#row + 1] = Text(1474, y + 17, 15, 0, 235, "-", color("1,1,1,0.9"), 0) .. {
			RowCommand = function(self, p)
				self:settext(p.row.name .. "   " .. R.rate(board, p.row, notes))
				self:diffuse(board.me == p.row and color("#9fe8ff") or color("1,1,1,0.9"))
			end,
		}
		row[#row + 1] = LiveNum("num_white 11x1.png", 1717, y + 7, 18, 20, 4) .. {
			RowCommand = function(self, p)
				-- O2Jam: the DMJam score is in the text next to the name
				setNum(self, not o2jam and p.row.ex or nil)
			end,
		}
		-- how far this play is from them, + and - sheets like the local list
		row[#row + 1] = LiveNum("num_plus 12x1.png", 1804, y + 7, 18, 20, 5, true) .. {
			RowCommand = function(self, p)
				local d = curEx - p.row.ex
				setNum(self, (d >= 0 and not o2jam) and d or nil)
			end,
		}
		row[#row + 1] = LiveNum("num_minus 12x1.png", 1804, y + 7, 18, 20, 5, true) .. {
			RowCommand = function(self, p)
				local d = curEx - p.row.ex
				setNum(self, (d < 0 and not o2jam) and d or nil)
			end,
		}
		ir[#ir + 1] = row
	end
	t[#t + 1] = ir

	-- clicking the header switches between the two lists, IR first
	local showIR = true
	t[#t + 1] = UIElements.QuadButton(1, 1) .. {
		InitCommand = function(self)
			self:halign(0):valign(0):xy(1380, 562):zoomto(200, 15):diffusealpha(0)
		end,
		BeginCommand = function(self)
			self:playcommand("Switch")
		end,
		SwitchCommand = function(self)
			local f = self:GetParent()
			f:GetChild("IRRanking"):visible(showIR)
			f:GetChild("LocalRanking"):visible(not showIR)
		end,
		MouseDownCommand = function(self, params)
			if params.event == "DeviceButton_left mouse button" then
				showIR = not showIR
				self:playcommand("Switch")
			end
		end,
	}
end

---------------------------------------------------------------------------
-- footer: title, artist, keys, judge rank, level, notes
---------------------------------------------------------------------------

t[#t + 1] = Text(960, 958, 23, 0.5, 800, song:GetDisplayMainTitle(), color("#8fd4ff"), 400)
t[#t + 1] = Text(960, 985, 18, 0.5, 800, song:GetDisplayArtist(), nil, 450)
t[#t + 1] = Text(960, 1011, 16, 0.5, 800, song:GetGroupName(), color("1,1,1,0.6"), 500)
t[#t + 1] = Img("diff_keys_info.png", 724, 1035, 285, 31)
t[#t + 1] = Img("notes_info.png", 1015, 1035, 180, 31)
t[#t + 1] = Frame("keys 1x5.png", 1, 729, 1040, 58, 21, true, 300)
t[#t + 1] = Frame("judge 1x5.png", judgeRank, 790, 1040, 58, 21, true, 300)
do
	-- converted BMS packs carry the level in their name (SP01..SP25 insane levels)
	local level = getBMSLevel(song, steps)
	local diff = 5
	if level < 0 then
		local d = steps:GetDifficulty()
		diff = ({Difficulty_Beginner = 1, Difficulty_Easy = 2, Difficulty_Medium = 3, Difficulty_Hard = 4, Difficulty_Challenge = 5})[d] or 0
		level = level == -1 and nil or steps:GetMeter()
	end
	local numRow = ({[0] = 0, 2, 1, 3, 4, 5})[diff]
	t[#t + 1] = Frame("difficulty 1x6.png", diff, 855, 1042, 104, 17, true, 300)
	if level then
		t[#t + 1] = Num("num_diff" .. numRow .. " 10x1.png", 964, 1042, 18, 17, 2, level, {delay = 300})
	else
		t[#t + 1] = Text(982, 1050, 15, 0.5, 40, "?", nil, 300)
	end
end
t[#t + 1] = Num("num_notes 11x1.png", 1035, 1042, 18, 17, 4, notes, {delay = 300})

---------------------------------------------------------------------------
-- CLEAR / FAILED splash
---------------------------------------------------------------------------

do
	local name = cleared and "clear" or "failed"
	local mx, mw = cleared and 350 or 318, cleared and 1219 or 1293
	local fx, fw = cleared and 295 or 263, cleared and 1329 or 1393
	local bx, bw = cleared and 201 or 168, cleared and 1517 or 1583
	t[#t + 1] = Def.Sprite {
		Texture = dir .. name .. "_main.png",
		InitCommand = function(self)
			self:halign(0):valign(0):xy(mx, 423):zoomto(mw, 196):diffusealpha(0)
		end,
		OnCommand = function(self)
			self:linear(0.3):diffusealpha(1):sleep(0.6):accelerate(0.2):y(523):diffusealpha(0)
		end,
	}
	t[#t + 1] = Def.Sprite {
		Texture = dir .. name .. "_glow.png",
		InitCommand = function(self)
			self:halign(0):valign(0):xy(mx - 1, 422):blend("BlendMode_Add"):diffusealpha(0)
		end,
		OnCommand = function(self)
			self:sleep(0.1):diffusealpha(1):decelerate(0.4):diffusealpha(0)
		end,
	}
	t[#t + 1] = Def.Sprite {
		Texture = dir .. name .. "_flash.png",
		InitCommand = function(self)
			self:halign(0):valign(0):xy(fx, 368):zoomto(fw, 306):blend("BlendMode_Add"):diffusealpha(0)
		end,
		OnCommand = function(self)
			self:sleep(0.1):diffusealpha(1):decelerate(0.7):diffusealpha(cleared and 0.25 or 0.47)
				:sleep(0.1):accelerate(0.2):y(468):diffusealpha(0)
		end,
	}
	t[#t + 1] = Def.Sprite {
		Texture = dir .. name .. "_blur.png",
		InitCommand = function(self)
			self:halign(0):valign(0):xy(bx, 423):zoomto(bw, 196):blend("BlendMode_Add"):diffusealpha(0)
		end,
		OnCommand = function(self)
			self:sleep(0.05):diffusealpha(1):decelerate(0.4):x(bx - 400):zoomto(bw + 800, 196):diffusealpha(0)
		end,
	}
end

---------------------------------------------------------------------------
-- RANDOM / R-RANDOM / MIRROR: hovering the lane option shows the lane order
-- the play had, as the 7 keys with the chart lane each one played
---------------------------------------------------------------------------

do
	local order = (not customLanes) and BMSRanking and BMSRanking.laneOrderOf and BMSRanking.laneOrderOf(score)
	if order then
		local kw, kh, gap, pad = 30, 40, 5, 12
		local pw = 7 * kw + 6 * gap + pad * 2
		local ph = kh + pad * 2 + 22
		local px, py = 38, 343 - ph - 6
		local pop = Def.ActorFrame {
			Name = "LaneOrderPopup",
			InitCommand = function(self)
				self:xy(px, py):visible(false)
			end,
			ShowLanesCommand = function(self)
				self:visible(true):stoptweening():diffusealpha(0):linear(0.08):diffusealpha(1)
			end,
			HideLanesCommand = function(self)
				self:stoptweening():visible(false)
			end,
			Def.Quad {
				InitCommand = function(self)
					self:halign(0):valign(0):zoomto(pw, ph):diffuse(color("0.04,0.06,0.10,0.94"))
				end,
			},
			Def.Quad {
				InitCommand = function(self)
					self:halign(0):valign(0):zoomto(pw, 2):diffuse(color("#66d9ff"))
				end,
			},
		}
		for k = 1, 7 do
			local blue = k % 2 == 0
			local x = pad + (k - 1) * (kw + gap)
			local h = blue and kh - 8 or kh
			pop[#pop + 1] = Def.Quad {
				InitCommand = function(self)
					self:halign(0):valign(0):xy(x, pad):zoomto(kw, h)
					self:diffuse(blue and color("#2f6fe0") or color("#e9ecf3"))
				end,
			}
			pop[#pop + 1] = LoadFont("Common Normal") .. {
				InitCommand = function(self)
					self:xy(x + kw / 2, pad + h - 11):zoom(0.62):settext(order:sub(k, k))
					self:diffuse(blue and color("1,1,1,1") or color("0.07,0.08,0.11,1"))
				end,
			}
		end
		pop[#pop + 1] = LoadFont("Common Normal") .. {
			InitCommand = function(self)
				self:xy(pw / 2, pad + kh + 12):zoom(0.5):settext("LANE ORDER  " .. order)
				self:diffuse(color("0.75,0.8,0.9,1"))
			end,
		}
		t[#t + 1] = UIElements.QuadButton(1, 1) .. {
			InitCommand = function(self)
				self:halign(0):valign(0):xy(36, 340):zoomto(134, 18):diffusealpha(0)
			end,
			MouseOverCommand = function(self)
				self:GetParent():GetChild("LaneOrderPopup"):playcommand("ShowLanes")
			end,
			MouseOutCommand = function(self)
				self:GetParent():GetChild("LaneOrderPopup"):playcommand("HideLanes")
			end,
		}
		t[#t + 1] = pop
	end
end

---------------------------------------------------------------------------
-- a song of a dan course: hand this song over for the COURSE RESULT screen
---------------------------------------------------------------------------

if BMSDan and BMSDan.addCourseSong and isCurrentPlay and not o2jam then
	local life = {}
	local full = gaugeLife(gaugeName, gw) or {}
	local n = 200
	for i = 1, n do
		local k = math.max(1, math.min(#full, math.floor((i - 0.5) / n * #full) + 1))
		life[i] = full[k] or 0
	end
	BMSDan.addCourseSong {
		key = score:GetScoreKey(),
		notes = notes,
		counts = {counts[1], counts[2], counts[3], counts[4], counts[5]},
		emptyPoors = emptyPoors,
		fast = {fast[1], fast[2], fast[3], fast[4], fast[5], fast[6]},
		slow = {slow[1], slow[2], slow[3], slow[4], slow[5], slow[6]},
		miss = curMiss,
		maxCombo = score:GetMaxCombo(),
		arrange = arrange,
		life = life,
	}
end

return Def.ActorFrame {t}
