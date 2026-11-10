------------------------------------------------------
--Methods for generating IIDX-esque ClearType texts --
------------------------------------------------------
--EDIT: scores no longer needed since it grabs it for you

local stypetable = {
	-- Shorthand Versions of ClearType. Not Really used anywhere yet but who knows
	[1] = "MFC",
	[2] = "WF",
	[3] = "SDP",
	[4] = "PFC",
	[5] = "BF",
	[6] = "SDG",
	[7] = "FC",
	[8] = "MF",
	[9] = "SDCB",
	[10] = "Clear",
	[11] = "Failed",
	[12] = "Invalid",
	[13] = "No Play",
	[14] = "-" -- song is nil
	--[15]="Ragequit", -- can't implement unless there's a way to track playcounts by difficulty
}

local typetable = {
	-- ClearType texts
	[1] = "MFC",
	[2] = "WF",
	[3] = "SDP",
	[4] = "PFC",
	[5] = "BF",
	[6] = "SDG",
	[7] = "FC",
	[8] = "MF",
	[9] = "SDCB",
	[10] = "Clear",
	[11] = "Failed",
	[12] = "Invalid",
	[13] = "No Play",
	[14] = "-"
	--[15]="Ragequit", -- can't implement unless there's a way to track playcounts by difficulty
}

local typecolors = {
	-- colors corresponding to cleartype
	[1] = color(colorConfig:get_data().clearType["MFC"]),
	[2] = color(colorConfig:get_data().clearType["WF"]),
	[3] = color(colorConfig:get_data().clearType["SDP"]),
	[4] = color(colorConfig:get_data().clearType["PFC"]),
	[5] = color(colorConfig:get_data().clearType["BF"]),
	[6] = color(colorConfig:get_data().clearType["SDG"]),
	[7] = color(colorConfig:get_data().clearType["FC"]),
	[8] = color(colorConfig:get_data().clearType["MF"]),
	[9] = color(colorConfig:get_data().clearType["SDCB"]),
	[10] = color(colorConfig:get_data().clearType["Clear"]),
	[11] = color(colorConfig:get_data().clearType["Failed"]),
	[12] = color(colorConfig:get_data().clearType["Invalid"]),
	[13] = color(colorConfig:get_data().clearType["NoPlay"]),
	[14] = color(colorConfig:get_data().clearType["None"])
	--[15]	= color("#e61e25"),
}

local typetranslations = {
	THEME:GetString("ClearTypes", "MFC"),
	THEME:GetString("ClearTypes", "WF"),
	THEME:GetString("ClearTypes", "SDP"),
	THEME:GetString("ClearTypes", "PFC"),
	THEME:GetString("ClearTypes", "BF"),
	THEME:GetString("ClearTypes", "SDG"),
	THEME:GetString("ClearTypes", "FC"),
	THEME:GetString("ClearTypes", "MF"),
	THEME:GetString("ClearTypes", "SDCB"),
	THEME:GetString("ClearTypes", "Clear"),
	THEME:GetString("ClearTypes", "Failed"),
	THEME:GetString("ClearTypes", "Invalid"),
	THEME:GetString("ClearTypes", "No Play"),
	"-"
}

-- Methods for other uses (manually setting colors/text, etc.)
local function getClearTypeText(index)
	return typetranslations[index] -- this couldnt possibly break anything right? haha
end

local function getShortClearTypeText(index)
	return stypetable[index]
end

local function getClearTypeColor(index)
	return typecolors[index]
end

local function getClearTypeItem(clearlevel, ret)
	if ret == 0 then
		return typetable[clearlevel]
	elseif ret == 1 then
		return stypetable[clearlevel]
	elseif ret == 2 then
		return typecolors[clearlevel]
	else
		return clearlevel
	end
end

-- ClearTypes based on stage awards and grades.
-- Stageaward based cleartypes do not work if anything causes the stageaward to not show up (disqualification, score saving is off, etc.)
-- and will just result in "No Play" or "Clear". I migggggggggght just drop the SA usage and use raw values instead.
-- returntype 	=0 -> ClearType,
--				=1 -> ShortClearType,
-- 				=2 -> ClearTypeColor,
-- 				=else -> ClearTypeLevel
-- i killed stageawards -mina
local function clearTypes(grade, playCount, perfcount, greatcount, misscount, returntype)
	grade = grade or 0
	playcount = playcount or 0
	misscount = misscount or 0
	clearlevel = 13 -- no play

	if grade == 0 then
		if playcount == 0 then
			clearlevel = 13
		end
	else
		if grade == "Grade_Failed" then -- failed
			clearlevel = 11
		elseif misscount > 0 then
			if misscount == 1 then
				clearlevel = 8 -- missflag
			elseif misscount > 1 and misscount < 10 then
				clearlevel = 9 -- SDCB
			else
				clearlevel = 10 -- Clear
			end
		elseif misscount == 0 then
			if greatcount == 0 then
				if perfcount == 0 then -- MFC
					clearlevel = 1
				elseif perfcount == 1 then -- whiteflag
					clearlevel = 2
				elseif perfcount < 10 and perfcount > 1 then -- SDP
					clearlevel = 3
				else -- PFC
					clearlevel = 4
				end
			else
				if greatcount < 10 and greatcount > 1 then -- SDG
					clearlevel = 6
				elseif greatcount == 1 then -- blackflag
					clearlevel = 5
				else -- FC
					clearlevel = 7
				end
			end
		else
			clearlevel = 12 -- this would mean negative misses
		end
	end
	return getClearTypeItem(clearlevel, returntype)
end

