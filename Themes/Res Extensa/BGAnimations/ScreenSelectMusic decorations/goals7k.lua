-- 7k: the "Goals" window (key 3) in the Dan window's look (Scripts/
-- ECFNWindow.lua): the profile's score goals on 7k charts, open ones first.
-- ADD sets a goal on the selected chart, clicking a row moves the wheel to
-- its song, the X on a row deletes that goal.
local W = ECFNWindow
local tab = 6
local listY = W.top + 62
local rows = 17
local page = 0
local goals = {}

local function gather()
	goals = {}
	local profile = PROFILEMAN:GetProfile(PLAYER_1)
	profile:SetFromAll()
	for _, g in ipairs(profile:GetGoalTable() or {}) do
		local steps = SONGMAN:GetStepsByChartKey(g:GetChartKey())
		if steps and steps:GetStepsType() == "StepsType_Kb7_Single" then
			local song = SONGMAN:GetSongByChartKey(g:GetChartKey())
			local level, levelName = getBMSLevel(song, steps)
			local pb = g:GetPBUpTo()
			goals[#goals + 1] = {
				goal = g, song = song, steps = steps, levelName = levelName,
				-- goals are reached on the wife percent, so that is what BEST shows
				done = g:IsAchieved(), best = pb and pb:GetWifeScore() or nil,
			}
		end
	end
	table.sort(goals, function(a, b)
		if a.done ~= b.done then return not a.done end
		return a.goal:WhenAssigned() > b.goal:WhenAssigned()
	end)
end

local function entry(i)
	return goals[page * rows + i]
end

local function pages()
	return math.max(1, math.ceil(#goals / rows))
end

local t = W.frame(tab, "BMSGoals", function()
	gather()
	page = 0
end)
t.BMSGoalsRefreshMessageCommand = function(self)
	if self.open then
		gather()
		page = math.min(page, pages() - 1)
		self:playcommand("Show")
	end
end
local function refresh()
	MESSAGEMAN:Broadcast("BMSGoalsRefresh")
end

t[#t + 1] = W.text(8, W.top + 12, 0.42, 0, function(self)
	self:settext("GOALS")
end)
t[#t + 1] = W.text(8, W.top + 30, 0.34, 0) .. {
	ShowCommand = function(self)
		local open = 0
		for _, g in ipairs(goals) do
			if not g.done then
				open = open + 1
			end
		end
		self:settextf("%d open, %d reached", open, #goals - open):diffuse(W.gray)
	end,
}
t[#t + 1] = W.button("ADD THIS CHART", W.width - 58, W.top + 12, 100, function()
	SCREENMAN:GetTopScreen():GoalFromCurrentChart()
	refresh()
end, function()
	return GAMESTATE:GetCurrentSteps() ~= nil
end)

local col = {lv = 10, title = 46, rateX = W.width - 150, target = W.width - 104, best = W.width - 58, del = W.width - 16}
local function head(x, align, label)
	t[#t + 1] = W.text(x, listY - 14, 0.3, align, function(self)
		self:settext(label):diffuse(W.gray)
	end)
end
head(col.lv, 0, "LV")
head(col.title, 0, "TITLE")
head(col.rateX, 0.5, "RATE")
head(col.target, 1, "GOAL")
head(col.best, 1, "BEST")

for i = 1, rows do
	local y = listY + (i - 1) * W.rowH
	t[#t + 1] = Def.ActorFrame {
		ShowCommand = function(self)
			self:visible(entry(i) ~= nil)
		end,
		W.rowBand(i, y, nil, function(i)
			local e = entry(i)
			if e then
				W.pickSong(e.song)
			end
		end),
		W.text(col.lv, y, 0.32, 0) .. {
			ShowCommand = function(self)
				local e = entry(i)
				self:settext(e and e.levelName or ""):diffuse(color("#d080ff"))
			end,
		},
		W.text(col.title, y, 0.32, 0, function(self)
			self:maxwidth((col.rateX - col.title - 24) / 0.32)
		end) .. {
			ShowCommand = function(self)
				local e = entry(i)
				self:settext(e and e.song and e.song:GetDisplayMainTitle() or "")
				self:diffuse(e and e.done and W.green or W.white)
			end,
		},
		W.text(col.rateX, y, 0.3, 0.5) .. {
			ShowCommand = function(self)
				local e = entry(i)
				self:settext(e and getRateString(notShit.round(e.goal:GetRate(), 3)) or "")
			end,
		},
		W.text(col.target, y, 0.32, 1) .. {
			ShowCommand = function(self)
				local e = entry(i)
				self:settext(e and string.format("%.2f%%", e.goal:GetPercent() * 100) or "")
			end,
		},
		W.text(col.best, y, 0.32, 1) .. {
			ShowCommand = function(self)
				local e = entry(i)
				if e and e.best then
					self:settext(string.format("%.2f%%", e.best * 100)):diffuse(e.done and W.green or W.white)
				else
					self:settext("-"):diffuse(W.gray)
				end
			end,
		},
		-- delete the goal
		UIElements.TextToolTip(1, 1, "Common Normal") .. {
			InitCommand = function(self)
				self:xy(W.x + col.del, y):zoom(0.34):settext("X"):diffuse(W.red)
			end,
			MouseOverCommand = function(self)
				self:diffusealpha(0.6)
			end,
			MouseOutCommand = function(self)
				self:diffusealpha(1)
			end,
			MouseDownCommand = function(self, params)
				local e = entry(i)
				if e and params.event == "DeviceButton_left mouse button" then
					e.goal:Delete()
					refresh()
				end
			end,
		},
	}
end

local pageY = listY + rows * W.rowH + 8
t[#t + 1] = W.button("PREV", 34, pageY, 56, function()
	page = (page - 1) % pages()
	refresh()
end)
t[#t + 1] = W.button("NEXT", W.width - 34, pageY, 56, function()
	page = (page + 1) % pages()
	refresh()
end)
t[#t + 1] = W.text(W.width / 2, pageY, 0.3, 0.5) .. {
	ShowCommand = function(self)
		if #goals == 0 then
			self:settext("No goals yet"):diffuse(W.gray)
		else
			self:settextf("%d-%d of %d", page * rows + 1, math.min(#goals, (page + 1) * rows), #goals):diffuse(W.gray)
		end
	end,
}

return t
