-- 7k lane picker (opened from the lane option in song select, see
-- editBMSLanes in Scripts/BMSRules.lua). Shows the 7 keys like the site's
-- lane order popup: a key is white or blue by the chart lane on it (1 3 5 7
-- white, 2 4 6 blue) and tall or short by where it sits.
--
-- Options view: pick a lane option (Left/Right or click). Random has a
-- Numbers on/off switch (N): with the numbers off every play only shuffles
-- white lanes among white keys and blue lanes among blue keys.
-- Custom view (the Custom option): just the keys. Type 1-7 (Backspace) or
-- swap two lanes with the mouse (drag one key onto another, or click one
-- and then the other). C switches "keep colors": the numbers hide and every
-- play rolls the lanes keeping each key's white/blue color.
-- Enter sets the option and starts the song.
-- Enter plays, Esc or right click closes without changing anything.

local W, H = 520, 236
local KW, KG = 40, 6 -- key width, gap
local KH_WHITE, KH_BLUE = 64, 50
local CHIP_W, CHIP_G, CHIP_H = 66, 4, 18

local C_PANEL = color("0.05,0.06,0.09,0.96")
local C_LINE = color("#2a3040")
local C_ACCENT = color("#66d9ff")
local C_TEXT = color("#e9ecf3")
local C_MUTED = color("0.62,0.66,0.75,1")
local C_WHITE = color("#e9ecf3")
local C_BLUE = color("#2f6fe0")
local C_GREY = color("#4a5060")
local C_EMPTY = color("0.16,0.18,0.24,1")
local C_DARK = color("0.07,0.08,0.11,1")

local choices = getBMSArrangeChoices()
local sel = 1
-- Random's numbers switch: off = colors only (the CRandom setting on the
-- chart's own WBWBWBW pattern)
local numbers = true
-- custom view: every play rolls the lanes keeping each key's white/blue
-- color from the order shown (the CRandom setting on a custom pattern)
local keepColors = false
local buffer = getBMSLanes() or ""
if #buffer ~= 7 then
	buffer = "1234567"
end
local function alternating(order)
	for k = 1, #order do
		if tonumber(order:sub(k, k)) % 2 ~= k % 2 then
			return false
		end
	end
	return true
end
do
	local cur = getBMSArrangeValue()
	if cur == "CRandom" then
		if alternating(buffer) then
			cur = "Random"
			numbers = false
		else
			cur = "Custom"
			keepColors = true
		end
	end
	for i, c in ipairs(choices) do
		if c.value == cur then
			sel = i
		end
	end
end
-- the first digit typed starts a new order
local fresh = true
-- key picked by a click, waiting for the second click of a swap
local picked = nil
-- key a mouse press started on (drag to another key to swap)
local pressed = nil

local root
local function refresh()
	if root then
		root:playcommand("Refresh")
	end
end

local function selValue()
	return choices[sel].value
end

local function isCustom()
	return selValue() == "Custom"
end

local function selectValue(v)
	for i, c in ipairs(choices) do
		if c.value == v then
			sel = i
		end
	end
	picked, pressed = nil, nil
end

-- what the 7 keys show for the picked option: a digit per key, nil where
-- every play rolls its own, "" for a key not typed yet
local function keysShown()
	local v = selValue()
	if v == "Off" then
		return "1234567"
	elseif v == "Mirror" then
		return "7654321"
	elseif v == "Custom" then
		return buffer
	end
	return nil
end

local hints = {
	Off = "The chart's own lanes.",
	Mirror = "Lanes flipped left to right.",
	Random = "Every play shuffles all 7 lanes, any lane can land on any key.",
	RandomColors = "Numbers off: every play shuffles white lanes (1 3 5 7) among white keys and blue lanes (2 4 6) among blue keys.",
	RRandom = "Every play rotates the lanes, sometimes flipped.",
	SRandom = "Every note goes to a random key.",
	HRandom = "Every note goes to a random key, avoiding jacks.",
	Custom = "Type 1-7, or drag a key onto another (or click both) to swap them.",
	CustomColors = "Keep colors: every play rolls the lanes, each key keeps its color. Drag or click two keys to swap their colors.",
}

