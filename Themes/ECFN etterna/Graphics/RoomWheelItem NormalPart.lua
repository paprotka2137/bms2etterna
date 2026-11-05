-- multiplayer room list: a plain bar behind the room name and description.
-- Without this file the room wheel borrowed the song bars (level digits,
-- LN label, lamp), which only make sense for songs.
if hideMSD() then
    local s = ecfnScale()
    local dir = THEME:GetCurrentThemeDirectory()
    if dir:sub(1, 1) ~= "/" then
        dir = "/" .. dir
    end
    dir = dir .. "BGAnimations/ScreenSelectMusic decorations/ecfn/"
    return Def.Sprite {
        Texture = dir .. "bar 1x8.png",
        InitCommand = function(self)
            -- frame 0: the song bar, rooms look like the song list
            self:animate(false):setstate(0):halign(0):zoomto(730 * s, 52 * s)
        end,
    }
end

return Def.Quad {
    InitCommand = function(self)
        self:halign(0):zoomto(854, 36):diffuse(color("#000000")):diffusealpha(0.45)
    end,
}
