-- osu! key image (mania/arrows/key1b, pressed: key1Db): an outlined frame that
-- sits on the hit position. The skin has no stage hint and no column lights.
return Def.ActorFrame {
	Def.Sprite {
		Texture = "_key.png"
	},
	Def.Sprite {
		Texture = "_key pressed.png",
		InitCommand = function(self)
			self:visible(false)
		end,
		PressCommand = function(self)
			self:visible(true)
		end,
		LiftCommand = function(self)
			self:visible(false)
		end
	}
}
