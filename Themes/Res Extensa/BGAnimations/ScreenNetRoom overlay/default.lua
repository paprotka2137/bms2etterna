local t = Def.ActorFrame { }

t[#t + 1] =
	Def.Actor {
	CodeMessageCommand = function(self, params)
		if params.Name == "AvatarShow" and not SCREENMAN:get_input_redirected(PLAYER_1) then
			SCREENMAN:SetNewScreen("ScreenAssetSettings")
		end
	end,
	OnCommand = function(self)
		inScreenSelectMusic = true
	end,
	EndCommand = function(self)
		inScreenSelectMusic = nil
	end
}

if hideMSD() then
	-- 7k: the ECFN bottom bar of the song select, the title is in decorations/ecfn.lua
	t[#t + 1] = LoadActorWithParams("../_frame", {ecfn = true})
	t[#t + 1] = LoadActorWithParams("../_PlayerInfo", {ecfn = true})
	t[#t + 1] = LoadActor("../_cursor")
	t[#t + 1] = LoadActor("../_mousewheelscroll")
	t[#t + 1] = LoadActor("../_halppls")
	return t
end

t[#t + 1] = LoadActor("../_frame")
t[#t + 1] = LoadActor("../_PlayerInfo")
t[#t + 1] = LoadActor("currentsort")
t[#t + 1] =
	LoadFont("Common Large") ..
	{
		InitCommand = function(self)
			self:xy(5, 32):halign(0):valign(1):zoom(0.55):diffuse(getMainColor("positive"))
			self:settext(THEME:GetString("ScreenNetRoom", "Title"))
		end
	}
t[#t + 1] = LoadActor("../_cursor")
t[#t + 1] = LoadActor("../_mousewheelscroll")
t[#t + 1] = LoadActor("../_halppls")
--t[#t + 1] = LoadActor("../_userlist")
t[#t + 1] = LoadActor("../_lobbyuserlist")

return t
