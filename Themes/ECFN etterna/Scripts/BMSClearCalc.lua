-- How hard a 7k chart is to EASY clear and HARD clear, on the scale of the
-- chart's table (Satellite sl, Stella st, Overjoy oj) or on the insane ★
-- scale (sp, also for charts in no table), or of the scale picked by
-- clicking the numbers.
--
-- Every note gets a difficulty from how dense the chart is around it (all
-- notes, and the notes of its hand), how fast its column repeats (jacks) and
-- how big its chord is. A chord of n notes counts as n^a notes in the
-- densities, since it is hit at once. A player of skill S misses a note of
-- difficulty d with chance 1 / (1 + (S / d)^k). The expected gauge is run
-- through the chart with this fork's LR2 gauge rules (TOTAL, BMS damage
-- scale, hard gauge relief below 32%), and the skill needed for the gauge to
-- clear is searched for. That skill becomes a level through curves fitted on
-- the table folders (tools/clearcalc; the site's tools/calcrating.py runs the
-- same model): a chart's EASY lands on its folder's level on average.
--
-- P: 1 short density memory (s), 2 long density memory (s), 3 long share,
-- 4 hand weight, 5 jack weight, 6 miss curve steepness k, 7 empty POOR share
-- of a miss, 8 shortest jack gap (s), 9 chord weight, 10 chord exponent a
local P = {0.869284, 2.477, 0.327945, 1.08909, 4.67436, 10.1646, 0.366215, 0.06, 0.268818, 0.800109}

-- The expected gauge has no luck in it. A real HARD gauge also dies to a bad
-- run, so HARD has to stay HARD_Z standard deviations above dying. EASY and
-- GROOVE: a real gauge swings, so the skill is a mix (SUM_W) of the skill to
-- end at TARGET (the end of the chart matters) and of the skill to gain 60%
-- over the whole chart with no cap or floor (every part counts the same).
local HARD_Z, TARGET, SUM_W = 0.5, 56.4783, 0.5

-- rows closer than SWEEP_GAP (rolls, staircases, sweeps) count SWEEP_W in
-- the densities; in chords of JACK_CHORD notes or more the jack part is
-- scaled by chord^(JACK_EXP - 1), a big chordjack is read as one hit
local SWEEP_GAP, SWEEP_W = 0.0240988, 0.622437
-- notes less than CHORD_GAP (s) after the first note of a row are part of
-- its chord: BMS charts often split one chord over rows a few ms apart
local CHORD_GAP = 0.015
local JACK_CHORD, JACK_EXP = 7, 0.7
-- the same chord as the row before (a held-shape chordjack, it can be
-- mashed): its jack part counts SAME_JACK and its densities SAME_DENS
local SAME_JACK, SAME_DENS = 0.6, 0.5

-- HARD's skill is moved by this (ln) before it becomes a level, so that HARD
-- sits about 2.5 ★ over EASY on the insane table
local HARD_SHIFT = -0.0860

