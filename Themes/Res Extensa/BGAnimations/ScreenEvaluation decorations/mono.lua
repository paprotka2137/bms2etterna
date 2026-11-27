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

-- The judge rank the result is shown on: the one played, or another one
-- picked with [ / ] or a click on the play options; it opens on the chart's own (default.lua builds this
-- file once per judge rank). Scores are judged again from their replays
-- (HighScore::RejudgeBMS); the gauge and the clear it gave stay the play's,
-- they went by the chart's own #RANK.
local playedRank = getBMSJudgeRankIndexFromScore(score)
local chartRank = getBMSChartJudgeRank(steps)
BMSResultView = BMSResultView or {}
local rebuilt = BMSResultView.rebuilt == true
local canRejudge = score.GetBMSRejudge ~= nil and not isO2JamScore(score) and
	not string.lower(score:GetModifiers() or ""):find("classgauge", 1, true)
if not rebuilt then
	-- a score without a replay can only be shown as it was played
	if canRejudge then
		canRejudge = score:GetBMSRejudge(playedRank == 1 and 2 or 1) ~= nil
	end
	BMSResultView.played = playedRank
	BMSResultView.chart = chartRank
	BMSResultView.enabled = canRejudge
end
local viewRank = playedRank
if canRejudge then
	viewRank = BMSResultView.rank or chartRank or playedRank
end
BMSResultView.current = viewRank

local rejudged = {}
-- a score's judgments on the shown rank, nil when they are its own
local function viewTNS(s)
	if not canRejudge or isO2JamScore(s) or getBMSJudgeRankIndexFromScore(s) == viewRank then
		return nil
	end
	local k = s:GetScoreKey()
	if rejudged[k] == nil then
		rejudged[k] = s:GetBMSRejudge(viewRank) or false
	end
	return rejudged[k] or nil
end

local function tns(s, x)
	local r = viewTNS(s)
	if r then
		return r["TapNoteScore_" .. x] or 0
	end
	return s:GetTapNoteScore("TapNoteScore_" .. x)
end

local function maxCombo(s)
	local r = viewTNS(s)
	return r and r.MaxCombo or s:GetMaxCombo()
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
	-- the judged notes stay the same, only BADs come and go
	local r = viewTNS(s)
	if r then
		return getBMSMissCount(s) + r.TapNoteScore_W4 - s:GetTapNoteScore("TapNoteScore_W4")
	end
	return getBMSMissCount(s)
end

-- O2Jam charts play by O2Jam rules: COOL GOOD BAD MISS, DMJam score and
-- O2Jam grade, a long note is judged twice (head and tail)
local o2jam = isO2JamScore(score)

local counts = judgeCounts(score)
-- the score keeps its empty POORs; a score opened again from the list has a
-- player stage stats rebuilt from the replay, which has none of them
local emptyPoors = score:GetEmptyPoorCount()
if isCurrentPlay then
	emptyPoors = math.max(emptyPoors, pss:GetEmptyPoorCount())
