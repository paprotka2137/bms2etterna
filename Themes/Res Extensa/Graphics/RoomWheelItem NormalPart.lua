-- multiplayer room list: a row of the mono song wheel (930 wide, a 1px line
-- under it) behind the room name and description. Without this file the room
-- wheel borrowed the song bars (level digits, LN label, lamp).
if hideMSD() then
	local s = ecfnScale()
	return Def.ActorFrame {
		Def.Quad {
			InitCommand = function(self)
				self:halign(0):zoomto(640 * s, 52 * s):diffuse(rxColor("bg"))
			end,
		},
		Def.Quad {
			InitCommand = function(self)
				self:halign(0):valign(0):y(26 * s):zoomto(640 * s, 1):diffuse(rxColor("line"))
			end,
		},
	}
end

return Def.Quad {
	InitCommand = function(self)
		self:halign(0):zoomto(854, 36):diffuse(color("#000000")):diffusealpha(0.45)
	end,
}
