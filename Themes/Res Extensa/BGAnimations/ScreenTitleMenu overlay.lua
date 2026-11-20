local t = Def.ActorFrame {}

t[#t+1] = LoadActor(THEME:GetPathG("", "_crashUploadOptIn"))

-- new res extensa release on GitHub: offer it (once per game start)
t[#t + 1] = LoadActor("_bmsUpdate")

t[#t + 1] = LoadActor("_cursor")
return t