-- ln(skill) -> level, through these points (the medians of the folders),
-- straight lines past the ends. sp: every folder on one ★ scale (sl from the
-- table comparison sheet, st and oj from the Stella / Overjoy comparison,
-- Overjoy = ★ + 20). sl, st, oj: that table's own levels.
local SCALES = {
	insane = {prefix = "sp", lo = 33.3984, hi = 8.4461, knots = {
		{4.0604, 2.000},
		{4.1378, 3.000},
		{4.1855, 5.000},
		{4.2300, 6.000},
		{4.2615, 9.000},
		{4.2999, 10.000},
		{4.3378, 12.000},
		{4.3757, 14.000},
		{4.4120, 16.000},
		{4.4455, 20.000},
		{4.4684, 20.000},
		{4.4850, 20.497},
		{4.4944, 20.497},
		{4.5043, 21.000},
		{4.5135, 21.000},
		{4.5234, 21.000},
		{4.5319, 21.000},
		{4.5400, 22.000},
		{4.5490, 22.000},
		{4.5568, 22.000},
		{4.5670, 22.497},
		{4.5742, 22.497},
		{4.5831, 23.000},
		{4.5919, 23.000},
		{4.6017, 23.000},
		{4.6107, 23.000},
		{4.6202, 23.700},
		{4.6307, 23.700},
		{4.6397, 23.700},
		{4.6475, 24.300},
		{4.6594, 24.300},
		{4.6705, 24.300},
		{4.6820, 24.300},
		{4.6955, 25.000},
		{4.7078, 25.200},
		{4.7221, 25.200},
		{4.7389, 25.400},
		{4.7589, 25.400},
		{4.7950, 25.700},
		{4.8736, 26.600},
	}},
	satellite = {prefix = "sl", lo = 12.6980, hi = 33.9894, knots = {
		{3.9271, 0.000},
		{4.0274, 1.000},
		{4.1050, 2.000},
		{4.1634, 3.000},
		{4.2138, 4.000},
		{4.2477, 5.000},
		{4.2877, 6.000},
		{4.3182, 7.000},
		{4.3447, 8.000},
		{4.3694, 9.000},
		{4.3931, 10.000},
		{4.4288, 11.000},
		{4.4576, 12.000},
	}},
	stella = {prefix = "st", lo = 30.6779, hi = 21.3574, knots = {
		{4.4905, 0.000},
		{4.5132, 1.000},
		{4.5527, 2.000},
		{4.5883, 3.000},
		{4.6212, 4.000},
		{4.6528, 5.000},
		{4.6846, 6.000},
		{4.7115, 7.000},
		{4.7344, 8.000},
		{4.7577, 9.000},
		{4.8049, 10.000},
		{4.8637, 11.000},
		{4.8982, 12.000},
	}},
	overjoy = {prefix = "oj", lo = 23.9550, hi = 11.2561, knots = {
		{4.5155, 1.000},
		{4.5431, 2.000},
		{4.5781, 3.000},
		{4.6407, 4.000},
		{4.7109, 5.000},
		{4.7745, 6.000},
		{4.9072, 7.000},
	}},
}
local SCALE_ORDER = {"insane", "satellite", "stella", "overjoy"}

local GAIN = {1.2, 1.0, 0.1}
local POOR = {-4.8, -6.0, -10.0}
local EPOOR = {-1.6, -2.0, -2.0}

local exp, log, floor, min, max = math.exp, math.log, math.floor, math.min, math.max

local function damageScale(total, notes)
	local fix1 = 10 / min(10, max(1, floor(total / 16) - 5))
	local fix2
	if notes <= 20 then fix2 = 10
	elseif notes < 30 then fix2 = 8 + .2 * (30 - notes)
	elseif notes < 60 then fix2 = 5 + .2 * (60 - notes) / 3
	elseif notes < 125 then fix2 = 4 + (125 - notes) / 65
	elseif notes < 250 then fix2 = 3 + .008 * (250 - notes)
	elseif notes < 500 then fix2 = 2 + .004 * (500 - notes)
	elseif notes < 1000 then fix2 = 1 + .002 * (1000 - notes)
	else fix2 = 1 end
	return max(fix1, fix2)
end

-- ln difficulty of every note, t (seconds) and col (0..6) sorted by time.
-- With parts, also each note's density, hand, jack and chord parts.
local function noteDifficulty(t, col, parts)
	local n = #t
	local ts, tl, lam, hw, jw, jf, cw, a = P[1], P[2], P[3], P[4], P[5], P[8], P[9], P[10]
	local ds, dl, h0, h1, last = 0, 0, 0, 0, t[1]
	local lastCol = {}
	for c = 0, 6 do lastCol[c] = -1e9 end
	local prevMask = -1
	local d = {}
	local i = 1
	while i <= n do
		local j = i
		while j <= n and t[j] - t[i] < CHORD_GAP do j = j + 1 end
		local dt = t[i] - last
		last = t[i]
		local es, el = exp(-dt / ts), exp(-dt / tl)
		ds, dl, h0, h1 = ds * es, dl * el, h0 * es, h1 * es
		local chord = j - i
		local c0, c1 = 0, 0
		for k = i, j - 1 do
			local c = col[k]
			if c < 3 then c0 = c0 + 1
			elseif c > 3 then c1 = c1 + 1
			else c0, c1 = c0 + .5, c1 + .5 end
		end
		local mask = 0
		for k = i, j - 1 do mask = mask + 2 ^ col[k] end
		local same = chord >= 2 and mask == prevMask
		prevMask = mask
		local rf = (dt < SWEEP_GAP and SWEEP_W or 1) * (same and SAME_DENS or 1)
		local rw = chord ^ a * rf
		ds, dl = ds + rw, dl + rw
		if c0 > 0 then h0 = h0 + rf * c0 ^ a end
		if c1 > 0 then h1 = h1 + rf * c1 ^ a end
		local jc = (chord >= JACK_CHORD and chord ^ (JACK_EXP - 1) or 1) * (same and SAME_JACK or 1)
		local base = (1 - lam) * ds / ts + lam * dl / tl
		for k = i, j - 1 do
			local c = col[k]
			local h = c < 3 and h0 or (c > 3 and h1 or .5 * (h0 + h1))
			local jack = 1 / max(t[k] - lastCol[c], jf)
			lastCol[c] = t[k]
			local hand, jk, ch = hw * h / ts, jw * jack * jc, cw * (chord - 1)
			d[k] = log(base + hand + jk + ch)
			if parts then
				parts[k] = {base, hand, jk, ch}
			end
		end
		i = j
	end
	return d
