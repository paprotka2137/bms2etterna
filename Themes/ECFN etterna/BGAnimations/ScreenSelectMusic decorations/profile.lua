local update = false
local showOnline = false
local recentactive = false
local percentactive = false
-- 7k only: best clears, sorted by pack level and then lamp
local bestactive = hideMSD()
local bestList = {}
local buildBestList
-- 7k has no MSD, its profile page falls back to Best when nothing is picked
local function BroadcastIfActive(msg)
	if update then
		if msg == "UpdateRanking" and hideMSD() and not (recentactive or percentactive or bestactive) then
			bestactive = true
			buildBestList()
		end
		MESSAGEMAN:Broadcast(msg)
	end
end

-- 7k: ECFN style buttons, lit blue when picked
local ecfnDir = THEME:GetCurrentThemeDirectory()
if ecfnDir:sub(1, 1) ~= "/" then
	ecfnDir = "/" .. ecfnDir
end
ecfnDir = ecfnDir .. "BGAnimations/ScreenSelectMusic decorations/ecfn/"
-- 7k: a flat button like the Dan window's, centered on its frame
local function ecfnButtonBG(w, h)
	return Def.ActorFrame {
		InitCommand = function(self)
			self:visible(hideMSD())
		end,
		Def.Quad {
			InitCommand = function(self)
				self:zoomto(w, h):diffuse(color("1,1,1,0.08"))
			end,
		},
	}
end
local function ecfnCell(w, h, extra)
	local f = ecfnButtonBG(w, h)
	if extra then
		local init = f.InitCommand
		f.InitCommand = function(self)
			init(self)
			extra(self)
		end
	end
	return f
end
local function buttonLight(self, on)
	if hideMSD() then
		self:diffuse(color("#3f9fff")):diffusealpha(on and 0.4 or 0)
	else
		self:diffusealpha(on and 1 or 0.2)
	end
end

local translated_info = {
	Validated = THEME:GetString("TabProfile", "ScoreValidated"),
	Invalidated = THEME:GetString("TabProfile", "ScoreInvalidated"),
	Online = THEME:GetString("TabProfile", "Online"),
	Local = THEME:GetString("TabProfile", "Local"),
	Recent = THEME:GetString("TabProfile", "Recent"),
	Percent = THEME:GetString("TabProfile", "Percent"),
	Best = THEME:GetString("TabProfile", "Best"),
	NextPage = THEME:GetString("TabProfile", "NextPage"),
	PrevPage = THEME:GetString("TabProfile", "PreviousPage"),
	Save = THEME:GetString("TabProfile", "SaveProfile"),
	AssetSettings = THEME:GetString("TabProfile", "AssetSettingEntry"),
	Success = THEME:GetString("TabProfile", "SaveSuccess"),
	Failure = THEME:GetString("TabProfile", "SaveFail"),
	ValidateAll = THEME:GetString("TabProfile", "ValidateAllScores"),
	ForceRecalc = THEME:GetString("TabProfile", "ForceRecalcScores"),
	UploadAllScore = THEME:GetString("TabProfile", "UploadAllScore"),
}

local t = Def.ActorFrame {
	BeginCommand = function(self)
		self:queuecommand("Set"):visible(false)
	end,
	OffCommand = function(self)
		self:bouncebegin(0.2):xy(-500, 0):diffusealpha(0)
		self:sleep(0.04):queuecommand("Invis")
	end,
	InvisCommand= function(self)
		self:visible(false)
	end,
	OnCommand = function(self)
		self:bouncebegin(0.2):xy(0, 0):diffusealpha(1)
	end,
	SetCommand = function(self)
		self:finishtweening()
		if getTabIndex() == 4 or SCREENMAN:GetTopScreen():GetName() == "ScreenNetRoom" and getTabIndex() == 1 then
			self:queuecommand("On")
			self:visible(true)
			update = true
			-- 7k opens on the Best list, freshly built
			if hideMSD() and bestactive then
				buildBestList()
				BroadcastIfActive("UpdateRanking")
			end
		else
			self:queuecommand("Off")
			update = false
		end
	end,
	LogOutMessageCommand = function(self)
		showOnline = false
		BroadcastIfActive("UpdateRanking")
	end,
	LoginMessageCommand = function(self)
		BroadcastIfActive("UpdateRanking")
	end,
	LoginFailedMessageCommand = function(self)
		BroadcastIfActive("UpdateRanking")
	end,
	OnlineUpdateMessageCommand = function(self)
		BroadcastIfActive("UpdateRanking")
	end,
	TabChangedMessageCommand = function(self)
		self:queuecommand("Set")
	end
}

