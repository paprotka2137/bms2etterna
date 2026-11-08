#include "Etterna/Globals/global.h"
#include "Etterna/Actor/Base/ActorUtil.h"
#include "Etterna/Singletons/GameState.h"
#include "LifeMeterBar.h"
#include "Etterna/Models/Misc/PlayerState.h"
#include "Etterna/Singletons/PrefsManager.h"
#include "Etterna/Models/Songs/Song.h"
#include "Etterna/Models/Songs/SongOptions.h"
#include "Etterna/Singletons/StatsManager.h"
#include "Etterna/Actor/GameplayAndMenus/StreamDisplay.h"
#include "Etterna/Singletons/ThemeManager.h"
#include "Etterna/Models/Misc/ThemeMetric.h"
#include "Etterna/Models/StepsAndStyles/Steps.h"
#include "Etterna/Models/StepsAndStyles/Style.h"
#include "Etterna/Singletons/CryptManager.h"
#include "Etterna/Singletons/ScreenManager.h"
#include "Etterna/Singletons/SongManager.h"
#include "Core/Services/Locator.hpp"
#include "RageUtil/File/RageFileManager.h"

#include "rapidjson/document.h"

#include <algorithm>
#include <cctype>
#include <limits>
#include <unordered_map>

static std::string
LIFE_PERCENT_CHANGE_NAME(size_t i)
{
	return "LifePercentChange" + ScoreEventToString(static_cast<ScoreEvent>(i));
}

float
LifeMeterBar::MapTNSToDeltaLife(TapNoteScore score)
{
	auto fDeltaLife = 0.f;
	switch (score) {
		DEFAULT_FAIL(score);

			// Using constant values here as a hack
			// For estimating replay stuff

		case TNS_W1:
			fDeltaLife = 0.008f;
			break;
		case TNS_W2:
			fDeltaLife = 0.008f;
			break;
		case TNS_W3:
			fDeltaLife = 0.004f;
			break;
		case TNS_W4:
			fDeltaLife = 0.f;
			break;
		case TNS_W5:
			fDeltaLife = -0.04f;
			break;
		case TNS_Miss:
			fDeltaLife = -0.08f;
			break;
		case TNS_HitMine:
			fDeltaLife = -0.16f;
			break;
		case TNS_None:
			fDeltaLife = -0.08f;
			break;
		case TNS_CheckpointHit:
			fDeltaLife = 0.008f;
			break;
		case TNS_CheckpointMiss:
			fDeltaLife = -0.08f;
			break;
	}
	if (fDeltaLife > 0)
		fDeltaLife *= PREFSMAN->m_fLifeDifficultyScale;
	else
		fDeltaLife /= PREFSMAN->m_fLifeDifficultyScale;
	return fDeltaLife;
}

float
LifeMeterBar::MapHNSToDeltaLife(HoldNoteScore score)
{
	auto fDeltaLife = 0.f;
	switch (score) {
		case HNS_Held:
			fDeltaLife = 0.f;
			break;
		case HNS_LetGo:
			fDeltaLife = -0.08f;
			break;
		case HNS_Missed:
			fDeltaLife = 0.f;
			break;
		default:
			FAIL_M(ssprintf("Invalid HoldNoteScore: %i", score));
	}
	if (fDeltaLife > 0)
		fDeltaLife *= PREFSMAN->m_fLifeDifficultyScale;
	else
		fDeltaLife /= PREFSMAN->m_fLifeDifficultyScale;
	return fDeltaLife;
}

LifeMeterBar::LifeMeterBar()
{
	DANGER_THRESHOLD.Load("LifeMeterBar", "DangerThreshold");
	INITIAL_VALUE.Load("LifeMeterBar", "InitialValue");
	HOT_VALUE.Load("LifeMeterBar", "HotValue");
	LIFE_MULTIPLIER.Load("LifeMeterBar", "LifeMultiplier");
	MIN_STAY_ALIVE.Load("LifeMeterBar", "MinStayAlive");
	m_fLifePercentChange.Load(
	  "LifeMeterBar", LIFE_PERCENT_CHANGE_NAME, NUM_ScoreEvent);
	m_pPlayerState = nullptr;

	const std::string sType = "LifeMeterBar";

	m_fPassingAlpha = 0;
	m_fHotAlpha = 0;

	m_fBaseLifeDifficulty = PREFSMAN->m_fLifeDifficultyScale;
	m_fLifeDifficulty = m_fBaseLifeDifficulty;

	// set up progressive lifebar
	m_iMissCombo = 0;

	// set up combotoregainlife
	m_iComboToRegainLife = 0;

	m_sprUnder.Load(THEME->GetPathG(sType, "Under"));
	m_sprUnder->SetName("Under");
	ActorUtil::LoadAllCommandsAndSetXY(m_sprUnder, sType);
	this->AddChild(m_sprUnder);

	m_sprDanger.Load(THEME->GetPathG(sType, "Danger"));
	m_sprDanger->SetName("Danger");
	ActorUtil::LoadAllCommandsAndSetXY(m_sprDanger, sType);
	this->AddChild(m_sprDanger);

	m_pStream = new StreamDisplay;
	m_pStream->Load("StreamDisplay");
	m_pStream->SetName("Stream");
	ActorUtil::LoadAllCommandsAndSetXY(m_pStream, sType);
	this->AddChild(m_pStream);

	m_sprOver.Load(THEME->GetPathG(sType, "Over"));
	m_sprOver->SetName("Over");
	ActorUtil::LoadAllCommandsAndSetXY(m_sprOver, sType);
	this->AddChild(m_sprOver);

	m_Change_SE_W1 = m_fLifePercentChange.GetValue(SE_W1);
	m_Change_SE_W2 = m_fLifePercentChange.GetValue(SE_W2);
	m_Change_SE_W3 = m_fLifePercentChange.GetValue(SE_W3);
	m_Change_SE_W4 = m_fLifePercentChange.GetValue(SE_W4);
	m_Change_SE_W5 = m_fLifePercentChange.GetValue(SE_W5);
	m_Change_SE_Miss = m_fLifePercentChange.GetValue(SE_Miss);
	m_Change_SE_HitMine = m_fLifePercentChange.GetValue(SE_HitMine);
	m_Change_SE_CheckpointHit = m_fLifePercentChange.GetValue(SE_CheckpointHit);
	m_Change_SE_CheckpointMiss =
	  m_fLifePercentChange.GetValue(SE_CheckpointMiss);
	m_Change_SE_Held = m_fLifePercentChange.GetValue(SE_Held);
	m_Change_SE_LetGo = m_fLifePercentChange.GetValue(SE_LetGo);
	m_fLifePercentage = INITIAL_VALUE;
	m_iProgressiveLifebar = 0;
}

