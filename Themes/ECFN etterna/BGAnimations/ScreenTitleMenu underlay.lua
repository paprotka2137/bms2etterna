if IsSMOnlineLoggedIn() then
	CloseConnection()
end

local t = Def.ActorFrame {}

-- title menu in the look of the beatoraja ECFN skin: its select background
-- and vignette, the theme name on the left and the choices as wheel bars on
-- the right (Graphics/ScreenTitleMenu scroll.lua). Everything is placed in
-- the skin's 1920x1080 space and scaled to the screen.
local s = ecfnScale()
local dir = THEME:GetCurrentThemeDirectory()
if dir:sub(1, 1) ~= "/" then
	dir = "/" .. dir
end
dir = dir .. "BGAnimations/ScreenSelectMusic decorations/ecfn/"

-- text fitted to a height in skin pixels
local function fit(self, h)
	local txt = self:GetText()
	self:settext("Ag")
	local z = h * s * 0.8 / self:GetHeight()
	self:settext(txt):zoom(z)
	return z
end

t[#t + 1] = Def.Quad {
	InitCommand = function(self)
		self:halign(0):valign(0):zoomto(SCREEN_WIDTH, SCREEN_HEIGHT):diffuse(color("0,0,0,1"))
	end,
}
t[#t + 1] = Def.Sprite {
	Texture = dir .. "background.png",
	InitCommand = function(self)
		self:halign(0):valign(0):zoomto(SCREEN_WIDTH, SCREEN_HEIGHT)
	end,
}
t[#t + 1] = Def.Sprite {
	Texture = dir .. "shadow.png",
	InitCommand = function(self)
		self:halign(0):valign(0):zoomto(SCREEN_WIDTH, SCREEN_HEIGHT)
	end,
}

-- top left screen name, like the skin's ":SELECT A MUSIC"
t[#t + 1] = LoadFont("ECFN Normal") .. {
	Text = ":TITLE MENU",
	InitCommand = function(self)
		fit(self, 26)
		self:halign(0):xy(ecfnX(14), 40 * s):diffuse(color("#ffffff"))
	end,
}

-- thin silver-blue strips along the top and above the footer
local function strip(y)
	return Def.Quad {
		InitCommand = function(self)
			self:halign(0):valign(0):xy(0, y):zoomto(SCREEN_WIDTH, 2 * s)
			self:diffuseleftedge(color("#c8d2e0")):diffuserightedge(color("#3f9fff")):diffusealpha(0.55)
		end,
	}
