local t = Def.ActorFrame {}
local topFrameHeight = 35
local bottomFrameHeight = 54
local borderWidth = 4
-- 7k song select: see-through bars over the ECFN background
local ecfn = Var("ecfn") == true
local frameColor = ecfn and rxColor("bg", 0.82) or getMainColor("frames")
if ecfn then
	borderWidth = 1
end
local borderColor = ecfn and rxColor("line") or getMainColor("highlight")
-- there the ECFN top bar replaces the top frame and the bottom one ends
-- before the wheel, which runs down the whole right side
-- the footer runs the whole width under the centered wheel
local bottomWidth = SCREEN_WIDTH

--Frames
if not ecfn then
	t[#t + 1] = UIElements.QuadButton(1, 1) .. {
		InitCommand = function(self)
			self:xy(0, 0):halign(0):valign(0):zoomto(SCREEN_WIDTH, topFrameHeight):diffuse(frameColor)
		end
	}
end

t[#t + 1] = UIElements.QuadButton(1, 1) .. {
	InitCommand = function(self)
		self:xy(0, SCREEN_HEIGHT):halign(0):valign(1):zoomto(bottomWidth, bottomFrameHeight):diffuse(frameColor)
	end
}

--FrameBorders
if not ecfn then
	t[#t + 1] = Def.Quad {
		InitCommand = function(self)
			self:xy(0, topFrameHeight):halign(0):valign(1):zoomto(SCREEN_WIDTH, borderWidth):diffuse(borderColor):diffusealpha(
				0.5
			)
		end
	}
end

t[#t + 1] = Def.Quad {
	InitCommand = function(self)
		self:xy(0, SCREEN_HEIGHT - bottomFrameHeight):halign(0):valign(0):zoomto(bottomWidth, borderWidth):diffuse(borderColor):diffusealpha(ecfn and 1 or 0.5)
	end
}

-- 7k song select: a 1px line between the profile and the rest
if ecfn then
	t[#t + 1] = Def.Quad {
		InitCommand = function(self)
			self:xy(ecfnX(560), SCREEN_HEIGHT - bottomFrameHeight + 8):halign(0):valign(0)
			self:zoomto(1, bottomFrameHeight - 16):diffuse(rxColor("line"))
		end
	}
end

--[[
if themeConfig:get_data().global.TipType == 2 or themeConfig:get_data().global.TipType == 3 then
	t[#t + 1] =
		LoadFont("Common Normal") ..
		{
			InitCommand = function(self)
				self:xy(SCREEN_CENTER_X, SCREEN_BOTTOM - 7):zoom(0.35):settext(
					getRandomQuotes(themeConfig:get_data().global.TipType)
				):diffuse(borderColor):diffusealpha(0):zoomy(0):maxwidth((SCREEN_WIDTH - 350) / 0.35)
			end,
			BeginCommand = function(self)
				self:sleep(2)
				self:smooth(1)
				self:diffusealpha(1)
				self:zoomy(0.35)
			end
		}
end
]]

return t
