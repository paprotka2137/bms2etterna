-- 7k: the "Rivals" window (key 7) in the Dan window's look (Scripts/
-- ECFNWindow.lua), the game's side of the ranking site's rivals (#/rivals
-- and a profile's Rivals tab). It uses the same rivals as the site and the
-- chat's /rival, through POST /api/game/chat/rival:
--   PASSED YOU  charts a rival passed your best EX on in the last 30 days
--               (op=beaten, the site's "Passed you" list), newest first
--   RIVALS      your rivals with how many charts each one is ahead of you /
--               behind you on (op=list); a click opens VS with that rival
--   VS          one rival chart by chart (op=vs): AHEAD lists the charts
--               they beat you on, BEHIND the ones you beat them on, the
--               smallest gap first, so the top rows are the easiest to take
-- "+ ADD" adds a rival by nickname, VS has REMOVE / ADD for the one shown.
-- Clicking a chart row moves the wheel to its song (gray = not on this
-- computer). Needs the in-game login of the ranking site (Ranking window).
local W = ECFNWindow
local tab = 13
local listY = W.top + 62
local rows = 17
local page = 0

-- kept in a global so the data and the view stay when the screen is reloaded
BMSRivals = BMSRivals or {mode = "passed", vsSide = "ahead"}
local S = BMSRivals
local RELOAD = 30 -- seconds before opening the window asks the site again

---------------------------------------------------------------------------
-- talking to the site
---------------------------------------------------------------------------
local function split(s, sep)
	local out = {}
	local start = 1
	while true do
		local i = s:find(sep, start, true)
		if not i then
			out[#out + 1] = s:sub(start)
			return out
		end
		out[#out + 1] = s:sub(start, i - 1)
		start = i + #sep
	end
end

local function parse(body)
	local lines = {}
	for _, l in ipairs(split((body or ""):gsub("\r", ""), "\n")) do
		if l ~= "" then
			lines[#lines + 1] = split(l, "\t")
		end
	end
	return lines
end

local function errorOf(status, lines)
	if status == 0 then
		return "No connection to the ranking site"
	end
	local msg = lines[1] and lines[1][1] == "ERR" and lines[1][2]
	if msg == "op must be add or remove" then
		-- a site from before this window: the worker needs deploying
		return "The ranking site does not have this yet (deploy the site's worker)"
	end
	return msg or ("Site error " .. tostring(status))
end

local function loggedIn()
	return BMSRanking ~= nil and BMSRanking.loggedIn ~= nil and BMSRanking.loggedIn()
end

local function refresh()
	MESSAGEMAN:Broadcast("BMSRivalsRefresh")
end

-- the last error of each request (list, beaten, vs, add, remove)
S.errs = S.errs or {}
local function request(params, done)
	DLMAN:BMSRequest("POST", "/api/game/chat/rival", params, function(status, body)
		local lines = parse(body)
		if status ~= 200 or not lines[1] or lines[1][1] ~= "OK" then
			S.errs[params.op] = errorOf(status, lines)
		else
			S.errs[params.op] = nil
			done(lines)
		end
		refresh()
	end)
end

local function loadList()
	request({op = "list", name = ""}, function(lines)
		local list = {}
		for i = 2, #lines do
			local f = lines[i]
			list[#list + 1] = {name = f[1] or "?", ahead = tonumber(f[2]) or 0, behind = tonumber(f[3]) or 0}
		end
		S.list = list
		S.listTime = GetTimeSinceStart()
		-- the chat's player menu knows who is a rival too
		if BMSChat and BMSChat.rivals then
			BMSChat.rivals = {}
			for _, r in ipairs(list) do
				BMSChat.rivals[string.lower(r.name)] = r.name
			end
		end
	end)
end

local function loadPassed()
	request({op = "beaten", name = ""}, function(lines)
		local out = {}
		for i = 2, #lines do
			local f = lines[i]
			if f[1] == "B" then
				out[#out + 1] = {
					rival = f[2] or "?", ck = f[3] or "", title = f[4] or "", lv = f[5] or "", tbl = f[6] or "",
					them = tonumber(f[7]) or 0, me = tonumber(f[8]) or 0,
				}
			end
		end
		S.passed = out
		S.passedTime = GetTimeSinceStart()
	end)
end

local function loadVs(name)
	S.vsName = name
	S.vs = nil
	request({op = "vs", name = name}, function(lines)
		local v = {name = lines[1][2] or name, isRival = lines[1][3] == "1", ahead = {}, behind = {}}
		for i = 2, #lines do
			local f = lines[i]
			if f[1] == "C" then
				local e = {
					ck = f[2] or "", title = f[3] or "", lv = f[4] or "", tbl = f[5] or "",
					them = tonumber(f[6]) or 0, me = tonumber(f[7]) or 0,
					themLamp = tonumber(f[8]), myLamp = tonumber(f[9]),
				}
				local side = e.them > e.me and v.ahead or v.behind
				side[#side + 1] = e
			end
		end
		S.vsName = v.name
		S.vs = v
		S.vsTime = GetTimeSinceStart()
	end)
end

local function setRival(name, op)
	S.errs.add, S.errs.remove = nil, nil
	request({op = op, name = name}, function(lines)
		local nick = lines[1][3] or name
		if S.vs and string.lower(S.vs.name) == string.lower(nick) then
			S.vs.isRival = lines[1][2] == "1"
		end
		if op == "add" then
			S.mode = "vs"
			page = 0
			loadVs(nick)
		end
		loadList()
		loadPassed()
	end)
end

local function stale(time)
	return not time or GetTimeSinceStart() - time > RELOAD
end

local function loadAll()
	if not loggedIn() then
		return
	end
	if stale(S.listTime) then
		loadList()
	end
	if stale(S.passedTime) then
		loadPassed()
	end
	if S.mode == "vs" and S.vsName and stale(S.vsTime) then
		loadVs(S.vsName)
	end
end

---------------------------------------------------------------------------
-- what the rows show
---------------------------------------------------------------------------
local function score(tbl, ex)
	if tbl == "o2jam" then
		return string.format("%.2f%%", ex / 1000)
	end
	return tostring(ex)
end
local function gap(tbl, d)
	if tbl == "o2jam" then
		return string.format("+%.2f%%", d / 1000)
	end
	return "+" .. d
end

-- the error of the request behind the view shown
local viewOp = {passed = "beaten", list = "list", vs = "vs"}
local function viewErr()
	return S.errs[viewOp[S.mode]]
end

local function current()
	if S.mode == "list" then
		return S.list or {}
	elseif S.mode == "vs" then
		return S.vs and S.vs[S.vsSide] or {}
	end
	return S.passed or {}
end
local function entry(i)
	return current()[page * rows + i]
end
local function pages()
	return math.max(1, math.ceil(#current() / rows))
end

local function songOf(e)
	return e and e.ck and e.ck ~= "" and SONGMAN:GetSongByChartKey(e.ck) or nil
end
local function titleOf(e)
	local song = songOf(e)
	return song and song:GetDisplayMainTitle() or e.title, song and W.white or W.gray
end
local lvColor = color("#d080ff")
local function lampColor(lamp)
	if lamp and lamp >= 1 and lamp <= 6 and getBMSLampInfo then
		return getBMSLampInfo(lamp, 2)
	end
	return W.white
end

-- the columns of each view: x, align, name, max width, and the text and
-- color of an entry
local cols = {
	list = {
		{24, 0, "RIVAL", 120, function(e)
			return e.name, W.white
		end},
		{W.width - 150, 1, "AHEAD OF YOU", 90, function(e)
			return tostring(e.ahead), W.red
		end},
		{W.width - 60, 1, "BEHIND YOU", 90, function(e)
			return tostring(e.behind), W.green
		end},
		{W.width - 10, 1, "", 40, function(e)
			return "VS >", W.gray
		end},
	},
	passed = {
		{24, 0, "RIVAL", 70, function(e)
			return e.rival, W.gold
		end},
		{100, 0, "LV", 34, function(e)
			return e.lv, lvColor
		end},
		{136, 0, "TITLE", W.width - 300, titleOf},
		{W.width - 112, 1, "RIVAL", 54, function(e)
			return score(e.tbl, e.them), W.white
		end},
		{W.width - 62, 1, "YOU", 54, function(e)
			return score(e.tbl, e.me), W.gray
		end},
		{W.width - 10, 1, "GAP", 50, function(e)
			return gap(e.tbl, e.them - e.me), W.red
		end},
	},
	vs = {
		{24, 0, "LV", 34, function(e)
			return e.lv, lvColor
		end},
		{62, 0, "TITLE", W.width - 230, titleOf},
		{W.width - 112, 1, "RIVAL", 54, function(e)
			return score(e.tbl, e.them), lampColor(e.themLamp)
		end},
		{W.width - 62, 1, "YOU", 54, function(e)
			return score(e.tbl, e.me), lampColor(e.myLamp)
		end},
		{W.width - 10, 1, "GAP", 50, function(e)
			local d = math.abs(e.them - e.me)
			return gap(e.tbl, d), e.them > e.me and W.red or W.green
		end},
	},
}
local MAXCOLS = 6

local t = W.frame(tab, "BMSRivals", function()
	page = 0
	if S.mode == "vs" and not S.vsName then
		S.mode = "passed"
	end
	loadAll()
end)
t.BMSRivalsRefreshMessageCommand = function(self)
	if self.open then
		self:playcommand("Show")
	end
end

-- views
local views = {{"passed", "PASSED YOU", 80}, {"list", "RIVALS", 60}, {"vs", "VS", 40}}
local vx = 8
for _, v in ipairs(views) do
	t[#t + 1] = W.button(v[2], vx + v[3] / 2, W.top + 12, v[3], function()
		S.errs.add, S.errs.remove = nil, nil
		S.mode = v[1]
		page = 0
		if v[1] == "vs" and S.vsName and stale(S.vsTime) then
			loadVs(S.vsName)
		end
		refresh()
	end, function()
		return loggedIn() and (v[1] ~= "vs" or S.vsName ~= nil)
	end, function()
		return S.mode == v[1]
	end)
	vx = vx + v[3] + 4
end
-- add a rival by nickname
t[#t + 1] = W.button("+ ADD RIVAL", W.width - 8 - 40, W.top + 12, 80, function()
	easyInputStringWithFunction("Nickname of the rival on the ranking site:", 32, false, function(answer)
		answer = (answer or ""):gsub("^%s+", ""):gsub("%s+$", "")
		if answer ~= "" then
			setRival(answer, "add")
		end
	end)
end, loggedIn)

-- second line: what the view is about, or what went wrong in red
t[#t + 1] = W.text(8, W.top + 32, 0.32, 0) .. {
	ShowCommand = function(self)
		local s = ""
		local err = loggedIn() and (S.errs.add or S.errs.remove or viewErr())
		if not loggedIn() then
			s = ""
		elseif err then
			self:settext(err):diffuse(W.red):maxwidth((W.width - (S.mode == "vs" and 200 or 16)) / 0.32)
			return
		elseif S.mode == "list" then
			s = S.list and string.format("%d rival%s (at most 50)", #S.list, #S.list == 1 and "" or "s") or ""
		elseif S.mode == "passed" then
			s = S.passed and string.format("Passed you on %d chart%s in the last 30 days", #S.passed, #S.passed == 1 and "" or "s") or ""
		elseif S.vs then
			s = string.format("%s: ahead on %d, behind on %d", S.vs.name, #S.vs.ahead, #S.vs.behind)
		elseif S.vsName then
			s = S.vsName
		end
		self:settext(s):diffuse(W.gray):maxwidth((W.width - 200) / 0.32)
	end,
}
-- VS: which side, and rival or not
local function inVs()
	return loggedIn() and S.mode == "vs" and S.vs ~= nil
end
local sides = {{"ahead", "AHEAD"}, {"behind", "BEHIND"}}
for k, sd in ipairs(sides) do
	t[#t + 1] = Def.ActorFrame {
		ShowCommand = function(self)
			self:visible(inVs())
		end,
		W.button(sd[2], W.width - 190 + (k - 1) * 58 + 27, W.top + 32, 54, function()
			S.vsSide = sd[1]
			page = 0
			refresh()
		end, nil, function()
			return S.vsSide == sd[1]
		end),
	}
end
t[#t + 1] = Def.ActorFrame {
	ShowCommand = function(self)
		self:visible(inVs())
	end,
	W.button("REMOVE", W.width - 8 - 30, W.top + 32, 60, function()
		if S.vs then
			setRival(S.vs.name, S.vs.isRival and "remove" or "add")
		end
	end) .. {
		ShowCommand = function(self)
			self:GetChild("Label"):settext(S.vs and not S.vs.isRival and "ADD" or "REMOVE")
		end,
	},
}

-- column names
for k = 1, MAXCOLS do
	t[#t + 1] = W.text(0, listY - 14, 0.3, 0) .. {
		ShowCommand = function(self)
			local c = cols[S.mode][k]
			self:visible(c ~= nil and loggedIn())
			if c then
				self:x(W.x + c[1]):halign(c[2]):settext(c[3]):diffuse(W.gray)
			end
		end,
	}
end

for i = 1, rows do
	local y = listY + (i - 1) * W.rowH
	local f = Def.ActorFrame {
		ShowCommand = function(self)
			self:visible(loggedIn() and entry(i) ~= nil)
		end,
		W.rowBand(i, y, nil, function(i)
			local e = entry(i)
			if not e then
				return
			end
			if S.mode == "list" then
				S.mode = "vs"
				page = 0
				loadVs(e.name)
				refresh()
			else
				local song = songOf(e)
				if song then
					W.pickSong(song)
				end
			end
		end),
		W.text(18, y, 0.3, 1) .. {
			ShowCommand = function(self)
				self:settext(entry(i) and (page * rows + i) or ""):diffuse(W.gray)
			end,
		},
	}
	for k = 1, MAXCOLS do
		f[#f + 1] = W.text(0, y, 0.32, 0) .. {
			ShowCommand = function(self)
				local c = cols[S.mode][k]
				local e = entry(i)
				if not c or not e then
					self:settext("")
					return
				end
				local s, col = c[5](e)
				self:x(W.x + c[1]):halign(c[2]):maxwidth(c[4] / 0.32)
				self:settext(s or ""):diffuse(col or W.white)
			end,
		}
	end
	t[#t + 1] = f
end

-- pages and messages
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
		local n = #current()
		self:diffuse(W.gray)
		if n > 0 then
			self:settextf("%d-%d of %d", page * rows + 1, math.min(n, (page + 1) * rows), n)
		else
			self:settext("")
		end
	end,
}
-- in the middle of an empty list: why it is empty
t[#t + 1] = W.text(W.width / 2, listY + 40, 0.36, 0.5, function(self)
	self:maxwidth((W.width - 40) / 0.36)
end) .. {
	ShowCommand = function(self)
		local s = ""
		local col = W.gray
		if not loggedIn() then
			s = "Log in to the ranking site in the Ranking window (key 1) to see your rivals"
		elseif viewErr() then
			s = "" -- the error is on the line above
		elseif #current() == 0 then
			if S.mode == "list" then
				s = S.list and "No rivals yet: + ADD RIVAL, /rival nick in the chat, or + Add rival on a profile on the site" or "Loading..."
			elseif S.mode == "passed" then
				s = S.passed and "No rival passed you in the last 30 days" or "Loading..."
			elseif not S.vs then
				s = "Loading..."
			elseif S.vsSide == "ahead" then
				s = S.vs.name .. " is not ahead of you on any chart you both cleared"
			else
				s = "You are not ahead of " .. S.vs.name .. " on any chart you both cleared"
			end
		end
		self:settext(s):diffuse(col)
	end,
}
t[#t + 1] = W.text(W.width / 2, pageY + 16, 0.26, 0.5) .. {
	ShowCommand = function(self)
		local s = ""
		if loggedIn() then
			if S.mode == "passed" then
				s = "A rival uploaded a better EX than your best on a chart you cleared. Click a row to pick the song."
			elseif S.mode == "list" then
				s = "Best EX on charts you both cleared. Click a rival to compare chart by chart."
			else
				s = "Charts you both cleared, the smallest gap first. Click a row to pick the song."
			end
		end
		self:settext(s):diffuse(W.gray):maxwidth((W.width - 20) / 0.26)
	end,
}

return t