LifeMeterBar::~LifeMeterBar()
{
	SAFE_DELETE(m_pStream);
}

void
LifeMeterBar::Load(const PlayerState* pPlayerState,
				   PlayerStageStats* pPlayerStageStats)
{
	LifeMeter::Load(pPlayerState, pPlayerStageStats);

	const auto* style = GAMESTATE->GetCurrentStyle(pPlayerState->m_PlayerNumber);
	m_bBMS = style != nullptr && style->m_iColsPerPlayer == 7;
	if (m_bBMS) {
		LoadBMSGauge();
		AfterLifeChanged();
		return;
	}

	const auto dtype = pPlayerState->m_PlayerOptions.GetStage().m_DrainType;
	switch (dtype) {
		case DrainType_Normal:
			m_fLifePercentage = INITIAL_VALUE;
			break;
			/* These types only go down, so they always start at full. */
		case DrainType_NoRecover:
		case DrainType_SuddenDeath:
			m_fLifePercentage = 1.0f;
			break;
		default:
			FAIL_M(ssprintf("Invalid DrainType: %i", dtype));
	}

	AfterLifeChanged();
}

// LR2 gauge tables, as lr2oraja Endless Dream has them (GaugeProperty.LR2).
// Groove type gauges scale recovery by TOTAL, Hard scales damage up for low
// TOTAL / short charts. A survival gauge that drops below its death value
// is dead (0) and stays dead.
struct BMSGaugeProperty
{
	bool survival;
	float min, init, border, death;
	float change[6]; // PG GR GD BD PR MS(empty POOR)
	float gutsBelow, gutsScale; // damage scale while the gauge is below
};
static const BMSGaugeProperty BMS_GAUGES[NUM_BMSGauge] = {
	{ false, 2.f, 20.f, 80.f, 0.f,
	  { 1.2f, 1.2f, .6f, -3.2f, -4.8f, -1.6f }, 0.f, 1.f },
	{ false, 2.f, 20.f, 80.f, 0.f,
	  { 1.f, 1.f, .5f, -4.f, -6.f, -2.f }, 0.f, 1.f },
	{ true, 0.f, 100.f, 0.f, 2.f,
	  { .1f, .1f, .05f, -6.f, -10.f, -2.f }, 32.f, .6f },
	// EX HARD: hard with double BAD/POOR damage and no relief at low gauge
	{ true, 0.f, 100.f, 0.f, 2.f,
	  { .1f, .1f, .05f, -12.f, -20.f, -2.f }, 0.f, 1.f },
	{ true, 0.f, 100.f, 0.f, 2.f,
	  { .15f, .06f, 0.f, -100.f, -100.f, -10.f }, 0.f, 1.f },
};

// LR2 course (dan) gauges, as beatoraja / Endless Dream have them
// (GaugeProperty.LR2 CLASS_LR2, EXCLASS_LR2, EXHARDCLASS_LR2): start full,
// never scaled by TOTAL or note count, a survival gauge for the whole
// course. CLASS and EX CLASS take 60% damage below 30%.
static const BMSGaugeProperty BMS_CLASS_GAUGES[3] = {
	{ true, 0.f, 100.f, 0.f, 2.f,
	  { .1f, .1f, .05f, -2.f, -3.f, -2.f }, 30.f, .6f },
	{ true, 0.f, 100.f, 0.f, 2.f,
	  { .1f, .1f, .05f, -6.f, -10.f, -2.f }, 30.f, .6f },
	{ true, 0.f, 100.f, 0.f, 2.f,
	  { .1f, .1f, .05f, -12.f, -20.f, -2.f }, 0.f, 1.f },
};

// LR2 hard and EX hard gauge damage multiplier from TOTAL and note count (Endless
// Dream's GaugeModifier.MODIFY_DAMAGE)
static float
LR2DamageScale(float total, float notes)
{
	const auto fix1 = static_cast<float>(
	  10.0 /
	  std::min(10.0, std::max(1.0, std::floor(total / 16.0) - 5.0)));
	float fix2;
	if (notes <= 20.f)
		fix2 = 10.f;
	else if (notes < 30.f)
		fix2 = 8.f + .2f * (30.f - notes);
	else if (notes < 60.f)
		fix2 = 5.f + .2f * (60.f - notes) / 3.f;
	else if (notes < 125.f)
		fix2 = 4.f + (125.f - notes) / 65.f;
	else if (notes < 250.f)
		fix2 = 3.f + .008f * (250.f - notes);
	else if (notes < 500.f)
		fix2 = 2.f + .004f * (500.f - notes);
	else if (notes < 1000.f)
		fix2 = 1.f + .002f * (1000.f - notes);
	else
		fix2 = 1.f;
	return std::max(fix1, fix2);
}