end

-- runs the expected gauge g (1 EASY, 2 GROOVE, 3 HARD) at skill lnS; with
-- trace, keeps the gauge and the miss chance at every note
local function clears(ld, g, lnS, gain, poor, trace, sum)
	local k = P[6]
	local v = g == 3 and 100 or 20
	local var = 0
	local dead = false
	for i = 1, #ld do
		local p = 1 / (1 + exp(-k * (ld[i] - lnS)))
		if dead then
			v = 0
		elseif g == 3 then
			local dmg = poor * (v < 32 and .6 or 1)
			v = v + (1 - p) * gain + p * dmg
			var = var + p * (1 - p) * (gain - dmg) ^ 2
			if v > 100 then v, var = 100, 0 end
			if v - HARD_Z * var ^ .5 < 2 then
				if not trace then return false end
				v, dead = 0, true
			end
		elseif sum then
			v = v + (1 - p) * gain + p * poor
		else
			v = v + (1 - p) * gain + p * poor
			if v > 100 then v = 100 elseif v < 2 then v = 2 end
		end
		if trace then
			trace.gauge[i], trace.miss[i] = v, p
		end
	end
	if g == 3 then return not dead end
	return v >= (sum and 80 or TARGET)
end

-- piecewise linear through knots {x, y}, straight lines past the ends
local function through(x, m)
	local k = m.knots
	if x <= k[1][1] then return k[1][2] + (x - k[1][1]) * m.lo end
	for i = 2, #k do
		if x <= k[i][1] then
			return k[i - 1][2] + (x - k[i - 1][1]) * (k[i][2] - k[i - 1][2]) / (k[i][1] - k[i - 1][1])
		end
	end
	return k[#k][2] + (x - k[#k][1]) * m.hi
end

-- level of a gauge's needed skill (g 1 EASY, 2 GROOVE, 3 HARD) on a scale
local function toLevel(lnS, g, sc)
	return through(lnS + (g == 3 and HARD_SHIFT or 0), sc or SCALES.insane)
end

local function toStar(lnS, g) return toLevel(lnS, g, SCALES.insane) end

local function gaugeChanges(g, total, n)
	if g < 3 then
		return GAIN[g] * total / n, POOR[g] + P[7] * EPOOR[g]
	end
	return GAIN[3], (POOR[3] + P[7] * EPOOR[3]) * damageScale(total, n)
end

local function defaultTotal(total, n)
	if not total or total <= 0 then
		return 160 + (n + min(max(n - 400, 0), 200)) * .16
	end
	return total
end

local function search(ld, g, gain, poor, sum)
	local lo, hi = log(0.05), log(500)
	for _ = 1, 32 do
		local mid = .5 * (lo + hi)
		if clears(ld, g, mid, gain, poor, nil, sum) then hi = mid else lo = mid end
	end
	return .5 * (lo + hi)
end

local function neededSkill(ld, g, gain, poor)
	local s = search(ld, g, gain, poor)
	if g < 3 and SUM_W > 0 then
		s = (1 - SUM_W) * s + SUM_W * search(ld, g, gain, poor, true)
	end
	return s
end

-- skill (ln) a gauge needs: g 1 EASY, 2 GROOVE, 3 HARD
function bmsClearSkills(t, col, total)
	local n = #t
	if n < 2 then return nil end
	local ld = noteDifficulty(t, col)
	total = defaultTotal(total, n)
	local out = {}
	for g = 1, 3 do
		out[g] = neededSkill(ld, g, gaugeChanges(g, total, n))
	end
	return out
end

function bmsClearStars(t, col, total)
	local s = bmsClearSkills(t, col, total)
	if not s then return nil end
	return toStar(s[1], 1), toStar(s[2], 2), toStar(s[3], 3)
end

-- the notes (time, column) of a 7k chart at a music rate
local function readNotes(steps, rate)
	local nd = steps:GetNonEmptyNoteData()
	local etaner = steps:GetETANER()
	local rows = nd and nd[1]
	if not rows or #rows == 0 or #etaner ~= #rows then return nil end
	local t, col = {}, {}
	for i = 1, #rows do
		local time = etaner[i].time / rate
		for c = 0, 6 do
			local tr = nd[c + 2]
			local v = tr and tr[i]
			-- taps and long note heads, a long note counts once like in BMS
			if v == 1 or v == 2 then
				t[#t + 1] = time
				col[#col + 1] = c
			end
		end
	end
	return t, col
end

-- the table a chart is in, from its pack name ("BMS2SM - sl05", "- SP12")
local PACKS = {sp = "insane", sl = "satellite", st = "stella", overjoy = "overjoy"}
local function chartScale(steps)
	local ok, group = pcall(function()
		return SONGMAN:GetSongByChartKey(steps:GetChartKey()):GetGroupName()
	end)
	local name = ok and group and group:lower():match("^bms2sm %- (%a+)")
	return SCALES[PACKS[name] or "insane"]
end

local function isCalcSteps(steps)
	if not steps or steps:GetStepsType() ~= "StepsType_Kb7_Single" then return false end
	return not (isO2JamSteps and isO2JamSteps(steps))
end

-- Which table's scale the levels are shown on: nil for the chart's own
-- table, or one of SCALE_ORDER. Clicking the EASY / HARD numbers cycles it.
BMSClearScale = BMSClearScale or nil

function cycleBMSClearScale(dir)
	local i = 0
	for k, name in ipairs(SCALE_ORDER) do
		if name == BMSClearScale then i = k end
	end
	i = (i + (dir or 1)) % (#SCALE_ORDER + 1)
	BMSClearScale = SCALE_ORDER[i] -- 0 -> nil: the chart's own table
	return BMSClearScale
end

local function shownScale(steps)
	return BMSClearScale and SCALES[BMSClearScale] or chartScale(steps)
end

-- EASY, GROOVE and HARD clear levels of a chart at a music rate, on the
-- scale picked above, and that scale's prefix ("sp", "sl", "st", "oj").
-- nil for charts that are not 7k BMS (O2Jam charts play on their own gauge)
local cache = {}
function getBMSClearDifficulty(steps, rate)
	if not isCalcSteps(steps) then return nil end
	rate = rate or 1
	local key = steps:GetChartKey() .. "@" .. string.format("%.2f", rate)
	local sk = cache[key]
	if not sk then
		local t, col = readNotes(steps, rate)
		if not t then return nil end
		sk = bmsClearSkills(t, col, steps:GetBMSTotal())
		if not sk then return nil end
		cache[key] = sk
	end
	local sc = shownScale(steps)
	return toLevel(sk[1], 1, sc), toLevel(sk[2], 2, sc), toLevel(sk[3], 3, sc), sc.prefix
end

---------------------------------------------------------------------------
-- debug view: everything the calc saw, and the patterns in the chart
---------------------------------------------------------------------------

-- pattern kinds, in the order the debug view lists them
BMSCalcPatterns = {
	{key = "stream", name = "STREAMS", color = "#80ff80"},
	{key = "chordstream", name = "CHORDSTREAMS", color = "#40e0d0"},
	{key = "jack", name = "JACKS", color = "#ff6060"},
	{key = "chordjack", name = "CHORDJACKS", color = "#ff9a40"},
	{key = "chord", name = "CHORDS", color = "#ffd040"},
	{key = "delay", name = "DELAY", color = "#c080ff"},
	{key = "trill", name = "TRILLS", color = "#6aa8ff"},
	{key = "spike", name = "SPIKES", color = "#ff60ff"},
	{key = "bpm", name = "BPM / STOPS", color = "#ffffff"},
}

-- Patterns of a chart. Every row is labelled from the 8 rows around it:
--   fast (rows under 150 ms apart on average)
--     most rows share a column with the row before: CHORDJACKS when the
--     rows average 1.8 notes or more, else JACKS
--     rows under 60 ms apart on average: DELAY (notes so fast they are
--     rolled like a staircase or a split chord)
--     otherwise CHORDSTREAMS at 1.8 notes a row or more, else STREAMS
--   slow: CHORDS for rows of 3 notes or more, JACKS for a column played
--     again within 250 ms
-- TRILLS (one hand going between two columns), SPIKES (seconds with 1.4x
-- the notes of a busy second) and BPM / STOPS come on top of that.
-- Returns [from, to] time ranges per kind, and every note's kinds
-- (noteKinds[i][key] = true).
local function findPatterns(t, col, steps, rate)
	local n = #t
	local found, noteKinds = {}, {}
	for _, k in ipairs(BMSCalcPatterns) do found[k.key] = {} end
	for i = 1, n do noteKinds[i] = {} end
	local function mark(kind, a, b)
		local list = found[kind]
		local last = list[#list]
		-- the same kind closer than 300 ms is one range
		if last and a >= last[1] and a - last[2] < .3 then
			last[2] = max(last[2], b)
		else
			list[#list + 1] = {a, b}
		end
	end

	-- rows: time, columns, notes (indices) and whether a column repeats from
	-- the row before
	local rows = {}
	local i = 1
	while i <= n do
		local r = {t = t[i], cols = {}, n = 0, notes = {}}
		while i <= n and t[i] - r.t < 1e-4 do
			r.cols[col[i]] = true
			r.n = r.n + 1
			r.notes[#r.notes + 1] = i
			i = i + 1
		end
		local prev = rows[#rows]
		r.gap = prev and (r.t - prev.t) or math.huge
		r.repeats = false
		if prev then
			for c in pairs(r.cols) do
				if prev.cols[c] then r.repeats = true end
			end
		end
		rows[#rows + 1] = r
	end

	local nr = #rows
	for ri, r in ipairs(rows) do
		local a, b = max(1, ri - 3), min(nr, ri + 4)
		local gaps, gapN, size, rep = 0, 0, 0, 0
		for k = a, b do
			local w = rows[k]
			size = size + w.n
			if k > a then
				gaps = gaps + w.gap
				gapN = gapN + 1
				if w.repeats then rep = rep + 1 end
			end
		end
		local cnt = b - a + 1
		size = size / cnt
		local fast = gapN > 0 and gaps / gapN < .15
		local label
		if fast then
			if gapN > 0 and rep / gapN >= .5 then
				label = size >= 1.8 and "chordjack" or "jack"
			elseif gaps / gapN < .06 then
				label = "delay"
			else
				label = size >= 1.8 and "chordstream" or "stream"
			end
		elseif r.n >= 3 then
			label = "chord"
		elseif r.repeats and r.gap < .25 then
			label = "jack"
		end
		if label then
			r.label = label
			mark(label, r.t, r.t)
			for _, k in ipairs(r.notes) do noteKinds[k][label] = true end
		end
	end

	-- trills: one hand going between the same two columns, 6 times in a row
	-- (notes of the other hand in between don't break it)
	for hand = 1, 2 do
		local h = {}
		local run = {}
		local function flush()
			if h.swaps and h.swaps >= 6 then
				mark("trill", t[run[1]], t[run[#run]])
				for _, k in ipairs(run) do noteKinds[k].trill = true end
			end
		end
		for _, r in ipairs(rows) do
			-- this hand's notes in the row: columns 1-4 left, 4-7 right
			local mine, cnum = nil, 0
			for _, k in ipairs(r.notes) do
				local c = col[k]
				if (hand == 1 and c <= 3) or (hand == 2 and c >= 3) then
					mine, cnum = k, cnum + 1
				end
			end
			if cnum == 1 then
				local c = col[mine]
				if h.a and c == h.a and c ~= h.b and r.t - h.t < .2 then
					h.a, h.b = h.b, c
					h.swaps = h.swaps + 1
					run[#run + 1] = mine
				elseif h.b and c ~= h.b and r.t - h.t < .2 then
					flush()
					h.a, h.b, h.swaps = h.b, c, 1
					run = {h.last, mine}
				else
					flush()
					h.a, h.b, h.swaps = nil, c, 0
					run = {mine}
				end
				h.t, h.last = r.t, mine
			elseif cnum > 1 then
				flush()
				h, run = {}, {}
			end
		end
		flush()
	end

	-- spikes: seconds with 1.4x the notes of a busy second of the chart
	local first, lastT = t[1], t[n]
	local secs = {}
	for k = 1, floor(lastT - first) + 1 do secs[k] = 0 end
	for k = 1, n do
		local s = floor(t[k] - first) + 1
		secs[s] = secs[s] + 1
	end
	local sorted = {}
	for _, v in ipairs(secs) do if v > 0 then sorted[#sorted + 1] = v end end
	table.sort(sorted)
	-- the busy part of the chart, not its breaks: 3/4 of its seconds
	local median = sorted[max(1, floor(#sorted * .75))] or 0
	for k = 1, n do
		local v = secs[floor(t[k] - first) + 1]
		if median > 0 and v >= median * 1.4 and v >= 8 then
			noteKinds[k].spike = true
		end
	end
	for k, v in ipairs(secs) do
		if median > 0 and v >= median * 1.4 and v >= 8 then
			mark("spike", first + k - 1, first + k)
		end
	end

	-- BPM changes and stops from the timing data, and the notes within a
	-- second after them
	local td = steps:GetTimingData()
	local function each(list, f)
		for k, s in ipairs(list or {}) do
			local beat, value = tostring(s):match("([%d%.%-]+)=([%d%.%-]+)")
			if beat then f(k, tonumber(beat), tonumber(value)) end
		end
	end
	local changes = {}
	each(td:GetBPMsAndTimes(), function(k, beat)
		if k > 1 then
			changes[#changes + 1] = {td:GetElapsedTimeFromBeat(beat) / rate, 0}
		end
	end)
	each(td:GetStops(), function(_, beat, len)
		changes[#changes + 1] = {td:GetElapsedTimeFromBeat(beat) / rate, max(len or 0, 0) / rate}
	end)
	table.sort(changes, function(x, y) return x[1] < y[1] end)
	for _, c in ipairs(changes) do
		mark("bpm", c[1], c[1] + c[2])
		for k = 1, n do
			if t[k] >= c[1] and t[k] <= c[1] + c[2] + 1 then noteKinds[k].bpm = true end
		end
	end
	return found, noteKinds
end

-- everything for the debug view, nil when the calc does not rate the chart
function getBMSClearDebug(steps, rate)
	if not isCalcSteps(steps) then return nil end
	rate = rate or 1
	local t, col = readNotes(steps, rate)
	if not t or #t < 2 then return nil end
	local n = #t
	local parts = {}
	local ld = noteDifficulty(t, col, parts)
	local total = defaultTotal(steps:GetBMSTotal(), n)
	local sc = shownScale(steps)
	local dbg = {t = t, col = col, ld = ld, parts = parts, total = total, notes = n, gauges = {}, prefix = sc.prefix}
	for g = 1, 3 do
		local gain, poor = gaugeChanges(g, total, n)
		-- a hair above the needed skill, where the gauge just clears
		local s = neededSkill(ld, g, gain, poor) + 1e-6
		local trace = {gauge = {}, miss = {}}
		clears(ld, g, s, gain, poor, trace)
		dbg.gauges[g] = {skill = s, star = toLevel(s, g, sc), gain = gain, poor = poor, gauge = trace.gauge, miss = trace.miss}
	end
	local ok, found, kinds = pcall(findPatterns, t, col, steps, rate)
	dbg.patterns = ok and found or {}
	dbg.noteKinds = ok and kinds or {}
	if not ok then dbg.patternError = tostring(found) end
	return dbg
end
