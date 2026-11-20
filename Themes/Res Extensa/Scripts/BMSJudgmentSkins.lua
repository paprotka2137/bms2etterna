-- 7k: judgment pictures players drop into the theme, picked in Player Options
-- like a noteskin. Each folder in JudgmentSkins/ is one skin, see
-- JudgmentSkins/README.txt for the file names. "Text" (no folder) is the
-- default LR2 style text judgment.

local IMAGE_EXT = {png = true, jpg = true, jpeg = true, gif = true, bmp = true}

-- every picture a skin can hold
local SKIN_KEYS = {"PGREAT", "GREAT", "GOOD", "BAD", "POOR", "EMPTYPOOR", "COOL", "MISS"}

-- what a missing picture falls back to (before falling back to the text)
local SKIN_FALLBACK = {
	EMPTYPOOR = "POOR",
	COOL = "PGREAT",
	MISS = "POOR",
}

function getJudgmentSkinDir()
	local dir = THEME:GetCurrentThemeDirectory()
	if dir:sub(1, 1) ~= "/" then
		dir = "/" .. dir
	end
	if dir:sub(-1) ~= "/" then
		dir = dir .. "/"
	end
	return dir .. "JudgmentSkins/"
end

-- folder names of all the skins, sorted
function listJudgmentSkins()
	local out = {}
	for _, d in ipairs(FILEMAN:GetDirListing(getJudgmentSkinDir(), true, false) or {}) do
		if d:sub(1, 1) ~= "." and d:sub(1, 1) ~= "_" then
			out[#out + 1] = d
		end
	end
	table.sort(out, function(a, b)
		return a:lower() < b:lower()
	end)
	return out
end

-- {PGREAT = "/Themes/.../PGREAT.png", ...} for a skin, nil when it has no pictures.
-- A file counts for a judgment when its name starts with the judgment name,
-- in any case, so "PGREAT.png", "pgreat.png" and "PGREAT 1x3.png" all work.
function getJudgmentSkinFiles(name)
	if not name or name == "" then
		return nil
	end
	local dir = getJudgmentSkinDir() .. name .. "/"
	local files = FILEMAN:GetDirListing(dir, false, false) or {}
	table.sort(files)
	local wanted = {}
	for _, k in ipairs(SKIN_KEYS) do
		wanted[k:lower()] = k
	end
	local out, any = {}, false
	for _, f in ipairs(files) do
		local ext = f:match("%.(%w+)$")
		local base = f:lower():match("^(%a+)")
		local key = base and wanted[base]
		if ext and IMAGE_EXT[ext:lower()] and key and not out[key] then
			out[key] = dir .. f
			any = true
		end
	end
	return any and out or nil
end

-- the picture for a judgment name ("PGREAT", "COOL", "EMPTYPOOR"...), nil to use text
function getJudgmentSkinKey(files, judgeName)
	if not files or not judgeName then
		return nil
	end
	local k = judgeName
	while k do
		if files[k] then
			return k
		end
		k = SKIN_FALLBACK[k]
	end
	return nil
end

function getJudgmentSkinKeys()
	return SKIN_KEYS
end

-- the skin the player picked, nil for the text judgment or when the folder is gone
function getPlayerJudgmentSkin(pn)
	local name = playerConfig:get_data(pn_to_profile_slot(pn or PLAYER_1)).JudgmentSkin
	if type(name) ~= "string" or name == "" then
		return nil
	end
	for _, d in ipairs(listJudgmentSkins()) do
		if d == name then
			return name
		end
	end
	return nil
end

-- Player Options row
function JudgmentSkin()
	local skins = listJudgmentSkins()
	local choices = {THEME:GetString("OptionNames", "JudgmentSkinText")}
	for _, s in ipairs(skins) do
		choices[#choices + 1] = s
	end
	local t = {
		Name = "JudgmentSkin",
		LayoutType = "ShowOneInRow",
		SelectType = "SelectOne",
		OneChoiceForAllPlayers = false,
		ExportOnChange = false,
		ExportOnCancel = true,
		Choices = choices,
		LoadSelections = function(self, list, pn)
			local cur = getPlayerJudgmentSkin(pn)
			for i, s in ipairs(skins) do
				if s == cur then
					list[i + 1] = true
					return
				end
			end
			list[1] = true
		end,
		SaveSelections = function(self, list, pn)
			local value = ""
			for i = 2, #list do
				if list[i] then
					value = skins[i - 1]
					break
				end
			end
			playerConfig:get_data(pn_to_profile_slot(pn)).JudgmentSkin = value
			playerConfig:set_dirty(pn_to_profile_slot(pn))
			playerConfig:save(pn_to_profile_slot(pn))
		end
	}
	setmetatable(t, t)
	return t
end