end
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
local curMiss = missCount(score)

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
	-- a full combo comes and goes with the judge rank, the clear doesn't
	local r = viewTNS(s)
	if r and lamp ~= 6 then
		local breaks = r.TapNoteScore_W4 + r.TapNoteScore_W5 + r.TapNoteScore_Miss +
			s:GetHoldNoteScore("HoldNoteScore_LetGo") + s:GetHoldNoteScore("HoldNoteScore_MissedHold")
		if breaks == 0 then
			lamp = 1
		elseif lamp == 1 then
			lamp = getBMSGaugeLamp(s)
		end
	end
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
local judgeRank = viewRank
local windows = getBMSWindowsMs(judgeRank)
-- the gauge went by the chart's own #RANK
local gaugeWindows = getBMSWindowsMs(chartRank or playedRank)
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
local taps = {} -- {time, offset, judgment 1-5, judgment for the gauge 1-5}
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
			taps[#taps + 1] = {t, o, j, o2jam and j or offsetJudgment(o, gaugeWindows)}
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
---------------------------------------------------------------------------
-- Res Extensa mono result screen. The score data above is the ECFN one
-- (ecfn.lua); everything below draws it in the res extensa website's look,
-- in the same 1920x1080 space scaled to the screen height.
---------------------------------------------------------------------------

local function fadeIn(self, delay, len)
	self:diffusealpha(0):sleep((delay or 0) / 1000):linear((len or 200) / 1000):diffusealpha(1)
end

-- fixed text, faded in after delay ms
local function Text(font, x, y, px, align, maxw, text, c, delay)
	local z = rxZoom(font, px)
	return LoadFont(font) .. {
		InitCommand = function(self)
			self:xy(x, y):halign(align or 0):valign(0.5):zoom(z):diffuse(c or rxColor("text"))
			if maxw then
				self:maxwidth(maxw / z)
			end
			self:settext(text or "")
		end,
		OnCommand = function(self)
			if delay then
				local a = (c and c[4]) or 1
				self:diffusealpha(0):sleep(delay / 1000):linear(0.15):diffusealpha(a)
			end
		end,
	}
end

local function Box(x, y, w, h, c)
	return rxBox(x, y, w, h, c)
end

local quad = rxQuad

-- quads built once by build(verts)
local function Quads(x, y, build, delay)
	return Def.ActorMultiVertex {
		InitCommand = function(self)
			self:xy(x, y)
			local verts = {}
			build(verts)
			if #verts == 0 then
				self:visible(false)
				return
			end
			self:SetVertices(verts)
			self:SetDrawState {Mode = "DrawMode_Quads", First = 1, Num = #verts}
		end,
		OnCommand = function(self)
			fadeIn(self, delay or 100, 200)
		end,
	}
end

local function signed(v)
	if v > 0 then
		return "+" .. v
	elseif v < 0 then
		return "−" .. -v
	end
	return "±0"
end
local function pct(ex)
	return string.format("%.2f%%", math.max(ex, 0) / maxEx * 100)
end

local judgeColors = {rxColor("pg"), rxColor("gr"), rxColor("gd"), rxColor("bd"), rxColor("pr")}
local djNames = {"AAA", "AA", "A", "B", "C", "D", "E", "F"}

local L, CR = 64, 1300 -- left part (graphs end at CR)
local RX0, RX1 = 1380, 1856 -- right card

local t = Def.ActorFrame {
	Name = "RXResult",
	InitCommand = function(self)
		self:xy((SCREEN_WIDTH - W * scale) / 2, 0):zoom(scale)
	end,
	OnCommand = function(self)
		self:xy((SCREEN_WIDTH - W * scale) / 2, 0):zoom(scale)
	end,
}

-- the ground, wider than 16:9 too
do
	local side = math.max(0, (SCREEN_WIDTH / scale - W) / 2)
	t[#t + 1] = Box(-side, 0, W + side * 2, H, rxColor("bg"))
	local pic = song:GetBackgroundPath() or song:GetJacketPath() or song:GetBannerPath()
	if pic then
		-- the song's picture over the whole screen, cropped to fill it
		t[#t + 1] = Def.Sprite {
			InitCommand = function(self)
				self:LoadBackground(pic)
				local w, h = self:GetTexture():GetSourceWidth(), self:GetTexture():GetSourceHeight()
				local fw = W + side * 2
				local z = math.max(fw / math.max(w, 1), H / math.max(h, 1))
				self:xy(W / 2, H / 2):zoomto(w * z, h * z)
			end,
			OnCommand = function(self)
				self:diffusealpha(0):linear(0.4):diffusealpha(1)
			end,
		}
	end
	-- a veil so the text reads: darker on the left where the numbers are
	t[#t + 1] = Def.Quad {
		InitCommand = function(self)
			self:halign(0):valign(0):xy(-side, 0):zoomto(W + side * 2, H)
			self:diffuseleftedge(rxColor("bg", 0.9)):diffuserightedge(rxColor("bg", 0.72))
		end,
	}
	-- glass cards behind the score strip, the judgments, the graphs and the ranking
	local function card(x, y, w, h)
		t[#t + 1] = Box(x, y, w, h, rxColor("bg", 0.62))
		t[#t + 1] = Box(x, y, w, 1, rxColor("white", 0.1))
		t[#t + 1] = Box(x, y + h - 1, w, 1, rxColor("white", 0.1))
		t[#t + 1] = Box(x, y, 1, h, rxColor("white", 0.1))
		t[#t + 1] = Box(x + w - 1, y, 1, h, rxColor("white", 0.1))
	end
	card(L, 420, CR - L + 20, 110)
	card(L, 560, 580, 460)
	card(670, 560, CR - 670 + 20, 460)
	card(RX0 - 24, 100, RX1 - RX0 + 48, 920)
end

---------------------------------------------------------------------------
-- top bar: the title big; play options on the right
---------------------------------------------------------------------------

do
	local side = math.max(0, (SCREEN_WIDTH / scale - W) / 2)
	t[#t + 1] = Box(-side, 0, W + side * 2, 72, rxColor("bg", 0.75))
	t[#t + 1] = Box(-side, 71, W + side * 2, 1, rxColor("white", 0.1))
end

-- the chart's title, big; no level number, artist or folder
t[#t + 1] = Text(rxFont.bold, L, 37, 46, 0, 1200, (song:GetDisplayMainTitle():gsub("[\r\n]+", " ")), rxColor("white"))

-- lane option and gauge
local arrangeNames = {BMSMirror = "MIRROR", BMSRandom = "RANDOM", BMSRRandom = "R-RANDOM", BMSSRandom = "S-RANDOM", BMSHRandom = "H-RANDOM"}
local arrangeFrames = {BMSMirror = 1, BMSRandom = 2, BMSRRandom = 3, BMSSRandom = 4, BMSHRandom = 6}
local arrange = 0
local arrangeText = "NORMAL"
local customLanes
local colorRandom = false
do
	local mods = score:GetModifiers() or ""
	for k, v in pairs(arrangeFrames) do
		for word in mods:gmatch("[^,%s]+") do
			if word == k then
				arrange = v
				arrangeText = arrangeNames[k]
			end
		end
	end
	customLanes = mods:match("Lanes(%d%d%d%d%d%d%d)")
	colorRandom = mods:lower():find("bmscrandom", 1, true) ~= nil
	if customLanes then
		arrangeText = "LANES " .. customLanes
	elseif colorRandom then
		arrangeText = "RANDOM (COLORS)"
	end
end

---------------------------------------------------------------------------
-- gauge graph
---------------------------------------------------------------------------

local gaugeName = scoreGaugeName(score)
local GX, GY, GW, GH = 694, 610, CR - 694, 200
local gx, gy, gw, gh = GX, GY, GW, GH

local gaugeOrder = {"Easy", "Groove", "Hard", "ExHard", "Death"}
local gaugeIndex = {Easy = 1, Groove = 2, Hard = 3, ExHard = 4, Death = 5}
local usedGAS = string.lower(score:GetModifiers() or ""):find("gas", 1, true) ~= nil

-- with gauge auto shift the graph shows the gauge the play ended on: the
-- cleared one, or EASY when every gauge failed
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
if o2jam then
	gaugeProps.Hard = {true, 0, 100, 0, 0, {0.1, 0.1, 0, -0.5, -3}, 0, 1}
end

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

-- replays a gauge over the judgments of the replay, returns samples 0..1
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
				local inc = change[order[k][4]]
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

-- line colors below / above the clear border
local gaugeLine = {
	Easy = {rxColor("easy"), rxColor("pr")},
	Groove = {rxColor("clear"), rxColor("pr")},
	Hard = {rxColor("hard"), rxColor("hard")},
	ExHard = {rxColor("exhard"), rxColor("exhard")},
	Death = {rxColor("muted"), rxColor("muted")},
}
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
	local rec = isCurrentPlay and pss.GetBMSGaugeRecord and
		pss:GetBMSGaugeRecord(gaugeIndex[name] - 1, finalSecond / math.max(score:GetMusicRate(), 0.01), samples)
	if rec then
		life = rec
	elseif not usedGAS and name == gaugeName and isCurrentPlay then
		local rate = score:GetMusicRate()
		rate = rate > 0 and rate or 1
		life = pss:GetLifeRecord(finalSecond / rate, samples)
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
	local by = gh * (1 - border)
	quad(v, 0, 0, gw, gh, rxColor("panel"))
	if border > 0 then
		quad(v, 0, 0, gw, by, color("#161616"))
		quad(v, 0, by, gw, by + 1, rxColor("line2"))
	end
	for k = 1, 3 do
		quad(v, 0, gh * k / 4, gw, gh * k / 4 + 1, color("#1a1a1a"))
	end
	local samples = math.floor(gw / 2)
	local sw = gw / samples
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
		quad(v, (i - 1) * sw, math.min(y, prev) - 1, i * sw, math.max(y, prev) + 1, c)
	end
end

local plusKeys = {["DeviceButton_="] = 1, ["DeviceButton_KP +"] = 1, ["DeviceButton_-"] = -1, ["DeviceButton_KP -"] = -1}
t[#t + 1] = Def.ActorMultiVertex {
	InitCommand = function(self)
		self:xy(gx, gy)
		self:playcommand("Redraw")
	end,
	OnCommand = function(self)
		fadeIn(self, 150, 200)
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
do
	local names = {Easy = "EASY", Groove = "GROOVE", Hard = "HARD", ExHard = "EX HARD", Death = "DEATH"}
	local function gaugeText()
		if o2jam then
			return "GAUGE  O2JAM HARD"
		end
		local text = "GAUGE  " .. names[gaugeName]
		if usedGAS then
			text = text .. " (GAS)"
		end
		local view = viewGauges[viewIndex]
		if view ~= gaugeName then
			text = text .. "  >  " .. names[view]
		end
		return text
	end
	local label = Text(rxFont.normal, GX, GY - 20, 14, 0, 500, gaugeText(), rxColor("muted"))
	label.ECFNGaugeViewMessageCommand = function(self)
		self:settext(gaugeText())
	end
	t[#t + 1] = label
	if #viewGauges > 1 then
		t[#t + 1] = Text(rxFont.normal, CR, GY - 20, 14, 1, 300, "+ / −  other gauges", rxColor("dim"))
	end
end
-- play options under the top bar
do
	local text = arrangeText
	if o2jam then
		text = text .. "   ·   O2JAM JUDGE"
	else
		text = text .. "   ·   " .. string.upper(getBMSOptionName("JudgeRank", viewRank)) .. " JUDGE"
		local notes = {}
		if chartRank == viewRank then
			notes[#notes + 1] = "CHART"
		end
		if playedRank ~= viewRank then
			notes[#notes + 1] = "PLAYED " .. string.upper(getBMSOptionName("JudgeRank", playedRank))
		end
		if #notes > 0 then
			text = text .. " (" .. table.concat(notes, ", ") .. ")"
		end
		if canRejudge then
			text = text .. "   [ ]"
		end
	end
	local rate = score:GetMusicRate()
	if math.abs(rate - 1) > 0.001 then
		text = text .. "   ·   " .. getRateString(notShit.round(rate, 3))
	end
	t[#t + 1] = Text(rxFont.normal, RX1, 36, 16, 1, 520, text, rxColor("muted"))
	-- a click on it shows the result on the next judge rank (right click: the one before)
	if canRejudge then
		t[#t + 1] = UIElements.QuadButton(1, 1) .. {
			InitCommand = function(self)
				self:halign(1):valign(0.5):xy(RX1, 36):zoomto(520, 28):diffusealpha(0)
			end,
			MouseDownCommand = function(self, params)
				if not BMSResultView.step then
					return
				end
				if params.event == "DeviceButton_left mouse button" then
					BMSResultView.step(1)
				elseif params.event == "DeviceButton_right mouse button" then
					BMSResultView.step(-1)
				end
			end,
		}
	end
end

---------------------------------------------------------------------------
-- lamp, DJ level, score, miss count, target
---------------------------------------------------------------------------

local lampText = rxLampLabel(curLamp)
if curLamp >= 4 and curLamp <= 7 then
	lampText = lampText .. " CLEAR"
end
local newLamp = curLamp > best.lamp and curLamp >= 2
local newRank = bestRank and curRank < bestRank
local newEx = best.ex and curEx > best.ex
local newMiss = best.miss and cleared and curMiss < best.miss

-- a small white NEW tag
local function NewTag(x, y)
	return Def.ActorFrame {
		InitCommand = function(self)
			self:xy(x, y)
		end,
		OnCommand = function(self)
			self:diffusealpha(0):sleep(0.5):linear(0.15):diffusealpha(1)
		end,
		Box(0, -11, 52, 22, rxColor("white")),
		Text(rxFont.bold, 26, 0, 14, 0.5, 48, "NEW", color("#111111")),
	}
end

-- the DJ level (O2Jam grade) big on the left
t[#t + 1] = Text(rxFont.normal, L, 112, 14, 0, 200, o2jam and "GRADE" or "DJ LEVEL", rxColor("muted"))
if newRank then
	t[#t + 1] = NewTag(L + 110, 112)
end
do
	local g, c
	if o2jam then
		g = getO2JamGrade(getO2JamScore(score))
		c = getO2JamGradeColor(g)
	else
		g, c = djNames[curRank], rxColor("white")
	end
	t[#t + 1] = Text(rxFont.light, L - 8, 260, 210, 0, 440, g, c) .. {
		-- the DJ level slides in from the left
		OnCommand = function(self)
			self:diffusealpha(0):addx(-60):sleep(0.2):decelerate(0.35):addx(60):diffusealpha(1)
			if newRank then
				self:sleep(0.1):glow(color("1,1,1,0.8")):linear(0.5):glow(color("1,1,1,0"))
			end
		end,
	}
end

-- the lamp next to it
local HX = 540
t[#t + 1] = Text(rxFont.normal, HX, 150, 14, 0, 200, "LAMP", rxColor("muted"))
if newLamp then
	t[#t + 1] = NewTag(HX + 60, 150)
end
t[#t + 1] = Text(rxFont.bold, HX, 218, 84, 0, CR - HX, lampText, rxLampColor(curLamp)) .. {
	BeginCommand = function(self)
		if curLamp >= 9 then
			self:diffuseshift():effectcolor1(rxLampColor(curLamp)):effectcolor2(color("#ffffff")):effectperiod(1)
		end
	end,
	-- the lamp drops in; a new best lamp lands harder and flashes white once
	OnCommand = function(self)
		local z = self:GetZoom()
		if newLamp then
			self:diffusealpha(0):zoom(z * 1.5):sleep(0.45):decelerate(0.18):zoom(z * 0.96):diffusealpha(1)
			self:bounceend(0.12):zoom(z):glow(color("1,1,1,0.9")):linear(0.4):glow(color("1,1,1,0"))
		else
			self:diffusealpha(0):addx(-30):sleep(0.3):decelerate(0.25):addx(30):diffusealpha(1)
		end
	end,
}
do
	local b = "best  " .. (best.lamp > 0 and rxLampLabel(best.lamp) or "—")
	if not o2jam then
		b = b .. "      DJ level best  " .. (bestRank and djNames[bestRank] or "—")
	end
	t[#t + 1] = Text(rxFont.normal, HX, 290, 18, 0, CR - HX, b, rxColor("muted"), 350)
end

-- the rating this lamp is worth (EASY/CLEAR: the Easy value, HARD and up: the
-- Hard value, like the profile BEST list) and every table the chart is in
if not o2jam then
	local ck = steps:GetChartKey()
	local gr = BMSGoodRatingFile and BMSGoodRatingFile[ck]
	if not gr and getBMSClearDifficulty then
		local was = BMSClearScale
		BMSClearScale = "insane"
		local ok, e, _, h = pcall(getBMSClearDifficulty, steps, 1)
		BMSClearScale = was
		if ok and e and h then
			gr = {e, h}
		end
	end
	local rating
	if gr and curLamp >= 4 and curLamp <= 5 then
		rating = gr[1]
	elseif gr and curLamp >= 6 then
		rating = gr[2]
	end
	t[#t + 1] = Text(rxFont.normal, HX, 336, 14, 0, 200, "RATING", rxColor("muted"), 400)
	t[#t + 1] = Text(rxFont.bold, HX, 372, 34, 0, 220, rating and string.format("★%.2f", rating) or "—",
		rating and color("#ffd080") or rxColor("dim"), 400)
	local tables
	if rxChartTablesText then
		if rxRequestChartTables then
			pcall(rxRequestChartTables, steps)
		end
		local ok, txt = pcall(rxChartTablesText, steps, song)
		if ok and txt and txt ~= "" then
			tables = txt
		end
	end
	t[#t + 1] = Text(rxFont.normal, HX + 260, 336, 14, 0, 200, "TABLES", rxColor("muted"), 400)
	t[#t + 1] = Text(rxFont.semibold, HX + 260, 372, 30, 0, CR - HX - 260, tables or "—", rxColor("text"), 400)
end

-- the four numbers: EX score, rate, miss count, target
do
	local y0 = 420
	local cw = (CR - L + 20) / 4
	local function cell(i, label, value, diff, diffColor, isNew)
		local x = L + 24 + (i - 1) * cw
		if i > 1 then
			t[#t + 1] = Box(x - 24, y0 + 20, 1, 70, rxColor("white", 0.1))
		end
		t[#t + 1] = Text(rxFont.large, x, y0 + 46, 42, 0, cw - 40, value, rxColor("white"), 200 + 60 * i)
		-- the difference sits on the label line, at the cell's right
		if diff then
			t[#t + 1] = Text(rxFont.semibold, x + cw - 48, y0 + 86, 16, 1, 120, diff, diffColor, 300 + 60 * i)
		end
		t[#t + 1] = Text(rxFont.normal, x, y0 + 86, 13, 0, cw - (diff and 180 or 60), label, rxColor("muted"))
		if isNew then
			t[#t + 1] = NewTag(x + cw - 100, y0 + 46)
		end
	end
	local green, red, muted = rxColor("gd"), rxColor("pr"), rxColor("muted")
	if o2jam then
		local dm = getO2JamScore(score)
		local bestDm
		for _, s in ipairs(localScores) do
			if s:GetScoreKey() ~= score:GetScoreKey() and s:GetMusicRate() > 0.999 then
				local v = getO2JamScore(s)
				if bestDm == nil or v > bestDm then
					bestDm = v
				end
			end
		end
		local d = bestDm and (dm - bestDm) or nil
		cell(1, "O2JAM SCORE", string.format("%.3f", dm), d and string.format("%+.3f", d) or nil,
			d and (d >= 0 and green or red) or muted, bestDm and dm > bestDm)
		cell(2, "NOTES (LONG NOTE = 2)", tostring(notes))
		cell(3, "MAX COMBO", tostring(maxCombo(score)))
		cell(4, "SS 99  S 96  A 90  B 86  C 78  D 50", getO2JamGrade(dm))
	else
		local d = curEx - (best.ex or 0)
		cell(1, "EX SCORE  / " .. maxEx, tostring(curEx), best.ex and signed(d) or nil, d >= 0 and green or red, newEx)
		cell(2, best.ex and ("RATE   ·   best " .. pct(best.ex)) or "RATE", pct(curEx))
		local md = best.miss and (curMiss - best.miss) or nil
		cell(3, "MISS COUNT", tostring(curMiss), md and signed(md) or nil, md and (md <= 0 and green or red) or muted, newMiss)
		local nextEx = curRank == 1 and maxEx or djBorder(curRank - 1)
		local targetName = curRank == 1 and "MAX" or "AAA"
		local nextName = curRank == 1 and "MAX" or djNames[curRank - 1]
		cell(4, "TO " .. targetName .. " " .. pct(targetEx), signed(curEx - targetEx),
			curRank == 1 and nil or (nextName .. " " .. signed(curEx - nextEx)), muted)
	end
end

---------------------------------------------------------------------------
-- judgments with FAST/SLOW
---------------------------------------------------------------------------

do
	local y0 = 610
	local xName, xCount, xFast, xSlow = L + 28, 340, 470, 590
	t[#t + 1] = Text(rxFont.normal, xFast, y0 - 20, 13, 1, 80, "FAST", rxColor("fast"))
	t[#t + 1] = Text(rxFont.normal, xSlow, y0 - 20, 13, 1, 80, "SLOW", rxColor("slow"))
	local names = {"PGREAT", "GREAT", "GOOD", "BAD", "POOR", "EMPTY POOR"}
	local cols = {rxColor("pg"), rxColor("gr"), rxColor("gd"), rxColor("bd"), rxColor("pr"), rxColor("pr")}
	if o2jam then
		names = {"COOL", "–", "GOOD", "BAD", "MISS", "–"}
	end
	local rows = {counts[1], counts[2], counts[3], counts[4], counts[5], emptyPoors}
	for k = 1, 6 do
		local y = y0 + 14 + 42 * (k - 1)
		local d = 300 + 40 * k
		t[#t + 1] = Text(rxFont.semibold, xName, y, 19, 0, 190, names[k], names[k] == "–" and rxColor("dim") or cols[k], d)
		t[#t + 1] = Text(rxFont.semibold, xCount, y, 22, 1, 110, tostring(rows[k]), rxColor("white"), d)
		t[#t + 1] = Text(rxFont.normal, xFast, y, 17, 1, 80, k == 1 and "" or tostring(fast[k]), rxColor("text"), d)
		t[#t + 1] = Text(rxFont.normal, xSlow, y, 17, 1, 80, (k == 1 or k == 6) and "" or tostring(slow[k]), rxColor("text"), d)
		t[#t + 1] = Box(xName, y + 21, xSlow - xName, 1, rxColor("white", 0.06))
	end
	local totalFast, totalSlow = 0, 0
	for k = 2, 6 do
		totalFast = totalFast + fast[k]
		totalSlow = totalSlow + slow[k]
	end
	local y = y0 + 14 + 42 * 6 + 14
	t[#t + 1] = Text(rxFont.normal, xName, y, 14, 0, 160, "MAX COMBO", rxColor("muted"))
	t[#t + 1] = Text(rxFont.semibold, xCount, y, 19, 1, 110, tostring(maxCombo(score)), rxColor("text"))
	t[#t + 1] = Text(rxFont.semibold, xFast, y, 17, 1, 80, tostring(totalFast), rxColor("fast"))
	t[#t + 1] = Text(rxFont.semibold, xSlow, y, 17, 1, 80, tostring(totalSlow), rxColor("slow"))
	y = y + 34
	t[#t + 1] = Text(rxFont.normal, xName, y, 14, 0, 160, "COMBO BREAK", rxColor("muted"))
	t[#t + 1] = Text(rxFont.semibold, xCount, y, 19, 1, 110, tostring(counts[4] + counts[5]), rxColor("text"))
	y = y + 34
	t[#t + 1] = Text(rxFont.normal, xName, y, 14, 0, 160, "NOTES", rxColor("muted"))
	t[#t + 1] = Text(rxFont.semibold, xCount, y, 19, 1, 110, tostring(notes), rxColor("text"))
end

---------------------------------------------------------------------------
-- timing distribution (the judgment and FAST/SLOW graphs over time were
-- dropped: the screen was too busy)
---------------------------------------------------------------------------

local graphW = CR - GX
local bins = 160

-- timing distribution over the LR2 windows: tinted bands for PGREAT GREAT
-- GOOD BAD under a 1ms histogram
do
	local y = 870
	local h = 110
	local range = math.floor(windows[3] * 1.25)
	t[#t + 1] = Text(rxFont.normal, GX, y - 16, 14, 0, 400, "TIMING", rxColor("muted"))
	t[#t + 1] = Quads(GX, y, function(v)
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
		local bands = {color("#0e1a1d"), color("#1d1a0d"), color("#0f1c0f"), color("#1b0f1d")}
		local edges = {windows[1], windows[2], windows[3], range}
		quad(v, 0, 0, graphW, h, bands[4])
		for i = 3, 1, -1 do
			local x1 = (range - edges[i]) * bw
			local x2 = (range + edges[i] + 1) * bw
			quad(v, x1, 0, x2, h, bands[i])
		end
		local cx = (range + 0.5) * bw
		quad(v, cx, 0, cx + 1, h, rxColor("muted"))
		for o = -range, range do
			local n = hist[o]
			if n then
				local hh = n / most * (h - 4)
				quad(v, (o + range) * bw, h - hh, (o + range + 1) * bw, h, rxColor("text", 0.9))
			end
		end
	end, 350)
	local offs = {}
	for _, tp in ipairs(taps) do
		if tp[3] < 5 then
			offs[#offs + 1] = tp[2]
		end
	end
	if #offs > 0 then
		t[#t + 1] = Text(rxFont.normal, CR, y - 16, 14, 1, 400,
			string.format("avg %+.1f ms   ·   sd %.1f ms", wifeMean(offs), wifeSd(offs)), rxColor("text"))
	end
	t[#t + 1] = Text(rxFont.normal, GX, y + h + 14, 13, 0, 80, "−" .. range .. " ms", rxColor("dim"))
	t[#t + 1] = Text(rxFont.normal, CR, y + h + 14, 13, 1, 80, "+" .. range .. " ms", rxColor("dim"))
end

---------------------------------------------------------------------------
-- right column: picture, chart facts, ranking
---------------------------------------------------------------------------

do
	local y0 = 128
	local bpms = steps:GetDisplayBpms()
	local lo, hi = math.floor(bpms[1] + 0.5), math.floor(bpms[2] + 0.5)
	local len = steps:GetLengthSeconds()
	if not len or len <= 0 then
		len = song:MusicLengthSeconds()
	end
	len = math.floor(len)
	local total = steps:GetBMSTotal()
	local facts = {
		{"BPM", lo ~= hi and (lo .. "–" .. hi) or tostring(hi)},
		{"TIME", string.format("%d:%02d", math.floor(len / 60), len % 60)},
		{"TOTAL", (total and total > 0) and tostring(math.floor(total + 0.5)) or "–"},
		{"NOTES", tostring(notes)},
	}
	local cw = (RX1 - RX0) / 4
	for i, f in ipairs(facts) do
		local x = RX0 + (i - 1) * cw
		t[#t + 1] = Text(rxFont.semibold, x, y0 + 16, 22, 0, cw - 8, f[2], rxColor("white"))
		t[#t + 1] = Text(rxFont.normal, x, y0 + 42, 12, 0, cw - 8, f[1], rxColor("muted"))
	end
	t[#t + 1] = Box(RX0, y0 + 64, RX1 - RX0, 1, rxColor("line"))
end

local RY = 250 -- ranking header
local rowY0, rowH = 318, 50

-- a ranking row's parts at row k
local function rowY(k)
	return rowY0 + rowH * (k - 1)
end

-- local ranking: every local score on this chart by EX score
do
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
	local summary = "now #" .. (curPos or "?") .. " of " .. #localScores
	if bestPos then
		summary = "best #" .. bestPos .. "   ·   " .. summary
	end
	t[#t + 1] = Text(rxFont.normal, RX1, RY, 14, 1, 330, summary, rxColor("muted"))

	for k = 1, math.min(10, #localScores) do
		local s = localScores[k]
		local y = rowY(k)
		local mine = s:GetScoreKey() == score:GetScoreKey()
		local row = Def.ActorFrame {
			OnCommand = function(self)
				fadeIn(self, 100 + 20 * k, 100)
			end,
		}
		if mine then
			row[#row + 1] = Box(RX0, y - rowH / 2 + 2, RX1 - RX0, rowH - 4, rxColor("white", 0.08))
		end
		row[#row + 1] = Box(RX0, y + rowH / 2 - 1, RX1 - RX0, 1, rxColor("white", 0.06))
		row[#row + 1] = Text(rxFont.semibold, RX0 + 30, y, 17, 1, 40, tostring(k),
			k == 1 and rxColor("gold") or k == 2 and rxColor("silver") or k == 3 and rxColor("bronze") or rxColor("muted"))
		row[#row + 1] = Box(RX0 + 42, y - 12, 6, 24, rxSiteLampColor(getBMSLampFromScore(s)))
		local label = s:GetDate():sub(1, 16)
		if math.abs(s:GetMusicRate() - 1) > 0.001 then
			label = label .. "  " .. getRateString(notShit.round(s:GetMusicRate(), 3))
		end
		if o2jam then
			local v = getO2JamScore(s)
			label = label .. string.format("   %.3f  %s", v, getO2JamGrade(v))
		end
		row[#row + 1] = Text(rxFont.normal, RX0 + 64, y, 16, 0, 270, label, mine and rxColor("white") or rxColor("text"))
		if not o2jam then
			row[#row + 1] = Text(rxFont.semibold, RX1 - 80, y, 18, 1, 90, tostring(exScore(s)), rxColor("white"))
			local gap = exScore(s) - exScore(localScores[1])
			row[#row + 1] = Text(rxFont.normal, RX1, y, 14, 1, 70, k == 1 and "" or signed(gap), rxColor("muted"))
		end
		t[#t + 1] = row
	end
end

-- the header: IR / LOCAL like the site's tabs
local function RankTab(label, x, isOn)
	return LoadFont(rxFont.normal) .. {
		InitCommand = function(self)
			self:halign(0):xy(x, RY):zoom(rxZoom(rxFont.normal, 16)):settext(label)
		end,
		SwitchMessageCommand = function(self, p)
			self:diffuse(isOn(p.ir) and rxColor("white") or rxColor("muted"))
		end,
	}
end

-- the BMS 7k ranking site when logged in from the game; the header switches
-- between it and the local ranking, the site first
local hasIR = BMSRanking and BMSRanking.loggedIn()
if hasIR then
	local R = BMSRanking
	local ck = steps:GetChartKey()
	local board

	local ir = Def.ActorFrame {
		Name = "IRRanking",
		BeginCommand = function(self)
			-- another judge rank of the same result: the board is loaded already
			if rebuilt and R.cache[ck] and R.cache[ck].board then
				board = R.cache[ck].board
			else
				R.forget(ck)
				board = R.chart(ck)
			end
			self:playcommand("Show")
		end,
		BMSBoardLoadedMessageCommand = function(self, params)
			if params.chartkey == ck then
				board = R.cache[ck] and R.cache[ck].board
				self:playcommand("Show")
			end
		end,
		BMSScoreUploadedMessageCommand = function(self, params)
			-- once, by the result built first
			if params.ok and not rebuilt then
				R.sendUnrankedCalc(params.chartkey, params.response)
			end
			if params.chartkey == ck then
				R.forget(ck)
				board = R.chart(ck)
				self:playcommand("Show")
			end
		end,
	}

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

	ir[#ir + 1] = LoadFont(rxFont.normal) .. {
		InitCommand = function(self)
			self:halign(1):xy(RX1, RY):zoom(rxZoom(rxFont.normal, 14)):maxwidth(330 / rxZoom(rxFont.normal, 14)):diffuse(rxColor("muted"))
		end,
		ShowCommand = function(self)
			if not board or board.err then
				self:settext("")
				return
			end
			local parts = {}
			if board.me then
				parts[#parts + 1] = "best #" .. board.me.rank
			end
			local p = playPlace()
			if p then
				parts[#parts + 1] = "now #" .. p
			end
			parts[#parts + 1] = (board.players or 0) .. " players"
			self:settext(table.concat(parts, "   ·   "))
		end,
	}
	ir[#ir + 1] = LoadFont(rxFont.normal) .. {
		InitCommand = function(self)
			self:xy((RX0 + RX1) / 2, rowY(2)):zoom(rxZoom(rxFont.normal, 16)):maxwidth((RX1 - RX0) / rxZoom(rxFont.normal, 16)):diffuse(rxColor("muted"))
		end,
		ShowCommand = function(self)
			if not board then
				self:settext("Loading…")
			elseif board.err then
				self:settext(board.err)
			elseif #board.rows == 0 then
				self:settext("No scores yet, sending yours…")
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
	local function gapToTop(r)
		local top = board.rows[1]
		return r.ex - (top and top.ex or r.ex)
	end
	for k = 1, 10 do
		local y = rowY(k)
		local row = Def.ActorFrame {
			ShowCommand = function(self)
				local r = rowFor(k)
				self:visible(r ~= nil)
				if r then
					self:playcommand("Row", {row = r})
				end
			end,
			OnCommand = function(self)
				fadeIn(self, 100 + 20 * k, 100)
			end,
		}
		row[#row + 1] = Box(RX0, y - rowH / 2 + 2, RX1 - RX0, rowH - 4, rxColor("white", 0.08)) .. {
			RowCommand = function(self, p)
				self:visible(board.me == p.row)
			end,
		}
		row[#row + 1] = Box(RX0, y + rowH / 2 - 1, RX1 - RX0, 1, rxColor("white", 0.06))
		row[#row + 1] = Text(rxFont.semibold, RX0 + 30, y, 17, 1, 40, "") .. {
			RowCommand = function(self, p)
				local r = p.row.rank
				self:settext(tostring(r))
				self:diffuse(r == 1 and rxColor("gold") or r == 2 and rxColor("silver") or r == 3 and rxColor("bronze") or rxColor("muted"))
			end,
		}
		row[#row + 1] = Box(RX0 + 42, y - 12, 6, 24, rxColor("noplay")) .. {
			RowCommand = function(self, p)
				self:diffuse(rxSiteLampColor(p.row.lamp))
			end,
		}
		row[#row + 1] = Text(rxFont.normal, RX0 + 64, y, 16, 0, 270, "") .. {
			RowCommand = function(self, p)
				self:settext(p.row.name .. "   " .. R.rate(board, p.row, notes))
				self:diffuse(board.me == p.row and rxColor("white") or rxColor("text"))
			end,
		}
		row[#row + 1] = Text(rxFont.semibold, RX1 - 80, y, 18, 1, 90, "", rxColor("white")) .. {
			RowCommand = function(self, p)
				self:settext(not o2jam and tostring(p.row.ex) or "")
			end,
		}
		row[#row + 1] = Text(rxFont.normal, RX1, y, 14, 1, 70, "", rxColor("muted")) .. {
			RowCommand = function(self, p)
				local d = gapToTop(p.row)
				self:settext((not o2jam and d ~= 0) and signed(d) or "")
			end,
		}
		ir[#ir + 1] = row
	end
	t[#t + 1] = ir
end

t[#t + 1] = Box(RX0, RY + 22, RX1 - RX0, 1, rxColor("line"))
t[#t + 1] = RankTab("Online", RX0, function(isIR) return isIR end)
t[#t + 1] = RankTab("Local", RX0 + 90, function(isIR) return not isIR end)
do
	local showIR = hasIR and true or false
	t[#t + 1] = Def.Quad {
		Name = "TabLine",
		InitCommand = function(self)
			self:halign(0):valign(0):y(RY + 21):zoomto(60, 2):diffuse(rxColor("white"))
		end,
		SwitchMessageCommand = function(self, p)
			self:x(p.ir and RX0 or RX0 + 90)
		end,
	}
	t[#t + 1] = UIElements.QuadButton(1, 1) .. {
		InitCommand = function(self)
			self:halign(0):valign(0):xy(RX0 - 8, RY - 20):zoomto(180, 40):diffusealpha(0)
		end,
		BeginCommand = function(self)
			self:playcommand("Switch")
		end,
		SwitchCommand = function(self)
			local f = self:GetParent()
			if f:GetChild("IRRanking") then
				f:GetChild("IRRanking"):visible(showIR)
			end
			f:GetChild("LocalRanking"):visible(not showIR)
			MESSAGEMAN:Broadcast("Switch", {ir = showIR})
		end,
		MouseDownCommand = function(self, params)
			if params.event == "DeviceButton_left mouse button" and hasIR then
				showIR = not showIR
				self:playcommand("Switch")
			end
		end,
	}
end

---------------------------------------------------------------------------
-- CLEAR / FAILED: a big word over the screen that drops away
---------------------------------------------------------------------------

t[#t + 1] = Def.ActorFrame {
	InitCommand = function(self)
		self:xy(W / 2, H / 2)
	end,
	Def.Quad {
		InitCommand = function(self)
			local side = math.max(0, (SCREEN_WIDTH / scale - W) / 2)
			self:zoomto(W + side * 2, 240):diffuse(rxColor("bg", 0))
		end,
		OnCommand = function(self)
			if rebuilt then
				return
			end
			self:linear(0.15):diffusealpha(0.92):sleep(0.75):linear(0.25):diffusealpha(0)
		end,
	},
	LoadFont(rxFont.bold) .. {
		InitCommand = function(self)
			self:zoom(rxZoom(rxFont.bold, 150)):settext(cleared and "CLEAR" or "FAILED")
			self:diffuse(cleared and rxColor("white") or rxColor("failed")):diffusealpha(0)
		end,
		OnCommand = function(self)
			if rebuilt then
				return
			end
			self:linear(0.2):diffusealpha(1):sleep(0.7):accelerate(0.25):addy(60):diffusealpha(0)
		end,
	},
}

---------------------------------------------------------------------------
-- RANDOM / MIRROR: hovering the lane option shows the lane order the play
-- had, as the 7 keys with the chart lane each one played
---------------------------------------------------------------------------

do
	local order = (not customLanes) and BMSRanking and BMSRanking.laneOrderOf and BMSRanking.laneOrderOf(score)
	if order then
		local kw, kh, gap, pad = 30, 40, 5, 14
		local pw = 7 * kw + 6 * gap + pad * 2
		local ph = kh + pad * 2 + 24
		local px, py = RX1 - pw, 80
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
					self:halign(0):valign(0):zoomto(pw, ph):diffuse(rxColor("line2"))
				end,
			},
			Def.Quad {
				InitCommand = function(self)
					self:halign(0):valign(0):xy(1, 1):zoomto(pw - 2, ph - 2):diffuse(rxColor("bg"))
				end,
			},
		}
		for k = 1, 7 do
			local blue = tonumber(order:sub(k, k)) % 2 == 0
			local x = pad + (k - 1) * (kw + gap)
			local h = k % 2 == 0 and kh - 8 or kh
			pop[#pop + 1] = Def.Quad {
				InitCommand = function(self)
					self:halign(0):valign(0):xy(x, pad):zoomto(kw, h)
					self:diffuse(blue and rxColor("clear") or rxColor("text"))
				end,
			}
			pop[#pop + 1] = LoadFont(rxFont.semibold) .. {
				InitCommand = function(self)
					self:xy(x + kw / 2, pad + h - 11):zoom(rxZoom(rxFont.semibold, 16)):settext(order:sub(k, k))
					self:diffuse(color("#111111"))
				end,
			}
		end
		pop[#pop + 1] = LoadFont(rxFont.normal) .. {
			InitCommand = function(self)
				self:xy(pw / 2, pad + kh + 14):zoom(rxZoom(rxFont.normal, 13)):settext("LANE ORDER  " .. order)
				self:diffuse(rxColor("muted"))
			end,
		}
		t[#t + 1] = UIElements.QuadButton(1, 1) .. {
			InitCommand = function(self)
				self:halign(1):valign(0):xy(RX1, 16):zoomto(520, 40):diffusealpha(0)
			end,
			MouseOverCommand = function(self)
				self:GetParent():GetChild("LaneOrderPopup"):playcommand("ShowLanes")
			end,
			MouseOutCommand = function(self)
				self:GetParent():GetChild("LaneOrderPopup"):playcommand("HideLanes")
			end,
			-- it covers the play options, so it switches the judge rank too
			MouseDownCommand = function(self, params)
				if not canRejudge or not BMSResultView.step then
					return
				end
				if params.event == "DeviceButton_left mouse button" then
					BMSResultView.step(1)
				elseif params.event == "DeviceButton_right mouse button" then
					BMSResultView.step(-1)
				end
			end,
		}
		t[#t + 1] = pop
	end
end

---------------------------------------------------------------------------
-- a song of a dan course: hand this song over for the COURSE RESULT screen
---------------------------------------------------------------------------

if BMSDan and BMSDan.addCourseSong and isCurrentPlay and not o2jam and not rebuilt then
	local life = {}
	local full = gaugeLife(gaugeName, math.floor(gw / 2)) or {}
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
		maxCombo = maxCombo(score),
		arrange = arrange,
		life = life,
	}
end

return Def.ActorFrame {Name = "RXView" .. viewRank, t}
