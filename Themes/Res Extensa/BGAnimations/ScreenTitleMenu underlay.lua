if IsSMOnlineLoggedIn() then
	CloseConnection()
end

local t = Def.ActorFrame {}

-- title menu in the look of the beatoraja ECFN skin: its select background
-- and vignette, the theme name on the left and the choices as wheel bars on
-- the right (Graphics/ScreenTitleMenu scroll.lua). Everything is placed in
-- the skin's 1920x1080 space and scaled to the screen.
local s = ecfnScale()

-- title menu in the look of the res extensa website: near black page, the
-- name in big Inter on the left, the choices as a plain list on the right
-- (Graphics/ScreenTitleMenu scroll.lua). Sizes are in 1920x1080 space.
local function px(n)
	return n * s
end

t[#t + 1] = Def.Quad {
	InitCommand = function(self)
		self:halign(0):valign(0):zoomto(SCREEN_WIDTH, SCREEN_HEIGHT):diffuse(rxColor("bg"))
	end,
}

-- top bar like the site's header
t[#t + 1] = rxBox(0, px(72), SCREEN_WIDTH, 1, rxColor("line"))
t[#t + 1] = rxLabel(rxFont.semibold, ecfnX(40), px(36), px(22), 0, "res extensa", rxColor("text"))
t[#t + 1] = rxLabel(rxFont.normal, ecfnX(1880), px(36), px(18), 1, "title menu", rxColor("muted"))

-- footer with the keys
t[#t + 1] = rxBox(0, SCREEN_HEIGHT - px(48), SCREEN_WIDTH, 1, rxColor("line"))
t[#t + 1] = rxLabel(rxFont.normal, ecfnX(1880), SCREEN_HEIGHT - px(24), px(16), 1,
	"Up / Down  select    Start  decide    Back  exit", rxColor("muted"))

local logoX, logoY = ecfnX(160), SCREEN_CENTER_Y - px(20)
local playingMusic = {}
local playingMusicCounter = 1

-- what the build is for, above the name
t[#t + 1] = rxLabel(rxFont.normal, logoX, logoY - px(110), px(20), 0, "BMS  ·  O2JAM  ·  7 KEYS", rxColor("muted"))

-- the name, click to play random songs (right click stops them)
t[#t + 1] = LoadFont(rxFont.bold) .. {
	Name = "Logo",
	Text = "res extensa",
	InitCommand = function(self)
		self:z(1):halign(0):valign(0.5):xy(logoX, logoY - px(30)):zoom(rxZoom(rxFont.bold, px(120)))
		self:diffuse(rxColor("white"))
	end,
	PlayingMusicMessageCommand = function(self, params)
		if params.file ~= "" and params.file:find("_missing") == nil then
			self:effectclock("beat"):diffuseshift():effectcolor1(rxColor("white")):effectcolor2(rxColor("muted"))
		end
	end,
	StoppedMusicMessageCommand = function(self)
		self:stopeffect()
	end,
}
t[#t + 1] = UIElements.QuadButton(1, 1) .. {
	InitCommand = function(self)
		self:z(2):halign(0):valign(0.5):xy(logoX, logoY - px(30)):zoomto(px(680), px(130)):diffusealpha(0)
	end,
	MouseOverCommand = function(self)
		local logo = self:GetParent():GetChild("Logo")
		if logo then logo:diffusealpha(0.75) end
	end,
	MouseOutCommand = function(self)
		local logo = self:GetParent():GetChild("Logo")
		if logo then logo:diffusealpha(1) end
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

-- a short line and the version under the name
t[#t + 1] = rxBox(logoX, logoY + px(48), px(64), px(2), rxColor("white"))
t[#t + 1] = LoadFont(rxFont.normal) .. {
	Name = "Version",
	InitCommand = function(self)
		self:settext("ver " .. getThemeVersion())
		self:halign(0):valign(0.5):xy(logoX, logoY + px(88)):zoom(rxZoom(rxFont.normal, px(22))):diffuse(rxColor("muted"))
	end,
}
t[#t + 1] = rxLabel(rxFont.normal, logoX, logoY + px(124), px(18), 0,
	"Click the name for random music, right click stops it.", rxColor("dim"))

-- the Etterna "update available" button is gone: it pointed at upstream
-- Etterna. New res extensa releases come up in _bmsUpdate.lua (overlay).

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
			self:halign(0):zoomto(640 * s, 52 * s)
			self:xy(scrollerX - 16 * s, scrollerY + 60 * s * ((i - 1) - (choiceCount - 1) / 2))
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
