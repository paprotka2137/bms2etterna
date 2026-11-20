-- 7k: the selected bar gets 1px lines above and below and a marker at its
-- right edge, in plain gray. The marker
-- pulses on the beat of the preview. The highlight is drawn over the bar, so
-- its fill stays see-through. Only effects here, no tweens: the wheel stops
-- placing its items while anything in it is tweening.
if hideMSD() then
	local s = ecfnScale()
	local BW, BH = 640, 76
	local function paint(self)
		local c = rxColor("text")
		self:GetChild("Fill"):diffuse(rxColor("white", 0.06))
		self:GetChild("Top"):diffuse(c)
		self:GetChild("Bottom"):diffuse(c)
		self:GetChild("Marker"):diffuse(c):effectclock("beat"):diffuseshift()
			:effectcolor1(c):effectcolor2(rxColor("text", 0.35)):effectperiod(1)
	end
	return Def.ActorFrame {
		BeginCommand = paint,
		CurrentSongChangedMessageCommand = paint,
		CurrentStepsChangedMessageCommand = paint,
		Def.Quad {
			Name = "Fill",
			InitCommand = function(self)
				self:halign(0):zoomto(BW * s, (BH - 2) * s):diffuse(rxColor("white", 0.06))
			end,
		},
		Def.Quad {
			Name = "Top",
			InitCommand = function(self)
				self:halign(0):valign(0):y(-BH / 2 * s):zoomto(BW * s, math.max(1, s)):diffuse(rxColor("text"))
			end,
		},
		Def.Quad {
			Name = "Bottom",
			InitCommand = function(self)
				self:halign(0):valign(1):y(BH / 2 * s):zoomto(BW * s, math.max(1, s)):diffuse(rxColor("text"))
			end,
		},
		Def.Quad {
			Name = "Marker",
			InitCommand = function(self)
				-- on the right edge: the left one is the lamp's
				self:halign(1):x(BW * s):zoomto(6 * s, BH * s):diffuse(rxColor("white"))
			end,
		},
	}
end

return Def.ActorFrame {
	Def.Quad {
		Name = "Horizontal",
		InitCommand = function(self)
			self:xy(0, -2):zoomto(854, 34):halign(0)
		end,
		SetCommand = function(self)
			self:diffuseramp()
			self:effectcolor1(color("#FFFFFF33"))
			self:effectcolor2(color("#FFFFFF33"))
		end,
		BeginCommand = function(self)
			self:queuecommand("Set")
		end,
		OffCommand = function(self)
			self:visible(false)
		end
	}
}
