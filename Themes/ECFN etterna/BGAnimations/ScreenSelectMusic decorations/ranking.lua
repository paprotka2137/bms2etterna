-- 7k: the "Ranking" window (key 1, in place of the Scores tab). IR shows the
-- BMS 7k ranking site's board for the selected chart and logs in to the site,
-- LOCAL lists this profile's scores on it with the eval screen and replays.
local R = BMSRanking
local tab = 10
local frameX = 10
local frameY = 45
local frameWidth = capWideScale(360, 400)
local rowsShown = 15
local rowH = 17
local listY = frameY + 72

local onTab = false
local ck
local board
-- "ir" or "local", kept while the game runs
BMSRankingMode = BMSRankingMode or (R.loggedIn() and "ir" or "local")
local localRows = {}
local localPage = 0
local selected -- the local score the buttons act on
local netScreen = false
-- IR: the board row whose play is open over the list, and its details
-- from the site (nil while they load)
local opened
local detail

local white = color("#ffffff")
local gray = color("#9aa3b5")
local blue = color("#3f9fff")

local function currentKey()
	local steps = GAMESTATE:GetCurrentSteps()
	return steps and steps:GetChartKey() or nil
end

-- columns: right edge (or left edge for the name) of each, from the window's left
local col = {
	rank = 26,
	lamp = 32,
	name = 44,
	lampText = frameWidth - 196,
	lane = frameWidth - 152,
	ex = frameWidth - 106,
	rate = frameWidth - 46,
	bp = frameWidth - 10,
}

