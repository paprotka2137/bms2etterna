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

-- 7k: a flat bar in the look of the res extensa website: lamp strip, level,
-- title, LN tag; folders with their lamp spread under the name. 640x76 in
-- the 1920x1080 select space (metrics.ini places the wheel at x 975).
if hideMSD() then
    local s = ecfnScale()
    local BW, BH = 640, 76

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

    -- a folder's lamp is the lowest of its songs (none while any is unplayed)
    local function folderLamps(group)
        local key = "folder:" .. group
        local f = ecfnLampCache and ecfnLampCache[key]
        if f == nil then
            f = {lamp = 10, counts = {}, total = 0}
            for i = 0, 10 do
                f.counts[i] = 0
            end
            local songs = SONGMAN:GetSongsInGroup(group) or {}
            if #songs == 0 then
                -- a level of the table browser: its songs are the wheel's
                local top = SCREENMAN:GetTopScreen()
                local wheel = top and top.GetMusicWheel and top:GetMusicWheel()
                if wheel and wheel.IsBrowsingTables and wheel:IsBrowsingTables() then
                    songs = wheel:GetSongsInGroup(group) or {}
                end
            end
            for _, song in ipairs(songs) do
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

    local function txt(font, px, x, maxw)
        local z = rxZoom(font, px * s)
        return LoadFont(font) .. {
            InitCommand = function(self)
                self:halign(0):x(x * s):zoom(z):maxwidth(maxw * s / z)
            end,
        }
    end

    local t = Def.ActorFrame {
        -- folders sit on the panel color
        -- the wheel is curved (metrics.ini), so the bars' right ends are
        -- staggered: the panel and the line fade out over the right part
        Def.Quad {
            Name = "Bg",
            InitCommand = function(self)
                self:halign(0):zoomto(BW * 0.6 * s, (BH - 2) * s):diffuse(rxColor("panel"))
            end,
            SetCommand = function(self, params)
                self:visible(isFolder[params.Type] or params.Type == "Sort" or false)
            end,
        },
        Def.Quad {
            Name = "BgFade",
            InitCommand = function(self)
                self:halign(0):x(BW * 0.6 * s):zoomto(BW * 0.4 * s, (BH - 2) * s):diffuse(rxColor("panel"))
                self:diffuserightedge(rxColor("panel", 0))
            end,
            SetCommand = function(self, params)
                self:visible(isFolder[params.Type] or params.Type == "Sort" or false)
            end,
        },
        Def.Quad {
            Name = "Sep",
            InitCommand = function(self)
                self:halign(0):valign(0):y(-BH / 2 * s):zoomto(BW * s, math.max(1, s)):diffuse(rxColor("hover"))
                self:diffuserightedge(rxColor("hover", 0))
            end,
        },
        -- the lamp's color washing in from the left edge, so lamps read at a
        -- glance; none for unplayed charts
        Def.Quad {
            Name = "LampGlow",
            InitCommand = function(self)
                self:halign(0):zoomto(260 * s, (BH - 2) * s)
            end,
            SetCommand = function(self, params)
                local frame = 0
                if params.Type == "Song" and params.Song then
                    frame = songLamp(params.Song)
                elseif isFolder[params.Type] and params.Text and params.Text ~= "" then
                    frame = folderLamps(params.Text).lamp
                end
                self:visible(frame > 0 and params.Type ~= "Sort" and params.Type ~= "Custom")
                local c = rxLampColor(frame)
                self:diffuseleftedge({c[1], c[2], c[3], frame == 1 and 0.22 or 0.3})
                self:diffuserightedge({c[1], c[2], c[3], 0})
            end,
        },
        Def.Quad {
            Name = "Lamp",
            InitCommand = function(self)
                self:halign(0):x(0):zoomto(12 * s, (BH - 2) * s)
            end,
            SetCommand = function(self, params)
                local frame = 0
                if params.Type == "Song" and params.Song then
                    frame = songLamp(params.Song)
                elseif isFolder[params.Type] and params.Text and params.Text ~= "" then
                    frame = folderLamps(params.Text).lamp
                end
                self:visible(params.Type ~= "Sort" and params.Type ~= "Custom")
                -- unplayed: a faint strip, so the curve of the wheel isn't a
                -- staircase of gray blocks
                self:diffuse(rxLampColor(frame))
                if frame == 0 then
                    self:diffusealpha(0.3)
                end
                -- an effect, not tweens: the wheel stops placing its items while
                -- anything in it is tweening
                if frame >= 9 then
                    self:diffuseshift():effectcolor1(rxLampColor(frame)):effectcolor2(color("#ffffff")):effectperiod(1)
                else
                    self:stopeffect()
                end
            end,
        },
        txt("RX Bold", 24, 56, 60) .. {
            Name = "Level",
            SetCommand = function(self, params)
                if params.Type ~= "Song" or not params.Song then
                    self:visible(false)
                    return
                end
                -- no level numbers on the wheel: the table line shows them
                self:visible(false)
                do return end
                local info = barInfo(params.Song)
                if info.level == nil then
                    self:settext("?"):diffuse(rxLevelColor(5))
                else
                    self:settext(tostring(math.max(0, math.min(99, info.level)))):diffuse(rxLevelAccent(info.level, info.row))
                end
            end,
        },
        txt("RX Normal", 23, 56, 534) .. {
            Name = "Title",
            SetCommand = function(self, params)
                if params.Type == "Song" and params.Song then
                    self:visible(true):settext(params.Song:GetDisplayFullTitle()):diffuse(rxColor("text"))
                elseif params.Type == "Custom" then
                    -- a table's chart that isn't in Songs
                    local c = rxColor("muted")
                    self:visible(true):settext(params.Label or ""):diffuse({c[1], c[2], c[3], 0.7})
                else
                    self:visible(false)
                end
            end,
        },
        txt("RX SemiBold", 23, 56, 500) .. {
            Name = "Folder",
            SetCommand = function(self, params)
                if isFolder[params.Type] then
                    local open = params.Type == "SectionExpanded"
                    -- no arrow: Inter has no ▾ ▸ and they came out as "?"
                    self:visible(true):settext(params.Text or "")
                    self:diffuse(open and rxColor("white") or rxColor("text"))
                elseif params.Type == "Sort" then
                    self:visible(true):settext(params.Label or ""):diffuse(rxColor("muted"))
                else
                    self:visible(false)
                end
            end,
        },
        LoadFont("RX SemiBold") .. {
            Name = "LN",
            InitCommand = function(self)
                self:halign(1):x((BW - 24) * s):zoom(rxZoom("RX SemiBold", 13 * s)):settext("LN"):diffuse(rxColor("muted"))
            end,
            SetCommand = function(self, params)
                self:visible(params.Type == "Song" and params.Song and barInfo(params.Song).ln or false)
            end,
        },
        LoadFont("RX SemiBold") .. {
            Name = "Missing",
            InitCommand = function(self)
                self:halign(1):x((BW - 24) * s):zoom(rxZoom("RX SemiBold", 13 * s)):settext("MISSING"):diffuse(rxColor("muted"))
            end,
            SetCommand = function(self, params)
                self:visible(params.Type == "Custom" and params.Unavailable or false)
            end,
        },
    }

    -- a folder's lamp spread, best lamps first, along the bottom of the bar
    local graph = Def.ActorFrame {
        Name = "LampGraph",
        SetCommand = function(self, params)
            local f = isFolder[params.Type] and params.Text and params.Text ~= "" and folderLamps(params.Text)
            self:visible(f and f.total > 0 or false)
            if not f or f.total == 0 then
                return
            end
            local x = 56 * s
            for l = 10, 0, -1 do
                local w = 500 * s * f.counts[l] / f.total
                self:GetChild("G" .. l):x(x):zoomto(w, 3 * s)
                x = x + w
            end
        end,
    }
    for l = 0, 10 do
        graph[#graph + 1] = Def.Quad {
            Name = "G" .. l,
            InitCommand = function(self)
                self:halign(0):y(26 * s):diffuse(rxLampColor(l))
            end,
        }
    end
    t[#t + 1] = graph

    t[#t + 1] = UIElements.QuadButton(1, 1) .. {
        InitCommand = function(self)
            self:halign(0):diffusealpha(0):zoomto(BW * s, BH * s)
        end,
        SetCommand = function(self, params)
            self.index = params.DrawIndex
        end,
        MouseDownCommand = function(self, params)
            clickItem(self.index, 11, params)
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
            clickItem(self.index, 11, params)
		end,
	},
}
