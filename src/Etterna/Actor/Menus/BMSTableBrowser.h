#ifndef BMS_TABLE_BROWSER_H
#define BMS_TABLE_BROWSER_H

#include <string>
#include <vector>

class Song;

/* BMS difficulty tables for the music wheel's "Tables" folder.
 *
 * A table comes from two places:
 *  - the converted packs in Songs, named "BMS2SM - <prefix><level>"
 *    ("BMS2SM - st03" is Stella level 3), which say which charts are here;
 *  - Assets/BMSTables/<id>.json (written by tools/update_bms_tables.py from
 *    the table's own header.json / data.json), which lists every chart of
 *    the table, so the ones that are not here show up as unavailable.
 * Either one alone is enough. */
namespace BMSTableBrowser {

struct Entry
{
	std::string title;
	std::string artist;
	Song* song = nullptr; // nullptr: not in the Songs folder
};

struct Level
{
	std::string level; // "3", "?", "BEGINNER"
	std::string label; // "st3", the name of the level's folder
	std::vector<Entry> entries;
};

struct Table
{
	std::string id; // "stella"
	std::string name; // "Stella"
	std::string symbol; // "st"
	int order = 100;
	std::vector<Level> levels;

	[[nodiscard]] auto NumCharts() const -> int;
	[[nodiscard]] auto NumAvailable() const -> int;
};

// every table with its charts matched to the given songs (the wheel's
// songs after its filters); songs outside of them are left out entirely
auto
Build(const std::vector<Song*>& songs) -> std::vector<Table>;

// read the json files again next time (they are kept after the first read)
void
Reload();

} // namespace BMSTableBrowser

#endif
