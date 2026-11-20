-- in-game updater: once per game start the title menu asks GitHub for the
-- newest release of res extensa and offers it.
--  * files update: when the release needs the same game program as this
--    one (update.json "build" = ProductVersion()), only the data folders
--    are downloaded (res-extensa-files-<ver>.zip) and unpacked in game,
--    then the game restarts
--  * full update: the package for this system (.exe installer on Windows,
--    .tar.gz on Linux, .dmg on macOS) is downloaded, the game quits and
--    Updater/update.(sh|bat) puts it in and starts the game again
-- Releases without update.json always get the full update. Source
-- checkouts (a .git folder) are never updated, they only get a note.

local REPO = "paprotka2137/bms2etterna"
local API = "https://api.github.com/repos/" .. REPO .. "/releases/latest"
local DIR = "/Cache/Update/"
local SKIP_FILE = "/Save/BMSUpdate_skip.txt"

-- the C++ side came with the updater: older builds have nothing to do here
if not DLMAN.BMSUpdateGet or BMSUpdateChecked then
	return Def.ActorFrame {}
end
BMSUpdateChecked = true

local function readFile(path)
	local str
	local f = RageFileUtil.CreateRageFile()
	if f:Open(path, 1) then
		str = f:Read()
		f:Close()
	end
	f:destroy()
	return str
end
local function writeFile(path, str)
	local f = RageFileUtil.CreateRageFile()
	if f:Open(path, 2) then
		f:Write(str)
		f:Close()
	end
	f:destroy()
end