local frameX = 10
local frameY = 45
local frameWidth = capWideScale(360, 400)
local frameHeight = 350
local fontScale = 0.25
local scoresperpage = 20
local scoreYspacing = 12.5
local distY = 15
local offsetX = -10
local offsetY = 20
local txtDist = 33
local rankingSkillset = 1
local rankingPage = 1
local numrankingpages = 10
local rankingWidth = frameWidth - capWideScale(10, 25)
local rankingX = capWideScale(25, 35)
local rankingY = capWideScale(40, 40)
local rankingTitleSpacing = (rankingWidth / (#ms.SkillSets))
local buttondiffuse = 0
local whee
local profile

if GAMESTATE:IsPlayerEnabled() then
	profile = GetPlayerOrMachineProfile(PLAYER_1)
end

t[#t + 1] = Def.Quad {
	InitCommand = function(self)
		self:xy(frameX, frameY):zoomto(frameWidth, frameHeight):halign(0):valign(0):diffuse(getMainColor("tabs"))
	end
}

local hoverAlpha = 0.6

local function byValidity(valid)
	if valid then
		return getMainColor("positive")
	end
	return byJudgment("TapNoteScore_Miss")
end

local function ButtonActive(self)
	return isOver(self) and update
end

-- one entry per cleared 7k chart: an easy clear on a higher level ranks above
-- any lamp on a lower one, then the better lamp, then the better percent
buildBestList = function()
	bestList = {}
	local seen = {}
	SCOREMAN:SortRecentScoresForGame()
	local n = 1
	local hs = SCOREMAN:GetRecentScoreForGame(n)
	while hs do
		local ck = hs:GetChartKey()
		if not seen[ck] then
			seen[ck] = true
			local steps = SONGMAN:GetStepsByChartKey(ck)
			if steps and steps:GetStepsType() == "StepsType_Kb7_Single" then
				local lamp, best = getBestBMSLamp(ck)
				if lamp then
					local song = SONGMAN:GetSongByChartKey(ck)
					local level, levelName = getBMSLevel(song, steps)
					bestList[#bestList + 1] = {
						score = best, song = song, steps = steps, lamp = lamp,
						level = level, levelName = levelName, wife = getBMSScoreRate(best),
					}
				end
			end
		end
		n = n + 1
		hs = SCOREMAN:GetRecentScoreForGame(n)
	end
	table.sort(bestList, function(a, b)
		if a.level ~= b.level then return a.level > b.level end
		if a.lamp ~= b.lamp then return a.lamp < b.lamp end
		return a.wife > b.wife
	end)
end

-- level column for 7k, where there is no SSR to show
local function levelText(song, steps)
	local _, name = getBMSLevel(song, steps)
	return name
end

-- The input callback for mouse clicks already exists within the tabmanager and redefining it within the local scope does nothing but create confusion - mina
local r = Def.ActorFrame {
	InitCommand = function(self)
		self:xy(frameX, frameY)
	end,
	OnCommand = function(self)
		whee = SCREENMAN:GetTopScreen():GetMusicWheel()
	end
}

local function rankingLabel(i)
	local ths  -- the top highscore object - mina
	local ck
	local thssteps
	local thssong
	local xoffset
	local onlineScore

	local t = Def.ActorFrame {
		InitCommand = function(self)
			self:xy(rankingX + offsetX + 7, rankingY + offsetY + 10 + (i - 1) * scoreYspacing)
			-- self:RunCommandsOnChildren(cmd(halign,0;zoom,fontScale))
			self:visible(false)
		end,
		UpdateRankingMessageCommand = function(self)
			if rankingSkillset > 1 and update and not recentactive and not bestactive then
				if not showOnline then
					ths = SCOREMAN:GetTopSSRHighScoreForGame(i + (scoresperpage * (rankingPage - 1)), ms.SkillSets[rankingSkillset])
					if ths then
						self:visible(true)
						ck = ths:GetChartKey()
						thssong = SONGMAN:GetSongByChartKey(ck)
						thssteps = SONGMAN:GetStepsByChartKey(ck)
						MESSAGEMAN:Broadcast("DisplayProfileRankingLabels")
					else
						self:visible(false)
					end
				else
					onlineScore = DLMAN:GetTopSkillsetScore(i, ms.SkillSets[rankingSkillset])
					MESSAGEMAN:Broadcast("DisplayProfileRankingLabels")
					if not onlineScore then
						self:visible(false)
					else
						self:visible(true)
					end
				end
			else
				onlinesScore = nil
				self:visible(false)
			end
		end,
		LoadFont("Common Large") .. {
			Name = "text1",
			InitCommand = function(self)
				self:halign(0):zoom(fontScale)
				self:maxwidth(100)
			end,
			DisplayProfileRankingLabelsMessageCommand = function(self)
				if not showOnline then
					if ths then
						self:halign(0.5)
						self:settext(((rankingPage - 1) * scoresperpage) + i .. ".")
						self:diffuse(byValidity(ths:GetEtternaValid()))
					end
				else
					self:halign(0.5)
					self:settext(i .. ".")
					self:diffuse(getMainColor("positive"))
				end
			end
		},
		LoadFont("Common Large") .. {
			Name = "text2",
			InitCommand = function(self)
				self:halign(0):zoom(fontScale)
				self:x(15):maxwidth(160)
			end,
			DisplayProfileRankingLabelsMessageCommand = function(self)
				if not showOnline then
					if ths and hideMSD() then
						self:settext(levelText(thssong, thssteps))
						self:diffuse(byValidity(ths:GetEtternaValid()))
					elseif ths then
						self:settextf("%5.2f", ths:GetSkillsetSSR(ms.SkillSets[rankingSkillset]))
						self:diffuse(byValidity(ths:GetEtternaValid()))
					else
						self:settext("")
					end
				else
					if onlineScore then
						self:settextf("%5.2f", onlineScore.ssr)
						self:diffuse(getMainColor("positive"))
					else
						self:settext("")
					end
				end
			end
		},
		LoadFont("Common Large") .. {
			Name = "text3",
			InitCommand = function(self)
				self:halign(0):zoom(fontScale)
				self:x(60):maxwidth(580)
			end,
			DisplayProfileRankingLabelsMessageCommand = function(self)
				if not showOnline then
					if thssong and ths then
						self:settext(thssong:GetDisplayMainTitle())
						self:diffuse(byValidity(ths:GetEtternaValid()))
					else
						self:settext("")
					end
				else
					if onlineScore then
						self:settext(onlineScore.songName)
						self:diffuse(getMainColor("positive"))
					else
						self:settext("")
					end
				end
			end
		},
		LoadFont("Common Large") .. {
			Name = "text4",
			InitCommand = function(self)
				self:halign(0):zoom(fontScale)
				self:x(225)
			end,
			DisplayProfileRankingLabelsMessageCommand = function(self)
				if not showOnline then
					if ths then
						self:halign(0.5)
						local ratestring = string.format("%.2f", ths:GetMusicRate()):gsub("%.?0+$", "") .. "x"
						self:settext(ratestring)
						self:diffuse(byValidity(ths:GetEtternaValid()))
					else
						self:settext("")
					end
				else
					if onlineScore then
						local ratestring = string.format("%.2f", onlineScore.rate):gsub("%.?0+$", "") .. "x"
						self:halign(0.5)
						self:settext(ratestring)
						self:diffuse(getMainColor("positive"))
					else
						self:settext("")
					end
				end
			end
		},
		LoadFont("Common Large") .. {
			Name = "text5",
			InitCommand = function(self)
				self:halign(0):zoom(fontScale)
				self:x(245):maxwidth(160)
			end,
			DisplayProfileRankingLabelsMessageCommand = function(self)
				if not showOnline then
					if ths then
						local wifeval = getDisplayScorePercent(ths)
						if wifeval > 99.9 then
							self:settextf("%5.4f%%", wifeval)
						else
							self:settextf("%5.2f%%", wifeval)
						end
						if not ths:GetEtternaValid() then
							self:diffuse(byJudgment("TapNoteScore_Miss"))
						else
							self:diffuse(getGradeColor(ths:GetWifeGrade()))
						end
					else
						self:settext("")
					end
				else
					if onlineScore then
						self:settextf("%5.2f%%", onlineScore.wife * 100)
						self:diffuse(getGradeColor(onlineScore.grade))
					else
						self:settext("")
					end
				end
			end
		},
		LoadFont("Common Large") .. {
			Name = "text6",
			InitCommand = function(self)
				self:halign(0):zoom(fontScale)
				self:x(305)
			end,
			DisplayProfileRankingLabelsMessageCommand = function(self)
				self:halign(0.5)
				if not showOnline then
					if thssteps then
						local diff = thssteps:GetDifficulty()
						self:diffuse(byDifficulty(diff))
						self:settext(getShortDifficulty(diff))
					else
						self:settext("")
					end
				else
					if onlineScore then
						local diff = onlineScore.difficulty
						self:diffuse(byDifficulty(diff))
						self:settext(getShortDifficulty(diff))
					else
						self:settext("")
					end
				end
			end
		},
		UIElements.QuadButton(1, 1) .. {
			InitCommand = function(self)
				self:x(-8):halign(0):diffusealpha(buttondiffuse)
			end,
			DisplayProfileRankingLabelsMessageCommand = function(self) -- hacky
				self:visible(true)
				self:zoomto(frameWidth - capWideScale(38,78), scoreYspacing * .995)
			end,
			MouseDownCommand = function(self, params)
				if rankingSkillset > 1 and params.event == "DeviceButton_left mouse button" and update then
					if not showOnline then
						if ths then
							whee:SelectSong(thssong)
						end
					elseif onlineScore and onlineScore.chartkey then
						local song = SONGMAN:GetSongByChartKey(onlineScore.chartkey)
						if song then
							whee:SelectSong(song)
						end
					end
				elseif params.event == "DeviceButton_right mouse button" and update and not showOnline and ths then
					ths:ToggleEtternaValidation()
					BroadcastIfActive("UpdateRanking")
					if ths:GetEtternaValid() then
						ms.ok(translated_info["Validated"])
					else
						ms.ok(translated_info["Invalidated"])
					end
				end
			end,
			MouseOverCommand = function(self)
				local alpha = 0.7
				for i = 1,6 do
					self:GetParent():GetChild("text" .. i):diffusealpha(alpha)
				end
			end,
			MouseOutCommand = function(self)
				local alpha = 1
				for i = 1,6 do
					self:GetParent():GetChild("text" .. i):diffusealpha(alpha)
				end
			end,
		}
	}
	return t
end

local function rankingButton(i)
	local t = Def.ActorFrame {
		InitCommand = function(self)
			self:xy(rankingX + (i - 1) * rankingTitleSpacing, rankingY * 1.15)
		end,
		BeginCommand = function(self)
			self:visible(not hideMSD())
		end,
		UpdateRankingMessageCommand = function(self)
			self:visible(not hideMSD())
		end,
		ecfnCell(rankingTitleSpacing - 2, 22),
		UIElements.QuadButton(1, 1) .. {
			InitCommand = function(self)
				self:zoomto(rankingTitleSpacing, 26):diffuse(getMainColor("frames"))
				buttonLight(self, false)
			end,
			SetCommand = function(self)
				if i == rankingSkillset and not recentactive and not bestactive then
					self:diffusealpha(1)
				else
					self:diffusealpha(0.2)
				end
			end,
			MouseDownCommand = function(self, params)
				if params.event == "DeviceButton_left mouse button" and update and not hideMSD() then
					recentactive = false
					bestactive = false
					rankingSkillset = i
					rankingPage = 1
					if not percentactive then
						SCOREMAN:SortSSRsForGame(ms.SkillSets[rankingSkillset])
					else
						SCOREMAN:SortSSRsByPercentForGame()
					end
					BroadcastIfActive("UpdateRanking")
				end
			end,
			UpdateRankingMessageCommand = function(self)
				self:queuecommand("Set")
			end,
			MouseOverCommand = function(self)
				local alpha = 0.7
				self:GetParent():GetChild("RankButtonTxt"):diffusealpha(alpha)
			end,
			MouseOutCommand = function(self)
				local alpha = 1
				self:GetParent():GetChild("RankButtonTxt"):diffusealpha(alpha)
			end,
		},
		LoadFont("Common Large") .. {
			Name = "RankButtonTxt",
			InitCommand = function(self)
				self:addy(-1):diffuse(getMainColor("positive")):maxwidth(rankingTitleSpacing / 0.40 - 10):zoom(0.40)
			end,
			BeginCommand = function(self)
				self:settext(ms.SkillSetsTranslated[i])
			end
		}
	}
	return t
end


local function recentLabel(i)
	local ths  -- aAAAAAAAA
	local ck
	local thssteps
	local thssong
	local xoffset
	local onlineScore

	local t = Def.ActorFrame {
		InitCommand = function(self)
			self:xy(rankingX - 22 , rankingY + offsetY + 10 + (i - 1) * scoreYspacing)
			self:visible(false)
		end,
		UpdateRankingMessageCommand = function(self)
			if recentactive and update then
					ths = SCOREMAN:GetRecentScoreForGame(i + (scoresperpage * (rankingPage - 1)))
					if ths then
						self:visible(true)
						ck = ths:GetChartKey()
						thssong = SONGMAN:GetSongByChartKey(ck)
						thssteps = SONGMAN:GetStepsByChartKey(ck)
						MESSAGEMAN:Broadcast("DisplayProfileRankingLabels")
					else
						self:visible(false)
					end
			else
				onlinesScore = nil
				self:visible(false)
			end
		end,
		LoadFont("Common Large") .. {
			Name = "rectext1",
			InitCommand = function(self)
				self:halign(0):zoom(fontScale)
				self:maxwidth(100)
			end,
			DisplayProfileRankingLabelsMessageCommand = function(self)
				if ths and IsUsingWideScreen() then
					self:halign(0.5)
					self:settext(((rankingPage - 1) * scoresperpage) + i .. ".")
					self:diffuse(byValidity(ths:GetEtternaValid()))
				end
			end
		},
		LoadFont("Common Large") .. {
			Name = "rectext2",
			InitCommand = function(self)
				self:halign(0):zoom(fontScale)
				self:x(15):maxwidth(160)
			end,
			DisplayProfileRankingLabelsMessageCommand = function(self)
				if ths and hideMSD() then
					self:settext(levelText(thssong, thssteps))
					self:diffuse(byValidity(ths:GetEtternaValid()))
				elseif ths then
					self:settextf("%5.2f", ths:GetSkillsetSSR(ms.SkillSets[1]))
					self:diffuse(byValidity(ths:GetEtternaValid()))
				else
					self:settext("")
				end
			end
		},
		LoadFont("Common Large") .. {
			Name = "rectext3",
			InitCommand = function(self)
				self:halign(0):zoom(fontScale)
				self:x(55):maxwidth(580)
			end,
			DisplayProfileRankingLabelsMessageCommand = function(self)
				if thssong and ths then
					self:settext(thssong:GetDisplayMainTitle())
					self:diffuse(byValidity(ths:GetEtternaValid()))
				else
					self:settext("")
				end
			end
		},
		LoadFont("Common Large") .. {
			Name = "rectext4",
			InitCommand = function(self)
				self:halign(0):zoom(fontScale)
				self:x(220)
			end,
			DisplayProfileRankingLabelsMessageCommand = function(self)
				if ths then
					self:halign(0.5)
					local ratestring = string.format("%.2f", ths:GetMusicRate()):gsub("%.?0+$", "") .. "x"
					self:settext(ratestring)
					self:diffuse(byValidity(ths:GetEtternaValid()))
				else
					self:settext("")
				end
			end
		},
		LoadFont("Common Large") .. {
			Name = "rectext5",
			InitCommand = function(self)
				self:halign(0):zoom(fontScale)
				self:x(240):maxwidth(160)
			end,
			DisplayProfileRankingLabelsMessageCommand = function(self)
				if ths then
					local wifeval = getDisplayScorePercent(ths)
					if wifeval > 99.9 then
						self:settextf("%5.4f%%", wifeval)
					else
						self:settextf("%5.2f%%", wifeval)
					end
					if not ths:GetEtternaValid() then
						self:diffuse(byJudgment("TapNoteScore_Miss"))
					else
						self:diffuse(getGradeColor(ths:GetWifeGrade()))
					end
				else
					self:settext("")
				end
			end
		},
		LoadFont("Common Large") .. {
			Name = "rectext6",
			InitCommand = function(self)
				self:halign(0):zoom(fontScale)
				self:x(300)
			end,
			DisplayProfileRankingLabelsMessageCommand = function(self)
				self:halign(0.5)
				if thssteps then
					local diff = thssteps:GetDifficulty()
					self:diffuse(byDifficulty(diff))
					self:settext(getShortDifficulty(diff))
				else
					self:settext("")
				end
			end
		},
		LoadFont("Common Normal") .. {
			Name = "rectext7",
			--date
			InitCommand = function(self)
				self:x(312):zoom(fontScale + 0.05):halign(0)
			end,
			DisplayProfileRankingLabelsMessageCommand = function(self)
				if ths then
					if not IsUsingWideScreen() then
						self:settext(getScoreDate(ths):sub(1,10)):x(318)
					else
						self:settext(getScoreDate(ths))
					end
				else
					self:settext("")
				end
			end,
		},
		UIElements.QuadButton(1, 1) .. {
			InitCommand = function(self)
				self:x(capWideScale(15,-7)):halign(0):zoom(fontScale):diffusealpha(buttondiffuse)
			end,
			DisplayProfileRankingLabelsMessageCommand = function(self) -- hacky
				self:visible(true)
				self:zoomto(frameWidth - capWideScale(14,10), scoreYspacing * .995)
				-- 7k: faint rows like the Dan window
				if hideMSD() then
					self:diffuse(color("#ffffff")):diffusealpha(i % 2 == 0 and 0.04 or 0.07)
				end
			end,
			MouseDownCommand = function(self, params)
				if recentactive and params.event == "DeviceButton_left mouse button" and update then
					if ths then
						whee:SelectSong(thssong)
					end
				elseif params.event == "DeviceButton_right mouse button" and update and recentactive then
					if ths and not showOnline then
						ths:ToggleEtternaValidation()
						BroadcastIfActive("UpdateRanking")
						if ths:GetEtternaValid() then
							ms.ok(translated_info["Validated"])
						else
							ms.ok(translated_info["Invalidated"])
						end
					end
				end
			end,
			MouseOverCommand = function(self)
				local alpha = 0.7
				for i = 1,7 do
					self:GetParent():GetChild("rectext" .. i):diffusealpha(alpha)
				end
			end,
			MouseOutCommand = function(self)
				local alpha = 1
				for i = 1,7 do
					self:GetParent():GetChild("rectext" .. i):diffusealpha(alpha)
				end
			end,
		},
	}
	return t
end

local function recentButton()
	local t = Def.ActorFrame {
		InitCommand = function(self)
			self:xy(rankingX + (3.5) * rankingTitleSpacing, 24 * 0.75):valign(1)
		end,
		ecfnCell(rankingTitleSpacing - 2, 22),
		UIElements.QuadButton(1, 1) .. {
			InitCommand = function(self)
				self:zoomto(rankingTitleSpacing, 26):diffuse(getMainColor("frames"))
				buttonLight(self, false)
			end,
			SetCommand = function(self)
				buttonLight(self, recentactive)
			end,
			MouseDownCommand = function(self, params)
				if params.event == "DeviceButton_left mouse button" and update then
					bestactive = false
					rankingPage = 1
					-- 7k has no overall button to go back to the profile, so recent toggles
					if recentactive and hideMSD() then
						recentactive = false
						rankingSkillset = 1
					else
						recentactive = true
						percentactive = false
						SCOREMAN:SortRecentScoresForGame()
					end
					BroadcastIfActive("UpdateRanking")
				end
			end,
			UpdateRankingMessageCommand = function(self)
				self:queuecommand("Set")
			end,
			MouseOverCommand = function(self)
				local alpha = 0.7
				self:GetParent():GetChild("RecentButtonTxt"):diffusealpha(alpha)
			end,
			MouseOutCommand = function(self)
				local alpha = 1
				self:GetParent():GetChild("RecentButtonTxt"):diffusealpha(alpha)
			end,
		},
		LoadFont(hideMSD() and "Common Normal" or "Common Large") .. {
			Name = "RecentButtonTxt",
			InitCommand = function(self)
				self:addy(-1):diffuse(getMainColor("positive")):maxwidth(rankingTitleSpacing * 2):zoom(hideMSD() and 0.4 or 0.42)
			end,
			BeginCommand = function(self)
				self:settext(hideMSD() and string.upper(translated_info["Recent"]) or translated_info["Recent"])
			end
		}
	}
	return t
end

local function percentButton()
	local t = Def.ActorFrame {
		InitCommand = function(self)
			self:xy(rankingX + (2.5) * rankingTitleSpacing, 24 * 0.75):valign(1)
		end,
		ecfnCell(rankingTitleSpacing - 2, 22),
		UIElements.QuadButton(1, 1) .. {
			InitCommand = function(self)
				self:zoomto(rankingTitleSpacing, 26):diffuse(getMainColor("frames"))
				buttonLight(self, false)
			end,
			SetCommand = function(self)
				buttonLight(self, percentactive)
			end,
			MouseDownCommand = function(self, params)
				if params.event == "DeviceButton_left mouse button" and update then
					percentactive = not percentactive
					showOnline = false
					recentactive = false
					bestactive = false
					rankingPage = 1
					if rankingSkillset == 1 then
						rankingSkillset = 2
					end

					if not percentactive and hideMSD() then
						rankingSkillset = 1
					elseif not percentactive then
						SCOREMAN:SortSSRsForGame(ms.SkillSets[rankingSkillset])
					else
						SCOREMAN:SortSSRsByPercentForGame()
					end
					BroadcastIfActive("UpdateRanking")
				end
			end,
			UpdateRankingMessageCommand = function(self)
				self:queuecommand("Set")
			end,
			MouseOverCommand = function(self)
				local alpha = 0.7
				self:GetParent():GetChild("PercentButtonTxt"):diffusealpha(alpha)
			end,
			MouseOutCommand = function(self)
				local alpha = 1
				self:GetParent():GetChild("PercentButtonTxt"):diffusealpha(alpha)
			end,
		},
		LoadFont(hideMSD() and "Common Normal" or "Common Large") .. {
			Name = "PercentButtonTxt",
			InitCommand = function(self)
				self:addy(-1):diffuse(getMainColor("positive")):maxwidth(rankingTitleSpacing * 2):zoom(hideMSD() and 0.4 or 0.42)
			end,
			BeginCommand = function(self)
				self:settext(hideMSD() and string.upper(translated_info["Percent"]) or translated_info["Percent"])
			end
		}
	}
	return t
end


local function bestLabel(i)
	local entry

	local t = Def.ActorFrame {
		InitCommand = function(self)
			self:xy(rankingX - 22 , rankingY + offsetY + 10 + (i - 1) * scoreYspacing)
			self:visible(false)
		end,
		UpdateRankingMessageCommand = function(self)
			entry = nil
			if bestactive and update and not showOnline then
				entry = bestList[i + (scoresperpage * (rankingPage - 1))]
			end
			self:visible(entry ~= nil)
			if entry then
				self:playcommand("DisplayBest")
			end
		end,
		LoadFont("Common Large") .. {
			Name = "besttext1",
			InitCommand = function(self)
				self:halign(0.5):zoom(fontScale):maxwidth(100)
			end,
			DisplayBestCommand = function(self)
				self:settext(((rankingPage - 1) * scoresperpage) + i .. ".")
				self:diffuse(getMainColor("positive"))
				self:visible(IsUsingWideScreen())
			end
		},
		LoadFont("Common Large") .. {
			Name = "besttext2",
			InitCommand = function(self)
				self:halign(0):zoom(fontScale):x(15):maxwidth(160)
			end,
			DisplayBestCommand = function(self)
				self:settext(entry.levelName)
				self:diffuse(getMainColor("positive"))
			end
		},
		LoadFont("Common Large") .. {
			Name = "besttext3",
			InitCommand = function(self)
				self:halign(0):zoom(fontScale):x(55):maxwidth(580)
			end,
			DisplayBestCommand = function(self)
				self:settext(entry.song and entry.song:GetDisplayMainTitle() or "")
				self:diffuse(getMainColor("positive"))
			end
		},
		LoadFont("Common Large") .. {
			Name = "besttext4",
			InitCommand = function(self)
				self:halign(0.5):zoom(fontScale):x(220)
			end,
			DisplayBestCommand = function(self)
				self:settext(string.format("%.2f", entry.score:GetMusicRate()):gsub("%.?0+$", "") .. "x")
				self:diffuse(getMainColor("positive"))
			end
		},
		LoadFont("Common Large") .. {
			Name = "besttext5",
			InitCommand = function(self)
				self:halign(0):zoom(fontScale):x(240):maxwidth(160)
			end,
			DisplayBestCommand = function(self)
				self:settextf("%5.2f%%", entry.wife * 100)
				self:diffuse(getGradeColor(entry.score:GetWifeGrade()))
			end
		},
		-- the ECFN clear name (E-CLEAR, H-CLEAR, F-COMBO...) of the lamp
		Def.Sprite {
			Name = "besttext6",
			Texture = ecfnDir .. "state_clear 3x11.png",
			InitCommand = function(self)
				self:animate(false):halign(0.5):x(306):zoomto(48, 8.4)
			end,
			DisplayBestCommand = function(self)
				self:setstate(getBMSLampFrame(entry.score) * 3)
			end
		},
		LoadFont("Common Normal") .. {
			Name = "besttext7",
			InitCommand = function(self)
				self:x(capWideScale(318, 330)):zoom(fontScale + 0.05):halign(0)
			end,
			DisplayBestCommand = function(self)
				self:settext(getScoreDate(entry.score):sub(1, 10))
			end,
		},
		UIElements.QuadButton(1, 1) .. {
			InitCommand = function(self)
				self:x(capWideScale(15,-7)):halign(0):diffusealpha(buttondiffuse)
			end,
			DisplayBestCommand = function(self)
				self:zoomto(frameWidth - capWideScale(14,10), scoreYspacing * .995)
				-- 7k: faint rows like the Dan window
				if hideMSD() then
					self:diffuse(color("#ffffff")):diffusealpha(i % 2 == 0 and 0.04 or 0.07)
				end
			end,
			MouseDownCommand = function(self, params)
				if bestactive and update and entry and entry.song and params.event == "DeviceButton_left mouse button" then
					whee:SelectSong(entry.song)
				end
			end,
			MouseOverCommand = function(self)
				for i = 1,7 do
					self:GetParent():GetChild("besttext" .. i):diffusealpha(0.7)
				end
			end,
			MouseOutCommand = function(self)
				for i = 1,7 do
					self:GetParent():GetChild("besttext" .. i):diffusealpha(1)
				end
			end,
		},
	}
	return t
end

local function bestButton()
	local t = Def.ActorFrame {
		InitCommand = function(self)
			self:xy(rankingX + (4.5) * rankingTitleSpacing, 24 * 0.75):valign(1)
		end,
		BeginCommand = function(self)
			self:visible(hideMSD())
		end,
		ecfnCell(rankingTitleSpacing - 2, 22),
		UIElements.QuadButton(1, 1) .. {
			InitCommand = function(self)
				self:zoomto(rankingTitleSpacing, 26):diffuse(getMainColor("frames"))
				buttonLight(self, false)
			end,
			SetCommand = function(self)
				buttonLight(self, bestactive)
			end,
			MouseDownCommand = function(self, params)
				if params.event == "DeviceButton_left mouse button" and update and hideMSD() then
					recentactive = false
					percentactive = false
					showOnline = false
					rankingSkillset = 1
					rankingPage = 1
					bestactive = true
					if bestactive then
						buildBestList()
					end
					BroadcastIfActive("UpdateRanking")
				end
			end,
			UpdateRankingMessageCommand = function(self)
				self:queuecommand("Set")
			end,
			MouseOverCommand = function(self)
				self:GetParent():GetChild("BestButtonTxt"):diffusealpha(0.7)
			end,
			MouseOutCommand = function(self)
				self:GetParent():GetChild("BestButtonTxt"):diffusealpha(1)
			end,
		},
		LoadFont(hideMSD() and "Common Normal" or "Common Large") .. {
			Name = "BestButtonTxt",
			InitCommand = function(self)
				self:addy(-1):diffuse(getMainColor("positive")):maxwidth(rankingTitleSpacing * 2):zoom(hideMSD() and 0.4 or 0.42)
			end,
			BeginCommand = function(self)
				self:settext(hideMSD() and string.upper(translated_info["Best"]) or translated_info["Best"])
			end
		}
	}
	return t
end

-- Online and Local buttons
t[#t + 1] = Def.ActorFrame {
	InitCommand = function(self)
		self:x(8)
		if DLMAN:IsLoggedIn() then
			self:visible(true)
		else
			self:visible(false)
		end
	end,
	SetCommand = function(self)
		if DLMAN:IsLoggedIn() then
			self:visible(true)
		else
			self:visible(false)
		end
	end,
	UpdateRankingMessageCommand = function(self)
		self:queuecommand("Set")
	end,
	Def.ActorFrame {
		InitCommand = function(self)
			self:xy(rankingX + frameWidth * 6 / 8 - rankingTitleSpacing, rankingY + offsetY + 2)
		end,
		UIElements.QuadButton(1, 1) .. {
			InitCommand = function(self)
				self:zoomto(rankingTitleSpacing, 26):diffusealpha(0.2):diffuse(getMainColor("frames"))
			end,
			SetCommand = function(self)
				if not showOnline then
					self:diffusealpha(1)
				else
					self:diffusealpha(0.2)
				end
			end,
			MouseDownCommand = function(self, params)
				if params.event == "DeviceButton_left mouse button" and update then
					showOnline = false
					BroadcastIfActive("UpdateRanking")
				end
			end,
			UpdateRankingMessageCommand = function(self)
				self:queuecommand("Set")
			end,
			MouseOverCommand = function(self)
				local alpha = 0.7
				self:GetParent():GetChild("LocalTxt"):diffusealpha(alpha)
			end,
			MouseOutCommand = function(self)
				local alpha = 1
				self:GetParent():GetChild("LocalTxt"):diffusealpha(alpha)
			end,
		},
		LoadFont("Common Large") ..{
			Name = "LocalTxt",
			InitCommand = function(self)
				self:diffuse(getMainColor("positive")):maxwidth(rankingTitleSpacing*2):zoom(0.42)
			end,
			BeginCommand = function(self)
				self:settext(translated_info["Local"])
			end
		}
	},
	Def.ActorFrame {
		InitCommand = function(self)
			self:xy(rankingX + frameWidth * 7 / 8 - rankingTitleSpacing, rankingY + offsetY + 2)
		end,
		UIElements.QuadButton(1, 1) .. {
			InitCommand = function(self)
				self:zoomto(rankingTitleSpacing, 26):diffusealpha(0.2)
				if DLMAN:IsLoggedIn() then
					self:diffuse(getMainColor("frames"))
					if showOnline then
						self:diffusealpha(1)
					else
						self:diffusealpha(0.2)
					end
				else
					self:diffuse(getMainColor("disabled")):diffusealpha(0.1)
				end
			end,
			SetCommand = function(self)
				if DLMAN:IsLoggedIn() then
					self:diffuse(getMainColor("frames"))
					if showOnline then
						self:diffusealpha(1)
					else
						self:diffusealpha(0.2)
					end
				else
					self:diffuse(getMainColor("disabled")):diffusealpha(0.1)
				end
			end,
			MouseDownCommand = function(self, params)
				if params.event == "DeviceButton_left mouse button" and update and DLMAN:IsLoggedIn() then
					showOnline = true
					BroadcastIfActive("UpdateRanking")
				end
			end,
			UpdateRankingMessageCommand = function(self)
				self:queuecommand("Set")
			end,
			MouseOverCommand = function(self)
				local alpha = 0.7
				self:GetParent():GetChild("OnlineTxt"):diffusealpha(alpha)
			end,
			MouseOutCommand = function(self)
				local alpha = 1
				self:GetParent():GetChild("OnlineTxt"):diffusealpha(alpha)
			end,
		},
		LoadFont("Common Large") .. {
			Name = "OnlineTxt",
			InitCommand = function(self)
				self:diffuse(getMainColor("positive")):maxwidth(rankingTitleSpacing*2):zoom(0.42)
			end,
			BeginCommand = function(self)
				self:settext(translated_info["Online"])
			end
		}
	},

}
-- prev/next page
r[#r + 1] = Def.ActorFrame {
	InitCommand = function(self)
		self:xy(10, frameHeight - offsetY):visible(false)
	end,
	UpdateRankingMessageCommand = function(self)
		if (rankingSkillset > 1 or recentactive or bestactive) and not showOnline then
			self:visible(true)
			if not self and self.GetChildren then
				for child in self:GetChildren() do
					child:queuecommand("Display")
				end
			end
		else
			self:visible(false)
		end
	end,
	ecfnCell(42, 18, function(self)
		self:xy(capWideScale(300,336.25) + 21, 1.5)
	end),
	UIElements.QuadButton(1, 1) .. {
		InitCommand = function(self)
			self:xy(capWideScale(300,336.25), -8.5):zoomto(40, 20):halign(0):valign(0):diffuse(getMainColor("frames")):diffusealpha(hideMSD() and 0 or 0.2)
		end,
		MouseDownCommand = function(self, params)
			if params.event == "DeviceButton_left mouse button" then
				if rankingPage < numrankingpages then
					rankingPage = rankingPage + 1
				else
					rankingPage = 1
				end
				BroadcastIfActive("UpdateRanking")
			end
		end,
		MouseOverCommand = function(self)
			local alpha = 0.7
			self:GetParent():GetChild("NextP"):diffusealpha(alpha)
		end,
		MouseOutCommand = function(self)
			local alpha = 1
			self:GetParent():GetChild("NextP"):diffusealpha(alpha)
		end,

	},
	LoadFont(hideMSD() and "Common Normal" or "Common Large") .. {
		Name = "NextP",
		InitCommand = function(self)
			self:x(capWideScale(304.25,340)):halign(0):zoom(hideMSD() and 0.36 or 0.3):diffuse(getMainColor("positive")):settext(hideMSD() and string.upper(translated_info["NextPage"]) or translated_info["NextPage"])
		end,
	},
	ecfnCell(67, 18, function(self)
		self:xy(-2 + 33.5, 1.5)
	end),
	UIElements.QuadButton(1, 1) .. {
		InitCommand = function(self)
			self:xy(-2,-8.5):zoomto(65, 20):halign(0):valign(0):diffuse(getMainColor("frames")):diffusealpha(hideMSD() and 0 or 0.2)
		end,
		MouseDownCommand = function(self, params)
			if params.event == "DeviceButton_left mouse button" then
				if rankingPage > 1 then
					rankingPage = rankingPage - 1
				else
					rankingPage = numrankingpages
				end
				BroadcastIfActive("UpdateRanking")
			end
		end,
		MouseOverCommand = function(self)
			local alpha = 0.7
			self:GetParent():GetChild("PrevP"):diffusealpha(alpha)
		end,
		MouseOutCommand = function(self)
			local alpha = 1
			self:GetParent():GetChild("PrevP"):diffusealpha(alpha)
		end,
	},
	LoadFont(hideMSD() and "Common Normal" or "Common Large") .. {
		Name = "PrevP",
		InitCommand = function(self)
			self:halign(0):zoom(hideMSD() and 0.36 or 0.3):diffuse(getMainColor("positive")):settext(hideMSD() and string.upper(translated_info["PrevPage"]) or translated_info["PrevPage"])
		end,
	},
}

for i = 1, scoresperpage do
	r[#r + 1] = rankingLabel(i)
end

for i = 1, scoresperpage do
	r[#r + 1] = recentLabel(i)
end

-- Technically the "overall" skillset is used for single value display during music select/eval and isn't factored in to the profile rating
-- Only the specific skillsets are, and so overall should be used to display the specific skillset breakdowns separately - mina
for i = 1, #ms.SkillSets do
	r[#r + 1] = rankingButton(i)
end

r[#r + 1] = recentButton()
r[#r + 1] = percentButton()
r[#r + 1] = bestButton()
for i = 1, scoresperpage do
	r[#r + 1] = bestLabel(i)
end

local function littlebits(i)
	local t = Def.ActorFrame {
		InitCommand = function(self)
			self:xy(frameX + capWideScale(28,45), frameY - 30)
		end,
		UpdateRankingMessageCommand = function(self)
			if rankingSkillset == 1 and update and not recentactive and not bestactive and not hideMSD() then
				self:visible(true)
			else
				self:visible(false)
			end
		end,
		LoadFont("Common Large") .. {
			InitCommand = function(self)
				self:y(txtDist * i):maxwidth(170 * 2):halign(0):zoom(0.575)
			end,
			SetCommand = function(self)
				self:settext(ms.SkillSetsTranslated[i] .. ":")
			end,
		},
		LoadFont("Common Large") .. {
			InitCommand = function(self)
				self:xy(210, txtDist * i):halign(0):zoom(0.575)
			end,
			SetCommand = function(self)
				local rating = 0
				if not showOnline then
					rating = profile:GetPlayerSkillsetRating(ms.SkillSets[i])
					self:settextf("%05.2f", rating)
					self:GetParent():x(frameX + capWideScale(28,45))
					self:x(210)
				else
					rating = DLMAN:GetSkillsetRating(ms.SkillSets[i])
					self:settextf("%05.2f (#%i)", rating, DLMAN:GetSkillsetRank(ms.SkillSets[i]))
					self:GetParent():x(frameX)
					self:x(capWideScale(184,198)):maxwidth(9999)
					if not IsUsingWideScreen() then self:maxwidth(270) end
				end
				self:diffuse(byMSD(rating))
			end,
			UpdateRankingMessageCommand = function(self)
				self:queuecommand("Set")
			end,
			PlayerRatingUpdatedMessageCommand = function(self)
				self:queuecommand("Set")
			end
		}
	}
	return t
end

for i = 2, #ms.SkillSets do
	r[#r + 1] = littlebits(i)
end

local user
local pass
local profilebuttons = Def.ActorFrame {
	InitCommand = function(self)
	end,
	BeginCommand = function(self)
		user = playerConfig:get_data(pn_to_profile_slot(PLAYER_1)).UserName
		local passToken = playerConfig:get_data(pn_to_profile_slot(PLAYER_1)).PasswordToken
		if passToken ~= "" and answer ~= "" then
			if not DLMAN:IsLoggedIn() then
				DLMAN:LoginWithToken(user, passToken)
			end
		else
			passToken = ""
			user = ""
		end
	end,
	UpdateRankingMessageCommand = function(self)
		if rankingSkillset == 1 and update and not recentactive and not bestactive then
			self:visible(true)
		else
			self:visible(false)
		end
	end,
	UIElements.TextToolTip(1, 1, "Common Large") .. {
		InitCommand = function(self)
			self:xy(frameX + frameWidth * 1/7, frameHeight + 04):halign(0.5):diffuse(getMainColor("positive")):zoom(0.3)
			self:settext(translated_info["Save"])
		end,
		MouseOverCommand = function(self)
			self:diffusealpha(hoverAlpha)
		end,
		MouseOutCommand = function(self)
			self:diffusealpha(1)
		end,
		MouseDownCommand = function(self, params)
			if params.event == "DeviceButton_left mouse button" and update and rankingSkillset == 1 and not recentactive and not bestactive then
				if PROFILEMAN:SaveProfile(PLAYER_1) then
					ms.ok(translated_info["Success"])
					STATSMAN:UpdatePlayerRating()
				else
					ms.ok(translated_info["Failure"])
				end
			end
		end
	},
	UIElements.TextToolTip(1, 1, "Common Large") .. {
		InitCommand = function(self)
			self:xy(frameX + frameWidth * 3/7, frameHeight + 04):halign(0.5):diffuse(getMainColor("positive")):zoom(0.3)
			self:settext(translated_info["AssetSettings"])
		end,
		MouseOverCommand = function(self)
			self:diffusealpha(hoverAlpha)
		end,
		MouseOutCommand = function(self)
			self:diffusealpha(1)
		end,
		MouseDownCommand = function(self, params)
			if params.event == "DeviceButton_left mouse button" and update and rankingSkillset == 1 and not recentactive and not bestactive then
				SCREENMAN:SetNewScreen("ScreenAssetSettings")
			end
		end,
	},
	UIElements.TextToolTip(1, 1, "Common Large") .. {
		InitCommand = function(self)
			self:xy(frameX + frameWidth * 1/7, frameHeight + 26):halign(0.5):diffuse(getMainColor("positive")):zoom(0.3)
			self:settext(translated_info["ValidateAll"])
		end,
		MouseOverCommand = function(self)
			self:diffusealpha(hoverAlpha)
		end,
		MouseOutCommand = function(self)
			self:diffusealpha(1)
		end,
		MouseDownCommand = function(self, params)
			if params.event == "DeviceButton_left mouse button" and update and rankingSkillset == 1 and not recentactive and not bestactive then
				profile:UnInvalidateAllScores()
				STATSMAN:UpdatePlayerRating()
			end
		end,
	},
	UIElements.TextToolTip(1, 1, "Common Large") .. {
		InitCommand = function(self)
			self:xy(frameX + frameWidth * 3/7, frameHeight + 26):diffuse(getMainColor("positive")):zoom(0.3)
			self:settext(translated_info["ForceRecalc"])
		end,
		MouseOverCommand = function(self)
			self:diffusealpha(hoverAlpha)
		end,
		MouseOutCommand = function(self)
			self:diffusealpha(1)
		end,
		MouseDownCommand = function(self, params)
			if params.event == "DeviceButton_left mouse button" and update and rankingSkillset == 1 and not recentactive and not bestactive  then
				ms.ok("Recalculating Scores... this might be slow and may or may not crash")
				profile:ForceRecalcScores()
				STATSMAN:UpdatePlayerRating()
			end
		end,
	},
	UIElements.TextToolTip(1, 1, "Common Large") .. {
		InitCommand = function(self)
			self:xy(frameX + frameWidth * 5.3/7, frameHeight + 26):diffuse(getMainColor("positive")):zoom(0.3)
			self:settext(translated_info["UploadAllScore"])
		end,
		MouseOverCommand = function(self)
			self:diffusealpha(hoverAlpha)
		end,
		MouseOutCommand = function(self)
			self:diffusealpha(1)
		end,
		MouseDownCommand = function(self, params)
			if params.event == "DeviceButton_left mouse button" and update and rankingSkillset == 1 and not recentactive and not bestactive  then
				if DLMAN:IsLoggedIn() then
					DLMAN:UploadAllScores()
				else
					ms.ok("You must be logged in...")
				end
			end
		end,
	},
}

t[#t + 1] = profilebuttons
t[#t + 1] = r
return t
