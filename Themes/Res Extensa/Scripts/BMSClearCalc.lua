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
local P = {0.869284, 2.477, 0.327945, 0.8, 5.6, 10.1646, 0.366215, 0.06, 0.268818, 0.800109}

-- the calc's version, raised with every change of the numbers. A rating file
-- made by another version (the site's calcrating.json or its copy in
-- Save/BMSCache) is not used: the game's own calc rates the charts instead,
-- and after an update the unranked charts' ratings on the site are sent again
-- (BMSRanking.lua R.resendCalc)
BMSClearCalcVersion = 44
function BMSCalcFileCurrent(str)
	return tonumber((str or ""):match('"calcVersion":(%d+)')) == BMSClearCalcVersion
end

-- The expected gauge has no luck in it. A real HARD gauge also dies to a bad
-- run, so HARD has to stay HARD_Z standard deviations above dying. EASY and
-- GROOVE: a real gauge swings, so the skill is a mix (SUM_W) of the skill to
-- end at TARGET (the end of the chart matters) and of the skill to gain 60%
-- over the whole chart with no cap (every part counts the same, but the
-- gauge still stops at its 2% floor).
local HARD_Z, TARGET, SUM_W = 0.5, 56.4783, 0.7
-- for the debug view: where the expected EASY / GROOVE gauge has to end
BMSClearTarget = TARGET

-- rows closer than SWEEP_GAP (rolls, staircases, sweeps) count SWEEP_W in
-- the densities; in chords of JACK_CHORD notes or more the jack part is
-- scaled by chord^(JACK_EXP - 1), a big chordjack is read as one hit
local SWEEP_GAP, SWEEP_W = 0.0240988, 0.622437
-- notes less than CHORD_GAP (s) after the first note of a row are part of
-- its chord: BMS charts often split one chord over rows a few ms apart
local CHORD_GAP = 0.015
local JACK_CHORD, JACK_EXP = 6, 0.7

