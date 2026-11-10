-- 7k: COURSE RESULT of a BMS dan course, after the result screen of its last
-- song. Laid out like the stage result (ecfn.lua, beatoraja ECFN
-- course_result): the left panels hold the whole course (every song's
-- judgments added up, the course gauge over all songs), the footer the course
-- name and its notes. START or BACK goes on to song select.
local dir = THEME:GetCurrentThemeDirectory()
if dir:sub(1, 1) ~= "/" then
	dir = "/" .. dir
end
dir = dir .. "BGAnimations/ScreenEvaluation decorations/ecfn/"
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
-- drawing helpers (as in ScreenEvaluation decorations/ecfn.lua)
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

local t = Def.ActorFrame {
	Name = "ECFNCourseResult",
	InitCommand = function(self)
		self:xy((SCREEN_WIDTH - W * scale) / 2, 0):zoom(scale)
	end,
}

t[#t + 1] = Box(0, 0, W, H, color("0,0,0,1"))

t[#t + 1] = Img(cleared and "upper.png" or "upper_f.png", 55, 0, 1811, 165, {
	OnCommand = function(self)
		fadeIn(self, 200, 300)
	end,
})
t[#t + 1] = Img(cleared and "courseresult.png" or "courseresult_f.png", 729, 13, 462, 24, {
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
-- course gauge graph: one part per song
---------------------------------------------------------------------------

local gx, gy, gw, gh = 41, 71, 519, 259
t[#t + 1] = Img("groove_main.png", 13, 55, 565, 309)
local gaugeLook = {
	Class = {color("#440000aa"), color("#ff0000")},
	ExClass = {color("#440000aa"), color("#ff0000")},
	ExHardClass = {color("#444400aa"), color("#ffff00")},
}
local look = gaugeLook[res.classGauge] or gaugeLook.Class
t[#t + 1] = Quads(gx, gy, function(v)
	quad(v, 0, 0, gw, gh, look[1])
	local part = gw / songsTotal
	local function lifeY(l)
		l = math.max(0, math.min(1, l or 0))
		return math.max(2, math.min(gh - 2, gh * (1 - l)))
	end
	for i = 1, songsTotal do
		local x0 = (i - 1) * part
		if i > 1 then
			quad(v, x0 - 1, 0, x0 + 1, gh, color("1,1,0.6,0.55"))
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
				quad(v, xa, math.min(y, p) - 1, xb, math.max(y, p) + 1, look[2])
				prev = y
			end
		end
	end
end, 100)
t[#t + 1] = Img("gauge_frame.png", 37, 67, 527, 267, {
	OnCommand = function(self)
		self:diffusealpha(0):cropbottom(0.5):croptop(0.5):sleep(0.1):decelerate(0.2):diffusealpha(1):cropbottom(0):croptop(0)
	end,
})
t[#t + 1] = Frame("random_op 1x10.png", arrange, 38, 343, 130, 12, true, 100)
do
	local names = {Class = "CLASS", ExClass = "EX CLASS", ExHardClass = "EX HARD CLASS"}
	local text = (names[res.classGauge] or "CLASS") .. string.format("  %.1f%%", res.gauge or 0)
		.. "  /  SONGS " .. (res.songsPlayed or 0) .. "/" .. (res.songsTotal or songsTotal)
	t[#t + 1] = Text(560, 349, 12, 1, 360, text, color("1,1,1,0.85"))
end

-- big DJ level over the graph
t[#t + 1] = Def.Sprite {
	Texture = dir .. "rank_b 1x8.png",
	InitCommand = function(self)
		self:animate(false):setstate(curRank - 1):halign(0):valign(0):xy(116, 131):zoomto(369, 124)
	end,
	OnCommand = function(self)
		self:diffusealpha(0):zoomto(396, 524 / 4):sleep(0.1):decelerate(0.2):diffusealpha(1):zoomto(369, 124)
	end,
}

---------------------------------------------------------------------------
-- score frame: clear type, DJ level, score, miss count, target
---------------------------------------------------------------------------

t[#t + 1] = Img("score_frame.png", 23, 373, 485, 345)

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

if bestRank then
	t[#t + 1] = Frame("rank_m 1x8.png", bestRank - 1, 227, 437, 69, 23, true)
end
t[#t + 1] = Frame("rank_m 1x8.png", curRank - 1, 383, 437, 69, 23, true)
t[#t + 1] = Frame("rank_s 1x9.png", curRank - 1, 321, 474, 45, 19, true)
do
	local nextEx = curRank == 1 and maxEx or djBorder(curRank - 1)
	t[#t + 1] = Diff("num_plus 12x1.png", "num_rankminus 12x1.png", 368, 475, 19, 18, 5, curEx - nextEx)
end

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
-- a course has more notes than a song: 5 digits
if best.ex then
	t[#t + 1] = Num("num_white 11x1.png", 205, 507, 20, 20, 5, best.ex)
	t[#t + 1] = Rate("num_acc 11x1.png", "score_per.png", 225, best.ex)
else
	t[#t + 1] = Num("num_white 11x1.png", 205, 507, 20, 20, 5, 0)
	t[#t + 1] = Rate("num_acc 11x1.png", "score_per.png", 225, 0)
end
t[#t + 1] = Num("num_cyan 11x1.png", 356, 507, 20, 20, 5, curEx)
t[#t + 1] = Rate("num_acc_cur 11x1.png", "score_per_cur.png", 376, curEx)
t[#t + 1] = Diff("num_plus 12x1.png", "num_minus 12x1.png", 368, 553, 19, 18, 5, curEx - (best.ex or 0))

if best.miss then
	t[#t + 1] = Num("num_white 11x1.png", 205, 589, 20, 20, 5, best.miss)
	t[#t + 1] = Diff("num_missplus 12x1.png", "num_missminus 12x1.png", 368, 625, 19, 18, 5, curMiss - best.miss)
end
t[#t + 1] = Num("num_cyan 11x1.png", 356, 589, 20, 20, 5, curMiss)

do
	local pct = targetEx / maxEx * 100
	local int = math.floor(pct)
	local frac = math.floor((pct - int) * 100)
	t[#t + 1] = Num("num_orange 11x1.png", 213, 661, 20, 20, 5, targetEx)
	t[#t + 1] = Num("num_orange 11x1.png", 359, 661, 18, 20, 3, int)
	t[#t + 1] = Img("target_dot1.png", 411, 664, 8, 18)
	t[#t + 1] = Num("num_orange 11x1.png", 418, 661, 18, 20, 2, frac, {pad = "zero"})
	t[#t + 1] = Img("target_per1.png", 454, 662, 26, 18)
	t[#t + 1] = Text(194, 671, 14, 1, 120, curRank == 1 and "MAX" or "AAA", color("#ffb070"))

	local my = curEx / maxEx * 100
	local myInt = math.floor(my)
	local myFrac = math.floor((my - myInt) * 100)
	t[#t + 1] = Diff("num_plus 12x1.png", "num_minus 12x1.png", 214, 697, 19, 18, 5, curEx - targetEx)
	t[#t + 1] = Num("num_plus 12x1.png", 357, 697, 17, 18, 3, myInt)
	t[#t + 1] = Img("target_dot2.png", 404, 697, 7, 18)
	t[#t + 1] = Num("num_plus 12x1.png", 413, 697, 17, 18, 2, myFrac, {pad = "zero"})
	t[#t + 1] = Img("target_per2.png", 446, 697, 23, 18)
end

---------------------------------------------------------------------------
-- judge detail with FAST/SLOW, the whole course
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
}
t[#t + 1] = Img("detail_fast.png", 403, 732, 31, 8)
t[#t + 1] = Img("detail_slow.png", 317, 732, 36, 8)
do
	local rows = {counts[1], counts[2], counts[3], counts[4], counts[5], emptyPoors}
	for k = 1, 6 do
		local y = 34 * (k - 1)
		t[#t + 1] = Num("num_judge 11x1.png", 148, 747 + y, 22, 20, 5, rows[k])
		t[#t + 1] = Num("num_fast 11x1.png", 376, 750 + y, 14, 13, 5, fast[k])
		t[#t + 1] = Num("num_slow 11x1.png", 294, 750 + y, 14, 13, 5, slow[k])
	end
	local totalFast, totalSlow = 0, 0
	for k = 2, 6 do
		totalFast = totalFast + fast[k]
		totalSlow = totalSlow + slow[k]
	end
	t[#t + 1] = Num("num_small 11x1.png", 185, 954, 14, 13, 5, maxCombo)
	t[#t + 1] = Num("num_small 11x1.png", 185, 977, 14, 13, 5, counts[4] + counts[5])
	t[#t + 1] = Num("num_small 11x1.png", 376, 954, 14, 13, 5, totalFast)
	t[#t + 1] = Num("num_small 11x1.png", 376, 977, 14, 13, 5, totalSlow)
end

---------------------------------------------------------------------------
-- footer: course name, keys, notes of the whole course
---------------------------------------------------------------------------

t[#t + 1] = Text(960, 980, 26, 0.5, 800, res.name or course.name or "", color("#8fd4ff"), 400)
t[#t + 1] = Img("diff_keys_info.png", 838, 1035, 70, 31)
t[#t + 1] = Img("notes_info.png", 912, 1035, 180, 31)
t[#t + 1] = Frame("keys 1x5.png", 1, 843, 1040, 58, 21, true, 300)
t[#t + 1] = Num("num_notes 11x1.png", 916, 1042, 18, 17, 5, notes, {delay = 300})

---------------------------------------------------------------------------
-- CLEAR / FAILED splash
---------------------------------------------------------------------------

do
	local name = cleared and "clear" or "failed"
	local mx, mw = cleared and 350 or 318, cleared and 1219 or 1293
	t[#t + 1] = Def.Sprite {
		Texture = dir .. name .. "_main.png",
		InitCommand = function(self)
			self:halign(0):valign(0):xy(mx, 423):zoomto(mw, 196):diffusealpha(0)
		end,
		OnCommand = function(self)
			self:linear(0.3):diffusealpha(1):sleep(0.6):accelerate(0.2):y(523):diffusealpha(0)
		end,
	}
end

-- START / BACK go on to song select (ScreenSplash, metrics.ini)

return t
