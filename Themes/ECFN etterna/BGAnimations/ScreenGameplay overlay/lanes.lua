-- 7k: the lane order this song plays on, as small white/blue keys next to
-- the bottom of the notefield (the same keys as the lane picker and the
-- site: a key is white or blue by the chart lane on it, 1 3 5 7 white,
-- 2 4 6 blue, tall or short by where it sits). Only for moved lanes
-- (Mirror, Random, R-Random, custom); S-Random and H-Random move notes one
-- by one, so they just show their name. Customize Gameplay moves it (key .)
-- and sizes it (key ;).

if not hideMSD() or GAMESTATE:GetCurrentStyle():ColumnsPerPlayer() ~= 7 then
	return Def.ActorFrame {}
end

local KW, KG = 11, 2
local KH_WHITE, KH_BLUE = 16, 12
local C_WHITE = color("#e9ecf3")
local C_BLUE = color("#2f6fe0")
local C_DARK = color("0.07,0.08,0.11,1")
local C_MUTED = color("0.75,0.8,0.9,1")

local labels = {
	BMSArrange_Mirror = "MIRROR",
	BMSArrange_Random = "RANDOM",
	BMSArrange_CRandom = "RANDOM (COLORS)",
	BMSArrange_RRandom = "R-RANDOM",
	BMSArrange_SRandom = "S-RANDOM",
	BMSArrange_HRandom = "H-RANDOM",
	BMSArrange_Custom = "CUSTOM",
}

local allowedCustomization = playerConfig:get_data(pn_to_profile_slot(PLAYER_1)).CustomizeGameplay

local function current()
	local po = GAMESTATE:GetPlayerState():GetPlayerOptions("ModsLevel_Stage")
	local label = labels[po:ArrangeSetting()]
	local order = GAMESTATE.GetBMSLaneOrder and GAMESTATE:GetBMSLaneOrder() or ""
	order = (#order == 7) and order or nil
	-- Customize Gameplay shows it even with the lanes off, so it can be moved
	if allowedCustomization and label == nil then
		return "LANE ORDER", "1234567"
	end
	return label, order
end

-- right edge and bottom of the notefield, the same sums as lanecover.lua
local function place(self)
	local cols = 7
	local mv = MovableValues or {}
	local scale = getNoteFieldScale and getNoteFieldScale(PLAYER_1) or 1
	local width = 64 * cols * (mv.NotefieldWidth or 1) + (mv.NotefieldSpacing or 0) * (cols - 1)
	local x = SCREEN_CENTER_X
	local screen = SCREENMAN:GetTopScreen()
	local player = screen and screen:GetChild("PlayerP1")
	if player then
		x = player:GetX()
	end
	self:xy(x + width * scale / 2 + 8, SCREEN_BOTTOM - 40)
end

local t = Def.ActorFrame {
	Name = "LaneOrder",
	InitCommand = function(self)
		if allowedCustomization and Movable and Movable.DeviceButton_period then
			for _, key in ipairs({"DeviceButton_period", "DeviceButton_;"}) do
				if Movable[key] then
					Movable[key].element = self
					Movable[key].condition = true
					Movable[key].Border = self:GetChild("Border")
				end
			end
		end
	end,
	OnCommand = function(self)
		-- a position set in Customize Gameplay (key .), otherwise next to
		-- the notefield
		local mv = MovableValues or {}
		if mv.LaneOrderX and mv.LaneOrderY and mv.LaneOrderX >= 0 and mv.LaneOrderY >= 0 then
			self:xy(mv.LaneOrderX, mv.LaneOrderY)
		else
			place(self)
			if MovableValues then
				MovableValues.LaneOrderX = self:GetX()
				MovableValues.LaneOrderY = self:GetY()
			end
		end
		-- size set in Customize Gameplay (key ;)
		if MovableValues and MovableValues.LaneOrderZoom == nil then
			MovableValues.LaneOrderZoom = 1
		end
		self:zoom(mv.LaneOrderZoom or 1)
		self:playcommand("Show")
	end,
	DoneLoadingNextSongMessageCommand = function(self)
		self:playcommand("Show")
	end,
	ShowCommand = function(self)
		local label, order = current()
		self:visible(label ~= nil)
	end,
	LoadFont("Common Normal") .. {
		InitCommand = function(self)
			self:halign(0):valign(1):xy(0, -KH_WHITE - 4):zoom(0.3):diffuse(C_MUTED)
		end,
		ShowCommand = function(self)
			local label = current()
			self:settext(label or "")
		end,
	},
}

for k = 1, 7 do
	local x = (k - 1) * (KW + KG)
	local h = k % 2 == 1 and KH_WHITE or KH_BLUE
	t[#t + 1] = Def.Quad {
		InitCommand = function(self)
			self:halign(0):valign(0):xy(x, -KH_WHITE):zoomto(KW, h)
		end,
		ShowCommand = function(self)
			local _, order = current()
			local d = order and tonumber(order:sub(k, k))
			self:visible(d ~= nil)
			if d then
				self:diffuse(d % 2 == 1 and C_WHITE or C_BLUE)
			end
		end,
	}
	t[#t + 1] = LoadFont("Common Normal") .. {
		InitCommand = function(self)
			self:xy(x + KW / 2, -KH_WHITE + h - 6):zoom(0.3)
		end,
		ShowCommand = function(self)
			local _, order = current()
			local d = order and order:sub(k, k)
			self:visible(d ~= nil)
			if d then
				self:settext(d):diffuse(tonumber(d) % 2 == 1 and C_DARK or color("1,1,1,1"))
			end
		end,
	}
end

-- the outline Customize Gameplay drags it by (label and keys)
t[#t + 1] = MovableBorder(7 * KW + 6 * KG, KH_WHITE + 14, 1, (7 * KW + 6 * KG) / 2, -KH_WHITE / 2 - 6)

return t
