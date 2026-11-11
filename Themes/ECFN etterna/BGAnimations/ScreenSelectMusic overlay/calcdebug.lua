-- Clear calc debug view (Scripts/BMSClearCalc.lua) for 7k song select, drawn
-- over the whole screen above the wheel.
--   F5  open / close
--   F6  next graph (note difficulty, miss chance, expected gauge)
--   F7  next pattern shaded over the graph (a click on a pattern name too)
-- F-keys because the letter keys are 7k lanes and move the wheel.

local dbg = {open = false, graph = 1, focus = 0, data = nil}
local graphs = {"NOTE DIFFICULTY", "MISS CHANCE", "EXPECTED GAUGE"}
local BINS = 300

-- laid out in 1080p pixels and zoomed to the screen (the theme's screen is
-- 480 high)
local Z = SCREEN_HEIGHT / 1080
local SW, SH = SCREEN_WIDTH / Z, 1080
local m = 24
local legendW = 230
local gx, gy = m + legendW, 120
local gw = SW - gx - m
local bandH, bandGap = 26, 6
local nPat = #BMSCalcPatterns
local bandsH = nPat * (bandH + bandGap)
local gh = SH - gy - 50 - bandsH - 40
local by = gy + gh + 46

local gaugeColors = {color("#7dff4f"), color("#ffffff"), color("#ff4a4a")}
local gaugeNames = {"EASY", "GROOVE", "HARD"}
local partColors = {color("#b0b0b0"), color("#4fa3ff"), color("#ff4f6a"), color("#ffd23a")}
local partNames = {"DENSITY", "HAND", "JACK", "CHORD"}

local function rgba(hex, a)
	local c = color(hex)
	c[4] = a
	return c
end

