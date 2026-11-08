-- R Skin v3.0 (paprotka edit) smieszne ln, converted from the osu!mania skin
-- (Retsukiya's R Skin, [Mania] Keys: 7 section of skin.ini) to an Etterna kb7 noteskin.
--
-- osu! 7K setup: notes are flat bars (mania-noteS), the LN head is
-- the same note, the LN body is lnekx (grey bar), the LN tail T.png is empty.

local ret = ... or {}

-- column colours as osu! shows this skin: white, blue, white, pink, white, blue, white
ret.ColumnColor = {
	Key1 = "White", Key2 = "Blue", Key3 = "White", Key4 = "Pink",
	Key5 = "White", Key6 = "Blue", Key7 = "White"
}

ret.ElementRedir = {
	["Tap Lift"] = "Tap Note",
	["Tap Fake"] = "Tap Note",
	["Hold Head Inactive"] = "Hold Head Active",
	["Roll Head Active"] = "Hold Head Active",
	["Roll Head Inactive"] = "Hold Head Active",
	["Hold Tail Inactive"] = "Hold Tail Active",
	["Roll Tail Active"] = "Hold Tail Active",
	["Roll Tail Inactive"] = "Hold Tail Active",
	["Roll Body Active"] = "Hold Body Active",
	["Roll Body Inactive"] = "Hold Body Inactive"
}

-- no hold caps (the osu! skin has none)
ret.Blank = {
	["Hold TopCap Active"] = true,
	["Hold TopCap Inactive"] = true,
	["Hold BottomCap Active"] = true,
	["Hold BottomCap Inactive"] = true,
	["Roll TopCap Active"] = true,
	["Roll TopCap Inactive"] = true,
	["Roll BottomCap Active"] = true,
	["Roll BottomCap Inactive"] = true
}

-- note height in the textures; osu! times a note on its front edge, so notes
-- are drawn half a note back from the timing point
local NOTE_HEIGHT = 32
ret.FrontEdge = {
	["Tap Note"] = true,
	["Tap Mine"] = true,
	["Hold Head Active"] = true
}

-- Etterna passes element names with different capitalisation (Topcap vs TopCap,
-- Bottomcap vs BottomCap), and Lua tables are case-sensitive, which let the
-- default noteskin's blue hold caps through. Compare in lowercase.
local function isCap(sElement)
	local l = sElement:lower()
	return l:find("topcap", 1, true) ~= nil or l:find("bottomcap", 1, true) ~= nil
end

local canon = {}
for _, tbl in ipairs({ ret.ElementRedir, ret.Blank, ret.FrontEdge }) do
	for k, v in pairs(tbl) do
		canon[k:lower()] = k
		if type(v) == "string" then canon[v:lower()] = v end
	end
end
canon["hold tail active"] = "Hold Tail Active"
local function canonical(sElement)
	return canon[sElement:lower()] or sElement
end

-- Set to true (downscroll) or false (upscroll) if the scroll direction is
-- detected wrongly (LN heads on the wrong end, notes half a note off).
local FORCE_REVERSE = nil

-- In downscroll the engine draws the LN head graphic on the far (tail) end and
-- the tail graphic on the near (head) end. true = swap them back in downscroll.
local SWAP_HEAD_TAIL_WHEN_REVERSE = true

local function reverse()
	if FORCE_REVERSE ~= nil then return FORCE_REVERSE end
	local function try(level)
		local ok, rev = pcall(function()
			local ps = GAMESTATE:GetPlayerState()
			local po = level and ps:GetPlayerOptions(level) or ps:GetCurrentPlayerOptions()
			return po:UsingReverse()
		end)
		return ok and rev == true
	end
	return try("ModsLevel_Preferred") or try("ModsLevel_Current") or try(nil)
end

ret.Redir = function(sButton, sElement)
	return ret.ColumnColor[sButton] or "White", ret.ElementRedir[sElement] or sElement
end

local function blank()
	local t
	if Var "SpriteOnly" then
		t = LoadActor("_blank")
	else
		t = Def.Actor {}
	end
	return t .. {
		InitCommand = function(self)
			self:visible(false)
		end
	}
end

local function shifted(actor, off)
	if Var "SpriteOnly" then return actor end
	return Def.ActorFrame {
		actor .. {
			InitCommand = function(self)
				self:y(off)
			end
		}
	}
end

local function func()
	local sButton = Var "Button"
	local sElement = canonical(Var "Element")

	if ret.Blank[sElement] or isCap(sElement) then
		return blank()
	end

	local sButtonToLoad, sElementToLoad = ret.Redir(sButton, sElement)
	local rev = reverse()

	if sElementToLoad == "Hold Head Active" or sElementToLoad == "Hold Tail Active" then
		-- which end of the LN this graphic is drawn on
		local nearEnd = (sElementToLoad == "Hold Head Active")
		if SWAP_HEAD_TAIL_WHEN_REVERSE and rev then
			nearEnd = not nearEnd
		end
		if not nearEnd then
			-- far end: T.png is empty in the osu! skin
			return blank()
		end
		local head = LoadActor(NOTESKIN:GetPath(sButtonToLoad, "Hold Head Active"))
		return shifted(head, rev and -NOTE_HEIGHT / 2 or NOTE_HEIGHT / 2)
	end

	local actor = LoadActor(NOTESKIN:GetPath(sButtonToLoad, sElementToLoad))
	if ret.FrontEdge[sElementToLoad] then
		return shifted(actor, rev and -NOTE_HEIGHT / 2 or NOTE_HEIGHT / 2)
	end
	return actor
end

ret.Load = func
ret.CommonLoad = func

return ret
