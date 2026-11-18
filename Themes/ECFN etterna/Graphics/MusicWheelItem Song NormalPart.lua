local lastclick = GetTimeSinceStart()
local requiredtimegap = 0.1

-- clicking an item moves the wheel to it, clicking the selected one picks it
local function clickItem(index, numwheelitems, params)
    if params.event == "DeviceButton_left mouse button" then
        local now = GetTimeSinceStart()
        if now - lastclick < requiredtimegap then return end
        lastclick = now

        local middle = math.ceil(numwheelitems / 2)
        local top = SCREENMAN:GetTopScreen()
        local we = top:GetMusicWheel()
        if we then
            local dist = index - middle
            if dist == 0 and we:IsSettled() then
                -- clicked current item
                top:SelectCurrent()
            else
                local itemtype = we:MoveAndCheckType(index - middle)
                we:Move(0)
                if itemtype == "WheelItemDataType_Section" then
                    -- clicked a group
                    top:SelectCurrent()
                end
            end
        end
    elseif params.event == "DeviceButton_right mouse button" then
        -- right click opens playlists
        local tind = getTabIndex()
        setTabIndex(7)
        MESSAGEMAN:Broadcast("TabChanged", {from = tind, to = 7})
    end
end

-- 7k: bar of the beatoraja ECFN skin, 730x52 in its space with the level at
-- x 37, the title at x 155 (folders 50) and the clear lamp hanging off the left
if hideMSD() then
    local s = ecfnScale()
    local dir = THEME:GetCurrentThemeDirectory()
    if dir:sub(1, 1) ~= "/" then
        dir = "/" .. dir
    end
    dir = dir .. "BGAnimations/ScreenSelectMusic decorations/ecfn/"
    -- bar frames: song folder table grade nograde command search nosong
    local barFrames = {Song = 0, SectionCollapsed = 1, SectionExpanded = 1, Sort = 5}
    -- lamp sheets: frame count and where they sit (the animated ones are bigger)
    local lampFrames = {2, 1, 1, 1, 1, 1, 2, 3, 3, 3}
    local lampDelays = {0.04, 1, 1, 1, 1, 1, 0.05, 0.1 / 3, 0.1 / 3, 0.1 / 3}

    -- what a song bar shows that never changes on the select screen: its 7k
    -- chart, level and whether it has long notes. Every bar is set again on
    -- each wheel move, so this is read once per song (the cache is emptied
    -- every time the song select loads, like the lamps)
    local function barInfo(song)
        local key = song:GetSongDir()
        local cache = ecfnBarCache
        local info = cache and cache[key]
        if info == nil then
            local st = getBMSSongSteps(song)
            local level, row = getBMSLevelDisplay(song, st)
            local holds = 0
            if st then
                local rv = st:GetRadarValues(PLAYER_1)
                holds = rv:GetValue("RadarCategory_Holds") + rv:GetValue("RadarCategory_Rolls")
            end
            info = {level = level, row = row, ln = holds > 0}
            if cache then
                cache[key] = info
            end
        end
        return info
    end

    local t = Def.ActorFrame {
        Def.Sprite {
            Name = "Bar",
            Texture = dir .. "bar 1x8.png",
            InitCommand = function(self)
                self:animate(false):halign(0):zoomto(730 * s, 52 * s)
            end,
            SetCommand = function(self, params)
                self:setstate(barFrames[params.Type] or 5)
            end,
        },
        LoadFont("ECFN Bar") .. {
            Name = "Title",
            InitCommand = function(self)
                self:halign(0):x(155 * s):y(1 * s)
                self:settext("Ag")
                self.z = 26 * s * 1.25 / self:GetHeight()
                self:zoom(self.z):maxwidth(490 * s / self.z)
            end,
            SetCommand = function(self, params)
                if params.Type == "Song" and params.Song then
                    self:visible(true)
                    self:settext(params.Song:GetDisplayFullTitle())
                    self:diffuse(color("#ffffff"))
                else
                    self:visible(false)
                end
            end,
        },
        -- folder and sort names: the engine's own texts take the pack colors
        -- (unreadable on the orange bars), metrics hide them on 7k
        LoadFont("ECFN Bar") .. {
            Name = "Folder",
            InitCommand = function(self)
                self:halign(0):x(50 * s):y(1 * s)
                self:settext("Ag")
                self.z = 26 * s * 1.25 / self:GetHeight()
                self:zoom(self.z):maxwidth(560 * s / self.z)
            end,
            SetCommand = function(self, params)
                if params.Type == "SectionCollapsed" or params.Type == "SectionExpanded" then
                    self:visible(true):settext(params.Text or "")
                    self:diffuse(params.Type == "SectionExpanded" and color("#fff0a0") or color("#ffffff"))
                elseif params.Type == "Sort" then
                    self:visible(true):settext(params.Label or ""):diffuse(color("#ffffff"))
                else
                    self:visible(false)
                end
            end,
        },
        Def.Sprite {
            Name = "LN",
            Texture = dir .. "label_ln.png",
            InitCommand = function(self)
                self:halign(0):xy(-88 * s, -3 * s):zoomto(80 * s, 24 * s)
            end,
            SetCommand = function(self, params)
                self:visible(params.Type == "Song" and params.Song and barInfo(params.Song).ln or false)
            end,
        },
    }

    -- level digits of the song's hardest 7k chart, 38x30 each and centered
    local levelDigits = Def.ActorFrame {
        Name = "Level",
        InitCommand = function(self)
            self:xy(75 * s, -1 * s)
        end,
        SetCommand = function(self, params)
            local unknown = self:GetChild("Unknown")
            local d1, d2 = self:GetChild("D1"), self:GetChild("D2")
            d1:visible(false)
            d2:visible(false)
            unknown:visible(false)
            if params.Type ~= "Song" or not params.Song then
                return
            end
            local info = barInfo(params.Song)
            local level, row = info.level, info.row
            if level == nil then
                unknown:visible(true)
                return
            end
            level = math.max(0, math.min(99, level))
            if level >= 10 then
                d1:visible(true):setstate(row * 10 + math.floor(level / 10)):x(-38 * s)
                d2:visible(true):setstate(row * 10 + level % 10):x(0)
            else
                d1:visible(true):setstate(row * 10 + level):x(-19 * s)
            end
        end,
        LoadFont("Common Large") .. {
            Name = "Unknown",
            InitCommand = function(self)
                self:settext("?"):zoom(0.45):diffuse(color("#d080ff"))
            end,
        },
    }
    for _, n in ipairs({"D1", "D2"}) do
        levelDigits[#levelDigits + 1] = Def.Sprite {
            Name = n,
            Texture = dir .. "level 10x6.png",
            InitCommand = function(self)
                self:animate(false):halign(0):zoomto(38 * s, 30 * s)
            end,
        }
    end
    t[#t + 1] = levelDigits

    -- clear lamp of the best play over the song's 7k charts
    -- clear lamp of a song: the best play over its 7k charts. The cache is
    -- emptied every time the song select loads.
    local function songLamp(song)
        local key = song:GetSongDir()
        local frame = ecfnLampCache and ecfnLampCache[key]
        if frame == nil then
            frame = 0
            for _, st in ipairs(song:GetAllSteps()) do
                if st:GetStepsType() == "StepsType_Kb7_Single" then
                    frame = math.max(frame, getBestBMSLampFrame(st:GetChartKey()))
                end
            end
            if ecfnLampCache then
                ecfnLampCache[key] = frame
            end
        end
        return frame
    end

    -- a folder like beatoraja: its lamp is the lowest lamp of its songs (none
    -- while any song is unplayed), and a bar under it shows how many songs
    -- have each lamp
    local function folderLamps(group)
        local key = "folder:" .. group
        local f = ecfnLampCache and ecfnLampCache[key]
        if f == nil then
            f = {lamp = 10, counts = {}, total = 0}
            for i = 0, 10 do
                f.counts[i] = 0
            end
            for _, song in ipairs(SONGMAN:GetSongsInGroup(group) or {}) do
                local l = songLamp(song)
                f.counts[l] = f.counts[l] + 1
                f.total = f.total + 1
                f.lamp = math.min(f.lamp, l)
            end
            if f.total == 0 then
                f.lamp = 0
            end
            if ecfnLampCache then
                ecfnLampCache[key] = f
            end
        end
        return f
    end
    local isFolder = {SectionCollapsed = true, SectionExpanded = true}

    local lamps = Def.ActorFrame {
        Name = "Lamp",
        SetCommand = function(self, params)
            local frame = 0
            if params.Type == "Song" and params.Song then
                frame = songLamp(params.Song)
            elseif isFolder[params.Type] and params.Text and params.Text ~= "" then
                frame = folderLamps(params.Text).lamp
            end
            for i = 1, 10 do
                self:GetChild("L" .. i):visible(i == frame)
            end
        end,
    }
    for i = 1, 10 do
        local big = lampFrames[i] > 1
        lamps[#lamps + 1] = Def.Sprite {
            Name = "L" .. i,
            Texture = dir .. string.format("lamp%d %dx1.png", i, lampFrames[i]),
            InitCommand = function(self)
                self:halign(0):visible(false)
                if big then
                    self:xy(-7 * s, 0):zoomto(46 * s, 68 * s)
                    self:SetAllStateDelays(lampDelays[i])
                else
                    self:xy(-7 * s, -5 * s):zoomto(40 * s, 58 * s)
                end
            end,
        }
    end
    t[#t + 1] = lamps

    -- the folder's lamp graph, 400x4 at x 35 along the bottom of the bar, in
    -- the colors of the skin's lamp.png, best lamps first
    local graphColors = {
        [0] = "#484848", "#c53838", "#c042e0", "#eea9ff", "#57ff4a", "#ffdd58",
        "#f5f5f5", "#fffc4a", "#5ffff2", "#6aff5e", "#fdff63",
    }
    local graph = Def.ActorFrame {
        Name = "LampGraph",
        SetCommand = function(self, params)
            local f = isFolder[params.Type] and params.Text and params.Text ~= "" and folderLamps(params.Text)
            self:visible(f and f.total > 0 or false)
            if not f or f.total == 0 then
                return
            end
            local x = 35 * s
            for l = 10, 0, -1 do
                local w = 400 * s * f.counts[l] / f.total
                self:GetChild("G" .. l):x(x):zoomto(w, 4 * s)
                x = x + w
            end
        end,
    }
    for l = 0, 10 do
        graph[#graph + 1] = Def.Quad {
            Name = "G" .. l,
            InitCommand = function(self)
                self:halign(0):y(21 * s):diffuse(color(graphColors[l]))
            end,
        }
    end
    t[#t + 1] = graph

    t[#t + 1] = UIElements.QuadButton(1, 1) .. {
        InitCommand = function(self)
            self:halign(0):diffusealpha(0):zoomto(730 * s, 52 * s)
        end,
        SetCommand = function(self, params)
            self.index = params.DrawIndex
        end,
        MouseDownCommand = function(self, params)
            clickItem(self.index, 21, params)
        end,
    }
    return t
end

return Def.ActorFrame {
    -- 7k songs: background behind the title in the color of the best gauge cleared
    Def.Quad {
        InitCommand = function(self)
            self:halign(0):xy(0, -2):zoomto(854, 34)
            self:diffusealpha(0)
        end,
        SetCommand = function(self, params)
            local lamp = params.Song and getBestBMSLampForSong(params.Song)
            if lamp then
                local c = getBMSLampInfo(lamp, 2)
                self:diffuseleftedge({c[1], c[2], c[3], 0.45})
                self:diffuserightedge({c[1], c[2], c[3], 0.08})
            else
                self:diffusealpha(0)
            end
        end,
    },
    UIElements.QuadButton(1, 1) .. {
		InitCommand = function(self)
			self:halign(0)
			self:xy(0,0)
			self:diffusealpha(0)
			self:zoomto(854, 38)
		end,
        SetCommand = function(self, params)
            self.index = params.DrawIndex
        end,
		MouseDownCommand = function(self, params)
            clickItem(self.index, 15, params)
		end,
	},
}
