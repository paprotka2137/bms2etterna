-- 7k: COURSE RESULT of a BMS dan course, after the result screen of its last
-- song, in the mono look of the stage result. It holds the whole course
-- (every song's judgments added up, the course gauge over all songs) and the
-- course's notes. START or BACK goes on to song select.
local W, H = 1920, 1080
local scale = SCREEN_HEIGHT / H
---------------------------------------------------------------------------
-- course data
---------------------------------------------------------------------------

local D = BMSDan
local res = SONGMAN.GetBMSCourseResult and SONGMAN:GetBMSCourseResult() or {}
local course = (D and res.id and D.byId(res.id)) or {name = res.name or "", charts = {}}
local played = (D and D.course and D.course.id == res.id and D.course.songs) or {}
if D then
	D.courseResultShown = D.courseKey(res)
end

-- notes of every course chart, the songs not reached included
local songNotes = {}
do
	local resolved = D and course.charts and D.resolve(course) or {}
	for i = 1, math.max(#(course.charts or {}), res.songsTotal or 0) do
		local p = played[i]
		local r = resolved[i]
		if p then
			songNotes[i] = p.notes
		elseif r and r.steps then
			songNotes[i] = r.steps:GetRadarValues(PLAYER_1):GetValue("RadarCategory_Notes") or 0
		else
			songNotes[i] = 0
		end
	end
end
local songsTotal = math.max(#songNotes, 1)

local counts = {0, 0, 0, 0, 0}
local emptyPoors = 0
local fast = {0, 0, 0, 0, 0, 0}
local slow = {0, 0, 0, 0, 0, 0}
local notes = 0
local curMiss = 0
local maxCombo = 0
local arrange = 0
for i = 1, songsTotal do
	notes = notes + (songNotes[i] or 0)
	local p = played[i]
	if p then
		for k = 1, 5 do
			counts[k] = counts[k] + (p.counts[k] or 0)
		end
		for k = 1, 6 do
			fast[k] = fast[k] + (p.fast[k] or 0)
			slow[k] = slow[k] + (p.slow[k] or 0)
		end
		emptyPoors = emptyPoors + (p.emptyPoors or 0)
		curMiss = curMiss + (p.miss or 0)
		maxCombo = math.max(maxCombo, p.maxCombo or 0)
		arrange = p.arrange or arrange
	else
		-- a song never reached: every note of it is a miss, like beatoraja
		curMiss = curMiss + (songNotes[i] or 0)
	end
end
-- the course result keeps the engine's count when the theme missed a song
if res.judges and #played < (res.songsPlayed or 0) then
	for k = 1, 5 do
		counts[k] = res.judges[k] or counts[k]
	end
	emptyPoors = res.judges[6] or emptyPoors
	maxCombo = res.maxCombo or maxCombo
end
notes = math.max(notes, counts[1] + counts[2] + counts[3] + counts[4] + counts[5], 1)
local maxEx = notes * 2
local curEx = counts[1] * 2 + counts[2]

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

-- lamp frames: 0 NO PLAY 1 FAILED 5 CLEAR 6 H-CLEAR 7 EXH-CLEAR 8 F-COMBO 9 PERFECT 10 MAX
local cleared = res.cleared and true or false
local gaugeLamp = {Class = 5, ExClass = 6, ExHardClass = 7}
local curLamp = 1
if cleared then
	if counts[3] + counts[4] + counts[5] == 0 then
		curLamp = counts[2] == 0 and 10 or 9
	elseif counts[4] + counts[5] == 0 then
		curLamp = 8
	else
		curLamp = gaugeLamp[res.classGauge] or 5
	end
end
local curRank = djLevel(curEx)
local targetEx = curRank == 1 and maxEx or djBorder(1)

-- the previous best of this course (BMSDan.ini), read before this play is saved
local best = {lamp = 0}
do
	local r = D and D.record(res.id) or nil
	if r then
		best.ex = tonumber(r.best_ex)
		best.miss = tonumber(r.best_miss)
		best.lamp = tonumber(r.best_lamp) or 0
		if best.lamp == 0 then
			if tonumber(r.cleared) == 1 then
				best.lamp = gaugeLamp[r.gauge_type or ""] or 5
			elseif (tonumber(r.attempts) or 0) > 0 then
				best.lamp = 1
			end
		end
	end
end
local bestRank = best.ex and djLevel(best.ex) or nil

-- save the course (records, ranking site) and its bests, once
if D and res.finished then
	D.finish(res)
	D.saveCourseBest(res.id, curEx, curMiss, curLamp)
end

---------------------------------------------------------------------------
-- drawing, in the mono look of the stage result (ScreenEvaluation
-- decorations/mono.lua)
---------------------------------------------------------------------------

local function fade(a, delay)
	a.OnCommand = function(self)
		local al = self:GetDiffuseAlpha()
		self:diffusealpha(0):sleep((delay or 0) / 1000):linear(0.2):diffusealpha(al)
	end
	return a
end

local function L(font, x, y, px, align, text, c, delay, maxw)
	return fade(rxLabel(font, x, y, px, align, text or "", c or rxColor("text"), maxw), delay)
end

local function signed(n)
	if n > 0 then
		return "+" .. n
	elseif n < 0 then
		return "−" .. (-n)
	end
	return "±0"
end

local djNames = {"AAA", "AA", "A", "B", "C", "D", "E", "F"}

local t = Def.ActorFrame {
	Name = "RXCourseResult",
	InitCommand = function(self)
		self:xy((SCREEN_WIDTH - W * scale) / 2, 0):zoom(scale)
	end,
	OnCommand = function(self)
		self:xy((SCREEN_WIDTH - W * scale) / 2, 0):zoom(scale)
	end,
}

-- page, wider than the frame so a non 16:9 screen is covered too
t[#t + 1] = Def.Quad {
	InitCommand = function(self)
		self:xy(W / 2, H / 2):zoomto(W * 2, H):diffuse(rxColor("bg"))
	end,
}

-- top bar
local courseName = res.name or course.name or ""
t[#t + 1] = rxHLine(-W, 72, W * 3, rxColor("line"))
t[#t + 1] = L(rxFont.semibold, 40, 36, 22, 0, "res extensa", rxColor("text"))
t[#t + 1] = L(rxFont.normal, 210, 36, 18, 0, "course result", rxColor("muted"))
t[#t + 1] = L(rxFont.semibold, 420, 36, 22, 0, courseName, rxColor("white"), 100, 900)
t[#t + 1] = L(rxFont.normal, 1880, 36, 18, 1,
	string.format("songs %d / %d   ·   %d notes", res.songsPlayed or 0, res.songsTotal or songsTotal, notes), rxColor("muted"), 100)

local X = 80

---------------------------------------------------------------------------
-- lamp and DJ level
---------------------------------------------------------------------------

local function Head(x, y, text)
	return L(rxFont.normal, x, y, 16, 0, string.upper(text), rxColor("muted"), 100)
end
local function NewTag(x, y)
	return Def.ActorFrame {
		InitCommand = function(self)
			self:xy(x, y)
		end,
		OnCommand = function(self)
			self:diffusealpha(0):sleep(0.4):linear(0.2):diffusealpha(1):queuecommand("Pulse")
		end,
		PulseCommand = function(self)
			self:linear(0.8):diffusealpha(0.35):linear(0.8):diffusealpha(1):queuecommand("Pulse")
		end,
		rxBox(0, -12, 52, 24, rxColor("white")),
		rxLabel(rxFont.bold, 26, 0, 16, 0.5, "NEW", color("#111111")),
	}
end

t[#t + 1] = Head(X, 120, "Lamp")
t[#t + 1] = Def.ActorFrame {
	LoadFont(rxFont.bold) .. {
		InitCommand = function(self)
			self:halign(0):valign(0.5):xy(X, 180):zoom(rxZoom(rxFont.bold, 72)):maxwidth(720 / rxZoom(rxFont.bold, 72))
			self:settext(rxLampLabel(curLamp)):diffuse(rxLampColor(curLamp))
			if curLamp >= 9 then
				self:diffuseshift():effectcolor1(rxLampColor(curLamp)):effectcolor2(color("#ffffff")):effectperiod(1)
			end
		end,
		OnCommand = function(self)
			self:diffusealpha(0):x(X + 24):sleep(0.3):decelerate(0.3):x(X):diffusealpha(1)
		end,
	},
}
t[#t + 1] = L(rxFont.normal, X, 236, 18, 0, "best before: " .. rxLampLabel(best.lamp), rxColor("dim"), 300)
if curLamp > best.lamp and curLamp >= 2 then
	t[#t + 1] = NewTag(X + 300, 236)
end

t[#t + 1] = Head(860, 120, "DJ level")
t[#t + 1] = L(rxFont.light, 860, 180, 72, 0, djNames[curRank], rxColor("white"), 300)
t[#t + 1] = L(rxFont.normal, 860, 236, 18, 0, "best before: " .. (bestRank and djNames[bestRank] or "—"), rxColor("dim"), 300)
if bestRank and curRank < bestRank then
	t[#t + 1] = NewTag(860 + 240, 236)
end

---------------------------------------------------------------------------
-- four stat cells: EX score, rate, miss count, target
---------------------------------------------------------------------------

local cellY, cellW = 280, 280
t[#t + 1] = rxHLine(X, cellY, cellW * 4, rxColor("line"))
t[#t + 1] = rxHLine(X, cellY + 100, cellW * 4, rxColor("line"))
local green, red, grey = rxColor("easy"), rxColor("failed"), rxColor("muted")
local function Cell(i, value, diff, diffColor, label, isNew)
	local x = X + (i - 1) * cellW
	local f = Def.ActorFrame {}
	f[#f + 1] = L(rxFont.semibold, x, cellY + 40, 36, 0, value, rxColor("white"), 200 + i * 50)
	f[#f + 1] = L(rxFont.normal, x + 170, cellY + 44, 20, 0, diff or "", diffColor or grey, 200 + i * 50)
	f[#f + 1] = L(rxFont.normal, x, cellY + 78, 15, 0, string.upper(label), rxColor("muted"), 200 + i * 50)
	if isNew then
		f[#f + 1] = NewTag(x + 200, cellY + 78)
	end
	return f
end
do
	local exDiff, exColor
	if best.ex then
		local d = curEx - best.ex
		exDiff, exColor = signed(d), d > 0 and green or (d < 0 and red or grey)
	end
	t[#t + 1] = Cell(1, tostring(curEx), exDiff, exColor, "EX score", best.ex and curEx > best.ex)

	local nextEx = curRank == 1 and maxEx or djBorder(curRank - 1)
	t[#t + 1] = Cell(2, string.format("%.2f%%", curEx / maxEx * 100), signed(curEx - nextEx), grey,
		(curRank == 1 and "rate · to MAX" or "rate · to " .. djNames[curRank - 1]))

	local missDiff, missColor
	if best.miss then
		local d = curMiss - best.miss
		missDiff, missColor = signed(d), d < 0 and green or (d > 0 and red or grey)
	end
	t[#t + 1] = Cell(3, tostring(curMiss), missDiff, missColor, "miss count", best.miss and cleared and curMiss < best.miss)

	local d = curEx - targetEx
	t[#t + 1] = Cell(4, tostring(targetEx), signed(d), d >= 0 and green or red,
		"target · " .. (curRank == 1 and "MAX" or "AAA"))
end

---------------------------------------------------------------------------
-- judgments with FAST / SLOW, the whole course
---------------------------------------------------------------------------

do
	local jy, jw = 430, 420
	local names = {"PGREAT", "GREAT", "GOOD", "BAD", "POOR", "EMPTY POOR"}
	local cols = {rxColor("pg"), rxColor("gr"), rxColor("gd"), rxColor("bd"), rxColor("pr"), rxColor("pr", 0.7)}
	local rows = {counts[1], counts[2], counts[3], counts[4], counts[5], emptyPoors}
	t[#t + 1] = L(rxFont.normal, X + 250, jy, 15, 1, "FAST", rxColor("fast"), 300)
	t[#t + 1] = L(rxFont.normal, X + 330, jy, 15, 1, "SLOW", rxColor("slow"), 300)
	t[#t + 1] = L(rxFont.normal, X + jw, jy, 15, 1, "COUNT", rxColor("muted"), 300)
	for k = 1, 6 do
		local y = jy + 20 + (k - 1) * 40
		t[#t + 1] = rxHLine(X, y + 40, jw, rxColor("panel"))
		t[#t + 1] = L(rxFont.semibold, X, y + 20, 20, 0, names[k], cols[k], 300 + k * 30)
		t[#t + 1] = L(rxFont.normal, X + 250, y + 20, 18, 1, tostring(fast[k]), rxColor("muted"), 300 + k * 30)
		t[#t + 1] = L(rxFont.normal, X + 330, y + 20, 18, 1, tostring(slow[k]), rxColor("muted"), 300 + k * 30)
		t[#t + 1] = L(rxFont.semibold, X + jw, y + 20, 20, 1, tostring(rows[k]), rxColor("text"), 300 + k * 30)
	end
	local totalFast, totalSlow = 0, 0
	for k = 2, 6 do
		totalFast = totalFast + fast[k]
		totalSlow = totalSlow + slow[k]
	end
	local y = jy + 20 + 6 * 40 + 30
	local facts = {
		{"MAX COMBO", maxCombo},
		{"COMBO BREAK", counts[4] + counts[5]},
		{"FAST", totalFast},
		{"SLOW", totalSlow},
	}
	for i, f in ipairs(facts) do
		local fy = y + (i - 1) * 32
		t[#t + 1] = L(rxFont.normal, X, fy, 16, 0, f[1], rxColor("muted"), 500)
		t[#t + 1] = L(rxFont.normal, X + jw, fy, 18, 1, tostring(f[2]), rxColor("text"), 500)
	end
end

---------------------------------------------------------------------------
-- course gauge graph: one part per song
---------------------------------------------------------------------------

do
	local gx, gy, gw, gh = 600, 450, 1240, 420
	local names = {Class = "CLASS", ExClass = "EX CLASS", ExHardClass = "EX HARD CLASS"}
	local gaugeName = names[res.classGauge] or "CLASS"
	local line = res.classGauge == "ExHardClass" and rxColor("exhard") or rxColor("failed")
	t[#t + 1] = L(rxFont.normal, gx, gy - 20, 15, 0, "GAUGE · " .. gaugeName, rxColor("muted"), 300)
	t[#t + 1] = L(rxFont.normal, gx + gw, gy - 20, 15, 1, string.format("final %.1f%%", res.gauge or 0), rxColor("muted"), 300)
	t[#t + 1] = fade(rxQuads(gx, gy, "Init", function(v)
		-- frame and the 20 / 50 / 80 % lines
		rxQuad(v, 0, 0, gw, 1, rxColor("line"))
		rxQuad(v, 0, gh - 1, gw, gh, rxColor("line"))
		rxQuad(v, 0, 0, 1, gh, rxColor("line"))
		rxQuad(v, gw - 1, 0, gw, gh, rxColor("line"))
		for _, p in ipairs({0.2, 0.5, 0.8}) do
			local y = gh * (1 - p)
			rxQuad(v, 1, y, gw - 1, y + 1, rxColor("panel"))
		end
		local part = gw / songsTotal
		local function lifeY(l)
			l = math.max(0, math.min(1, l or 0))
			return math.max(2, math.min(gh - 2, gh * (1 - l)))
		end
		for i = 1, songsTotal do
			local x0 = (i - 1) * part
			if i > 1 then
				rxQuad(v, x0, 1, x0 + 1, gh - 1, rxColor("line2"))
			end
			local life = played[i] and played[i].life
			if life and #life > 0 then
				local n = #life
				local prev
				for k = 1, n do
					local xa = x0 + (k - 1) / n * part
					local xb = x0 + k / n * part
					local y = lifeY(life[k])
					local p = prev or y
					rxQuad(v, xa, math.min(y, p) - 1, xb, math.max(y, p) + 1, line)
					prev = y
				end
			end
		end
	end), 200)
	-- song numbers and notes under each part
	local part = gw / songsTotal
	for i = 1, songsTotal do
		local reached = played[i] ~= nil
		local cx = gx + (i - 0.5) * part
		t[#t + 1] = L(rxFont.semibold, cx, gy + gh + 24, 18, 0.5, string.format("%02d", i),
			reached and rxColor("text") or rxColor("dim"), 400, part - 8)
		t[#t + 1] = L(rxFont.normal, cx, gy + gh + 50, 15, 0.5,
			reached and string.format("%d notes", songNotes[i] or 0) or "not reached", rxColor("muted"), 400, part - 8)
	end
end

-- footer
t[#t + 1] = rxHLine(-W, H - 48, W * 3, rxColor("line"))
t[#t + 1] = L(rxFont.normal, 1880, H - 24, 16, 1, "Start / Back  song select", rxColor("muted"), 400)

---------------------------------------------------------------------------
-- CLEAR / FAILED splash
---------------------------------------------------------------------------

t[#t + 1] = Def.ActorFrame {
	InitCommand = function(self)
		self:diffusealpha(0)
	end,
	OnCommand = function(self)
		self:linear(0.3):diffusealpha(1):sleep(0.6):accelerate(0.2):addy(60):diffusealpha(0)
	end,
	Def.Quad {
		InitCommand = function(self)
			self:xy(W / 2, H / 2):zoomto(W * 2, 220):diffuse(rxColor("bg", 0.92))
		end,
	},
	rxHLine(-W, H / 2 - 110, W * 3, rxColor("line")),
	rxHLine(-W, H / 2 + 110, W * 3, rxColor("line")),
	rxLabel(rxFont.bold, W / 2, H / 2, 140, 0.5, cleared and "CLEAR" or "FAILED",
		cleared and rxColor("white") or rxColor("failed")),
}

-- START / BACK go on to song select (ScreenSplash, metrics.ini)

return Def.ActorFrame {t}
