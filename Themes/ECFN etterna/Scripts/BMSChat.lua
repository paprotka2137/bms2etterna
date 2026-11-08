-- BMS 7k ranking site chat: global channel, private messages (DMs), friends
-- and who is online. Uses the same in-game login as BMSRanking.lua. The game
-- polls /api/game/chat/poll every few seconds (also during songs, the C++ side
-- lets these answers through), the panel itself is
-- BGAnimations/ScreenBMSChat overlay.lua (opens with T).
--
-- A multiplayer room adds one more channel, "#room": its messages go through
-- the multiplayer connection (NSMAN), not the site, so they cost no polling.
--
-- Messages broadcast:
--   BMSChatUpdated              anything changed (messages, people, errors)
--   BMSChatMessage {from, body, dm}  a new message from someone else

BMSChat = BMSChat or {}
local C = BMSChat

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
	local text = (body or ""):gsub("\r", "")
	for _, l in ipairs(split(text, "\n")) do
		if l ~= "" then
			lines[#lines + 1] = split(l, "\t")
		end
	end
	return lines
end

local function errorOf(status, lines)
	if status == 0 then
		return "no connection to the ranking site"
	end
	if lines[1] and lines[1][1] == "ERR" then
		return lines[1][2] or "error"
	end
	return "site error " .. tostring(status)
end

-- Windows 1252 bytes 0x80-0x9F as code points (the rest of the range is Latin-1)
local CP1252 = {
	[0x80] = 0x20AC, [0x82] = 0x201A, [0x83] = 0x0192, [0x84] = 0x201E, [0x85] = 0x2026,
	[0x86] = 0x2020, [0x87] = 0x2021, [0x88] = 0x02C6, [0x89] = 0x2030, [0x8A] = 0x0160,
	[0x8B] = 0x2039, [0x8C] = 0x0152, [0x8E] = 0x017D, [0x91] = 0x2018, [0x92] = 0x2019,
	[0x93] = 0x201C, [0x94] = 0x201D, [0x95] = 0x2022, [0x96] = 0x2013, [0x97] = 0x2014,
	[0x98] = 0x02DC, [0x99] = 0x2122, [0x9A] = 0x0161, [0x9B] = 0x203A, [0x9C] = 0x0153,
	[0x9E] = 0x017E, [0x9F] = 0x0178,
}

local function encode(cp)
	if cp < 0x80 then
		return string.char(cp)
	elseif cp < 0x800 then
		return string.char(0xC0 + math.floor(cp / 0x40), 0x80 + cp % 0x40)
	end
	return string.char(0xE0 + math.floor(cp / 0x1000), 0x80 + math.floor(cp / 0x40) % 0x40, 0x80 + cp % 0x40)
end

-- one valid UTF-8 character at position i, returns its length or nil
local function utf8At(s, i)
	local c = s:byte(i)
	local n
	if c < 0x80 then
		return 1
	elseif c >= 0xC2 and c <= 0xDF then
		n = 2
	elseif c >= 0xE0 and c <= 0xEF then
		n = 3
	elseif c >= 0xF0 and c <= 0xF4 then
		n = 4
	else
		return nil
	end
	for k = i + 1, i + n - 1 do
		local d = s:byte(k)
		if not d or d < 0x80 or d > 0xBF then
			return nil
		end
	end
	return n
end

-- Any text from outside (the clipboard, the site) as valid UTF-8 without
-- control characters. Bytes that are not UTF-8 are read as Windows 1252,
-- which is what the clipboard gave on Windows before the engine asked for
-- Unicode text. Cut to at most `max` bytes on a character boundary.
function C.toUTF8(s, max)
	s = tostring(s or "")
	local out = {}
	local len = 0
	local i = 1
	while i <= #s do
		local n = utf8At(s, i)
		local ch
		if n then
			ch = s:sub(i, i + n - 1)
		else
			local b = s:byte(i)
			ch = encode(CP1252[b] or (b >= 0xA0 and b) or 0xFFFD)
			n = 1
		end
		if ch:byte(1) < 0x20 or ch:byte(1) == 0x7F then
			ch = " "
		end
		if max and len + #ch > max then
			break
		end
		out[#out + 1] = ch
		len = len + #ch
		i = i + n
	end
	return table.concat(out)
end

local function available()
	return DLMAN ~= nil and DLMAN.BMSRequest ~= nil
end

function C.loggedIn()
	return available() and DLMAN:BMSIsLoggedIn()
end

function C.myName()
	return available() and DLMAN:BMSGetName() or ""
end

-- everything the chat knows, dropped on login/logout
function C.reset()
	C.channels = {} -- key: "" = global, lowercase nick = DM; {name, msgs, unread, last}
	C.channels[""] = {name = "Global", msgs = {}, unread = 0, last = 0}
	C.people = {} -- {name, rel, online, status}
	C.onlineCount = 0
	C.current = ""
	C.cursor = 0
	C.first = true
	C.polling = false
	C.lastPoll = -100
	C.err = nil
	C.history = {}
	C.room = nil
end
if not C.channels then
	C.reset()
end

local function channel(key, name)
	local ch = C.channels[key]
	if not ch then
		ch = {name = name or key, msgs = {}, unread = 0, last = 0}
		C.channels[key] = ch
	end
	if name and name ~= "" then
		ch.name = name -- the site's spelling of the nick
	end
	return ch
end

-- global first, then the multiplayer room, then DMs, newest conversation first
function C.channelList()
	local list = {}
	for key, ch in pairs(C.channels) do
		if key ~= "" and key ~= C.ROOM then
			list[#list + 1] = {key = key, ch = ch}
		end
	end
	table.sort(list, function(a, b)
		if a.ch.last ~= b.ch.last then
			return a.ch.last > b.ch.last
		end
		return a.key < b.key
	end)
	if C.channels[C.ROOM] then
		table.insert(list, 1, {key = C.ROOM, ch = C.channels[C.ROOM]})
	end
	table.insert(list, 1, {key = "", ch = C.channels[""]})
	return list
end

-- ---------------------------------------------------------- multiplayer room
C.ROOM = "#room"

-- the room the multiplayer connection is in, "" when none
local function currentRoom()
	if NSMAN == nil or not IsNetSMOnline() or not IsSMOnlineLoggedIn() then
		return ""
	end
	return NSMAN:GetCurrentRoomName() or ""
end

-- adds the room channel when a room is entered (and opens it), drops it when
-- the room is left. Called often by the chat overlay.
function C.syncRoom()
	local room = currentRoom()
	if room == (C.room or "") then
		return
	end
	C.room = room
	C.channels[C.ROOM] = nil
	if room ~= "" then
		C.channels[C.ROOM] = {name = room, msgs = {}, unread = 0, last = 0, room = true}
		C.current = C.ROOM
	elseif C.current == C.ROOM then
		C.current = ""
	end
	MESSAGEMAN:Broadcast("BMSChatUpdated")
end

function C.inRoom()
	return C.channels[C.ROOM] ~= nil
end

-- a line from the multiplayer server (the engine's "Chat" message):
-- type 1 = room ("nick: text" or "*** notice"), type 0 = lobby notices
function C.roomMessage(params)
	C.syncRoom()
	local ch = C.channels[C.ROOM]
	local msg = params.msg or ""
	local notice = msg:match("^%*%*%* (.*)$")
	if params.type == 1 and ch and params.tab == ch.name then
		local m
		if notice then
			m = {id = 0, from = "", body = notice, t = os.time(), info = true}
		else
			local from, body = msg:match("^(.-): (.*)$")
			m = {id = 0, from = from or "?", body = body or msg, t = os.time()}
		end
		ch.msgs[#ch.msgs + 1] = m
		if #ch.msgs > 300 then
			table.remove(ch.msgs, 1)
		end
		local mine = m.from ~= "" and string.lower(m.from) == string.lower(NSMAN:GetLoggedInUsername() or "")
		if not mine and not (C.panelOpen and C.current == C.ROOM) then
			if not m.info then
				ch.unread = ch.unread + 1
			end
			MESSAGEMAN:Broadcast("BMSChatMessage", {from = m.info and "" or m.from, body = m.body, room = ch.name, more = 0})
		end
		MESSAGEMAN:Broadcast("BMSChatUpdated")
	elseif params.type == 0 and notice then
		-- lobby notices like "wrong room password": shown where the player looks
		local target = ch or C.channels[C.current] or C.channels[""]
		target.msgs[#target.msgs + 1] = {id = 0, from = "", body = notice, t = os.time(), info = true}
		MESSAGEMAN:Broadcast("BMSChatMessage", {from = "", body = notice, room = "Multiplayer", more = 0})
		MESSAGEMAN:Broadcast("BMSChatUpdated")
	end
end

local function sendRoom(text)
	NSMAN:SendChatMsg(text, 1, C.room or "")
end

function C.totalUnread()
	local n = 0
	for _, ch in pairs(C.channels) do
		n = n + ch.unread
	end
	return n
end

function C.open(key, name)
	key = string.lower(key or "")
	local ch = channel(key, name)
	if key ~= "" and ch.last == 0 then
		ch.last = os.time() -- so a new DM shows near the top of the list
	end
	C.current = key
	ch.unread = 0
	MESSAGEMAN:Broadcast("BMSChatUpdated")
end

-- a local line (help, errors) in the current channel, not sent anywhere
function C.info(text)
	local ch = C.channels[C.current] or C.channels[""]
	ch.msgs[#ch.msgs + 1] = {id = 0, from = "", body = text, t = os.time(), info = true}
	MESSAGEMAN:Broadcast("BMSChatUpdated")
end

local MAX_KEEP = 300

local function addMessage(f, me, panelOpen)
	local id = tonumber(f[2]) or 0
	local dm = f[3] == "D"
	local from, to = f[4] or "?", f[5] or ""
	local key, name = "", "Global"
	if dm then
		if string.lower(from) == me then
			key, name = string.lower(to), to
		else
			key, name = string.lower(from), from
		end
	end
	local ch = channel(key, name)
	for i = #ch.msgs, math.max(1, #ch.msgs - 20), -1 do
		if ch.msgs[i].id == id then
			return nil -- already have it
		end
	end
	local m = {id = id, dm = dm, from = C.toUTF8(from), to = to, t = tonumber(f[6]) or os.time(), body = C.toUTF8(f[7])}
	ch.msgs[#ch.msgs + 1] = m
	if #ch.msgs > MAX_KEEP then
		table.remove(ch.msgs, 1)
	end
	if dm then
		ch.last = math.max(ch.last, m.t)
	end
	local mine = string.lower(from) == me
	if not mine and not C.first and not (panelOpen and C.current == key) then
		ch.unread = ch.unread + 1
	end
	if not mine and not C.first then
		return m
	end
	return nil
end

-- status: what the player is doing, shown to friends. panelOpen: the chat
-- panel is open (messages in the open channel do not count as unread)
function C.poll(status, panelOpen)
	if not C.loggedIn() or C.polling then
		return
	end
	C.polling = true
	C.lastPoll = GetTimeSinceStart()
	local who = C.myName()
	DLMAN:BMSRequest("POST", "/api/game/chat/poll", {after = tostring(C.cursor), status = status or ""}, function(code, body)
		C.polling = false
		C.lastPoll = GetTimeSinceStart()
		if who ~= C.myName() then
			return -- logged in as someone else meanwhile
		end
		local lines = parse(body)
		if code ~= 200 or not lines[1] or lines[1][1] ~= "OK" then
			C.err = errorOf(code, lines)
			MESSAGEMAN:Broadcast("BMSChatUpdated")
			return
		end
		C.err = nil
		C.cursor = tonumber(lines[1][2]) or C.cursor
		C.onlineCount = tonumber(lines[1][3]) or 0
		local me = string.lower(lines[1][4] or who)
		local fresh = {}
		local people = {}
		for i = 2, #lines do
			local f = lines[i]
			if f[1] == "M" then
				local m = addMessage(f, me, C.panelOpen)
				if m then
					fresh[#fresh + 1] = m
				end
			elseif f[1] == "P" then
				people[#people + 1] = {name = f[2] or "?", rel = f[3] or "", online = f[4] == "1", status = f[5] or ""}
			end
		end
		C.people = people
		C.first = false
		MESSAGEMAN:Broadcast("BMSChatUpdated")
		-- toasts: only the last few if a lot came at once
		for i = math.max(1, #fresh - 2), #fresh do
			local m = fresh[i]
			MESSAGEMAN:Broadcast("BMSChatMessage", {from = m.from, body = m.body, dm = m.dm, more = #fresh - 1})
		end
	end, true)
end

-- poll again soon (after sending something)
function C.pollSoon()
	C.lastPoll = -100
end

local function send(to, text)
	DLMAN:BMSRequest("POST", "/api/game/chat/send", {to = to, body = text}, function(code, body)
		local lines = parse(body)
		if code ~= 200 or not lines[1] or lines[1][1] ~= "OK" then
			C.info("not sent: " .. errorOf(code, lines))
		end
		C.pollSoon()
	end, true)
end

function C.friend(name, op)
	DLMAN:BMSRequest("POST", "/api/game/chat/friend", {name = name, op = op}, function(code, body)
		local lines = parse(body)
		if code ~= 200 or not lines[1] or lines[1][1] ~= "OK" then
			C.info(errorOf(code, lines))
		elseif op == "remove" then
			C.info((lines[1][3] or name) .. " removed from friends")
		elseif lines[1][2] == "friend" then
			C.info("you and " .. (lines[1][3] or name) .. " are friends now")
		else
			C.info("friend request sent to " .. (lines[1][3] or name))
		end
		C.pollSoon()
	end, true)
end

C.HELP = {
	"Enter sends to the open channel. Tab / Shift+Tab switch channels, Esc closes.",
	"/w nick [message]  private message      /g  back to the global channel",
	"/add nick  add a friend (or accept a request)      /remove nick",
	"In a multiplayer room: /ready, /force, /free, /op nick, /owner nick, /kick nick go to the room.",
	"Click a channel or a player on the right to open it. Mouse wheel / PgUp PgDn scroll.",
}

local function trim(s)
	return (s:gsub("^%s*(.-)%s*$", "%1"))
end

-- the text typed in the box: a command or a message for the open channel
function C.submit(text)
	text = trim(C.toUTF8(text, 300))
	if text == "" then
		return
	end
	table.insert(C.history, text)
	if #C.history > 30 then
		table.remove(C.history, 1)
	end
	if text:sub(1, 1) == "/" then
		local cmd, rest = text:match("^/(%S+)%s*(.*)$")
		cmd = string.lower(cmd or "")
		if cmd == "w" or cmd == "msg" or cmd == "dm" or cmd == "pm" then
			local nick, msg = rest:match("^(%S+)%s*(.*)$")
			if not nick then
				C.info("usage: /w nick [message]")
				return
			end
			C.open(nick, nick)
			if msg ~= "" then
				send(nick, msg)
			end
		elseif cmd == "g" or cmd == "global" or cmd == "all" then
			C.open("")
		elseif cmd == "add" or cmd == "friend" then
			if rest == "" then
				C.info("usage: /add nick")
			else
				C.friend(rest, "add")
			end
		elseif cmd == "remove" or cmd == "unfriend" then
			if rest == "" then
				C.info("usage: /remove nick")
			else
				C.friend(rest, "remove")
			end
		elseif cmd == "help" or cmd == "?" then
			for _, l in ipairs(C.HELP) do
				C.info(l)
			end
			if C.current == C.ROOM then
				sendRoom("/help")
			end
		elseif C.current == C.ROOM then
			-- the room's own commands (/ready, /force ...) are for the server
			sendRoom(text)
		else
			C.info("unknown command /" .. cmd .. ", try /help")
		end
		return
	end
	if C.current == C.ROOM then
		sendRoom(text)
		return
	end
	local ch = C.channels[C.current]
	send(C.current == "" and "" or (ch and ch.name or C.current), text)
end

function C.relOf(name)
	local n = string.lower(name or "")
	for _, p in ipairs(C.people) do
		if string.lower(p.name) == n then
			return p
		end
	end
	return nil
end
