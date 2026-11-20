-- Res Extensa theme: every difficulty table a chart is in. A chart in several
-- tables sits in several packs ("BMS2SM - sl08" and "BMS2SM - st03") with the
-- same chart key, so the Songs folder says them all, the same way the site's
-- tools/chart_tables.py builds its chart_tables. The site's tablecharts.json
-- (every chart of every table, made by tools/chart_tables.py) adds tables
-- the local packs do not have. It is a static file, so it costs the site no
-- database reads: the copy on this computer is used right away and the
-- site's copy is fetched once per game start. (This used to ask the site
-- for every chart hovered, three database queries each.)

-- the site's short names (public/app.js LV_PREFIX): sl8, st3, ★12, ★★5
local prefixes = {
	insane = "★", overjoy = "★★", satellite = "sl", stella = "st", o2jam = "Lv",
	delay = "///", delayjoy = "dl", dystopia = "dy", ude = "Ude", gachimijoy = "双",
}
local order = {insane = 1, satellite = 2, stella = 3, overjoy = 4, delayjoy = 5, delay = 6, dystopia = 7, ude = 8, gachimijoy = 9}
-- pack names ("BMS2SM - sl05") to tables, like the site's tools/chart_tables.py
local packs = {
	sp = "insane", sl = "satellite", st = "stella", oj = "overjoy", overjoy = "overjoy",
	dl = "delayjoy", dy = "dystopia", ude = "ude", gachi = "gachimijoy",
}

-- odd dl folders, like the site's LV_ODD and RXTableLabels: -9 is BEG, 13 MASTER
local odd = {delayjoy = {[-9] = "BEG", [13] = "MASTER"}}
local function label(tbl, level)
	return (prefixes[tbl] or tbl) ..
		((level == nil or level >= 99) and "?" or (odd[tbl] and odd[tbl][level]) or tostring(level))
end

-- "satellite:8,stella:3" -> {{"satellite", 8}, {"stella", 3}}
local function fromLvls(lvls)
	local list = {}
	for tbl, lvl in tostring(lvls):gmatch("([%a_]+):(%-?%d+)") do
		list[#list + 1] = {tbl, tonumber(lvl)}
	end
	return list
end

-- the table and level of a pack name, or nil
local function packTable(group)
	local prefix, num = (group or ""):lower():match("^bms2sm %- (%a+)%s*(%d*)")
	local tbl = prefix and packs[prefix]
	if not tbl then
		return nil
	end
	return tbl, tonumber(num)
end

-- chart key -> {{table, level}, ...} over every pack, built once
local index
local function buildIndex()
	index = {}
	for _, song in ipairs(SONGMAN:GetAllSongs()) do
		local tbl, lvl = packTable(song:GetGroupName())
		if tbl then
			for _, st in ipairs(song:GetAllSteps()) do
				if st:GetStepsType() == "StepsType_Kb7_Single" then
					local ck = st:GetChartKey()
					local l = index[ck]
					if not l then
						l = {}
						index[ck] = l
					end
					l[#l + 1] = {tbl, lvl}
				end
			end
		end
	end
end

-- the lists merged, one entry per table, in the site's order, as text
local function format(...)
	local seen, list = {}, {}
	for _, l in ipairs({...}) do
		for _, e in ipairs(l) do
			if not seen[e[1]] then
				seen[e[1]] = true
				list[#list + 1] = e
			end
		end
	end
	if #list == 0 then
		return nil
	end
	table.sort(list, function(a, b)
		return (order[a[1]] or 99) < (order[b[1]] or 99)
	end)
	local parts = {}
	for _, e in ipairs(list) do
		parts[#parts + 1] = label(e[1], e[2])
	end
	return table.concat(parts, "  ·  ")
end

-- chart key -> {{table, level}, ...} from the site's tablecharts.json
local byKey = nil
local fetched = false

local function readFile(path)
	local str
	local f = RageFileUtil.CreateRageFile()
	if f:Open(path, 1) then
		str = f:Read()
		f:Close()
	end
	f:destroy()
	if str and str ~= "" then
		return str
	end
	return nil
end

local function writeFile(path, str)
	local f = RageFileUtil.CreateRageFile()
	if f:Open(path, 2) then
		f:Write(str)
		f:Close()
	end
	f:destroy()
end

-- {"insane":{"12":[["key","title"],...],...},"satellite":{...},...} -> byKey
-- (read with patterns, the file is big; a table starts at "name":{ and a
-- level at "12":[)
local function parseTC(str)
	if not str or str:sub(1, 1) ~= "{" then
		return nil
	end
	local starts = {}
	for t in pairs(prefixes) do
		local _, b = str:find('"' .. t .. '":{', 1, true)
		if b then
			starts[#starts + 1] = {t = t, from = b}
		end
	end
	if #starts == 0 then
		return nil
	end
	table.sort(starts, function(x, y)
		return x.from < y.from
	end)
	local out = {}
	for i, s in ipairs(starts) do
		local part = str:sub(s.from, starts[i + 1] and starts[i + 1].from or #str)
		for l, body in part:gmatch('"([^"]+)":%[(.-)"%]%]') do
			local lv = tonumber(l)
			if lv then
				for ck in (body .. '"]'):gmatch('%["(X%x+)",') do
					local list = out[ck]
					if not list then
						list = {}
						out[ck] = list
					end
					list[#list + 1] = {s.t, lv}
				end
			end
		end
	end
	return out
end

local function loadTC()
	if byKey then
		return
	end
	-- the site's own folder (the computer that runs the site), else the copy
	-- downloaded last time (the Recommend window keeps one there too)
	byKey = parseTC(readFile("/leaderboard/site/public/tablecharts.json"))
		or parseTC(readFile("/Save/BMSCache/tablecharts.json"))
		or {}
end

-- once per game start: the site's newest tablecharts.json (a static file,
-- no database reads), kept in Save/BMSCache for next time
local function fetch()
	if fetched or not DLMAN or not DLMAN.BMSRequest then
		return
	end
	fetched = true
	DLMAN:BMSRequest("GET", "/tablecharts.json", {}, function(status, body)
		local got = status == 200 and parseTC(body)
		if got and next(got) then
			byKey = got
			writeFile("/Save/BMSCache/tablecharts.json", body)
			MESSAGEMAN:Broadcast("BMSChartTables", {})
		end
	end)
end

function rxRequestChartTables(steps)
	if not index then
		buildIndex()
		MESSAGEMAN:Broadcast("BMSChartTables", {})
	end
	loadTC()
	fetch()
end

-- what to show: every table from the packs, then the site's list, else the
-- table of this song's own pack
function rxChartTablesText(steps, song)
	if not steps then
		return nil
	end
	local ck = steps:GetChartKey()
	loadTC()
	local own = {}
	local tbl, lvl = packTable(song and song:GetGroupName())
	if tbl then
		own[1] = {tbl, lvl}
	end
	return format(index and index[ck] or {}, byKey[ck] or {}, own)
end
