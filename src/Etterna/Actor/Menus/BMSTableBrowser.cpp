#include "Etterna/Globals/global.h"
#include "BMSTableBrowser.h"
#include "Core/Services/Locator.hpp"
#include "Etterna/Models/Songs/Song.h"
#include "RageUtil/File/RageFileManager.h"
#include "RageUtil/Utils/RageUtil.h"

#include "rapidjson/document.h"

#include <algorithm>
#include <map>
#include <set>
#include <unordered_map>

namespace BMSTableBrowser {

namespace {

// a table as read from a json file, before it meets the songs
struct ChartDef
{
	std::string level;
	std::string title;
	std::string artist;
};
struct TableDef
{
	std::string id;
	std::string name;
	std::string symbol;
	int order = 100;
	std::vector<std::string> packs;	 // pack prefixes ("st")
	std::vector<std::string> levels; // level order, may be empty
	std::vector<ChartDef> charts;
	bool fromJson = false;
};

// the tables the converted packs are named after (the same short names
// as the ranking site and the theme's table line)
auto
BuiltinTables() -> std::vector<TableDef>
{
	auto t = [](const char* id,
				const char* name,
				const char* symbol,
				int order,
				std::vector<std::string> packs) {
		TableDef d;
		d.id = id;
		d.name = name;
		d.symbol = symbol;
		d.order = order;
		d.packs = std::move(packs);
		return d;
	};
	return {
		t("insane", "Insane", "\xE2\x98\x85", 1, { "sp" }),
		t("satellite", "Satellite", "sl", 2, { "sl" }),
		t("stella", "Stella", "st", 3, { "st" }),
		t("overjoy", "Overjoy", "\xE2\x98\x85\xE2\x98\x85", 4, { "oj", "overjoy" }),
		t("delayjoy", "Delayjoy", "dl", 5, { "dl" }),
		t("delay", "///", "///", 6, { "3slash" }),
		t("dystopia", "Dystopia", "dy", 7, { "dy" }),
		t("ude", "Ude", "Ude", 8, { "ude" }),
		t("gachimijoy", "Gachimijoy", "\xE5\x8F\x8C", 9, { "gachi" }),
	};
}

// titles compared without case, spaces and ASCII punctuation (also the
// ideographic space), so "SOLROS [MX]" finds "SOLROS[MX]"
auto
Norm(const std::string& s) -> std::string
{
	std::string out;
	out.reserve(s.size());
	for (size_t i = 0; i < s.size(); ++i) {
		const auto c = static_cast<unsigned char>(s[i]);
		if (c < 0x80) {
			if (isspace(c) || ispunct(c)) {
				continue;
			}
			out += static_cast<char>(tolower(c));
			continue;
		}
		// U+3000 ideographic space
		if (c == 0xE3 && i + 2 < s.size() &&
			static_cast<unsigned char>(s[i + 1]) == 0x80 &&
			static_cast<unsigned char>(s[i + 2]) == 0x80) {
			i += 2;
			continue;
		}
		out += static_cast<char>(c);
	}
	return out;
}

// "03" -> "3", "-01" -> "-1", "?" and "BEGINNER" stay as they are
auto
NormLevel(std::string s) -> std::string
{
	Trim(s);
	if (s.empty()) {
		return "?";
	}
	auto neg = s[0] == '-';
	const auto digits = s.substr(neg ? 1 : 0);
	if (digits.empty() ||
		!std::all_of(digits.begin(), digits.end(), [](char c) {
			return c >= '0' && c <= '9';
		})) {
		return s;
	}
	auto n = digits.find_first_not_of('0');
	auto num = n == std::string::npos ? "0" : digits.substr(n);
	if (num == "0") {
		neg = false;
	}
	return (neg ? "-" : "") + num;
}

auto
IsNumber(const std::string& s, int& out) -> bool
{
	if (s.empty()) {
		return false;
	}
	size_t i = s[0] == '-' ? 1 : 0;
	if (i == s.size()) {
		return false;
	}
	for (auto j = i; j < s.size(); ++j) {
		if (s[j] < '0' || s[j] > '9') {
			return false;
		}
	}
	out = std::stoi(s);
	return true;
}

// numbers first, low to high, then words, "?" last
auto
LevelLess(const std::string& a, const std::string& b) -> bool
{
	int na = 0;
	int nb = 0;
	const auto ia = IsNumber(a, na);
	const auto ib = IsNumber(b, nb);
	if (ia && ib) {
		return na < nb;
	}
	if (ia != ib) {
		return ia;
	}
	if ((a == "?") != (b == "?")) {
		return b == "?";
	}
	return a < b;
}

auto
JsonString(const rapidjson::Value& o, const char* key) -> std::string
{
	if (!o.IsObject() || !o.HasMember(key)) {
		return "";
	}
	const auto& v = o[key];
	if (v.IsString()) {
		return v.GetString();
	}
	if (v.IsInt()) {
		return std::to_string(v.GetInt());
	}
	if (v.IsNumber()) {
		return std::to_string(static_cast<int>(v.GetDouble()));
	}
	return "";
}

const std::string TABLE_DIR = "/Assets/BMSTables/";

bool g_bLoaded = false;
std::vector<TableDef> g_JsonTables;

void
LoadJson()
{
	if (g_bLoaded) {
		return;
	}
	g_bLoaded = true;
	g_JsonTables.clear();

	std::vector<std::string> files;
	FILEMAN->GetDirListingWithMultipleExtensions(
	  TABLE_DIR, { "json" }, files, ONLY_FILE, true);
	std::sort(files.begin(), files.end());
	for (const auto& path : files) {
		std::string json;
		if (!GetFileContents(path, json)) {
			Locator::getLogger()->warn("BMS tables: could not read {}", path);
			continue;
		}
		if (json.rfind("\xEF\xBB\xBF", 0) == 0) {
			json.erase(0, 3);
		}
		rapidjson::Document doc;
		doc.Parse(json.c_str(), json.size());
		if (doc.HasParseError() || !doc.IsObject() ||
			!doc.HasMember("charts") || !doc["charts"].IsArray()) {
			Locator::getLogger()->warn("BMS tables: {} is not a table file",
									   path);
			continue;
		}
		TableDef d;
		d.fromJson = true;
		d.id = make_lower(JsonString(doc, "id"));
		if (d.id.empty()) {
			d.id = make_lower(GetFileNameWithoutExtension(path));
		}
		d.name = JsonString(doc, "name");
		d.symbol = JsonString(doc, "symbol");
		if (doc.HasMember("order") && doc["order"].IsInt()) {
			d.order = doc["order"].GetInt();
		}
		if (doc.HasMember("packs") && doc["packs"].IsArray()) {
			for (const auto& p : doc["packs"].GetArray()) {
				if (p.IsString()) {
					d.packs.emplace_back(make_lower(p.GetString()));
				}
			}
		}
		if (doc.HasMember("levels") && doc["levels"].IsArray()) {
			for (const auto& l : doc["levels"].GetArray()) {
				if (l.IsString()) {
					d.levels.emplace_back(NormLevel(l.GetString()));
				} else if (l.IsInt()) {
					d.levels.emplace_back(std::to_string(l.GetInt()));
				}
			}
		}
		for (const auto& c : doc["charts"].GetArray()) {
			ChartDef ch;
			ch.title = JsonString(c, "title");
			if (ch.title.empty()) {
				continue;
			}
			ch.level = NormLevel(JsonString(c, "level"));
			ch.artist = JsonString(c, "artist");
			d.charts.emplace_back(std::move(ch));
		}
		Locator::getLogger()->info(
		  "BMS tables: {} ({}) with {} charts", d.id, path, d.charts.size());
		g_JsonTables.emplace_back(std::move(d));
	}
}

// the table definitions: the built-in ones with the json files laid over
// them, plus tables only a json file knows
auto
Definitions() -> std::vector<TableDef>
{
	LoadJson();
	auto defs = BuiltinTables();
	for (const auto& j : g_JsonTables) {
		auto it = std::find_if(defs.begin(), defs.end(), [&](const TableDef& d) {
			return d.id == j.id;
		});
		if (it == defs.end()) {
			defs.emplace_back(j);
			if (defs.back().name.empty()) {
				defs.back().name = j.id;
			}
			if (defs.back().symbol.empty()) {
				defs.back().symbol = j.id + " ";
			}
			continue;
		}
		if (!j.name.empty()) {
			it->name = j.name;
		}
		if (!j.symbol.empty()) {
			it->symbol = j.symbol;
		}
		if (j.order != 100) {
			it->order = j.order;
		}
		for (const auto& p : j.packs) {
			if (std::find(it->packs.begin(), it->packs.end(), p) ==
				it->packs.end()) {
				it->packs.emplace_back(p);
			}
		}
		it->levels = j.levels;
		it->charts = j.charts;
		it->fromJson = true;
	}
	return defs;
}

// "BMS2SM - st03" -> the index of its table and level "3"
auto
PackTable(const std::string& group,
		  const std::vector<TableDef>& defs,
		  std::string& levelOut) -> int
{
	static const std::string HEAD = "bms2sm - ";
	const auto lower = make_lower(group);
	if (lower.rfind(HEAD, 0) != 0) {
		return -1;
	}
	const auto rest = lower.substr(HEAD.size());
	auto best = -1;
	size_t bestLen = 0;
	for (size_t i = 0; i < defs.size(); ++i) {
		for (const auto& p : defs[i].packs) {
			if (p.size() > bestLen && rest.rfind(p, 0) == 0) {
				best = static_cast<int>(i);
				bestLen = p.size();
			}
		}
	}
	if (best >= 0) {
		// the level as written in the pack name ("dlBEGINNER")
		levelOut = NormLevel(group.substr(HEAD.size() + bestLen));
	}
	return best;
}

auto
TitleLess(const Entry& a, const Entry& b) -> bool
{
	const auto ta = make_lower(a.song != nullptr ? a.song->GetDisplayFullTitle()
												 : a.title);
	const auto tb = make_lower(b.song != nullptr ? b.song->GetDisplayFullTitle()
												 : b.title);
	return ta < tb;
}

} // namespace

auto
Table::NumCharts() const -> int
{
	auto n = 0;
	for (const auto& l : levels) {
		n += static_cast<int>(l.entries.size());
	}
	return n;
}

auto
Table::NumAvailable() const -> int
{
	auto n = 0;
	for (const auto& l : levels) {
		for (const auto& e : l.entries) {
			n += e.song != nullptr ? 1 : 0;
		}
	}
	return n;
}

void
Reload()
{
	g_bLoaded = false;
}

auto
Build(const std::vector<Song*>& songs) -> std::vector<Table>
{
	const auto defs = Definitions();

	// songs by title, and the songs of each table's packs by level
	std::unordered_map<std::string, std::vector<Song*>> byTitle;
	std::vector<std::map<std::string, std::vector<Song*>>> packSongs(
	  defs.size());
	std::vector<std::set<const Song*>> inTablePacks(defs.size());
	for (auto* s : songs) {
		for (const auto& k :
			 { Norm(s->GetDisplayMainTitle() + s->GetDisplaySubTitle()),
			   Norm(s->GetTranslitMainTitle() + s->GetTranslitSubTitle()),
			   Norm(s->GetDisplayMainTitle()) }) {
			if (k.empty()) {
				continue;
			}
			auto& v = byTitle[k];
			if (std::find(v.begin(), v.end(), s) == v.end()) {
				v.emplace_back(s);
			}
		}
		std::string level;
		const auto t = PackTable(s->m_sGroupName, defs, level);
		if (t >= 0) {
			packSongs[t][level].emplace_back(s);
			inTablePacks[t].insert(s);
		}
	}

	std::vector<Table> out;
	for (size_t ti = 0; ti < defs.size(); ++ti) {
		const auto& d = defs[ti];
		Table t;
		t.id = d.id;
		t.name = d.name;
		t.symbol = d.symbol;
		t.order = d.order;

		std::map<std::string, std::vector<Entry>> levels;
		std::set<const Song*> listed; // songs some table entry found

		for (const auto& ch : d.charts) {
			Entry e;
			e.title = ch.title;
			e.artist = ch.artist;
			const auto it = byTitle.find(Norm(ch.title));
			if (it != byTitle.end()) {
				// prefer the song from this level's pack, then any of this
				// table's packs, then any song with that title
				const auto& lv = packSongs[ti][ch.level];
				Song* pick = nullptr;
				for (auto* s : it->second) {
					if (std::find(lv.begin(), lv.end(), s) != lv.end()) {
						pick = s;
						break;
					}
				}
				if (pick == nullptr) {
					for (auto* s : it->second) {
						if (inTablePacks[ti].count(s) != 0U) {
							pick = s;
							break;
						}
					}
				}
				if (pick == nullptr) {
					pick = it->second.front();
				}
				e.song = pick;
			}
			auto& lvEntries = levels[ch.level];
			if (e.song != nullptr) {
				// the same chart twice in one level (two entries with the
				// same title): list it once
				const auto dup =
				  std::any_of(lvEntries.begin(), lvEntries.end(), [&](const Entry& x) {
					  return x.song == e.song;
				  });
				listed.insert(e.song);
				if (dup) {
					continue;
				}
			}
			lvEntries.emplace_back(std::move(e));
		}

		// songs in the table's packs that no entry found (no table file, or
		// a title spelled differently) stay under their pack's level
		for (const auto& [level, list] : packSongs[ti]) {
			for (auto* s : list) {
				if (listed.count(s) != 0U) {
					continue;
				}
				Entry e;
				e.title = s->GetDisplayFullTitle();
				e.artist = s->GetDisplayArtist();
				e.song = s;
				levels[level].emplace_back(std::move(e));
			}
		}

		if (levels.empty()) {
			continue;
		}

		// the table's own level order, then the rest
		std::vector<std::string> order;
		for (const auto& l : d.levels) {
			if (levels.count(l) != 0U &&
				std::find(order.begin(), order.end(), l) == order.end()) {
				order.emplace_back(l);
			}
		}
		std::vector<std::string> rest;
		for (const auto& [l, _] : levels) {
			if (std::find(order.begin(), order.end(), l) == order.end()) {
				rest.emplace_back(l);
			}
		}
		std::sort(rest.begin(), rest.end(), LevelLess);
		order.insert(order.end(), rest.begin(), rest.end());

		for (const auto& l : order) {
			Level lv;
			lv.level = l;
			lv.label = d.symbol + l;
			lv.entries = std::move(levels[l]);
			std::stable_sort(lv.entries.begin(), lv.entries.end(), TitleLess);
			t.levels.emplace_back(std::move(lv));
		}
		out.emplace_back(std::move(t));
	}

	std::stable_sort(out.begin(), out.end(), [](const Table& a, const Table& b) {
		return a.order < b.order;
	});
	return out;
}

} // namespace BMSTableBrowser
