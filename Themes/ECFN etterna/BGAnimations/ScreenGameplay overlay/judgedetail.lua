-- The JUDGE DETAIL panel of the ECFN result screen, counted live during play.
-- Graphics and layout come from ScreenEvaluation decorations/ecfn.lua, in the
-- skin's 1920x1080 space with the panel's top left corner moved to 0,0.

local dir = THEME:GetCurrentThemeDirectory()
if dir:sub(1, 1) ~= "/" then
	dir = "/" .. dir
end
dir = dir .. "BGAnimations/ScreenEvaluation decorations/ecfn/"

local allowedCustomization = playerConfig:get_data(pn_to_profile_slot(PLAYER_1)).CustomizeGameplay
local PX, PY, PW, PH = 3, 676, 514, 369
-- panel size relative to the result screen
local zoom = SCREEN_HEIGHT / 1080 * 0.7

-- rows: PGREAT GREAT GOOD BAD POOR, empty POOR
local rowOf = {
	TapNoteScore_W1 = 1,
	TapNoteScore_W2 = 2,
	TapNoteScore_W3 = 3,
	TapNoteScore_W4 = 4,
	TapNoteScore_W5 = 4,
	TapNoteScore_Miss = 5,
}
local counts, fast, slow
local maxCombo
local setters = {}

local function reset()
	counts = {0, 0, 0, 0, 0, 0}
	fast = {0, 0, 0, 0, 0, 0}
	slow = {0, 0, 0, 0, 0, 0}
	maxCombo = 0
end
reset()

-- bitmap number like Num of the result screen, right aligned with the faded
-- 0 of the sheet (frame 10) in front, but its glyphs change with set()
local function LiveNum(file, x, y, gw, gh, digits, get)
	local glyphs = {}
	local f = Def.ActorFrame {
		InitCommand = function(self)
			self:xy(x - PX, y - PY)
		end,
	}
	for i = 1, digits do
		f[#f + 1] = Def.Sprite {
			Texture = dir .. file,
			InitCommand = function(self)
				self:animate(false):setstate(10):halign(0):valign(0):x((i - 1) * gw):zoomto(gw, gh)
				glyphs[i] = self
			end,
		}
	end
	setters[#setters + 1] = function()
		local s = tostring(math.floor(math.abs(get()) + 0.5))
		if #s > digits then
			s = s:sub(-digits)
		end
		local first = digits - #s + 1
		for i = 1, digits do
			glyphs[i]:setstate(i >= first and tonumber(s:sub(i - first + 1, i - first + 1)) or 10)
		end
	end
	return f
end

local function Img(file, x, y, w, h)
	return Def.Sprite {
		Texture = dir .. file,
		InitCommand = function(self)
			self:halign(0):valign(0):xy(x - PX, y - PY):zoomto(w, h)
		end,
	}
end

local function refresh()
	for _, set in ipairs(setters) do
		set()
	end
end

local panel = Def.ActorFrame {
	InitCommand = function(self)
		self:zoom(zoom):xy(-PW * zoom, -PH * zoom / 2)
	end,
	Img("judge_detail.png", PX, PY, PW, PH),
	Def.Sprite {
		Texture = dir .. "p_great 1x4.png",
		InitCommand = function(self)
			self:halign(0):valign(0):xy(55 - PX, 746 - PY):zoomto(91, 22)
			self:SetAllStateDelays(0.25 / 4)
		end,
	},
	Img("detail_fast.png", 403, 732, 31, 8),
	Img("detail_slow.png", 317, 732, 36, 8),
}
for k = 1, 6 do
	local y = 34 * (k - 1)
	panel[#panel + 1] = LiveNum("num_judge 11x1.png", 170, 747 + y, 22, 20, 4, function()
		return counts[k]
	end)
	panel[#panel + 1] = LiveNum("num_fast 11x1.png", 390, 750 + y, 14, 13, 4, function()
		return fast[k]
	end)
	panel[#panel + 1] = LiveNum("num_slow 11x1.png", 308, 750 + y, 14, 13, 4, function()
		return slow[k]
	end)
end
-- FAST/SLOW totals leave PGREAT out like the result screen
local function total(t)
	return t[2] + t[3] + t[4] + t[5] + t[6]
end
panel[#panel + 1] = LiveNum("num_small 11x1.png", 199, 954, 14, 13, 4, function()
	return maxCombo
end)
panel[#panel + 1] = LiveNum("num_small 11x1.png", 199, 977, 14, 13, 4, function()
	return counts[4] + counts[5]
end)
panel[#panel + 1] = LiveNum("num_small 11x1.png", 390, 954, 14, 13, 4, function()
	return total(fast)
end)
panel[#panel + 1] = LiveNum("num_small 11x1.png", 390, 977, 14, 13, 4, function()
	return total(slow)
end)

local function resetCommand(self)
	reset()
	refresh()
end

-- the X/Y of the judge counter is the right edge of the panel, centered
return Def.ActorFrame {
	Name = "JudgeCounter",
	InitCommand = function(self)
		if allowedCustomization then
			Movable.DeviceButton_p.element = self
			Movable.DeviceButton_p.condition = true
		end
		self:xy(MovableValues.JudgeCounterX, MovableValues.JudgeCounterY)
	end,
	OnCommand = resetCommand,
	PracticeModeResetCommand = resetCommand,
	PracticeModeResetMessageCommand = resetCommand,
	JudgmentMessageCommand = function(self, msg)
		if msg.HoldNoteScore then
			return
		end
		local k = rowOf[msg.Judgment]
		if k == nil then
			return
		end
		counts[k] = counts[k] + 1
		-- misses went by, beatoraja counts them as late
		if k == 5 or (msg.Offset and msg.Offset > 0) then
			slow[k] = slow[k] + 1
		elseif msg.Offset and msg.Offset < 0 then
			fast[k] = fast[k] + 1
		end
		refresh()
	end,
	-- LR2 BADs that leave the note in the lane
	LR2BadMessageCommand = function(self, msg)
		counts[4] = counts[4] + 1
		if msg.Offset and msg.Offset > 0 then
			slow[4] = slow[4] + 1
		else
			fast[4] = fast[4] + 1
		end
		refresh()
	end,
	-- empty POORs are presses before the note
	EmptyPoorMessageCommand = function(self)
		counts[6] = counts[6] + 1
		fast[6] = fast[6] + 1
		refresh()
	end,
	ComboChangedMessageCommand = function(self)
		local pss = STATSMAN:GetCurStageStats():GetPlayerStageStats()
		if pss:MaxCombo() ~= maxCombo then
			maxCombo = pss:MaxCombo()
			refresh()
		end
	end,
	panel,
	MovableBorder(PW * zoom, PH * zoom, 1, -PW * zoom / 2, 0),
}