-- a chordjack (a chord of 3+ that repeats 2+ columns of the row before it,
-- less than 0.2 s later) is easier than its jacks say: its jack part counts
-- CJ_JACK and its density CJ_DENS
local CJ_JACK, CJ_DENS = 0.9, 0.9
-- the same chord as the row before (a held-shape chordjack, it can be
-- mashed): its jack part counts SAME_JACK and its densities SAME_DENS
local SAME_JACK, SAME_DENS = 0.6, 0.5
-- a delay or grace (a row less than DELAY_GAP after a row that came after a
-- gap at least that long) is read and hit on its own: it counts DELAY_W, not
-- SWEEP_W. A grace of 1-GRACE_MAX notes split off a chord of 2+ in a
-- chordjack section is timed against it: it counts up to GRACE_W, fully when
-- the recent share of chordjack rows (see CJ_RUN) is GRACE_CJ or more, fading
-- to DELAY_W below that
local DELAY_W, DELAY_GAP, GRACE_W, GRACE_MAX, GRACE_CJ = 0.7, 0.045, 6, 2, 0.3
-- a long chordjack run: in a chordjack row, with f the share of chordjack
-- rows in the recent ones (memory CS_MEM s), the jack and density parts count
-- max(CJ_RUN_MIN, 1 - CJ_RUN * f) more
local CJ_RUN, CJ_RUN_MIN = 0.04, 0.8
-- slow chordjacks (more than CJ_SLOW s apart) are pumped with the wrist and
-- need less control: a chordjack row counts (CJ_SLOW / gap)^CJ_SLOW_EXP.
-- Chordjacks mixed into other patterns (recent chordjack share under
-- CJ_MIXED) need control: they count CJ_MIXED_W. Both in jack and density
local CJ_SLOW, CJ_SLOW_EXP, CJ_MIXED, CJ_MIXED_W = 0.11, 0.5, 0.4, 1.15
-- a dense chordstream: the average chord size of the recent rows (a memory
-- of CS_MEM s) is over CS_AVG. A chord of 3+ (less than 0.2 s after the row
-- before, not a chordjack, not the same chord) then counts
-- 1 - CS_SLOPE * (average - CS_AVG), never less than CS_MIN
local CS_SLOPE, CS_AVG, CS_MEM, CS_MIN = 0.2, 2.6, 1.0, 0.95
-- jacks: the jack part goes as (shortest jack gap / gap)^JACK_CURVE, so slow
-- jacks count less and the fastest stay as they were. A minijack (a jack
-- whose column gap before it was more than MINI_RATIO times longer, two
-- notes and not a jack run) counts MINI_W of its jack part
local JACK_CURVE, MINI_W, MINI_RATIO = 2, 0.7, 2
-- a note in a roll / sweep row (less than SWEEP_GAP after the row before):
-- its column comes back inside a rolling motion, its jack part counts ROLL_JACK
local ROLL_JACK = 0.3
-- HARD: a note's miss chance is at most HARD_MISS_MAX, a burst is got through
-- by hitting part of it
local HARD_MISS_MAX = 0.2
-- HARD: chordjack notes count HARD_CJ of their difficulty
local HARD_CJ = 1
-- a chart under SHORT_LEN s of notes is short enough to mash through: its
-- notes count (length / SHORT_LEN)^SHORT_EXP of their difficulty
local SHORT_LEN, SHORT_EXP = 60, 0.25
-- luck / mashing: a note harder than LUCK_SPIKE x the chart's median note is
-- got through with luck or by mashing; it counts LUCK_KEEP of the excess
local LUCK_SPIKE, LUCK_KEEP = 1.8, 0.4
-- a full alternation (the row two back again, sharing no key with the row
-- before, less than 0.2 s on: X.X.X.X / .X.X.X.) of rows of up to MASH_MAX
-- notes can be mashed: MASH_W (a trill of big chords inside a dense
-- chordstream is not mashed)
local MASH_W, MASH_MAX = 0.6, 2
-- a fast burst inside a chordstream (a row less than DELAY_GAP after the row
-- before while the recent average chord is BURST_AVG or more) is hard to hit
local BURST_W, BURST_AVG = 0.8, 2.0
-- a very fast run (a row SWEEP_GAP..FAST_GAP s after the row before, which
-- was also less than FAST_GAP after its own row before: 64th runs and
-- staircases, rows less than FAST_GAP apart) is swept through more than read:
-- it counts FAST_W
local FAST_W, FAST_GAP = 0.9, 0.055
-- a staircase (a single note on the next column, the same way as the step
-- before, less than STAIR_GAP s after the row before) is swept with the hand:
-- it counts STAIR_W
local STAIR_W, STAIR_GAP = 0.7, 0.07
-- a steady chordstream (rows at an even pace, each less than STEADY_GAP s
-- after the one before and within STEADY_TOL of the gap before it, STEADY_RUN
-- or more such rows in a row, chords of STEADY_CHORD+) is read as one rhythm
-- and partly mashed: its rows count STEADY_W in the densities
local STEADY_W, STEADY_GAP, STEADY_TOL, STEADY_RUN, STEADY_CHORD = 0.85, 0.12, 0.1, 4, 2