// Lookup of BMS #TOTAL and #RANK values. Every json in Songs/total/
// (insane_total.json from the table script, bms_total.json from
// tools/bms_total) maps the md5 of a raw .bms file to its TOTAL, RANK, title
// and original file name. Bms files put in that folder count too. Converted charts (.sm/.ssc) have no source file
// to hash, so they are matched by file name (BMS2SM keeps the bms name), then
// by title + subtitle, using the note count when a title is ambiguous.
namespace {
struct BMSTotalEntry
{
	float total{ 0.f };
	bool fromBMS{ false }; // read from a bms file, not a table comment
	int rank{ -1 };		   // bms #RANK (0 VERY HARD .. 3 EASY), -1 unknown
	float defexrank{ -1.f }; // bms #DEFEXRANK (percent, 100 = NORMAL), -1 unknown
	int notes{ 0 };		   // bms note count, scratch included
	std::string stem;	   // original file name, lower case, no extension
	std::vector<std::string> titles;
};

struct BMSTotalTable
{
	std::unordered_map<std::string, BMSTotalEntry> byHash; // md5, hex
	std::unordered_map<std::string, std::string> sha256;   // sha256 -> md5
	std::unordered_map<std::string, std::vector<const BMSTotalEntry*>> byStem;
	std::unordered_map<std::string, std::vector<const BMSTotalEntry*>>
	  byTitle; // normalized title
	bool loaded{ false };
};

// lower case ascii alphanumerics, keep all non-ascii bytes as they are
std::string
NormalizeBMSTitle(const std::string& s)
{
	std::string out;
	for (const auto c : s) {
		const auto u = static_cast<unsigned char>(c);
		if (u >= 0x80)
			out += c;
		else if (std::isalnum(u))
			out += static_cast<char>(std::tolower(u));
	}
	return out;
}

// file name without directories (either slash) and extension, lower case
std::string
FileStem(const std::string& path)
{
	auto name = path.substr(path.find_last_of("/\\") + 1);
	const auto dot = name.find_last_of('.');
	if (dot != std::string::npos)
		name.erase(dot);
	return make_lower(name);
}

// a numeric header value (#TOTAL, #RANK) straight from a bms file, -1 when
// the file doesn't have it. The line nearest the end of the file wins, line
// is where it was found.
float
ReadBMSHeaderValue(const std::string& path,
				   const std::string& tag,
				   int* line = nullptr)
{
	std::vector<std::string> lines;
	if (!GetFileContents(path, lines))
		return -1.f;
	const auto n = tag.size();
	auto value = -1.f;
	for (size_t i = 0; i < lines.size(); ++i) {
		const auto& l = lines[i];
		if (l.size() > n + 2 && l[0] == '#' &&
			make_upper(l.substr(1, n)) == tag &&
			std::isspace(static_cast<unsigned char>(l[n + 1]))) {
			value = StringToFloat(l.substr(n + 2));
			if (line != nullptr)
				*line = static_cast<int>(i);
		}
	}
	return value;
}

// #TAG:x; written into a converted .sm/.ssc, -1 when it isn't there. Read
// from the file itself, the song cache doesn't keep tags it doesn't know.
float
ReadSMValue(const std::string& path, const std::string& tag)
{
	static std::unordered_map<std::string, float> cache;
	const auto key = tag + ":" + path;
	const auto cached = cache.find(key);
	if (cached != cache.end())
		return cached->second;
	auto value = -1.f;
	const auto prefix = "#" + tag + ":";
	std::vector<std::string> lines;
	if (GetFileContents(path, lines)) {
		for (auto line : lines) {
			TrimLeft(line);
			if (line.size() > prefix.size() &&
				make_upper(line.substr(0, prefix.size())) == prefix) {
				line = line.substr(prefix.size(),
								   line.find(';') - prefix.size());
				Trim(line);
				if (!line.empty())
					value = StringToFloat(line);
				break;
			}
		}
	}
	cache[key] = value;
	return value;
}

// merge what one source knows about a chart; bms values beat table comments
void
AddBMSTotal(BMSTotalTable& table,
			const std::string& md5,
			float total,
			bool fromBMS,
			int rank,
			float defexrank,
			int notes,
			const std::string& file,
			const std::string& title)
{
	auto& e = table.byHash[md5];
	if (total > 0.f && (e.total <= 0.f || (fromBMS && !e.fromBMS))) {
		e.total = total;
		e.fromBMS = fromBMS;
	}
	if (rank >= 0 && (e.rank < 0 || fromBMS))
		e.rank = rank;
	if (defexrank > 0.f && (e.defexrank <= 0.f || fromBMS))
		e.defexrank = defexrank;
	if (e.notes <= 0)
		e.notes = notes;
	if (e.stem.empty() && !file.empty())
		e.stem = FileStem(file);
	const auto key = NormalizeBMSTitle(title);
	if (!key.empty() &&
		std::find(e.titles.begin(), e.titles.end(), key) == e.titles.end())
		e.titles.push_back(key);
}

BMSTotalTable&
GetBMSTotalTable()
{
	static BMSTotalTable table;
	if (table.loaded)
		return table;
	table.loaded = true;

	auto str = [](const rapidjson::Value& c, const char* key) {
		return c.HasMember(key) && c[key].IsString()
				 ? std::string(c[key].GetString())
				 : std::string();
	};

	for (const std::string dir : { "/Songs/total/", "/AdditionalSongs/total/" }) {
		std::vector<std::string> files;
		FILEMAN->GetDirListingWithMultipleExtensions(
		  dir, { "json" }, files, ONLY_FILE, true);
		for (const auto& path : files) {
			std::string json;
			if (!GetFileContents(path, json)) {
				Locator::getLogger()->warn("BMS TOTAL: could not read {}",
										   path);
				continue;
			}
			if (json.rfind("\xEF\xBB\xBF", 0) == 0)
				json.erase(0, 3);
			rapidjson::Document doc;
			doc.Parse(json.c_str(), json.size());
			if (doc.HasParseError() || !doc.IsObject() ||
				!doc.HasMember("charts") || !doc["charts"].IsObject()) {
				Locator::getLogger()->warn("BMS TOTAL: {} is not valid", path);
				continue;
			}
			auto withTotal = 0;
			for (auto& it : doc["charts"].GetObject()) {
				const auto& c = it.value;
				if (!c.IsObject())
					continue;
				const auto source = str(c, "total_source");
				auto total = 0.f;
				// bmson TOTAL is a percentage, not the bms value
				if (c.HasMember("total") && c["total"].IsNumber() &&
					source != "bmson_percent")
					total = c["total"].GetFloat();
				if (total > 0.f)
					withTotal++;
				const auto notes = c.HasMember("notes") && c["notes"].IsInt()
									 ? c["notes"].GetInt()
									 : 0;
				// bms #RANK, 0 VERY HARD .. 3 EASY (4 VERY EASY)
				auto rank = c.HasMember("rank") && c["rank"].IsInt()
							  ? c["rank"].GetInt()
							  : -1;
				// bms #DEFEXRANK, percent where 100 is NORMAL
				const auto defexrank =
				  c.HasMember("defexrank") && c["defexrank"].IsNumber()
					? c["defexrank"].GetFloat()
					: -1.f;
				// "rank": null means the bms file has neither header, LR2
				// plays that on #RANK 2. Table jsons without the key say
				// nothing about it.
				if (c.HasMember("rank") && c["rank"].IsNull() &&
					defexrank <= 0.f)
					rank = 2;
				const auto md5 = make_lower(it.name.GetString());
				AddBMSTotal(table,
							md5,
							total,
							source == "bms",
							rank,
							defexrank,
							notes,
							str(c, "file"),
							str(c, "title") + str(c, "subtitle"));
				if (!str(c, "subtitle").empty())
					AddBMSTotal(
					  table, md5, 0.f, false, -1, -1.f, 0, "", str(c, "title"));
				if (!str(c, "sha256").empty())
					table.sha256[make_lower(str(c, "sha256"))] = md5;
			}
			Locator::getLogger()->info(
			  "BMS TOTAL: loaded {} ({} charts, {} with TOTAL)", path,
			  doc["charts"].MemberCount(), withTotal);
		}

		// bms files put in the folder: their own #TOTAL, #RANK and name
		files.clear();
		FILEMAN->GetDirListingWithMultipleExtensions(
		  dir, { "bms", "bme", "bml", "pms" }, files, ONLY_FILE, true);
		for (const auto& file : files) {
			const auto total = ReadBMSHeaderValue(file, "TOTAL");
			// of #RANK and #DEFEXRANK the one nearer the end counts, and a
			// file with neither plays on #RANK 2 like in LR2
			auto rankLine = -1;
			auto defexLine = -1;
			auto rank =
			  static_cast<int>(ReadBMSHeaderValue(file, "RANK", &rankLine));
			auto defexrank =
			  ReadBMSHeaderValue(file, "DEFEXRANK", &defexLine);
			if (rankLine > defexLine)
				defexrank = -1.f;
			if (rank < 0 && defexrank <= 0.f)
				rank = 2;
			const auto md5 =
			  make_lower(BinaryToHex(CryptManager::GetMD5ForFile(file)));
			AddBMSTotal(table, md5, total, true, rank, defexrank, 0, file, "");
			Locator::getLogger()->info(
			  "BMS TOTAL: {} has #TOTAL {} #RANK {} #DEFEXRANK {}",
			  file,
			  total,
			  rank,
			  defexrank);
		}
	}

	for (const auto& [md5, e] : table.byHash) {
		if (e.total <= 0.f && e.rank < 0 && e.defexrank <= 0.f)
			continue;
		if (!e.stem.empty())
			table.byStem[e.stem].push_back(&e);
		for (const auto& t : e.titles)
			table.byTitle[t].push_back(&e);
	}
	return table;
}

// One value (TOTAL, RANK) out of the charts sharing a name, -1 when none of
// them has it. When they disagree, pick the one whose note count fits ours
// best: converts lose the scratch lane, so a bms chart can't have fewer notes
// than our chart.
template<typename Get>
float
PickBMSValue(const std::vector<const BMSTotalEntry*>& candidates,
			 int notes,
			 Get get)
{
	const BMSTotalEntry* best = nullptr;
	auto same = true;
	for (const auto* c : candidates) {
		if (get(*c) < 0.f)
			continue;
		if (best == nullptr)
			best = c;
		same = same && get(*c) == get(*best);
	}
	if (best == nullptr)
		return -1.f;
	if (same)
		return get(*best);
	auto bestScore = std::numeric_limits<int>::max();
	for (const auto* c : candidates) {
		if (c->notes <= 0 || get(*c) < 0.f)
			continue;
		const auto score =
		  std::abs(c->notes - notes) + (c->notes < notes ? 100000 : 0);
		if (score < bestScore) {
			bestScore = score;
			best = c;
		}
	}
	return get(*best);
}

// A chart's header value (tag "TOTAL" or "RANK"), -1 when unknown. The bms
// file's own header first, then its md5 in the json, then the tag written into
// a converted .sm/.ssc, then the json by file name and by title. get reads the
// value off a json entry (-1 unknown) and valid says whether a header value
// counts.
template<typename Get, typename Valid>
float
FindBMSValue(const Song* song,
			 const Steps* steps,
			 const std::string& tag,
			 std::string& source,
			 Get get,
			 Valid valid)
{
	auto& table = GetBMSTotalTable();
	const auto notes =
	  steps != nullptr
		? static_cast<int>(steps->GetRadarValues()[RadarCategory_Notes])
		: 0;

	if (steps != nullptr) {
		const auto& fn = steps->GetFilename();
		const auto ext = make_lower(GetExtension(fn));
		// charts loaded from a bms file: header first, then md5 of the file
		if (ext == "bms" || ext == "bme" || ext == "bml" || ext == "pms") {
			const auto value = ReadBMSHeaderValue(fn, tag);
			if (valid(value)) {
				source = "#" + tag;
				return value;
			}
			static std::unordered_map<std::string, std::string> md5Cache;
			auto cached = md5Cache.find(fn);
			if (cached == md5Cache.end())
				cached =
				  md5Cache
					.emplace(fn,
							 make_lower(BinaryToHex(
							   CryptManager::GetMD5ForFile(fn))))
					.first;
			const auto hit = table.byHash.find(cached->second);
			if (hit != table.byHash.end() && get(hit->second) >= 0.f) {
				source = "json md5";
				return get(hit->second);
			}
		}
	}

	// converts that carry the tag in the .sm/.ssc itself
	if (song != nullptr) {
		std::vector<std::string> files;
		if (steps != nullptr) {
			const auto ext = make_lower(GetExtension(steps->GetFilename()));
			if (ext == "sm" || ext == "ssc")
				files.push_back(steps->GetFilename());
		}
		if (files.empty())
			FILEMAN->GetDirListingWithMultipleExtensions(
			  song->GetSongDir(), { "ssc", "sm" }, files, ONLY_FILE, true);
		// BMS2SM writes the bms #RANK as #JUDGERANK
		std::vector<std::string> tags{ tag };
		if (tag == "RANK")
			tags.insert(tags.begin(), "JUDGERANK");
		for (const auto& file : files) {
			for (const auto& t : tags) {
				const auto value = ReadSMValue(file, t);
				if (valid(value)) {
					source = "#" + t;
					return value;
				}
			}
		}
	}

	if (song != nullptr) {
		// converts are named after the bms file they came from, both the
		// .sm and its folder
		auto dir = song->GetSongDir();
		while (!dir.empty() && dir.back() == '/')
			dir.pop_back();
		for (const auto& name :
			 { steps != nullptr ? FileStem(steps->GetFilename()) : std::string(),
			   make_lower(dir.substr(dir.find_last_of('/') + 1)) }) {
			if (name.empty())
				continue;
			const auto hit = table.byStem.find(name);
			if (hit != table.byStem.end()) {
				const auto value = PickBMSValue(hit->second, notes, get);
				if (value >= 0.f) {
					source = "json file";
					return value;
				}
			}
		}
		for (const auto& title :
			 { song->m_sMainTitle + song->m_sSubTitle, song->m_sMainTitle }) {
			const auto hit = table.byTitle.find(NormalizeBMSTitle(title));
			if (hit != table.byTitle.end()) {
				const auto value = PickBMSValue(hit->second, notes, get);
				if (value >= 0.f) {
					source = "json title";
					return value;
				}
			}
		}
	}
	return -1.f;
}
} // namespace

