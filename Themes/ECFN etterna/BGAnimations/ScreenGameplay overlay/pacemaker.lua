-- 7k: the ECFN SCORE GRAPH (pacemaker) next to the notefield, as in the
-- beatoraja ECFN play skin (play7main.lua, "スコアグラフ"): bars for YOU,
-- MYBEST and PACEMAKER growing as the song goes, the AAA / AA / A lines,
-- the current DJ level and the EX scores, rates and differences under it.
-- Graphics are cut from ECFN's play/frame/SP/Default/main.png and
-- play/Graph.png; coordinates are ECFN's 1920x1080 ones with the panel's
-- top left at 0,0 (ECFN x 528, top of the screen), scaled to the screen.
-- The pacemaker is picked in Player Options (Scripts/BMSPacemaker.lua);
-- the scores come from WifeJudgmentSpotting.lua (BMSPace message), the same
-- EX score the goal tracker paces with. Customize Gameplay moves it (key /)
-- and sizes it (key ').

if not hideMSD() or not playerConfig:get_data(pn_to_profile_slot(PLAYER_1)).PacemakerGraph then
	return Def.ActorFrame {}
end

local dir = THEME:GetCurrentThemeDirectory()
if dir:sub(1, 1) ~= "/" then
	dir = "/" .. dir
end
dir = dir .. "BGAnimations/ScreenGameplay overlay/gfx_pacemaker/"

local allowedCustomization = playerConfig:get_data(pn_to_profile_slot(PLAYER_1)).CustomizeGameplay
local o2jam = isO2JamPlay()
local PW, PH = 290, 933
local zoom = SCREEN_HEIGHT / 1080
-- bars: top and full height in the panel
local BAR_Y, BAR_H = 109, 611

-- notes the EX score counts (O2Jam: long note tails are judged too)
local total = 1
local pbRate
local targetRate, targetRow, targetText
local cur = {ex = 0, judged = 0, rate = 0}

local function loadChart()
	local steps = GAMESTATE:GetCurrentSteps()
	local n = 0
	if steps then
		local rv = steps:GetRadarValues()
		n = rv:GetValue("RadarCategory_Notes") or 0
		if o2jam then
			n = n + (rv:GetValue("RadarCategory_Holds") or 0)
		end
	end
	total = math.max(n, 1)
	pbRate = getBMSPBRateForCurrentChart()
	targetRate, targetRow, targetText = getPacemakerRate(pbRate)
end

local setters = {}
local function refresh()
	for _, set in ipairs(setters) do
		set()
	end
end

local function round(x)
	return math.floor(x + 0.5)
end
-- EX scores of the pace lines
local function paceEx(rate)
	return round((rate or 0) * cur.judged * 2)
end
local function totalEx(rate)
	return round((rate or 0) * total * 2)
end

local function Img(file, x, y, w, h)
	return Def.Sprite {
		Texture = dir .. file,
		InitCommand = function(self)
			self:halign(0):valign(0):xy(x, y):zoomto(w, h)
		end,
	}
end

-- one frame of a sheet, picked by get() (nil hides it)
local function Frame(file, x, y, w, h, get)
	return Def.Sprite {
		Texture = dir .. file,
		InitCommand = function(self)
			self:animate(false):halign(0):valign(0):xy(x, y):zoomto(w, h)
			setters[#setters + 1] = function()
				local f = get()
				self:visible(f ~= nil)
				if f then
					self:setstate(f)
				end
			end
		end,
	}
end

-- bitmap number, right aligned. blank: frame for leading digits (faded 0)
-- or nil to leave them out; zeros: draw leading zeros as real zeros
local function Num(file, x, y, gw, gh, digits, get, blank, zeros)
	local glyphs = {}
	local f = Def.ActorFrame {
		InitCommand = function(self)
			self:xy(x, y)
		end,
	}
	for i = 1, digits do
		f[#f + 1] = Def.Sprite {
			Texture = dir .. file,
			InitCommand = function(self)
				self:animate(false):halign(0):valign(0):x((i - 1) * gw):zoomto(gw, gh)
				glyphs[i] = self
			end,
		}
	end
	setters[#setters + 1] = function()
		local v = get()
		if v == nil then
			for i = 1, digits do
				glyphs[i]:visible(false)
			end
			return
		end
		local s = tostring(math.floor(math.abs(v)))
		if #s > digits then
			s = s:sub(-digits)
		end
		if zeros then
			s = string.rep("0", digits - #s) .. s
		end
		local first = digits - #s + 1
		for i = 1, digits do
			local g = glyphs[i]
			if i >= first then
				g:visible(true):setstate(tonumber(s:sub(i - first + 1, i - first + 1)))
			elseif blank then
				g:visible(true):setstate(blank)
			else
				g:visible(false)
			end
		end
	end
	return f
end

-- signed difference: + in white, - in red, then 4 digits with faded zeros
local function Diff(x, y, get)
	local glyphs = {}
	local f = Def.ActorFrame {
		InitCommand = function(self)
			self:xy(x, y)
		end,
	}
	for i = 1, 5 do
		f[#f + 1] = Def.Sprite {
			Texture = dir .. "num_diff 12x2.png",
			InitCommand = function(self)
				self:animate(false):halign(0):valign(0):x((i - 1) * 22):zoomto(22, 22)
				glyphs[i] = self
			end,
		}
	end
	setters[#setters + 1] = function()
		local v = get()
		for i = 1, 5 do
			glyphs[i]:visible(v ~= nil)
		end
		if v == nil then
			return
		end
		local row = v < 0 and 12 or 0
		local s = tostring(math.min(math.abs(v), 9999))
		glyphs[1]:setstate(row + 11)
		local first = 5 - #s + 1
		for i = 2, 5 do
			if i >= first then
				glyphs[i]:setstate(row + tonumber(s:sub(i - first + 1, i - first + 1)))
			else
				glyphs[i]:setstate(row + 10)
			end
		end
	end
	return f
end

-- a rate as 3 digits, the dot in the frame and 2 decimals
local function Rate(y, get)
	local f = Def.ActorFrame {}
	f[#f + 1] = Num("num_rate 11x1.png", 16, y, 14, 16, 3, function()
		return math.floor(get() * 100)
	end, 10)
	f[#f + 1] = Num("num_rate 11x1.png", 62, y, 14, 16, 2, function()
		return math.floor(get() * 10000) % 100
	end, nil, true)
	return f
end

-- a bar of a pace: the ECFN texture scrolls sideways (one 1px column of the
-- sheet (896 wide in ECFN, 1024 here) at a time, all of it every 10 seconds) and is cut from the
-- top down to the value
local function Bar(file, x, get)
	return Def.Sprite {
		Texture = dir .. file,
		InitCommand = function(self)
			self:halign(0):valign(0):xy(x, BAR_Y)
			self:customtexturerect(0, 0, 1 / 1024, 1):zoomto(60, BAR_H)
			self:texturewrapping(true):texcoordvelocity(0.1, 0)
			setters[#setters + 1] = function()
				self:croptop(1 - math.max(0, math.min(get(), 1)))
			end
		end,
	}
end
-- the dim bar of the final score of a pace
local function FinalBar(x, get)
	return Def.Sprite {
		Texture = dir .. "bar_final.png",
		InitCommand = function(self)
			self:halign(0):valign(0):xy(x, BAR_Y - 1):zoomto(62, BAR_H + 1)
			setters[#setters + 1] = function()
				local v = get()
				self:visible(v ~= nil)
				self:croptop(1 - math.max(0, math.min(v or 0, 1)))
			end
		end,
	}
end

local function youFrac()
	return cur.rate * cur.judged / total
end
local function exOrNil(v)
	-- O2Jam scores are not EX: only rates there
	if o2jam then
		return nil
	end
	return v
end

-- DJ level of the rate so far: 0 AAA .. 7 F
local function djLevel(rate)
	for i = 0, 6 do
		if rate >= (8 - i) / 9 then
			return i
		end
	end
	return 7
end

-- 7k lane option, as the ECFN label rows (RANDOM OFF .. S-RANDOM+)
local optionRow = {
	BMSArrange_Off = 0,
	BMSArrange_Mirror = 1,
	BMSArrange_Random = 2,
	BMSArrange_CRandom = 2,
	BMSArrange_RRandom = 3,
	BMSArrange_SRandom = 4,
	BMSArrange_HRandom = 6,
}

local panel = Def.ActorFrame {
	InitCommand = function(self)
		self:zoom(zoom)
	end,
	Img("graph_bg.png", 0, 101, 290, 832),
	Img("frame.png", 0, 0, PW, PH),
}
-- AAA / AA / A lines, yellow once the score is past them for the whole song
for k, ninths in ipairs({8, 7, 6}) do
	local y = ({162, 230, 299})[k]
	panel[#panel + 1] = Frame("lines 1x6.png", 0, y, 288, 18, function()
		local border = math.ceil(total * 2 * ninths / 9)
		return (cur.ex >= border and not o2jam) and (k + 2) or (k - 1)
	end)
end
-- bars: YOU, MYBEST, PACEMAKER (left to right)
panel[#panel + 1] = Bar("bar_you.png", 62, youFrac)
panel[#panel + 1] = FinalBar(133, function()
	return pbRate
end)
panel[#panel + 1] = Bar("bar_best.png", 134, function()
	return pbRate and getBMSPBPaceEx(cur.judged, pbRate) / (total * 2) or 0
end)
panel[#panel + 1] = FinalBar(205, function()
	return targetRate
end)
panel[#panel + 1] = Bar("bar_target.png", 206, function()
	return getPacemakerPaceEx(cur.judged, targetRate, pbRate) / (total * 2)
end)

-- header: YOU and PACEMAKER EX scores
panel[#panel + 1] = Num("num_upper 11x1.png", 190, 40, 22, 22, 4, function()
	return exOrNil(cur.ex)
end, 10)
panel[#panel + 1] = Num("num_upper 11x1.png", 190, 66, 22, 22, 4, function()
	return exOrNil(totalEx(targetRate))
end, 10)

-- YOU: EX score, rate so far, lane option, DJ level
panel[#panel + 1] = Num("num_upper 11x1.png", 188, 735, 22, 22, 4, function()
	return exOrNil(cur.ex)
end, 10)
panel[#panel + 1] = Rate(760, function()
	return cur.rate
end)
panel[#panel + 1] = Frame("option 1x10.png", 14, 777, 98, 13, function()
	local po = GAMESTATE:GetPlayerState():GetPlayerOptions("ModsLevel_Stage")
	return optionRow[po:ArrangeSetting()]
end)
panel[#panel + 1] = Frame("rank 1x8.png", 208, 764, 69, 23, function()
	return djLevel(cur.rate)
end)

-- MYBEST: EX score, difference to its pace, rate
panel[#panel + 1] = Num("num_upper 11x1.png", 188, 802, 22, 22, 4, function()
	return exOrNil(totalEx(pbRate))
end, 10)
panel[#panel + 1] = Diff(168, 832, function()
	return pbRate and exOrNil(cur.ex - round(getBMSPBPaceEx(cur.judged, pbRate))) or nil
end)
panel[#panel + 1] = Rate(827, function()
	return pbRate or 0
end)

-- PACEMAKER: EX score, which one, difference to its pace, rate
panel[#panel + 1] = Num("num_upper 11x1.png", 188, 869, 22, 22, 4, function()
	return exOrNil(totalEx(targetRate))
end, 10)
panel[#panel + 1] = Frame("target 1x11.png", 14, 911, 132, 13, function()
	return targetRow
end)
-- MYBEST and goal % have no ECFN label: written out
panel[#panel + 1] = LoadFont("Common Normal") .. {
	InitCommand = function(self)
		self:halign(0):valign(0.5):xy(16, 918):diffuse(color("0.85,0.85,0.85,1"))
		setters[#setters + 1] = function()
			self:visible(targetRow == nil)
			self:settext("PACEMAKER " .. (targetText or ""))
			self:zoom(13 / math.max(self:GetHeight(), 1) * 1.1)
		end
	end,
}
panel[#panel + 1] = Diff(168, 899, function()
	return exOrNil(cur.ex - round(getPacemakerPaceEx(cur.judged, targetRate, pbRate)))
end)
panel[#panel + 1] = Rate(894, function()
	return targetRate or 0
end)

local function reset()
	cur = {ex = 0, judged = 0, rate = 0}
	loadChart()
	refresh()
end

-- top left of the panel: a position set in Customize Gameplay (key /),
-- otherwise right of the notefield (left of it when there is no room)
local function place(self)
	local mv = MovableValues or {}
	if mv.PacemakerX and mv.PacemakerY and mv.PacemakerX >= 0 and mv.PacemakerY >= 0 then
		self:xy(mv.PacemakerX, mv.PacemakerY)
		return
	end
	local cols = 7
	local scale = getNoteFieldScale and getNoteFieldScale(PLAYER_1) or 1
	local width = (64 * cols * (mv.NotefieldWidth or 1) + (mv.NotefieldSpacing or 0) * (cols - 1)) * scale
	local x = SCREEN_CENTER_X
	local screen = SCREENMAN:GetTopScreen()
	local player = screen and screen:GetChild("PlayerP1")
	if player then
		x = player:GetX() + (mv.NotefieldX or 0)
	end
	local px = x + width / 2 + 8
	if px + PW * zoom > SCREEN_WIDTH then
		px = x - width / 2 - 8 - PW * zoom
	end
	self:xy(px, 0)
	if MovableValues then
		MovableValues.PacemakerX = self:GetX()
		MovableValues.PacemakerY = self:GetY()
	end
end

return Def.ActorFrame {
	Name = "Pacemaker",
	InitCommand = function(self)
		if allowedCustomization and Movable and Movable["DeviceButton_/"] then
			for _, key in ipairs({"DeviceButton_/", "DeviceButton_'"}) do
				Movable[key].element = self
				Movable[key].condition = true
				Movable[key].Border = self:GetChild("Border")
			end
		end
	end,
	OnCommand = function(self)
		place(self)
		-- size set in Customize Gameplay (key '), from the top left
		if MovableValues and MovableValues.PacemakerZoom == nil then
			MovableValues.PacemakerZoom = 1
		end
		self:zoom((MovableValues or {}).PacemakerZoom or 1)
		reset()
	end,
	DoneLoadingNextSongMessageCommand = function(self)
		reset()
	end,
	PracticeModeResetMessageCommand = function(self)
		reset()
	end,
	BMSPaceMessageCommand = function(self, msg)
		cur.ex = msg.ex or 0
		cur.judged = msg.judged or 0
		cur.rate = msg.rate or 0
		refresh()
	end,
	panel,
	MovableBorder(PW * zoom, PH * zoom, 1, PW * zoom / 2, PH * zoom / 2),
}
