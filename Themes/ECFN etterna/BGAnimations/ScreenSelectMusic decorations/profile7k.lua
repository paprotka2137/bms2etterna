-- 7k: the "Profile" window (key 2) in the Dan window's look (Scripts/
-- ECFNWindow.lua). BEST lists the best play of every 7k chart sorted by level
-- and lamp, RECENT the latest plays, TOP the best EX rates. Clicking a row
-- moves the wheel to its song.
local W = ECFNWindow
local tab = 4
local listY = W.top + 62
local rows = 17
local mode = "best"
local page = 0
local lists = {}

-- every 7k play, latest first
local function gather()
	local all = {}
	SCOREMAN:SortRecentScoresForGame()
	local n = 1
	local hs = SCOREMAN:GetRecentScoreForGame(n)
	while hs do
		local ck = hs:GetChartKey()
		local steps = SONGMAN:GetStepsByChartKey(ck)
		if steps and steps:GetStepsType() == "StepsType_Kb7_Single" then
			local song = SONGMAN:GetSongByChartKey(ck)
			local level, levelName = getBMSLevel(song, steps)
			all[#all + 1] = {
				score = hs, ck = ck, song = song, steps = steps, level = level, levelName = levelName,
				rate = getBMSScoreRate(hs), lamp = getBMSLampFromScore(hs),
			}
		end
		n = n + 1
		hs = SCOREMAN:GetRecentScoreForGame(n)
	end
	lists.recent = all

	-- best per chart: lamp from 1.0x plays, the best EX rate among them
	local best, top = {}, {}
	local seen = {}
	for _, e in ipairs(all) do
		if not seen[e.ck] then
			seen[e.ck] = true
			local lamp, bestScore = getBestBMSLamp(e.ck)
			if lamp then
				best[#best + 1] = {
					score = bestScore, ck = e.ck, song = e.song, steps = e.steps, level = e.level,
					levelName = e.levelName, rate = getBMSScoreRate(bestScore), lamp = lamp,
				}
			end
		end
	end
	for _, e in ipairs(best) do
		top[#top + 1] = e
	end
	table.sort(best, function(a, b)
		if a.level ~= b.level then return a.level > b.level end
		if a.lamp ~= b.lamp then return a.lamp < b.lamp end
		return a.rate > b.rate
	end)
	table.sort(top, function(a, b)
		return a.rate > b.rate
	end)
	lists.best = best
	lists.top = top
end

local function current()
	return lists[mode] or {}
end

local function entry(i)
	return current()[page * rows + i]
end

local function pages()
	return math.max(1, math.ceil(#current() / rows))
end

local t = W.frame(tab, "BMSProfile", function()
	gather()
	page = 0
end)

-- header: name, rating and play count, the modes on the right
t[#t + 1] = W.text(8, W.top + 12, 0.42, 0) .. {
	ShowCommand = function(self)
		local profile = PROFILEMAN:GetProfile(PLAYER_1)
		self:settext(profile:GetDisplayName()):maxwidth(150 / 0.42)
	end,
}
t[#t + 1] = W.text(8, W.top + 30, 0.34, 0) .. {
	ShowCommand = function(self)
		local counts = {0, 0, 0, 0, 0}
		for _, e in ipairs(lists.best or {}) do
			counts[e.lamp] = counts[e.lamp] + 1
		end
		self:settextf("%d charts   FC %d   HARD %d   CLEAR %d   EASY %d", #(lists.best or {}),
			counts[1], counts[2], counts[3], counts[4]):diffuse(W.gray)
		self:maxwidth((W.width - 16) / 0.34)
	end,
}
local modes = {{"best", "BEST"}, {"recent", "RECENT"}, {"top", "TOP"}}
for k, m in ipairs(modes) do
	t[#t + 1] = W.button(m[2], W.width - 8 - (4 - k) * 54 + 27, W.top + 12, 50, function()
		mode = m[1]
		page = 0
		MESSAGEMAN:Broadcast("BMSProfileRefresh")
	end, nil, function()
		return mode == m[1]
	end)
end
t.BMSProfileRefreshMessageCommand = function(self)
	if self.open then
		self:playcommand("Show")
	end
end

-- column names
local col = {num = 18, lv = 24, title = 62, rateX = W.width - 150, ex = W.width - 92, lamp = W.width - 62, date = W.width - 10}
local function head(x, align, label)
	t[#t + 1] = W.text(x, listY - 14, 0.3, align, function(self)
		self:settext(label):diffuse(W.gray)
	end)
end
head(col.lv, 0, "LV")
head(col.title, 0, "TITLE")
head(col.rateX, 0.5, "RATE")
head(col.ex, 1, "EX%")
head(col.lamp, 0.5, "LAMP")
head(col.date, 1, "DATE")

for i = 1, rows do
	local y = listY + (i - 1) * W.rowH
	t[#t + 1] = Def.ActorFrame {
		ShowCommand = function(self)
			self:visible(entry(i) ~= nil)
		end,
		W.rowBand(i, y, nil, function(i)
			local e = entry(i)
			if e then
				W.pickSong(e.song)
			end
		end),
		W.text(col.num, y, 0.3, 1) .. {
			ShowCommand = function(self)
				self:settext(entry(i) and (page * rows + i) or ""):diffuse(W.gray)
			end,
		},
		W.text(col.lv, y, 0.32, 0) .. {
			ShowCommand = function(self)
				local e = entry(i)
				self:settext(e and e.levelName or ""):diffuse(color("#d080ff"))
			end,
		},
		W.text(col.title, y, 0.32, 0, function(self)
			self:maxwidth((col.rateX - col.title - 24) / 0.32)
		end) .. {
			ShowCommand = function(self)
				local e = entry(i)
				self:settext(e and e.song and e.song:GetDisplayMainTitle() or "")
				-- invalid scores in red like Til Death
				self:diffuse(e and not e.score:GetEtternaValid() and W.red or W.white)
			end,
		},
		W.text(col.rateX, y, 0.3, 0.5) .. {
			ShowCommand = function(self)
				local e = entry(i)
				self:settext(e and getRateString(notShit.round(e.score:GetMusicRate(), 3)) or "")
			end,
		},
		W.text(col.ex, y, 0.32, 1) .. {
			ShowCommand = function(self)
				local e = entry(i)
				self:settext(e and string.format("%.2f%%", e.rate * 100) or "")
			end,
		},
		W.text(col.lamp, y, 0.3, 0.5) .. {
			ShowCommand = function(self)
				local e = entry(i)
				if e then
					self:settext(getBMSLampInfo(e.lamp, 1)):diffuse(getBMSLampInfo(e.lamp, 2))
				end
			end,
		},
		W.text(col.date, y, 0.28, 1) .. {
			ShowCommand = function(self)
				local e = entry(i)
				self:settext(e and e.score:GetDate():sub(1, 10) or ""):diffuse(W.gray)
			end,
		},
	}
end

-- pages
local pageY = listY + rows * W.rowH + 8
t[#t + 1] = W.button("PREV", 34, pageY, 56, function()
	page = (page - 1) % pages()
	MESSAGEMAN:Broadcast("BMSProfileRefresh")
end)
t[#t + 1] = W.button("NEXT", W.width - 34, pageY, 56, function()
	page = (page + 1) % pages()
	MESSAGEMAN:Broadcast("BMSProfileRefresh")
end)
t[#t + 1] = W.text(W.width / 2, pageY, 0.3, 0.5) .. {
	ShowCommand = function(self)
		local n = #current()
		if n == 0 then
			self:settext("No plays yet"):diffuse(W.gray)
		else
			self:settextf("%d-%d of %d", page * rows + 1, math.min(n, (page + 1) * rows), n):diffuse(W.gray)
		end
	end,
}

return t
