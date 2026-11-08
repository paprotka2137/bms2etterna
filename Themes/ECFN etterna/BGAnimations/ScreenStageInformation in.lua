-- 7k: the ECFN decide screen shows up at once, without the black fade in
-- every other screen has (Screen in.lua)
if hideMSD() then
	return Def.ActorFrame {}
end
local t = LoadActor("Screen in")
return t
