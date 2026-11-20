local showVisualizer = themeConfig:get_data().global.ShowVisualizer

local function input(event)
	-- mouse click events left here to let anything in selectmusic react to them
	if event.DeviceInput.button == "DeviceButton_left mouse button" then 
		if event.type == "InputEventType_Release" then
			MESSAGEMAN:Broadcast("MouseLeftClick")
			MESSAGEMAN:Broadcast("MouseUp", {event = event})
		elseif event.type == "InputEventType_FirstPress" then
			MESSAGEMAN:Broadcast("MouseDown", {event = event})
		end
	elseif event.DeviceInput.button == "DeviceButton_right mouse button" then
		if event.type == "InputEventType_Release" then
			MESSAGEMAN:Broadcast("MouseRightClick")
			MESSAGEMAN:Broadcast("MouseUp", {event = event})
		elseif event.type == "InputEventType_FirstPress" then
			MESSAGEMAN:Broadcast("MouseDown", {event = event})
		end
	end
	return false
end

local hoverAlpha = 0.6

local t = Def.ActorFrame {
	BeginCommand = function(self)
		local s = SCREENMAN:GetTopScreen()
		s:AddInputCallback(input)
		setenv("NewOptions","Main")
	end
}

t[#t + 1] = Def.Actor {
	CodeMessageCommand = function(self, params)
		if params.Name == "AvatarShow" and getTabIndex() == 0 and not SCREENMAN:get_input_redirected(PLAYER_1) then
			SCREENMAN:SetNewScreen("ScreenAssetSettings")
		end
	end,
	OnCommand = function(self)
		inScreenSelectMusic = true
	end,
	EndCommand = function(self)
		inScreenSelectMusic = nil
	end,
}

