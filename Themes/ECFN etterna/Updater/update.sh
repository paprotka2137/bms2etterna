#!/bin/sh
# res extensa updater for Linux and macOS, started by the game
# (DLMAN:BMSUpdateLaunch) right before it quits.
#   update.sh <game pid> <package or -> <game folder>
# Waits for the game to close, puts the new release in (a .tar.gz on Linux,
# a .dmg on macOS, "-" for nothing: only a restart) and starts the game
# again. Save, Songs and the rest of your files are not touched: the
# packages don't hold them. What happened goes to Logs/update.log.

PID="$1"
PKG="$2"
ROOT="$3"

# run a copy from the temp folder: the update replaces this file while the
# shell is still reading it
if [ "$4" != "copied" ]; then
	COPY="$(mktemp "${TMPDIR:-/tmp}/res-extensa-update.XXXXXX")" &&
		cp "$0" "$COPY" && exec sh "$COPY" "$PID" "$PKG" "$ROOT" copied
fi

mkdir -p "$ROOT/Logs"
exec >>"$ROOT/Logs/update.log" 2>&1
echo "=== $(date) update: $PKG into $ROOT"

# the game has to be closed before its files can be swapped
n=0
while kill -0 "$PID" 2>/dev/null; do
	sleep 1
	n=$((n + 1))
	if [ "$n" -ge 120 ]; then
		echo "the game (pid $PID) didn't close, giving up"
		exit 1
	fi
done

start_game() {
	if [ "$(uname)" = "Darwin" ]; then
		open "$ROOT/Etterna.app"
	else
		cd "$ROOT" && nohup ./Etterna >/dev/null 2>&1 &
	fi
}

if [ "$PKG" = "-" ]; then
	start_game
	exit 0
fi

# a source checkout (where the game is built) updates with git instead
if [ -e "$ROOT/.git" ]; then
	echo "$ROOT is a git checkout, not updating it"
	start_game
	exit 1
fi

TMP="$(mktemp -d "${TMPDIR:-/tmp}/res-extensa-update.XXXXXX")" || exit 1
ok=0
case "$PKG" in
*.tar.gz)
	if tar xzf "$PKG" -C "$TMP"; then
		# the package holds <name>/Etterna/Etterna and the data folders next to it
		BIN="$(find "$TMP" -maxdepth 3 -type f -name Etterna | head -n 1)"
		if [ -n "$BIN" ]; then
			SRC="$(dirname "$BIN")"
			cp -Rf "$SRC/." "$ROOT/" && chmod +x "$ROOT/Etterna" && ok=1
		fi
	fi
	;;
*.dmg)
	if hdiutil attach -nobrowse -readonly -mountpoint "$TMP/dmg" "$PKG"; then
		APP="$(find "$TMP/dmg" -maxdepth 3 -type d -name Etterna.app | head -n 1)"
		if [ -n "$APP" ]; then
			SRC="$(dirname "$APP")"
			# a new app bundle, not one mixed with the old one
			rm -rf "$ROOT/Etterna.app.old"
			mv "$ROOT/Etterna.app" "$ROOT/Etterna.app.old" 2>/dev/null
			if ditto "$SRC" "$ROOT"; then
				rm -rf "$ROOT/Etterna.app.old"
				ok=1
			else
				rm -rf "$ROOT/Etterna.app"
				mv "$ROOT/Etterna.app.old" "$ROOT/Etterna.app"
			fi
		fi
		hdiutil detach "$TMP/dmg" -quiet
	fi
	;;
esac
rm -rf "$TMP"

if [ "$ok" = 1 ]; then
	echo "updated"
	rm -f "$PKG"
else
	echo "update failed, starting the old version"
fi
start_game
[ "$4" = "copied" ] && rm -f "$0"