end
t[#t + 1] = strip(72 * s)

-- footer with the keys
t[#t + 1] = Def.Quad {
	InitCommand = function(self)
		self:halign(0):valign(0):xy(0, SCREEN_HEIGHT - 40 * s):zoomto(SCREEN_WIDTH, 40 * s)
		self:diffuse(color("0,0,0,0.55"))
	end,
}
t[#t + 1] = strip(SCREEN_HEIGHT - 40 * s)
t[#t + 1] = LoadFont("ECFN Normal") .. {
	Text = "UP / DOWN  SELECT        START  DECIDE        BACK  EXIT",
	InitCommand = function(self)
		fit(self, 16)
		self:halign(1):xy(ecfnX(1900), SCREEN_HEIGHT - 20 * s):diffuse(color("#aab9d7"))
	end,
}

local logoX, logoY = ecfnX(560), SCREEN_CENTER_Y - 60 * s
local playingMusic = {}
local playingMusicCounter = 1

-- what the build is for, above the name
t[#t + 1] = LoadFont("ECFN Normal") .. {
	Text = "BMS  /  O2JAM    7KEYS",
	InitCommand = function(self)
		fit(self, 20)
		self:halign(0):valign(1):xy(logoX - 425 * s, logoY - 92 * s):diffuse(color("#a0bef0"))
		self:shadowlength(2 * s):shadowcolor(color("0,0,0,0.6"))
	end,
}

-- line under the name, version at its right end
t[#t + 1] = Def.Sprite {
	Texture = dir .. "name_line.png",
	InitCommand = function(self)
		self:xy(logoX, logoY + 98 * s):zoomto(853 * s, 20 * s)
	end,
}

-- theme name, click to play random songs (right click stops them)
t[#t + 1] = UIElements.SpriteButton(1, 1, THEME:GetPathG("", "_title logo")) .. {
	Name = "Logo",
	InitCommand = function(self)
		self:z(1):xy(logoX, logoY):zoom(0.8 * s)
	end,
	MouseOverCommand = function(self)
		self:diffusealpha(0.75)
	end,
	MouseOutCommand = function(self)
		self:diffusealpha(1)
	end,
	PlayingMusicMessageCommand = function(self, params)
		if params.file ~= "" and params.file:find("_missing") == nil then
			self:effectclock("beat"):heartbeat()
		end
	end,
	StoppedMusicMessageCommand = function(self)
		self:stopeffect()
	end,
	MouseDownCommand = function(self, params)
		if params.event == "DeviceButton_left mouse button" then
			local function startSong()
				local sngs = SONGMAN:GetAllSongs()
				if #sngs == 0 then ms.ok("No songs to play") return end

				local song = sngs[math.random(#sngs)]
				local p = song:GetMusicPath()
				local l = song:MusicLengthSeconds()
				local top = SCREENMAN:GetTopScreen()

				local thisSong = playingMusicCounter
				playingMusic[thisSong] = true

				SOUND:StopMusic()
				SOUND:PlayMusicPart(p, 0, l)

				ms.ok("NOW PLAYING: " .. song:GetMainTitle() .. " | LENGTH: " .. SecondsToMMSS(l))

				top:setTimeout(
					function()
						if not playingMusic[thisSong] then return end
						playingMusicCounter = playingMusicCounter + 1
						startSong()
					end,
					l
				)
			end

			SCREENMAN:GetTopScreen():setTimeout(function()
					playingMusic[playingMusicCounter] = false
					playingMusicCounter = playingMusicCounter + 1
					startSong()
				end,
			0.1)
		else
			SOUND:StopMusic()
			playingMusic = {}
			playingMusicCounter = playingMusicCounter + 1
			ms.ok("Stopped music")
		end
	end,
}

-- version
t[#t + 1] = LoadFont("ECFN Normal") .. {
	Name = "Version",
	InitCommand = function(self)
		self:settext("ver " .. getThemeVersion())
		fit(self, 26)
		self:halign(1):xy(logoX + 420 * s, logoY + 135 * s):diffuse(color("#6eb4ff"))
		self:shadowlength(2 * s):shadowcolor(color("0,0,0,0.7"))
	end,
}

--game update button
local gameneedsupdating = false
local buttons = {x = 20, y = 20, width = 142, height = 42, fontScale = 0.35, color = getMainColor("frames")}
t[#t + 1] = Def.ActorFrame {
	InitCommand = function(self)
		self:xy(buttons.x,buttons.y)
	end,
	UIElements.QuadButton(1, 1) .. {
		InitCommand = function(self)
			self:zoomto(buttons.width, buttons.height):halign(0):valign(0):diffuse(buttons.color):diffusealpha(0)
			self:playcommand("LastVersionUpdated")
		end,
		LastVersionUpdatedMessageCommand = function(self)
			local latest = tonumber((DLMAN:GetLastVersion():gsub("[.]", "", 1)))
			local current = tonumber((GAMESTATE:GetEtternaVersion():gsub("[.]", "", 1)))
			if latest and latest > current then
				gameneedsupdating = true
			end
			self:playcommand("On")
		end,
		OnCommand = function(self)
			if gameneedsupdating then
				self:diffusealpha(0.3)
			end
		end,
		MouseDownCommand = function(self, params)
			if params.event == "DeviceButton_left mouse button" and gameneedsupdating then
				DLMAN:ShowProjectReleases()
			end
		end
	},
	LoadFont("Common Large") .. {
		OnCommand = function(self)
			self:xy(1.7, 1):align(0,0):zoom(buttons.fontScale):diffuse(getMainColor("positive"))
			if gameneedsupdating then
				self:settext(THEME:GetString("ScreenTitleMenu", "UpdateAvailable"))
			else
				self:settext("")
			end
		end
	}
}

local function mysplit(inputstr, sep)
	if sep == nil then
		sep = "%s"
	end
	local t = {}
	i = 1
	for str in string.gmatch(inputstr, "([^" .. sep .. "]+)") do
		t[i] = str
		i = i + 1
	end
	return t
end

local scrollerX = THEME:GetMetric("ScreenTitleMenu", "ScrollerX")
local scrollerY = THEME:GetMetric("ScreenTitleMenu", "ScrollerY")
local scrollerChoices = THEME:GetMetric("ScreenTitleMenu", "ChoiceNames")
local choices = mysplit(scrollerChoices, ",")
local choiceCount = #choices
for i = 1, choiceCount do
	-- same place as the bar of the choice (metrics ScrollerTransform)
	t[#t + 1] = UIElements.QuadButton(1, 1) .. {
		OnCommand = function(self)
			self:halign(0):zoomto(730 * s, 52 * s)
			self:xy(scrollerX - 40 * s, scrollerY + 60 * s * ((i - 1) - (choiceCount - 1) / 2))
			self:diffusealpha(0)
		end,
		MouseDownCommand = function(self, params)
			if params.event == "DeviceButton_left mouse button" then
				SCREENMAN:GetTopScreen():playcommand("MadeChoicePlayer_1")
				SCREENMAN:GetTopScreen():playcommand("Choose")
				if choices[i] == "Multi" or choices[i] == "GameStart" then
					GAMESTATE:JoinPlayer()
				end
				GAMESTATE:ApplyGameCommand(THEME:GetMetric("ScreenTitleMenu", "Choice" .. choices[i]))
			end
		end
	}
end

return t