float
LifeMeterBar::FindBMSTotal(const Song* song,
						   const Steps* steps,
						   std::string& source)
{
	const auto total = FindBMSValue(
	  song,
	  steps,
	  "TOTAL",
	  source,
	  [](const BMSTotalEntry& e) { return e.total > 0.f ? e.total : -1.f; },
	  [](float v) { return v > 0.f; });
	return std::max(total, 0.f);
}

int
LifeMeterBar::GetBMSRank(const Song* song,
						 const Steps* steps,
						 std::string& source)
{
	// #DEFEXRANK wins over #RANK. It is a percent of NORMAL's windows; nanasi
	// puts RANK 0 .. 4 at 48, 64, 100, 120 and 160. We only have LR2's four
	// ranks, so it takes the nearest one.
	const auto defexrank = FindBMSValue(
	  song,
	  steps,
	  "DEFEXRANK",
	  source,
	  [](const BMSTotalEntry& e) {
		  return e.defexrank > 0.f ? e.defexrank : -1.f;
	  },
	  [](float v) { return v > 0.f; });
	if (defexrank > 0.f) {
		source = ssprintf("#DEFEXRANK %g (%s)", defexrank, source.c_str());
		if (defexrank < 56.f)
			return 0;
		if (defexrank < 82.f)
			return 1;
		if (defexrank < 110.f)
			return 2;
		return 3;
	}

	const auto rank = FindBMSValue(
	  song,
	  steps,
	  "RANK",
	  source,
	  [](const BMSTotalEntry& e) { return static_cast<float>(e.rank); },
	  [](float v) { return v >= 0.f; });
	if (rank < 0.f) {
		source = "none";
		return -1;
	}
	return static_cast<int>(rank);
}

