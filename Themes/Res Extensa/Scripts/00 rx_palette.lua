-- Res Extensa theme palette: the "Mono" look of the res extensa website
-- (leaderboard/site/public/style.css). Near-black ground, white text, 1px
-- lines; color only where it means something (lamps, judgments, gauges).
rxPalette = {
	bg = "#0c0c0c",
	panel = "#111111",
	hover = "#1a1a1a",
	line = "#222222",
	line2 = "#333333",
	text = "#ededed",
	muted = "#8a8a8a",
	dim = "#5a5a5a",
	white = "#ffffff",
	-- lamps, the site's colors
	fc = "#66ffff",
	exhard = "#ffd91a",
	hard = "#ffffff",
	clear = "#4aa8ff",
	easy = "#66ff66",
	assist = "#c080ff",
	failed = "#e61e25",
	noplay = "#2a2a2a",
	-- judgments
	pg = "#a0f0ff",
	gr = "#ffd040",
	gd = "#70ff70",
	bd = "#c080ff",
	pr = "#ff4040",
	fast = "#4aa8ff",
	slow = "#ff8a3a",
	-- medals
	gold = "#ffd700",
	silver = "#c0c0c0",
	bronze = "#cd7f32",
}

-- a palette color, optionally with an alpha 0..1
function rxColor(name, alpha)
	local c = color(rxPalette[name] or name)
	if alpha then
		c[4] = alpha
	end
	return c
end

-- the theme's fonts (Fonts/inter, Inter with the gothic font's Japanese)
rxFont = {
	normal = "RX Normal",
	semibold = "RX SemiBold",
	large = "RX Large",
	light = "RX Light",
	bold = "RX Bold",
}
