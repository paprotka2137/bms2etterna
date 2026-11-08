-- 7k: the ECFN top bar in place of the Til Death title and sort display.
-- ":SELECT A MUSIC" on the left (clicking it still picks a random song, see
-- default.lua), the search box with its icons and the key mode / sort / LN
-- mode cells over the wheel, all in the skin's 1920x1080 space.
local s = ecfnScale()
local dir = THEME:GetCurrentThemeDirectory()
if dir:sub(1, 1) ~= "/" then
	dir = "/" .. dir
end
dir = dir .. "BGAnimations/ScreenSelectMusic decorations/ecfn/"

local function setTab(i)
	local tind = getTabIndex()
	setTabIndex(i)
	MESSAGEMAN:Broadcast("TabChanged", {from = tind, to = i})
end

local function Button(file, x, y, w, h, onClick)
	return UIElements.SpriteButton(1, 1, dir .. file) .. {
		InitCommand = function(self)
			self:halign(0):valign(0):xy(x, y):zoomto(w, h)
		end,
		MouseOverCommand = function(self)
			self:diffusealpha(0.7)
		end,
		MouseOutCommand = function(self)
			self:diffusealpha(1)
		end,
		MouseDownCommand = function(self, params)
			if params.event == "DeviceButton_left mouse button" then
				onClick()
			end
		end,
	}
end

-- the sort cell cycles through these, the skin has pictures for some of them
local sorts = {"SortOrder_Group", "SortOrder_Title", "SortOrder_Artist", "SortOrder_BPM", "SortOrder_Length"}
local sortFrames = {SortOrder_Title = 0, SortOrder_Artist = 1, SortOrder_BPM = 2, SortOrder_Length = 3}
local function nextSort()
	local cur = GAMESTATE:GetSortOrder()
	local i = 0
	for k, v in ipairs(sorts) do
		if v == cur then
			i = k
		end
	end
	local wheel = SCREENMAN:GetTopScreen():GetMusicWheel()
	wheel:ChangeSort(sorts[i % #sorts + 1])
end

local t = Def.ActorFrame {
	InitCommand = function(self)
		self:xy((SCREEN_WIDTH - 1920 * s) / 2, 0):zoom(s)
	end,
	OnCommand = function(self)
		self:xy((SCREEN_WIDTH - 1920 * s) / 2, 0):zoom(s)
	end,
	Def.Sprite {
		Texture = dir .. "upper.png",
		InitCommand = function(self)
			self:halign(0):valign(0):xy(25, 0):zoomto(1811, 85)
		end,
	},

	-- dark backing so the wheel's top bars don't show through the cells
	Def.Quad {
		InitCommand = function(self)
			self:halign(0):valign(0):xy(1296, 16):zoomto(584, 106):diffuse(color("0,0,0,0.8"))
		end,
	},
	-- search box, it shows the search of the Search tab and opens that tab
	Button("search_ico.png", 1308, 24, 47, 47, function() setTab(3) end),
	Button("search_window.png", 1364, 24, 332, 47, function() setTab(3) end),
	-- lit while typing (the Search tab is on), the typed text with a blinking
	-- caret, Enter keeps the results and Escape drops them
	Def.Quad {
		InitCommand = function(self)
			self:halign(0):valign(0):xy(1364, 24):zoomto(332, 47):diffuse(color("#3f9fff")):diffusealpha(0)
		end,
		TabChangedMessageCommand = function(self)
			self:stoptweening():linear(0.1):diffusealpha(getTabIndex() == 3 and 0.25 or 0)
		end,
	},
	LoadFont("Common Normal") .. {
		InitCommand = function(self)
			self:halign(0):valign(0.5):xy(1378, 47)
			self:settext("Ag")
			self.z = 22 / self:GetHeight() * 1.25
			self:zoom(self.z):maxwidth(300 / self.z)
			self.str = ""
			self.caret = true
			self:playcommand("Show")
			self:queuecommand("Blink")
		end,
		ShowCommand = function(self)
			if getTabIndex() == 3 then
				self:settext(self.str .. (self.caret and "_" or " ")):diffuse(color("1,1,1,1"))
			elseif self.str == "" then
				self:settext("search song"):diffuse(color("1,1,1,0.45"))
			else
				self:settext(self.str):diffuse(color("1,1,1,1"))
			end
		end,
		BlinkCommand = function(self)
			self.caret = not self.caret
			self:playcommand("Show")
			self:sleep(0.4):queuecommand("Blink")
		end,
		TabChangedMessageCommand = function(self)
			self:playcommand("Show")
		end,
		UpdateStringMessageCommand = function(self, params)
			local str = params and params.searchstring
			if str == nil then
				return
			end
			self.str = str
			self:playcommand("Show")
		end,
	},
	Button("text_button.png", 1712, 24, 47, 47, function() setTab(7) end),
	Button("keyconfig.png", 1767, 24, 47, 47, function() setTab(4) end),
	Button("skin_select.png", 1821, 24, 47, 47, function()
		SCREENMAN:GetTopScreen():OpenOptions()
	end),

	-- key mode, sort and LN mode
	Button("sort_ico.png", 1308, 76, 47, 40, nextSort),
	Def.Sprite {
		Texture = dir .. "modeset_7k.png",
		InitCommand = function(self)
			self:halign(0):valign(0):xy(1364, 76):zoomto(158, 40)
		end,
	},
	Def.Quad {
		Name = "SortBack",
		InitCommand = function(self)
			self:halign(0):valign(0):xy(1538, 76):zoomto(158, 40):diffuse(color("0.05,0.07,0.1,0.9"))
		end,
	},
	Def.Sprite {
		Texture = dir .. "sortset 1x8.png",
		InitCommand = function(self)
			self:animate(false):halign(0):valign(0):xy(1538, 76):zoomto(158, 40)
		end,
		BeginCommand = function(self)
			self:queuecommand("Sort")
		end,
		SortOrderChangedMessageCommand = function(self)
			self:queuecommand("Sort")
		end,
		SortCommand = function(self)
			local f = sortFrames[GAMESTATE:GetSortOrder()]
			self:visible(f ~= nil)
			if f then
				self:setstate(f)
			end
		end,
	},
	-- sorts the skin has no picture for are written out
	LoadFont("Common Normal") .. {
		InitCommand = function(self)
			self:xy(1538 + 79, 96):zoom(0.9):maxwidth(140 / 0.9)
		end,
		BeginCommand = function(self)
			self:queuecommand("Sort")
		end,
		SortOrderChangedMessageCommand = function(self)
			self:queuecommand("Sort")
		end,
		SortCommand = function(self)
			local cur = GAMESTATE:GetSortOrder()
			if cur == nil or sortFrames[cur] then
				self:settext("")
				return
			end
			if cur == "SortOrder_Group" then
				self:settext("FOLDER")
			else
				self:settext(string.upper(THEME:GetString("SortOrder", ToEnumShortString(cur))))
			end
		end,
	},
	-- the sort cell is clicked through an invisible quad (a sprite button would
	-- keep its hover fade and show the sort icon over the cell)
	UIElements.QuadButton(1, 1) .. {
		InitCommand = function(self)
			self:halign(0):valign(0):xy(1538, 76):zoomto(158, 40):diffusealpha(0)
		end,
		MouseDownCommand = function(self, params)
			if params.event == "DeviceButton_left mouse button" then
				nextSort()
			end
		end,
	},
	Def.Sprite {
		Texture = dir .. "lnmodeset 1x3.png",
		InitCommand = function(self)
			self:animate(false):setstate(0):halign(0):valign(0):xy(1711, 76):zoomto(158, 40)
		end,
	},
}

return t