-- HARD's skill is moved by this (ln) before it becomes a level, so that HARD
-- sits about 2.5 ★ over EASY on the insane table
local HARD_SHIFT = -0.0629
-- HARD's skill becomes the skill whose EASY level is where HARD should be:
-- through these points, fitted so a chart's HARD sits about 1.5 ★ over the
-- EASY of the charts with the same HARD skill (tools/clearcalc/lab/hardmap.py)
-- then +0.03 (about +1 ★ on HARD), as players found HARD clears harder than
-- their EASY-to-HARD gap said
local HARD_MAP = {lo = 1.0000, hi = 1.0000, knots = {
	{3.55111, 3.46263},
	{3.64507, 3.55852},
	{3.70509, 3.62773},
	{3.75596, 3.68573},
	{3.79782, 3.71886},
	{3.83317, 3.74981},
	{3.86358, 3.78664},
	{3.89091, 3.80522},
	{3.91763, 3.82761},
	{3.94013, 3.86137},
	{3.96533, 3.88226},
	{3.99284, 3.89803},
	{4.02048, 3.93949},
	{4.04693, 3.95721},
	{4.07310, 3.99264},
	{4.09640, 4.01709},
	{4.12025, 4.02902},
	{4.14235, 4.05869},
	{4.16634, 4.07545},
	{4.19102, 4.10517},
	{4.21641, 4.11787},
	{4.23821, 4.15058},
	{4.25689, 4.17725},
	{4.27761, 4.18761},
	{4.29878, 4.20180},
	{4.31904, 4.22447},
	{4.33869, 4.25395},
	{4.36057, 4.28631},
	{4.38195, 4.29842},
	{4.40334, 4.30911},
	{4.42805, 4.34618},
	{4.44977, 4.37876},
	{4.47479, 4.41629},
	{4.49973, 4.45370},
	{4.52536, 4.48066},
	{4.55478, 4.50644},
	{4.59431, 4.53155},
	{4.64344, 4.57869},
	{4.71948, 4.64618},
	{4.85512, 4.84965},
}}

-- Every scale is set 0.5 lower than the folder medians, by request (the
-- folder fit read about 1 point high in play).
-- ln(skill) -> level, through these points (the medians of the folders),
-- straight lines past the ends. sp: every folder on one ★ scale (sl from the
-- table comparison sheet, st and oj from the Stella / Overjoy comparison,
-- Overjoy = ★ + 20). sl, st, oj: that table's own levels.
local SCALES = {
	insane = {prefix = "sp", lo = 22.6906, hi = 3.0000, knots = {
		{3.5534, 1.500},
		{3.5870, 2.500},
		{3.6323, 3.500},
		{3.6737, 4.500},
		{3.7016, 5.500},
		{3.7188, 6.500},
		{3.7410, 7.500},
		{3.7689, 8.500},
		{3.7907, 9.500},
		{3.8085, 10.500},
		{3.8368, 11.500},
		{3.8687, 12.500},
		{3.8811, 13.500},
		{3.9167, 14.500},
		{3.9283, 15.500},
		{3.9416, 16.500},
		{3.9679, 17.500},
		{3.9848, 18.500},
		{4.0064, 19.500},
		{4.0542, 20.500},
		{4.0933, 22.000},
		{4.1765, 23.500},
		{4.2009, 24.500},
		{4.3475, 25.500},
		{4.5555, 27.500},
	}},
	satellite = {prefix = "sl", lo = 9.4109, hi = 28.4352, knots = {
		{3.4050, 0.500},
		{3.5224, 1.500},
		{3.6102, 2.500},
		{3.6700, 3.500},
		{3.7262, 4.500},
		{3.7707, 5.500},
		{3.8156, 6.500},
		{3.8506, 7.500},
		{3.8818, 8.500},
		{3.9120, 9.500},
		{3.9324, 10.500},
		{3.9772, 11.500},
		{4.0080, 12.500},
	}},
	stella = {prefix = "st", lo = 26.5218, hi = 15.8649, knots = {
		{4.0476, 0.500},
		{4.0752, 1.500},
		{4.1238, 2.500},
		{4.1652, 3.500},
		{4.2105, 4.500},
		{4.2484, 5.500},
		{4.2909, 6.500},
		{4.3332, 7.500},
		{4.3525, 8.500},
		{4.3986, 9.500},
		{4.4503, 10.500},
		{4.5407, 11.500},
		{4.5895, 12.500},
	}},
	overjoy = {prefix = "oj", lo = 23.9571, hi = 7.5667, knots = {
		{4.0740, 1.500},
		{4.1080, 2.500},
		{4.1780, 3.500},
		{4.2288, 4.500},
		{4.2910, 5.500},
		{4.4205, 6.500},
		{4.5628, 7.500},
	}},
}
local SCALE_ORDER = {"insane", "satellite", "stella", "overjoy"}

