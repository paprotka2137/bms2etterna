local t = Def.ActorFrame {}

-- 7k: the ECFN song select background, no Til Death frame or wheel bar
if hideMSD() then
	local dir = THEME:GetCurrentThemeDirectory()
	if dir:sub(1, 1) ~= "/" then
		dir = "/" .. dir
	end
	t[#t + 1] = Def.Quad {
		InitCommand = function(self)
			self:halign(0):valign(0):zoomto(SCREEN_WIDTH, SCREEN_HEIGHT):diffuse(color("0,0,0,1"))
		end,
		BeginCommand = function(self)
			SCREENMAN:GetTopScreen():AddInputCallback(MPinput)
		end,
	}
	t[#t + 1] = Def.Sprite {
		Texture = dir .. "BGAnimations/ScreenSelectMusic decorations/ecfn/background.png",
		InitCommand = function(self)
			self:halign(0):valign(0):zoomto(SCREEN_WIDTH, SCREEN_HEIGHT)
		end,
	}
	return t
end

--bg
t[#t + 1] = LoadActor(THEME:GetPathG("", "_OptionsScreen")) ..  {
	OnCommand = function(self)
		self:FullScreen():zoom(1):diffusealpha(1)
	end
}

--black dim behind songwheel text
t[#t + 1] = Def.Quad {
	InitCommand = function(self)
		self:xy(SCREEN_WIDTH, 0):halign(1):valign(0):zoomto(capWideScale(get43size(350), 350), SCREEN_HEIGHT)
		self:diffuse(0.1,0.1,0.1,0.4)
	end,
	BeginCommand= function(self)
		SCREENMAN:GetTopScreen():AddInputCallback(MPinput)
	end
}
--vertical bar left of songwheel
t[#t + 1] = Def.Quad {
	InitCommand = function(self)
		self:xy(SCREEN_WIDTH - capWideScale(get43size(350), 350), 0):halign(0):valign(0):zoomto(4, SCREEN_HEIGHT)
		self:diffuse(getMainColor("highlight")):diffusealpha(0.5)
	end
}

return t
