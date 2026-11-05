-- 7k eval screen after a BMS dan course: the course result (合格 / 不合格),
-- saved to the profile's BMSDan.ini and sent to the ranking site once.
local res = SONGMAN.GetBMSCourseResult and SONGMAN:GetBMSCourseResult()
if not res or not res.finished or not BMSDan then
	return Def.ActorFrame {}
end
BMSDan.finish(res)

local w, h = 420, 92
local x, y = SCREEN_CENTER_X, 70
local j = res.judges or {}
local passed = res.cleared

local function line(dy, zoom, txt, col)
	return LoadFont("Common Normal") .. {
		InitCommand = function(self)
			self:xy(x, y + dy):zoom(zoom):settext(txt):diffuse(col or color("#ffffff"))
			self:shadowlength(1):shadowcolor(color("0,0,0,0.8")):maxwidth((w - 20) / zoom)
		end,
	}
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
			self:xy(x, y - 14):valign(0):zoomto(w, 3):diffuse(passed and color("#ffd91a") or color("#ff4444"))
		end,
	},
	line(0, 0.5, res.name),
	line(24, 0.9, passed and "合格  CLEAR" or "不合格  FAILED", passed and color("#ffd91a") or color("#ff5555")),
	line(48, 0.38, string.format("%s %.1f%%   songs %d/%d   max combo %d",
		BMSDan.gaugeNames[res.classGauge] or res.classGauge,
		res.gauge, res.songsPlayed, res.songsTotal, res.maxCombo or 0), color("#cfd6e6")),
	line(64, 0.34, string.format("PG %d  GR %d  GD %d  BD %d  PR %d  EP %d   EX %d",
		j[1] or 0, j[2] or 0, j[3] or 0, j[4] or 0, j[5] or 0, j[6] or 0, (j[1] or 0) * 2 + (j[2] or 0)), color("#9aa3b5")),
}