// The chart's TOTAL when we know it (BMS header or Songs/total json).
// Otherwise do what LR2 does for BMS without #TOTAL (and lr2oraja Endless
// Dream for osu charts): 160 + (n + clamp(n-400,0,200))*0.16, n counting a
// long note once
float
LifeMeterBar::GetBMSTotal(const Song* song,
						  const Steps* steps,
						  std::string& source)
{
	const auto total = FindBMSTotal(song, steps, source);
	if (total > 0.f)
		return total;
	auto notes = 0.f;
	if (steps != nullptr)
		notes = steps->GetRadarValues()[RadarCategory_Notes];
	notes = std::max(notes, 1.f);
	source = "default";
	return 160.f + (notes + std::clamp(notes - 400.f, 0.f, 200.f)) * 0.16f;
}

void
LifeMeterBar::LoadBMSGauge()
{
	const auto& po = m_pPlayerState->m_PlayerOptions.GetStage();
	m_BMSGauge = po.m_BMSGauge;
	if (m_BMSGauge < 0 || m_BMSGauge >= NUM_BMSGauge)
		m_BMSGauge = BMSGauge_Normal;
	m_bBMSAutoShift = po.m_bBMSAutoShift;

	// dan course: the course gauge decides everything, no auto shift
	m_iBMSClassGauge = -1;
	if (SONGMAN != nullptr && SONGMAN->InBMSCourse()) {
		m_iBMSClassGauge = std::clamp(SONGMAN->bmsCourse.classGauge, 0, 2);
		m_bBMSAutoShift = false;
		m_fBMSClassValue = BMS_CLASS_GAUGES[m_iBMSClassGauge].init;
		m_fBMSMin = BMS_CLASS_GAUGES[m_iBMSClassGauge].min;
		m_fBMSBorder = BMS_CLASS_GAUGES[m_iBMSClassGauge].border;
		m_fLifePercentage = m_fBMSClassValue / 100.f;
		static const char* names[] = { "CLASS", "EX CLASS", "EX HARD CLASS" };
		Locator::getLogger()->info("BMS course gauge: {}",
								   names[m_iBMSClassGauge]);
		return;
	}

	auto notes = 0.f;
	if (GAMESTATE->m_pCurSteps != nullptr)
		notes = GAMESTATE->m_pCurSteps->GetRadarValues()[RadarCategory_Notes];
	notes = std::max(notes, 1.f);

	std::string source;
	const auto total =
	  GetBMSTotal(GAMESTATE->m_pCurSong, GAMESTATE->m_pCurSteps, source);
	Locator::getLogger()->info("BMS gauge: TOTAL {:.1f} ({}), {} notes",
							   total, source, static_cast<int>(notes));
	if (SCREENMAN != nullptr)
		SCREENMAN->SystemMessage(
		  fmt::format("TOTAL {:.1f} ({})", total, source));

	// with auto shift every gauge below the chosen one runs alongside it
	for (auto g = 0; g < NUM_BMSGauge; g++) {
		m_bBMSTracked[g] =
		  g == m_BMSGauge || (m_bBMSAutoShift && g < m_BMSGauge);
		const auto& prop = BMS_GAUGES[g];
		const auto damageScale =
		  g == BMSGauge_Hard || g == BMSGauge_ExHard
			? LR2DamageScale(total, notes)
			: 1.f;
		for (auto i = 0; i < NUM_BMSJudge; i++) {
			auto f = prop.change[i];
			if (f > 0 && !prop.survival)
				f *= total / notes;
			else if (f < 0)
				f *= damageScale;
			m_fBMSChange[g][i] = f;
		}
		m_fBMSValue[g] = prop.init;
	}
	SetBMSCurrentGauge(m_BMSGauge);
	RecordBMSGauges(0.f);
}

