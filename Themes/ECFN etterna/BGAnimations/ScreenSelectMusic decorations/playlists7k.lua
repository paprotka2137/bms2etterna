-- 7k: the "Playlists" window (key 4) in the Dan window's look (Scripts/
-- ECFNWindow.lua). The playlists on top (clicking one makes it the active
-- one), the charts of the active one below. NEW asks for a name, ADD puts
-- the selected chart in the active playlist, PLAY plays it as a course,
-- the X on a chart takes it out.
local W = ECFNWindow
local tab = 7
local listY = W.top + 62
local plRows = 5
local chartY = listY + plRows * W.rowH + 20
local chartRows = 10
local plPage, chartPage = 0, 0
local playlists = {}
local active

local function gather()
	playlists = SONGMAN:GetPlaylists() or {}
	table.sort(playlists, function(a, b)
		return a:GetName():lower() < b:GetName():lower()
	end)
	local a = SONGMAN:GetActivePlaylist()
	active = nil
	for _, pl in ipairs(playlists) do
		if a and pl:GetName() == a:GetName() then
			active = pl
		end
	end
end

local function charts()
	return active and active:GetAllSteps() or {}
end

local function plEntry(i)
	return playlists[plPage * plRows + i]
end

local function chartEntry(i)
	return charts()[chartPage * chartRows + i]
end

local t = W.frame(tab, "BMSPlaylists", function()
	gather()
	plPage, chartPage = 0, 0
end)
t.BMSPlaylistsRefreshMessageCommand = function(self)
	if self.open then
		gather()
		self:playcommand("Show")
	end
end
-- the engine's new playlist dialog ends with this
t.DisplayAllPlaylistsMessageCommand = t.BMSPlaylistsRefreshMessageCommand
local function refresh()
	MESSAGEMAN:Broadcast("BMSPlaylistsRefresh")
end

t[#t + 1] = W.text(8, W.top + 12, 0.42, 0, function(self)
	self:settext("PLAYLISTS")
end)
t[#t + 1] = W.text(8, W.top + 30, 0.34, 0) .. {
	ShowCommand = function(self)
		self:settext(active and ("Active: " .. active:GetName()) or "No playlist picked"):diffuse(W.gray)
		self:maxwidth((W.width - 140) / 0.34)
	end,
}
t[#t + 1] = W.button("NEW", W.width - 100, W.top + 12, 50, function()
	SONGMAN:NewPlaylist()
end)
t[#t + 1] = W.button("ADD", W.width - 46, W.top + 12, 50, function()
	SCREENMAN:GetTopScreen():AddCurrentChartToActivePlaylist()
	refresh()
end, function()
	return active ~= nil and GAMESTATE:GetCurrentSteps() ~= nil
end)
t[#t + 1] = W.button("PLAY", W.width - 46, W.top + 30, 50, function()
	SCREENMAN:GetTopScreen():StartPlaylistAsCourse(active:GetName())
end, function()
	return active ~= nil and active:GetNumCharts() > 0
end)

-- the playlists
local function head(x, y, align, label)
	t[#t + 1] = W.text(x, y, 0.3, align, function(self)
		self:settext(label):diffuse(W.gray)
	end)
end
head(10, listY - 14, 0, "PLAYLIST")
head(W.width - 12, listY - 14, 1, "CHARTS")
for i = 1, plRows do
	local y = listY + (i - 1) * W.rowH
	t[#t + 1] = Def.ActorFrame {
		ShowCommand = function(self)
			self:visible(plEntry(i) ~= nil)
		end,
		W.rowBand(i, y, function(i)
			local pl = plEntry(i)
			return pl and active and pl:GetName() == active:GetName()
		end, function(i)
			local pl = plEntry(i)
			if pl then
				SONGMAN:SetActivePlaylist(pl:GetName())
				chartPage = 0
				refresh()
			end
		end),
		W.text(10, y, 0.32, 0, function(self)
			self:maxwidth((W.width - 90) / 0.32)
		end) .. {
			ShowCommand = function(self)
				local pl = plEntry(i)
				self:settext(pl and pl:GetName() or "")
			end,
		},
		W.text(W.width - 12, y, 0.32, 1) .. {
			ShowCommand = function(self)
				local pl = plEntry(i)
				self:settext(pl and pl:GetNumCharts() or "")
			end,
		},
	}
