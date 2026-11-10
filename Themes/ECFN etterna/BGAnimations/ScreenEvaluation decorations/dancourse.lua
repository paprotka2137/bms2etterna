-- 7k result screen of a song in a BMS dan course: where the course stands
-- and what START does next (the next song, or the COURSE RESULT screen).
local res = SONGMAN.GetBMSCourseResult and SONGMAN:GetBMSCourseResult()
if not res or not res.id or not BMSDan then
	return Def.ActorFrame {}
end
-- only right after a song of the course (not an old score opened later)
local pss = STATSMAN:GetCurStageStats():GetPlayerStageStats()
local hs = pss and pss:GetHighScore()
local key = hs and hs:GetScoreKey() or ""
local mine = false
for _, k in ipairs(res.scoreKeys or {}) do
	if k == key then
		mine = true
	end
end
if not mine then
	return Def.ActorFrame {}
end

local w, h = 460, 54
local x, y = SCREEN_CENTER_X, 64
local alive = not res.finished or res.cleared
local col = alive and color("#ffd91a") or color("#ff4444")

local function line(dy, zoom, txt, c)
	return LoadFont("Common Normal") .. {
		InitCommand = function(self)
			self:xy(x, y + dy):zoom(zoom):settext(txt):diffuse(c or color("#ffffff"))
			self:shadowlength(1):shadowcolor(color("0,0,0,0.8")):maxwidth((w - 20) / zoom)
		end,
	}
end

local next
if not res.finished then
	next = "START: song " .. (res.songsPlayed + 1) .. "/" .. res.songsTotal
else
	next = "START: course result"
end

return Def.ActorFrame {
	OnCommand = function(self)
		self:diffusealpha(0):sleep(0.3):linear(0.25):diffusealpha(1)
	end,
	Def.Quad {
		InitCommand = function(self)
			self:xy(x, y + h / 2 - 14):zoomto(w, h):diffuse(color("0,0,0,0.8"))
		end,
	},
	Def.Quad {
		InitCommand = function(self)
			self:xy(x, y - 14):valign(0):zoomto(w, 3):diffuse(col)
		end,
	},
	line(0, 0.45, string.format("%s   song %d/%d   %s %.1f%%", res.name, res.songsPlayed, res.songsTotal,
		BMSDan.gaugeNames[res.classGauge] or res.classGauge, res.gauge)),
	line(24, 0.42, next, col),
}
