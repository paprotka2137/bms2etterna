-- 7k: the decide screen between the song select and gameplay, in the look of
-- the res extensa website: the chart's facts set in big Inter on the near
-- black page, a 1px line drawn across, then out to black. Placed in 1920x1080
-- space and scaled to the screen. Everything else gets nothing here.
if not hideMSD() then
	return Def.ActorFrame {}
end

local W, H = 1920, 1080
local scale = SCREEN_HEIGHT / H

local song = GAMESTATE:GetCurrentSong()
local steps = GAMESTATE:GetCurrentSteps()
local level, row = "", 0
if song then
	local n
	n, row = getBMSLevelDisplay(song, steps)
	local _, name = getBMSLevel(song, steps)
	if name and name ~= "" then
		level = name
	elseif n then
		level = tostring(n)
	end
end

local X = 160

-- text that fades and slides in after `delay`
local function Text(font, y, px, get, c, delay)
	local z = rxZoom(font, px)
	return LoadFont(font) .. {
		InitCommand = function(self)
			self:halign(0):valign(0.5):xy(X + 24, y):zoom(z):maxwidth((W - 2 * X) / z)
			self:settext(song and (get() or "") or ""):diffuse(c or rxColor("text")):diffusealpha(0)
		end,
		OnCommand = function(self)
			self:sleep(delay or 0):decelerate(0.35):x(X):diffusealpha(1)
		end,
	}
end

local t = Def.ActorFrame {
	InitCommand = function(self)
		self:xy((SCREEN_WIDTH - W * scale) / 2, 0):zoom(scale)
	end,
	OnCommand = function(self)
		self:xy((SCREEN_WIDTH - W * scale) / 2, 0):zoom(scale)
	end,
}

-- page, wider than the frame so a non 16:9 screen is covered too
t[#t + 1] = Def.Quad {
	InitCommand = function(self)
		self:xy(W / 2, H / 2):zoomto(W * 2, H):diffuse(rxColor("bg"))
	end,
}

-- header and footer lines like the other screens
t[#t + 1] = rxHLine(0, 72, W, rxColor("line"))
t[#t + 1] = rxLabel(rxFont.semibold, 40, 36, 22, 0, "res extensa", rxColor("text"))
t[#t + 1] = rxLabel(rxFont.normal, 1880, 36, 18, 1, "now loading", rxColor("muted"))
t[#t + 1] = rxHLine(0, H - 48, W, rxColor("line"))

local midY = 560

-- level chip and genre above the title
t[#t + 1] = Def.ActorFrame {
	InitCommand = function(self)
		self:xy(X + 24, midY - 150):diffusealpha(0)
	end,
	OnCommand = function(self)
		self:decelerate(0.35):x(X):diffusealpha(1)
	end,
	Def.Quad {
		InitCommand = function(self)
			self:halign(0):valign(0.5):zoomto(6, 28):diffuse(rxLevelColor(row))
		end,
	},
	LoadFont(rxFont.bold) .. {
		InitCommand = function(self)
			self:halign(0):valign(0.5):x(20):zoom(rxZoom(rxFont.bold, 28)):settext(level or ""):diffuse(rxLevelColor(row))
		end,
	},
	LoadFont(rxFont.normal) .. {
		InitCommand = function(self)
			local z = rxZoom(rxFont.normal, 22)
			self:halign(0):valign(0.5):x(200):zoom(z):maxwidth(1200 / z):diffuse(rxColor("muted"))
			self:settext(song and string.upper(song:GetGenre() or "") or "")
		end,
	},
}

t[#t + 1] = Text(rxFont.bold, midY - 70, 84, function() return song:GetDisplayMainTitle() end, rxColor("white"), 0.05)
t[#t + 1] = Text(rxFont.normal, midY + 4, 26, function() return song:GetDisplaySubTitle() end, rxColor("muted"), 0.1)

-- the line drawn across under the title
t[#t + 1] = Def.Quad {
	InitCommand = function(self)
		self:halign(0):valign(0):xy(X, midY + 40):zoomto(0, 1):diffuse(rxColor("line2"))
	end,
	OnCommand = function(self)
		self:sleep(0.1):decelerate(0.6):zoomto(W - 2 * X, 1)
	end,
}
t[#t + 1] = Def.Quad {
	InitCommand = function(self)
		self:halign(0):valign(0):xy(X, midY + 39):zoomto(0, 3):diffuse(rxColor("white"))
	end,
	OnCommand = function(self)
		self:sleep(0.1):decelerate(0.6):zoomto(64, 3)
	end,
}

t[#t + 1] = Text(rxFont.semibold, midY + 84, 30, function() return song:GetDisplayArtist() end, rxColor("text"), 0.15)

-- notes and length on the right under the line
if song and steps then
	local rate = getCurRateValue()
	local notes = steps:GetRadarValues(PLAYER_1):GetValue("RadarCategory_Notes")
	local len = SecondsToMMSS(steps:GetLengthSeconds() / rate)
	local info = string.format("%d notes   ·   %s", notes, len)
	if rate ~= 1 then
		info = info .. string.format("   ·   %.2fx", rate)
	end
	t[#t + 1] = LoadFont(rxFont.normal) .. {
		InitCommand = function(self)
			self:halign(1):valign(0.5):xy(W - X, midY + 84):zoom(rxZoom(rxFont.normal, 22))
			self:settext(info):diffuse(rxColor("muted")):diffusealpha(0)
		end,
		OnCommand = function(self)
			self:sleep(0.2):linear(0.3):diffusealpha(1)
		end,
	}
end

-- out to black at the end (the screen waits 2.5 seconds)
t[#t + 1] = Def.Quad {
	InitCommand = function(self)
		self:xy(W / 2, H / 2):zoomto(W * 2, H):diffuse(color("0,0,0,0"))
	end,
	OnCommand = function(self)
		self:sleep(1.5):decelerate(0.5):diffusealpha(1)
	end,
}

-- the screen sets up its decorations frame itself, the scaling sits inside it
return Def.ActorFrame {t}
