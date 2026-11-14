-- Live spectating through the ranking site: watch a friend's play as it
-- happens, with their scroll speed, lane option, gauge, noteskin and lane
-- cover. Click their name in the chat (T) and pick Spectate, or /spec nick.
--
-- The player's side: while a song is played, the engine keeps what the player
-- presses (NSMAN:TakeLiveEvents) and this file sends it to
-- /api/game/live/push about once a second while someone watches (every 8
-- seconds otherwise, only to learn whether someone does).
--
-- The spectator's side: waits on song select for the player's next song,
-- loads the same chart (ScreenSelectMusic:StartLiveSpectate) into
-- ScreenGameplaySpectate and feeds it the presses as they come
-- (NSMAN:FeedLiveEvents). The spectator runs a few seconds behind the player.
-- After the song it is back on song select waiting for the next one.
--
-- S.update(screenName) is called by the chat overlay (ScreenBMSChat overlay),
-- which runs on every screen, also during songs.

BMSSpectate = BMSSpectate or {}
local S = BMSSpectate

local PUSH_WATCHED = 1.0 -- seconds between pushes while someone watches
local PUSH_ALONE = 8.0 -- ... and while nobody does
local PULL_WAIT = 1.0 -- spectator: looking for the next song
local PULL_WATCH = 0.5 -- spectator: in the song
local JOIN_MAX_SECONDS = 10 -- a song further in than this is skipped, the next one is watched
local MAX_LINES = 3000 -- events in one push

local function available()
	return NSMAN ~= nil and NSMAN.SetLiveBroadcast ~= nil and DLMAN ~= nil and DLMAN.BMSRequest ~= nil
end

local function loggedIn()
	return available() and DLMAN:BMSIsLoggedIn()
end

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

