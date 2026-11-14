-- 7k plays by BMS rules (gauge and clear lamps) and has no MSD for now
function hideMSD()
	local style = GAMESTATE:GetCurrentStyle()
	if style == nil then
		-- the song select loads its actors before it sets the style, kb7 only has 7k
		local game = GAMESTATE:GetCurrentGame()
		return game ~= nil and game:GetName() == "kb7"
	end
	return style:ColumnsPerPlayer() == 7
end

-- judge rank and gauge, in the order they are picked from song select
local bmsOptionValues = {
	JudgeRank = {"Easy", "Normal", "Hard", "VeryHard"},
	Gauge = {"Easy", "Normal", "Hard", "ExHard", "Death"},
	Arrange = {"Off", "Mirror", "Random", "RRandom", "SRandom", "HRandom", "Custom"},
}
local bmsOptionNames = {
	JudgeRank = {"JudgeRankEasy", "JudgeRankNormal", "JudgeRankHard", "JudgeRankVeryHard"},
	Gauge = {"GaugeEasy", "GaugeGroove", "GaugeHard", "GaugeExHard", "GaugeDeath"},
	Arrange = {"ArrangeOff", "ArrangeMirror", "ArrangeRandom", "ArrangeRRandom", "ArrangeSRandom", "ArrangeHRandom", "ArrangeCustom"},
}
local bmsOptionEnums = {
	JudgeRank = {setting = "JudgeRankSetting", enum = "BMSJudgeRank_"},
	Gauge = {setting = "GaugeSetting", enum = "BMSGauge_"},
	Arrange = {setting = "ArrangeSetting", enum = "BMSArrange_"},
}
local modsLevels = {"ModsLevel_Preferred", "ModsLevel_Stage", "ModsLevel_Song", "ModsLevel_Current"}

-- index of the current "JudgeRank" or "Gauge" setting
function getBMSOption(kind)
	local e = bmsOptionEnums[kind]
	local po = GAMESTATE:GetPlayerState():GetPlayerOptions("ModsLevel_Preferred")
	local cur = po[e.setting](po)
	for i, v in ipairs(bmsOptionValues[kind]) do
		if cur == e.enum .. v then
			return i
		end
	end
	return kind == "Gauge" and 2 or 1
end

function getBMSOptionName(kind, i)
	return THEME:GetString("OptionNames", bmsOptionNames[kind][i or getBMSOption(kind)])
end

-- judge rank index (1 Easy .. 4 VeryHard) from the selected chart's own #RANK,
-- nil when it has none. Gameplay uses it over the picked rank, like LR2.
function getBMSChartJudgeRank(steps)
	steps = steps or GAMESTATE:GetCurrentSteps()
	if not steps or not steps.GetBMSRank then
		return nil
	end
	local rank = steps:GetBMSRank()
	if not rank then
		return nil
	end
	-- bms #RANK: 0 VERY HARD, 1 HARD, 2 NORMAL, 3 EASY, 4 VERY EASY
	return ({4, 3, 2, 1})[rank + 1] or 1
end

-- judge rank the selected chart will be played on
function getBMSEffectiveJudgeRank()
	return getBMSChartJudgeRank() or getBMSOption("JudgeRank")
end

-- "Normal", or "Normal (chart)" when the chart's #RANK overrides the picker
function getBMSJudgeRankText()
	local chart = getBMSChartJudgeRank()
	if chart then
		return getBMSOptionName("JudgeRank", chart) .. " (" .. THEME:GetString("GeneralInfo", "BMSChartRank") .. ")"
	end
	return getBMSOptionName("JudgeRank")
end

local function setBMSOption(kind, i)
	local e = bmsOptionEnums[kind]
	local ps = GAMESTATE:GetPlayerState()
	for _, lvl in ipairs(modsLevels) do
		local po = ps:GetPlayerOptions(lvl)
		po[e.setting](po, e.enum .. bmsOptionValues[kind][i])
	end
	MESSAGEMAN:Broadcast("BMSOptionChanged", {kind = kind})
end

-- moves the setting by delta, stopping at the ends (the lane arrangement wraps around)
function changeBMSOption(kind, delta)
	-- the chart's own judge rank can't be overridden
	if kind == "JudgeRank" and getBMSChartJudgeRank() then
		return
	end
	local n = #bmsOptionValues[kind]
	local i = getBMSOption(kind) + delta
	if kind == "Arrange" then
		i = (i - 1) % n + 1
	else
		i = math.min(math.max(i, 1), n)
	end
	setBMSOption(kind, i)
end

