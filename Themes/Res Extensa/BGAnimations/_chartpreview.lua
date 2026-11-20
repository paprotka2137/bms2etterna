-- all the preview stuff should be var'd and used consistently -mina
local prevZoom = 0.65
local musicratio = 1

local wodth = capWideScale(280, 300)
local hidth = 40
local yeet
local cd
local calcinfo

local yPos = Var("yPos")
local yPosReverse = Var("yPosReverse")
if not yPos then yPos = 55 end
if not yPosReverse then yPosReverse = 60 end

local translated_info = {
	Paused = THEME:GetString("ChartPreview", "Paused"),
	NPS = THEME:GetString("ChordDensityGraph", "NPS"),
	BPM = THEME:GetString("ChordDensityGraph", "BPM"),
}

local function UpdatePreviewPos(self)
	if not self:IsVisible() then return end
	local scrnm = SCREENMAN:GetTopScreen():GetName()
	local allowedScreens = {
		ScreenSelectMusic = true,
		ScreenNetSelectMusic = true,
	}

	if allowedScreens[scrnm] == true then
		local pos = SCREENMAN:GetTopScreen():GetSampleMusicPosition() / musicratio
		self:GetChild("Pos"):zoomto(math.min(pos,wodth), hidth)
		self:queuecommand("Highlight")

		-- calcdisplay position indicator (not the best place to put this but it works)
		local calcgraphpos = SCREENMAN:GetTopScreen():GetSampleMusicPosition() / musicratio
		local badorp = self:GetDescendant("notChordDensityGraph", "GraphPos")
		badorp:zoomto(math.min(calcgraphpos * capWideScale(300,450) / capWideScale(280,300), capWideScale(300,450)), hidth * 3):halign(0)
	end
end

local function updateCalcInfoDisplays(actor)
	if not calcinfo:GetVisible() then return end
	mx = INPUTFILTER:GetMouseX()
	px = actor:GetParent():GetTrueX()
	sl1 = actor:GetParent():GetDescendant("notChordDensityGraph", "Seek1"):playcommand("UpdatePosition", {pos = mx, w = wodth, px=px})
	st1 = actor:GetParent():GetDescendant("notChordDensityGraph", "Seektext1"):playcommand("UpdatePosition", {pos = mx, w = wodth, px=px})
	st1:settextf("%0.2f", actor:GetParent():GetChild("Seek"):GetX() * musicratio /  getCurRateValue())
	sl1:visible(true)
	st1:visible(true)
end

