local active = true
local numericinputactive = false
local whee

local function IgnoreTabInputs()
	local IgnoreTabInput = themeConfig:get_data().global.IgnoreTabInput
	if IgnoreTabInput == 3 then
		return true
	elseif IgnoreTabInput == 2 and getTabIndex() == 3 then
		return true
	else
		return false
	end
end

local tabNames = {"General", "MSD", "Scores", "Search", "Profile", "Filters", "Goals", "Playlists", "Packs", "Tags", "Ranking", "Dan", "Recommend"} -- this probably should be in tabmanager.
-- 7k (ECFN song select) works like beatoraja's option windows: General is
-- always up and holding 1 2 3 4 5 6 slides out Ranking, Profile, Goals, Playlists,
-- Dan and Recommend until the key is let go. The bar shows those keys instead of tabs,
-- clicking one keeps its window open until it is clicked again. MSD, Search,
-- Filters and Packs are gone (search opens from the search box at the top).
local ecfn = hideMSD()
local ecfnDir = THEME:GetCurrentThemeDirectory()
if ecfnDir:sub(1, 1) ~= "/" then
	ecfnDir = "/" .. ecfnDir
end
ecfnDir = ecfnDir .. "BGAnimations/ScreenSelectMusic decorations/ecfn/"
local shownTabs = {}
if ecfn then
	-- Ranking (the BMS 7k ranking site, with the local scores) in place of
	-- Scores, no Tags; Recommend (charts to clear / hard clear) on key 6
	shownTabs = {11, 5, 7, 8, 12, 13}
