-- 7k: the "Profile" window (key 2) in the Dan window's look (Scripts/
-- ECFNWindow.lua). BEST lists the best play of every 7k chart sorted by level
-- and lamp, RECENT the latest plays, TOP the best EX rates. Clicking a row
-- moves the wheel to its song. Logged in to the ranking site, the lists come
-- from the site (every computer's plays), else from this computer's scores.
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
			local e = all[#all]
			e.title = song and song:GetDisplayMainTitle() or ""
			e.rateText = getRateString(notShit.round(hs:GetMusicRate(), 3))
			e.date = hs:GetDate():sub(1, 10)
			e.valid = hs:GetEtternaValid()
		end
		n = n + 1
		hs = SCOREMAN:GetRecentScoreForGame(n)
	end
	-- failed plays are left out
	local shown = {}
	for _, e in ipairs(all) do
		if e.lamp < 6 then
			shown[#shown + 1] = e
		end
	end
	lists.recent = shown

	-- best per chart: lamp from 1.0x plays, the best EX rate among them
	local best, top = {}, {}
	local seen = {}
	for _, e in ipairs(all) do
		if not seen[e.ck] then
			seen[e.ck] = true
			local lamp, bestScore = getBestBMSLamp(e.ck)
			if lamp and lamp < 6 then
				best[#best + 1] = {
					score = bestScore, ck = e.ck, song = e.song, steps = e.steps, level = e.level,
					levelName = e.levelName, rate = getBMSScoreRate(bestScore), lamp = lamp,
					title = e.title, rateText = getRateString(notShit.round(bestScore:GetMusicRate(), 3)),
					date = bestScore:GetDate():sub(1, 10), valid = bestScore:GetEtternaValid(),
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

---------------------------------------------------------------------------
-- the same lists from the ranking site (POST /api/game/myscores)
---------------------------------------------------------------------------

local siteLists -- {best, recent, top} once the site answered
local sitePending = false
local siteTime
-- how hard a level is on the insane scale, to sort the tables together
-- (the site's SL_AS_INSANE / ST_AS_INSANE)
local SL = {[0] = 0, 1.5, 3.5, 5, 6.75, 9.25, 11, 12, 14, 16, 17.2, 18, 19}
local ST = {[0] = 19.5, 21, 22, 22.75, 23.5, 24, 24.5, 25.25, 25.75, 26.5, 27.25, 27.75, 28.5}
local prefix = {insane = "★", satellite = "sl", stella = "st"}

local function siteEntry(f)
	local ck, tbl, lv = f[2], f[8] or "", tonumber(f[9])
	local notes = math.max(tonumber(f[6]) or 0, 1)
	local hard = lv or -1
	if tbl == "satellite" then
		hard = (SL[lv or -1] or (lv or 0) * 1.6) + 0.01
	elseif tbl == "stella" then
		hard = (ST[lv or -1] or 19.5 + (lv or 0) * 0.75) + 0.02
	end
	local song = SONGMAN:GetSongByChartKey(ck)
	return {
		ck = ck, song = song,
		level = hard,
		levelName = lv and ((prefix[tbl] or "★") .. lv) or "?",
		title = song and song:GetDisplayMainTitle() or (f[10] or "?"),
		lamp = math.max(1, math.min(6, tonumber(f[4]) or 6)),
		playLamp = math.max(1, math.min(6, tonumber(f[3]) or 6)),
		rate = (tonumber(f[5]) or 0) / (notes * 2),
		rateText = "1.0x", -- the site keeps 1.0x plays only
		date = (f[7] or ""):sub(1, 10),
		valid = true,
	}
end

local function loadSite()
	if not (BMSRanking and BMSRanking.loggedIn and BMSRanking.loggedIn()) then
		siteLists = nil
		return
	end
	if sitePending or (siteTime and GetTimeSinceStart() - siteTime < 20) then
		return
	end
	sitePending = true
	DLMAN:BMSRequest("POST", "/api/game/myscores", {}, function(status, body)
		sitePending = false
		siteTime = GetTimeSinceStart()
		local rows = {}
		for l in ((body or ""):gsub("\r", "")):gmatch("[^\n]+") do
			local f = {}
			for v in (l .. "\t"):gmatch("([^\t]*)\t") do
				f[#f + 1] = v
			end
			rows[#rows + 1] = f
		end
		if status ~= 200 or not rows[1] or rows[1][1] ~= "OK" then
			return -- keep the local lists
		end
		local best, recent, top = {}, {}, {}
		for i = 2, #rows do
			local f = rows[i]
			-- failed plays are left out
			if f[1] == "B" then
				local e = siteEntry(f)
				if e.lamp < 6 and e.playLamp < 6 then
					best[#best + 1] = e
					top[#top + 1] = e
				end
			elseif f[1] == "R" then
				local e = siteEntry(f)
				e.lamp = e.playLamp -- a single play shows its own lamp
				if e.lamp < 6 then
					recent[#recent + 1] = e
				end
			end
		end
		table.sort(best, function(a, b)
			if a.level ~= b.level then return a.level > b.level end
			if a.lamp ~= b.lamp then return a.lamp < b.lamp end
			return a.rate > b.rate
		end)
		table.sort(top, function(a, b)
			return a.rate > b.rate
		end)
		siteLists = {best = best, recent = recent, top = top}
		MESSAGEMAN:Broadcast("BMSProfileRefresh")
	end)
end

local function current()
	if siteLists then
		return siteLists[mode] or {}
	end
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
	loadSite()
	page = 0
end)

-- header: name, rating and play count, the modes on the right
t[#t + 1] = W.text(8, W.top + 12, 0.42, 0) .. {
	ShowCommand = function(self)
		local profile = PROFILEMAN:GetProfile(PLAYER_1)
		self:settext(profile:GetDisplayName() .. (siteLists and "  (site)" or "")):maxwidth(150 / 0.42)
	end,
}
t[#t + 1] = W.text(8, W.top + 30, 0.34, 0) .. {
	ShowCommand = function(self)
		local counts = {0, 0, 0, 0, 0}
		local best = (siteLists or lists).best or {}
		for _, e in ipairs(best) do
			counts[e.lamp] = (counts[e.lamp] or 0) + 1
		end
		self:settextf("%d charts   FC %d   HARD %d   CLEAR %d   EASY %d", #best,
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
			if e and e.song then
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
				self:settext(e and e.title or "")
				-- invalid scores in red like Til Death
				self:diffuse(e and not e.valid and W.red or W.white)
			end,
		},
		W.text(col.rateX, y, 0.3, 0.5) .. {
			ShowCommand = function(self)
				local e = entry(i)
				self:settext(e and e.rateText or "")
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
				self:settext(e and e.date or ""):diffuse(W.gray)
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