-- LR2 lamps, used for 7k where the game plays by LR2 gauge rules
local bmsLamps = {
	{"FullCombo", "FC", "#66ffff"},
	{"ExHardClear", "EXH", "#ffd91a"},
	{"HardClear", "HARD", "#ffffff"},
	{"NormalClear", "CLEAR", "#4aa8ff"},
	{"EasyClear", "EASY", "#66ff66"},
	{"Failed", "F", "#e61e25"},
}

local function getBMSLampItem(lamp, ret)
	local l = bmsLamps[lamp]
	if ret == 0 then
		return THEME:GetString("ClearTypes", l[1])
	elseif ret == 1 then
		return l[2]
	elseif ret == 2 then
		return color(l[3])
	end
	return lamp
end

-- the gauge a score was played on is kept in its modifiers
local function getBMSGaugeLamp(score)
	local mods = string.lower(score:GetModifiers() or "")
	-- O2Jam charts play on the O2Jam hard gauge
	if mods:find("o2jamhard", 1, true) then
		return 3
	end
	-- "exhardgauge" contains "hardgauge", check it first
	if mods:find("exhardgauge", 1, true) or mods:find("deathgauge", 1, true) then
		return 2
	elseif mods:find("hardgauge", 1, true) then
		return 3
	elseif mods:find("easygauge", 1, true) then
		return 5
	end
	return 4
end

-- lamp index of a score, 1 (full combo) is the best and 6 (failed) the worst
function getBMSLampFromScore(score)
	if score:GetWifeGrade() == "Grade_Failed" then
		return 6
	end
	-- a song played inside a dan course (course gauge) gives no lamp,
	-- like LR2 / beatoraja: it only counts as played
	if string.lower(score:GetModifiers() or ""):find("classgauge", 1, true) then
		return 6
	end
	local tns = function(x) return score:GetTapNoteScore("TapNoteScore_" .. x) end
	local hns = function(x) return score:GetHoldNoteScore("HoldNoteScore_" .. x) end
	local breaks = tns("W4") + tns("W5") + tns("Miss") + hns("LetGo") + hns("MissedHold")
	if breaks == 0 then
		return 1
	end
	return getBMSGaugeLamp(score)
end

-- name (ret 0), short name (ret 1) or color (ret 2) of a lamp index
function getBMSLampInfo(lamp, ret)
	return getBMSLampItem(lamp, ret)
end

local function bmsClearType(score, ret)
	return getBMSLampItem(getBMSLampFromScore(score), ret)
end

-- slowed down plays do not count for lamps, there are no rates in LR2
local function countsForLamp(score)
	return score:GetMusicRate() > 0.999
end

-- best lamp and the score that got it for a chart, nil if never cleared
function getBestBMSLamp(chartKey)
	local best, bestScore
	local rates = SCOREMAN:GetScoresByKey(chartKey)
	if not rates then
		return nil
	end
	for _, hsl in pairs(rates) do
		for _, s in ipairs(hsl:GetScores()) do
			if countsForLamp(s) then
				local lamp = getBMSLampFromScore(s)
				if lamp < 6 and (best == nil or lamp < best or
						(lamp == best and getBMSScoreRate(s) > getBMSScoreRate(bestScore))) then
					best = lamp
					bestScore = s
				end
			end
		end
	end
	return best, bestScore
end

-- best lamp over all 7k charts of a song
function getBestBMSLampForSong(song)
	local best
	for _, st in ipairs(song:GetAllSteps()) do
		if st:GetStepsType() == "StepsType_Kb7_Single" then
			local lamp = getBestBMSLamp(st:GetChartKey())
			if lamp and (best == nil or lamp < best) then
				best = lamp
			end
		end
	end
	return best
end

-- the level of a converted BMS chart is in its pack name ("BMS2SM - SP25"),
-- "SP?" and unknown packs sort below every level
function getBMSLevel(song, steps)
	local group = song and song:GetGroupName() or ""
	local lvl = group:match("[Ss][Pp]%s*(%d+)%s*$")
	if lvl then
		return tonumber(lvl), "SP" .. lvl
	end
	if group:match("[Ss][Pp]%s*%?%s*$") then
		return -1, "SP?"
	end
	if steps then
		return -2, tostring(steps:GetMeter())
	end
	return -2, "?"
end

local function isBMSMode()
	local style = GAMESTATE:GetCurrentStyle()
	return style ~= nil and style:ColumnsPerPlayer() == 7
end

-- Returns the cleartype given the score
function getClearTypeFromScore(pn, score, ret)
	local song
	local steps
	local profile
	local playCount = 0
	local greatcount = 0
	local perfcount = 0
	local misscount = 0
	
	if score == nil then
		return getClearTypeItem(13, ret)
	end
	song = GAMESTATE:GetCurrentSong()
	steps = GAMESTATE:GetCurrentSteps()
	profile = GetPlayerOrMachineProfile(pn)
	if not isScoreValid(pn, steps, score) then
		return getClearTypeItem(12, ret)
	end
	if isBMSMode() then
		return bmsClearType(score, ret)
	end
	if score ~= nil and song ~= nil and steps ~= nil then
		playCount = profile:GetSongNumTimesPlayed(song)
		grade = score:GetWifeGrade()
		perfcount = score:GetTapNoteScore("TapNoteScore_W2")
		greatcount = score:GetTapNoteScore("TapNoteScore_W3")
		misscount =
			score:GetTapNoteScore("TapNoteScore_Miss") + score:GetTapNoteScore("TapNoteScore_W5") +
			score:GetTapNoteScore("TapNoteScore_W4")
	end


	return clearTypes(grade, playCount, perfcount, greatcount, misscount, ret) or typetable[12]
end