end
t[#t + 1] = W.text(W.width / 2, listY - 14, 0.3, 0.5) .. {
	ShowCommand = function(self)
		if #playlists == 0 then
			self:settext("No playlists, NEW makes one"):diffuse(W.gray)
		else
			self:settext("")
		end
	end,
}

-- the active playlist's charts
head(10, chartY - 14, 0, "TITLE")
head(W.width - 120, chartY - 14, 0.5, "RATE")
head(W.width - 44, chartY - 14, 1, "LV")
for i = 1, chartRows do
	local y = chartY + (i - 1) * W.rowH
	t[#t + 1] = Def.ActorFrame {
		ShowCommand = function(self)
			self:visible(chartEntry(i) ~= nil)
		end,
		W.rowBand(i, y, nil, function(i)
			local ch = chartEntry(i)
			local songs = active and active:GetSonglist() or {}
			local song = songs[chartPage * chartRows + i]
			if ch and song then
				W.pickSong(song)
			end
		end),
		W.text(10, y, 0.32, 0, function(self)
			self:maxwidth((W.width - 160) / 0.32)
		end) .. {
			ShowCommand = function(self)
				local ch = chartEntry(i)
				if ch then
					self:settext(ch:GetSongTitle()):diffuse(ch:IsLoaded() and W.white or W.red)
				end
			end,
		},
		W.text(W.width - 120, y, 0.3, 0.5) .. {
			ShowCommand = function(self)
				local ch = chartEntry(i)
				self:settext(ch and getRateString(notShit.round(ch:GetRate(), 3)) or "")
			end,
		},
		W.text(W.width - 44, y, 0.32, 1) .. {
			ShowCommand = function(self)
				local songs = active and active:GetSonglist() or {}
				local song = songs[chartPage * chartRows + i]
				local name = ""
				if song then
					local _, n = getBMSLevel(song, getBMSSongSteps(song))
					name = n
				end
				self:settext(name):diffuse(color("#d080ff"))
			end,
		},
		UIElements.TextToolTip(1, 1, "Common Normal") .. {
			InitCommand = function(self)
				self:xy(W.x + W.width - 16, y):zoom(0.34):settext("X"):diffuse(W.red)
			end,
			MouseOverCommand = function(self)
				self:diffusealpha(0.6)
			end,
			MouseOutCommand = function(self)
				self:diffusealpha(1)
			end,
			MouseDownCommand = function(self, params)
				if active and chartEntry(i) and params.event == "DeviceButton_left mouse button" then
					active:DeleteChart(chartPage * chartRows + i)
					refresh()
				end
			end,
		},
	}
end

local pageY = chartY + chartRows * W.rowH + 8
local function chartPages()
	return math.max(1, math.ceil(#charts() / chartRows))
end
t[#t + 1] = W.button("PREV", 34, pageY, 56, function()
	chartPage = (chartPage - 1) % chartPages()
	refresh()
end)
t[#t + 1] = W.button("NEXT", W.width - 34, pageY, 56, function()
	chartPage = (chartPage + 1) % chartPages()
	refresh()
end)
t[#t + 1] = W.text(W.width / 2, pageY, 0.3, 0.5) .. {
	ShowCommand = function(self)
		local n = #charts()
		if not active then
			self:settext("")
		elseif n == 0 then
			self:settext("Empty, ADD puts the selected chart here"):diffuse(W.gray)
		else
			self:settextf("%d-%d of %d", chartPage * chartRows + 1, math.min(n, (chartPage + 1) * chartRows), n):diffuse(W.gray)
		end
	end,
}

return t
