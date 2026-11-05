-- 7k gets the beatoraja ECFN result layout, everything else keeps the Til Death one
-- (no "return LoadActor(...)": a tail call drops this file from the stack and
-- LoadActor can't find the folder to resolve the relative path from)
local t
if hideMSD() then
	t = LoadActor("ecfn.lua")
	-- result of a dan course on top
	t = Def.ActorFrame {t, LoadActor("dancourse.lua")}
else
	t = LoadActor("td.lua")
end
return t