local function quad(v, x1, y1, x2, y2, c)
	v[#v + 1] = {{x1, y1, 0}, c}
	v[#v + 1] = {{x2, y1, 0}, c}
	v[#v + 1] = {{x2, y2, 0}, c}
	v[#v + 1] = {{x1, y2, 0}, c}
end

local function Quads(x, y, build)
	return Def.ActorMultiVertex {
		InitCommand = function(self)
			self:xy(x, y)
		end,
		DrawCommand = function(self)
			local v = {}
			if dbg.data then
				build(v, dbg.data)
			end
			if #v == 0 then
				self:visible(false)
				return
			end
			self:visible(true):SetVertices(v)
			self:SetDrawState {Mode = "DrawMode_Quads", First = 1, Num = #v}
		end,
	}
end

-- text of a height in screen pixels, y is its middle
local function Text(x, y, h, align, maxw, get, c)
	return LoadFont("Common Normal") .. {
		InitCommand = function(self)
			self:xy(x, y):halign(align):valign(0.5)
			self:settext("Ag")
			local z = h / self:GetHeight() * 1.25
			self:zoom(z)
			if maxw then
				self:maxwidth(maxw / z)
			end
			self:diffuse(c or color("1,1,1,1"))
			self:settext("")
		end,
		DrawCommand = function(self)
			self:settext(get() or "")
		end,
	}
end

local function currentRate()
	return GAMESTATE:GetSongOptionsObject("ModsLevel_Preferred"):MusicRate()
end

local function load()
	dbg.data = nil
	local steps = GAMESTATE:GetCurrentSteps()
	if not dbg.open or not steps or not getBMSClearDebug then
		return
	end
	local ok, d = pcall(getBMSClearDebug, steps, currentRate())
	if ok and d then
		d.first = d.t[1]
		d.last = math.max(d.t[#d.t], d.first + 1)
		dbg.data = d
	elseif not ok then
		SCREENMAN:SystemMessage("clear calc debug: " .. tostring(d))
	end
end

local function xOf(d, time)
	return (time - d.first) / (d.last - d.first) * gw
end

-- the notes of every bar, by index into the chart's notes
local function bins(d)
	local b = {}
	for i = 1, BINS do
		b[i] = {}
	end
	for i, time in ipairs(d.t) do
		local k = math.min(BINS, math.floor((time - d.first) / (d.last - d.first) * BINS) + 1)
		local list = b[k]
		list[#list + 1] = i
	end
	return b
end

local function mmss(s)
	s = math.max(0, math.floor(s + 0.5))
	return string.format("%d:%02d", math.floor(s / 60), s % 60)
end

local t = Def.ActorFrame {
	Name = "ClearCalcDebug",
	InitCommand = function(self)
		self:zoom(Z):visible(false)
	end,
	BeginCommand = function(self)
		SCREENMAN:GetTopScreen():AddInputCallback(function(event)
			if event.type ~= "InputEventType_FirstPress" or not hideMSD() then
				return false
			end
			local b = event.DeviceInput.button
			if b == "DeviceButton_F5" then
				dbg.open = not dbg.open
				load()
			elseif b == "DeviceButton_F6" and dbg.open then
				dbg.graph = dbg.graph % #graphs + 1
			elseif b == "DeviceButton_F7" and dbg.open then
				dbg.focus = (dbg.focus + 1) % (nPat + 1)
			else
				return false
			end
			self:visible(dbg.open)
			self:playcommand("Draw")
			return true
		end)
	end,
	-- another chart: blank until the wheel stops, then the calc runs once
	CurrentSongChangedMessageCommand = function(self)
		if dbg.open then
			dbg.data = nil
			self:playcommand("Draw")
		end
	end,
	CurrentStepsChangedMessageCommand = function(self)
		self:playcommand("CurrentSongChangedMessage")
	end,
	DelayedChartUpdateMessageCommand = function(self)
		if dbg.open then
			load()
			self:playcommand("Draw")
		end
	end,
	CurrentRateChangedMessageCommand = function(self)
		self:playcommand("DelayedChartUpdateMessage")
	end,
}

-- opaque backdrop, the graph area and its grid
t[#t + 1] = Def.Quad {
	InitCommand = function(self)
		self:halign(0):valign(0):zoomto(SW, SH):diffuse(color("0.03,0.04,0.07,0.985"))
	end,
}
t[#t + 1] = Def.Quad {
	InitCommand = function(self)
		self:halign(0):valign(0):xy(gx, gy):zoomto(gw, gh):diffuse(color("0.09,0.10,0.14,1"))
	end,
}
t[#t + 1] = Quads(gx, gy, function(v)
	for k = 1, 3 do
		local y = gh * k / 4
		quad(v, 0, y - 0.5, gw, y + 0.5, color("1,1,1,0.10"))
	end
end)

-- header
t[#t + 1] = Text(m, 30, 30, 0, SW * 0.6, function()
	local focus = BMSCalcPatterns[dbg.focus]
	return "CLEAR CALC  -  " .. graphs[dbg.graph] .. (focus and ("  -  " .. focus.name) or "")
end, color("#ffc040"))
t[#t + 1] = Text(SW - m, 30, 18, 1, SW * 0.38, function()
	return "F5 close    F6 graph    F7 pattern"
end, color("#9fc8ff"))
t[#t + 1] = Text(m, 72, 26, 0, SW * 0.45, function()
	local d = dbg.data
	if not d then
		return GAMESTATE:GetCurrentSteps() and "waiting for the wheel to stop..." or "no chart"
	end
	local g = d.gauges
	local pre = d.prefix or ""
	return string.format("EASY %s%.1f    GROOVE %s%.1f    HARD %s%.1f", pre, g[1].star, pre, g[2].star, pre, g[3].star)
end)
t[#t + 1] = Text(SW - m, 72, 17, 1, SW * 0.5, function()
	local d = dbg.data
	if not d then return nil end
	local g = d.gauges
	return string.format("skill %.0f / %.0f / %.0f     TOTAL %.0f    %d notes     easy +%.3f %.1f    hard +%.2f %.1f",
		math.exp(g[1].skill), math.exp(g[2].skill), math.exp(g[3].skill), d.total, d.notes,
		g[1].gain, g[1].poor, g[3].gain, g[3].poor)
end, color("1,1,1,0.75"))

-- focused pattern shaded over the graph
t[#t + 1] = Quads(gx, gy, function(v, d)
	local k = BMSCalcPatterns[dbg.focus]
	if not k then return end
	local c = rgba(k.color, 0.28)
	for _, r in ipairs(d.patterns[k.key] or {}) do
		local x1, x2 = xOf(d, r[1]), xOf(d, r[2])
		quad(v, x1, 0, math.max(x2, x1 + 3), gh, c)
	end
end)

-- the graph
local top = nil
t[#t + 1] = Quads(gx, gy, function(v, d)
	local b = bins(d)
	local bw = gw / BINS
	local function line(values, max, c, thick)
		local prev
		for i = 1, BINS do
			local val = values[i]
			if val then
				local y = gh - math.min(val / max, 1) * gh
				quad(v, (i - 1) * bw, y - thick, i * bw, y + thick, c)
				-- join steps so the line reads as one
				if prev and math.abs(prev - y) > thick then
					quad(v, (i - 1) * bw - thick / 2, math.min(prev, y), (i - 1) * bw + thick / 2, math.max(prev, y), c)
				end
				prev = y
			else
				prev = nil
			end
		end
	end
	if dbg.graph == 1 then
		-- the hardest note of every bar, split into its parts
		top = 0
		local hardest = {}
		for i = 1, BINS do
			for _, n in ipairs(b[i]) do
				if not hardest[i] or d.ld[n] > d.ld[hardest[i]] then
					hardest[i] = n
				end
			end
			if hardest[i] then
				top = math.max(top, math.exp(d.ld[hardest[i]]))
			end
		end
		for g = 1, 3 do
			top = math.max(top, math.exp(d.gauges[g].skill))
		end
		top = top * 1.05
		for i = 1, BINS do
			local n = hardest[i]
			if n then
				local y = gh
				for k, part in ipairs(d.parts[n]) do
					local h = part / top * gh
					if h > 0 then
						quad(v, (i - 1) * bw, y - h, i * bw - 1, y, partColors[k])
						y = y - h
					end
				end
			end
		end
		for g = 1, 3 do
			local y = gh - math.exp(d.gauges[g].skill) / top * gh
			quad(v, 0, y - 1.5, gw, y + 1.5, gaugeColors[g])
		end
	elseif dbg.graph == 2 then
		-- average miss chance of each bar at the skill each gauge needs
		top = 0.05
		local vals = {{}, {}, {}}
		for g = 1, 3 do
			for i = 1, BINS do
				local s, c = 0, 0
				for _, n in ipairs(b[i]) do
					s = s + d.gauges[g].miss[n]
					c = c + 1
				end
				if c > 0 then
					vals[g][i] = s / c
					top = math.max(top, s / c)
				end
			end
		end
		top = top * 1.05
		for g = 3, 1, -1 do
			line(vals[g], top, gaugeColors[g], 2)
		end
	else
		-- the expected gauge at the end of every bar
		top = 100
		-- where EASY and GROOVE have to end (the calc's TARGET)
		local y80 = gh * (1 - 0.4125)
		quad(v, 0, y80 - 1, gw, y80 + 1, color("0.5,1,0.4,0.5"))
		local y32 = gh * 0.68
		quad(v, 0, y32 - 1, gw, y32 + 1, color("1,0.3,0.3,0.4"))
		for g = 3, 1, -1 do
			local vals = {}
			for i = 1, BINS do
				local list = b[i]
				if #list > 0 then
					vals[i] = d.gauges[g].gauge[list[#list]]
				end
			end
			line(vals, 100, gaugeColors[g], 2)
		end
		-- where the HARD gauge is lowest
		local lowAt, lowV = nil, math.huge
		for n, val in ipairs(d.gauges[3].gauge) do
			if val < lowV then
				lowV, lowAt = val, n
			end
		end
		if lowAt then
			local x = xOf(d, d.t[lowAt])
			quad(v, x - 1.5, 0, x + 1.5, gh, color("1,0.3,0.3,0.9"))
		end
	end
	-- a tick every 30 seconds
	for s = 30, d.last - d.first, 30 do
		local x = s / (d.last - d.first) * gw
		quad(v, x - 1, gh, x + 1, gh + 10, color("1,1,1,0.6"))
	end
end)

-- axis labels
t[#t + 1] = Text(gx - 10, gy + 10, 16, 1, legendW - 20, function()
	if not dbg.data or not top then return nil end
	if dbg.graph == 2 then return string.format("%.0f%%", top * 100) end
	if dbg.graph == 3 then return "100%" end
	return string.format("%.0f", top)
end, color("1,1,1,0.7"))
t[#t + 1] = Text(gx - 10, gy + gh - 10, 16, 1, legendW - 20, function()
	return dbg.data and "0" or nil
end, color("1,1,1,0.7"))
t[#t + 1] = Text(gx, gy + gh + 22, 16, 0, 120, function()
	return dbg.data and mmss(dbg.data.first) or nil
end, color("1,1,1,0.7"))
t[#t + 1] = Text(gx + gw, gy + gh + 22, 16, 1, 120, function()
	return dbg.data and mmss(dbg.data.last) or nil
end, color("1,1,1,0.7"))
t[#t + 1] = Text(gx + gw / 2, gy + gh + 22, 15, 0.5, gw * 0.8, function()
	if not dbg.data then return nil end
	if dbg.graph == 1 then return "hardest note in each bar; lines: skill each gauge needs" end
	if dbg.graph == 2 then return "average miss chance in each bar, for a player who just clears each gauge" end
	return "expected gauge for a player who just clears it; lines at the EASY/GROOVE goal (41%) and 32%, red: where HARD is lowest"
end, color("1,1,1,0.55"))

-- legend
for k = 1, 4 do
	local y = gy + 30 + 34 * (k - 1)
	t[#t + 1] = Quads(m, y, function(v)
		local cols = dbg.graph == 1 and partColors or gaugeColors
		if cols[k] then
			quad(v, 0, -9, 18, 9, cols[k])
		end
	end)
	t[#t + 1] = Text(m + 28, y, 20, 0, legendW - 40, function()
		if dbg.graph == 1 then return partNames[k] end
		return gaugeNames[k]
	end)
end
for g = 1, 3 do
	local y = gy + 30 + 34 * 4 + 20 + 28 * (g - 1)
	t[#t + 1] = Quads(m, y, function(v)
		if dbg.graph == 1 then
			quad(v, 0, -2, 18, 2, gaugeColors[g])
		end
	end)
	t[#t + 1] = Text(m + 28, y, 16, 0, legendW - 40, function()
		if dbg.graph ~= 1 then return nil end
		return gaugeNames[g] .. " SKILL"
	end, color("1,1,1,0.8"))
end

-- one strip per pattern under the graph
for k, pk in ipairs(BMSCalcPatterns) do
	local y = by + (k - 1) * (bandH + bandGap)
	t[#t + 1] = Text(m, y + bandH / 2, 19, 0, legendW - 80, function()
		return pk.name
	end, color(pk.color))
	t[#t + 1] = Text(gx - 10, y + bandH / 2, 16, 1, 70, function()
		local d = dbg.data
		if not d then return nil end
		local s = 0
		for _, r in ipairs(d.patterns[pk.key] or {}) do
			s = s + (r[2] - r[1])
		end
		return string.format("%ds", math.floor(s + 0.5))
	end, color("1,1,1,0.6"))
	t[#t + 1] = Quads(gx, y, function(v, d)
		local focused = dbg.focus == k
		quad(v, 0, 0, gw, bandH, color(focused and "0.24,0.24,0.32,1" or "0.11,0.12,0.16,1"))
		local c = rgba(pk.color, (dbg.focus == 0 or focused) and 1 or 0.35)
		for _, r in ipairs(d.patterns[pk.key] or {}) do
			local x1, x2 = xOf(d, r[1]), xOf(d, r[2])
			quad(v, x1, 3, math.max(x2, x1 + 3), bandH - 3, c)
		end
	end)
	t[#t + 1] = UIElements.QuadButton(1, 1) .. {
		InitCommand = function(self)
			self:halign(0):valign(0):xy(m, y):zoomto(legendW, bandH):diffusealpha(0)
		end,
		MouseDownCommand = function(self, params)
			if dbg.open and params.event == "DeviceButton_left mouse button" then
				dbg.focus = dbg.focus == k and 0 or k
				self:GetParent():playcommand("Draw")
			end
		end,
	}
end

return t
