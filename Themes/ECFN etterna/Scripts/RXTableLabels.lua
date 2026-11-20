-- Res Extensa theme: the LV column of the Recommend and Profile windows lists
-- every table a chart is in ("★12 sl8 dl3"), like the song select line
-- (Scripts/RXTables.lua). A chart on this computer asks RXTables (the local
-- BMS2SM packs plus the site's tablecharts.json, a static file: no database
-- reads); a chart that is not here uses the table list the caller has (the
-- Recommend window's tablecharts.json rows), else the one label it had.

local prefixes = {
	insane = "★", overjoy = "★★", satellite = "sl", stella = "st", o2jam = "Lv",
	delay = "///", delayjoy = "dl", dystopia = "dy", ude = "Ude", gachimijoy = "双",
}
-- odd dl folders, like the site's LV_ODD: dlBEGINNER is -9, dlDELAYMASTER 13
local odd = {delayjoy = {[-9] = "BEG", [13] = "MASTER"}}
local function oddText(text)
	return (text:gsub("dl%-9", "dlBEG"):gsub("dl13", "dlMASTER"))
end
local order = {insane = 1, satellite = 2, stella = 3, overjoy = 4, delayjoy = 5, delay = 6, dystopia = 7, ude = 8, gachimijoy = 9}

-- {{t = "satellite", l = 8}, ...} -> "sl8 st3"
local function fromList(lv)
	local seen, list = {}, {}
	for _, x in ipairs(lv or {}) do
		if x.t and not seen[x.t] then
			seen[x.t] = true
			list[#list + 1] = x
		end
	end
	if #list == 0 then
		return nil
	end
	table.sort(list, function(a, b)
		return (order[a.t] or 99) < (order[b.t] or 99)
	end)
	local parts = {}
	for _, x in ipairs(list) do
		parts[#parts + 1] = (prefixes[x.t] or x.t) ..
			((x.l == nil or x.l >= 99) and "?" or (odd[x.t] and odd[x.t][x.l]) or tostring(x.l))
	end
	return table.concat(parts, " ")
end

-- chart key -> the Recommend window's rows (BMSTableCharts), built when that
-- list changes
local tcList, tcMap
local function fromTableCharts(ck)
	if not BMSTableCharts or #BMSTableCharts == 0 then
		return nil
	end
	if tcList ~= BMSTableCharts then
		tcList, tcMap = BMSTableCharts, {}
		for _, c in ipairs(BMSTableCharts) do
			tcMap[c.ck] = c.lv
		end
	end
	return tcMap[ck]
end

-- every table of a chart as short text, else fallback
function rxTablesLabel(ck, steps, song, lv, fallback)
	if steps and rxChartTablesText then
		if rxRequestChartTables then
			rxRequestChartTables(steps)
		end
		local ok, text = pcall(rxChartTablesText, steps, song)
		if ok and text then
			return oddText((text:gsub("%s+·%s+", " ")))
		end
	end
	return fromList(lv or (ck and fromTableCharts(ck))) or fallback
end
