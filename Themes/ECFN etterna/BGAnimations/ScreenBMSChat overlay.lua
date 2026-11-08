-- Chat of the BMS 7k ranking site (Scripts/BMSChat.lua holds the state).
-- T opens the panel from the bottom of the screen (song select, results,
-- title menu), Esc closes it. While it is closed, new messages show as a
-- small toast in the bottom right, also during songs.

local C = BMSChat
local R = BMSRanking

local W = SCREEN_WIDTH
local H = 210
local HEAD = 16
local CW = 120 -- channels column
local PW = 170 -- players column
local LINE = 11
local ROW = 14
local ZOOM = 0.35
local MX = CW + 6 -- message area
local MW = W - CW - PW - 12
local NMSG = math.floor((H - HEAD - 26) / LINE)
local NROW = math.floor((H - HEAD - 6) / ROW)
local TOAST_W = 230

local function mainColor(kind, fallback)
	local ok, c = pcall(getMainColor, kind)
	if ok and c then
		return c
	end
	return color(fallback)
end
local ACCENT = mainColor("positive", "#9654FD")
local GREY = color("#8a8a8a")
local DIM = color("#5a5a5a")
local WHITE = color("#ffffff")
local ONLINE = color("#4cd964")
local REQUEST = color("#ffcc33")

local open = false
local typing = "" -- text in the input box
local histPos = nil
local scroll = 0 -- lines scrolled up from the newest
local screenName = ""
local registered = false
local panel, meas, frame, stepper
local msgRows, chanRows, chanBgs, chanHits, pplRows, pplDots, pplBgs = {}, {}, {}, {}, {}, {}, {}
local chanKeys, pplNames = {}, {}

local function ulen(s)
	return #(s:gsub("[\128-\191]", ""))
end

local function textWidth(s)
	meas:settext(s)
	return meas:GetZoomedWidth()
end