local function lines(body)
	local out = {}
	for _, l in ipairs(split((body or ""):gsub("\r", ""), "\n")) do
		if l ~= "" then
			out[#out + 1] = l
		end
	end
	return out
end

local function info(text)
	if BMSChat and BMSChat.info then
		BMSChat.info(text)
	end
	MESSAGEMAN:Broadcast("BMSChatMessage", {from = "", body = text, room = "Spectate", more = 0})
end

local function musicSeconds()
	local ok, t = pcall(function()
		return GAMESTATE:GetSongPosition():GetMusicSeconds()
	end)
	return ok and t or 0
end

local function isGameplay(name)
	return name:find("Gameplay") ~= nil and name:find("SyncMachine") == nil
end

-- --------------------------------------------------------------- the player

-- B: the stream of the song being played (nil between songs)
local B = nil
S.watchers = 0 -- shown in the corner during a song

local function lastWords(stream)
	-- the screen is gone: what is left goes out with the end mark
	stream.events = stream.events or {}
	for _, l in ipairs(split(NSMAN:TakeLiveEvents(), "\n")) do
		if l ~= "" then
			stream.events[#stream.events + 1] = l
		end
	end
end

-- one request at a time per stream; "final" also sends the end mark
local function push(stream, final)
	if stream.pushing or not stream.id then
		return
	end
	stream.pushing = true
	stream.lastPush = GetTimeSinceStart()
	local from = stream.sent
	-- nobody watching: only the time (and at the end the end mark) goes out
	local upto = stream.watchers > 0 and math.min(#stream.events, from + MAX_LINES) or from
	local params = {id = stream.id, from = tostring(from), t = string.format("%.2f", stream.t)}
	if upto > from then
		params.ev = table.concat(stream.events, "\n", from + 1, upto)
	end
	local ending = final and (upto == #stream.events or stream.watchers == 0)
	if ending then
		params["end"] = stream.ended or "quit"
	end
	DLMAN:BMSRequest("POST", "/api/game/live/push", params, function(code, body)
		stream.pushing = false
		local f = split((lines(body)[1] or ""), "\t")
		if code == 200 and f[1] == "OK" then
			stream.watchers = tonumber(f[2]) or 0
			stream.sent = math.min(tonumber(f[3]) or upto, #stream.events)
			if ending then
				stream.done = true
			end
		elseif f[1] == "ERR" then
			-- the site lost the stream (it restarted): begin it again
			stream.id = nil
			stream.sent = 0
		end
		if stream == B then
			S.watchers = stream.watchers
		end
	end, true)
end

local function start(stream)
	if stream.starting then
		return
	end
	stream.starting = true
	DLMAN:BMSRequest("POST", "/api/game/live/start", stream.meta, function(code, body)
		stream.starting = false
		local f = split((lines(body)[1] or ""), "\t")
		if code == 200 and f[1] == "OK" then
			stream.id = f[2]
			stream.watchers = tonumber(f[3]) or 0
			stream.sent = 0
			stream.lastPush = -100
			if stream == B then
				S.watchers = stream.watchers
			end
		else
			stream.retryAt = GetTimeSinceStart() + 10
		end
	end, true)
end

local function metaOfThisPlay()
	local steps = GAMESTATE:GetCurrentSteps()
	local song = GAMESTATE:GetCurrentSong()
	if not steps or not song then
		return nil
	end
	local po = GAMESTATE:GetPlayerState():GetPlayerOptionsString("ModsLevel_Preferred")
	local rate = GAMESTATE:GetSongOptionsObject("ModsLevel_Current"):MusicRate()
	local pc = playerConfig and playerConfig:get_data(pn_to_profile_slot(PLAYER_1)) or {}
	return {
		chartkey = steps:GetChartKey(),
		title = song:GetDisplayMainTitle(),
		artist = song:GetDisplayArtist(),
		diff = ToEnumShortString(steps:GetDifficulty()),
		meter = tostring(steps:GetMeter()),
		rate = string.format("%.3f", rate),
		mods = po,
		rng = tostring(NSMAN:GetStageSeed()),
		cover = tostring(pc.LaneCover or 0),
		coverh = tostring(pc.LaneCoverHeight or 0),
	}
end

local lastGameplay = nil -- the gameplay screen the current stream belongs to
local ending = {} -- streams of songs that ended, still sending their tail

local function playerUpdate(top, name)
	-- the engine only keeps presses while this is on (and only of real plays)
	local want = loggedIn()
	if want ~= S.broadcastOn then
		S.broadcastOn = want
		NSMAN:SetLiveBroadcast(want)
	end
	if not want then
		B = nil
		return
	end
	local playing = top ~= nil and isGameplay(name) and GAMESTATE:GetGameplayMode() == "GameplayMode_Normal" and
		not NSMAN:IsLiveSpectating()

	-- the song ended, was quit or restarted (a restart is a new screen)
	if B and (not playing or top ~= lastGameplay) then
		lastWords(B)
		B.ended = name:find("Evaluation") and "done" or "quit"
		B.final = true
		ending[#ending + 1] = B
		B = nil
		S.watchers = 0
	end

	if playing and not B then
		local meta = metaOfThisPlay()
		if meta then
			lastGameplay = top
			B = {meta = meta, events = {}, sent = 0, watchers = 0, t = 0, lastPush = -100}
			NSMAN:TakeLiveEvents() -- presses from before this song are not part of it
			start(B)
		end
	end

	if B then
		B.t = musicSeconds()
		for _, l in ipairs(split(NSMAN:TakeLiveEvents(), "\n")) do
			if l ~= "" then
				B.events[#B.events + 1] = l
			end
		end
		if not B.id then
			if not B.starting and GetTimeSinceStart() >= (B.retryAt or 0) then
				start(B)
			end
		elseif GetTimeSinceStart() - B.lastPush >= (B.watchers > 0 and PUSH_WATCHED or PUSH_ALONE) then
			push(B, false)
		end
	end

	for i = #ending, 1, -1 do
		local e = ending[i]
		if e.done or not e.id or (e.tries or 0) > 5 then
			table.remove(ending, i)
		elseif not e.pushing then
			e.tries = (e.tries or 0) + 1
			push(e, true)
		end
	end
end

-- ------------------------------------------------------------ the spectator

S.who = nil -- the player followed, nil when not spectating
S.phase = nil -- "waiting" or "watching"
local W = {} -- what the spectator knows about the stream it follows

local savedCover = nil -- the spectator's own lane cover, while theirs is shown

local function useCover(meta)
	if not playerConfig then
		return
	end
	local pc = playerConfig:get_data(pn_to_profile_slot(PLAYER_1))
	if not savedCover then
		savedCover = {pc.LaneCover, pc.LaneCoverHeight}
	end
	pc.LaneCover = tonumber(meta.cover) or pc.LaneCover
	pc.LaneCoverHeight = tonumber(meta.coverh) or pc.LaneCoverHeight
end

local function restoreCover()
	if savedCover and playerConfig then
		local pc = playerConfig:get_data(pn_to_profile_slot(PLAYER_1))
		pc.LaneCover, pc.LaneCoverHeight = savedCover[1], savedCover[2]
	end
	savedCover = nil
end

function S.isFollowing(name)
	return S.who ~= nil and string.lower(S.who) == string.lower(name or "")
end

function S.start(name)
	if not available() then
		info("this build cannot spectate (it needs the new game version)")
		return
	end
	if not loggedIn() then
		info("log in to the ranking site first (Enter in the chat)")
		return
	end
	if string.lower(name) == string.lower(DLMAN:BMSGetName() or "") then
		info("you cannot spectate yourself")
		return
	end
	S.who = name
	S.phase = "waiting"
	W = {seen = {}}
	info("spectating " .. name .. ": you join from their next song, wait on song select. /unspec stops")
	MESSAGEMAN:Broadcast("BMSSpectateChanged")
end

function S.stop(quiet)
	if not S.who then
		return
	end
	local who = S.who
	S.who = nil
	S.phase = nil
	W = {}
	if NSMAN:IsLiveSpectating() then
		NSMAN:StopLiveSpectate()
	end
	restoreCover()
	if loggedIn() then
		DLMAN:BMSRequest("POST", "/api/game/live/stop", {who = who}, function() end, true)
	end
	if not quiet then
		info("stopped spectating " .. who)
	end
	MESSAGEMAN:Broadcast("BMSSpectateChanged")
end

-- the banner text, "" when not spectating
function S.bannerText(name)
	if not S.who then
		return ""
	end
	if S.phase == "watching" and isGameplay(name or "") then
		return "SPECTATING " .. S.who
	end
	local what = W.title and ("  -  now playing " .. W.title) or ""
	if name ~= "ScreenSelectMusic" then
		return "Spectating " .. S.who .. what .. "  (go to song select to watch the next song, /unspec stops)"
	end
	return "Spectating " .. S.who .. what .. "  (their next song starts here, /unspec stops)"
end

-- read one pull answer: header fields, meta table, event lines
local function readPull(body)
	local ls = lines(body)
	local h = split(ls[1] or "", "\t")
	local meta, events = {}, {}
	for i = 2, #ls do
		local kind, rest = ls[i]:match("^(%a)\t(.*)$")
		if kind == "M" then
			local k, v = rest:match("^([^\t]*)\t(.*)$")
			if k then
				meta[k] = v
			end
		elseif kind == "E" then
			events[#events + 1] = rest
		end
	end
	return {
		ok = h[1] == "OK",
		err = h[1] == "ERR" and (h[2] or "error") or nil,
		id = h[2] or "",
		ended = h[3] or "",
		total = tonumber(h[4]) or 0,
		t = tonumber(h[5]) or 0,
		startedAgo = (tonumber(h[6]) or 0) / 1000,
		touchedAgo = (tonumber(h[7]) or 0) / 1000,
		name = h[8],
	}, meta, events
end

-- song select: the player started a song we can join
local function tryJoin(top, p, meta)
	if W.seen[p.id] then
		return
	end
	W.seen[p.id] = true
	local ck = meta.chartkey or ""
	local steps = SONGMAN:GetStepsByChartKey(ck)
	local title = (meta.title or "?") .. " [" .. (meta.diff or "?") .. " " .. (meta.meter or "") .. "]"
	if not steps then
		info(S.who .. " is playing " .. title .. ", you do not have that chart")
		return
	end
	if top.StartLiveSpectate == nil then
		info("this build cannot spectate (it needs the new game version)")
		return
	end
	if not NSMAN:StartLiveSpectate(p.name or S.who, ck, tonumber(meta.rate) or 1, 0, 0, tonumber(meta.rng) or 0,
		meta.mods or "") then
		info("could not load " .. title)
		return
	end
	useCover(meta)
	if not top:StartLiveSpectate(steps) then
		NSMAN:StopLiveSpectate()
		restoreCover()
		info("could not pick " .. title .. " on the wheel (is a search or a filter hiding it?)")
		return
	end
	if BMSChat and BMSChat.closePanel then
		BMSChat.closePanel()
	end
	W.id = p.id
	W.feedWho = p.name or S.who
	W.after = 0
	W.endT = nil
	W.autoBack = false
	S.phase = "watching"
	MESSAGEMAN:Broadcast("BMSSpectateChanged")
end

local function pull(top, name)
	W.pulling = true
	W.lastPull = GetTimeSinceStart()
	local watching = S.phase == "watching" and W.id
	local params = {who = S.who}
	if watching then
		params.id = W.id
		params.after = tostring(W.after)
	end
	local who = S.who
	DLMAN:BMSRequest("POST", "/api/game/live/pull", params, function(code, body)
		W.pulling = false
		if S.who ~= who then
			return -- stopped or switched meanwhile
		end
		local p, meta, events = readPull(body)
		if p.err then
			info(p.err)
			S.stop(true)
			return
		end
		if code ~= 200 or not p.ok then
			return -- try again on the next pull
		end
		local nowTop = SCREENMAN:GetTopScreen()
		local nowName = nowTop and nowTop:GetName() or ""

		if S.phase == "watching" then
			if p.id ~= W.id then
				-- they quit and started something else: leave this song
				W.endT = -1000
			else
				if #events > 0 then
					NSMAN:FeedLiveEvents(W.feedWho, table.concat(events, "\n"))
					W.after = W.after + #events
				end
				if p.ended == "quit" and W.after >= p.total then
					W.endT = -1000
				elseif p.ended ~= "" and W.after >= p.total then
					W.endT = p.t
				end
			end
			return
		end

		-- waiting for the next song
		if p.id ~= "" and p.ended == "" and p.touchedAgo < 20 then
			W.title = meta.title or W.title
		elseif p.id == "" or p.ended ~= "" then
			W.title = nil
		end
		if p.id ~= "" and p.ended == "" and next(meta) ~= nil then
			W.meta = W.meta or {}
			W.meta[p.id] = meta
		end
		local m = W.meta and W.meta[p.id]
		if p.id ~= "" and p.ended == "" and m and p.t < JOIN_MAX_SECONDS and p.startedAgo < 30 and
			nowName == "ScreenSelectMusic" and nowTop then
			tryJoin(nowTop, p, m)
		elseif p.id ~= "" and m and not W.seen[p.id] and p.ended == "" and p.t >= JOIN_MAX_SECONDS then
			-- already well into it: wait for the next one
			W.seen[p.id] = true
		end
	end, true)
end

local function spectatorUpdate(top, name)
	if not S.who then
		return
	end
	if not loggedIn() then
		S.stop(true)
		return
	end
	-- the song is over for the spectator too (or never started): wait again
	if S.phase == "watching" and not isGameplay(name) and name ~= "ScreenStageInformation" and
		not NSMAN:IsLiveSpectating() then
		S.phase = "waiting"
		W.id = nil
		restoreCover()
		MESSAGEMAN:Broadcast("BMSSpectateChanged")
	end
	-- the player's song ended (failed early) or was quit: leave it too
	-- (only while notes are left: after the last one the song ends by itself)
	if S.phase == "watching" and W.endT and name == "ScreenGameplaySpectate" and top and not W.autoBack then
		local song = GAMESTATE:GetCurrentSong()
		local now = musicSeconds()
		if song and now < song:GetLastSecond() and (W.endT < -999 or now > W.endT + 3) then
			W.autoBack = true
			top:begin_backing_out()
		end
	end
	local every = S.phase == "watching" and PULL_WATCH or PULL_WAIT
	if not W.pulling and GetTimeSinceStart() - (W.lastPull or -100) >= every then
		pull(top, name)
	end
end

-- ScreenGameplaySpectate is done (LiveSpectateFinished from the engine)
function S.finished(backedOut)
	restoreCover()
	if backedOut and not W.autoBack and S.who then
		-- Esc during the song: the spectator had enough
		S.stop()
		return
	end
	if S.who then
		S.phase = "waiting"
		W.id = nil
		MESSAGEMAN:Broadcast("BMSSpectateChanged")
	end
end

-- ------------------------------------------------------------------ both

function S.update(name)
	if not available() then
		return
	end
	local top = SCREENMAN:GetTopScreen()
	playerUpdate(top, name or "")
	spectatorUpdate(top, name or "")
end

-- song select goes on to ScreenGameplaySpectate when spectating
-- (the fallback ToGameplay knows practice and replays only)
if not S.baseToGameplay then
	S.baseToGameplay = ToGameplay
end
function ToGameplay()
	if GAMESTATE:GetGameplayMode() == "GameplayMode_Spectate" then
		return "ScreenGameplaySpectate"
	end
	return S.baseToGameplay()
end
