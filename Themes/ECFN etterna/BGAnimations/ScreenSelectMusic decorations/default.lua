local t = Def.ActorFrame {}

-- 7k: panels of the beatoraja ECFN skin, under the Til Death tabs
if hideMSD() then
	-- with the extension, "ecfn" alone loads the ecfn/ image folder
	t[#t + 1] = LoadActor("ecfn.lua")
end
t[#t + 1] = LoadActor("tabs")
t[#t + 1] = LoadActor("wifetwirl")
t[#t + 1] = LoadActor("msd")
t[#t + 1] = LoadActor("songsearch")
t[#t + 1] = LoadActor("score")
t[#t + 1] = LoadActor("filter")
t[#t + 1] = LoadActor("downloads")
if hideMSD() then
	-- 7k: Profile, Goals and Playlists in the Dan window's look, no Tags
	t[#t + 1] = LoadActor("ranking")
	t[#t + 1] = LoadActor("profile7k")
	t[#t + 1] = LoadActor("goals7k")
	t[#t + 1] = LoadActor("playlists7k")
	t[#t + 1] = LoadActor("dan")
else
	t[#t + 1] = LoadActor("profile.lua")
	t[#t + 1] = LoadActor("goaltracker")
	t[#t + 1] = LoadActor("playlists.lua")
	t[#t + 1] = LoadActor("tags")
end
t[#t + 1] = LoadActor("stepsdisplay")

t[#t + 1] = LoadActor("../_mousewheelscroll")
collectgarbage()
return t
