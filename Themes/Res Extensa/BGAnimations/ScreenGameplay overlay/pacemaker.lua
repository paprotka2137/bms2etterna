-- 7k: the score graph (pacemaker) next to the notefield in the res extensa
-- look: bars for YOU, MY BEST and the PACEMAKER growing as the song goes,
-- the AAA / AA / A lines, the current DJ level and the EX scores, rates and
-- differences under it. 290x933 in the 1920x1080 space scaled to the screen.
-- The pacemaker is picked in Player Options (Scripts/BMSPacemaker.lua); the
-- scores come from WifeJudgmentSpotting.lua (BMSPace message). Customize
-- Gameplay moves it (key /) and sizes it (key ').

if not hideMSD() or not playerConfig:get_data(pn_to_profile_slot(PLAYER_1)).PacemakerGraph then
	return Def.ActorFrame {}
end

local allowedCustomization = playerConfig:get_data(pn_to_profile_slot(PLAYER_1)).CustomizeGameplay
local o2jam = isO2JamPlay()
local PW, PH = 290, 933
local zoom = SCREEN_HEIGHT / 1080
local BAR_Y, BAR_H = 112, 600

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
local function paceEx(rate)
	return round((rate or 0) * cur.judged * 2)
end
local function totalEx(rate)
	return round((rate or 0) * total * 2)
end
local function exOrNil(v)
	if o2jam then
		return nil
	end
	return v
end
local function rateText(r)
	return string.format("%.2f%%", (r or 0) * 100)
end
local function signed(v)
	if v == nil then
		return ""
	elseif v > 0 then
		return "+" .. v
	elseif v < 0 then
		return "−" .. -v
	end
	return "±0"
end

-- text set by get() on refresh; c is a color or a function giving one
local function LiveText(font, x, y, px, align, maxw, get, c)
	local z = rxZoom(font, px)
	return LoadFont(font) .. {
		InitCommand = function(self)
			self:xy(x, y):halign(align):zoom(z):maxwidth(maxw / z)
			if type(c) ~= "function" then
				self:diffuse(c or rxColor("text"))
			end
			setters[#setters + 1] = function()
				local v = get()
				self:settext(v ~= nil and tostring(v) or "")
				if type(c) == "function" then
					self:diffuse(c())
				end
			end
		end,
	}
end
local function Label(x, y, text, align)
	return LoadFont(rxFont.normal) .. {
		InitCommand = function(self)
			self:xy(x, y):halign(align or 0):zoom(rxZoom(rxFont.normal, 13)):diffuse(rxColor("muted")):settext(text)
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

-- a bar growing from the bottom of the graph to get() (0..1)
local function Bar(x, c, get)
	return Def.Quad {
		InitCommand = function(self)
			self:halign(0):valign(1):xy(x, BAR_Y + BAR_H):zoomto(56, 0):diffuse(c)
			setters[#setters + 1] = function()
				self:zoomy(BAR_H * math.max(0, math.min(get() or 0, 1)))
			end
		end,
	}
end

local function youFrac()
	return cur.rate * cur.judged / total
end

local djNames = {"AAA", "AA", "A", "B", "C", "D", "E", "F"}
local function djLevel(rate)
	for i = 0, 6 do
		if rate >= (8 - i) / 9 then
			return i
		end
	end
	return 7
end

local arrangeNames = {
	BMSArrange_Off = "NORMAL",
	BMSArrange_Mirror = "MIRROR",
	BMSArrange_Random = "RANDOM",
	BMSArrange_CRandom = "RANDOM (COLORS)",
	BMSArrange_RRandom = "R-RANDOM",
	BMSArrange_SRandom = "S-RANDOM",
	BMSArrange_HRandom = "H-RANDOM",
}

local youC, bestC, paceC = rxColor("text"), rxColor("muted"), rxColor("gr")

local panel = Def.ActorFrame {
	InitCommand = function(self)
		self:zoom(zoom)
	end,
	Box(0, 0, PW, PH, rxColor("line")),
	Box(1, 1, PW - 2, PH - 2, rxColor("bg", 0.88)),
	-- header: YOU and the PACEMAKER's final EX score
	Label(16, 30, "YOU"),
	LiveText(rxFont.semibold, PW - 16, 30, 24, 1, 160, function()
		return o2jam and rateText(cur.rate) or cur.ex
	end, rxColor("white")),
	Label(16, 66, "PACEMAKER"),
	LiveText(rxFont.semibold, PW - 16, 66, 24, 1, 160, function()
		return o2jam and rateText(targetRate) or totalEx(targetRate)
	end, paceC),
	Box(16, 92, PW - 32, 1, rxColor("line")),
	-- graph ground
	Box(16, BAR_Y, PW - 32, BAR_H, rxColor("panel")),
}
-- AAA / AA / A lines, gold once the score is past them for the whole song
for k, ninths in ipairs({8, 7, 6}) do
	local y = BAR_Y + BAR_H * (1 - ninths / 9)
	local passed = function()
		return cur.ex >= math.ceil(total * 2 * ninths / 9) and not o2jam
	end
	panel[#panel + 1] = Def.Quad {
		InitCommand = function(self)
			self:halign(0):valign(0):xy(16, y):zoomto(PW - 32, 1)
			setters[#setters + 1] = function()
				self:diffuse(passed() and rxColor("gr") or rxColor("line2"))
			end
		end,
	}
	panel[#panel + 1] = LiveText(rxFont.semibold, 22, y - 10, 13, 0, 60, function()
		return djNames[k]
	end, function()
		return passed() and rxColor("gr") or rxColor("dim")
	end)
end
-- final scores of the paces, dim, then the bars that grow
panel[#panel + 1] = Bar(134, rxColor("muted", 0.18), function()
	return pbRate
end)
panel[#panel + 1] = Bar(206, rxColor("gr", 0.18), function()
	return targetRate
end)
panel[#panel + 1] = Bar(62, youC, youFrac)
panel[#panel + 1] = Bar(134, bestC, function()
	return (pbRate or 0) * cur.judged / total
end)
panel[#panel + 1] = Bar(206, paceC, function()
	return (targetRate or 0) * cur.judged / total
end)
for i, name in ipairs({"YOU", "BEST", "PACE"}) do
	panel[#panel + 1] = Label(62 + 72 * (i - 1) + 28, BAR_Y + BAR_H + 14, name, 0.5)
end

-- rows under the graph: YOU, MY BEST, PACEMAKER
local function Row(y, title, titleC)
	return LoadFont(rxFont.semibold) .. {
		InitCommand = function(self)
			self:xy(16, y):halign(0):zoom(rxZoom(rxFont.semibold, 15)):diffuse(titleC):settext(title)
		end,
	}
end
do
	local y = 760
	panel[#panel + 1] = Box(16, y - 18, PW - 32, 1, rxColor("line"))
	panel[#panel + 1] = Row(y, "YOU", youC)
	panel[#panel + 1] = LiveText(rxFont.semibold, PW - 16, y, 20, 1, 120, function()
		return exOrNil(cur.ex)
	end, rxColor("white"))
	panel[#panel + 1] = LiveText(rxFont.normal, 16, y + 26, 15, 0, 120, function()
		return rateText(cur.rate)
	end, rxColor("text"))
	panel[#panel + 1] = LiveText(rxFont.bold, PW - 16, y + 26, 20, 1, 80, function()
		return djNames[djLevel(cur.rate) + 1]
	end, rxColor("white"))
	panel[#panel + 1] = LiveText(rxFont.normal, 16, y + 50, 13, 0, 200, function()
		local po = GAMESTATE:GetPlayerState():GetPlayerOptions("ModsLevel_Stage")
		return arrangeNames[po:ArrangeSetting()] or ""
	end, rxColor("muted"))

	y = 838
	panel[#panel + 1] = Box(16, y - 18, PW - 32, 1, rxColor("line"))
	panel[#panel + 1] = Row(y, "MY BEST", bestC)
	panel[#panel + 1] = LiveText(rxFont.semibold, PW - 16, y, 20, 1, 120, function()
		return exOrNil(totalEx(pbRate))
	end, rxColor("text"))
	panel[#panel + 1] = LiveText(rxFont.normal, 16, y + 26, 15, 0, 120, function()
		return pbRate and rateText(pbRate) or "—"
	end, rxColor("muted"))
	panel[#panel + 1] = LiveText(rxFont.semibold, PW - 16, y + 26, 17, 1, 120, function()
		return pbRate and signed(exOrNil(cur.ex - paceEx(pbRate))) or ""
	end, function()
		return (cur.ex - paceEx(pbRate)) >= 0 and rxColor("gd") or rxColor("pr")
	end)

	y = 896
	panel[#panel + 1] = Box(16, y - 18, PW - 32, 1, rxColor("line"))
	panel[#panel + 1] = LiveText(rxFont.semibold, 16, y, 15, 0, 150, function()
		return targetText or "PACEMAKER"
	end, paceC)
	panel[#panel + 1] = LiveText(rxFont.normal, 16, y + 22, 13, 0, 120, function()
		return rateText(targetRate)
	end, rxColor("muted"))
	panel[#panel + 1] = LiveText(rxFont.semibold, PW - 16, y, 17, 1, 120, function()
		return signed(exOrNil(cur.ex - paceEx(targetRate)))
	end, function()
		return (cur.ex - paceEx(targetRate)) >= 0 and rxColor("gd") or rxColor("pr")
	end)
end

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
