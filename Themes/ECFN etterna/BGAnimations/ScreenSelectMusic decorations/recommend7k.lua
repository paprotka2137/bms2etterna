-- 7k: the "Recommend" window (key 6) in the Dan window's look (Scripts/
-- ECFNWindow.lua), the game's side of the site's "Next clears": charts of
-- the tables whose Good enough rating would raise the player's rating,
-- closest to it first. HARD lists charts to hard clear (HARD or better):
-- EASY and CLEAR lamps and also charts never played or only failed. CLEAR
-- lists charts to clear (EASY or CLEAR) that are not cleared yet. The chips
-- pick the tables the rating counts, like on the site. Every chart of the
-- tables counts (leaderboard/site/public/tablecharts.json), also ones not
-- on this computer (gray, a click does nothing). Logged in to the ranking
-- site, the lamps of every computer's plays count too. Clicking a row moves
-- the wheel to its song.
local W = ECFNWindow
local tab = 12
local listY = W.top + 62
local rows = 17
local RATING_TOP = 20
local page = 0
-- kept in globals so the choices stay when the screen is reloaded
BMSRecommendMode = BMSRecommendMode or "hard"
BMSRecommendTables = BMSRecommendTables or {insane = true, satellite = true, stella = true, overjoy = true}
local TABLES = {{"insane", "INSANE"}, {"satellite", "SATELLITE"}, {"stella", "STELLA"}, {"overjoy", "OVERJOY"}}
local prefix = {insane = "★", satellite = "sl", stella = "st", overjoy = "★★"}
local lists = {clear = {}, hard = {}}
local nowRating

---------------------------------------------------------------------------
-- Good enough rating of a chart: {Easy, Hard} on the insane ★ scale, from
-- the site's calcrating.json (shared with the Profile window), else the
-- game's clear calc
---------------------------------------------------------------------------
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
	BMSGoodRatingFile = out
	return out
end

local grCalc = {}
local function chartGR(ck)
	local v = loadGR()[ck]
	if v then
		return v
	end
	if grCalc[ck] ~= nil then
		return grCalc[ck] or nil
	end
	grCalc[ck] = false
	local steps = SONGMAN:GetStepsByChartKey(ck)
	if steps and getBMSClearDifficulty then
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

---------------------------------------------------------------------------
-- every chart of the tables: {ck, song (name), lv = {{t, l}, ...}}, read
-- once per game start from the site's tablecharts.json
---------------------------------------------------------------------------
local TC_FILE = "/leaderboard/site/public/tablecharts.json"
local function unescape(s)
	return (s:gsub('\\(["\\/])', "%1"))
