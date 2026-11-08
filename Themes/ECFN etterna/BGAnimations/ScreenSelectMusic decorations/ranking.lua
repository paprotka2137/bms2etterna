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
				rateText = notes > 0 and string.format("%.2f%%", ex / (2 * notes) * 100) or "-",
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
			self:diffuse(mine and blue or color("#ffffff")):diffusealpha(mine and 0.25 or (i % 2 == 0 and 0.04 or 0))
		end,
		MouseDownCommand = function(self, params)
			if params.event == "DeviceButton_left mouse button" and onTab and BMSRankingMode == "local" then
				local row = rowFor(i)
				if row then
					selected = row
					self:GetParent():GetParent():playcommand("Show")
				end
			end
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
	r[#r + 1] = text(col.ex, y, 0.36, 1) .. {
		RowCommand = function(self, p)
			self:settext(p.row.ex)
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
