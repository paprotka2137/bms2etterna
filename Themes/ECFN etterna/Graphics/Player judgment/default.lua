local allowedCustomization = playerConfig:get_data(pn_to_profile_slot(PLAYER_1)).CustomizeGameplay
local c
local enabledJudgment = playerConfig:get_data(pn_to_profile_slot(PLAYER_1)).JudgmentText
local JTEnabled = JudgementTweensEnabled()

--[[
-- old commands from metrics [Judgment]:
JudgmentW1Command=shadowlength,0;diffusealpha,1;zoom,1.3;linear,0.05;zoom,1;sleep,0.8;smooth,0.1;zoomy,0.5;zoomx,2;diffusealpha,0;glowblink;effectperiod,0.05;effectcolor1,color("1,1,1,0");effectcolor2,color("1,1,1,0.25")
JudgmentW2Command=shadowlength,0;diffusealpha,1;zoom,1.2;linear,0.05;zoom,1;sleep,0.8;smooth,0.1;zoomy,0.5;zoomx,2;diffusealpha,0
JudgmentW3Command=shadowlength,0;diffusealpha,1;zoom,1.2;linear,0.05;zoom,1;sleep,0.8;smooth,0.1;zoomy,0.5;zoomx,2;diffusealpha,0;
JudgmentW4Command=shadowlength,0;diffusealpha,1;zoom,1.1;linear,0.05;zoom,1;sleep,0.8;smooth,0.1;zoomy,0.5;zoomx,2;diffusealpha,0;
JudgmentW5Command=shadowlength,0;diffusealpha,1;zoom,1.05;linear,0.05;zoom,1;sleep,0.8;smooth,0.1;zoomy,0.5;zoomx,2;diffusealpha,0;
JudgmentMissCommand=shadowlength,0;diffusealpha,1;zoom,1.05;linear,0.05;zoom,1;sleep,0.8;smooth,0.1;zoomy,0.5;zoomx,2;diffusealpha,0;
]]

local JudgeCmds = {
	TapNoteScore_W1 = function(self)
		local jz = MovableValues.JudgeZoom or 1
		self:shadowlength(0):diffusealpha(1):zoom(1.3 * jz)
		self:linear(0.05)
		self:zoom(1 * jz)
		self:sleep(0.8):smooth(0.1)
		self:zoomy(0.5 * jz):zoomx(2 * jz):diffusealpha(0)
		self:glowblink():effectperiod(0.05):effectcolor1(color("1,1,1,0")):effectcolor2(color("1,1,1,0.25"))
	end,
	TapNoteScore_W2 = function(self)
		local jz = MovableValues.JudgeZoom or 1
		self:shadowlength(0):diffusealpha(1):zoom(1.2 * jz)
		self:linear(0.05)
		self:zoom(1 * jz)
		self:sleep(0.8):smooth(0.1)
		self:zoomy(0.5 * jz):zoomx(2 * jz):diffusealpha(0)
	end,
	TapNoteScore_W3 = function(self)
		local jz = MovableValues.JudgeZoom or 1
		self:shadowlength(0):diffusealpha(1):zoom(1.2 * jz)
		self:linear(0.05)
		self:zoom(1 * jz)
		self:sleep(0.8):smooth(0.1)
		self:zoomy(0.5 * jz):zoomx(2 * jz):diffusealpha(0)
	end,
	TapNoteScore_W4 = function(self)
		local jz = MovableValues.JudgeZoom or 1
		self:shadowlength(0):diffusealpha(1):zoom(1.1 * jz)
		self:linear(0.05)
		self:zoom(1 * jz)
		self:sleep(0.8):smooth(0.1)
		self:zoomy(0.5 * jz):zoomx(2 * jz):diffusealpha(0)
	end,
	TapNoteScore_W5 = function(self)
		local jz = MovableValues.JudgeZoom or 1
		self:shadowlength(0):diffusealpha(1):zoom(1.05 * jz)
		self:linear(0.05)
		self:zoom(1 * jz)
		self:sleep(0.8):smooth(0.1)
		self:zoomy(0.5 * jz):zoomx(2 * jz):diffusealpha(0)
	end,
	TapNoteScore_Miss = function(self)
		local jz = MovableValues.JudgeZoom or 1
		self:shadowlength(0):diffusealpha(1):zoom(1.05 * jz)
		self:linear(0.05)
		self:zoom(1 * jz)
		self:sleep(0.8):smooth(0.1)
		self:zoomy(0.5 * jz):zoomx(2 * jz):diffusealpha(0)
	end,
}