local redirBefore = false
local closing = false
local function close()
	if closing then
		return
	end
	closing = true
	SCREENMAN:set_input_redirected(PLAYER_1, redirBefore)
	SCREENMAN:GetTopScreen():Cancel()
end

local function accept()
	local v = selValue()
	if v == "Custom" then
		if #buffer ~= 7 then
			SCREENMAN:PlayInvalidSound()
			SCREENMAN:SystemMessage(THEME:GetString("GeneralInfo", "BMSLanesInvalid"))
			return
		end
		setBMSArrangeByName(keepColors and "CRandom" or "Custom", buffer)
	elseif v == "Random" and not numbers then
		setBMSArrangeByName("CRandom", "1234567")
	else
		setBMSArrangeByName(v)
	end
	SCREENMAN:SystemMessage(THEME:GetString("GeneralInfo", "ProfileArrange") .. ": " .. getBMSArrangeText())
	close()
	-- and start the song (song select does it once the picker is gone)
	MESSAGEMAN:Broadcast("BMSLanesStart")
end

local function typeDigit(d)
	if isCustom() and keepColors then
		SCREENMAN:PlayInvalidSound()
		return
	end
	if not isCustom() or fresh or #buffer >= 7 then
		buffer = ""
		fresh = false
	end
	selectValue("Custom")
	if buffer:find(d, 1, true) then
		SCREENMAN:PlayInvalidSound()
		return
	end
	buffer = buffer .. d
	refresh()
end

local function erase()
	if not isCustom() or keepColors then
		return
	end
	fresh = false
	picked = nil
	buffer = buffer:sub(1, -2)
	refresh()
end

local function swap(a, b)
	if #buffer ~= 7 or a == b then
		return
	end
	local t = {}
	for k = 1, 7 do
		t[k] = buffer:sub(k, k)
	end
	t[a], t[b] = t[b], t[a]
	buffer = table.concat(t)
	fresh = false
	refresh()
end

local function move(delta)
	if isCustom() then
		return
	end
	sel = (sel - 1 + delta) % #choices + 1
	refresh()
end

local function toggleKeepColors()
	keepColors = not keepColors
	if #buffer ~= 7 then
		buffer = "1234567"
	end
	picked, pressed = nil, nil
	refresh()
end

local function toggleNumbers()
	if selValue() ~= "Random" then
		return
	end
	numbers = not numbers
	refresh()
end