else
	for i = 1, #tabNames - 3 do
		shownTabs[#shownTabs + 1] = i
	end
end
local ecfnKeys = {"1", "2", "3", "4", "5", "6"}

local function switchTab(to)
	local tind = getTabIndex()
	setTabIndex(to)
	MESSAGEMAN:Broadcast("TabChanged", {from = tind, to = to})
end

local function ecfnInput(event)
	if not active or numericinputactive or SCREENMAN:get_input_redirected(PLAYER_1) then
		return false
	end
	if INPUTFILTER:IsControlPressed() or getTabIndex() == 3 then
		return false -- Ctrl+R and typing in the search
	end
	local top = SCREENMAN:GetTopScreen():GetName()
	if top ~= "ScreenSelectMusic" and top ~= "ScreenNetSelectMusic" then
		return false
	end
	for k, key in ipairs(ecfnKeys) do
		if event.DeviceInput.button == "DeviceButton_" .. key then
			local tab = shownTabs[k] - 1
			if event.type == "InputEventType_FirstPress" then
				switchTab(tab)
			elseif event.type == "InputEventType_Release" and getTabIndex() == tab then
				switchTab(0)
			end
		end
	end
	return false
end

local function input(event)
	if ecfn then
		return ecfnInput(event)
	end
	if event.type ~= "InputEventType_Release" and active then
		if numericinputactive == false then
			if
				not (INPUTFILTER:IsBeingPressed("left ctrl") or INPUTFILTER:IsBeingPressed("right ctrl") or
					(SCREENMAN:GetTopScreen():GetName() ~= "ScreenSelectMusic" and
					 SCREENMAN:GetTopScreen():GetName() ~= "ScreenNetSelectMusic"))
			 then
				if event.DeviceInput.button == "DeviceButton_0" and ecfn then
					-- nothing on 0 here
				elseif event.DeviceInput.button == "DeviceButton_0" then
					local tind = getTabIndex()
					-- if on the search tab dont let them press 0 if currently holding shift...
					-- prevents attempting to enter ')' causing page change
					-- (HACK) (HACK) (HACK) (HACK) (HACK) (HACK) (HACK) (HACK) (HACK) (HACK)
					if tind == 3 and (INPUTFILTER:IsBeingPressed("left shift") or INPUTFILTER:IsBeingPressed("right shift")) then
						return false
					end

					if not IgnoreTabInputs() then
						setTabIndex(9)
						MESSAGEMAN:Broadcast("TabChanged", {from = tind, to = 9})
					end
				else
					for k, i in ipairs(shownTabs) do
						local numpad = event.DeviceInput.button == "DeviceButton_KP "..event.char	-- explicitly ignore numpad inputs for tab swapping (doesn't care about numlock) -mina
						if not numpad and event.char and tonumber(event.char) and tonumber(event.char) == (ecfn and k or i) and not IgnoreTabInputs() then
							local tind = getTabIndex()
							setTabIndex(i - 1)
							MESSAGEMAN:Broadcast("TabChanged", {from = tind, to = i-1})
						end
					end
				end
			end
		end
	end
	return false
end
local t =
	Def.ActorFrame {
	BeginCommand = function(self)
		-- the Etterna chat overlay that defines MPinput is replaced by the BMS chat
		if MPinput then
			SCREENMAN:GetTopScreen():AddInputCallback(MPinput)
		end
		SCREENMAN:GetTopScreen():AddInputCallback(input)
		resetTabIndex()
	end,
	NumericInputActiveMessageCommand = function(self)
		numericinputactive = true
	end,
	NumericInputEndedMessageCommand = function(self)
		numericinputactive = false
	end,
	ReloadedScriptsMessageCommand = function(self)
		MESSAGEMAN:Broadcast("TabChanged", {from = 1, to = 1})
	end,
}

local frameWidth = capWideScale(get43size(450), 450) / (#tabNames - 4)
if ecfn then
	frameWidth = (ecfnX(1160) - 4) / #shownTabs
end
local frameX = frameWidth / 2 + 2
local frameY = SCREEN_HEIGHT - 70

local function tabs(index, pos)
	local t = Def.ActorFrame {
		Name = "Tab" .. index,
		InitCommand = function(self)
			self:xy(frameX + ((pos - 1) * frameWidth), frameY)
		end,
		BeginCommand = function(self)
			self:queuecommand("Set")
		end,
		SetCommand = function(self)
			self:finishtweening()
			self:smooth(0.1)
			--show tab if it's the currently selected one
			if getTabIndex() == index - 1 then
				self:diffusealpha(1):y(frameY - 1)
				if ecfn then
					self:GetChild("TabBG"):diffusecolor(color("#3f9fff")):diffusealpha(0.45)
				else
					self:GetChild("TabBG"):diffusecolor(Brightness(getMainColor("positive"),0.3)):diffusealpha(0.5)
				end
			else -- otherwise "Hide" them
				self:diffusealpha(0.7):y(frameY)
				if ecfn then
					self:GetChild("TabBG"):diffusecolor(color("#000000")):diffusealpha(0)
				else
					self:GetChild("TabBG"):diffusecolor(getMainColor("frames")):diffusealpha(0.7)
				end
			end
		end,
		TabChangedMessageCommand = function(self)
			self:queuecommand("Set")
		end
	}

	-- 7k: a gray ECFN key mode cell under each tab, the selected one lit blue
	if ecfn then
		t[#t + 1] = Def.Sprite {
			Texture = ecfnDir .. "cell_gray.png",
			InitCommand = function(self)
				self:y(2):valign(0):zoomto(frameWidth - 2, 20)
			end,
		}
	end
	t[#t + 1] = UIElements.QuadButton(1, 1) .. {
		Name = "TabBG",
		InitCommand = function(self)
			self:y(2):valign(0):zoomto(frameWidth, 20):diffusecolor(getMainColor("frames")):diffusealpha(0.7)
		end,
		MouseDownCommand = function(self, params)
			if params.event == "DeviceButton_left mouse button" then
				local to = index - 1
				if ecfn and getTabIndex() == to then
					to = 0
				end
				switchTab(to)
			end
		end
	}

	t[#t + 1] = LoadFont("Common Normal") .. {
		Name = "TabText",
		InitCommand = function(self)
			self:y(4):valign(0):zoom(0.4):diffuse(getMainColor("positive")):maxwidth(frameWidth * 2)
		end,
		BeginCommand = function(self)
			self:queuecommand("Set")
		end,
		SetCommand = function(self)
			local name = THEME:GetString("TabNames", tabNames[index])
			if ecfn then
				name = string.upper(ecfnKeys[pos]) .. "   " .. string.upper(name)
			end
			self:settext(name)
			if isTabEnabled(index) then
				if index == 6 and FILTERMAN:AnyActiveFilter() then
					self:diffuse(color("#cc2929"))
				elseif ecfn then
					self:diffuse(color("#ffffff"))
				else
					self:diffuse(getMainColor("positive"))
				end
			else
				self:diffuse(color("#666666"))
			end
		end
	}
	return t
end

--Make tabs
-- 7k: one gray ECFN strip with the windows' names (held 1-5 or clicked),
-- the open one in white.
local function ecfnTab(index, pos)
	local w = (ecfnX(1160) - 8) / #shownTabs
	local open = function()
		return getTabIndex() == index - 1
	end
	return Def.ActorFrame {
		Name = "Tab" .. index,
		InitCommand = function(self)
			self:xy(4 + (pos - 1) * w, frameY + 5)
		end,
		BeginCommand = function(self)
			self:playcommand("Set")
		end,
		TabChangedMessageCommand = function(self)
			self:playcommand("Set")
		end,
		-- the window's name
		LoadFont("Common Normal") .. {
			InitCommand = function(self)
				self:x(w / 2):zoom(0.38):maxwidth((w - 12) / 0.38)
				self:settext(string.upper(THEME:GetString("TabNames", tabNames[index])))
				self:shadowlength(1):shadowcolor(color("0,0,0,0.8"))
			end,
			SetCommand = function(self)
				self:diffuse(open() and color("#ffffff") or color("#9aa3b5"))
			end,
		},
		-- clicking keeps the window open until it is clicked again
		UIElements.QuadButton(1, 1) .. {
			InitCommand = function(self)
				self:halign(0):x(2):zoomto(w - 4, 18):diffusealpha(0)
			end,
			MouseOverCommand = function(self)
				self:diffuse(color("#ffffff")):diffusealpha(0.08)
			end,
			SetCommand = function(self)
				-- the open window's name sits on a blue light
				if open() then
					self:diffuse(color("#3f9fff")):diffusealpha(0.3)
				else
					self:diffusealpha(0)
				end
			end,
			MouseOutCommand = function(self)
				self:playcommand("Set")
			end,
			MouseDownCommand = function(self, params)
				if params.event == "DeviceButton_left mouse button" then
					switchTab(open() and 0 or index - 1)
				end
			end,
		},
	}
end

if ecfn then
	t[#t + 1] = Def.Sprite {
		Texture = ecfnDir .. "win_strip.png",
		InitCommand = function(self)
			self:halign(0):valign(0):xy(0, frameY - 6):zoomto(ecfnX(1160) + 2, 22)
		end,
	}
	for pos, i in ipairs(shownTabs) do
		t[#t + 1] = ecfnTab(i, pos)
	end
else
	for pos, i in ipairs(shownTabs) do
		t[#t + 1] = tabs(i, pos)
	end
end

return t