// every gauge that runs keeps its own record for the result screen graph
void
LifeMeterBar::RecordBMSGauges(float fStepsSecond)
{
	if (m_pPlayerStageStats == nullptr)
		return;
	for (auto g = 0; g < NUM_BMSGauge; g++) {
		if (m_bBMSTracked[g])
			m_pPlayerStageStats->SetBMSGaugeRecordAt(
			  g, m_fBMSValue[g] / 100.f, std::max(fStepsSecond, 0.f));
	}
}

void
LifeMeterBar::SetBMSCurrentGauge(BMSGauge gauge)
{
	m_BMSGauge = gauge;
	m_fBMSMin = BMS_GAUGES[gauge].min;
	m_fBMSBorder = BMS_GAUGES[gauge].border;
	m_fLifePercentage = m_fBMSValue[gauge] / 100.f;
}

// With auto shift the shown gauge is the strongest tracked one that is
// qualified (alive, and at or above its border), else the bottom gauge,
// like Endless Dream's "select to under" auto shift
BMSGauge
LifeMeterBar::PickBMSAutoShiftGauge() const
{
	auto picked = BMSGauge_Easy;
	for (auto g = 0; g < NUM_BMSGauge; g++) {
		if (m_bBMSTracked[g] && m_fBMSValue[g] > 0.f &&
			m_fBMSValue[g] >= BMS_GAUGES[g].border)
			picked = static_cast<BMSGauge>(g);
	}
	return picked;
}

void
LifeMeterBar::ChangeBMSClassLife(BMSJudge judge)
{
	const auto& prop = BMS_CLASS_GAUGES[m_iBMSClassGauge];
	auto& value = m_fBMSClassValue;
	if (value <= 0.f)
		return;
	auto inc = prop.change[judge];
	if (inc < 0 && value < prop.gutsBelow)
		inc *= prop.gutsScale;
	value = std::clamp(value + inc, prop.min, 100.f);
	if (value < prop.death)
		value = 0.f;
	const auto InitialLife = m_fLifePercentage;
	m_fLifePercentage = value / 100.f;
	if (InitialLife != m_fLifePercentage)
		AfterLifeChanged();
}