local t = Def.ActorFrame {
	Name = "BMSRanking",
	BeginCommand = function(self)
		self:visible(false):xy(-500, 0):diffusealpha(0):queuecommand("Set")
	end,
	OffCommand = function(self)
		self:bouncebegin(0.2):xy(-500, 0):diffusealpha(0)
		self:sleep(0.04):queuecommand("Invis")
	end,
	InvisCommand = function(self)
		self:visible(false)
	end,
	OnCommand = function(self)
		self:bouncebegin(0.2):xy(0, 0):diffusealpha(1)
	end,
	SetCommand = function(self)
		self:finishtweening()
		if getTabIndex() == tab then
			onTab = true
			self:visible(true):queuecommand("On")
			self:queuecommand("Load")
		else
			if onTab then
				self:queuecommand("Off")
			end
			onTab = false
		end
	end,
	TabChangedMessageCommand = function(self)
		self:queuecommand("Set")
	end,
	CurrentStepsChangedMessageCommand = function(self)
		if onTab then
			-- wait until the wheel stops before asking the site
			self:GetChild("Timer"):stoptweening():sleep(0.25):queuecommand("DelayedLoad")
		end
	end,
	LoadCommand = function(self, params)
		ck = currentKey()
		opened = nil
		detail = nil
		if BMSRankingMode == "ir" then
			board = R.chart(ck, params and params.force)
		else
			self:playcommand("LoadLocal")
		end
		self:playcommand("Show")
	end,
	-- every local score on the chart (any rate), best EX first
	LoadLocalCommand = function(self)
		localRows = {}
		localPage = 0
		selected = nil
		local steps = GAMESTATE:GetCurrentSteps()
		local rates = ck and SCOREMAN:GetScoresByKey(ck)
		if not steps or not rates then
			return
		end
		local notes = steps:GetRadarValues(PLAYER_1):GetValue("RadarCategory_Notes")
		local list = {}
		for _, hsl in pairs(rates) do
			for _, sc in ipairs(hsl:GetScores()) do
				list[#list + 1] = sc
			end
		end
		local tns = function(sc, x)
			return sc:GetTapNoteScore("TapNoteScore_" .. x)
		end
		for _, sc in ipairs(list) do
			local ex = tns(sc, "W1") * 2 + tns(sc, "W2")
			local rateText = notes > 0 and string.format("%.2f%%", ex / (2 * notes) * 100) or "-"
			-- O2Jam: the DMJam score in thousandths, like the site keeps it
			if isO2JamScore(sc) then
				local v = getO2JamScore(sc)
				ex = math.floor(v * 1000 + 0.5)
				rateText = string.format("%.3f %s", v, getO2JamGrade(v))
			end
			local label = sc:GetDate():sub(1, 16)
			if math.abs(sc:GetMusicRate() - 1) > 0.001 then
				label = label .. "  " .. getRateString(notShit.round(sc:GetMusicRate(), 3))
			end
			localRows[#localRows + 1] = {
				name = label,
				lamp = getBMSLampFromScore(sc),
				ex = ex,
				bp = getBMSMissCount(sc),
				lane = R.shortLane(R.laneOf(sc:GetModifiers())),
				laneOrder = R.laneOrderOf(sc),
				rateText = rateText,
				score = sc,
			}
		end
		table.sort(localRows, function(a, b)
			if a.ex ~= b.ex then
				return a.ex > b.ex
			end
			return a.score:GetDate() > b.score:GetDate()
		end)
		for i, r in ipairs(localRows) do
			r.rank = i
		end
		selected = localRows[1]
	end,
	BMSBoardLoadedMessageCommand = function(self, params)
		if onTab and params.chartkey == ck then
			board = R.cache[ck] and R.cache[ck].board
			self:playcommand("Show")
		end
	end,
	BMSScoreDetailLoadedMessageCommand = function(self, params)
		if onTab and opened and params.chartkey == ck and params.name == opened.name then
			detail = R.scoreDetail(ck, opened)
			self:playcommand("Show")
		end
	end,
	BMSScoreUploadedMessageCommand = function(self, params)
		R.forget(params.chartkey)
		if onTab then
			self:playcommand("Load")
		end
	end,
	BMSLoginChangedMessageCommand = function(self)
		R.forget()
		if onTab then
			self:playcommand("Load")
		end
	end,
}

-- delays without stopping the window's slide
t[#t + 1] = Def.Actor {
	Name = "Timer",
	DelayedLoadCommand = function(self)
		if onTab then
			self:GetParent():playcommand("Load")
		end
	end,
	BMSLoginStep2Command = function(self)
		if R.step2 then
			local f = R.step2
			R.step2 = nil
			f()
		end
	end,
}

local function text(x, y, zoom, align, init)
	return LoadFont("Common Normal") .. {
		InitCommand = function(self)
			self:xy(frameX + x, y):zoom(zoom):halign(align):diffuse(white)
			self:shadowlength(1):shadowcolor(color("0,0,0,0.8"))
			if init then
				init(self)
			end
		end,
	}
end

-- login line with a button on the right
t[#t + 1] = text(8, frameY + 22, 0.38, 0) .. {
	ShowCommand = function(self)
		if not R.available() then
			self:settext("This build of the game has no ranking support"):diffuse(gray)
		elseif R.loggedIn() then
			self:settext("Ranking: " .. R.name()):diffuse(white)
		else
			self:settext("Ranking: not logged in, your plays are not sent"):diffuse(gray)
		end
		self:maxwidth((frameWidth - 110) / 0.38)
	end,
}
t[#t + 1] = UIElements.QuadButton(1, 1) .. {
	InitCommand = function(self)
		self:xy(frameX + frameWidth - 8, frameY + 22):halign(1):zoomto(80, 16)
		self:diffuse(blue):diffusealpha(0.35)
	end,
	ShowCommand = function(self)
		self:visible(R.available())
	end,
	MouseOverCommand = function(self)
		self:diffusealpha(0.6)
	end,
	MouseOutCommand = function(self)
		self:diffusealpha(0.35)
	end,
	MouseDownCommand = function(self, params)
		if params.event ~= "DeviceButton_left mouse button" or not onTab then
			return
		end
		if R.loggedIn() then
			R.logout()
			ms.ok("Ranking: logged out")
		else
			R.askLogin(self:GetParent():GetChild("Timer"))
		end
	end,
}
t[#t + 1] = text(frameWidth - 48, frameY + 22, 0.36, 0.5) .. {
	ShowCommand = function(self)
		self:visible(R.available()):settext(R.loggedIn() and "LOG OUT" or "LOG IN")
	end,
}

-- IR / LOCAL switch
local function modeButton(x, label, mode)
	return Def.ActorFrame {
		UIElements.QuadButton(1, 1) .. {
			InitCommand = function(self)
				self:xy(frameX + x, frameY + 42):halign(0):zoomto(44, 15)
			end,
			ShowCommand = function(self)
				local on = BMSRankingMode == mode
				self:diffuse(on and blue or white):diffusealpha(on and 0.45 or 0.08)
			end,
			MouseDownCommand = function(self, params)
				if params.event == "DeviceButton_left mouse button" and onTab and BMSRankingMode ~= mode then
					BMSRankingMode = mode
					self:GetParent():GetParent():playcommand("Load")
				end
			end,
		},
		text(x + 22, frameY + 42, 0.32, 0.5, function(self)
			self:settext(label)
		end),
	}
end
t[#t + 1] = modeButton(8, "IR", "ir")
t[#t + 1] = modeButton(56, "LOCAL", "local")

-- what the board shows: players, loading, errors
t[#t + 1] = text(110, frameY + 42, 0.34, 0) .. {
	ShowCommand = function(self)
		self:diffuse(gray):maxwidth((frameWidth - 118) / 0.34)
		if BMSRankingMode == "local" then
			if not ck then
				self:settext("No chart selected")
			elseif #localRows == 0 then
				self:settext("No local scores on this chart")
			else
				self:settext(string.format("%d local score%s, click one for the buttons below",
					#localRows, #localRows == 1 and "" or "s"))
			end
		elseif not ck then
			self:settext("No chart selected")
		elseif not board then
			self:settext("Loading...")
		elseif board.err then
			self:settext(board.err):diffuse(color("#ff7777"))
		elseif #board.rows == 0 then
			self:settext("No scores on this chart yet")
		else
			local s = string.format("%d player%s", board.players, board.players == 1 and "" or "s")
			if board.me then
				s = s .. string.format("   You: #%d", board.me.rank)
			elseif R.loggedIn() then
				s = s .. "   You: not played yet"
			end
			if board.notes <= 0 and R.chartNotes() <= 0 then
				s = s .. "   (rate shows once someone clears it)"
			else
				s = s .. "   click a player to see the play"
			end
			self:settext(s)
		end
	end,
}

-- column names
local heads = {
	{"#", col.rank, 1}, {"PLAYER", col.name, 0}, {"LAMP", col.lampText, 0.5},
	{"LANE", col.lane, 0.5}, {"EX", col.ex, 1}, {"RATE", col.rate, 1}, {"BP", col.bp, 1},
}
for _, h in ipairs(heads) do
	t[#t + 1] = text(h[2], listY - 14, 0.3, h[3], function(self)
		self:settext(h[1]):diffuse(gray)
	end) .. {
		ShowCommand = function(self)
			if h[1] == "PLAYER" or h[1] == "DATE" then
				self:settext(BMSRankingMode == "local" and "DATE" or "PLAYER")
			end
		end,
	}
end

-- the rows; the last one shows you when you are below the shown places
local function rowFor(i)
	if BMSRankingMode == "local" then
		return localRows[localPage * rowsShown + i]
	end
	if not board or board.err then
		return nil
	end
	if i == rowsShown and board.me and board.me.rank > rowsShown then
		return board.me
	end
	return board.rows[i]
end

for i = 1, rowsShown do
	local y = listY + (i - 1) * rowH
	local r = Def.ActorFrame {
		ShowCommand = function(self)
			local row = rowFor(i)
			self:visible(row ~= nil)
			if row then
				self:playcommand("Row", {row = row})
			end
		end,
	}
	-- your own row (IR) or the picked score (LOCAL) is lit; clicking a
	-- local score picks it
	r[#r + 1] = UIElements.QuadButton(1, 1) .. {
		Name = "RowButton",
		InitCommand = function(self)
			self:xy(frameX + 4, y):halign(0):zoomto(frameWidth - 8, rowH - 2)
		end,
		RowCommand = function(self, p)
			local mine
			if BMSRankingMode == "local" then
				mine = selected == p.row
			else
				mine = board and board.me == p.row
			end
			self.baseAlpha = mine and 0.25 or (i % 2 == 0 and 0.04 or 0)
			self:diffuse(mine and blue or color("#ffffff")):diffusealpha(self.baseAlpha)
		end,
		MouseOverCommand = function(self)
			if onTab and not opened and rowFor(i) then
				self:diffusealpha(math.max(self.baseAlpha or 0, 0.14))
			end
		end,
		MouseOutCommand = function(self)
			self:diffusealpha(self.baseAlpha or 0)
		end,
		MouseDownCommand = function(self, params)
			if params.event ~= "DeviceButton_left mouse button" or not onTab or opened then
				return
			end
			local row = rowFor(i)
			if not row then
				return
			end
			if BMSRankingMode == "local" then
				selected = row
			else
				-- a player's play on the site: open it over the list
				opened = row
				detail = R.scoreDetail(ck, row)
			end
			self:diffusealpha(self.baseAlpha or 0)
			self:GetParent():GetParent():playcommand("Show")
		end,
	}
	r[#r + 1] = text(col.rank, y, 0.34, 1) .. {
		RowCommand = function(self, p)
			self:settext(p.row.rank)
		end,
	}
	r[#r + 1] = Def.Quad {
		InitCommand = function(self)
			self:xy(frameX + col.lamp, y):zoomto(5, rowH - 5)
		end,
		RowCommand = function(self, p)
			self:diffuse(getBMSLampInfo(p.row.lamp, 2))
		end,
	}
	r[#r + 1] = text(col.name, y, 0.36, 0, function(self)
		self:maxwidth((col.lampText - col.name - 30) / 0.36)
	end) .. {
		RowCommand = function(self, p)
			self:settext(p.row.name)
		end,
	}
	r[#r + 1] = text(col.lampText, y, 0.32, 0.5) .. {
		RowCommand = function(self, p)
			self:settext(getBMSLampInfo(p.row.lamp, 1)):diffuse(getBMSLampInfo(p.row.lamp, 2))
		end,
	}
	r[#r + 1] = text(col.lane, y, 0.3, 0.5, function(self)
		self:maxwidth(40 / 0.3)
	end) .. {
		RowCommand = function(self, p)
			self:settext(p.row.lane or "-")
		end,
	}
	-- RANDOM plays: hovering the lane shows the lane order it was played on
	-- (clicks and the row highlight still go to the row under it)
	r[#r + 1] = UIElements.QuadButton(2, 1) .. {
		InitCommand = function(self)
			self:xy(frameX + col.lane, y):zoomto(44, rowH - 2):diffusealpha(0)
		end,
		RowCommand = function(self, p)
			self.order = p.row.laneOrder
			self:visible(self.order ~= nil)
		end,
		MouseOverCommand = function(self)
			self:GetParent():GetChild("RowButton"):playcommand("MouseOver")
			if onTab and not opened and self.order and rowFor(i) then
				TOOLTIP:SetText("LANE ORDER  " .. self.order .. "  (click to play it)")
				TOOLTIP:Show()
				self.tip = true
			end
		end,
		MouseOutCommand = function(self)
			self:GetParent():GetChild("RowButton"):playcommand("MouseOut")
			if self.tip then
				TOOLTIP:Hide()
				self.tip = false
			end
		end,
		-- clicking the lane takes that lane order as your own option (custom
		-- lanes) instead of opening the row
		MouseDownCommand = function(self, params)
			if self.tip then
				TOOLTIP:Hide()
				self.tip = false
			end
			if params.event ~= "DeviceButton_left mouse button" or not onTab or opened then
				return
			end
			if self.order and setBMSLanes and setBMSLanes(self.order) then
				SCREENMAN:SystemMessage(THEME:GetString("GeneralInfo", "ProfileArrange") .. ": " .. getBMSArrangeText())
			end
		end,
	}
	r[#r + 1] = text(col.ex, y, 0.36, 1) .. {
		RowCommand = function(self, p)
			-- O2Jam: the score is in the RATE column
			self:settext(isO2JamPlay() and "" or p.row.ex)
		end,
	}
	r[#r + 1] = text(col.rate, y, 0.34, 1) .. {
		RowCommand = function(self, p)
			self:settext(p.row.rateText or R.rate(board, p.row, R.chartNotes()))
		end,
	}
	r[#r + 1] = text(col.bp, y, 0.34, 1) .. {
		RowCommand = function(self, p)
			self:settext(p.row.bp)
		end,
	}
	t[#t + 1] = r
end

-- IR: one player's play over the list, like the site's score window and
-- the result screen: lamp, EX, rate, judgments, the gauge over the song,
-- lane, judge and modifiers. The judgments come with the board, the rest
-- from the site once it answers.
local panelY = listY - 20
local panelH = rowsShown * rowH + 14
local graphX, graphY = 8, panelY + 120
local graphW, graphH = frameWidth - 16, 74
local panelBG = color("#0b0f18")
local gaugeStyle = {
	EASY = {bg = {color("#004444cc"), color("#440000cc")}, line = {color("#00ffff"), color("#ff0000")}, border = 0.8},
	GROOVE = {bg = {color("#004400cc"), color("#440000cc")}, line = {color("#00ff00"), color("#ff0000")}, border = 0.8},
	HARD = {bg = {color("#440000cc")}, line = {color("#ff0000")}},
	EXHARD = {bg = {color("#444400cc")}, line = {color("#ffff00")}},
	DEATH = {bg = {color("#444444cc")}, line = {color("#cccccc")}},
}
gaugeStyle["O2JAM HARD"] = gaugeStyle.HARD
gaugeStyle["CLASS"] = gaugeStyle.HARD
gaugeStyle["EX CLASS"] = gaugeStyle.HARD
gaugeStyle["EX HARD CLASS"] = gaugeStyle.EXHARD

local function openGauge()
	return (detail and not detail.err and detail.gauge) or (opened and opened.gauge) or ""
end
local function openLamp()
	if detail and not detail.err and tonumber(detail.lamp) then
		return tonumber(detail.lamp)
	end
	return opened and opened.lamp or 6
end
local function playDate(d)
	d = tostring(d or ""):gsub("T", " ")
	return d:sub(1, 16)
end
-- the copy of the play on this computer (your own plays), for the eval
-- screen and the replay
local function openLocal()
	if netScreen or not opened or not detail or detail.err or not detail.score_key then
		return nil
	end
	return R.localScore(ck, detail.score_key)
end

local p = Def.ActorFrame {
	Name = "Play",
	InitCommand = function(self)
		self:visible(false)
	end,
	ShowCommand = function(self)
		self:visible(BMSRankingMode == "ir" and opened ~= nil)
		if self:GetVisible() then
			self:playcommand("Panel")
		end
	end,
}
-- background; it takes the clicks so the rows under it don't
p[#p + 1] = UIElements.QuadButton(1, 1) .. {
	InitCommand = function(self)
		self:xy(frameX + 2, panelY):halign(0):valign(0):zoomto(frameWidth - 4, panelH)
		self:diffuse(panelBG):diffusealpha(0.97)
	end,
}
p[#p + 1] = Def.Quad {
	InitCommand = function(self)
		self:xy(frameX + 2, panelY):halign(0):valign(0):zoomto(frameWidth - 4, 2):diffuse(blue)
	end,
}
-- "#3  name"
p[#p + 1] = text(8, panelY + 12, 0.46, 0, function(self)
	self:maxwidth((frameWidth - 90) / 0.46)
end) .. {
	PanelCommand = function(self)
		self:settext(string.format("#%d  %s", opened.rank, opened.name))
		self:diffuse(board and board.me == opened and blue or white)
	end,
}
-- close
p[#p + 1] = UIElements.TextToolTip(1, 1, "Common Normal") .. {
	InitCommand = function(self)
		self:xy(frameX + frameWidth - 8, panelY + 12):halign(1):zoom(0.34):settext("CLOSE  X"):diffuse(gray)
	end,
	MouseOverCommand = function(self)
		self:diffuse(white)
	end,
	MouseOutCommand = function(self)
		self:diffuse(gray)
	end,
	MouseDownCommand = function(self, params)
		if params.event == "DeviceButton_left mouse button" and onTab and opened then
			opened = nil
			detail = nil
			self:diffuse(gray)
			self:GetParent():GetParent():playcommand("Show")
		end
	end,
}
-- lamp · gauge · lane · date
p[#p + 1] = text(8, panelY + 29, 0.34, 0) .. {
	PanelCommand = function(self)
		local lamp = openLamp()
		self:settext(getBMSLampInfo(lamp, 0) or getBMSLampInfo(lamp, 1)):diffuse(getBMSLampInfo(lamp, 2))
	end,
}
p[#p + 1] = text(frameWidth - 8, panelY + 29, 0.3, 1) .. {
	PanelCommand = function(self)
		local lane = (detail and not detail.err and detail.lanes) or opened.lane or "-"
		self:settext(string.format("%s GAUGE   LANE %s   %s", openGauge() ~= "" and openGauge() or "?", lane, playDate(opened.date)))
		self:diffuse(gray):maxwidth((frameWidth - 150) / 0.3)
	end,
}
-- EX, rate and DJ level (O2Jam: the score and its grade)
p[#p + 1] = text(8, panelY + 50, 0.55, 0) .. {
	PanelCommand = function(self)
		if isO2JamPlay() then
			self:settext(R.rate(board or {}, opened, R.chartNotes()) .. "  O2Jam score")
			return
		end
		local n = R.chartNotes()
		if n <= 0 and board then
			n = board.notes or 0
		end
		local s = string.format("EX %d", opened.ex)
		if n > 0 then
			local r = opened.ex / (2 * n)
			s = s .. string.format("    %.2f%%    %s", r * 100, R.djLevel(r))
		end
		self:settext(s)
	end,
}
-- judgments
local judgeCols = {
	{"PGREAT", "COOL", "pg", color("#9ff3ff")},
	{"GREAT", nil, "gr", color("#ffe066")},
	{"GOOD", "GOOD", "gd", color("#7dff7d")},
	{"BAD", "BAD", "bd", color("#ff9a3c")},
	{"POOR", "MISS", "pr", color("#ff5c5c")},
	{"COMBO", "COMBO", "combo", white},
	{"BP", nil, "bp", gray},
}
local colW = (frameWidth - 16) / #judgeCols
for k, jc in ipairs(judgeCols) do
	local cx = 8 + colW * (k - 0.5)
	p[#p + 1] = text(cx, panelY + 74, 0.27, 0.5) .. {
		PanelCommand = function(self)
			local label = isO2JamPlay() and jc[2] or jc[1]
			self:visible(label ~= nil):settext(label or ""):diffuse(gray)
		end,
	}
	p[#p + 1] = text(cx, panelY + 90, 0.46, 0.5) .. {
		PanelCommand = function(self)
			local label = isO2JamPlay() and jc[2] or jc[1]
			self:visible(label ~= nil):settext(tostring(opened[jc[3]] or 0)):diffuse(jc[4])
		end,
	}
end
-- the gauge over the song
p[#p + 1] = text(8, panelY + 110, 0.28, 0) .. {
	PanelCommand = function(self)
		self:settext("GAUGE " .. openGauge()):diffuse(gray)
	end,
}
p[#p + 1] = text(frameWidth - 8, panelY + 110, 0.28, 1) .. {
	PanelCommand = function(self)
		local g = detail and not detail.err and detail.graph
		self:settext(g and string.format("ends at %d%%", g[#g]) or ""):diffuse(gray)
	end,
}
p[#p + 1] = Def.ActorMultiVertex {
	InitCommand = function(self)
		self:xy(frameX + graphX, graphY)
	end,
	PanelCommand = function(self)
		local verts = {}
		local function quad(x1, y1, x2, y2, c)
			verts[#verts + 1] = {{x1, y1, 0}, c}
			verts[#verts + 1] = {{x2, y1, 0}, c}
			verts[#verts + 1] = {{x2, y2, 0}, c}
			verts[#verts + 1] = {{x1, y2, 0}, c}
		end
		local st = gaugeStyle[string.upper(openGauge())] or gaugeStyle.GROOVE
		local border = st.border or 0
		local by = graphH * (1 - border)
		quad(0, 0, graphW, graphH, color("#00000099"))
		local g = detail and not detail.err and detail.graph
		if g then
			quad(0, by, graphW, graphH, st.bg[1])
			if border > 0 then
				quad(0, 0, graphW, by, st.bg[2])
			end
		end
		for _, gl in ipairs({0.2, 0.4, 0.6, 0.8}) do
			local y = graphH * (1 - gl)
			quad(0, y, graphW, y + 1, color("#ffffff14"))
		end
		if g then
			if border > 0 then
				quad(0, by - 1, graphW, by + 1, color("#ff000088"))
			end
			local function lifeY(i)
				local l = math.max(0, math.min(1, (tonumber(g[i]) or 0) / 100))
				return math.max(1, math.min(graphH - 1, graphH * (1 - l))), l
			end
			local n = #g
			local prev
			for x = 0, graphW - 1 do
				local i = math.floor(x / math.max(1, graphW - 1) * (n - 1) + 0.5) + 1
				local y, l = lifeY(i)
				local c = (border > 0 and l >= border) and st.line[2] or st.line[1]
				prev = prev or y
				quad(x, math.min(y, prev) - 1, x + 1, math.max(y, prev) + 1, c)
				prev = y
			end
		end
		self:SetVertices(verts)
		self:SetDrawState {Mode = "DrawMode_Quads", First = 1, Num = #verts}
	end,
}
-- what the graph box shows while there is no graph
p[#p + 1] = text(graphX + graphW / 2, graphY + graphH / 2, 0.32, 0.5, function(self)
	self:maxwidth((graphW - 16) / 0.32)
end) .. {
	PanelCommand = function(self)
		local s = ""
		if not detail then
			s = "Loading the play from the site..."
		elseif detail.err then
			s = "Gauge graph not available: " .. detail.err
		elseif not detail.graph then
			s = "No gauge graph for this play (sent by an older game version or the upload script)"
		end
		self:settext(s):diffuse(detail and detail.err and color("#ff7777") or gray)
	end,
}
-- judge and modifiers
p[#p + 1] = text(8, graphY + graphH + 12, 0.3, 0, function(self)
	self:maxwidth((frameWidth - 16) / 0.3)
end) .. {
	PanelCommand = function(self)
		if detail and not detail.err then
			local judge = (detail.judge and detail.judge ~= "") and detail.judge or "EASY"
			self:settext("JUDGE " .. judge .. "     PLAYED " .. playDate(detail.played_at or opened.date))
		else
			self:settext("PLAYED " .. playDate(opened.date))
		end
		self:diffuse(gray)
	end,
}
p[#p + 1] = text(8, graphY + graphH + 26, 0.28, 0, function(self)
	self:maxwidth((frameWidth - 16) / 0.28)
end) .. {
	PanelCommand = function(self)
		local mods = detail and not detail.err and detail.modifiers
		self:visible(mods ~= nil and mods ~= false):settext(mods and ("MODIFIERS " .. tostring(mods)) or ""):diffuse(gray)
	end,
}
-- your own play: the real eval screen and the replay from this computer
local function playButton(x, label, act)
	return UIElements.TextToolTip(1, 1, "Common Normal") .. {
		InitCommand = function(self)
			self:xy(frameX + x, graphY + graphH + 46):halign(0):zoom(0.34):settext(label)
		end,
		PanelCommand = function(self)
			local sc = openLocal()
			self:visible(sc ~= nil and sc:HasReplayData()):diffuse(white)
		end,
		MouseOverCommand = function(self)
			self:diffuse(blue)
		end,
		MouseOutCommand = function(self)
			self:diffuse(white)
		end,
		MouseDownCommand = function(self, params)
			if params.event == "DeviceButton_left mouse button" and onTab and self:GetVisible() then
				local sc = openLocal()
				if sc then
					act(sc)
				end
			end
		end,
	}
end
p[#p + 1] = playButton(8, "VIEW EVAL", function(sc)
	SCREENMAN:GetTopScreen():ShowEvalScreenForScore(sc)
end)
p[#p + 1] = playButton(80, "WATCH REPLAY", function(sc)
	SCREENMAN:GetTopScreen():PlayReplay(sc)
end)
p[#p + 1] = text(frameWidth - 8, graphY + graphH + 46, 0.28, 1) .. {
	PanelCommand = function(self)
		local s = ""
		if detail and not detail.err and detail.has_replay and detail.has_replay ~= 0 and not openLocal() then
			s = "replay is on the site"
		end
		self:settext(s):diffuse(gray)
	end,
}
t[#t + 1] = p

-- LOCAL: pages and the picked score's eval screen and replay
local bottomY = listY + rowsShown * rowH + 2
local function textButton(x, align, label, enabled, act)
	return UIElements.TextToolTip(1, 1, "Common Normal") .. {
		InitCommand = function(self)
			self:xy(frameX + x, bottomY):halign(align):zoom(0.32):settext(label)
		end,
		ShowCommand = function(self)
			self:visible(BMSRankingMode == "local" and not netScreen)
			self:diffuse(enabled() and white or color("#555a66"))
		end,
		MouseOverCommand = function(self)
			if enabled() then
				self:diffuse(blue)
			end
		end,
		MouseOutCommand = function(self)
			self:diffuse(enabled() and white or color("#555a66"))
		end,
		MouseDownCommand = function(self, params)
			if params.event == "DeviceButton_left mouse button" and onTab and self:GetVisible() and enabled() then
				act(self)
			end
		end,
	}
end
local function hasReplay()
	return selected ~= nil and selected.score:HasReplayData()
end
t[#t + 1] = textButton(8, 0, "< PREV", function()
	return localPage > 0
end, function(self)
	localPage = localPage - 1
	self:GetParent():playcommand("Show")
end)
t[#t + 1] = textButton(50, 0, "NEXT >", function()
	return (localPage + 1) * rowsShown < #localRows
end, function(self)
	localPage = localPage + 1
	self:GetParent():playcommand("Show")
end)
t[#t + 1] = textButton(110, 0, "VIEW EVAL", hasReplay, function()
	SCREENMAN:GetTopScreen():ShowEvalScreenForScore(selected.score)
end)
t[#t + 1] = textButton(175, 0, "WATCH REPLAY", hasReplay, function()
	SCREENMAN:GetTopScreen():PlayReplay(selected.score)
end)
t[#t + 1] = Def.Actor {
	BeginCommand = function()
		netScreen = SCREENMAN:GetTopScreen():GetName() == "ScreenNetSelectMusic"
	end,
}

-- refresh by hand
t[#t + 1] = UIElements.TextToolTip(1, 1, "Common Normal") .. {
	InitCommand = function(self)
		self:xy(frameX + frameWidth - 8, listY + rowsShown * rowH + 2):halign(1):zoom(0.32)
		self:settext("REFRESH"):diffuse(gray)
	end,
	MouseOverCommand = function(self)
		self:diffuse(white)
	end,
	MouseOutCommand = function(self)
		self:diffuse(gray)
	end,
	MouseDownCommand = function(self, params)
		if params.event == "DeviceButton_left mouse button" and onTab and ck then
			R.forget(ck)
			self:GetParent():playcommand("Load", {force = true})
		end
	end,
}

return t
