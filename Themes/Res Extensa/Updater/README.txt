res extensa in-game updater
===========================

On the title menu, once per game start, the game asks GitHub for the newest
release of paprotka2137/bms2etterna. If its tag is newer than themeInfo.Version
(Scripts/00 ThemeInfo.lua) a window offers it: Update now / Release page /
Later / Skip this version.

Two kinds of update
-------------------
* Quick (files) update: the release's update.json says which game program it
  needs ("build"). If that is the program the player has (ProductVersion(),
  APP_DISPLAY_VERSION in CMakeLists.txt), only res-extensa-files-<ver>.zip
  is downloaded and unpacked over Themes/ECFN etterna, NoteSkins, Data,
  Assets and Scripts in game, then the game restarts.
* Full update: otherwise the package for the player's system is downloaded
  (Windows *.exe installer, Linux *-Linux.tar.gz, macOS *-M1.dmg or
  *-Darwin-x64.dmg), the game quits and update.bat / update.sh (this folder)
  waits for it to close, puts the new version in the same folder and starts
  the game again. On Windows the installer runs silently into the same
  folder (Windows may ask to allow it).

Save, Songs and the player's settings are never touched. The scripts write
what they did to Logs/update.log. A folder with .git in it (a source
checkout) is never updated, it only gets a "new version is out" note.

What a release needs
--------------------
1. Tag vX.Y.Z and themeInfo.Version = "X.Y.Z" (the CI job stops otherwise).
2. Changed anything in src/ (the program)? Bump APP_DISPLAY_VERSION in
   CMakeLists.txt too: players then get the full update. Only theme / noteskin
   changes? Leave APP_DISPLAY_VERSION as it is: players get the quick update.
   The CI job refuses to publish update.json when src/ changed without a bump.
3. Publish the release on GitHub. CI attaches the packages as before plus
   update.json and res-extensa-files-X.Y.Z.zip (job "In-game update files").

Downloads are checked over https (the system's certificates); if that fails
the window says so and Release page opens the download in the browser.
