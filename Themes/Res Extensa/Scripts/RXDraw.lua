-- Res Extensa theme: small drawing helpers shared by the mono screens.
-- Positions are in whatever frame the actors are put in; sizes of text are
-- the font size in pixels of that frame (Inter's em, Fonts/inter).

local fontEm = {
	["RX Normal"] = 24,
	["RX SemiBold"] = 24,
	["RX Large"] = 48,
	["RX Light"] = 48,
	["RX Bold"] = 48,
	["Common Normal"] = 24,
	["Common Large"] = 48,
}

-- the zoom that draws `font` at `px` pixels
function rxZoom(font, px)
	return px / (fontEm[font] or 24)
end

-- text that reads get() on Refresh. c is a color or a function giving one
-- (read on Refresh too). align 0 left, 0.5 middle, 1 right; y is the middle.
function rxText(font, x, y, px, align, maxw, get, c)
	local z = rxZoom(font, px)
	return LoadFont(font) .. {
		InitCommand = function(self)
			self:xy(x, y):halign(align or 0):valign(0.5):zoom(z)
			if maxw then
				self:maxwidth(maxw / z)
			end
			if type(c) ~= "function" then
				self:diffuse(c or rxColor("text"))
			end
			self:settext("")
		end,
		RefreshCommand = function(self)
			if get then
				self:settext(get() or "")
			end
			if type(c) == "function" then
				self:diffuse(c() or rxColor("text"))
			end
		end,
	}
end

-- fixed text
function rxLabel(font, x, y, px, align, text, c, maxw)
	local z = rxZoom(font, px)
	return LoadFont(font) .. {
		InitCommand = function(self)
			self:xy(x, y):halign(align or 0):valign(0.5):zoom(z):diffuse(c or rxColor("muted"))
			if maxw then
				self:maxwidth(maxw / z)
			end
			self:settext(text)
		end,
	}
end

-- a filled rectangle from its top left corner
function rxBox(x, y, w, h, c)
	return Def.Quad {
		InitCommand = function(self)
			self:halign(0):valign(0):xy(x, y):zoomto(w, h):diffuse(c or rxColor("line"))
		end,
	}
end

-- 1px lines (in the frame's pixels)
function rxHLine(x, y, w, c)
	return rxBox(x, y, w, 1, c or rxColor("line"))
end
function rxVLine(x, y, h, c)
	return rxBox(x, y, 1, h, c or rxColor("line"))
end

-- adds a quad to a vertex list
function rxQuad(verts, x1, y1, x2, y2, c)
	verts[#verts + 1] = {{x1, y1, 0}, c}
	verts[#verts + 1] = {{x2, y1, 0}, c}
	verts[#verts + 1] = {{x2, y2, 0}, c}
	verts[#verts + 1] = {{x1, y2, 0}, c}
end

-- quads rebuilt by build(verts) on the given command
function rxQuads(x, y, cmd, build)
	local a = Def.ActorMultiVertex {
		InitCommand = function(self)
			self:xy(x, y)
		end,
	}
	a[cmd .. "Command"] = function(self)
		local verts = {}
		build(verts)
		if #verts == 0 then
			self:visible(false)
			return
		end
		self:visible(true)
		self:SetVertices(verts)
		self:SetDrawState {Mode = "DrawMode_Quads", First = 1, Num = #verts}
	end
	return a
end

-- an invisible clickable area; onClick(event) with the mouse button name.
-- blocked() (optional) stops the click, e.g. while a tab window is over it.
function rxClick(x, y, w, h, onClick, blocked)
	return UIElements.QuadButton(1, 1) .. {
		InitCommand = function(self)
			self:halign(0):valign(0):xy(x, y):zoomto(w, h):diffusealpha(0)
		end,
		MouseDownCommand = function(self, params)
			if blocked and blocked() then
				return
			end
			onClick(params.event)
		end,
	}
end

-- lamp colors by the ECFN lamp frame (getBMSLampFrame): 0 none, 1 FAILED,
-- 2 3 ASSIST, 4 EASY, 5 CLEAR, 6 HARD, 7 EX HARD, 8 FULL COMBO, 9 PERFECT, 10 MAX
local lampNames = {"noplay", "failed", "assist", "assist", "easy", "clear", "hard", "exhard", "fc", "fc", "fc"}
function rxLampColor(frame)
	return rxColor(lampNames[(frame or 0) + 1] or "noplay")
end

local lampLabels = {"NO PLAY", "FAILED", "ASSIST", "L-ASSIST", "EASY", "CLEAR", "HARD", "EX HARD", "FULL COMBO", "PERFECT", "MAX"}
function rxLampLabel(frame)
	return lampLabels[(frame or 0) + 1] or "NO PLAY"
end

-- the text color drawn on a lamp chip of that color
function rxLampTextColor(frame)
	if frame == 1 then
		return rxColor("white")
	elseif frame == 0 then
		return rxColor("muted")
	end
	return color("#111111")
end

-- a lamp chip: colored box with the lamp's name. get() gives the lamp frame.
function rxLampChip(x, y, w, h, px, get)
	return Def.ActorFrame {
		InitCommand = function(self)
			self:xy(x, y)
		end,
		Def.Quad {
			InitCommand = function(self)
				self:halign(0):valign(0):zoomto(w, h)
			end,
			RefreshCommand = function(self)
				local f = get()
				self:visible(f ~= nil)
				if f then
					self:diffuse(rxLampColor(f))
					-- PERFECT and MAX shimmer like on LR2
					if f >= 9 then
						self:diffuseshift():effectcolor1(rxLampColor(f)):effectcolor2(color("#ffffff")):effectperiod(1)
					else
						self:stopeffect()
					end
				end
			end,
		},
		LoadFont("RX Bold") .. {
			InitCommand = function(self)
				self:xy(w / 2, h / 2):zoom(rxZoom("RX Bold", px)):maxwidth((w - 8) / rxZoom("RX Bold", px))
			end,
			RefreshCommand = function(self)
				local f = get()
				self:settext(f and rxLampLabel(f) or "")
				if f then
					self:diffuse(rxLampTextColor(f))
				end
			end,
		},
	}
end

-- difficulty colors by the ECFN level row (getBMSLevelDisplay): 0 other,
-- 1 beginner, 2 normal, 3 hyper, 4 another, 5 insane
local rowColors = {[0] = "muted", "easy", "clear", "gr", "pr", "bd"}
function rxLevelColor(row)
	return rxColor(rowColors[row or 0] or "muted")
end

-- lamp colors by the site's lamp numbers (getBMSLampFromScore): 1 FULL COMBO,
-- 2 EX HARD, 3 HARD, 4 CLEAR, 5 EASY, 6 FAILED
local siteLamps = {"fc", "exhard", "hard", "clear", "easy", "failed"}
function rxSiteLampColor(lamp)
	return rxColor(siteLamps[lamp or 0] or "noplay")
end

-- the accent of a chart: BMS table levels (getBMSLevelDisplay row 5) run
-- along a scale from green (easy) through cyan, violet and pink to red (the
-- top of the tables); other charts keep their difficulty row color. Used for
-- the level numbers and the wheel's selection, so every level has its color.
local accentStops = {
	{0, {0.40, 1.00, 0.45}},
	{5, {0.29, 0.85, 1.00}},
	{10, {0.48, 0.55, 1.00}},
	{15, {0.75, 0.45, 1.00}},
	{20, {1.00, 0.40, 0.80}},
	{25, {1.00, 0.30, 0.30}},
}
function rxLevelAccent(level, row, alpha)
	if row ~= 5 or type(level) ~= "number" then
		local c = rxLevelColor(row)
		if alpha then
			c = {c[1], c[2], c[3], alpha}
		end
		return c
	end
	local l = math.max(0, math.min(25, level))
	for i = 2, #accentStops do
		local a, b = accentStops[i - 1], accentStops[i]
		if l <= b[1] then
			local f = (l - a[1]) / (b[1] - a[1])
			return {
				a[2][1] + (b[2][1] - a[2][1]) * f,
				a[2][2] + (b[2][2] - a[2][2]) * f,
				a[2][3] + (b[2][3] - a[2][3]) * f,
				alpha or 1,
			}
		end
	end
	return {1, 0.3, 0.3, alpha or 1}
end

-- the accent of the chart under the wheel
function rxCurrentAccent(alpha)
	local song = GAMESTATE:GetCurrentSong()
	if not song then
		return rxColor("white", alpha)
	end
	local level, row = getBMSLevelDisplay(song, GAMESTATE:GetCurrentSteps())
	return rxLevelAccent(level, row, alpha)
end