local t = Def.ActorFrame {
	Name = "ChartPreview",
	InitCommand=function(self)
		self:visible(false)
        self:SetUpdateFunction(UpdatePreviewPos)
		calcinfo = self:GetChild("notChordDensityGraph"):visible(false):draworder(1000) -- actor for calcinfo
		cd = self:GetChild("ChordDensityGraph"):visible(false):draworder(1000)
	end,
	CurrentSongChangedMessageCommand=function(self)
		self:GetChild("pausetext"):settext("")
	end,
	CurrentStepsChangedMessageCommand = function(self)
		if GAMESTATE:GetCurrentSong() then
            musicratio = (GAMESTATE:GetCurrentSteps():GetFirstSecond() / getCurRateValue() + GAMESTATE:GetCurrentSteps():GetLengthSeconds()) / wodth * getCurRateValue()
		end
	end,
    SetupNoteFieldCommand=function(self)
		self:playcommand("NoteFieldVisible")
	end,
	ChartPreviewOffMessageCommand=function(self)
		self:SetUpdateFunction(nil)
	end,
	ChartPreviewOnMessageCommand=function(self)
		self:SetUpdateFunction(UpdatePreviewPos)
		self:GetChild("NoteField"):playcommand("LoadNoteData", {steps = GAMESTATE:GetCurrentSteps()})
	end,
	NoteFieldVisibleMessageCommand = function(self)
		self:visible(true)
		self:SetUpdateFunction(UpdatePreviewPos)
		cd:visible(true):y(20)				-- need to control this manually -mina
		cd:GetChild("cdbg"):diffusealpha(0)	-- we want to use our position background for draw order stuff -mina
		cd:queuecommand("GraphUpdate")		-- first graph will be empty if we dont force this on initial creation
	end,
	OptionsScreenClosedMessageCommand = function(self)
		local pOptions = GAMESTATE:GetPlayerState():GetCurrentPlayerOptions()
		local usingscrollmod = false
		local usingreverse = pOptions:UsingReverse()
		local nf = self:GetChild("NoteField")
		if not nf then return end
		if pOptions:Split() ~= 0 or pOptions:Alternate() ~= 0 or pOptions:Cross() ~= 0 or pOptions:Centered() ~= 0 then
			usingscrollmod = true
		end

		nf:y(yPos * 2.85)
		if usingscrollmod then
			nf:y(yPos * 3.55)
		elseif usingreverse then
			nf:y(yPos * 2.85 + yPosReverse)
		end
	end,

	Def.NoteFieldPreview {
		Name = "NoteField",
		-- 7k: notes stop under the density graph instead of running into the top bar
		DrawDistanceBeforeTargetsPixels = hideMSD() and 390 or 600,
		DrawDistanceAfterTargetsPixels = 0,
		--YReverseOffsetPixels = 100,

		BeginCommand = function(self)
			self:zoom(prevZoom):draworder(90)
			self:x(wodth/2)
			self:GetParent():SortByDrawOrder()
		end,
		CurrentStepsChangedMessageCommand = function(self, params)
			local steps = params.ptr
			-- only load new notedata if the preview is visible
			if self:GetParent():GetVisible() then
				self:playcommand("LoadNoteData", {steps = steps})
			end
		end,
		LoadNoteDataCommand = function(self, params)
			local steps = params.steps
			if steps ~= nil then
				self:LoadNoteData(steps)
			else
				self:LoadDummyNoteData()
			end
		end,
		CalcInfoOnMessageCommand = function(self)
			self:show_interval_bars(true)
		end,
		CalcInfoOffMessageCommand = function(self)
			self:show_interval_bars(false)
		end,
	},

	Def.Quad {
		Name = "BG",
		InitCommand = function(self)
			self:xy(wodth/2, SCREEN_HEIGHT/2)
			self:diffuse(color("0.05,0.05,0.05,1"))
			self:playcommand("Size")
		end,
		CurrentStyleChangedMessageCommand=function(self)
			self:playcommand("Size")
		end,
		SizeCommand = function(self)
			local style = GAMESTATE:GetCurrentStyle()
			if not style then
				return
			end
			local cols = style:ColumnsPerPlayer()
			if hideMSD() then
				-- 7k (ECFN song select): only between the top bar and the tabs,
				-- see-through like the ECFN panels
				local top, bottom = 44, 402
				self:zoomto(48 * cols, bottom - top):y((top + bottom) / 2 - yPos)
				self:diffuse(color("0,0,0,0.8"))
			else
				self:zoomto(48 * cols, SCREEN_HEIGHT)
			end
		end
	},
	LoadFont("Common Large") .. {
		Name = "pausetext",
		InitCommand = function(self)
			self:xy(wodth/2, SCREEN_HEIGHT/2):draworder(900):zoom(0.5)
			self:settext(""):diffuse(color("0.8,0,0"))
			self:shadowlength(1):shadowcolor(0,0,0,1)
		end,
		NoteFieldVisibleMessageCommand = function(self)
			self:settext("")
		end,
		PreviewMusicStartedMessageCommand = function(self)
			self:playcommand("Set")
		end,
		SetCommand = function(self)
			if SCREENMAN:GetTopScreen():IsSampleMusicPaused() then
				self:settext(translated_info["Paused"])
			else
				self:settext("")
			end
		end,
		MusicPauseToggledMessageCommand = function(self)
			self:playcommand("Set")
		end,
	},
	Def.Quad {
		Name = "PosBG",
		InitCommand = function(self)
			--self:zoomto(wodth, hidth):halign(0):diffuse(color(".1,.1,.1,1")):draworder(900) -- alt bg for calc info
			self:zoomto(wodth, hidth):halign(0):diffuse(color("1,1,1,1")):draworder(900) -- cdgraph bg
		end,
		HighlightCommand = function(self)	-- use the bg for detection but move the seek pointer -mina
			if isOver(self) and GAMESTATE:GetCurrentSteps() ~= nil then
				local seek = self:GetParent():GetChild("Seek")
				local seektext = self:GetParent():GetChild("Seektext")
				local cdg = self:GetParent():GetChild("ChordDensityGraph")

				seek:visible(true)
				seektext:visible(true)
				seek:x(INPUTFILTER:GetMouseX() - self:GetParent():GetTrueX())
				seektext:x(INPUTFILTER:GetMouseX() - self:GetParent():GetTrueX() - 4)	-- todo: refactor this lmao -mina
				seektext:y(INPUTFILTER:GetMouseY() - self:GetParent():GetTrueY())
				if cdg.npsVector ~= nil and #cdg.npsVector > 0 then
					local percent = clamp((INPUTFILTER:GetMouseX() - self:GetParent():GetTrueX()) / wodth, 0, 1)
					local xtime = seek:GetX() * musicratio / getCurRateValue()
					local hoveredindex = clamp(math.ceil(cdg.finalNPSVectorIndex * percent), math.min(1, cdg.finalNPSVectorIndex), cdg.finalNPSVectorIndex)
					local hoverednps = cdg.npsVector[hoveredindex]
					local td = GAMESTATE:GetCurrentSteps():GetTimingData()
					local bpm = td:GetBPMAtBeat(td:GetBeatFromElapsedTime(seek:GetX() * musicratio)) * getCurRateValue()
					seektext:settextf("%0.2f\n%d %s\n%d %s", xtime, hoverednps, translated_info["NPS"], bpm, translated_info["BPM"])
				else
					seektext:settextf("%0.2f", seek:GetX() * musicratio / getCurRateValue())
				end

				updateCalcInfoDisplays(self)
			else
				self:GetParent():GetChild("Seektext"):visible(false)
				self:GetParent():GetChild("Seek"):visible(false)
				self:GetParent():GetDescendant("notChordDensityGraph", "Seektext1"):visible(false)
				self:GetParent():GetDescendant("notChordDensityGraph", "Seek1"):visible(false)
			end
		end
	},
	Def.Quad {
		Name = "Pos",
		InitCommand = function(self)
			self:zoomto(0, hidth):diffuse(color("0,1,0,.5")):halign(0):draworder(900)
		end
	}
}