local function wrap(text, width)
	local out = {}
	local line = ""
	for word in text:gmatch("%S+") do
		local cand = line == "" and word or (line .. " " .. word)
		if textWidth(cand) <= width then
			line = cand
		else
			if line ~= "" then
				out[#out + 1] = line
				line = ""
			end
			-- a word wider than the box on its own is cut by characters
			while textWidth(word) > width do
				local cut = ""
				for ch in word:gmatch("[%z\1-\127\194-\244][\128-\191]*") do
					if textWidth(cut .. ch) > width then
						break
					end
					cut = cut .. ch
				end
				if cut == "" then
					break
				end
				out[#out + 1] = cut
				word = word:sub(#cut + 1)
			end
			line = word
		end
	end
	if line ~= "" or #out == 0 then
		out[#out + 1] = line
	end
	return out
end

local function nameColor(name)
	if string.lower(name) == string.lower(C.myName()) then
		return ACCENT
	end
	local h = 0
	for i = 1, #name do
		h = (h * 31 + name:byte(i)) % 360
	end
	return HSV(h, 0.45, 1)
end

-- display lines of one message: {text, attrs = {{pos, len, color}}}
local function linesOf(m)
	if m._lines then
		return m._lines
	end
	local lines = {}
	if m.info then
		for i, l in ipairs(wrap("* " .. m.body, MW)) do
			lines[i] = {text = l, attrs = {{0, ulen(l), GREY}}}
		end
	else
		local time = os.date("%H:%M", m.t) .. " "
		local who = m.from .. ":"
		local w = wrap(time .. who .. " " .. m.body, MW)
		for i, l in ipairs(w) do
			lines[i] = {text = l, attrs = {}}
		end
		lines[1].attrs = {{0, ulen(time), DIM}, {ulen(time), ulen(who), nameColor(m.from)}}
	end
	m._lines = lines
	return lines
end

local function isGameplay(name)
	return name:find("Gameplay") ~= nil or name:find("StageInformation") ~= nil
end

local function canOpenOn(name)
	return name == "ScreenSelectMusic" or name == "ScreenNetSelectMusic" or name == "ScreenNetRoom" or
		name == "ScreenTitleMenu" or name:find("^ScreenEvaluation") ~= nil
end

local function statusText()
	if isGameplay(screenName) then
		local song = GAMESTATE:GetCurrentSong()
		return song and ("playing " .. song:GetDisplayMainTitle()) or "playing"
	elseif screenName:find("^ScreenEvaluation") then
		return "results"
	elseif screenName == "ScreenSelectMusic" or screenName == "ScreenNetSelectMusic" then
		return "choosing a song"
	end
	return "in menus"
end

-- the rows on the right: friends, then requests, then everyone else online
local function peopleRows()
	local friends, requests, others = {}, {}, {}
	for _, p in ipairs(C.people) do
		if p.rel == "friend" or p.rel == "sent" then
			friends[#friends + 1] = p
		elseif p.rel == "request" then
			requests[#requests + 1] = p
		elseif p.online then
			others[#others + 1] = p
		end
	end
	local rows = {}
	local function section(title, list)
		if #list > 0 then
			rows[#rows + 1] = {header = title}
			for _, p in ipairs(list) do
				rows[#rows + 1] = p
			end
		end
	end
	section("Friends", friends)
	section("Friend requests (/add nick)", requests)
	section("Online", others)
	if #rows == 0 then
		rows[1] = {header = "Nobody else online"}
	end
	return rows
end

-- "# Global", "* Room: name" (multiplayer room) or "@ nick"
local function chanLabel(key, ch)
	if key == "" then
		return "# " .. ch.name
	elseif key == C.ROOM then
		return "* Room: " .. ch.name
	end
	return "@ " .. ch.name
end

local function render()
	if not panel then
		return
	end
	C.panelOpen = open
	local ch = C.channels[C.current] or C.channels[""]
	local header = panel:GetChild("Header")
	local title = chanLabel(C.current, ch)
	local info = string.format("   %d online", C.onlineCount or 0)
	if C.err then
		info = "   " .. C.err
	end
	header:settext(title .. info)
	header:ClearAttributes()
	header:AddAttribute(ulen(title), {Length = ulen(info), Diffuse = C.err and color("#ff6666") or GREY})

	-- messages, newest at the bottom
	local lines = {}
	if not C.loggedIn() and C.current ~= C.ROOM then
		lines = {
			{text = "You are not logged in to the ranking site.", attrs = {}},
			{text = "Press Enter to log in (same nick and password as on the site).", attrs = {{0, 99, GREY}}},
		}
		scroll = 0
	else
		local need = NMSG + scroll
		for i = #ch.msgs, 1, -1 do
			local ls = linesOf(ch.msgs[i])
			for j = #ls, 1, -1 do
				table.insert(lines, 1, ls[j])
			end
			if #lines >= need then
				break
			end
		end
		if #ch.msgs == 0 then
			lines = {{text = C.current == "" and "No messages yet. Say hi! (/help for commands)" or
				C.current == C.ROOM and "Room chat. /ready when you are set, /help for the room commands." or
				"No messages with " .. ch.name .. " yet.", attrs = {{0, 99, GREY}}}}
		end
		scroll = math.max(0, math.min(scroll, #lines - NMSG))
	end
	local last = #lines - scroll
	for i = 1, NMSG do
		local row = msgRows[i]
		local l = lines[last - NMSG + i]
		row:ClearAttributes()
		if l then
			row:settext(l.text)
			for _, a in ipairs(l.attrs) do
				row:AddAttribute(a[1], {Length = math.min(a[2], ulen(l.text) - a[1]), Diffuse = a[3]})
			end
		else
			row:settext("")
		end
	end
	panel:GetChild("ScrollHint"):visible(scroll > 0)

	-- channels
	chanKeys = {}
	for i, c in ipairs(C.channelList()) do
		if i > NROW then
			break
		end
		chanKeys[i] = c.key
	end
	for i = 1, NROW do
		local key = chanKeys[i]
		local row, bg = chanRows[i], chanBgs[i]
		row:ClearAttributes()
		if key then
			local c = C.channels[key]
			local label = chanLabel(key, c)
			local badge = c.unread > 0 and string.format(" (%d)", c.unread) or ""
			row:settext(label .. badge)
			row:diffuse(key == C.current and WHITE or GREY)
			if badge ~= "" then
				row:AddAttribute(ulen(label), {Length = ulen(badge), Diffuse = REQUEST})
			end
			bg:visible(key == C.current)
		else
			row:settext("")
			bg:visible(false)
		end
	end

	-- players
	local rows = C.loggedIn() and peopleRows() or {}
	pplNames = {}
	for i = 1, NROW do
		local p = rows[i]
		local row, dot = pplRows[i], pplDots[i]
		row:ClearAttributes()
		pplNames[i] = p and not p.header and p.name or nil
		if not p then
			row:settext("")
			dot:visible(false)
		elseif p.header then
			row:settext(p.header):x(4):diffuse(DIM)
			dot:visible(false)
		else
			local extra = ""
			if p.rel == "sent" then
				extra = "  request sent"
			elseif p.online and p.status ~= "" then
				extra = "  " .. p.status
			end
			row:settext(p.name .. extra):x(14):diffuse(p.online and WHITE or GREY)
			if extra ~= "" then
				row:AddAttribute(ulen(p.name), {Length = ulen(extra), Diffuse = DIM})
			end
			dot:visible(true):diffuse(p.rel == "request" and REQUEST or (p.online and ONLINE or DIM))
		end
	end

	-- input box
	local box = panel:GetChild("Input")
	if typing == "" then
		local where = C.current == "" and "#Global" or C.current == C.ROOM and ("room " .. ch.name) or ("@" .. ch.name)
		box:settext((C.loggedIn() or C.current == C.ROOM) and ("Message " .. where .. "   (/help)") or ""):diffuse(DIM)
		panel:GetChild("Caret"):x(MX + 4)
	else
		local shown = typing
		while textWidth(shown) > MW - 10 and #shown > 0 do
			-- drop the first character (always at least one byte, so this ends)
			local rest = shown:gsub("^[%z\1-\127\194-\244][\128-\191]*", "")
			shown = #rest < #shown and rest or shown:sub(2)
		end
		box:settext(shown):diffuse(WHITE)
		panel:GetChild("Caret"):x(MX + 4 + box:GetZoomedWidth() + 1)
	end
end

local function setOpen(v)
	if open == v then
		return
	end
	open = v
	C.panelOpen = v
	scroll = 0
	histPos = nil
	frame:stoptweening():decelerate(0.18):y(v and SCREEN_HEIGHT - H or SCREEN_HEIGHT + 4)
	if v then
		local ch = C.channels[C.current]
		if ch then
			ch.unread = 0
		end
		frame:GetParent():GetChild("Toast"):stoptweening():diffusealpha(0)
		C.pollSoon()
	end
	render()
end

local function switchChannel(dir)
	local list = C.channelList()
	local at = 1
	for i, c in ipairs(list) do
		if c.key == C.current then
			at = i
		end
	end
	at = (at - 1 + dir) % #list + 1
	scroll = 0
	C.open(list[at].key)
end

local function ctrl()
	return INPUTFILTER:IsBeingPressed("left ctrl") or INPUTFILTER:IsBeingPressed("right ctrl")
end
local function shift()
	return INPUTFILTER:IsBeingPressed("left shift") or INPUTFILTER:IsBeingPressed("right shift")
end

local function input(event)
	local b = event.DeviceInput.button
	local press = event.type == "InputEventType_FirstPress"
	local pressOrRepeat = press or event.type == "InputEventType_Repeat"

	if not open then
		if press and b == "DeviceButton_t" and canOpenOn(screenName) and not ctrl() and
			not INPUTFILTER:IsBeingPressed("left alt") and not INPUTFILTER:IsBeingPressed("right alt") and
			not SCREENMAN:get_input_redirected(PLAYER_1) then
			setOpen(true)
			return true
		end
		return false
	end

	-- mouse: clicks on the panel stay in the panel, a click above it closes it
	if event.DeviceInput.is_mouse then
		if b == "DeviceButton_left mouse button" and press then
			if not isOver(panel:GetChild("Bg")) then
				setOpen(false)
				return false
			end
			for i = 1, NROW do
				if chanKeys[i] and isOver(chanHits[i]) then
					scroll = 0
					C.open(chanKeys[i])
					return true
				end
				if pplNames[i] and isOver(pplBgs[i]) then
					scroll = 0
					C.open(pplNames[i], pplNames[i])
					return true
				end
			end
			return true
		end
		if (b == "DeviceButton_mousewheel up" or b == "DeviceButton_mousewheel down") and press then
			if isOver(panel:GetChild("Bg")) then
				scroll = math.max(0, scroll + (b == "DeviceButton_mousewheel up" and 2 or -2))
				render()
				return true
			end
			return false
		end
		return isOver(panel:GetChild("Bg"))
	end

	-- F keys (screenshots, reload and so on) still work
	if b:find("^DeviceButton_F%d") then
		return false
	end
	if not pressOrRepeat then
		return true
	end

	if b == "DeviceButton_escape" then
		setOpen(false)
	elseif b == "DeviceButton_enter" or b == "DeviceButton_KP enter" then
		if not C.loggedIn() and C.current ~= C.ROOM then
			if press and R and R.askLogin then
				setOpen(false)
				R.askLogin(stepper)
			end
		elseif typing ~= "" then
			C.submit(typing)
			typing = ""
			histPos = nil
			scroll = 0
		end
	elseif b == "DeviceButton_tab" then
		switchChannel(shift() and -1 or 1)
	elseif b == "DeviceButton_backspace" then
		local rest = typing:gsub("[%z\1-\127\194-\244][\128-\191]*$", "")
		typing = #rest < #typing and rest or typing:sub(1, -2)
	elseif b == "DeviceButton_delete" then
		typing = ""
	elseif b == "DeviceButton_pgup" then
		scroll = scroll + NMSG - 2
	elseif b == "DeviceButton_pgdn" then
		scroll = math.max(0, scroll - (NMSG - 2))
	elseif b == "DeviceButton_up" and #C.history > 0 then
		histPos = math.max(1, (histPos or #C.history + 1) - 1)
		typing = C.history[histPos]
	elseif b == "DeviceButton_down" and histPos then
		histPos = histPos + 1
		typing = C.history[histPos] or ""
		if not C.history[histPos] then
			histPos = nil
		end
	elseif ctrl() and b == "DeviceButton_v" then
		local clip = Arch and Arch.getClipboard and Arch.getClipboard() or ""
		typing = C.toUTF8(typing .. clip, 300)
	elseif b == "DeviceButton_space" then
		typing = typing .. " "
	elseif not ctrl() and event.char and event.char:find("^[%w%p ]$") then
		if #typing < 300 then
			typing = typing .. event.char
		end
	end
	render()
	return true
end

local function update(self)
	local top = SCREENMAN:GetTopScreen()
	if top then
		local name = top:GetName()
		if name ~= screenName then
			screenName = name
			if open and not canOpenOn(name) then
				setOpen(false)
			end
		end
	end
	if not registered then
		for _, s in ipairs(SCREENMAN:GetOverlayScreens() or {}) do
			if s:GetName() == "ScreenBMSChat" then
				s:AddInputCallback(input)
				registered = true
			end
		end
	end
	C.syncRoom()
	if C.loggedIn() and not C.polling then
		local every = open and 3 or (isGameplay(screenName) and 10 or 8)
		if GetTimeSinceStart() - C.lastPoll >= every then
			C.poll(statusText(), open)
		end
	end
end

local t = Def.ActorFrame {
	Name = "BMSChat",
	InitCommand = function(self)
		self:SetUpdateFunction(update)
		self:SetUpdateFunctionInterval(0.2)
	end,
	BMSLoginChangedMessageCommand = function(self)
		C.reset()
		render()
	end,
	-- multiplayer room lines (ETTProtocol::handleReceiveChat)
	ChatMessageCommand = function(self, params)
		C.roomMessage(params)
	end,
}

-- the panel
local p = Def.ActorFrame {
	Name = "Panel",
	InitCommand = function(self)
		frame = self
		panel = self
		self:y(SCREEN_HEIGHT + 4)
	end,
	BeginCommand = function(self)
		render()
	end,
	BMSChatUpdatedMessageCommand = function(self)
		if open then
			render()
		end
	end,
	Def.Quad {
		Name = "Bg",
		InitCommand = function(self)
			self:halign(0):valign(0):zoomto(W, H):diffuse(color("#101014")):diffusealpha(0.94)
		end,
	},
	Def.Quad {
		InitCommand = function(self)
			self:halign(0):valign(0):zoomto(W, 1):diffuse(ACCENT)
		end,
	},
	Def.Quad { -- column lines
		InitCommand = function(self)
			self:halign(0):valign(0):xy(CW, HEAD):zoomto(1, H - HEAD):diffuse(DIM):diffusealpha(0.6)
		end,
	},
	Def.Quad {
		InitCommand = function(self)
			self:halign(0):valign(0):xy(W - PW, HEAD):zoomto(1, H - HEAD):diffuse(DIM):diffusealpha(0.6)
		end,
	},
	Def.Quad {
		InitCommand = function(self)
			self:halign(0):valign(0):xy(0, HEAD):zoomto(W, 1):diffuse(DIM):diffusealpha(0.6)
		end,
	},
	LoadFont("Common Normal") .. {
		Name = "Header",
		InitCommand = function(self)
			self:halign(0):valign(0.5):xy(MX, HEAD / 2 + 1):zoom(ZOOM + 0.05):maxwidth((MW - 40) / (ZOOM + 0.05))
		end,
	},
	LoadFont("Common Normal") .. {
		InitCommand = function(self)
			self:halign(0):valign(0.5):xy(6, HEAD / 2 + 1):zoom(ZOOM):diffuse(ACCENT):settext("CHAT")
		end,
	},
	LoadFont("Common Normal") .. {
		InitCommand = function(self)
			self:halign(1):valign(0.5):xy(W - 6, HEAD / 2 + 1):zoom(ZOOM - 0.05):diffuse(DIM)
				:settext("Tab: next channel   Esc: close")
		end,
	},
	LoadFont("Common Normal") .. {
		Name = "ScrollHint",
		InitCommand = function(self)
			self:halign(1):valign(0.5):xy(MX + MW, HEAD + 8):zoom(ZOOM - 0.05):diffuse(REQUEST)
				:settext("scrolled up - PgDn / wheel"):visible(false)
		end,
	},
	-- input box
	Def.Quad {
		InitCommand = function(self)
			self:halign(0):valign(0):xy(MX, H - 21):zoomto(MW, 16):diffuse(color("#24242c"))
		end,
	},
	LoadFont("Common Normal") .. {
		Name = "Input",
		InitCommand = function(self)
			self:halign(0):valign(0.5):xy(MX + 4, H - 13):zoom(ZOOM)
		end,
	},
	Def.Quad {
		Name = "Caret",
		InitCommand = function(self)
			self:halign(0):valign(0.5):xy(MX + 4, H - 13):zoomto(1, 10):diffuse(WHITE)
				:diffuseblink():effectcolor1(color("1,1,1,1")):effectcolor2(color("1,1,1,0")):effectperiod(1)
		end,
	},
	-- invisible, measures text for wrapping
	LoadFont("Common Normal") .. {
		InitCommand = function(self)
			meas = self
			self:zoom(ZOOM):visible(false)
		end,
	},
}

for i = 1, NMSG do
	p[#p + 1] = LoadFont("Common Normal") .. {
		InitCommand = function(self)
			msgRows[i] = self
			self:halign(0):valign(0.5):xy(MX, HEAD + 6 + (i - 0.5) * LINE):zoom(ZOOM)
				:maxwidth(MW / ZOOM)
		end,
	}
end

for i = 1, NROW do
	local y = HEAD + 3 + (i - 0.5) * ROW
	p[#p + 1] = Def.Quad {
		InitCommand = function(self)
			chanBgs[i] = self
			self:halign(0):valign(0.5):xy(2, y):zoomto(CW - 4, ROW - 1):diffuse(ACCENT):diffusealpha(0.35)
				:visible(false)
		end,
	}
	-- invisible hit box, so every row can be clicked (the quad above only shows on the open one)
	p[#p + 1] = Def.Quad {
		InitCommand = function(self)
			chanHits[i] = self
			self:halign(0):valign(0.5):xy(2, y):zoomto(CW - 4, ROW - 1):diffusealpha(0)
		end,
	}
	p[#p + 1] = LoadFont("Common Normal") .. {
		InitCommand = function(self)
			chanRows[i] = self
			self:halign(0):valign(0.5):xy(8, y):zoom(ZOOM):maxwidth((CW - 14) / ZOOM)
		end,
	}
	p[#p + 1] = Def.ActorFrame {
		InitCommand = function(self)
			self:xy(W - PW, y)
		end,
		Def.Quad {
			InitCommand = function(self)
				pplBgs[i] = self
				self:halign(0):valign(0.5):x(1):zoomto(PW - 2, ROW - 1):diffusealpha(0)
			end,
		},
		Def.Quad {
			InitCommand = function(self)
				pplDots[i] = self
				self:xy(8, 0):zoomto(4, 4):visible(false)
			end,
		},
		LoadFont("Common Normal") .. {
			InitCommand = function(self)
				pplRows[i] = self
				self:halign(0):valign(0.5):x(14):zoom(ZOOM):maxwidth((PW - 20) / ZOOM)
			end,
		},
	}
end

t[#t + 1] = p

-- R.askLogin waits a moment between the nick and the password boxes
t[#t + 1] = Def.Actor {
	InitCommand = function(self)
		stepper = self
	end,
	BMSLoginStep2Command = function(self)
		if R and R.step2 then
			R.step2()
		end
	end,
}

-- toast for new messages while the panel is closed
t[#t + 1] = Def.ActorFrame {
	Name = "Toast",
	InitCommand = function(self)
		self:xy(SCREEN_WIDTH - 8, SCREEN_HEIGHT - 8):diffusealpha(0)
	end,
	BMSChatMessageMessageCommand = function(self, params)
		if open then
			return
		end
		local title = params.dm and ("Message from " .. params.from) or
			params.room and ("Room " .. params.room .. "  " .. params.from) or ("#Global  " .. params.from)
		if (params.more or 0) > 0 then
			title = title .. string.format("  (+%d)", params.more)
		end
		self:GetChild("Title"):settext(title)
		self:GetChild("Body"):settext(params.body)
		self:GetChild("Hint"):visible(canOpenOn(screenName))
		self:stoptweening():linear(0.15):diffusealpha(1):sleep(params.dm and 6 or 4):linear(0.4):diffusealpha(0)
	end,
	Def.Quad {
		InitCommand = function(self)
			self:halign(1):valign(1):zoomto(TOAST_W, 34):diffuse(color("#101014")):diffusealpha(0.9)
		end,
	},
	Def.Quad {
		InitCommand = function(self)
			self:halign(1):valign(1):x(-TOAST_W + 2):zoomto(2, 34):diffuse(ACCENT)
		end,
	},
	LoadFont("Common Normal") .. {
		Name = "Title",
		InitCommand = function(self)
			self:halign(0):valign(0.5):xy(-TOAST_W + 8, -25):zoom(ZOOM):diffuse(ACCENT)
				:maxwidth((TOAST_W - 50) / ZOOM)
		end,
	},
	LoadFont("Common Normal") .. {
		Name = "Hint",
		InitCommand = function(self)
			self:halign(1):valign(0.5):xy(-6, -25):zoom(ZOOM - 0.05):diffuse(DIM):settext("T: open")
		end,
	},
	LoadFont("Common Normal") .. {
		Name = "Body",
		InitCommand = function(self)
			self:halign(0):valign(0.5):xy(-TOAST_W + 8, -11):zoom(ZOOM):diffuse(WHITE)
				:maxwidth((TOAST_W - 14) / ZOOM)
		end,
	},
}

-- In fullscreen the theme draws its own mouse pointer (TOOLTIP in _cursor.lua)
-- in the top screen's overlay, which sits under this overlay screen, so the
-- open panel and the toast hid it. Draw the same pointer again on top.
t[#t + 1] = Def.ActorFrame {
	InitCommand = function(self)
		-- the frame stays visible so this runs every frame, the quad shows only when needed
		self:SetUpdateFunction(function(f)
			local q = f:GetChild("Pointer")
			-- same rule as _cursor.lua: the theme pointer is shown in exclusive fullscreen
			local fullscreen = not PREFSMAN:GetPreference("Windowed") and
				not PREFSMAN:GetPreference("FullscreenIsBorderlessWindow")
			local toast = f:GetParent():GetChild("Toast")
			local show = fullscreen and (open or toast:GetDiffuseAlpha() > 0)
			q:visible(show)
			if show then
				q:xy(INPUTFILTER:GetMouseX(), INPUTFILTER:GetMouseY())
			end
		end)
	end,
	Def.Quad {
		Name = "Pointer",
		InitCommand = function(self)
			self:rotationz(45):zoomto(5, 5):visible(false)
		end,
	},
}

return t
