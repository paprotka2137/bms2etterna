-- 7k: the song's picture over the whole screen under a dark veil, like the
-- result screen; everything else gets the song background of Til Death
if not hideMSD() then
	local t = LoadActor("_songbg")
	return t
end

-- the picture of the song under the wheel, loaded once the wheel has rested
-- a moment so scrolling does not load every picture on the way
local function songPicture()
	local song = GAMESTATE:GetCurrentSong()
	return song and (song:GetBackgroundPath() or song:GetJacketPath() or song:GetBannerPath())
end

return Def.ActorFrame {
	Def.Quad {
		InitCommand = function(self)
			self:halign(0):valign(0):zoomto(SCREEN_WIDTH, SCREEN_HEIGHT):diffuse(rxColor("bg"))
		end,
	},
	Def.Sprite {
		Name = "SongPicture",
		BeginCommand = function(self)
			self:queuecommand("Wait")
		end,
		CurrentSongChangedMessageCommand = function(self)
			self:queuecommand("Wait")
		end,
		WaitCommand = function(self)
			self.want = songPicture()
			if self.want ~= self.pic then
				self:stoptweening():linear(0.12):diffusealpha(0):sleep(0.12):queuecommand("Load")
			elseif self.pic then
				-- back on the song shown: undo a fade that had started
				self:stoptweening():linear(0.1):diffusealpha(1)
			end
		end,
		LoadCommand = function(self)
			local pic = songPicture()
			if pic ~= self.want then
				return
			end
			self.pic = pic
			if not pic then
				self:visible(false)
				return
			end
			self:visible(true):LoadBackground(pic)
			local tex = self:GetTexture()
			local w, h = tex:GetSourceWidth(), tex:GetSourceHeight()
			local z = math.max(SCREEN_WIDTH / math.max(w, 1), SCREEN_HEIGHT / math.max(h, 1))
			-- a little bigger than the screen so it can slide in and pulse
			z = z * 1.04
			self:zoomto(w * z, h * z)
			self:xy(SCREEN_CENTER_X + 40, SCREEN_CENTER_Y):diffusealpha(0)
			self:decelerate(0.35):x(SCREEN_CENTER_X):diffusealpha(1)
			-- a soft pulse on the beat of the preview
			self:effectclock("beat"):pulse():effectmagnitude(1, 1.012, 1):effectperiod(1)
		end,
	},
	-- the veil: dark enough on the left for the panel, a bit lighter in the
	-- middle, and a darker band under the centered wheel so its rows read
	Def.Quad {
		InitCommand = function(self)
			self:halign(0):valign(0):zoomto(SCREEN_WIDTH, SCREEN_HEIGHT)
			self:diffuse(rxColor("bg", 0.72))
		end,
	},
	Def.Quad {
		InitCommand = function(self)
			self:halign(0):valign(0):x(ecfnX(1244)):zoomto(SCREEN_WIDTH - ecfnX(1244), SCREEN_HEIGHT)
			self:diffuse(rxColor("bg", 0.7))
		end,
	},
	-- a fullscreen button for right click pausing so your right clicks dont pause accidentally
	UIElements.QuadButton(-1000, 1) .. {
		InitCommand = function(self)
			self:valign(0):halign(0)
			self:zoomto(SCREEN_WIDTH, SCREEN_HEIGHT)
			self:diffusealpha(0)
		end,
		MouseDownCommand = function(self, params)
			if params.event == "DeviceButton_right mouse button" then
				SCREENMAN:GetTopScreen():PauseSampleMusic()
				MESSAGEMAN:Broadcast("MusicPauseToggled")
			end
		end
	},
}
