-- 7k pacemaker: the score the ECFN score graph and the goal tracker pace
-- against (on 7k it replaces Tracker Goal / Tracker Mode: MYBEST is the PB
-- mode, Custom % the Pacemaker % row, which is the Tracker Goal value), picked like beatoraja's TARGET option. Grades are 27ths of the
-- max EX score (A = 18/27 = 6/9, AA = 21/27, AAA = 24/27), with a third of
-- a grade below (-) and above (+) each, as in beatoraja.

-- {config value, option name, rate, row of the ECFN "PACEMAKER ..." label}
local targets = {
	{"A-", "A-", 17 / 27, 0},
	{"A", "A", 18 / 27, 1},
	{"A+", "A+", 19 / 27, 2},
	{"AA-", "AA-", 20 / 27, 3},
	{"AA", "AA", 21 / 27, 4},
	{"AA+", "AA+", 22 / 27, 5},
	{"AAA-", "AAA-", 23 / 27, 6},
	{"AAA", "AAA", 24 / 27, 7},
	{"AAA+", "AAA+", 25 / 27, 8},
	{"MAX", "MAX", 1, 9},
	{"NEXT", "NEXT", nil, 10},
	{"MYBEST", "MYBEST", nil, nil},
	{"GOAL", "Custom %", nil, nil},
}

function getPacemakerTargets()
	return targets
end

local function find(value)
	for _, t in ipairs(targets) do
		if t[1] == value then
			return t
		end
	end
	return targets[#targets]
end

function getPacemakerSetting()
	local v = playerConfig:get_data(pn_to_profile_slot(PLAYER_1)).PacemakerTarget
	return find(v)[1]
end

-- the best EX rate (O2Jam: score / 100) at the current music rate on the
-- current chart, or nil without a score
local pbScore
function getBMSPBRateForCurrentChart()
	pbScore = nil
	local best
	local rate = getCurRateValue()
	for k, scores in pairs(getRateTable() or {}) do
		local r = tonumber((k:gsub("x", "")))
		if r and math.abs(r - rate) < 0.001 then
			for _, sc in ipairs(scores) do
				local v = getBMSScoreRate(sc)
				if v > 0 and (best == nil or v > best) then
					best = v
					pbScore = sc
				end
			end
		end
	end
	return best
end

-- the pacemaker rate (0-1), its ECFN label row (nil: drawn as text) and the
-- text for it. pbRate is the PB from getBMSPBRateForCurrentChart.
function getPacemakerRate(pbRate)
	local t = find(getPacemakerSetting())
	local goal = (playerConfig:get_data(pn_to_profile_slot(PLAYER_1)).TargetGoal or 93) / 100
	if t[1] == "NEXT" then
		-- the next DJ level (ninths) above the PB, MAX past AAA
		local pb = pbRate or 0
		for i = 1, 8 do
			if pb < i / 9 then
				return i / 9, t[4], "NEXT"
			end
		end
		return 1, t[4], "NEXT"
	elseif t[1] == "MYBEST" then
		if pbRate then
			return pbRate, nil, "MYBEST"
		end
		return goal, nil, string.format("%g%%", goal * 100)
	elseif t[1] == "GOAL" then
		return goal, nil, string.format("%g%%", goal * 100)
	end
	return t[3], t[4], t[2]
end

-- The PB's EX score after each judged note, from its replay, so MYBEST paces
-- like the PB really went (a slow start, a late break) instead of its final
-- rate spread evenly. curve[k] = EX after k judged notes, in chart order,
-- judged on the PB's own judge rank with the LR2 windows. nil without a
-- readable replay (or on O2Jam charts, where the score is not EX).
local curves = {}
local function pbCurve()
	if pbScore == nil or isO2JamPlay() then
		return nil
	end
	local key = pbScore:GetScoreKey()
	if curves[key] ~= nil then
		return curves[key] or nil
	end
	curves[key] = false
	if not pbScore:HasReplayData() then
		return nil
	end
	local replay = pbScore:GetReplay()
	if replay == nil then
		return nil
	end
	replay:LoadAllData()
	local offsets = replay:GetOffsetVector() or {}
	local rows = replay:GetNoteRowVector() or {}
	local types = replay:GetTapNoteTypeVector() or {}
	if #offsets == 0 or #rows ~= #offsets then
		return nil
	end
	local typed = #types == #offsets
	local skip = {TapNoteType_Mine = true, TapNoteType_Fake = true, TapNoteType_AutoKeysound = true}
	local idx = {}
	for i = 1, #offsets do
		if not (typed and skip[types[i]]) then
			idx[#idx + 1] = i
		end
	end
	table.sort(idx, function(a, b)
		if rows[a] ~= rows[b] then
			return rows[a] < rows[b]
		end
		return a < b
	end)
	local w = getBMSWindowsMs(getBMSJudgeRankIndexFromScore(pbScore))
	local curve, ex = {}, 0
	for k, i in ipairs(idx) do
		local o = math.abs(offsets[i])
		if o <= w[1] then
			ex = ex + 2
		elseif o <= w[2] then
			ex = ex + 1
		end
		curve[k] = ex
	end
	curves[key] = curve
	return curve
end

-- the PB's EX score after `judged` notes: from its replay when it has one,
-- otherwise its final rate times the notes judged so far
function getBMSPBPaceEx(judged, pbRate)
	local curve = pbCurve()
	if curve and #curve > 0 then
		if judged <= 0 then
			return 0
		end
		return curve[math.min(judged, #curve)]
	end
	return (pbRate or 0) * judged * 2
end

-- the pacemaker's EX score after `judged` notes (MYBEST follows the replay)
function getPacemakerPaceEx(judged, targetRate, pbRate)
	if getPacemakerSetting() == "MYBEST" and pbRate then
		return getBMSPBPaceEx(judged, pbRate)
	end
	return (targetRate or 0) * judged * 2
end
