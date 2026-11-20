-- Various player and stage info, more text = fps drop so we should be sparing
local profileP1 = GetPlayerOrMachineProfile(PLAYER_1)
local PlayerFrameX = 0
local PlayerFrameY = SCREEN_HEIGHT - 50
local bgalpha = PREFSMAN:GetPreference("BGBrightness")

local translated_info = {
	Judge = THEME:GetString("ScreenGameplay", "ScoringJudge"),
	Scoring = THEME:GetString("ScreenGameplay", "ScoringType")
}

-- 7k: an ECFN style info corner instead (gauge and lanes; the progress bar has the title),
-- in ECFN's 1920x1080 space scaled to the screen, from the bottom left
if hideMSD() then
	local dir = THEME:GetCurrentThemeDirectory()
	if dir:sub(1, 1) ~= "/" then
		dir = "/" .. dir
	end
	dir = dir .. "BGAnimations/ScreenEvaluation decorations/ecfn/"
	local z = SCREEN_HEIGHT / 1080
	local X = 140 -- left edge of the text and plates
	local ecfnRow = {[0] = 0, 2, 1, 3, 4, 5}

	local function steps()
		return GAMESTATE:GetCurrentSteps()
	end
	-- ECFN font text, px tall
	local function Text(x, y, px, maxw, col, get)
		return LoadFont(rxFont.normal) .. {
			InitCommand = function(self)
				self:halign(0):valign(0.5):xy(x, y):diffuse(col or color("1,1,1,1"))
			end,
			SetCommand = function(self)
				self:settext(get() or "")
				local zz = px / math.max(self:GetHeight(), 1)
				self:zoom(zz):maxwidth(maxw / zz)
			end,
		}
	end
	local function Img(file, x, y, w, h)
		return Def.Sprite {
			Texture = dir .. file,
			InitCommand = function(self)
				self:halign(0):valign(0):xy(x, y):zoomto(w, h)
			end,
		}
	end
	local function Frame(file, x, y, w, h, get)
		return Def.Sprite {
			Texture = dir .. file,
			InitCommand = function(self)
				self:animate(false):halign(0):valign(0):xy(x, y):zoomto(w, h)
			end,
			SetCommand = function(self)
				local f = get()
				self:visible(f ~= nil)
				if f then
					self:setstate(f)
				end
			end,
		}
	end
	-- right aligned bitmap digits, faded 0 (frame 10) in front when the sheet has one
	local function Num(file, x, y, gw, gh, digits, dim, get)
		local f = Def.ActorFrame {
			InitCommand = function(self)
				self:xy(x, y)
			end,
		}
		for i = 1, digits do
			f[#f + 1] = Def.Sprite {
				Texture = dir .. file,
				InitCommand = function(self)
					self:animate(false):halign(0):valign(0):x((i - 1) * gw):zoomto(gw, gh)
				end,
				SetCommand = function(self)
					local v = get()
					if v == nil then
						self:visible(false)
						return
					end
					local s = tostring(math.floor(v))
					if #s > digits then
						s = s:sub(-digits)
					end
					local first = digits - #s + 1
					if i >= first then
						self:visible(true):setstate(tonumber(s:sub(i - first + 1, i - first + 1)))
					else
						self:visible(dim):setstate(dim and 10 or 0)
					end
				end,
			}
		end
		return f
	end
	local function level()
		local lv, diff = getBMSLevelDisplay(GAMESTATE:GetCurrentSong(), steps())
		return lv, diff
	end
	local plateX, plateY = X, -64

	local ecfn = Def.ActorFrame {
		InitCommand = function(self)
			self:xy(0, SCREEN_HEIGHT):zoom(z)
		end,
		BeginCommand = function(self)
			self:playcommand("Set")
		end,
		DoneLoadingNextSongMessageCommand = function(self)
			self:playcommand("Set")
		end,
		Def.Quad {
			InitCommand = function(self)
				self:halign(0):valign(1):xy(0, 0):zoomto(760, 104)
				self:diffuse(rxColor("bg")):diffusealpha(math.max(bgalpha, 0.5) * 0.8):faderight(0.6)
			end,
		},
		-- avatar flush in the corner
		Def.Sprite {
			InitCommand = function(self)
				self:halign(0):valign(1):xy(0, 0)
			end,
			BeginCommand = function(self)
				self:Load(getAvatarPath(PLAYER_1))
				self:zoomto(104, 104)
			end,
		},
		-- profile name
		Text(116, -44, 22, 640, rxColor("white"), function()
			local profile = GetPlayerOrMachineProfile(PLAYER_1)
			return profile and profile:GetDisplayName() or ""
		end),
		-- the other options, small
		Text(116, -16, 15, 640, rxColor("muted"), function()
			return getModifierTranslations(GAMESTATE:GetPlayerState():GetPlayerOptionsString("ModsLevel_Current"))
		end),
	}
	return ecfn