t[#t + 1] = LoadActor("_chorddensitygraph.lua")
t[#t + 1] = LoadActor("_calcdisplay.lua")

-- more draw order shenanigans
t[#t + 1] = LoadFont("Common Normal") .. {
	Name = "Seektext",
	InitCommand = function(self)
		self:y(8):valign(0):halign(1):draworder(1100):diffuse(color("0.8,0,0")):zoom(0.4)
	end
}

t[#t + 1] = UIElements.QuadButton(1, 1) .. {
	Name = "Seek",
	InitCommand = function(self)
		self:zoomto(2, hidth):diffuse(color("1,.2,.5,1")):halign(0.5):draworder(1100)
	end,
	MouseDownCommand = function(self, params)
		if params.event == "DeviceButton_left mouse button" then
			SCREENMAN:GetTopScreen():SetSampleMusicPosition( self:GetX() * musicratio )
		end
	end
}


-- 7k: the patterns the clear calc finds (Scripts/BMSClearCalc.lua) on the
-- chart preview, scrolling with its notes.
--   F7  note colours: every note in the colour of its pattern, then one
--       pattern at a time (its notes coloured, the rest grey), then off
--   F8  pattern lanes and names right of the notes on / off
-- The preview can't recolour its own notes, so the colours are drawn over
-- them.
if hideMSD() and getBMSClearDebug then
	local MAXLABELS = 14
	local laneW, laneGap = 5, 2
	local kinds = BMSCalcPatterns
	local nKinds = #kinds
	-- a note's own colour in the "all" mode: the first of these it has
	local priority = {"chordjack", "jack", "delay", "trill", "chordstream", "stream", "chord", "spike", "bpm"}
	local state = {key = nil}
	-- the 7k preview background spans skin y 44..402 (see "BG" above)
	local clipTop, clipBottom = 44 - yPos, 402 - yPos
	-- note colouring: 0 off, -1 every pattern, k only pattern k
	BMSPreviewNoteMode = BMSPreviewNoteMode or 0

	local function loadChart()
		local steps = GAMESTATE:GetCurrentSteps()
		local key = steps and steps:GetChartKey() or nil
		if key == state.key then
			return
		end
		state = {key = key}
		if not steps then
			return
		end
		-- chart time (rate 1): the preview scrolls by the chart's beats
		local ok, d = pcall(getBMSClearDebug, steps, 1)
		if not ok or not d then
			return
		end
		local td = steps:GetTimingData()
		local ranges = {}
		for k, pk in ipairs(kinds) do
			for _, r in ipairs(d.patterns[pk.key] or {}) do
				ranges[#ranges + 1] = {
					kind = k,
					b1 = td:GetBeatFromElapsedTime(r[1]),
					-- a single moment still gets a short mark
					b2 = td:GetBeatFromElapsedTime(math.max(r[2], r[1] + 0.12)),
				}
			end
		end
		local beats = {}
		for i, time in ipairs(d.t) do
			beats[i] = td:GetBeatFromElapsedTime(time)
		end
		state.ranges = ranges
		state.beats = beats
		state.col = d.col
		state.noteKinds = d.noteKinds or {}
	end

	local kindIndex = {}
	for k, pk in ipairs(kinds) do
		kindIndex[pk.key] = k
	end

	-- first note at or after this beat
	local function firstNote(beats, beat)
		local lo, hi = 1, #beats + 1
		while lo < hi do
			local mid = math.floor((lo + hi) / 2)
			if beats[mid] < beat then lo = mid + 1 else hi = mid end
		end
		return lo
	end

	local function quad(v, x1, y1, x2, y2, c)
		v[#v + 1] = {{x1, y1, 0}, c}
		v[#v + 1] = {{x2, y1, 0}, c}
		v[#v + 1] = {{x2, y2, 0}, c}
		v[#v + 1] = {{x1, y2, 0}, c}
	end

	local labels = {}
	local modeText
	local f = Def.ActorFrame {
		Name = "PatternMarks",
		InitCommand = function(self)
			self:draworder(95)
		end,
		BeginCommand = function(self)
			SCREENMAN:GetTopScreen():AddInputCallback(function(event)
				if event.type ~= "InputEventType_FirstPress" then
					return false
				end
				local b = event.DeviceInput.button
				if b == "DeviceButton_F8" then
					BMSPreviewPatterns = not BMSPreviewPatterns
					SCREENMAN:SystemMessage("Chart preview pattern lanes: " .. (BMSPreviewPatterns and "on" or "off"))
					return true
				elseif b == "DeviceButton_F7" and self:GetParent():GetVisible() then
					-- off -> all -> each pattern -> off
					local m = BMSPreviewNoteMode
					if m == 0 then
						m = -1
					elseif m == -1 then
						m = 1
					elseif m < nKinds then
						m = m + 1
					else
						m = 0
					end
					BMSPreviewNoteMode = m
					return true
				end
				return false
			end)
			self:SetUpdateFunction(function(a)
				if not a:GetParent():GetVisible() then
					return
				end
				a:GetChild("Draw"):playcommand("Place")
			end)
		end,
		CurrentStepsChangedMessageCommand = function(self)
			state = {key = nil}
		end,
		Def.ActorMultiVertex {
			Name = "Draw",
			PlaceCommand = function(self)
				local lanes = BMSPreviewPatterns == true
				local mode = BMSPreviewNoteMode or 0
				local verts = {}
				local used = 0
				if lanes or mode ~= 0 then
					loadChart()
				end
				local nf = self:GetParent():GetParent():GetChild("NoteField")
				local ps = GAMESTATE:GetPlayerState()
				if (lanes or mode ~= 0) and state.ranges and nf and ps then
					local z = nf:GetZoom()
					local nx, ny = nf:GetX(), nf:GetY()
					local function yAt(beat)
						local off = ArrowEffects.GetYOffset(ps, 1, beat)
						return ny + ArrowEffects.GetYPos(ps, 1, off) * z, off
					end

					-- the notes: coloured, or grey when not the picked pattern
					if mode ~= 0 then
						local beats, cols, nk = state.beats, state.col, state.noteKinds
						local x1 = ArrowEffects.GetXPos(ps, 1, 0)
						local x2 = ArrowEffects.GetXPos(ps, 2, 0)
						local w = math.abs(x2 - x1) * z
						if w <= 0 then w = 40 end
						local h = w * 0.5
						local grey = color("0.25,0.25,0.28,0.85")
						local now = GAMESTATE:GetSongPosition():GetSongBeatVisible()
						local i = firstNote(beats, now - 2)
						local outside = 0
						while i <= #beats and outside < 24 do
							local y, off = yAt(beats[i])
							if y < clipTop - h or y > clipBottom + h then
								-- count the notes past the far end of the field
								if off > 0 then outside = outside + 1 end
							else
								outside = 0
								local c
								local k = nk[i] or {}
								if mode == -1 then
									for _, key in ipairs(priority) do
										if k[key] then
											c = color(kinds[kindIndex[key]].color)
											c[4] = 0.8
											break
										end
									end
								elseif k[kinds[mode].key] then
									c = color(kinds[mode].color)
									c[4] = 0.85
								else
									c = grey
								end
								if c then
									local x = nx + ArrowEffects.GetXPos(ps, cols[i] + 1, off) * z
									quad(verts, x - w / 2, y - h / 2, x + w / 2, y + h / 2, c)
								end
							end
							i = i + 1
						end
					end

					-- one lane per pattern right of the field, names where they start
					if lanes then
						local x0 = nx + 24 * 7 + 3
						local placed = {}
						for _, r in ipairs(state.ranges) do
							local y1, y2 = yAt(r.b1), yAt(r.b2)
							local startY = y1
							if y1 > y2 then
								y1, y2 = y2, y1
							end
							if y2 >= clipTop and y1 <= clipBottom then
								local c = color(kinds[r.kind].color)
								c[4] = (mode > 0 and mode ~= r.kind) and 0.3 or 0.85
								local x = x0 + (r.kind - 1) * (laneW + laneGap)
								quad(verts, x, math.max(y1, clipTop), x + laneW, math.min(y2, clipBottom), c)
								local free = startY >= clipTop and startY <= clipBottom and used < MAXLABELS
								for _, py in ipairs(placed) do
									if math.abs(py - startY) < 7 then
										free = false
									end
								end
								if free then
									placed[#placed + 1] = startY
									used = used + 1
									local l = labels[used]
									l:visible(true):xy(x0 + nKinds * (laneW + laneGap) + 4, startY)
									l:settext(kinds[r.kind].name):diffuse(color(kinds[r.kind].color))
								end
							end
						end
					end
				end
				for i = used + 1, MAXLABELS do
					labels[i]:visible(false)
				end
				-- which colouring is on
				if mode == 0 then
					modeText:visible(false)
				else
					modeText:visible(true)
					if mode == -1 then
						modeText:settext("F7: ALL PATTERNS"):diffuse(color("1,1,1,1"))
					else
						modeText:settext("F7: " .. kinds[mode].name):diffuse(color(kinds[mode].color))
					end
				end
				if #verts == 0 then
					self:visible(false)
				else
					self:visible(true):SetVertices(verts)
					self:SetDrawState {Mode = "DrawMode_Quads", First = 1, Num = #verts}
				end
			end,
		},
		LoadFont("Common Normal") .. {
			InitCommand = function(self)
				modeText = self
				self:halign(0):valign(0):xy(wodth / 2 - 24 * 7 + 4, clipTop + 4):zoom(0.4):visible(false)
				self:shadowlength(1):shadowcolor(0, 0, 0, 1)
			end,
		},
	}
	for i = 1, MAXLABELS do
		f[#f + 1] = LoadFont("Common Normal") .. {
			InitCommand = function(self)
				labels[i] = self
				self:halign(0):valign(0.5):zoom(0.32):visible(false)
				self:shadowlength(1):shadowcolor(0, 0, 0, 1)
			end,
		}
	end
	t[#t + 1] = f
end

return t
