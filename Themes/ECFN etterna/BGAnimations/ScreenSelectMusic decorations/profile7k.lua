-- 7k: the "Profile" window (key 2) in the Dan window's look (Scripts/
-- ECFNWindow.lua). BEST lists the best play of every 7k chart sorted by its
-- Good enough rating (like the site's profile; O2Jam charts by level and
-- lamp), RECENT the latest plays, TOP the best EX rates. Clicking a row
-- moves the wheel to its song. Logged in to the ranking site, the lists come
-- from the site (every computer's plays), else from this computer's scores.
-- BMS / O2JAM switches between BMS charts (EX%, LR2 lamps) and O2Jam charts
-- (.ojn: DMJam score in percent with its grade, O2Jam lamps).
local W = ECFNWindow
local tab = 4
local listY = W.top + 62
local rows = 17
local mode = "best"
-- kept in a global so the choice stays when the screen is reloaded
BMSProfileGame = BMSProfileGame or "bms"
local page = 0
local lists = {bms = {}, o2jam = {}}

local function isO2()
	return BMSProfileGame == "o2jam"
end

-- best 1.0x play of an O2Jam chart: best lamp, highest DMJam score
local function bestO2Jam(ck)
	local lamp, bestScore, bestValue
	local rates = SCOREMAN:GetScoresByKey(ck)
	if not rates then
		return nil
	end
	for _, hsl in pairs(rates) do
		for _, s in ipairs(hsl:GetScores()) do
			if s:GetMusicRate() > 0.999 then
				local l = getBMSLampFromScore(s)
				if l < 6 then
					local v = getO2JamScore(s)
					if lamp == nil or l < lamp then
						lamp = l
					end
					if bestValue == nil or v > bestValue then
						bestValue, bestScore = v, s
					end
				end
			end
		end
	end
	return lamp, bestScore, bestValue
end

-- Good enough rating of a chart: its clear calc Easy and Hard values on the
-- insane ★ scale, the numbers the site shows. They come from the site's
-- calcrating.json when it is on this computer (the exact site numbers), else
-- from the game's clear calc.
local GR_FILE = "/leaderboard/site/public/calcrating.json"
local function loadGR()
	if BMSGoodRatingFile then
		return BMSGoodRatingFile
	end
	local out = {}
	local f = RageFileUtil.CreateRageFile()
	if f:Open(GR_FILE, 1) then
		local str = f:Read() or ""
		f:Close()
		for k, e, h in str:gmatch('"([^"]+)":%[(-?[%d%.]+),(-?[%d%.]+)%]') do
			out[k] = {tonumber(e), tonumber(h)}
		end
	end
	f:destroy()
	-- kept in a global: read once per game start
	BMSGoodRatingFile = out
	return out
end

local grCalc = {}
local function chartGR(ck, steps)
	local v = loadGR()[ck]
	if v then
		return v
	end
	if grCalc[ck] ~= nil then
		return grCalc[ck] or nil
	end
	grCalc[ck] = false
	steps = steps or SONGMAN:GetStepsByChartKey(ck)
	if steps and getBMSClearDifficulty then
		-- the calc on the insane scale, whatever scale the wheel shows
		local was = BMSClearScale
		BMSClearScale = "insane"
		local ok, e, _, h = pcall(getBMSClearDifficulty, steps, 1)
		BMSClearScale = was
		if ok and e and h then
			grCalc[ck] = {e, h}
		end
	end
	return grCalc[ck] or nil
end

-- the rating a lamp is worth: Easy value for EASY and CLEAR, Hard value for
-- HARD, EX HARD and FC, nil when failed or the chart has no rating
local function lampGR(e)
	if e.o2 or not e.lamp or e.lamp < 1 or e.lamp > 5 then
		return nil
	end
	local g = chartGR(e.ck, e.steps)
	return g and (e.lamp <= 3 and g[2] or g[1]) or nil
end

local function sortLists(best, top)
	for _, e in ipairs(best) do
		e.gr = lampGR(e)
	end
	table.sort(best, function(a, b)
		-- highest rating first, charts without one after (like the site)
		local ga, gb = a.gr or -99, b.gr or -99
		if ga ~= gb then return ga > gb end
		if a.level ~= b.level then return a.level > b.level end
		if a.lamp ~= b.lamp then return a.lamp < b.lamp end
		return a.rate > b.rate
	end)
	table.sort(top, function(a, b)
		return a.rate > b.rate
	end)
end

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
			local o2 = isO2JamSteps(steps)
			local level, levelName
			if o2 then
				level = steps:GetMeter()
				levelName = "Lv" .. level
			else
				level, levelName = getBMSLevel(song, steps)
			end
			all[#all + 1] = {
				score = hs, ck = ck, song = song, steps = steps, level = level, levelName = levelName,
				o2 = o2, rate = o2 and getO2JamScore(hs) / 100 or getBMSScoreRate(hs),
				lamp = getBMSLampFromScore(hs),
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

	for _, g in ipairs({"bms", "o2jam"}) do
		local o2 = g == "o2jam"
		-- failed plays are left out
		local shown = {}
		for _, e in ipairs(all) do
			if e.o2 == o2 and e.lamp < 6 then
				shown[#shown + 1] = e
			end
		end

		-- best per chart: lamp from 1.0x plays, the best EX rate (DMJam score) among them
		local best, top = {}, {}
		local seen = {}
		for _, e in ipairs(all) do
			if e.o2 == o2 and not seen[e.ck] then
				seen[e.ck] = true
				local lamp, bestScore, value
				if o2 then
					lamp, bestScore, value = bestO2Jam(e.ck)
				else
					lamp, bestScore = getBestBMSLamp(e.ck)
				end
				if lamp and lamp < 6 then
					best[#best + 1] = {
						score = bestScore, ck = e.ck, song = e.song, steps = e.steps, level = e.level,
						levelName = e.levelName, o2 = o2, lamp = lamp,
						rate = o2 and value / 100 or getBMSScoreRate(bestScore),
						title = e.title, rateText = getRateString(notShit.round(bestScore:GetMusicRate(), 3)),
						date = bestScore:GetDate():sub(1, 10), valid = bestScore:GetEtternaValid(),
					}
				end
			end
		end
		for _, e in ipairs(best) do
			top[#top + 1] = e
		end
		sortLists(best, top)
		lists[g] = {best = best, recent = shown, top = top}
	end
end

---------------------------------------------------------------------------
-- the same lists from the ranking site (POST /api/game/myscores)
---------------------------------------------------------------------------

local siteLists -- {bms = {best, recent, top}, o2jam = {...}} once the site answered
local sitePending = false
local siteTime
-- how hard a level is on the insane scale, to sort the tables together
-- (the site's SL_AS_INSANE / ST_AS_INSANE / OJ_AS_INSANE)
local SL = {[0] = 0, 1.5, 3.5, 5, 6.75, 9.25, 11, 12, 14, 16, 17.2, 18, 19}
local ST = {[0] = 19.5, 21, 22, 22.75, 23.5, 24, 24.5, 25.25, 25.75, 26.5, 27.25, 27.75, 28.5}
local OJ = {[0] = 23, 24, 25, 26, 27, 28, 29, 30, 31}
local prefix = {insane = "★", satellite = "sl", stella = "st", overjoy = "★★", o2jam = "Lv"}

local function siteEntry(f)
	local ck, tbl, lv = f[2], f[8] or "", tonumber(f[9])
	local notes = math.max(tonumber(f[6]) or 0, 1)
	local o2 = tbl == "o2jam"
	local hard = lv or -1
	if tbl == "satellite" then
		hard = (SL[lv or -1] or (lv or 0) * 1.6) + 0.01
	elseif tbl == "stella" then
		hard = (ST[lv or -1] or 19.5 + (lv or 0) * 0.75) + 0.02
	elseif tbl == "overjoy" then
		hard = (OJ[lv or -1] or 23 + (lv or 0)) + 0.03
	end
	local song = SONGMAN:GetSongByChartKey(ck)
	local ex = tonumber(f[5]) or 0
	return {
		ck = ck, song = song, o2 = o2,
		level = hard,
		levelName = lv and ((prefix[tbl] or "★") .. lv) or "?",
		title = song and song:GetDisplayMainTitle() or (f[10] or "?"),
		lamp = math.max(1, math.min(6, tonumber(f[4]) or 6)),
		playLamp = math.max(1, math.min(6, tonumber(f[3]) or 6)),
		-- O2Jam: the site keeps the DMJam score in thousandths of a percent
		rate = o2 and ex / 100000 or ex / (notes * 2),
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
		local out = {}
		for _, g in ipairs({"bms", "o2jam"}) do
			out[g] = {best = {}, recent = {}, top = {}}
		end
		for i = 2, #rows do
			local f = rows[i]
			-- failed plays are left out
			if f[1] == "B" then
				local e = siteEntry(f)
				local l = out[e.o2 and "o2jam" or "bms"]
				if e.lamp < 6 and e.playLamp < 6 then
					l.best[#l.best + 1] = e
					l.top[#l.top + 1] = e
				end
			elseif f[1] == "R" then
				local e = siteEntry(f)
				local l = out[e.o2 and "o2jam" or "bms"]
				e.lamp = e.playLamp -- a single play shows its own lamp
				if e.lamp < 6 then
					l.recent[#l.recent + 1] = e
				end
			end
		end
		for _, l in pairs(out) do
			sortLists(l.best, l.top)
		end
		siteLists = out
		MESSAGEMAN:Broadcast("BMSProfileRefresh")
	end)
end

local function currentGame()
	return (siteLists or lists)[BMSProfileGame] or {}
end

local function current()
	return currentGame()[mode] or {}
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
		local best = currentGame().best or {}
		for _, e in ipairs(best) do
			counts[e.lamp] = (counts[e.lamp] or 0) + 1
		end
		if isO2() then
			local sum = 0
			for _, e in ipairs(best) do
				sum = sum + e.rate
			end
			self:settextf("%d charts   FC %d   HARD %d   avg %.2f%%", #best, counts[1], counts[3],
				#best > 0 and sum / #best * 100 or 0)
		else
			self:settextf("%d charts   FC %d   EXH %d   HARD %d   CLEAR %d   EASY %d", #best,
				counts[1], counts[2], counts[3], counts[4], counts[5])
		end
		self:diffuse(W.gray)
		-- the BMS / O2JAM switch sits on the right of this line
		self:maxwidth((W.width - 16 - 112) / 0.34)
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
-- BMS / O2JAM, under RECENT and TOP
local games = {{"bms", "BMS"}, {"o2jam", "O2JAM"}}
for k, g in ipairs(games) do
	t[#t + 1] = W.button(g[2], W.width - 8 - (3 - k) * 54 + 27, W.top + 30, 50, function()
		BMSProfileGame = g[1]
		page = 0
		MESSAGEMAN:Broadcast("BMSProfileRefresh")
	end, nil, function()
		return BMSProfileGame == g[1]
	end)
end
t.BMSProfileRefreshMessageCommand = function(self)
	if self.open then
		self:playcommand("Show")
	end
end

-- column names
local col = {num = 18, lv = 24, title = 62, gr = W.width - 172, rateX = W.width - 150, ex = W.width - 92, lamp = W.width - 62, date = W.width - 10}
local function head(x, align, label, o2label)
	t[#t + 1] = W.text(x, listY - 14, 0.3, align, function(self)
		self:settext(label):diffuse(W.gray)
	end) .. {
		ShowCommand = function(self)
			self:settext(o2label and isO2() and o2label or label)
		end,
	}
end
head(col.lv, 0, "LV")
head(col.title, 0, "TITLE")
t[#t + 1] = W.text(col.gr, listY - 14, 0.3, 1, function(self)
	self:diffuse(W.gray)
end) .. {
	ShowCommand = function(self)
		self:settext(isO2() and "" or "RATING")
	end,
}
head(col.rateX, 0.5, "RATE")
head(col.ex, 1, "EX%", "SCORE")
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
			self:maxwidth((col.gr - 40 - col.title) / 0.32)
		end) .. {
			ShowCommand = function(self)
				local e = entry(i)
				self:settext(e and e.title or "")
				-- invalid scores in red like Til Death
				self:diffuse(e and not e.valid and W.red or W.white)
			end,
		},
		-- the Good enough rating of the lamp (BEST), as on the site
		W.text(col.gr, y, 0.3, 1) .. {
			ShowCommand = function(self)
				local e = entry(i)
				local v = e and not e.o2 and (e.gr or lampGR(e))
				self:settext(v and string.format("★%.2f", v) or ""):diffuse(color("#ffd080"))
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
				if e and e.o2 then
					-- DMJam score with its O2Jam grade, in the grade's color
					local v = e.rate * 100
					local g = getO2JamGrade(v)
					self:settext(string.format("%s  %.2f%%", g, v)):diffuse(getO2JamGradeColor(g))
				else
					self:settext(e and string.format("%.2f%%", e.rate * 100) or ""):diffuse(W.white)
				end
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
			self:settext(isO2() and "No O2Jam plays yet" or "No plays yet"):diffuse(W.gray)
		else
			self:settextf("%d-%d of %d", page * rows + 1, math.min(n, (page + 1) * rows), n):diffuse(W.gray)
		end
	end,
}

return t
