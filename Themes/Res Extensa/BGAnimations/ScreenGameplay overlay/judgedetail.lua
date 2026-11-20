-- Live judge counter in the res extensa look: PGREAT GREAT GOOD BAD, empty
-- POOR, POOR, each with its FAST and SLOW, then max combo, combo breaks and
-- the FAST/SLOW totals. Same counting as the result screen.

local allowedCustomization = playerConfig:get_data(pn_to_profile_slot(PLAYER_1)).CustomizeGameplay
local PW, PH = 360, 352
-- panel size relative to the screen (it was drawn at 0.7 of the result's)
local zoom = SCREEN_HEIGHT / 1080 * 0.7

-- rows: PGREAT GREAT GOOD BAD, POOR (empty POOR, a press with no note),
-- FAIL (a note that went by)
local rowOf = {
	TapNoteScore_W1 = 1,
	TapNoteScore_W2 = 2,
	TapNoteScore_W3 = 3,
	TapNoteScore_W4 = 4,
	TapNoteScore_W5 = 4,
	TapNoteScore_Miss = 6,
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

local function refresh()
	for _, set in ipairs(setters) do
		set()
	end
end

-- a number that changes with refresh()
local function LiveText(font, x, y, px, align, c, get)
	local z = rxZoom(font, px)
	return LoadFont(font) .. {
		InitCommand = function(self)
			self:xy(x, y):halign(align):zoom(z):diffuse(c):settext("0")
			setters[#setters + 1] = function()
				self:settext(tostring(get()))
			end
		end,
	}
end
local function Label(font, x, y, px, align, text, c)
	return LoadFont(font) .. {
		InitCommand = function(self)
			self:xy(x, y):halign(align):zoom(rxZoom(font, px)):diffuse(c):settext(text)
		end,
	}
end

local o2 = isO2JamPlay()
local names = {"PGREAT", "GREAT", "GOOD", "BAD", "EMPTY POOR", "POOR"}
if o2 then
	names = {"COOL", "–", "GOOD", "BAD", "–", "MISS"}
end
local cols = {rxColor("pg"), rxColor("gr"), rxColor("gd"), rxColor("bd"), rxColor("pr"), rxColor("pr")}

local xName, xCount, xFast, xSlow = 20, 200, 270, 340
local panel = Def.ActorFrame {
	InitCommand = function(self)
		self:zoom(zoom):xy(-PW * zoom, -PH * zoom / 2)
	end,
	Def.Quad {
		InitCommand = function(self)
			self:halign(0):valign(0):zoomto(PW, PH):diffuse(rxColor("line"))
		end,
	},
	Def.Quad {
		InitCommand = function(self)
			self:halign(0):valign(0):xy(1, 1):zoomto(PW - 2, PH - 2):diffuse(rxColor("bg", 0.9))
		end,
	},
	Label(rxFont.normal, xFast, 24, 14, 1, "FAST", rxColor("fast")),
	Label(rxFont.normal, xSlow, 24, 14, 1, "SLOW", rxColor("slow")),
}
for k = 1, 6 do
	local y = 60 + 36 * (k - 1)
	panel[#panel + 1] = Label(rxFont.semibold, xName, y, 17, 0, names[k], names[k] == "–" and rxColor("dim") or cols[k])
	panel[#panel + 1] = LiveText(rxFont.semibold, xCount, y, 20, 1, rxColor("white"), function()
		return counts[k]
	end)
	if k > 1 then
		panel[#panel + 1] = LiveText(rxFont.normal, xFast, y, 16, 1, rxColor("text"), function()
			return fast[k]
		end)
	end
	if k > 1 and k ~= 5 then
		panel[#panel + 1] = LiveText(rxFont.normal, xSlow, y, 16, 1, rxColor("text"), function()
			return slow[k]
		end)
	end
	panel[#panel + 1] = Def.Quad {
		InitCommand = function(self)
			self:halign(0):valign(0):xy(xName, y + 17):zoomto(PW - 40, 1):diffuse(rxColor("hover"))
		end,
	}
end

-- FAST/SLOW totals leave PGREAT out like the result screen
local function total(t)
	return t[2] + t[3] + t[4] + t[5] + t[6]
end
do
	local y = 60 + 36 * 6 + 8
	panel[#panel + 1] = Label(rxFont.normal, xName, y, 14, 0, "MAX COMBO", rxColor("muted"))
	panel[#panel + 1] = LiveText(rxFont.semibold, xCount, y, 17, 1, rxColor("text"), function()
		return maxCombo
	end)
	panel[#panel + 1] = LiveText(rxFont.semibold, xFast, y, 16, 1, rxColor("fast"), function()
		return total(fast)
	end)
	panel[#panel + 1] = LiveText(rxFont.semibold, xSlow, y, 16, 1, rxColor("slow"), function()
		return total(slow)
	end)
	y = y + 30
	panel[#panel + 1] = Label(rxFont.normal, xName, y, 14, 0, "COMBO BREAK", rxColor("muted"))
	panel[#panel + 1] = LiveText(rxFont.semibold, xCount, y, 17, 1, rxColor("text"), function()
		return counts[4] + counts[6]
	end)
end

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
		if k == 6 or (msg.Offset and msg.Offset > 0) then
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
		counts[5] = counts[5] + 1
		fast[5] = fast[5] + 1
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
