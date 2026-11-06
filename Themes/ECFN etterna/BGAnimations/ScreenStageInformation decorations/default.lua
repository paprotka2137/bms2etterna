-- 7k: the decide screen of the beatoraja ECFN skin (decide/decidemain.lua)
-- between the song select and gameplay. Placed in the skin's 1920x1080 space
-- (its y counted from the bottom, turned into top edges here) and scaled to
-- the screen. The smoke is the skin's 60 frame animation, halved and packed
-- into four 3x5 sheets. Everything else gets nothing here, like before.
if not hideMSD() then
	return Def.ActorFrame {}
end

local dir = THEME:GetCurrentThemeDirectory()
if dir:sub(1, 1) ~= "/" then
	dir = "/" .. dir
end
dir = dir .. "BGAnimations/ScreenStageInformation decorations/"
local W, H = 1920, 1080
local scale = SCREEN_HEIGHT / H

local song = GAMESTATE:GetCurrentSong()
local steps = GAMESTATE:GetCurrentSteps()

-- text right aligned at x 1843, its bottom at the skin's y
local function Text(y, h, get, alpha, font)
	return LoadFont(font or "ECFN Normal") .. {
		InitCommand = function(self)
			self:halign(1):valign(1):xy(1843, H - y)
			self:settext("Ag")
			local z = h / self:GetHeight() * 1.25
			self:zoom(z):maxwidth(1200 / z)
			self:settext(song and get() or "")
			self:diffusealpha(0)
		end,
		OnCommand = function(self)
			self:linear(0.3):diffusealpha(alpha or 1)
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

t[#t + 1] = Def.Quad {
	InitCommand = function(self)
		self:halign(0):valign(0):zoomto(W, H):diffuse(color("0,0,0,1"))
	end,
}
t[#t + 1] = Def.Sprite {
	Texture = dir .. "background.png",
	InitCommand = function(self)
		self:halign(0):valign(0):zoomto(W, H):diffusealpha(40 / 255)
	end,
}

-- the smoke, 60 frames over 2.2 seconds
do
	local smoke = Def.ActorFrame {
		InitCommand = function(self)
			self.time = 0
			self:SetUpdateFunction(function(f, delta)
				f.time = f.time + delta
				local frame = math.floor(f.time / 2.2 * 60) % 60
				local sheet = math.floor(frame / 15)
				for i = 0, 3 do
					local s = f:GetChild("S" .. i)
					s:visible(i == sheet)
					if i == sheet then
						s:setstate(frame % 15)
					end
				end
			end)
		end,
	}
	for i = 0, 3 do
		smoke[#smoke + 1] = Def.Sprite {
			Name = "S" .. i,
			Texture = dir .. "smoke" .. i .. " 3x5.png",
			InitCommand = function(self)
				self:animate(false):halign(0):valign(0):zoomto(W, H):visible(i == 0)
			end,
		}
	end
	t[#t + 1] = smoke
end

-- song information, right aligned
local level = ""
if song then
	local _, name = getBMSLevel(song, steps)
	level = name
end
t[#t + 1] = Text(660, 24, function() return song:GetGenre() end)
t[#t + 1] = Text(568, 40, function() return song:GetDisplayMainTitle() end, 1, "ECFN Large")
t[#t + 1] = Text(530, 24, function() return song:GetDisplaySubTitle() end, 100 / 255)
t[#t + 1] = Text(482, 26, function() return song:GetDisplayArtist() end)
t[#t + 1] = Text(443, 20, function() return level end)

local function Part(file, x, y, w, h, alpha)
	return Def.Sprite {
		Texture = dir .. file,
		InitCommand = function(self)
			self:halign(0):valign(0):xy(x, H - y - h):zoomto(w, h):diffusealpha(0)
		end,
		OnCommand = function(self)
			self:linear(0.3):diffusealpha(alpha)
		end,
	}
end
t[#t + 1] = Part("freestage.png", 1440, 688, 432, 73, 205 / 255)
t[#t + 1] = Part("songbar.png", 66, 509, 1791, 25, 200 / 255)
t[#t + 1] = Part("nextstage.png", 1282, 370, 567, 51, 1)

-- the flash sweeping left over the title
t[#t + 1] = Def.Sprite {
	Texture = dir .. "flash.png",
	InitCommand = function(self)
		self:halign(0):valign(0):blend("BlendMode_Add")
	end,
	OnCommand = function(self)
		self:xy(0, H - 488 - 246):zoomto(2220, 246):diffusealpha(230 / 255)
		self:linear(0.3):xy(-1500, H - 419 - 200):zoomto(6700, 0):diffusealpha(0)
	end,
}

-- in from black and out to black (the screen waits 2.5 seconds). ECFN starts
-- with a white flash, here it read as a white screen while things loaded.
t[#t + 1] = Def.Quad {
	InitCommand = function(self)
		self:halign(0):valign(0):zoomto(W, H):diffuse(color("0,0,0,1"))
	end,
	OnCommand = function(self)
		self:decelerate(0.3):diffusealpha(0)
	end,
}
t[#t + 1] = Def.Quad {
	InitCommand = function(self)
		self:halign(0):valign(0):zoomto(W, H):diffuse(color("0,0,0,0"))
	end,
	OnCommand = function(self)
		self:sleep(1.5):decelerate(0.5):diffusealpha(1)
	end,
}

-- the screen sets up its decorations frame itself, the scaling sits inside it
return Def.ActorFrame {t}