void
LifeMeterBar::ChangeBMSLife(BMSJudge judge)
{
	if (m_pPlayerStageStats->m_bFailed)
		return;
	if (m_iBMSClassGauge >= 0) {
		ChangeBMSClassLife(judge);
		return;
	}
	for (auto g = 0; g < NUM_BMSGauge; g++) {
		auto& value = m_fBMSValue[g];
		// hard gauges stay dead once they hit 0
		if (!m_bBMSTracked[g] || value <= 0.f)
			continue;
		const auto& prop = BMS_GAUGES[g];
		auto inc = m_fBMSChange[g][judge];
		// hard gauge takes less damage below 32%
		if (inc < 0 && value < prop.gutsBelow)
			inc *= prop.gutsScale;
		value = std::clamp(value + inc, prop.min, 100.f);
		if (value < prop.death)
			value = 0.f;
	}

	RecordBMSGauges(GAMESTATE->m_Position.m_fMusicSeconds /
					GAMESTATE->m_SongOptions.GetCurrent().m_fMusicRate);

	const auto InitialLife = m_fLifePercentage;
	const auto InitialGauge = m_BMSGauge;
	SetBMSCurrentGauge(m_bBMSAutoShift ? PickBMSAutoShiftGauge() : m_BMSGauge);
	if (InitialGauge != m_BMSGauge) {
		Message msg("BMSGaugeShift");
		msg.SetParam("Player", m_pPlayerState->m_PlayerNumber);
		msg.SetParam("Gauge", BMSGaugeToString(m_BMSGauge));
		MESSAGEMAN->Broadcast(msg);
	}
	if (InitialLife != m_fLifePercentage || InitialGauge != m_BMSGauge)
		AfterLifeChanged();
}

void
LifeMeterBar::ChangeLife(TapNoteScore score)
{
	if (m_bBMS) {
		switch (score) {
			case TNS_W1:
				ChangeBMSLife(BMS_PG);
				break;
			case TNS_W2:
				ChangeBMSLife(BMS_GR);
				break;
			case TNS_W3:
				ChangeBMSLife(BMS_GD);
				break;
			case TNS_W4:
			case TNS_W5:
				ChangeBMSLife(BMS_BD);
				break;
			case TNS_Miss:
				ChangeBMSLife(BMS_PR);
				break;
			case TNS_None:
			case TNS_HitMine:
				ChangeBMSLife(BMS_MS);
				break;
			default:
				break;
		}
		return;
	}

	auto fDeltaLife = 0.f;
	switch (score) {
		DEFAULT_FAIL(score);

			/*Whatever was originally done to try and be fancy resulted in the
			lifemeterbar parsing the metrics file to obtain constant values
			every single update cycle. This is obviously a temporary fix however
			the 200 avg fps gain is well worth it. Also, this function should
			only be called if life values actually change, like with the
			lifechanged message. - Mina*/

		case TNS_W1:
			fDeltaLife = m_Change_SE_W1;
			break;
		case TNS_W2:
			fDeltaLife = m_Change_SE_W2;
			break;
		case TNS_W3:
			fDeltaLife = m_Change_SE_W3;
			break;
		case TNS_W4:
			fDeltaLife = m_Change_SE_W4;
			break;
		case TNS_W5:
			fDeltaLife = m_Change_SE_W5;
			break;
		case TNS_Miss:
			fDeltaLife = m_Change_SE_Miss;
			break;
		case TNS_HitMine:
			fDeltaLife = m_Change_SE_HitMine;
			break;
		case TNS_None:
			fDeltaLife = m_Change_SE_Miss;
			break;
		case TNS_CheckpointHit:
			fDeltaLife = m_Change_SE_CheckpointHit;
			break;
		case TNS_CheckpointMiss:
			fDeltaLife = m_Change_SE_CheckpointMiss;
			break;
	}

	switch (m_pPlayerState->m_PlayerOptions.GetSong().m_DrainType) {
		DEFAULT_FAIL(m_pPlayerState->m_PlayerOptions.GetSong().m_DrainType);
		case DrainType_Normal:
			break;
		case DrainType_NoRecover:
			fDeltaLife = std::min(fDeltaLife, 0.F);
			break;
		case DrainType_SuddenDeath:
			if (score < MIN_STAY_ALIVE)
				fDeltaLife = -1.0f;
			else
				fDeltaLife = 0;
			break;
	}

	ChangeLife(fDeltaLife);
}

void
LifeMeterBar::ChangeLife(HoldNoteScore score, TapNoteScore tscore)
{
	if (m_bBMS) {
		// a dropped long note is a POOR, the head was judged already
		if (score == HNS_LetGo)
			ChangeBMSLife(BMS_PR);
		return;
	}

	auto fDeltaLife = 0.f;
	const auto dtype = m_pPlayerState->m_PlayerOptions.GetSong().m_DrainType;
	switch (dtype) {
		case DrainType_Normal:
			switch (score) {
				case HNS_Held:
					fDeltaLife = m_Change_SE_Held;
					break;
				case HNS_LetGo:
					fDeltaLife = m_Change_SE_LetGo;
					break;
				case HNS_Missed:
					fDeltaLife = 0.f;
					break;
				default:
					FAIL_M(ssprintf("Invalid HoldNoteScore: %i", score));
			}
			break;
		case DrainType_NoRecover:
			switch (score) {
				case HNS_Held:
					fDeltaLife = +0.000f;
					break;
				case HNS_LetGo:
					fDeltaLife = m_Change_SE_LetGo;
					break;
				case HNS_Missed:
					fDeltaLife = +0.000f;
					break;
				default:
					FAIL_M(ssprintf("Invalid HoldNoteScore: %i", score));
			}
			break;
		case DrainType_SuddenDeath:
			switch (score) {
				case HNS_Held:
					fDeltaLife = +0;
					break;
				case HNS_LetGo:
					fDeltaLife = -1.0f;
					break;
				case HNS_Missed:
					fDeltaLife = +0;
					break;
				default:
					FAIL_M(ssprintf("Invalid HoldNoteScore: %i", score));
			}
			break;
		default:
			FAIL_M(ssprintf("Invalid DrainType: %i", dtype));
	}

	ChangeLife(fDeltaLife);
}