-- clickable areas, checked on each left click; view: "options", "custom"
-- or nil for both
local hits = {}
local function addHit(actor, fn, view)
	hits[#hits + 1] = {actor = actor, fn = fn, view = view}
end
local keyActors = {}

local function keyUnderMouse()
	if not isCustom() or #buffer ~= 7 then
		return nil
	end
	for k, a in ipairs(keyActors) do
		if isOver(a) then
			return k
		end
	end
	return nil
end

local function mouseDown()
	local k = keyUnderMouse()
	if k then
		pressed = k
		refresh()
		return
	end
	local view = isCustom() and "custom" or "options"
	for _, h in ipairs(hits) do
		if (h.view == nil or h.view == view) and h.actor:GetVisible() and isOver(h.actor) then
			h.fn()
			return
		end
	end
	picked = nil
	refresh()
end

local function mouseUp()
	if not pressed then
		return
	end
	local from = pressed
	pressed = nil
	local k = keyUnderMouse()
	if k and k ~= from then
		-- dragged onto another key
		picked = nil
		swap(from, k)
	elseif k == from then
		-- a click: the first picks the key, the second swaps with it
		if picked == nil then
			picked = k
		elseif picked == k then
			picked = nil
		else
			local a = picked
			picked = nil
			swap(a, k)
		end
	end
	refresh()
end

local function input(event)
	if closing then
		return true
	end
	local b = event.DeviceInput.button
	if event.type == "InputEventType_Release" then
		if b == "DeviceButton_left mouse button" then
			mouseUp()
		end
		return true
	end
	local repeatOk = event.type == "InputEventType_Repeat"
	if b == "DeviceButton_left mouse button" then
		if not repeatOk then
			mouseDown()
		end
	elseif b == "DeviceButton_right mouse button" or b == "DeviceButton_escape" then
		if not repeatOk then
			close()
		end
	elseif b == "DeviceButton_enter" or b == "DeviceButton_KP enter" then
		if not repeatOk then
			accept()
		end
	elseif b == "DeviceButton_backspace" or b == "DeviceButton_delete" then
		erase()
	elseif b == "DeviceButton_left" or b == "DeviceButton_up" then
		move(-1)
	elseif b == "DeviceButton_right" or b == "DeviceButton_down" or b == "DeviceButton_tab" then
		move(1)
	elseif not repeatOk then
		local ch = (event.charNoModifiers or ""):lower()
		local kp = b:match("^DeviceButton_KP (%d)$")
		if kp then
			ch = kp
		end
		if ch:match("^[1-7]$") then
			typeDigit(ch)
		elseif ch == "c" and isCustom() then
			toggleKeepColors()
		elseif ch == "n" then
			toggleNumbers()
		end
	end
	-- the picker is modal: nothing reaches the screen below
	return true
end

local function txt()
	return LoadFont("Common Normal")
end


local t = Def.ActorFrame {
	InitCommand = function(self)
		root = self
		self:Center()
	end,
	BeginCommand = function(self)
		math.randomseed(os.time())
		redirBefore = SCREENMAN:get_input_redirected(PLAYER_1)
		SCREENMAN:set_input_redirected(PLAYER_1, true)
		SCREENMAN:GetTopScreen():AddInputCallback(input)
		self:playcommand("Refresh")
		-- hover highlight on the chips, keys and buttons
		local last = 0
		self:SetUpdateFunction(function()
			local now = GetTimeSinceStart()
			if now - last > 0.05 then
				last = now
				refresh()
			end
		end)
	end,
	OnCommand = function(self)
		self:diffusealpha(0):zoom(0.96):decelerate(0.12):diffusealpha(1):zoom(1)
	end,
	-- panel
	Def.Quad {
		InitCommand = function(self)
			self:zoomto(W, H):diffuse(C_PANEL)
		end,
	},
	Def.Quad {
		InitCommand = function(self)
			self:zoomto(W, 2):y(-H / 2 + 1):diffuse(C_ACCENT)
		end,
	},
	txt() .. {
		InitCommand = function(self)
			self:xy(-W / 2 + 14, -H / 2 + 16):halign(0):zoom(0.42):diffuse(C_MUTED)
		end,
		RefreshCommand = function(self)
			self:settext(isCustom() and "CUSTOM LANE ORDER" or "LANE ORDER")
		end,
	},
	txt() .. {
		InitCommand = function(self)
			self:xy(W / 2 - 14, -H / 2 + 16):halign(1):zoom(0.32):diffuse(C_MUTED)
		end,
		RefreshCommand = function(self)
			self:settext(isCustom() and "Enter  play     Esc  cancel" or "Left / Right  pick     Enter  play     Esc  cancel")
		end,
	},
}

-- lane options as chips (hidden in the custom view)
do
	local total = #choices * CHIP_W + (#choices - 1) * CHIP_G
	local y = -H / 2 + 42
	for i, c in ipairs(choices) do
		local x = -total / 2 + (i - 1) * (CHIP_W + CHIP_G) + CHIP_W / 2
		t[#t + 1] = Def.Quad {
			InitCommand = function(self)
				self:xy(x, y):zoomto(CHIP_W, CHIP_H)
				addHit(self, function()
					selectValue(c.value)
					refresh()
				end, "options")
			end,
			RefreshCommand = function(self)
				self:visible(not isCustom())
				local on = sel == i
				self:diffuse(on and C_ACCENT or C_LINE)
				self:diffusealpha(on and 1 or (isOver(self) and 0.9 or 0.6))
			end,
		}
		t[#t + 1] = txt() .. {
			InitCommand = function(self)
				self:xy(x, y):zoom(0.34):maxwidth((CHIP_W - 6) / 0.34):settext(c.name)
			end,
			RefreshCommand = function(self)
				self:visible(not isCustom())
				self:diffuse(sel == i and C_DARK or C_TEXT)
			end,
		}
	end
end

-- the 7 keys
do
	local total = 7 * KW + 6 * KG
	local top = -H / 2 + 66
	for k = 1, 7 do
		local x = -total / 2 + (k - 1) * (KW + KG) + KW / 2
		local h = k % 2 == 1 and KH_WHITE or KH_BLUE
		-- outline of a picked / pressed key
		t[#t + 1] = Def.Quad {
			InitCommand = function(self)
				self:xy(x, top - 3):valign(0):zoomto(KW + 6, h + 6):diffuse(C_ACCENT)
			end,
			RefreshCommand = function(self)
				self:visible(isCustom() and (picked == k or pressed == k))
			end,
		}
		t[#t + 1] = Def.Quad {
			InitCommand = function(self)
				self:xy(x, top):valign(0):zoomto(KW, h)
				keyActors[k] = self
			end,
			RefreshCommand = function(self)
				local shown = keysShown()
				local d = shown and tonumber(shown:sub(k, k))
				if shown == nil then
					-- rolled each play: with the numbers off the key
					-- colors stay
					if selValue() == "Random" and not numbers then
						self:diffuse(k % 2 == 1 and C_WHITE or C_BLUE)
					else
						self:diffuse(C_GREY)
					end
				elseif d == nil then
					self:diffuse(C_EMPTY)
				else
					self:diffuse(d % 2 == 1 and C_WHITE or C_BLUE)
				end
				-- a hovered key you can swap lights up a little
				if isCustom() and #buffer == 7 and isOver(self) and pressed == nil then
					self:diffusealpha(0.85)
				end
			end,
		}
		t[#t + 1] = txt() .. {
			InitCommand = function(self)
				self:xy(x, top + h - 14):zoom(0.7)
			end,
			RefreshCommand = function(self)
				local shown = keysShown()
				local d = shown and shown:sub(k, k) or "?"
				local n = tonumber(d)
				if (shown == nil and selValue() == "Random" and not numbers) or (isCustom() and keepColors) then
					-- numbers off / keep colors: no numbers, just the colors
					d = ""
				end
				self:settext(d)
				self:diffuse((n and n % 2 == 1) and C_DARK or C_TEXT)
			end,
		}
	end
	-- typing cursor under the next key of a custom order
	t[#t + 1] = Def.Quad {
		InitCommand = function(self)
			self:zoomto(KW, 3):y(top + KH_WHITE + 6):diffuse(C_ACCENT)
		end,
		RefreshCommand = function(self)
			local typing = isCustom() and #buffer < 7
			self:visible(typing)
			if typing then
				self:x(-total / 2 + #buffer * (KW + KG) + KW / 2)
			end
		end,
	}
	-- the order as digits, or Random's numbers switch
	t[#t + 1] = txt() .. {
		InitCommand = function(self)
			self:xy(0, top + KH_WHITE + 22):zoom(0.46):diffuse(C_MUTED)
		end,
		RefreshCommand = function(self)
			local shown = keysShown()
			self:visible(selValue() ~= "Random")
			if isCustom() and keepColors then
				local c = {}
				for k = 1, #shown do
					c[k] = tonumber(shown:sub(k, k)) % 2 == 1 and "W" or "B"
				end
				self:settext(table.concat(c, " "))
			elseif shown == nil then
				self:settext("? ? ? ? ? ? ?")
			else
				local spaced = shown:gsub(".", "%0 "):gsub(" $", "")
				self:settext(spaced ~= "" and spaced or "-")
			end
		end,
	}
	do
		local bw, bh = 150, 18
		local y = top + KH_WHITE + 22
		t[#t + 1] = Def.Quad {
			InitCommand = function(self)
				self:y(y):zoomto(bw, bh)
				addHit(self, toggleNumbers, "options")
			end,
			RefreshCommand = function(self)
				self:visible(selValue() == "Random")
				self:diffuse(numbers and C_LINE or C_ACCENT)
				self:diffusealpha(isOver(self) and 1 or 0.8)
			end,
		}
		t[#t + 1] = txt() .. {
			InitCommand = function(self)
				self:y(y):zoom(0.36)
			end,
			RefreshCommand = function(self)
				self:visible(selValue() == "Random")
				self:settext("N  Numbers: " .. (numbers and "ON" or "OFF (colors only)"))
				self:diffuse(numbers and C_TEXT or C_DARK)
			end,
		}
	end
	-- what the picked option does
	t[#t + 1] = txt() .. {
		InitCommand = function(self)
			self:xy(0, top + KH_WHITE + 44):zoom(0.34):maxwidth((W - 40) / 0.34):diffuse(C_TEXT)
		end,
		RefreshCommand = function(self)
			local v = selValue()
			if v == "Random" and not numbers then
				v = "RandomColors"
			elseif v == "Custom" and keepColors then
				v = "CustomColors"
			end
			self:settext(hints[v] or "")
		end,
	}
end

-- buttons: the custom view has the keep colors switch
do
	local custom = {
		{
			label = function()
				return "C  Keep colors: " .. (keepColors and "ON" or "OFF")
			end,
			fn = function() toggleKeepColors() end,
			on = function() return keepColors end,
		},
		{label = "Enter  Play", fn = accept, main = true},
		{label = "Esc  Cancel", fn = close},
	}
	local options = {
		{label = "Enter  Play", fn = accept, main = true},
		{label = "Esc  Cancel", fn = close},
	}
	local bw, bg, bh = 112, 8, 22
	local y = H / 2 - 22
	local function row(list, view)
		local total = #list * bw + (#list - 1) * bg
		for i, b in ipairs(list) do
			local x = -total / 2 + (i - 1) * (bw + bg) + bw / 2
			local function shown()
				return (view == "custom") == isCustom()
			end
			t[#t + 1] = Def.Quad {
				InitCommand = function(self)
					self:xy(x, y):zoomto(bw, bh)
					addHit(self, b.fn, view)
				end,
				RefreshCommand = function(self)
					self:visible(shown())
					local lit = b.main or (b.on and b.on())
					self:diffuse(lit and C_ACCENT or C_LINE)
					self:diffusealpha(isOver(self) and 1 or 0.75)
				end,
			}
			-- a switch shows a lamp: lit when on
			if b.on then
				t[#t + 1] = Def.Quad {
					InitCommand = function(self)
						self:xy(x - bw / 2 + 9, y):zoomto(7, 7)
					end,
					RefreshCommand = function(self)
						self:visible(shown())
						self:diffuse(b.on() and C_DARK or C_GREY)
					end,
				}
			end
			t[#t + 1] = txt() .. {
				InitCommand = function(self)
					self:xy(x + (b.on and 5 or 0), y):zoom(0.36):maxwidth((bw - (b.on and 20 or 8)) / 0.36)
				end,
				RefreshCommand = function(self)
					self:visible(shown())
					self:settext(type(b.label) == "function" and b.label() or b.label)
					local lit = b.main or (b.on and b.on())
					self:diffuse(lit and C_DARK or C_TEXT)
				end,
			}
		end
	end
	row(custom, "custom")
	row(options, "options")
end

return t
