-- 7k song select windows in the look of the Dan window (dan.lua): a
-- near-opaque dark blue backdrop under the top bar down to the window strip,
-- white text with gray column names, tight rows with the picked one in blue
-- and flat buttons. ECFNWindow.frame makes the window's frame (it slides in
-- and out with its tab like the Til Death ones); the other helpers make its
-- parts. Positions are from the window's left edge.
ECFNWindow = {
	x = 10,
	top = 45,
	width = 400,
	rowH = 14,
	white = color("#ffffff"),
	gray = color("#9aa3b5"),
	blue = color("#3f9fff"),
	green = color("#66ff66"),
	red = color("#ff6666"),
	gold = color("#ffd91a"),
}
local W = ECFNWindow

function ECFNWindow.bottom()
	return SCREEN_HEIGHT - 82
end

-- tab: the tab index; onShow(self) runs each time the window opens
function ECFNWindow.frame(tab, name, onShow)
	local t = Def.ActorFrame {
		Name = name,
		BeginCommand = function(self)
			self.open = false
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
				self.open = true
				if onShow then
					onShow(self)
				end
				self:visible(true):queuecommand("On")
				self:playcommand("Show")
			else
				if self.open then
					self:queuecommand("Off")
				end
				self.open = false
			end
		end,
		TabChangedMessageCommand = function(self)
			self:queuecommand("Set")
		end,
	}
	t[#t + 1] = Def.Quad {
		InitCommand = function(self)
			self:xy(W.x, W.top - 4):halign(0):valign(0):zoomto(W.width, W.bottom() - W.top + 4)
			self:diffuse(color("0.02,0.03,0.06,0.92"))
		end,
	}
	return t
end

function ECFNWindow.text(x, y, zoom, align, init)
	return LoadFont("Common Normal") .. {
		InitCommand = function(self)
			self:xy(W.x + x, y):zoom(zoom):halign(align):diffuse(W.white)
			self:shadowlength(1):shadowcolor(color("0,0,0,0.8"))
			if init then
				init(self)
			end
		end,
	}
end

-- a flat button: label, its middle x, y, width, enabled() and lit() checks
-- (both optional) and what a left click does
function ECFNWindow.button(label, x, y, w, onClick, enabled, lit)
	return Def.ActorFrame {
		UIElements.QuadButton(1, 1) .. {
			InitCommand = function(self)
				self:xy(W.x + x, y):zoomto(w, 16)
			end,
			ShowCommand = function(self)
				local on = not enabled or enabled()
				if lit and lit() then
					self:diffuse(W.blue):diffusealpha(0.5)
				else
					self:diffuse(on and W.white or W.gray):diffusealpha(on and 0.1 or 0.05)
				end
			end,
			MouseOverCommand = function(self)
				self:GetParent():GetChild("Label"):diffusealpha(0.7)
			end,
			MouseOutCommand = function(self)
				self:GetParent():GetChild("Label"):diffusealpha(1)
			end,
			MouseDownCommand = function(self, params)
				if params.event == "DeviceButton_left mouse button" and (not enabled or enabled()) then
					onClick()
				end
			end,
		},
		W.text(x, y, 0.34, 0.5, function(self)
			self:settext(label)
		end) .. {
			Name = "Label",
			ShowCommand = function(self)
				self:diffuse((not enabled or enabled()) and W.white or W.gray)
			end,
		},
	}
end

-- the clickable band of a row, lit blue when picked(i) is true
function ECFNWindow.rowBand(i, y, picked, onClick)
	return UIElements.QuadButton(1, 1) .. {
		InitCommand = function(self)
			self:xy(W.x + 4, y):halign(0):zoomto(W.width - 8, W.rowH - 2)
		end,
		ShowCommand = function(self)
			local on = picked and picked(i)
			self:diffuse(on and W.blue or W.white):diffusealpha(on and 0.35 or 0.04)
		end,
		MouseDownCommand = function(self, params)
			if params.event == "DeviceButton_left mouse button" then
				onClick(i)
			end
		end,
	}
end

-- moves the music wheel to a song
function ECFNWindow.pickSong(song)
	local top = SCREENMAN:GetTopScreen()
	if song and top and top.GetMusicWheel then
		top:GetMusicWheel():SelectSong(song)
	end
end
