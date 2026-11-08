-- 7k multiplayer: the live room ranking during the song, BMS style. One row
-- per player with the EX score, the EX rate with its DJ level and the BP
-- (BAD + POOR) count, sorted by EX score. The others come from the server
-- every 250 ms (NSMAN:GetMPLeaderboard), our own row is live.
-- Sits at the leaderboard position of the gameplay layout (LeaderboardX/Y).

local ROWS = 8
local W = 196
local H = 24
local GAP = 2
local ACCENT = color("#3f9fff")
local GOLD = color("#ffd24a")
local GREY = color("#9aa4b0")
local DIM = color("#5c6670")
local WHITE = color("#ffffff")

local me = NSMAN:GetLoggedInUsername() or ""
local mine = {w1 = 0, w2 = 0, w3 = 0, w4 = 0, w5 = 0, miss = 0, combo = 0}
local jkeys = {
	TapNoteScore_W1 = "w1",
	TapNoteScore_W2 = "w2",
	TapNoteScore_W3 = "w3",
	TapNoteScore_W4 = "w4",
	TapNoteScore_W5 = "w5",
	TapNoteScore_Miss = "miss",
}

local function djLevel(r)
	if r == nil then
		return "", DIM
	end
	local n = r * 9
	if n >= 8 then
		return "AAA", GOLD
	elseif n >= 7 then
		return "AA", color("#e0e8f0")
	elseif n >= 6 then
		return "A", color("#7ee08a")
	elseif n >= 5 then
		return "B", GREY
	elseif n >= 4 then
		return "C", GREY
	elseif n >= 3 then
		return "D", DIM
	elseif n >= 2 then
		return "E", DIM
	end
	return "F", DIM
end

-- counts of a judgment string "W1 I W2 I W3 I W4 I W5 I Miss  xCombo"
local function parse(jdgstr)
	local v = {}
	for n in tostring(jdgstr or ""):gmatch("%d+") do
		v[#v + 1] = tonumber(n)
	end
	return {w1 = v[1] or 0, w2 = v[2] or 0, w3 = v[3] or 0, w4 = v[4] or 0, w5 = v[5] or 0, miss = v[6] or 0, combo = v[7] or 0}
end

local function entryOf(name, c)
	local judged = c.w1 + c.w2 + c.w3 + c.w4 + c.w5 + c.miss
	local ex = c.w1 * 2 + c.w2
	return {
		name = name,
		ex = ex,
		rate = judged > 0 and ex / (judged * 2) or nil,
		bp = c.w4 + c.w5 + c.miss,
		combo = c.combo,
		me = name == me,
	}
end

local function standings()
	local list = {}
	for _, s in ipairs(NSMAN:GetMPLeaderboard() or {}) do
		if s.user ~= me then
			list[#list + 1] = entryOf(s.user, parse(s.jdgstr))
		end
	end
	list[#list + 1] = entryOf(me, mine)
	table.sort(list, function(a, b)
		if a.ex ~= b.ex then
			return a.ex > b.ex
		end
		return a.name:lower() < b.name:lower()
	end)
	return list
end

local function Label(name, x, y, zoom, align, c, maxw)
	return LoadFont("Common Normal") .. {
		Name = name,
		InitCommand = function(self)
			self:halign(align):valign(0.5):xy(x, y):zoom(zoom):diffuse(c or WHITE)
			if maxw then
				self:maxwidth(maxw / zoom)
			end
		end,
	}
end

local function row(i)
	return Def.ActorFrame {
		Name = "Row" .. i,
		InitCommand = function(self)
			self:y(14 + (i - 1) * (H + GAP)):visible(false)
		end,
		SetRowCommand = function(self, e)
			if not e then
				self:visible(false)
				return
			end
			self:visible(true)
			self:GetChild("Bar"):diffuse(e.me and ACCENT or (i == 1 and GOLD or DIM))
			self:GetChild("Bg"):diffusealpha(e.me and 0.75 or 0.6)
			self:GetChild("Rank"):settext(i):diffuse(i == 1 and GOLD or GREY)
			self:GetChild("Name"):settext(e.name):diffuse(e.me and ACCENT or WHITE)
			self:GetChild("Ex"):settext(e.ex)
			local dj, djc = djLevel(e.rate)
			self:GetChild("Dj"):settext(dj):diffuse(djc)
			self:GetChild("Rate"):settext(e.rate and string.format("%.2f%%", e.rate * 100) or "--")
			self:GetChild("Bp"):settextf("BP %d   x%d", e.bp, e.combo)
		end,
		Def.Quad {
			Name = "Bg",
			InitCommand = function(self)
				self:halign(0):valign(0):zoomto(W, H):diffuse(color("0.03,0.05,0.08,1")):diffusealpha(0.6)
			end,
		},
		Def.Quad {
			Name = "Bar",
			InitCommand = function(self)
				self:halign(0):valign(0):zoomto(3, H)
			end,
		},
		Label("Rank", 13, H / 2, 0.5, 0.5, GREY),
		Label("Name", 24, 7, 0.36, 0, WHITE, 110),
		Label("Ex", W - 6, 8, 0.45, 1, WHITE),
		Label("Dj", 24, 17.5, 0.3, 0, GREY),
		Label("Rate", 50, 17.5, 0.3, 0, GREY),
		Label("Bp", W - 6, 17.5, 0.28, 1, GREY),
	}
end

local t = Def.ActorFrame {
	Name = "LeaderboardMP",
	InitCommand = function(self)
		self:xy(math.max(6, MovableValues.LeaderboardX or 0), MovableValues.LeaderboardY or 48)
	end,
	BeginCommand = function(self)
		self:playcommand("Refresh")
	end,
	RefreshCommand = function(self)
		local list = standings()
		for i = 1, ROWS do
			self:GetChild("Row" .. i):playcommand("SetRow", list[i])
		end
	end,
	MPLeaderboardUpdateMessageCommand = function(self)
		self:playcommand("Refresh")
	end,
	JudgmentMessageCommand = function(self, params)
		local k = jkeys[params.Judgment]
		if k and params.Val then
			mine[k] = params.Val
			self:playcommand("Refresh")
		end
	end,
	ComboChangedMessageCommand = function(self, params)
		mine.combo = params.PlayerStageStats and params.PlayerStageStats:GetCurrentCombo() or params.OldCombo or mine.combo
	end,
	Label("Title", 2, 4, 0.3, 0, ACCENT, W) .. {
		BeginCommand = function(self)
			local room = NSMAN:GetCurrentRoomName() or ""
			self:settext(room ~= "" and ("ROOM  " .. room) or "ROOM")
		end,
	},
}
for i = 1, ROWS do
	t[#t + 1] = row(i)
end
return t