end

local t = Def.ActorFrame {
	Def.Quad {
		InitCommand = function(self)
			self:xy(0, SCREEN_HEIGHT):align(0,1):zoomto(150,61)
			self:diffuse(0,0,0,bgalpha*0.4)
		end,
	},
	Def.Quad {
		InitCommand = function(self)
			self:xy(150, SCREEN_HEIGHT):align(0,1):zoomto((SCREEN_WIDTH*.44)-150,18)
			self:diffuse(0,0,0,bgalpha*0.4)
			self:faderight(0.7)
		end,
	},
	Def.Sprite {
		InitCommand = function(self)
			self:halign(0):valign(0):xy(PlayerFrameX, PlayerFrameY)
		end,
		BeginCommand = function(self)
			self:finishtweening()
			self:Load(getAvatarPath(PLAYER_1))
			self:zoomto(50, 50)
		end
	},
	LoadFont("Common Large") .. {
		InitCommand = function(self)
			self:xy(PlayerFrameX + 90, PlayerFrameY + 24.5):halign(0):zoom(0.4):maxwidth(140):diffuse(getMainColor("positive"))
		end,
		SetCommand = function(self)
			self:settext(getDifficulty(GAMESTATE:GetCurrentSteps():GetDifficulty()))
			self:diffuse(
				getDifficultyColor(
					GetCustomDifficulty(
						GAMESTATE:GetCurrentSteps():GetStepsType(),
						GAMESTATE:GetCurrentSteps():GetDifficulty()
					)
				)
			)
		end,
		DoneLoadingNextSongMessageCommand = function(self)
			self:queuecommand("Set")
		end
	},
	LoadFont("Common Large") .. {
		InitCommand = function(self)
			self:xy(PlayerFrameX + 52, PlayerFrameY + 30):halign(0):zoom(0.75):maxwidth(50)
		end,
		SetCommand = function(self)
			if hideMSD() then
				self:settext("")
				return
			end
			local meter = GAMESTATE:GetCurrentSteps():GetMSD(getCurRateValue(), 1)
			self:settextf("%05.2f", meter)
			self:diffuse(byMSD(meter))
		end,
		DoneLoadingNextSongMessageCommand = function(self)
			self:queuecommand("Set")
		end,
		CurrentRateChangedMessageCommand = function(self)
			self:queuecommand("Set")
		end,
		PracticeModeReloadMessageCommand = function(self)
			self:queuecommand("Set")
		end
	},
	LoadFont("Common Normal") .. {
		InitCommand = function(self)
			self:xy(PlayerFrameX + 91, PlayerFrameY + 40):halign(0):zoom(0.4):maxwidth(SCREEN_WIDTH * 0.8)
		end,
		BeginCommand = function(self)
			self:settext(getModifierTranslations(GAMESTATE:GetPlayerState():GetPlayerOptionsString("ModsLevel_Current")))
		end
	},
	LoadFont("Common Normal") .. {
		InitCommand = function(self)
			self:xy(PlayerFrameX + 53, PlayerFrameY - 4):halign(0):zoom(0.45)
		end,
		BeginCommand = function(self)
			self:settextf("%s: %d", translated_info["Judge"], GetTimingDifficulty())
		end
	},
	LoadFont("Common Normal") .. {
		InitCommand = function(self)
			self:xy(PlayerFrameX + 53, PlayerFrameY + 9):halign(0):zoom(0.45)
		end,
		BeginCommand = function(self)
			self:settextf("%s: %s", translated_info["Scoring"], scoringToText(4))
		end
	}
}
return t