-- gauges 1 EASY, 2 GROOVE, 3 HARD, 4 EX HARD (this fork's LR2 values)
local GAIN = {1.2, 1.0, 0.1, 0.1}
local POOR = {-4.8, -6.0, -10.0, -20.0}
local EPOOR = {-1.6, -2.0, -2.0, -2.0}

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
	local lastGap = {}
	for c = 0, 6 do lastCol[c], lastGap[c] = -1e9, 1e9 end
	local prevMask, prevMask2 = -1, -2
	local prevCols, prevT = {}, -1e9
	local prevDt, cavg, cjf, prevChord = 1e9, 0, 0, 0
	local steady = 0
	local stairCol, stairDir = -9, 0
	local d, cjNote = {}, {}
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
		local mask2 = prevMask2
		prevMask2, prevMask = prevMask, mask
		local ov = 0
		for k = i, j - 1 do if prevCols[col[k]] then ov = ov + 1 end end
		local cj = chord >= 3 and ov >= 2 and t[i] - prevT < 0.2
		prevCols, prevT = {}, t[i]
		for k = i, j - 1 do prevCols[col[k]] = true end
		local sweep = dt < SWEEP_GAP and SWEEP_W or 1
		local burst = dt < DELAY_GAP and cavg >= BURST_AVG
		local ec = exp(-dt / CS_MEM)
		cavg = cavg * ec + chord * (1 - ec)
		cjf = cjf * ec + (cj and 1 or 0) * (1 - ec)
		if dt < DELAY_GAP and prevDt >= DELAY_GAP then
			sweep = DELAY_W
			if prevChord >= 2 and chord <= GRACE_MAX then
				sweep = DELAY_W + (GRACE_W - DELAY_W) * min(1, cjf / GRACE_CJ)
			end
		end
		if burst then sweep = BURST_W end
		if dt >= SWEEP_GAP and dt < FAST_GAP and prevDt < FAST_GAP then sweep = sweep * FAST_W end
		if dt < STEADY_GAP and math.abs(dt - prevDt) <= STEADY_TOL * dt then steady = steady + 1 else steady = 0 end
		if steady >= STEADY_RUN and chord >= STEADY_CHORD then sweep = sweep * STEADY_W end
		local sc = chord == 1 and col[i] or -9
		local sdir = (sc >= 0 and stairCol >= 0 and math.abs(sc - stairCol) == 1) and (sc - stairCol) or 0
		if sdir ~= 0 and sdir == stairDir and dt < STAIR_GAP then sweep = sweep * STAIR_W end
		stairCol, stairDir = sc, sdir
		prevDt, prevChord = dt, chord
		local cjm = 1
		if cj then
			cjm = max(CJ_RUN_MIN, 1 - CJ_RUN * cjf)
			if cjf < CJ_MIXED then cjm = cjm * CJ_MIXED_W end
			if dt > CJ_SLOW then cjm = cjm * (CJ_SLOW / dt) ^ CJ_SLOW_EXP end
		end
		local csw = 1
		if chord >= 3 and not cj and not same and dt < 0.2 and cavg > CS_AVG then
			csw = max(CS_MIN, 1 - CS_SLOPE * (cavg - CS_AVG))
		end
		local mash = mask2 >= 0 and mask == mask2 and ov == 0 and dt < 0.2 and chord <= MASH_MAX
		local rf = sweep * (same and SAME_DENS or 1) * (cj and CJ_DENS * cjm or 1) * csw * (mash and MASH_W or 1)
		local rw = chord ^ a * rf
		ds, dl = ds + rw, dl + rw
		if c0 > 0 then h0 = h0 + rf * c0 ^ a end
		if c1 > 0 then h1 = h1 + rf * c1 ^ a end
		local jc = (chord >= JACK_CHORD and chord ^ (JACK_EXP - 1) or 1) * (same and SAME_JACK or 1) * (cj and CJ_JACK * cjm or 1)
		local base = (1 - lam) * ds / ts + lam * dl / tl
		for k = i, j - 1 do
			local c = col[k]
			local h = c < 3 and h0 or (c > 3 and h1 or .5 * (h0 + h1))
			local gap = t[k] - lastCol[c]
			local jack = (jf / max(gap, jf)) ^ JACK_CURVE / jf
			if lastGap[c] > MINI_RATIO * gap then jack = jack * MINI_W end
			if dt < SWEEP_GAP then jack = jack * ROLL_JACK end
			lastGap[c], lastCol[c] = gap, t[k]
			local hand, jk, ch = hw * h / ts, jw * jack * jc, cw * (chord - 1)
			d[k] = base + hand + jk + ch
			cjNote[k] = cj
			if parts then
				parts[k] = {base, hand, jk, ch}
			end
		end
		i = j
	end
	if n > 10 then
		local sorted = {}
		for k = 1, n do sorted[k] = d[k] end
		table.sort(sorted)
		local cap = LUCK_SPIKE * sorted[floor(n / 2) + 1]
		for k = 1, n do
			if d[k] > cap then d[k] = cap + LUCK_KEEP * (d[k] - cap) end
		end
	end
	-- a short chart (under SHORT_LEN s of notes) can be mashed through, it is
	-- no stamina test: every note counts (length / SHORT_LEN)^SHORT_EXP
	if t[n] - t[1] < SHORT_LEN then
		local f = (max(t[n] - t[1], 1) / SHORT_LEN) ^ SHORT_EXP
		for k = 1, n do d[k] = d[k] * f end
	end
	-- HARD: a chordjack note counts HARD_CJ (a chordjack is easier to keep a HARD gauge through)
	local dh = {}
	for k = 1, n do
		dh[k] = log(d[k] * (cjNote[k] and HARD_CJ or 1))
		d[k] = log(d[k])
	end
	return d, dh
end

-- runs the expected gauge g (1 EASY, 2 GROOVE, 3 HARD) at skill lnS; with
-- trace, keeps the gauge and the miss chance at every note
local function clears(ld, g, lnS, gain, poor, trace, sum)
	local k = P[6]
	local v = g >= 3 and 100 or 20
	local var = 0
	local dead = false
	for i = 1, #ld do
		local p = 1 / (1 + exp(-k * (ld[i] - lnS)))
		if dead then
			v = 0
		elseif g >= 3 then
			if p > HARD_MISS_MAX then p = HARD_MISS_MAX end
			-- HARD takes less damage under 32%, EX HARD does not
			local dmg = poor * ((g == 3 and v < 32) and .6 or 1)
			v = v + (1 - p) * gain + p * dmg
			var = var + p * (1 - p) * (gain - dmg) ^ 2
			if v > 100 then v, var = 100, 0 end
			if v - HARD_Z * var ^ .5 < 2 then
				if not trace then return false end
				v, dead = 0, true
			end
		elseif sum then
			-- no cap, but the gauge never goes under 2%: a bad middle is not carried
			-- past the floor, the gauge can still be won back at the end
			v = v + (1 - p) * gain + p * poor
			if v < 2 then v = 2 end
		else
			v = v + (1 - p) * gain + p * poor
			if v > 100 then v = 100 elseif v < 2 then v = 2 end
		end
		if trace then
			trace.gauge[i], trace.miss[i] = v, p
		end
	end
	if g >= 3 then return not dead end
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

-- level of a gauge's needed skill (g 1 EASY, 2 GROOVE, 3 HARD, 4 EX HARD) on a scale
local function toLevel(lnS, g, sc)
	if g >= 3 then lnS = through(lnS, HARD_MAP) end
	return through(lnS, sc or SCALES.insane)
end

local function toStar(lnS, g) return toLevel(lnS, g, SCALES.insane) end

-- Satellite and Stella are one table: sl0..sl12, then st0 is the level after
-- sl12. On either scale a level under st0 (below st -0.5) is shown as sl and
-- one above sl12 as st. Returns the level and its prefix.
local function shownLevel(lnS, g, sc)
	if sc == SCALES.satellite or sc == SCALES.stella then
		local st = toLevel(lnS, g, SCALES.stella)
		if st >= -0.5 then return st, "st" end
		return toLevel(lnS, g, SCALES.satellite), "sl"
	end
	return toLevel(lnS, g, sc), sc.prefix
end

local function gaugeChanges(g, total, n)
	if g < 3 then
		return GAIN[g] * total / n, POOR[g] + P[7] * EPOOR[g]
	end
	return GAIN[g], (POOR[g] + P[7] * EPOOR[g]) * damageScale(total, n)
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

-- skill (ln) a gauge needs: g 1 EASY, 2 GROOVE, 3 HARD, 4 EX HARD
function bmsClearSkills(t, col, total)
	local n = #t
	if n < 2 then return nil end
	local ld, lh = noteDifficulty(t, col)
	total = defaultTotal(total, n)
	local out = {}
	for g = 1, 4 do
		out[g] = neededSkill(g >= 3 and lh or ld, g, gaugeChanges(g, total, n))
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
-- scale picked above, then the prefix ("sp", "sl", "st", "oj") of EASY, HARD
-- and GROOVE (sl / st can differ per gauge, see shownLevel).
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
	local e, pe = shownLevel(sk[1], 1, sc)
	local gr, pg = shownLevel(sk[2], 2, sc)
	-- EASY never shows above HARD: a HARD clear gives the EASY lamp too (a tiny
	-- TOTAL makes the EASY gauge the harder one in the model; HARD, which TOTAL
	-- does not touch, keeps its own level)
	local hs = through(sk[3], HARD_MAP)
	local h, ph = shownLevel(hs, 1, sc)
	if sk[1] > hs then e, pe = h, ph end
	if sk[2] > hs then gr, pg = h, ph end
	-- EX HARD (never under HARD), and its prefix, after the others
	local ex, px = shownLevel(through(max(sk[4] or sk[3], sk[3]), HARD_MAP), 1, sc)
	return e, gr, h, pe, ph, pg, ex, px
end

-- The chart's Good enough rating as the ranking site keeps it: EASY and HARD
-- level at 1.0x on the insane ★ scale, whatever scale is shown (the same
-- numbers the site's tools/calcrating.py writes to public/calcrating.json).
-- The game sends it for unranked charts, which the site has no rating for.
function getBMSSiteRating(steps)
	if not isCalcSteps(steps) then return nil end
	local key = steps:GetChartKey() .. "@1.00"
	local sk = cache[key]
	if not sk then
		local t, col = readNotes(steps, 1)
		if not t then return nil end
		sk = bmsClearSkills(t, col, steps:GetBMSTotal())
		if not sk then return nil end
		cache[key] = sk
	end
	local hs = through(sk[3], HARD_MAP)
	return toStar(min(sk[1], hs), 1), toStar(hs, 1)
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
	local ld, lh = noteDifficulty(t, col, parts)
	local total = defaultTotal(steps:GetBMSTotal(), n)
	local sc = shownScale(steps)
	local dbg = {t = t, col = col, ld = ld, parts = parts, total = total, notes = n, gauges = {}, prefix = sc.prefix}
	for g = 1, 4 do
		local gain, poor = gaugeChanges(g, total, n)
		-- a hair above the needed skill, where the gauge just clears
		local gd = g >= 3 and lh or ld
		local s = neededSkill(gd, g, gain, poor) + 1e-6
		local trace = {gauge = {}, miss = {}}
		clears(gd, g, s, gain, poor, trace)
		local lv, pre = shownLevel(s, g, sc)
		dbg.gauges[g] = {skill = s, star = lv, prefix = pre, gain = gain, poor = poor, gauge = trace.gauge, miss = trace.miss}
	end
	local ok, found, kinds = pcall(findPatterns, t, col, steps, rate)
	dbg.patterns = ok and found or {}
	dbg.noteKinds = ok and kinds or {}
	if not ok then dbg.patternError = tostring(found) end
	return dbg
end
