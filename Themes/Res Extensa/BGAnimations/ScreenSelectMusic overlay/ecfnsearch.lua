-- 7k: the res extensa top bar in place of the Til Death title and sort
-- display: "res extensa <version>" on the left (clicking it picks a random
-- song, see default.lua), the search box, the sort and links to the
-- playlists, the profile and the options over the wheel. 1920x1080 space.
local s = ecfnScale()
local H = 72

local function setTab(i)
	local tind = getTabIndex()
	setTabIndex(i)
	MESSAGEMAN:Broadcast("TabChanged", {from = tind, to = i})
end

-- a text link: muted, white under the mouse
local function Link(label, x, y, px, align, onClick)
	local z = rxZoom(rxFont.normal, px)
	return Def.ActorFrame {
		LoadFont(rxFont.normal) .. {
			Name = "Label",
			InitCommand = function(self)
				self:xy(x, y):halign(align):zoom(z):settext(label):diffuse(rxColor("muted"))
			end,
		},
		UIElements.QuadButton(1, 1) .. {
			InitCommand = function(self)
				local w = self:GetParent():GetChild("Label"):GetZoomedWidth() + 16
				local qx = align == 1 and (x - w + 8) or (x - 8)
				self:xy(qx, y):halign(0):zoomto(w, 40):diffusealpha(0)
			end,
			MouseOverCommand = function(self)
				self:GetParent():GetChild("Label"):diffuse(rxColor("white"))
			end,
			MouseOutCommand = function(self)
				self:GetParent():GetChild("Label"):diffuse(rxColor("muted"))
			end,
			MouseDownCommand = function(self, params)
				if params.event == "DeviceButton_left mouse button" then
					onClick()
				end
			end,
		},
	}
end

local sorts = {"SortOrder_Group", "SortOrder_Title", "SortOrder_Artist", "SortOrder_BPM", "SortOrder_Length"}
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

local SX, SW = 1000, 440

local t = Def.ActorFrame {
	InitCommand = function(self)
		self:xy((SCREEN_WIDTH - 1920 * s) / 2, 0):zoom(s)
	end,
	OnCommand = function(self)
		self:xy((SCREEN_WIDTH - 1920 * s) / 2, 0):zoom(s)
	end,
	-- the bar across the whole screen (wider than 16:9 too)
	Def.Quad {
		InitCommand = function(self)
			local left = -(SCREEN_WIDTH - 1920 * s) / 2 / s
			self:halign(0):valign(0):xy(left, 0):zoomto(SCREEN_WIDTH / s, H):diffuse(rxColor("bg", 0.82))
		end,
	},
	Def.Quad {
		InitCommand = function(self)
			local left = -(SCREEN_WIDTH - 1920 * s) / 2 / s
			self:halign(0):valign(0):xy(left, H - 1):zoomto(SCREEN_WIDTH / s, 1):diffuse(rxColor("line"))
		end,
	},
	LoadFont(rxFont.semibold) .. {
		Name = "Brand",
		InitCommand = function(self)
			self:halign(0):xy(48, H / 2):zoom(rxZoom(rxFont.semibold, 24)):settext("res extensa"):diffuse(rxColor("white"))
		end,
	},
	LoadFont(rxFont.normal) .. {
		InitCommand = function(self)
			self:halign(0):xy(48, H / 2):zoom(rxZoom(rxFont.normal, 24)):settext(getThemeVersion()):diffuse(rxColor("muted"))
		end,
		OnCommand = function(self)
			self:x(48 + self:GetParent():GetChild("Brand"):GetZoomedWidth() + 8)
		end,
	},

	-- search box, it shows the search of the Search tab and opens that tab
	Def.Quad {
		Name = "SearchBox",
		InitCommand = function(self)
			self:halign(0):valign(0):xy(SX, 16):zoomto(SW, 40):diffuse(rxColor("line2"))
		end,
		TabChangedMessageCommand = function(self)
			self:diffuse(getTabIndex() == 3 and rxColor("text") or rxColor("line2"))
		end,
	},
	Def.Quad {
		InitCommand = function(self)
			self:halign(0):valign(0):xy(SX + 1, 17):zoomto(SW - 2, 38):diffuse(rxColor("bg", 0.6))
		end,
	},
	LoadFont(rxFont.normal) .. {
		InitCommand = function(self)
			self:halign(0):valign(0.5):xy(SX + 14, 36)
			self.z = rxZoom(rxFont.normal, 18)
			self:zoom(self.z):maxwidth((SW - 28) / self.z)
			self.str = ""
			self.caret = true
			self:playcommand("Show")
			self:queuecommand("Blink")
		end,
		ShowCommand = function(self)
			if getTabIndex() == 3 then
				self:settext(self.str .. (self.caret and "_" or " ")):diffuse(rxColor("white"))
			elseif self.str == "" then
				self:settext("Search"):diffuse(rxColor("muted"))
			else
				self:settext(self.str):diffuse(rxColor("text"))
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
	UIElements.QuadButton(1, 1) .. {
		InitCommand = function(self)
			self:halign(0):valign(0):xy(SX, 16):zoomto(SW, 40):diffusealpha(0)
		end,
		MouseDownCommand = function(self, params)
			if params.event == "DeviceButton_left mouse button" then
				setTab(3)
			end
		end,
	},

	-- the sort: label and value, a click goes to the next one
	LoadFont(rxFont.normal) .. {
		InitCommand = function(self)
			self:halign(0):xy(1468, 36):zoom(rxZoom(rxFont.normal, 13)):settext("SORT"):diffuse(rxColor("muted"))
		end,
	},
	LoadFont(rxFont.semibold) .. {
		InitCommand = function(self)
			self:halign(0):xy(1516, 36):zoom(rxZoom(rxFont.semibold, 18)):maxwidth(130 / rxZoom(rxFont.semibold, 18))
		end,
		BeginCommand = function(self)
			self:queuecommand("Sort")
		end,
		SortOrderChangedMessageCommand = function(self)
			self:queuecommand("Sort")
		end,
		SortCommand = function(self)
			local cur = GAMESTATE:GetSortOrder()
			if cur == nil then
				self:settext("")
			elseif cur == "SortOrder_Group" then
				self:settext("Folder")
			else
				self:settext(THEME:GetString("SortOrder", ToEnumShortString(cur)))
			end
		end,
	},
	UIElements.QuadButton(1, 1) .. {
		InitCommand = function(self)
			self:halign(0):valign(0):xy(1460, 16):zoomto(190, 40):diffusealpha(0)
		end,
		MouseDownCommand = function(self, params)
			if params.event == "DeviceButton_left mouse button" then
				nextSort()
			end
		end,
	},

	Link("Lists", 1672, H / 2, 16, 0, function() setTab(7) end),
	Link("Profile", 1740, H / 2, 16, 0, function() setTab(4) end),
	Link("Options", 1880, H / 2, 16, 1, function()
		SCREENMAN:GetTopScreen():OpenOptions()
	end),
}

return t