-- Ctrl+R in song select: Random on, or back to the chart's own lanes
function toggleBMSRandom()
	local random = 3
	setBMSOption("Arrange", getBMSOption("Arrange") == random and 1 or random)
	SCREENMAN:SystemMessage(THEME:GetString("GeneralInfo", "ProfileArrange") .. ": " .. getBMSOptionName("Arrange"))
end

-- custom lane order, "3216547" means lane 1 plays the notes of chart lane 3
function getBMSLanes()
	return GAMESTATE:GetPlayerState():GetPlayerOptions("ModsLevel_Preferred"):BMSLanes()
end

local function isValidLaneOrder(lanes)
	if #lanes ~= 7 then
		return false
	end
	for i = 1, 7 do
		if not lanes:find(tostring(i), 1, true) then
			return false
		end
	end
	return true
end

-- asks for a custom lane order and switches to it
function editBMSLanes()
	SCREENMAN:AddNewScreenToTop("ScreenTextEntry")
	SCREENMAN:GetTopScreen():Load({
		Question = THEME:GetString("GeneralInfo", "BMSLanesQuestion"),
		InitialAnswer = getBMSLanes(),
		MaxInputLength = 7,
		OnOK = function(answer)
			answer = answer:gsub("%s", "")
			if not isValidLaneOrder(answer) then
				SCREENMAN:SystemMessage(THEME:GetString("GeneralInfo", "BMSLanesInvalid"))
				return
			end
			local ps = GAMESTATE:GetPlayerState()
			for _, lvl in ipairs(modsLevels) do
				ps:GetPlayerOptions(lvl):BMSLanes(answer)
			end
			setBMSOption("Arrange", #bmsOptionValues.Arrange)
		end,
	})
end

-- switches to a given lane order (custom arrange), e.g. the RANDOM of a
-- score clicked in the ranking; false when the order is not valid
function setBMSLanes(order)
	order = tostring(order or ""):gsub("%s", "")
	if not isValidLaneOrder(order) then
		return false
	end
	local ps = GAMESTATE:GetPlayerState()
	for _, lvl in ipairs(modsLevels) do
		ps:GetPlayerOptions(lvl):BMSLanes(order)
	end
	setBMSOption("Arrange", #bmsOptionValues.Arrange)
	return true
end

function isBMSCustomArrange()
	return bmsOptionValues.Arrange[getBMSOption("Arrange")] == "Custom"
end

function getBMSArrangeText()
	local name = getBMSOptionName("Arrange")
	if isBMSCustomArrange() then
		return name .. " (" .. getBMSLanes() .. ")"
	end
	return name
end

-- gauge auto shift: when the chosen gauge dies play goes on with the lower
-- ones, the best gauge that survives decides the lamp
function getBMSAutoShift()
	return GAMESTATE:GetPlayerState():GetPlayerOptions("ModsLevel_Preferred"):BMSAutoShift()
end

function toggleBMSAutoShift()
	local on = not getBMSAutoShift()
	local ps = GAMESTATE:GetPlayerState()
	for _, lvl in ipairs(modsLevels) do
		ps:GetPlayerOptions(lvl):BMSAutoShift(on)
	end
	MESSAGEMAN:Broadcast("BMSOptionChanged", {kind = "AutoShift"})
end

function getBMSAutoShiftText()
	return THEME:GetString("OptionNames", getBMSAutoShift() and "On" or "Off")
end

-- LR2 judgment names on 7k
local bmsJudgeNames = {
	TapNoteScore_W1 = "PGREAT",
	TapNoteScore_W2 = "GREAT",
	TapNoteScore_W3 = "GOOD",
	TapNoteScore_W4 = "BAD",
	TapNoteScore_W5 = "BAD",
	TapNoteScore_Miss = "POOR",
}
local bmsShortJudgeNames = {
	TapNoteScore_W1 = "PG",
	TapNoteScore_W2 = "GR",
	TapNoteScore_W3 = "GD",
	TapNoteScore_W4 = "BD",
	TapNoteScore_W5 = "BD",
	TapNoteScore_Miss = "PR",
}
local bmsJudgeColors = {
	TapNoteScore_W1 = color("#a0f0ff"),
	TapNoteScore_W2 = color("#ffd040"),
	TapNoteScore_W3 = color("#70ff70"),
	TapNoteScore_W4 = color("#c080ff"),
	TapNoteScore_W5 = color("#c080ff"),
	TapNoteScore_Miss = color("#ff4040"),
}

-- O2Jam charts (.ojn) play by O2Jam rules: COOL is W1, GOOD W3, BAD W4
-- and MISS. The engine never gives W2 there.
local o2jamJudgeNames = {
	TapNoteScore_W1 = "COOL",
	TapNoteScore_W2 = "COOL",
	TapNoteScore_W3 = "GOOD",
	TapNoteScore_W4 = "BAD",
	TapNoteScore_W5 = "BAD",
	TapNoteScore_Miss = "MISS",
}
local o2jamShortJudgeNames = {
	TapNoteScore_W1 = "CL",
	TapNoteScore_W2 = "CL",
	TapNoteScore_W3 = "GD",
	TapNoteScore_W4 = "BD",
	TapNoteScore_W5 = "BD",
	TapNoteScore_Miss = "MS",
}

function isO2JamSteps(steps)
	if steps == nil or steps.GetFilename == nil then
		return false
	end
	local fn = string.lower(steps:GetFilename() or "")
	return fn:sub(-4) == ".ojn"
end

-- the chart being played (or picked) is an O2Jam chart
function isO2JamPlay()
	return isO2JamSteps(GAMESTATE:GetCurrentSteps())
end

-- a score played by O2Jam rules: the game writes "O2JamHard" into its
-- modifiers, older scores are told by their chart
local o2jamChartCache = {}
function isO2JamScore(score)
	if score == nil then
		return false
	end
	if string.lower(score:GetModifiers() or ""):find("o2jamhard", 1, true) then
		return true
	end
	local ck = score:GetChartKey()
	if o2jamChartCache[ck] == nil then
		o2jamChartCache[ck] = isO2JamSteps(SONGMAN:GetStepsByChartKey(ck))
	end
	return o2jamChartCache[ck]
end

-- O2Jam judgments of a score: COOL GOOD BAD MISS
function getO2JamCounts(score)
	local function tns(x)
		return score:GetTapNoteScore("TapNoteScore_" .. x)
	end
	return tns("W1") + tns("W2"), tns("W3"), tns("W4") + tns("W5"), tns("Miss")
end

-- notes of an O2Jam score: every note plus every long note tail (a long
-- note is judged twice). A failed play counts the notes it did not reach.
function getO2JamNoteCount(score)
	local cool, good, bad, miss = getO2JamCounts(score)
	local judged = cool + good + bad + miss
	local rv = score:GetRadarPossible()
	local possible = (rv:GetValue("RadarCategory_Notes") or 0) + (rv:GetValue("RadarCategory_Holds") or 0)
	return math.max(judged, possible)
end

-- O2Jam score in percent (out of 1,000,000 shown as 100%):
-- base = (COOL * 100 + GOOD * 99) / (notes * 100) * 1,000,000,
-- above 900,000 it is base * 9 - 8,000,000, else base / 9. A play that did
-- not judge all notes but one (failed) gets 80% of it.
function getO2JamScoreOf(cool, good, judged, n)
	if n <= 0 then
		return 0
	end
	local base = (cool * 100 + good * 99) / (n * 100) * 1000000
	local final
	if base > 900000 then
		final = base * 9 - 8000000
	else
		final = base / 9
	end
	if judged < n - 1 then
		final = final * 0.8
	end
	return math.floor(final) / 10000
end

function getO2JamScore(score)
	local cool, good, bad, miss = getO2JamCounts(score)
	return getO2JamScoreOf(cool, good, cool + good + bad + miss, getO2JamNoteCount(score))
end

-- O2Jam grade of an O2Jam score in percent: P (all COOL), SS > 99, S > 96, A > 90,
-- B > 86, C > 78, D > 50, else F
function getO2JamGrade(v)
	if v >= 99.9995 then
		return "P"
	elseif v > 99 then
		return "SS"
	elseif v > 96 then
		return "S"
	elseif v > 90 then
		return "A"
	elseif v > 86 then
		return "B"
	elseif v > 78 then
		return "C"
	elseif v > 50 then
		return "D"
	end
	return "F"
end

local o2jamGradeColors = {
	P = color("#ffffff"), SS = color("#ffe060"), S = color("#ffd040"), A = color("#60ff60"),
	B = color("#60d0ff"), C = color("#a0a0ff"), D = color("#c080ff"), F = color("#ff4040"),
}
function getO2JamGradeColor(g)
	return o2jamGradeColors[g] or color("#ffffff")
end

-- O2Jam windows in ms (COOL, GOOD, BAD) at a bpm: 6, 18 and 25 of 1/48
-- beat, same as Player.cpp
function getO2JamWindowsMs(bpm, rate)
	bpm = math.max(math.abs(bpm or 120), 30)
	local unit = 1250 / bpm / ((rate and rate > 0) and rate or 1)
	return {6 * unit, 6 * unit, 18 * unit, 25 * unit}
end

-- name, short name and color of a judgment on 7k, nil for anything else.
-- O2Jam names while an O2Jam chart is picked.
function getBMSJudgeName(tns)
	if isO2JamPlay() then
		return o2jamJudgeNames[tns]
	end
	return bmsJudgeNames[tns]
end

function getBMSShortJudgeName(tns)
	if isO2JamPlay() then
		return o2jamShortJudgeNames[tns]
	end
	return bmsShortJudgeNames[tns]
end

function getBMSJudgeColor(tns)
	return bmsJudgeColors[tns]
end

-- judge rank index a score was played on, from its modifiers (Easy when none is saved)
function getBMSJudgeRankIndexFromScore(score)
	local mods = string.lower(score and score:GetModifiers() or "")
	if mods:find("veryhardjudge", 1, true) then
		return 4
	elseif mods:find("hardjudge", 1, true) then
		return 3
	elseif mods:find("normaljudge", 1, true) then
		return 2
	end
	return 1
end

function getBMSJudgeRankFromScore(score)
	return getBMSOptionName("JudgeRank", getBMSJudgeRankIndexFromScore(score))
end

-- LR2 windows in ms (PGREAT, GREAT, GOOD, BAD), same as Player.cpp LR2_WINDOWS
local bmsWindowsMs = {
	{21, 60, 120, 200},
	{18, 40, 100, 200},
	{15, 30, 60, 200},
	{8, 24, 40, 200},
}
function getBMSWindowsMs(rank)
	return bmsWindowsMs[rank] or bmsWindowsMs[1]
end

-- judgment color of an offset (ms) on the given LR2 windows
function bmsOffsetToJudgeColor(offset, windows)
	local o = math.abs(offset)
	local names = {"TapNoteScore_W1", "TapNoteScore_W2", "TapNoteScore_W3", "TapNoteScore_W4"}
	for i = 1, 4 do
		if o <= windows[i] then
			return byJudgment(names[i])
		end
	end
	return byJudgment("TapNoteScore_Miss")
end

-- "Judge Rank: Easy" label for a 7k score, shown where 4k shows "Wife3 J4"
function getBMSJudgeRankLabel(score)
	return THEME:GetString("GeneralInfo", "ProfileJudgeRank") .. ": " .. getBMSJudgeRankFromScore(score)
end

-- LR2 / beatoraja score rate: EX score (PGREAT 2, GREAT 1) over the max EX of
-- the chart (2 per note). 7k shows this everywhere instead of the wife percent.
function getBMSExScore(score)
	return score:GetTapNoteScore("TapNoteScore_W1") * 2 + score:GetTapNoteScore("TapNoteScore_W2")
end

function getBMSMaxExScore(score)
	local judged = 0
	for _, j in ipairs({"W1", "W2", "W3", "W4", "W5", "Miss"}) do
		judged = judged + score:GetTapNoteScore("TapNoteScore_" .. j)
	end
	-- failed plays only judged part of the chart
	local possible = score:GetRadarPossible():GetValue("RadarCategory_Notes")
	return math.max(judged, possible or 0) * 2
end

-- LR2 / beatoraja BP (miss count) of a score: BAD + POOR + empty POOR, and
-- a failed play also counts every note it did not reach
function getBMSMissCount(score)
	local function tns(x)
		return score:GetTapNoteScore("TapNoteScore_" .. x)
	end
	local judged = tns("W1") + tns("W2") + tns("W3") + tns("W4") + tns("W5") + tns("Miss")
	local bp = tns("W4") + tns("W5") + tns("Miss") + score:GetEmptyPoorCount()
	local possible = score:GetRadarPossible():GetValue("RadarCategory_Notes") or 0
	-- O2Jam: every long note tail is a note of its own
	if isO2JamScore(score) then
		possible = possible + (score:GetRadarPossible():GetValue("RadarCategory_Holds") or 0)
	end
	return bp + math.max(possible - judged, 0)
end

function getBMSScoreRate(score)
	-- O2Jam scores show their DMJam score instead
	if isO2JamScore(score) then
		return math.max(getO2JamScore(score), 0) / 100
	end
	local max = getBMSMaxExScore(score)
	if max <= 0 then
		return 0
	end
	return getBMSExScore(score) / max
end

local bmsChartCache = {}
function isBMSScore(score)
	local ck = score:GetChartKey()
	if bmsChartCache[ck] == nil then
		local steps = SONGMAN:GetStepsByChartKey(ck)
		bmsChartCache[ck] = steps ~= nil and steps:GetStepsType() == "StepsType_Kb7_Single"
	end
	return bmsChartCache[ck]
end

-- percent (0-100) shown for a score: EX rate on 7k charts, wife elsewhere
function getDisplayScorePercent(score)
	if isBMSScore(score) then
		return getBMSScoreRate(score) * 100
	end
	return score:GetWifeScore() * 100
end

-- the 7k song select is laid out like the beatoraja ECFN skin, in its
-- 1920x1080 space scaled to the screen height and centered. The music wheel
-- metrics use these too.
function ecfnScale()
	return SCREEN_HEIGHT / 1080
end

function ecfnX(x)
	return (SCREEN_WIDTH - 1920 * ecfnScale()) / 2 + x * ecfnScale()
end

-- ECFN clear lamp of a score, the frame order of the skin's lamp sheets:
-- 1 FAILED 4 E-CLEAR 5 CLEAR 6 H-CLEAR 7 EXH-CLEAR 8 F-COMBO 9 PERFECT 10 MAX
function getBMSLampFrame(score)
	local lamp = getBMSLampFromScore(score)
	if lamp == 6 then
		return 1
	elseif lamp == 1 then
		local tns = function(x) return score:GetTapNoteScore("TapNoteScore_" .. x) end
		if tns("W3") + tns("W4") + tns("W5") + tns("Miss") == 0 then
			return tns("W2") == 0 and 10 or 9
		end
		return 8
	elseif lamp == 2 then
		return 7
	elseif lamp == 3 then
		return 6
	elseif lamp == 4 then
		return 5
	end
	return 4
end

-- best ECFN lamp of a chart (0 when never played), plays below 1.0x don't count
function getBestBMSLampFrame(chartKey)
	local best = 0
	local rates = SCOREMAN:GetScoresByKey(chartKey)
	if rates then
		for _, hsl in pairs(rates) do
			for _, s in ipairs(hsl:GetScores()) do
				if s:GetMusicRate() > 0.999 then
					best = math.max(best, getBMSLampFrame(s))
				end
			end
		end
	end
	return best
end

-- the hardest 7k chart of a song
function getBMSSongSteps(song)
	local best
	for _, st in ipairs(song:GetAllSteps()) do
		if st:GetStepsType() == "StepsType_Kb7_Single" then
			if best == nil or Enum.Reverse(Difficulty)[st:GetDifficulty()] > Enum.Reverse(Difficulty)[best:GetDifficulty()] then
				best = st
			end
		end
	end
	return best
end

-- level shown for a 7k chart and the ECFN level color (0 OTHER 1 BEGINNER
-- 2 NORMAL 3 HYPER 4 ANOTHER 5 INSANE). Insane packs are purple, nil level is "?"
local ecfnDifficultyColors = {
	Difficulty_Beginner = 1,
	Difficulty_Easy = 2,
	Difficulty_Medium = 3,
	Difficulty_Hard = 4,
	Difficulty_Challenge = 5,
}
function getBMSLevelDisplay(song, steps)
	local level = getBMSLevel(song, steps)
	if level >= 0 then
		return level, 5
	elseif level == -1 or steps == nil then
		return nil, 5
	end
	return steps:GetMeter(), ecfnDifficultyColors[steps:GetDifficulty()] or 0
end

-- the 7k song select writes in the ECFN skin's fonts (converted from its
-- BMFonts into Fonts/ecfn): every "Common Normal" text there becomes
-- "ECFN Normal" and every "Common Large" one "ECFN Large", wherever it is made
-- (LoadFont gives a File, the UI elements a Font name)
local ecfnFontSwap = {["Common Normal"] = "ECFN Normal", ["Common Large"] = "ECFN Large"}
local ecfnFontPaths
local function ecfnFonts()
	if not hideMSD() then
		return false
	end
	local screen = Var("LoadingScreen")
	return screen == "ScreenSelectMusic"
end
local makeBitmapText = Def.BitmapText
Def.BitmapText = function(t)
	if ecfnFonts() then
		if t.Font and ecfnFontSwap[t.Font] then
			t.Font = ecfnFontSwap[t.Font]
		elseif t.File then
			if not ecfnFontPaths then
				ecfnFontPaths = {
					[THEME:GetPathF("Common", "Normal")] = THEME:GetPathF("", "ECFN Normal"),
					[THEME:GetPathF("Common", "Large")] = THEME:GetPathF("", "ECFN Large"),
				}
			end
			t.File = ecfnFontPaths[t.File] or t.File
		end
	end
	-- one call deeper than the actor file, Def looks the caller up by level
	t._Level = (t._Level or 1) + 1
	return makeBitmapText(t)
end