-- 7k has the ECFN top bar (ecfnsearch.lua) instead of the title, visualizer and sort
local ecfn = hideMSD()
t[#t + 1] = LoadActorWithParams("../_frame", {ecfn = ecfn})
t[#t + 1] = LoadActorWithParams("../_PlayerInfo", {ecfn = ecfn})

if showVisualizer and not ecfn then
	local vis = audioVisualizer:new {
		x = 175,
		y = 30,
		maxHeight = 30,
		freqIntervals = audioVisualizer.multiplyIntervals(audioVisualizer.defaultIntervals, 5),
		color = getMainColor("positive"),
		onBarUpdate = function(self)
			--[
			self:diffusetopedge(getMainColor("frames"))
			self:diffusebottomedge(getMainColor("positive"))
			--]]
			--[[
			self:diffuselowerleft()
			self:diffuseupperleft()
			self:diffuselowerright()
			self:diffuseupperright()
			--]]
		end
	}
	t[#t + 1] = vis
end


if ecfn then
	t[#t + 1] = LoadActor("ecfnsearch")
else
	t[#t + 1] = LoadActor("currentsort")
end
t[#t + 1] = UIElements.TextToolTip(1, 1, "Common Large") .. {
	Name="rando",
	InitCommand = function(self)
		self:xy(5, 32):halign(0):valign(1):zoom(0.55):diffuse(getMainColor("positive"))
		self:settextf("%s:", THEME:GetString("ScreenSelectMusic", "Title"))
		if ecfn then
			-- invisible over the ECFN ":SELECT A MUSIC", clicking it still picks a random song
			self:xy(ecfnX(48), 50 * ecfnScale()):settext("res extensa 0.0.0"):zoom(0.5 * ecfnScale()):diffusealpha(0)
		end
		self.randex = 0
		self.randlist = {}
	end,
	MouseOverCommand = function(self)
		if not ecfn then
			self:diffusealpha(hoverAlpha)
		end
	end,
	MouseOutCommand = function(self)
		if not ecfn then
			self:diffusealpha(1)
		end
	end,
	MouseDownCommand = function(self, params)
		local w = SCREENMAN:GetTopScreen():GetMusicWheel()

		local function newrandsong()
			local t = w:GetSongs()
			if #t == 0 then return nil end
			local random_song = t[math.random(#t)]
			return random_song
		end

		if params.event == "DeviceButton_left mouse button" then
			
			if INPUTFILTER:IsShiftPressed() then
				self.randex = self.randex - 1
				if self.randex < 1 then
					self.randex = 1
					table.insert(self.randlist, 1, newrandsong())
				end
				local randsong = self.randlist[self.randex]

				-- if the last random song wasnt filtered out, we can select it
				-- so end early after jumping to it
				if w:SelectSong(randsong) then
					return
				end
				-- otherwise, just pick a new random song
			end

			self.randex = self.randex + 1
			if self.randex > #self.randlist then
				self.randex = #self.randlist + 1
				table.insert(self.randlist, newrandsong())
			end
			local randsong = self.randlist[self.randex]
			w:SelectSong(randsong)
		end
	end
}

-- 7k: ":RANDOM IN FOLDER" next to ":SELECT A MUSIC", picks a random song from
-- the folder that is open (or under the cursor) on the wheel, with the wheel's
-- filters. Shift+click goes back to the previous pick, like the other one.
if ecfn then
	-- a picture in the same font as the skin's header, made for it
	local dir = THEME:GetCurrentThemeDirectory()
	if dir:sub(1, 1) ~= "/" then
		dir = "/" .. dir
	end
	-- a text link in the top bar, next to the version
	t[#t + 1] = LoadFont(rxFont.normal) .. {
		Name = "randoFolderLabel",
		InitCommand = function(self)
			local s = ecfnScale()
			self:halign(0):xy(ecfnX(330), 36 * s):zoom(rxZoom(rxFont.normal, 16 * s)):settext("Random in folder"):diffuse(rxColor("muted"))
		end,
		RandoHoverMessageCommand = function(self, params)
			self:diffuse(params.on and rxColor("white") or rxColor("muted"))
		end,
	}
	t[#t + 1] = UIElements.QuadButton(1, 1) .. {
		Name = "randoFolder",
		InitCommand = function(self)
			local s = ecfnScale()
			self:halign(0):valign(0):xy(ecfnX(320), 12 * s):zoomto(170 * s, 48 * s):diffusealpha(0)
			self.randex = 0
			self.randlist = {}
			self.group = nil
		end,
		MouseOverCommand = function(self)
			MESSAGEMAN:Broadcast("RandoHover", {on = true})
		end,
		MouseOutCommand = function(self)
			MESSAGEMAN:Broadcast("RandoHover", {on = false})
		end,
		MouseDownCommand = function(self, params)
			if params.event ~= "DeviceButton_left mouse button" then
				return
			end
			local w = SCREENMAN:GetTopScreen():GetMusicWheel()
			local group = w:GetSelectedSection()
			local cur = GAMESTATE:GetCurrentSong()
			if (group == nil or group == "") and cur then
				group = cur:GetGroupName()
			end
			if group == nil or group == "" then
				return
			end
			-- a new folder starts a new history
			if group ~= self.group then
				self.group = group
				self.randex = 0
				self.randlist = {}
			end

			local function newrandsong()
				local songs = w:GetSongsInGroup(group)
				if #songs == 0 then
					-- other sorts name their sections differently, fall back to the pack
					songs = {}
					for _, sg in ipairs(w:GetSongs()) do
						if sg:GetGroupName() == group then
							songs[#songs + 1] = sg
						end
					end
				end
				if #songs == 0 then
					return nil
				end
				local pick = songs[math.random(#songs)]
				if #songs > 1 and pick == cur then
					pick = songs[math.random(#songs)]
				end
				return pick
			end

			if INPUTFILTER:IsShiftPressed() and self.randex > 1 then
				self.randex = self.randex - 1
				if w:SelectSong(self.randlist[self.randex]) then
					return
				end
			end

			local song = newrandsong()
			if song == nil then
				return
			end
			self.randex = #self.randlist + 1
			self.randlist[self.randex] = song
			w:SelectSong(song)
		end,
	}
end

-- clear calc debug view (F5), over everything but the cursor
if ecfn then
	t[#t + 1] = LoadActor("calcdebug")
end
t[#t + 1] = LoadActor("../_cursor")
t[#t + 1] = LoadActor("../_halppls")

updateNowPlaying()

return t
