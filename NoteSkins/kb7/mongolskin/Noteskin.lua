-- mongolskin (kb7), converted from the osu!mania skin "#마지막 스킨 [Stellium Skin]"
-- by Applemango, [Mania] Keys: 7 section of Skin.ini.
--
-- osu! 7K setup: taps and LN heads use mania-note1 / note2 / noteS (white, blue, gold),
-- the LN is Notes4K/LN.png (grey bar with a rounded end), keys are mania/arrows/key1b.

local ret = ... or {}

-- osu! default 7K column order: note1, note2, note1, noteS, note1, note2, note1
ret.ColumnColor = {
	Key1 = "White", Key2 = "Blue", Key3 = "White", Key4 = "Gold",
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

-- the LN bar is the same in every column
ret.Shared = {
	["Hold Body Active"] = true,
	["Hold Body Inactive"] = true,
	["Hold Tail Active"] = true
}

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
local NOTE_HEIGHT = 38
ret.FrontEdge = {
	["Tap Note"] = true,
	["Tap Mine"] = true,
	["Hold Head Active"] = true
}
-- the LN end (rounded cap) is drawn from the tail's timing point toward the head
local TAIL_HEIGHT = 29

-- Etterna / StepMania pass element names with different capitalisation
-- (Topcap vs TopCap, Bottomcap vs BottomCap), and Lua tables are case-sensitive,
-- which let the default noteskin's hold caps through. Compare in lowercase.
local function isCap(sElement)
	local l = sElement:lower()
	return l:find("topcap", 1, true) ~= nil or l:find("bottomcap", 1, true) ~= nil
end

local canon = {}
for _, tbl in ipairs({ ret.ElementRedir, ret.Shared, ret.Blank, ret.FrontEdge }) do
	for k, v in pairs(tbl) do
		canon[k:lower()] = k
		if type(v) == "string" then canon[v:lower()] = v end
	end
end
local function canonical(sElement)
	return canon[sElement:lower()] or sElement
end

-- scroll direction; check the preferred options too, because the current ones
-- may not be applied yet when the noteskin is loaded
-- If the LN end (the rounded cap) points the wrong way, or the heads sit half a
-- note off, the scroll direction was detected wrongly. Set this to true
-- (downscroll) or false (upscroll) to override the detection.
local FORCE_REVERSE = nil

-- In downscroll the engine draws the LN head graphic on the far (tail) end and the
-- tail graphic on the near (head) end, which made the LN look upside down.
-- true = swap the two graphics in downscroll (default), false = leave as the engine draws them.
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
	sElement = ret.ElementRedir[sElement] or sElement
	if ret.Shared[sElement] then
		return "Fallback", sElement
	end
	return ret.ColumnColor[sButton] or "White", sElement
end

local function func()
	local sButton = Var "Button"
	local sElement = canonical(Var "Element")

	if ret.Blank[sElement] or isCap(sElement) then
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

	local sButtonToLoad, sElementToLoad = ret.Redir(sButton, sElement)
	if SWAP_HEAD_TAIL_WHEN_REVERSE and reverse() then
		if sElementToLoad == "Hold Head Active" then
			-- drawn on the far end of the LN: put the rounded cap there (apex away from the body)
			local cap = LoadActor("_tailup")
			if Var "SpriteOnly" then return cap end
			return Def.ActorFrame {
				cap .. {
					InitCommand = function(self)
						self:y(TAIL_HEIGHT / 2)
					end
				}
			}
		elseif sElementToLoad == "Hold Tail Active" then
			-- drawn on the near end of the LN: this is where the head note belongs
			local head = LoadActor(NOTESKIN:GetPath(ret.ColumnColor[sButton] or "White", "Hold Head Active"))
			if Var "SpriteOnly" then return head end
			return Def.ActorFrame {
				head .. {
					InitCommand = function(self)
						self:y(-NOTE_HEIGHT / 2)
					end
				}
			}
		end
	end

	local actor = LoadActor(NOTESKIN:GetPath(sButtonToLoad, sElementToLoad))
	if Var "SpriteOnly" then
		return actor
	end

	if ret.FrontEdge[sElementToLoad] then
		local off = reverse() and -NOTE_HEIGHT / 2 or NOTE_HEIGHT / 2
		return Def.ActorFrame {
			actor .. {
				InitCommand = function(self)
					self:y(off)
				end
			}
		}
	end

	if sElementToLoad == "Hold Tail Active" then
		-- the flip is baked into the textures (the engine ignored zoom/rotation here):
		-- "Fallback Hold Tail Active.png" has its rounded end pointing down (upscroll),
		-- "_tailup.png" has it pointing up (downscroll)
		local rev = reverse()
		local tail = rev and LoadActor("_tailup") or actor
		return Def.ActorFrame {
			tail .. {
				InitCommand = function(self)
					self:y(rev and TAIL_HEIGHT / 2 or -TAIL_HEIGHT / 2)
				end
			}
		}
	end

	return actor
end

ret.Load = func
ret.CommonLoad = func

return ret
