-- LR2 style gauge drawn over the lifebar on 7k: 50 segments of 2%, colored by
-- the gauge in effect (it changes with gauge auto shift), with the clear line.
-- Other keymodes keep the normal stream.
if not hideMSD() then
	return Def.Actor {}
end

-- same box as the stream pill in metrics ([StreamDisplay]) and MovableBorder
local barX = -35
local barW = 200
local barH = 5
local segments = 50
local segW = barW / segments
local left = barX - barW / 2

local red = color("1,0.2,0.15")
local gauges = {
	Easy = {low = color("0.25,0.9,0.3"), high = red, border = 80},
	Normal = {low = color("0.2,0.6,1"), high = red, border = 80},
	Hard = {low = red, high = red, border = 0},
	ExHard = {low = color("1,0.85,0.1"), high = color("1,0.85,0.1"), border = 0},
	Death = {low = color("0.85,0.1,0.35"), high = color("0.85,0.1,0.35"), border = 0},
	-- dan course gauges
	Class = {low = red, high = red, border = 0},
	ExClass = {low = red, high = red, border = 0},
	ExHardClass = {low = color("1,0.85,0.1"), high = color("1,0.85,0.1"), border = 0}
}

local gauge = gauges.Normal
local lit = 0 -- lit segments
local life = 0
local flickerWait = 0

local function dim(c, f)
	return {c[1] * f, c[2] * f, c[3] * f, 1}
end

local function segColor(i)
	-- segment i holds the gauge from (i-1)*2 to i*2 percent
	return i * 2 > gauge.border and gauge.high or gauge.low
end

local t = Def.ActorFrame {
	Name = "BMSGauge",
	InitCommand = function(self)
		self:SetUpdateFunction(function(self, dt)
			-- the top lit segments flicker like LR2
			flickerWait = flickerWait - dt
			if flickerWait > 0 then
				return
			end
			flickerWait = 0.05
			for i = math.max(1, lit - 2), lit do
				local seg = self:GetChild("Seg" .. i)
				seg:diffuse(math.random() < 0.4 and dim(segColor(i), 0.55) or segColor(i))
			end
		end)
	end,
	LifeChangedMessageCommand = function(self, params)
		local meter = params.LifeMeter
		if meter == nil or (params.Player ~= nil and params.Player ~= PLAYER_1) then
			return
		end
		local stream = meter:GetChild("Stream")
		if stream ~= nil then
			stream:visible(false)
		end
		local classGauge = meter.GetBMSClassGauge and meter:GetBMSClassGauge()
		gauge = gauges[classGauge or meter:GetBMSGauge() or "Normal"] or gauges.Normal
		life = meter:GetLife() * 100
		lit = math.floor(life / 2 + 0.0001)
		for i = 1, segments do
			local c = segColor(i)
			self:GetChild("Seg" .. i):diffuse(i <= lit and c or dim(c, 0.22))
		end
		local border = self:GetChild("Border")
		border:visible(gauge.border > 0)
		border:x(left + barW * gauge.border / 100)
	end,
	Def.Quad {
		Name = "Back",
		InitCommand = function(self)
			self:x(barX):zoomto(barW + 2, barH + 2):diffuse(color("0,0,0,0.8"))
		end
	}
}

for i = 1, segments do
	t[#t + 1] = Def.Quad {
		Name = "Seg" .. i,
		InitCommand = function(self)
			self:halign(0):x(left + (i - 1) * segW):zoomto(segW - 1, barH)
		end
	}
end

t[#t + 1] = Def.Quad {
	Name = "Border",
	InitCommand = function(self)
		self:zoomto(1, barH + 4):diffuse(color("1,1,1,0.9"))
	end
}

return t