end
local function loadTableCharts()
	if BMSTableCharts then
		return BMSTableCharts
	end
	local byKey, order = {}, {}
	local f = RageFileUtil.CreateRageFile()
	if f:Open(TC_FILE, 1) then
		local str = f:Read() or ""
		f:Close()
		-- where each table's part starts: {"insane":{"1":[["key","song"],...],...},"satellite":{...}}
		local starts = {}
		for _, t in ipairs(TABLES) do
			local a, b = str:find('"' .. t[1] .. '":{', 1, true)
			if b then
				starts[#starts + 1] = {t = t[1], from = b}
			end
		end
		table.sort(starts, function(x, y)
			return x.from < y.from
		end)
		for i, s in ipairs(starts) do
			local part = str:sub(s.from, starts[i + 1] and starts[i + 1].from or #str)
			for l, body in part:gmatch('"([^"]+)":%[(.-)"%]%]') do
				local lv = tonumber(l)
				for ck, song in (body .. '"]'):gmatch('%["([^"]+)","(.-)"%]') do
					local c = byKey[ck]
					if not c then
						c = {ck = ck, song = unescape(song), lv = {}}
						byKey[ck] = c
						order[#order + 1] = c
					end
					c.lv[#c.lv + 1] = {t = s.t, l = lv}
				end
			end
		end
	end
	f:destroy()
	BMSTableCharts = order
	return order
end

local function inTables(c)
	for _, x in ipairs(c.lv) do
		if BMSRecommendTables[x.t] then
			return x
		end
	end
	return nil
end

---------------------------------------------------------------------------
-- the player's best lamp of every chart (1 FC .. 5 EASY, 6 failed)
---------------------------------------------------------------------------
local localLamps = {}
local siteLamps
local sitePending = false
local siteTime

local function gatherLocal()
	localLamps = {}
	SCOREMAN:SortRecentScoresForGame()
	local n = 1
	local hs = SCOREMAN:GetRecentScoreForGame(n)
	local seen = {}
	while hs do
		local ck = hs:GetChartKey()
		if not seen[ck] then
			seen[ck] = true
			local lamp = getBestBMSLamp(ck)
			localLamps[ck] = lamp or 6
		end
		n = n + 1
		hs = SCOREMAN:GetRecentScoreForGame(n)
	end
end

local function lampOf(ck)
	local a, b = localLamps[ck], siteLamps and siteLamps[ck]
	if a and b then
		return math.min(a, b)
	end
	return a or b
end

local function avgTop(vals)
	local top = {}
	for _, v in ipairs(vals) do
		top[#top + 1] = v
	end
	table.sort(top, function(x, y)
		return x > y
	end)
	local n = math.min(#top, RATING_TOP)
	if n == 0 then
		return nil
	end
	local sum = 0
	for i = 1, n do
		sum = sum + top[i]
	end
	return sum / n, top
end

-- the site's nextClears: charts whose rating would raise the player's one
local function build()
	local charts = loadTableCharts()
	local best, vals = {}, {}
	for _, c in ipairs(charts) do
		local l = lampOf(c.ck)
		if l and l >= 1 and l <= 5 and inTables(c) then
			local g = chartGR(c.ck)
			if g then
				best[c.ck] = l <= 3 and g[2] or g[1]
				vals[#vals + 1] = best[c.ck]
			end
		end
	end
	local now, top = avgTop(vals)
	nowRating = now
	local floor = (top and #top >= RATING_TOP) and top[RATING_TOP] or -math.huge
	-- the rating with the chart at value v
	local function gain(ck, v)
		if best[ck] and best[ck] >= v then
			return nil
		end
		local after
		if best[ck] then
			local copy = {}
			for k, x in pairs(best) do
				copy[#copy + 1] = k == ck and v or x
			end
			after = avgTop(copy)
		else
			-- one more value: the new top 20 average
			local n = math.min(#vals, RATING_TOP)
			if n < RATING_TOP then
				after = ((now or 0) * n + v) / (n + 1)
			else
				after = now + (v - top[RATING_TOP]) / RATING_TOP
			end
		end
		return after - (now or 0)
	end
	local out = {clear = {}, hard = {}}
	for _, c in ipairs(charts) do
		local x = inTables(c)
		local g = x and chartGR(c.ck)
		if g then
			local l = lampOf(c.ck)
			local targets = {}
			if l == nil or l == 6 then
				targets[#targets + 1] = {"clear", g[1]}
			end
			if l == nil or l >= 4 then
				targets[#targets + 1] = {"hard", g[2]}
			end
			for _, tg in ipairs(targets) do
				local v = tg[2]
				if v > floor and not (now and v > now + 3) then
					local up = gain(c.ck, v)
					if up and up > 0.0005 then
						local list = out[tg[1]]
						list[#list + 1] = {
							ck = c.ck, v = v, gain = up, lamp = l, title = c.song,
							levelName = (prefix[x.t] or "★") .. (x.l or "?"),
						}
					end
				end
			end
		end
	end
	for _, list in pairs(out) do
		table.sort(list, function(a, b)
			local da = now and math.abs(a.v - now) or a.v
			local db = now and math.abs(b.v - now) or b.v
			if math.abs(da - db) > 1e-9 then
				return da < db
			end
			return a.gain > b.gain
		end)
	end
	lists = out
end

-- the best lamps of every computer's plays from the ranking site (the
-- Profile window's POST /api/game/myscores, "B" rows: best lamp in field 4)
local function loadSite()
	if not (BMSRanking and BMSRanking.loggedIn and BMSRanking.loggedIn()) then
		siteLamps = nil
		return
	end
	if sitePending or (siteTime and GetTimeSinceStart() - siteTime < 20) then
		return
	end
	sitePending = true
	DLMAN:BMSRequest("POST", "/api/game/myscores", {}, function(status, body)
		sitePending = false
		siteTime = GetTimeSinceStart()
		local out, ok = {}, false
		for l in ((body or ""):gsub("\r", "")):gmatch("[^\n]+") do
			local f = {}
			for v in (l .. "\t"):gmatch("([^\t]*)\t") do
				f[#f + 1] = v
			end
			if f[1] == "OK" then
				ok = true
			elseif f[1] == "B" and f[2] then
				local lamp = math.max(1, math.min(6, tonumber(f[4]) or 6))
				out[f[2]] = math.min(out[f[2]] or 6, lamp)
			end
		end
		if status ~= 200 or not ok then
			return
		end
		siteLamps = out
		build()
		MESSAGEMAN:Broadcast("BMSRecommendRefresh")
	end)
end

local function current()
	return lists[BMSRecommendMode] or {}
end
local function entry(i)
	return current()[page * rows + i]
end
local function pages()
	return math.max(1, math.ceil(#current() / rows))
end
local function refresh()
	MESSAGEMAN:Broadcast("BMSRecommendRefresh")
end

local t = W.frame(tab, "BMSRecommend", function()
	gatherLocal()
	build()
	loadSite()
	page = 0
end)
t.BMSRecommendRefreshMessageCommand = function(self)
	if self.open then
		self:playcommand("Show")
	end
end

-- header: the rating now, HARD / CLEAR on the right
t[#t + 1] = W.text(8, W.top + 12, 0.42, 0) .. {
	ShowCommand = function(self)
		self:settext("RATING " .. (nowRating and string.format("★%.2f", nowRating) or "–") ..
			(siteLamps and "  (site)" or "")):maxwidth((W.width - 130) / 0.42)
	end,
}
local modes = {{"hard", "HARD"}, {"clear", "CLEAR"}}
for k, m in ipairs(modes) do
	t[#t + 1] = W.button(m[2], W.width - 8 - (3 - k) * 54 + 27, W.top + 12, 50, function()
		BMSRecommendMode = m[1]
		page = 0
		refresh()
	end, nil, function()
		return BMSRecommendMode == m[1]
	end)
end
-- the tables the rating counts
for k, tb in ipairs(TABLES) do
	t[#t + 1] = W.button(tb[2], 8 + (k - 1) * 70 + 33, W.top + 32, 66, function()
		BMSRecommendTables[tb[1]] = not BMSRecommendTables[tb[1]]
		build()
		page = 0
		refresh()
	end, nil, function()
		return BMSRecommendTables[tb[1]]
	end)
end

-- column names
local col = {num = 18, lv = 24, title = 62, v = W.width - 112, now = W.width - 62, gain = W.width - 10}
local function head(x, align, label)
	t[#t + 1] = W.text(x, listY - 14, 0.3, align, function(self)
		self:settext(label):diffuse(W.gray)
	end)
end
head(col.lv, 0, "LV")
head(col.title, 0, "TITLE")
head(col.v, 1, "RATING")
head(col.now, 0.5, "NOW")
head(col.gain, 1, "GAIN")

for i = 1, rows do
	local y = listY + (i - 1) * W.rowH
	t[#t + 1] = Def.ActorFrame {
		ShowCommand = function(self)
			self:visible(entry(i) ~= nil)
		end,
		W.rowBand(i, y, nil, function(i)
			local e = entry(i)
			local song = e and SONGMAN:GetSongByChartKey(e.ck)
			if song then
				W.pickSong(song)
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
			self:maxwidth((col.v - 44 - col.title) / 0.32)
		end) .. {
			ShowCommand = function(self)
				local e = entry(i)
				local song = e and SONGMAN:GetSongByChartKey(e.ck)
				self:settext(e and (song and song:GetDisplayMainTitle() or e.title) or "")
				-- charts not on this computer in gray
				self:diffuse(song and W.white or W.gray)
			end,
		},
		-- the Good enough rating of the lamp to get
		W.text(col.v, y, 0.3, 1) .. {
			ShowCommand = function(self)
				local e = entry(i)
				self:settext(e and string.format("★%.2f", e.v) or ""):diffuse(color("#ffd080"))
			end,
		},
		W.text(col.now, y, 0.3, 0.5) .. {
			ShowCommand = function(self)
				local e = entry(i)
				if e and e.lamp then
					self:settext(getBMSLampInfo(e.lamp, 1)):diffuse(getBMSLampInfo(e.lamp, 2))
				else
					self:settext(e and "NO PLAY" or ""):diffuse(W.gray)
				end
			end,
		},
		W.text(col.gain, y, 0.3, 1) .. {
			ShowCommand = function(self)
				local e = entry(i)
				self:settext(e and string.format("+%.2f", e.gain) or ""):diffuse(W.green)
			end,
		},
	}
end

-- pages
local pageY = listY + rows * W.rowH + 8
t[#t + 1] = W.button("PREV", 34, pageY, 56, function()
	page = (page - 1) % pages()
	refresh()
end)
t[#t + 1] = W.button("NEXT", W.width - 34, pageY, 56, function()
	page = (page + 1) % pages()
	refresh()
end)
t[#t + 1] = W.text(W.width / 2, pageY, 0.3, 0.5) .. {
	ShowCommand = function(self)
		local n = #current()
		if #loadTableCharts() == 0 then
			self:settext("No table chart list (leaderboard/site/public/tablecharts.json)"):diffuse(W.gray)
		elseif n == 0 then
			self:settext("Nothing in these tables would raise the rating"):diffuse(W.gray)
		else
			self:settextf("%d-%d of %d", page * rows + 1, math.min(n, (page + 1) * rows), n):diffuse(W.gray)
		end
	end,
}
t[#t + 1] = W.text(W.width / 2, pageY + 16, 0.26, 0.5) .. {
	ShowCommand = function(self)
		self:settext(BMSRecommendMode == "hard"
			and "HARD or better: EASY / CLEAR lamps and charts not played or not cleared yet"
			or "EASY or CLEAR: charts not played or not cleared yet"):diffuse(W.gray)
	end,
}

return t