local TNSFrames = {
	TapNoteScore_W1 = 0,
	TapNoteScore_W2 = 1,
	TapNoteScore_W3 = 2,
	TapNoteScore_W4 = 3,
	TapNoteScore_W5 = 4,
	TapNoteScore_Miss = 5
}

local function judgmentZoom(value)
    c.Judgment:zoom(value)
    if allowedCustomization then
	    c.Border:playcommand("ChangeWidth", {val = c.Judgment:GetZoomedWidth()})
	    c.Border:playcommand("ChangeHeight", {val = c.Judgment:GetZoomedHeight()})
	end
end

-- 7k shows LR2 judgment names as text instead of the judgment graphic
local bms = hideMSD()

-- LR2 style text judgment: quick pop, then hold and fade
local function showBMSJudgment(self, tns)
	local jz = MovableValues.JudgeZoom or 1
	self:finishtweening():stopeffect():visible(true)
	self:settext(getBMSJudgeName(tns)):diffuse(getBMSJudgeColor(tns)):diffusealpha(1)
	if tns == "TapNoteScore_W1" then
		self:diffuseshift():effectperiod(0.08):effectcolor1(color("#80e8ff")):effectcolor2(color("#ffffa0"))
	end
	if JTEnabled then
		self:zoom(1.15 * jz):linear(0.05):zoom(1 * jz):sleep(0.5):linear(0.1):diffusealpha(0)
	else
		self:zoom(jz)
	end
end

local judgmentActor
if bms then
	judgmentActor = LoadFont("Common Large") .. {
		Name = "Judgment",
		InitCommand = function(self)
			self:visible(false):xy(MovableValues.JudgeX, MovableValues.JudgeY):shadowlength(1)
			self:settext("PGREAT")
		end,
		ResetCommand = function(self)
			self:finishtweening():stopeffect():visible(false)
		end
	}
else
	judgmentActor = Def.Sprite {
		Texture = "../../../../" .. getAssetPath("judgment"),
		Name = "Judgment",
		InitCommand = function(self)
			self:pause():visible(false):xy(MovableValues.JudgeX, MovableValues.JudgeY)
		end,
		ResetCommand = function(self)
			self:finishtweening():stopeffect():visible(false)
		end
	}
end

local t = Def.ActorFrame {
	judgmentActor,
	OnCommand = function(self)
		c = self:GetChildren()
		judgmentZoom(MovableValues.JudgeZoom)
		if allowedCustomization then
			Movable.DeviceButton_1.element = c
			Movable.DeviceButton_2.element = c
			Movable.DeviceButton_1.condition = enabledJudgment
			Movable.DeviceButton_2.condition = enabledJudgment
			Movable.DeviceButton_2.DeviceButton_up.arbitraryFunction = judgmentZoom
			Movable.DeviceButton_2.DeviceButton_down.arbitraryFunction = judgmentZoom
			Movable.DeviceButton_1.propertyOffsets = {self:GetTrueX() , self:GetTrueY()}	-- centered to screen/valigned
		end
	end,
	JudgmentMessageCommand = function(self, param)
		if param.HoldNoteScore or param.FromReplay then
			return
		end
		if bms then
			if getBMSJudgeName(param.TapNoteScore) then
				showBMSJudgment(c.Judgment, param.TapNoteScore)
			end
			return
		end
		local iNumStates = c.Judgment:GetNumStates()
		local iFrame = TNSFrames[param.TapNoteScore]
		if not iFrame then
			return
		end
		if iNumStates == 12 then
			iFrame = iFrame * 2
			if not param.Early then
				iFrame = iFrame + 1
			end
		end

		self:playcommand("Reset")
		c.Judgment:visible(true)
		c.Judgment:setstate(iFrame)
		if JTEnabled then
			JudgeCmds[param.TapNoteScore](c.Judgment)
		end
	end,
	-- LR2 BAD that leaves the note in the lane
	LR2BadMessageCommand = function(self)
		if bms then
			showBMSJudgment(c.Judgment, "TapNoteScore_W4")
		end
	end,
	-- LR2 empty POOR: a press with no note to hit, the combo stays
	EmptyPoorMessageCommand = function(self)
		if bms then
			showBMSJudgment(c.Judgment, "TapNoteScore_Miss")
		end
	end,
	MovableBorder(0, 0, 1, MovableValues.JudgeX, MovableValues.JudgeY)
}

if enabledJudgment then
	return t
end

return Def.ActorFrame {}