-- "v0.1.2" -> {0, 1, 2}
local function parts(v)
	local t = {}
	for n in tostring(v or ""):gmatch("%d+") do
		t[#t + 1] = tonumber(n)
	end
	return t
end
local function newer(a, b)
	local x, y = parts(a), parts(b)
	for i = 1, math.max(#x, #y) do
		local p, q = x[i] or 0, y[i] or 0
		if p ~= q then
			return p > q
		end
	end
	return false
end
local function clean(v)
	return (tostring(v or ""):gsub("^[vV]", ""))
end
local function jsonString(body, key)
	return body:match('"' .. key .. '"%s*:%s*"([^"]*)"')
end
local function mb(bytes)
	return string.format("%.1f MB", (bytes or 0) / 1048576)
end

local platform = DLMAN:BMSUpdatePlatform()

-- every step goes to Logs/update.log (the updater scripts add theirs), so a
-- player can send one file when an update doesn't work
local LOG = "/Logs/update.log"
local function note(msg)
	local old = readFile(LOG) or ""
	if #old > 200000 then
		old = old:sub(-100000)
	end
	writeFile(LOG, old .. "[game " .. os.date("%Y-%m-%d %H:%M:%S") .. "] " .. msg .. "\n")
end
local function packageFor(name)
	if platform == "windows" then
		return name:find("%.exe$") ~= nil
	elseif platform == "linux" then
		return name:find("Linux") ~= nil and name:find("%.tar%.gz$") ~= nil
	elseif platform == "mac-arm64" then
		return name:find("M1") ~= nil and name:find("%.dmg$") ~= nil
	else
		return name:find("Darwin%-x64") ~= nil and name:find("%.dmg$") ~= nil
	end
end

local function updaterScript()
	local dir = THEME:GetCurrentThemeDirectory()
	if dir:sub(1, 1) ~= "/" then
		dir = "/" .. dir
	end
	if dir:sub(-1) ~= "/" then
		dir = dir .. "/"
	end
	return dir .. "Updater/" .. (platform == "windows" and "update.bat" or "update.sh")
end

local info = {} -- version, page, mode ("files" | "full" | "page"), url, name, size
local frame
local enabled = false
local busy = false
local redirb4 = false
local pendingPackage

local boxw, boxh = SCREEN_WIDTH * 0.55, SCREEN_HEIGHT * 0.36
local textsize = 0.62
local buttons = {
	{ name = "Update", label = "Update now" },
	{ name = "Page", label = "Release page" },
	{ name = "Later", label = "Later" },
	{ name = "Skip", label = "Skip this version" },
}

local function setText(main, sub)
	if not frame then
		return
	end
	if main then
		frame:GetChild("Text"):settext(main)
	end
	frame:GetChild("Sub"):settext(sub or "")
end

local function close()
	enabled = false
	busy = false
	if frame then
		frame:visible(false)
		frame:SetUpdateFunction(nil)
	end
	SCREENMAN:set_input_redirected(PLAYER_1, redirb4)
end

local function failed(msg)
	note("failed: " .. msg)
	busy = false
	frame:SetUpdateFunction(nil)
	setText(msg, "Release page opens the download in your browser.")
	frame:GetChild("Buttons"):visible(true)
end

local function launch(package)
	setText("Restarting...", "")
	-- a moment so the text shows before the game quits
	pendingPackage = package
	frame:sleep(0.3):queuecommand("Launch")
end

local function startUpdate()
	if info.mode == "page" then
		DLMAN:BMSUpdateOpenPage(info.page)
		close()
		return
	end
	busy = true
	frame:GetChild("Buttons"):visible(false)
	local path = DIR .. info.name
	note("downloading " .. info.url .. " to " .. path)
	setText("Downloading " .. info.name .. "...", "")
	frame:SetUpdateFunction(function()
		local now, total = DLMAN:BMSUpdateProgress()
		if total and total > 0 then
			setText(nil, string.format("%s / %s  (%d%%)", mb(now), mb(total), math.floor(now * 100 / total)))
		elseif now and now > 0 then
			setText(nil, mb(now))
		end
	end)
	DLMAN:BMSUpdateDownload(info.url, path, function(status)
		if not enabled then
			return
		end
		frame:SetUpdateFunction(nil)
		note("download finished: " .. tostring(status))
		if status ~= 200 then
			local why = ""
			if status == 0 then
				why = " No connection, or the https certificate check failed (the game log in Logs says which)."
			elseif status == -1 then
				why = " It couldn't be saved in the game folder: is the folder writable?"
			end
			failed("The download didn't work (" .. tostring(status) .. ")." .. why)
			return
		end
		if info.mode == "files" then
			SOUND:StopMusic()
			local written, bad = DLMAN:BMSUpdateInstallFiles(path)
			note("files update: " .. tostring(written) .. " written, " .. tostring(bad) .. " failed")
			if written == nil then
				failed("The downloaded update couldn't be opened.")
				return
			end
			if bad > 0 then
				failed(bad .. " of " .. (written + bad) .. " files couldn't be written.")
				return
			end
			launch(nil)
		else
			launch(path)
		end
	end)
end

local function choose(name)
	if busy then
		return
	end
	if name == "Update" then
		startUpdate()
	elseif name == "Page" then
		DLMAN:BMSUpdateOpenPage(info.page)
	elseif name == "Skip" then
		writeFile(SKIP_FILE, info.version)
		close()
	else
		close()
	end
end

local function show()
	note("offering " .. tostring(info.version) .. " (" .. tostring(info.mode) .. " " .. tostring(info.name)
		.. ") to " .. getThemeVersion() .. " / program " .. tostring(ProductVersion()) .. " on " .. platform)
	-- the answer came after the title menu was left: ask again next time
	if not frame then
		BMSUpdateChecked = false
		return
	end
	local what
	if info.mode == "files" then
		what = "Quick update: only the game files change (" .. mb(info.size) .. "), then the game restarts."
	elseif info.mode == "full" then
		what = "Full update (" .. mb(info.size) .. "): the game closes, the new version is put in and the game starts again."
			.. (platform == "windows" and " The installer opens with this folder filled in: click Install." or "")
	else
		what = "There is no package for this system in the release: get it from the release page."
	end
	setText(
		"res extensa " .. info.version .. " is out (you have " .. getThemeVersion() .. ").",
		what .. "\nSave, songs and settings stay as they are."
	)
	if info.mode == "page" then
		frame:GetChild("Buttons"):GetChild("Update"):GetChild("Label"):settext("Open page")
	end
	enabled = true
	redirb4 = SCREENMAN:get_input_redirected(PLAYER_1)
	SCREENMAN:set_input_redirected(PLAYER_1, true)
	frame:visible(true)
end

-- the newest release, then its update.json
local function check()
	DLMAN:BMSUpdateGet(API, function(status, body)
		if status ~= 200 or not body then
			note("checking GitHub failed: " .. tostring(status))
			return
		end
		local version = clean(jsonString(body, "tag_name"))
		if version == "" or not newer(version, getThemeVersion()) then
			return
		end
		if clean(readFile(SKIP_FILE)) == version then
			return
		end
		if DLMAN:BMSUpdateIsCheckout() then
			ms.ok("res extensa " .. version .. " is out (source checkout: update with git)")
			return
		end
		info.version = version
		info.page = jsonString(body, "html_url") or ("https://github.com/" .. REPO .. "/releases")
		-- assets: name, size and download url, in that order in each one
		local assets = {}
		local list = body:match('"assets"%s*:%s*(%b[])') or ""
		for name, size, url in list:gmatch(
			'"name"%s*:%s*"([^"]*)".-"size"%s*:%s*(%d+).-"browser_download_url"%s*:%s*"([^"]*)"'
		) do
			assets[#assets + 1] = { name = name, size = tonumber(size), url = url }
		end
		local manifest, package
		for _, a in ipairs(assets) do
			if a.name == "update.json" then
				manifest = a
			elseif packageFor(a.name) and not package then
				package = a
			end
		end
		local function full()
			if package then
				info.mode, info.url, info.name, info.size = "full", package.url, package.name, package.size
			else
				info.mode = "page"
			end
			show()
		end
		if not manifest then
			full()
			return
		end
		DLMAN:BMSUpdateGet(manifest.url, function(st, m)
			local build = st == 200 and m and jsonString(m, "build")
			local files = st == 200 and m and jsonString(m, "files")
			if build and files and clean(build) == clean(ProductVersion()) then
				for _, a in ipairs(assets) do
					if a.name == files then
						info.mode, info.url, info.name, info.size = "files", a.url, a.name, a.size
						show()
						return
					end
				end
			end
			full()
		end)
	end)
end

local function button(i, b)
	local bw = boxw / 4.4
	return Def.ActorFrame {
		Name = b.name,
		InitCommand = function(self)
			self:x((i - 2.5) * (bw + 8))
		end,
		Def.Quad {
			Name = "Back",
			InitCommand = function(self)
				self:zoomto(bw, 30):diffuse(color(i == 1 and "#2f6fbf" or "#3a3f4a"))
			end,
		},
		LoadFont("Common Normal") .. {
			Name = "Label",
			InitCommand = function(self)
				self:zoom(0.5):maxwidth((bw - 8) / 0.5):settext(b.label)
			end,
		},
	}
end

local row = Def.ActorFrame {
	Name = "Buttons",
	InitCommand = function(self)
		self:y(boxh / 2 - 28)
	end,
}
for i, b in ipairs(buttons) do
	row[#row + 1] = button(i, b)
end

return Def.ActorFrame {
	Name = "BMSUpdateDialogue",
	InitCommand = function(self)
		frame = self
		self:xy(SCREEN_CENTER_X, SCREEN_CENTER_Y):visible(false)
	end,
	BeginCommand = function(self)
		check()
		SCREENMAN:GetTopScreen():AddInputCallback(function(event)
			if not enabled then
				return
			end
			if event.type ~= "InputEventType_FirstPress" then
				return true
			end
			local btn = event.DeviceInput.button
			if btn == "DeviceButton_left mouse button" then
				for _, b in ipairs(buttons) do
					local a = self:GetChild("Buttons"):GetChild(b.name):GetChild("Back")
					if self:GetChild("Buttons"):GetVisible() and isOver(a) then
						choose(b.name)
						break
					end
				end
			elseif btn == "DeviceButton_enter" or event.button == "Start" then
				choose("Update")
			elseif btn == "DeviceButton_escape" or event.button == "Back" then
				choose("Later")
			end
			-- the dialog eats all input while it's up
			return true
		end)
	end,
	OffCommand = function(self)
		frame = nil
		enabled = false
	end,
	LaunchCommand = function(self)
		note("starting " .. updaterScript() .. " with " .. tostring(pendingPackage or "-"))
		if not DLMAN:BMSUpdateLaunch(updaterScript(), pendingPackage) then
			failed("The updater couldn't be started.")
		end
	end,
	Def.Quad {
		InitCommand = function(self)
			self:zoomto(SCREEN_WIDTH, SCREEN_HEIGHT):diffuse(color("0,0,0,0.7"))
		end,
	},
	Def.Quad {
		InitCommand = function(self)
			self:zoomto(boxw, boxh):diffuse(color("#10141c"))
		end,
	},
	Def.Quad {
		InitCommand = function(self)
			self:valign(0):y(-boxh / 2):zoomto(boxw, 3):diffuseleftedge(color("#c8d2e0")):diffuserightedge(color("#3f9fff"))
		end,
	},
	LoadFont("Common Normal") .. {
		Name = "Text",
		InitCommand = function(self)
			self:y(-boxh / 2 + 22):valign(0):zoom(textsize + 0.1)
			self:maxwidth(boxw * 0.92 / (textsize + 0.1)):diffuse(color("#6eb4ff"))
		end,
	},
	LoadFont("Common Normal") .. {
		Name = "Sub",
		InitCommand = function(self)
			self:y(-boxh / 2 + 58):valign(0):zoom(textsize)
			self:wrapwidthpixels(boxw * 0.9 / textsize)
		end,
	},
	row,
}
