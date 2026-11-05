-- 7k: the "Dan" window (key 6): BMS dan courses (段位認定) from
-- Assets/BMSCourses/. Pick a course, START plays its charts back to back on
-- a course gauge (CLASS, EX CLASS with HARD, EX HARD CLASS with EX HARD or
-- DEATH), like LR2 / beatoraja. Lanes: off or mirror only.
local D = BMSDan
local tab = 11
local frameX = 10
local frameY = 45
local frameWidth = capWideScale(360, 400)
local rowH = 14
local listY = frameY + 56
local bottomY = SCREEN_HEIGHT - 82 -- above the window strip
local detailY -- set once the list size is known

local onTab = false
local courses = {}
local found = {} -- [i] = {resolved, count}
local sel = 1

local white = color("#ffffff")
local gray = color("#9aa3b5")
local blue = color("#3f9fff")
local green = color("#66ff66")
local red = color("#ff6666")
local gold = color("#ffd91a")

local gaugeFromOption = {"Class", "Class", "ExClass", "ExHardClass", "ExHardClass"}

local function selected()
	return courses[sel]
end

local function load()
	courses = D.allCourses()
	found = {}
	for i, c in ipairs(courses) do
		local res, n = D.resolve(c)
		found[i] = {res = res, n = n}
	end
	if sel > #courses then
		sel = 1
	end
end

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

local t = Def.ActorFrame {
	Name = "BMSDan",
	BeginCommand = function(self)
		self:visible(false):xy(-500, 0):diffusealpha(0)
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
			load()
			self:visible(true):queuecommand("On")
			self:playcommand("Show")
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
	-- the gauge picked on song select decides the course gauge
	PlayerOptionsChangedMessageCommand = function(self)
		if onTab then
			self:playcommand("Show")
		end
	end,
}

-- backdrop
t[#t + 1] = Def.Quad {
	InitCommand = function(self)
		self:xy(frameX, frameY - 4):halign(0):valign(0):zoomto(frameWidth, bottomY - frameY + 4):diffuse(color("0.02,0.03,0.06,0.92"))
	end,
}

-- header: the set and the best clear
t[#t + 1] = text(8, frameY + 12, 0.42, 0) .. {
	ShowCommand = function(self)
		local c = selected()
		self:settext(c and c.set or "No dan courses (Assets/BMSCourses)")
		self:maxwidth((frameWidth - 16) / 0.42)
	end,
}
t[#t + 1] = text(8, frameY + 30, 0.34, 0) .. {
	ShowCommand = function(self)
		local b = D.best()
		if b then
			local r = D.record(b.id) or {}
			self:settext("Best: " .. (b.short or b.name) .. "  (" .. (D.gaugeNames[r.gauge_type] or "CLASS") .. ")"):diffuse(gold)
		else
			self:settext("No dan cleared yet"):diffuse(gray)
		end
	end,
}
t[#t + 1] = text(frameWidth - 8, frameY + 30, 0.32, 1) .. {
	ShowCommand = function(self)
		local g = gaugeFromOption[getBMSOption("Gauge")] or "Class"
		self:settext("Course gauge: " .. D.gaugeNames[g]):diffuse(gray)
	end,
}

-- column names
t[#t + 1] = text(8, listY - 14, 0.3, 0, function(self)
	self:settext("COURSE"):diffuse(gray)
end)
t[#t + 1] = text(frameWidth - 120, listY - 14, 0.3, 0.5, function(self)
	self:settext("CHARTS"):diffuse(gray)
end)
t[#t + 1] = text(frameWidth - 12, listY - 14, 0.3, 1, function(self)
	self:settext("RESULT"):diffuse(gray)
end)

local maxRows = 12
for i = 1, maxRows do
	local y = listY + (i - 1) * rowH
	t[#t + 1] = Def.ActorFrame {
		ShowCommand = function(self)
			self:visible(courses[i] ~= nil)
		end,
		UIElements.QuadButton(1, 1) .. {
			InitCommand = function(self)
				self:xy(frameX + 4, y):halign(0):zoomto(frameWidth - 8, rowH - 2)
			end,
			ShowCommand = function(self)
				self:diffuse(i == sel and blue or white):diffusealpha(i == sel and 0.35 or 0.04)
			end,
			MouseDownCommand = function(self, params)
				if params.event == "DeviceButton_left mouse button" and onTab and courses[i] then
					sel = i
					self:GetParent():GetParent():playcommand("Show")
				end
			end,
		},
		text(10, y, 0.32, 0) .. {
			ShowCommand = function(self)
				local c = courses[i]
				if c then
					self:settext(c.short or c.name):maxwidth((frameWidth - 150) / 0.32)
				end
			end,
		},
		text(frameWidth - 120, y, 0.3, 0.5) .. {
			ShowCommand = function(self)
				local c = courses[i]
				if c then
					local n, all = found[i].n, #c.charts
					self:settext(n .. " / " .. all):diffuse(n == all and white or red)
				end
			end,
		},
		text(frameWidth - 12, y, 0.3, 1) .. {
			ShowCommand = function(self)
				local c = courses[i]
				if not c then
					return
				end
				local r = D.record(c.id)
				if r and tonumber(r.cleared) == 1 then
					self:settext("CLEAR " .. (D.gaugeNames[r.gauge_type] or "")):diffuse(green)
				elseif r then
					self:settext("FAILED " .. (r.best_songs or 0) .. "/" .. #c.charts):diffuse(red)
				else
					self:settext("-"):diffuse(gray)
				end
			end,
		},
	}
end

-- the selected course's charts
detailY = listY + maxRows * rowH + 4
for k = 1, 4 do
	local y = detailY + (k - 1) * 12
	t[#t + 1] = text(10, y, 0.28, 0) .. {
		ShowCommand = function(self)
			local c = selected()
			local ch = c and c.charts[k]
			self:visible(ch ~= nil)
			if not ch then
				return
			end
			local r = found[sel].res[k]
			local name = ch.table_title or ch.title
			if r then
				self:settext(k .. ". " .. name .. "   (" .. r.song:GetGroupName() .. ")"):diffuse(white)
			else
				self:settext(k .. ". " .. name .. "   MISSING"):diffuse(red)
			end
			self:maxwidth((frameWidth - 20) / 0.28)
		end,
	}
end

-- START
local startY = math.min(detailY + 4 * 12 + 8, bottomY - 12)
t[#t + 1] = UIElements.QuadButton(1, 1) .. {
	InitCommand = function(self)
		self:xy(frameX + frameWidth - 8, startY):halign(1):zoomto(80, 16)
	end,
	ShowCommand = function(self)
		local c = selected()
		local ok = c and found[sel].n == #c.charts
		self:diffuse(ok and blue or gray):diffusealpha(ok and 0.5 or 0.15)
	end,
	MouseDownCommand = function(self, params)
		if params.event ~= "DeviceButton_left mouse button" or not onTab then
			return
		end
		local c = selected()
		if not c then
			return
		end
		local ok, why = D.start(c)
		if not ok then
			ms.ok("Dan: " .. tostring(why))
		end
	end,
}
t[#t + 1] = text(frameWidth - 48, startY, 0.36, 0.5, function(self)
	self:settext("START")
end)
t[#t + 1] = text(8, startY, 0.3, 0, function(self)
	self:settext("1.0x, lanes off or mirror only"):diffuse(gray)
end)

return t