void
LifeMeterBar::ChangeLife(float fDeltaLife)
{
	// If we've already failed, there's no point in letting them fill up the bar
	// again.
	if (m_pPlayerStageStats->m_bFailed)
		return;

	if (m_bBMS) {
		if (m_fLifePercentage <= 0.f)
			return;
		const auto InitialLife = m_fLifePercentage;
		m_fLifePercentage =
		  std::clamp(m_fLifePercentage + fDeltaLife, m_fBMSMin / 100.f, 1.f);
		const auto death = m_iBMSClassGauge >= 0
							 ? BMS_CLASS_GAUGES[m_iBMSClassGauge].death
							 : BMS_GAUGES[m_BMSGauge].death;
		if (m_fLifePercentage * 100.f < death)
			m_fLifePercentage = 0.f;
		if (m_iBMSClassGauge >= 0)
			m_fBMSClassValue = m_fLifePercentage * 100.f;
		else
			m_fBMSValue[m_BMSGauge] = m_fLifePercentage * 100.f;
		if (InitialLife != m_fLifePercentage)
			AfterLifeChanged();
		return;
	}

	switch (m_pPlayerState->m_PlayerOptions.GetSong().m_DrainType) {
		case DrainType_Normal:
		case DrainType_NoRecover:
			if (fDeltaLife > 0)
				fDeltaLife *= m_fLifeDifficulty;
			else
				fDeltaLife /= m_fLifeDifficulty;
			break;
		case DrainType_SuddenDeath:
			// This should always -1.0f;
			if (fDeltaLife < 0)
				fDeltaLife = -1.0f;
			else
				fDeltaLife = 0;
			break;
		default:
			break;
	}

	const auto InitialLife = m_fLifePercentage;

	m_fLifePercentage += fDeltaLife;

	// Default theme metrics states that LifeMultiplier is used ONLY for debug.
	// Clearly not true. -Mina
	CLAMP(m_fLifePercentage, 0, LIFE_MULTIPLIER);

	// Only send life changed messages if the life value has actually changed.
	// -Mina
	if (InitialLife != m_fLifePercentage)
		AfterLifeChanged();
}

void
LifeMeterBar::SetLife(float value)
{
	m_fLifePercentage = value;
	CLAMP(m_fLifePercentage, 0, LIFE_MULTIPLIER);
	AfterLifeChanged();
}

extern ThemeMetric<bool> PENALIZE_TAP_SCORE_NONE;
void
LifeMeterBar::HandleTapScoreNone()
{
	if (PENALIZE_TAP_SCORE_NONE)
		ChangeLife(TNS_None);
}

void
LifeMeterBar::AfterLifeChanged()
{
	m_pStream->SetPercent(m_fLifePercentage);

	Message msg("LifeChanged");
	msg.SetParam("Player", m_pPlayerState->m_PlayerNumber);
	msg.SetParam("LifeMeter", LuaReference::CreateFromPush(*this));
	MESSAGEMAN->Broadcast(msg);
}

bool
LifeMeterBar::IsHot() const
{
	if (m_bBMS)
		return m_fLifePercentage >= 1.f;
	return m_fLifePercentage >= HOT_VALUE;
}

bool
LifeMeterBar::IsInDanger() const
{
	if (m_bBMS)
		return m_fBMSBorder > 0.f ? m_fLifePercentage < m_fBMSBorder / 100.f
								  : m_fLifePercentage < .3f;
	return m_fLifePercentage < DANGER_THRESHOLD;
}

bool
LifeMeterBar::IsFailing() const
{
	// groove type gauges never fail during the song, only at the end
	if (m_bBMS)
		return m_fBMSBorder <= 0.f && m_fLifePercentage <= 0.f;
	return m_fLifePercentage <=
		   m_pPlayerState->m_PlayerOptions.GetCurrent().m_fPassmark;
}

bool
LifeMeterBar::IsFailingAtEnd() const
{
	if (m_bBMS)
		return m_fLifePercentage <= 0.f ||
			   m_fLifePercentage * 100.f < m_fBMSBorder - 0.001f;
	return IsFailing();
}

void
LifeMeterBar::Update(float fDeltaTime)
{
	LifeMeter::Update(fDeltaTime);

	m_fPassingAlpha += !IsFailing() ? +fDeltaTime * 2 : -fDeltaTime * 2;
	CLAMP(m_fPassingAlpha, 0, 1);

	m_fHotAlpha += IsHot() ? +fDeltaTime * 2 : -fDeltaTime * 2;
	CLAMP(m_fHotAlpha, 0, 1);

	m_pStream->SetPassingAlpha(m_fPassingAlpha);
	m_pStream->SetHotAlpha(m_fHotAlpha);

	if (m_pPlayerState->m_HealthState == HealthState_Danger)
		m_sprDanger->SetVisible(true);
	else
		m_sprDanger->SetVisible(false);
}

void
LifeMeterBar::FillForHowToPlay(int NumW2s, int NumMisses)
{
	m_iProgressiveLifebar = 0; // disable progressive lifebar

	const auto AmountForW2 = NumW2s * m_fLifeDifficulty * 0.008f;
	const auto AmountForMiss = NumMisses / m_fLifeDifficulty * 0.08f;

	m_fLifePercentage = AmountForMiss - AmountForW2;
	CLAMP(m_fLifePercentage, 0.0f, 1.0f);
	AfterLifeChanged();
}
