-- 7k multiplayer lobby in the look of the ECFN song select: the room list is
-- the engine's wheel on the right (metrics [ScreenNetRoom]), this draws the
-- title and one panel on the left with the selected room and who is online.
-- Everything is placed in the skin's 1920x1080 space and scaled.
local s = ecfnScale()
local dir = THEME:GetCurrentThemeDirectory()
if dir:sub(1, 1) ~= "/" then
	dir = "/" .. dir
end
dir = dir .. "BGAnimations/ScreenSelectMusic decorations/ecfn/"

local WHITE = color("#ffffff")
local GREY = color("#9aa4b0")
local DIM = color("#5c6670")
local BLUE = color("#3f9fff")
local OPEN = color("#4cd964")
local INGAME = color("#ff5a5a")
local LOCKED = color("#ffcc33")
local NLIST = 12

-- what the panel shows, filled by Refresh
local sel = {}

local function selectedRoom()
	local top = SCREENMAN:GetTopScreen()
	if not top or not top.GetRoomWheel then
		return nil
	end
	local w = top:GetRoomWheel()
	local idx = w:GetCurrentIndex()
	if idx == 0 then
		return {create = true}
	end
	local rooms = w:GetRooms() or {}
	return rooms[idx]
end

local function Text(name, x, y, h, c, maxw, align)
	return LoadFont("Common Normal") .. {
		Name = name,
		InitCommand = function(self)
			self:halign(align or 0):valign(0.5):xy(x, y)
			self:settext("Ag")
			local z = h / self:GetHeight() * 1.25
			self:zoom(z):diffuse(c or WHITE)
			if maxw then
				self:maxwidth(maxw / z)
			end
			self:settext("")
		end,
	}
end

local t = Def.ActorFrame {
	Name = "ECFNLobby",
	InitCommand = function(self)
		self:xy((SCREEN_WIDTH - 1920 * s) / 2, 0):zoom(s)
		self:SetUpdateFunction(function(af)
			local r = selectedRoom()
			local key = r and (r.create and "\1create" or (r.name .. "\1" .. (r.state or 0) .. "\1" .. #(r.players or {}) .. "\1" .. (r.description or ""))) or ""
			if key ~= af.lastKey then
				af.lastKey = key
				sel = r or {}
				af:playcommand("Refresh")
			end
		end)
		self:SetUpdateFunctionInterval(0.1)
	end,
	BeginCommand = function(self)
		self:playcommand("Refresh")
	end,
	RoomListUpdatedMessageCommand = function(self)
		self.lastKey = nil
	end,
	UsersUpdateMessageCommand = function(self)
		self:playcommand("Refresh")
	end,

	-- title, same place and look as ":SELECT A MUSIC"
	LoadFont("Common Large") .. {
		InitCommand = function(self)
			self:halign(0):valign(0.5):xy(35, 44):settext(":SELECT A ROOM")
			self:zoom(30 / self:GetHeight() * 1.25):diffuse(color("#d8d8d8")):strokecolor(color("0,0,0,0.8"))
		end,
	},

	Def.Sprite {
		Texture = dir .. "panel.png",
		InitCommand = function(self)
			self:halign(0):valign(0):xy(30, 110):zoomto(1130, 770)
		end,
	},
	Def.Quad {
		InitCommand = function(self)
			self:halign(0):valign(0):xy(30, 110):zoomto(1130, 4):diffuse(BLUE):diffusealpha(0.8)
		end,
	},

	Text("Label", 60, 150, 20, GREY) .. {
		RefreshCommand = function(self)
			self:settext(sel.create and "NEW ROOM" or "ROOM")
		end,
	},
	Text("Name", 60, 200, 48, WHITE, 1050) .. {
		RefreshCommand = function(self)
			self:settext(sel.create and "Create Room" or (sel.name or ""))
		end,
	},
	Text("Desc", 60, 255, 26, GREY, 1050) .. {
		RefreshCommand = function(self)
			if sel.create then
				self:settext("Press Enter, give it a name (and a password if you like).")
			else
				self:settext(sel.description or "")
			end
		end,
	},
	Text("State", 60, 305, 26, OPEN, 1050) .. {
		RefreshCommand = function(self)
			self:ClearAttributes()
			if sel.create or not sel.name then
				self:settext("")
				return
			end
			local state = sel.state == 2 and "IN GAME" or "OPEN"
			local rest = ""
			if sel.passworded then
				rest = rest .. "   PASSWORD"
			end
			rest = rest .. string.format("   %d player%s", #(sel.players or {}), #(sel.players or {}) == 1 and "" or "s")
			self:settext(state .. rest)
			self:diffuse(sel.state == 2 and INGAME or OPEN)
			local at = #state
			if sel.passworded then
				self:AddAttribute(at, {Length = 11, Diffuse = LOCKED})
				at = at + 11
			end
			self:AddAttribute(at, {Length = #rest, Diffuse = GREY})
		end,
	},
	Def.Quad {
		InitCommand = function(self)
			self:halign(0):valign(0):xy(60, 340):zoomto(1070, 1):diffuse(WHITE):diffusealpha(0.2)
		end,
	},
	Text("PlayersHead", 60, 375, 20, GREY) .. {
		RefreshCommand = function(self)
			self:settext(sel.create and "HOW IT WORKS" or "IN THIS ROOM")
		end,
	},
	Text("OnlineHead", 640, 375, 20, GREY) .. {
		RefreshCommand = function(self)
			self:settext(string.format("ONLINE (%d)", #(NSMAN:GetLobbyUserList() or {})))
		end,
	},
	Def.Quad {
		InitCommand = function(self)
			self:halign(0):valign(0):xy(615, 360):zoomto(1, 470):diffuse(WHITE):diffusealpha(0.2)
		end,
	},

	-- help at the bottom of the panel
	Text("Help", 60, 850, 20, DIM, 1070) .. {
		InitCommand = function(self)
			self:settext("Enter: join / create    Esc: back    T: chat (rooms get their own channel)")
		end,
	},
}

local howTo = {
	"1. The owner picks a song with Enter.",
	"2. Everyone types /ready in the room chat",
	"   (or clicks Ready).",
	"3. The owner presses Enter on it again,",
	"   everybody starts together.",
	"",
	"Everyone needs the same chart.",
	"/help in the room chat lists the commands.",
}

for i = 1, NLIST do
	local y = 410 + (i - 1) * 34
	t[#t + 1] = Text("P" .. i, 60, y, 24, WHITE, 540) .. {
		RefreshCommand = function(self)
			if sel.create then
				self:settext(howTo[i] or ""):diffuse(GREY)
				return
			end
			local p = sel.players or {}
			if i == NLIST and #p > NLIST then
				self:settext(string.format("... and %d more", #p - NLIST + 1)):diffuse(GREY)
			else
				self:settext(p[i] or ""):diffuse(WHITE)
			end
		end,
	}
	t[#t + 1] = Text("O" .. i, 640, y, 24, WHITE, 500) .. {
		RefreshCommand = function(self)
			local list = {}
			for _, name in ipairs(NSMAN:GetLobbyUserList() or {}) do
				list[#list + 1] = name
			end
			table.sort(list, function(a, b)
				return a:lower() < b:lower()
			end)
			if i == NLIST and #list > NLIST then
				self:settext(string.format("... and %d more", #list - NLIST + 1)):diffuse(GREY)
			else
				self:settext(list[i] or ""):diffuse(list[i] == NSMAN:GetLoggedInUsername() and BLUE or WHITE)
			end
		end,
	}
end

return t
