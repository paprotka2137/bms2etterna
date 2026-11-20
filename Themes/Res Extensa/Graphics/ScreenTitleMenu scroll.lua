-- a title menu choice as a row of the site's plain list: number, name, a
-- 1px line under it. The selected one gets the wheel's white marker and
-- slides a little left. Sizes are in 1920x1080 space.
local gc = Var("GameCommand")
local s = ecfnScale()
local index = (gc.GetIndex and gc:GetIndex() or 0) + 1
local w, h = 640 * s, 52 * s

return Def.ActorFrame {
	GainFocusCommand = function(self)
		self:finishtweening():decelerate(0.1):x(-16 * s)
	end,
	LoseFocusCommand = function(self)
		self:finishtweening():decelerate(0.1):x(0)
	end,
	-- hover fill and marker of the selected row
	Def.Quad {
		InitCommand = function(self)
			self:halign(0):zoomto(w, h):diffuse(rxColor("white", 0.05)):visible(false)
		end,
		GainFocusCommand = function(self) self:visible(true) end,
		LoseFocusCommand = function(self) self:visible(false) end,
	},
	Def.Quad {
		InitCommand = function(self)
			self:halign(0):zoomto(4 * s, h):diffuse(rxColor("white")):visible(false)
		end,
		GainFocusCommand = function(self) self:visible(true) end,
		LoseFocusCommand = function(self) self:visible(false) end,
	},
	-- line under the row
	Def.Quad {
		InitCommand = function(self)
			self:halign(0):valign(0):y(h / 2):zoomto(w, 1):diffuse(rxColor("line"))
		end,
	},
	LoadFont(rxFont.normal) .. {
		Text = string.format("%02d", index),
		InitCommand = function(self)
			self:halign(0):x(24 * s):zoom(rxZoom(rxFont.normal, 18 * s)):diffuse(rxColor("dim"))
		end,
		GainFocusCommand = function(self) self:diffuse(rxColor("muted")) end,
		LoseFocusCommand = function(self) self:diffuse(rxColor("dim")) end,
	},
	LoadFont(rxFont.semibold) .. {
		Text = THEME:GetString("ScreenTitleMenu", gc:GetText()),
		InitCommand = function(self)
			local z = rxZoom(rxFont.semibold, 24 * s)
			self:halign(0):x(76 * s):zoom(z):maxwidth((w - 100 * s) / z):diffuse(rxColor("muted"))
		end,
		GainFocusCommand = function(self) self:diffuse(rxColor("white")) end,
		LoseFocusCommand = function(self) self:diffuse(rxColor("muted")) end,
	},
}
