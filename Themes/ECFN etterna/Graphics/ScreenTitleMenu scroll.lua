-- a title menu choice drawn as a silver bar shaped like the ECFN wheel bars
-- (Graphics/_title bar 1x2.png: normal, selected) with its number on the
-- left. The selected one slides left inside the skin's glowing cursor, like
-- the song select. Sizes are in the skin's 1920x1080 space.
local gc = Var("GameCommand")
local s = ecfnScale()
local dir = THEME:GetCurrentThemeDirectory()
if dir:sub(1, 1) ~= "/" then
	dir = "/" .. dir
end
local cursor = dir .. "BGAnimations/ScreenSelectMusic decorations/ecfn/cursor.png"
local index = (gc.GetIndex and gc:GetIndex() or 0) + 1

local function barText(x, h)
	return function(self)
		self:halign(0):x(x * s):y(1 * s)
		local txt = self:GetText()
		self:settext("Ag")
		self.z = h * s * 0.8 / self:GetHeight()
		self:settext(txt):zoom(self.z)
		self:shadowlength(2 * s):shadowcolor(color("0,0,0,0.75"))
	end
end

local function focusVisible(self, on)
	self:visible(on)
end

return Def.ActorFrame {
	GainFocusCommand = function(self)
		self:finishtweening():decelerate(0.1):x(-40 * s)
	end,
	LoseFocusCommand = function(self)
		self:finishtweening():decelerate(0.1):x(0)
	end,
	Def.Sprite {
		Texture = THEME:GetPathG("", "_title bar 1x2"),
		InitCommand = function(self)
			self:animate(false):setstate(0):halign(0):zoomto(730 * s, 52 * s)
		end,
		GainFocusCommand = function(self)
			self:setstate(1)
		end,
		LoseFocusCommand = function(self)
			self:setstate(0)
		end,
	},
	Def.Sprite {
		Texture = cursor,
		InitCommand = function(self)
			self:halign(0):x(-10 * s):zoomto(712 * s, 83 * s):visible(false)
		end,
		GainFocusCommand = function(self) focusVisible(self, true) end,
		LoseFocusCommand = function(self) focusVisible(self, false) end,
	},
	Def.Sprite {
		Texture = cursor,
		InitCommand = function(self)
			self:halign(0):x(-10 * s):zoomto(712 * s, 83 * s):blend("BlendMode_Add"):visible(false)
			self:diffuseshift():effectcolor1(color("1,1,1,0")):effectcolor2(color("1,1,1,0.6")):effectperiod(2.5)
		end,
		GainFocusCommand = function(self) focusVisible(self, true) end,
		LoseFocusCommand = function(self) focusVisible(self, false) end,
	},
	LoadFont("ECFN Bar") .. {
		Text = string.format("%02d", index),
		InitCommand = function(self)
			barText(58, 22)(self)
		end,
		GainFocusCommand = function(self)
			self:diffuse(color("#9fd0ff"))
		end,
		LoseFocusCommand = function(self)
			self:diffuse(color("#d0dcf0"))
		end,
	},
	LoadFont("ECFN Bar") .. {
		Text = THEME:GetString("ScreenTitleMenu", gc:GetText()),
		InitCommand = function(self)
			barText(130, 26)(self)
			self:maxwidth(440 * s / self.z)
		end,
		GainFocusCommand = function(self)
			self:diffuse(color("#ffffff"))
		end,
		LoseFocusCommand = function(self)
			self:diffuse(color("#e8eef8"))
		end,
	},
}
