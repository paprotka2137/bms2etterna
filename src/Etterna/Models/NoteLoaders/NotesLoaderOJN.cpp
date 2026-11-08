#include "Etterna/Globals/global.h"
#include "NotesLoaderOJN.h"
#include "NotesLoader.h"
#include "Etterna/Models/Misc/GameConstantsAndTypes.h"
#include "Etterna/Models/Misc/NoteTypes.h"
#include "Etterna/Models/Misc/TimingData.h"
#include "Etterna/Models/NoteData/NoteData.h"
#include "Etterna/Models/Songs/Song.h"
#include "Etterna/Models/StepsAndStyles/Steps.h"
#include "Etterna/Singletons/GameManager.h"
#include "Core/Services/Locator.hpp"
#include "RageUtil/File/RageFile.h"
#include "RageUtil/File/RageFileManager.h"
#include "RageUtil/Utils/RageUtil.h"

#include <algorithm>
#ifdef _WIN32
#include <windows.h>
#else
#include <iconv.h>
#endif
#include <cmath>
#include <cstdint>
#include <cstring>
#include <map>
#include <set>

/* O2Jam charts.
 *
 * The .ojn holds a 300 byte header and up to three charts (EX, NX, HX). Each
 * chart is a list of packages: int measure, short channel, short count, then
 * count events spread evenly over the measure. Channel 0 is the measure
 * length (float), 1 a bpm change (float), 2-8 the seven lanes and anything
 * above that background samples. A note event is short sample, byte
 * volume/pan, byte type; sample 0 means no event, type 2 starts a long note
 * and type 3 ends it, and type bit 4 selects the ogg half of the bank.
 *
 * The .ojm is the sample bank, in one of three layouts: M30 (ogg, maybe xor'd
 * with "nami" or "0412"), OMC (wav + ogg, wav scrambled) and OJM (same as OMC
 * without the scrambling). Sample ids are 0-999 for wav and 1000+ for ogg, the
 * same numbers the notes use. Layouts follow open2jam's parsers. */

namespace {

const std::string SAMPLE_DIR = "_o2jam/";
const int HEADER_SIZE = 300;
const char* GENRES[] = { "Ballad", "Rock",	   "Dance",		  "Techno",
						 "Hip-hop", "Soul/R&B", "Jazz",		  "Funk",
						 "Classical", "Traditional", "Etc" };

template<typename T>
T
Get(const std::string& d, size_t off)
{
	T v{};
	if (off + sizeof(T) <= d.size())
		memcpy(&v, d.data() + off, sizeof(T));
	return v;
}

std::string
GetStr(const std::string& d, size_t off, size_t len)
{
	if (off >= d.size())
		return "";
	auto s = d.substr(off, std::min(len, d.size() - off));
	const auto nul = s.find('\0');
	if (nul != std::string::npos)
		s.resize(nul);
	return s;
}

bool
ReadWholeFile(const std::string& path, std::string& out)
{
	RageFile f;
	if (!f.Open(path, RageFile::READ))
		return false;
	out.clear();
	return f.Read(out, f.GetFileSize()) >= 0;
}

struct OJNHeader
{
	int songId = 0;
	int genre = 0;
	float bpm = 120.f;
	int level[3] = { 0, 0, 0 };
	std::string title, artist, noter, ojmFile;
	int coverSize = 0;
	int bmpSize = 0;
	int noteOffset[4] = { 0, 0, 0, 0 }; // [3] is the cover offset
};

bool
ParseHeader(const std::string& d, OJNHeader& h)
{
	if (d.size() < HEADER_SIZE || d.compare(4, 4, std::string("ojn\0", 4)) != 0)
		return false;
	h.songId = Get<int32_t>(d, 0);
	h.genre = Get<int32_t>(d, 12);
	h.bpm = Get<float>(d, 16);
	for (int i = 0; i < 3; i++)
		h.level[i] = Get<int16_t>(d, 20 + 2 * i);
	h.bmpSize = Get<int32_t>(d, 100);
	h.title = GetStr(d, 108, 64);
	h.artist = GetStr(d, 172, 32);
	h.noter = GetStr(d, 204, 32);
	h.ojmFile = GetStr(d, 236, 32);
	h.coverSize = Get<int32_t>(d, 268);
	for (int i = 0; i < 4; i++)
		h.noteOffset[i] = Get<int32_t>(d, 284 + 4 * i);
	const auto size = static_cast<int>(d.size());
	for (int i = 0; i < 4; i++)
		h.noteOffset[i] = std::clamp(h.noteOffset[i], HEADER_SIZE, size);
	return true;
}

// a chart's raw package block
std::string
ChartBlock(const std::string& d, const OJNHeader& h, int diff)
{
	const auto start = h.noteOffset[diff];
	const auto end = h.noteOffset[diff + 1];
	if (end <= start)
		return "";
	return d.substr(start, end - start);
}

/* O2Jam text is EUC-KR (CP949). The engine's own ConvertString does nothing
 * on Linux, so convert here; whatever still isn't UTF-8 keeps only ASCII. */
void
KoreanToUtf8(std::string& s)
{
	if (s.empty() || utf8_is_valid(s))
		return;
	std::string out;
#ifdef _WIN32
	const auto wlen = MultiByteToWideChar(
	  949, 0, s.data(), static_cast<int>(s.size()), nullptr, 0);
	if (wlen > 0) {
		std::wstring w(wlen, L'\0');
		MultiByteToWideChar(
		  949, 0, s.data(), static_cast<int>(s.size()), w.data(), wlen);
		const auto len = WideCharToMultiByte(
		  CP_UTF8, 0, w.data(), wlen, nullptr, 0, nullptr, nullptr);
		out.resize(std::max(len, 0));
		WideCharToMultiByte(
		  CP_UTF8, 0, w.data(), wlen, out.data(), len, nullptr, nullptr);
	}
#else
	auto cd = iconv_open("UTF-8", "CP949");
	if (cd == reinterpret_cast<iconv_t>(-1))
		cd = iconv_open("UTF-8", "EUC-KR");
	if (cd != reinterpret_cast<iconv_t>(-1)) {
		std::string in = s;
		out.resize(in.size() * 4 + 4);
		char* pin = in.data();
		char* pout = out.data();
		size_t inLeft = in.size();
		size_t outLeft = out.size();
		if (iconv(cd, &pin, &inLeft, &pout, &outLeft) == static_cast<size_t>(-1))
			out.clear();
		else
			out.resize(out.size() - outLeft);
		iconv_close(cd);
	}
#endif
	if (!out.empty() && utf8_is_valid(out)) {
		s = out;
		return;
	}
	out.clear();
	for (const auto c : s)
		if (static_cast<unsigned char>(c) < 0x80)
			out += c;
	s = out;
}

/* ---- sample bank ---- */

struct OJMSample
{
	int id;
	std::string ext; // "ogg" or "wav"
	std::string data;
};

const uint8_t REARRANGE_TABLE[] = {
	0x10, 0x0E, 0x02, 0x09, 0x04, 0x00, 0x07, 0x01, 0x06, 0x08, 0x0F, 0x0A,
	0x05, 0x0C, 0x03, 0x0D, 0x0B, 0x07, 0x02, 0x0A, 0x0B, 0x03, 0x05, 0x0D,
	0x08, 0x04, 0x00, 0x0C, 0x06, 0x0F, 0x0E, 0x10, 0x01, 0x09, 0x0C, 0x0D,
	0x03, 0x00, 0x06, 0x09, 0x0A, 0x01, 0x07, 0x08, 0x10, 0x02, 0x0B, 0x0E,
	0x04, 0x0F, 0x05, 0x08, 0x03, 0x04, 0x0D, 0x06, 0x05, 0x0B, 0x10, 0x02,
	0x0C, 0x07, 0x09, 0x0A, 0x0F, 0x0E, 0x00, 0x01, 0x0F, 0x02, 0x0C, 0x0D,
	0x00, 0x04, 0x01, 0x05, 0x07, 0x03, 0x09, 0x10, 0x06, 0x0B, 0x0A, 0x08,
	0x0E, 0x00, 0x04, 0x0B, 0x10, 0x0F, 0x0D, 0x0C, 0x06, 0x05, 0x07, 0x01,
	0x02, 0x03, 0x08, 0x09, 0x0A, 0x0E, 0x03, 0x10, 0x08, 0x07, 0x06, 0x09,
	0x0E, 0x0D, 0x00, 0x0A, 0x0B, 0x04, 0x05, 0x0C, 0x02, 0x01, 0x0F, 0x04,
	0x0E, 0x10, 0x0F, 0x05, 0x08, 0x07, 0x0B, 0x00, 0x01, 0x06, 0x02, 0x0C,
	0x09, 0x03, 0x0A, 0x0D, 0x06, 0x0D, 0x0E, 0x07, 0x10, 0x0A, 0x0B, 0x00,
	0x01, 0x0C, 0x0F, 0x02, 0x03, 0x08, 0x09, 0x04, 0x05, 0x0A, 0x0C, 0x00,
	0x08, 0x09, 0x0D, 0x03, 0x04, 0x05, 0x10, 0x0E, 0x0F, 0x01, 0x02, 0x0B,
	0x06, 0x07, 0x05, 0x06, 0x0C, 0x04, 0x0D, 0x0F, 0x07, 0x0E, 0x08, 0x01,
	0x09, 0x02, 0x10, 0x0A, 0x0B, 0x00, 0x03, 0x0B, 0x0F, 0x04, 0x0E, 0x03,
	0x01, 0x00, 0x02, 0x0D, 0x0C, 0x06, 0x07, 0x05, 0x10, 0x09, 0x08, 0x0A,
	0x03, 0x02, 0x01, 0x00, 0x04, 0x0C, 0x0D, 0x0B, 0x10, 0x05, 0x06, 0x0F,
	0x0E, 0x07, 0x09, 0x0A, 0x08, 0x09, 0x0A, 0x00, 0x07, 0x08, 0x06, 0x10,
	0x03, 0x04, 0x01, 0x02, 0x05, 0x0B, 0x0E, 0x0F, 0x0D, 0x0C, 0x0A, 0x06,
	0x09, 0x0C, 0x0B, 0x10, 0x07, 0x08, 0x00, 0x0F, 0x03, 0x01, 0x02, 0x05,
	0x0D, 0x0E, 0x04, 0x0D, 0x00, 0x01, 0x0E, 0x02, 0x03, 0x08, 0x0B, 0x07,
	0x0C, 0x09, 0x05, 0x0A, 0x0F, 0x04, 0x06, 0x10, 0x01, 0x0E, 0x02, 0x03,
	0x0D, 0x0B, 0x07, 0x00, 0x08, 0x0C, 0x09, 0x06, 0x0F, 0x10, 0x05, 0x0A,
	0x04, 0x00
};

void
Rearrange(std::string& buf)
{
	const auto length = buf.size();
	auto key = ((length % 17) << 4) + (length % 17);
	const auto blockSize = length / 17;
	const auto encoded = buf;
	for (size_t block = 0; block < 17; block++, key++) {
		if (key >= sizeof(REARRANGE_TABLE))
			break;
		memcpy(&buf[blockSize * REARRANGE_TABLE[key]],
			   &encoded[blockSize * block],
			   blockSize);
	}
}

// the key carries over from one sample to the next
struct AccXor
{
	int keybyte = 0xFF;
	int counter = 0;
	void Apply(std::string& buf)
	{
		for (auto& c : buf) {
			const auto temp = static_cast<uint8_t>(c);
			if (((keybyte << counter) & 0x80) != 0)
				c = static_cast<char>(~temp);
			if (++counter > 7) {
				counter = 0;
				keybyte = temp;
			}
		}
	}
};

std::string
WavFile(const std::string& d, size_t hdr, const std::string& pcm)
{
	auto put16 = [](std::string& s, uint16_t v) {
		s.append(reinterpret_cast<const char*>(&v), 2);
	};
	auto put32 = [](std::string& s, uint32_t v) {
		s.append(reinterpret_cast<const char*>(&v), 4);
	};
	std::string w = "RIFF";
	put32(w, static_cast<uint32_t>(36 + pcm.size()));
	w += "WAVEfmt ";
	put32(w, 16);
	put16(w, Get<uint16_t>(d, hdr + 32)); // format
	put16(w, Get<uint16_t>(d, hdr + 34)); // channels
	put32(w, Get<uint32_t>(d, hdr + 36)); // sample rate
	put32(w, Get<uint32_t>(d, hdr + 40)); // byte rate
	put16(w, Get<uint16_t>(d, hdr + 44)); // block align
	put16(w, Get<uint16_t>(d, hdr + 46)); // bits per sample
	w += "data";
	put32(w, static_cast<uint32_t>(pcm.size()));
	w += pcm;
	return w;
}

bool
ParseOJM(const std::string& d, std::vector<OJMSample>& out)
{
	if (d.size() < 20)
		return false;
	const auto sig = d.substr(0, 4);

	if (sig == std::string("M30\0", 4)) {
		const auto encryption = Get<int32_t>(d, 8);
		const auto count = Get<int32_t>(d, 12);
		size_t off = 28;
		for (int i = 0; i < count && off + 52 <= d.size(); i++) {
			const auto size = static_cast<size_t>(Get<int32_t>(d, off + 32));
			const auto codec = Get<int16_t>(d, off + 36);
			const auto ref = Get<int16_t>(d, off + 44);
			off += 52;
			if (off + size > d.size())
				break;
			auto data = d.substr(off, size);
			off += size;
			const char* mask = encryption == 16	  ? "nami"
							   : encryption == 32 ? "0412"
												  : nullptr;
			if (mask != nullptr)
				for (size_t j = 0; j + 3 < data.size(); j += 4)
					for (int k = 0; k < 4; k++)
						data[j + k] ^= mask[k];
			out.push_back({ codec == 0 ? 1000 + ref : ref, "ogg", data });
		}
		return true;
	}

	if (sig == std::string("OMC\0", 4) || sig == std::string("OJM\0", 4)) {
		const auto scrambled = sig[1] == 'M';
		const auto oggStart = static_cast<size_t>(Get<int32_t>(d, 12));
		const auto fileSize =
		  std::min(static_cast<size_t>(Get<int32_t>(d, 16)), d.size());
		AccXor acc;
		size_t off = 20;
		int id = 0;
		while (off < oggStart && off + 56 <= d.size()) {
			const auto hdr = off;
			const auto size = static_cast<size_t>(Get<int32_t>(d, off + 52));
			off += 56;
			if (size == 0 || off + size > d.size()) {
				id++;
				off += size;
				continue;
			}
			auto pcm = d.substr(off, size);
			off += size;
			if (scrambled) {
				Rearrange(pcm);
				acc.Apply(pcm);
			}
			out.push_back({ id++, "wav", WavFile(d, hdr, pcm) });
		}
		id = 1000;
		off = std::max(off, oggStart);
		while (off + 36 <= fileSize) {
			const auto size = static_cast<size_t>(Get<int32_t>(d, off + 32));
			off += 36;
			if (size == 0) {
				id++;
				continue;
			}
			if (off + size > d.size())
				break;
			out.push_back({ id++, "ogg", d.substr(off, size) });
			off += size;
		}
		return true;
	}
	return false;
}

std::string
SampleFileName(int id, const std::string& ext)
{
	return SAMPLE_DIR + ssprintf("%04d.%s", id, ext.c_str());
}

void
WriteIfChanged(const std::string& path, const std::string& data)
{
	if (IsAFile(path) && GetFileSizeInBytes(path) == static_cast<int>(data.size()))
		return;
	RageFile f;
	if (!f.Open(path, RageFile::WRITE)) {
		Locator::getLogger()->warn("OJN: can't write {}: {}", path, f.GetError());
		return;
	}
	f.Write(data);
	f.Close();
}

/* Writes the bank into _o2jam/ once and returns the sample files, sorted by
 * id, relative to the song folder. */
std::vector<std::string>
ExtractSamples(const std::string& dir, const std::string& ojmName)
{
	std::vector<std::string> files;
	std::string ojmPath = dir + ojmName;
	if (ojmName.empty() || !IsAFile(ojmPath)) {
		// the header name may differ in case or be missing
		std::vector<std::string> found;
		FILEMAN->GetDirListing(dir + "*.ojm", found, ONLY_FILE, false);
		if (found.empty())
			return files;
		ojmPath = dir + found[0];
	}

	std::string bank;
	std::vector<OJMSample> samples;
	if (!ReadWholeFile(ojmPath, bank) || !ParseOJM(bank, samples)) {
		Locator::getLogger()->warn("OJN: {} isn't a sample bank I can read",
								   ojmPath);
		return files;
	}
	bank.clear();

	FILEMAN->CreateDir(dir + SAMPLE_DIR);
	std::sort(samples.begin(), samples.end(), [](auto& a, auto& b) {
		return a.id < b.id;
	});
	for (auto& s : samples) {
		const auto name = SampleFileName(s.id, s.ext);
		WriteIfChanged(dir + name, s.data);
		files.push_back(name);
	}
	FILEMAN->FlushDirCache(dir + SAMPLE_DIR);
	FILEMAN->FlushDirCache(dir);
	return files;
}

// sample id -> index in the song's keysound list, from the file names
std::map<int, int>
KeysoundIndices(const Song& song)
{
	std::map<int, int> ids;
	for (size_t i = 0; i < song.m_vsKeysoundFile.size(); i++) {
		const auto& f = song.m_vsKeysoundFile[i];
		if (f.compare(0, SAMPLE_DIR.size(), SAMPLE_DIR) != 0)
			continue;
		ids[atoi(f.c_str() + SAMPLE_DIR.size())] = static_cast<int>(i);
	}
	return ids;
}

/* ---- notes ---- */

int
DiffIndex(Difficulty dc)
{
	switch (dc) {
		case Difficulty_Easy:
			return 0;
		case Difficulty_Medium:
			return 1;
		default:
			return 2;
	}
}

bool
ReadChart(const std::string& block, float headerBpm, Steps& out)
{
	const auto& keysounds = KeysoundIndices(*out.m_pSong);
	auto keysound = [&](int value, int type) {
		auto id = value - 1;
		if (type % 8 > 3)
			id += 1000;
		const auto it = keysounds.find(id);
		return it == keysounds.end() ? -1 : it->second;
	};

	struct Package
	{
		int measure;
		int channel;
		size_t off;
		int count;
	};
	std::vector<Package> packages;
	std::map<int, float> measureLength; // in measures, default 1
	int lastMeasure = 0;
	for (size_t off = 0; off + 8 <= block.size();) {
		Package p{ Get<int32_t>(block, off),
				   Get<int16_t>(block, off + 4),
				   off + 8,
				   Get<int16_t>(block, off + 6) };
		off += 8 + 4 * static_cast<size_t>(std::max(p.count, 0));
		if (p.measure < 0 || p.measure > 10000 || p.count <= 0 ||
			off > block.size())
			continue;
		lastMeasure = std::max(lastMeasure, p.measure);
		if (p.channel == 0) {
			for (int i = 0; i < p.count; i++) {
				const auto v = Get<float>(block, p.off + 4 * i);
				if (v > 0.f)
					measureLength[p.measure] = v;
			}
		}
		packages.push_back(p);
	}
	if (packages.empty())
		return false;

	// beat where each measure starts
	std::vector<double> measureBeat(lastMeasure + 2, 0.0);
	for (int m = 0; m <= lastMeasure; m++) {
		const auto it = measureLength.find(m);
		const double len = it == measureLength.end() ? 1.0 : it->second;
		measureBeat[m + 1] = measureBeat[m] + 4.0 * len;
	}
	auto rowAt = [&](const Package& p, int i) {
		const auto len = measureBeat[p.measure + 1] - measureBeat[p.measure];
		return BeatToNoteRow(
		  static_cast<float>(measureBeat[p.measure] + len * i / p.count));
	};

	TimingData td;
	td.m_fBeat0OffsetInSeconds = 0.f;
	td.SetBPMAtRow(0, headerBpm > 0.f ? headerBpm : 120.f);
	for (const auto& [m, len] : measureLength) {
		if (std::abs(len - 1.f) < 0.0001f)
			continue;
		// measure length as n/den with the smallest den that fits
		for (int den = 4; den <= 192; den++) {
			const auto num = len * den;
			if (std::abs(num - std::round(num)) < 0.001f && num >= 1.f) {
				td.SetTimeSignatureAtRow(BeatToNoteRow(static_cast<float>(
										   measureBeat[m])),
										 static_cast<int>(std::round(num)),
										 den);
				td.SetTimeSignatureAtRow(
				  BeatToNoteRow(static_cast<float>(measureBeat[m + 1])), 4, 4);
				break;
			}
		}
	}

	const auto tracks = GAMEMAN->GetStepsTypeInfo(out.m_StepsType).iNumTracks;
	NoteData nd;
	nd.SetNumTracks(tracks);
	std::vector<int> holdStart(tracks, -1);
	struct Auto
	{
		int row;
		int index;
	};
	std::vector<Auto> autos;

	// events in time order, so long note ends follow their heads
	struct Event
	{
		int row;
		int channel;
		int value;
		int type;
	};
	std::vector<Event> events;
	std::vector<std::pair<int, float>> bpms{ { 0, td.GetBPMAtRow(0) } };
	for (const auto& p : packages) {
		for (int i = 0; i < p.count; i++) {
			const auto at = p.off + 4 * i;
			const auto row = rowAt(p, i);
			if (p.channel == 1) {
				const auto bpm = Get<float>(block, at);
				if (bpm > 0.f) {
					td.SetBPMAtRow(row, bpm);
					bpms.emplace_back(row, bpm);
				}
				continue;
			}
			if (p.channel == 0)
				continue;
			const auto value = Get<int16_t>(block, at);
			if (value == 0)
				continue;
			events.push_back(
			  { row, p.channel, value, Get<uint8_t>(block, at + 3) });
		}
	}
	std::stable_sort(events.begin(), events.end(), [](auto& a, auto& b) {
		return a.row < b.row;
	});

	for (const auto& e : events) {
		const auto index = keysound(e.value, e.type);
		if (e.channel > 8) {
			autos.push_back({ e.row, index });
			continue;
		}
		const auto track = e.channel - 2;
		if (track >= tracks)
			continue;
		const auto type = e.type % 4;
		if (type == 3) { // long note end
			if (holdStart[track] != -1 && holdStart[track] < e.row) {
				TapNote tn = nd.GetTapNote(track, holdStart[track]);
				tn.type = TapNoteType_HoldHead;
				tn.subType = TapNoteSubType_Hold;
				nd.AddHoldNote(track, holdStart[track], e.row, tn);
			}
			holdStart[track] = -1;
			continue;
		}
		TapNote tn = TAP_ORIGINAL_TAP;
		tn.iKeysoundIndex = index;
		nd.SetTapNote(track, e.row, tn);
		holdStart[track] = type == 2 ? e.row : -1;
	}

	/* Most O2Jam charts made outside the original game keep the whole song
	 * in one sample started once by the background channel. Play that as
	 * the song's music instead of as a keysound: it then goes through the
	 * same path as every other chart, with the global offset applied the
	 * same way, and the beat-0 offset puts the chart where the sample starts.
	 */
	int musicIndex = -1;
	for (size_t i = 0; i < out.m_pSong->m_vsKeysoundFile.size(); i++)
		if (out.m_pSong->m_vsKeysoundFile[i] == out.m_pSong->m_sMusicFile)
			musicIndex = static_cast<int>(i);
	const auto musicStarts = std::count_if(
	  autos.begin(), autos.end(), [&](auto& a) { return a.index == musicIndex; });
	if (musicIndex >= 0 && musicStarts == 1) {
		const auto it = std::find_if(autos.begin(), autos.end(), [&](auto& a) {
			return a.index == musicIndex;
		});
		std::stable_sort(bpms.begin(), bpms.end(), [](auto& a, auto& b) {
			return a.first < b.first;
		});
		double seconds = 0.0;
		int lastRow = 0;
		float bpm = bpms.front().second;
		for (const auto& [row, b] : bpms) {
			if (row >= it->row)
				break;
			seconds += NoteRowToBeat(row - lastRow) * 60.0 / bpm;
			lastRow = row;
			bpm = b;
		}
		seconds += NoteRowToBeat(it->row - lastRow) * 60.0 / bpm;
		td.m_fBeat0OffsetInSeconds = static_cast<float>(seconds);
		autos.erase(it);
	}

	// background samples go on a free lane as autoplay keysounds
	for (const auto& a : autos) {
		if (a.index < 0)
			continue;
		for (int d : { 0, -1, 1 }) {
			const auto row = a.row + d;
			if (row < 0)
				continue;
			auto placed = false;
			for (int t = 0; t < tracks && !placed; t++) {
				if (nd.GetTapNote(t, row) == TAP_EMPTY &&
					!nd.IsHoldNoteAtRow(t, row)) {
					TapNote tn = TAP_ORIGINAL_AUTO_KEYSOUND;
					tn.iKeysoundIndex = a.index;
					nd.SetTapNote(t, row, tn);
					placed = true;
				}
			}
			if (placed)
				break;
		}
	}

	td.TidyUpData(false);
	out.SetNoteData(nd);
	out.m_Timing = td;
	out.TidyUpData();
	out.SetSavedToDisk(true);
	return true;
}

} // namespace

void
OJNLoader::GetApplicableFiles(const std::string& sPath,
							  std::vector<std::string>& out)
{
	FILEMAN->GetDirListing(sPath + std::string("*.ojn"), out, ONLY_FILE);
}

bool
OJNLoader::LoadNoteDataFromSimfile(const std::string& path, Steps& out)
{
	std::string d;
	OJNHeader h;
	if (!ReadWholeFile(path, d) || !ParseHeader(d, h))
		return false;
	return ReadChart(
	  ChartBlock(d, h, DiffIndex(out.GetDifficulty())), h.bpm, out);
}

bool
OJNLoader::LoadFromDir(const std::string& sDir, Song& out)
{
	std::vector<std::string> files;
	GetApplicableFiles(sDir, files);
	if (files.empty())
		return false;
	std::sort(files.begin(), files.end());
	const auto path = sDir + files[0];

	std::string d;
	OJNHeader h;
	if (!ReadWholeFile(path, d) || !ParseHeader(d, h)) {
		Locator::getLogger()->warn("OJN: {} isn't an O2Jam chart", path);
		return false;
	}

	out.m_vsKeysoundFile = ExtractSamples(sDir, h.ojmFile);

	// cover image, plus the small thumbnail after it
	if (h.coverSize > 0 &&
		static_cast<size_t>(h.noteOffset[3]) + h.coverSize <= d.size()) {
		const auto cover = SAMPLE_DIR + "cover.jpg";
		FILEMAN->CreateDir(sDir + SAMPLE_DIR);
		WriteIfChanged(sDir + cover, d.substr(h.noteOffset[3], h.coverSize));
		out.m_sBackgroundFile = cover;
		out.m_sJacketFile = cover;
		out.m_sBannerFile = cover;
	}

	std::string title = h.title;
	std::string artist = h.artist;
	std::string noter = h.noter;
	KoreanToUtf8(title);
	KoreanToUtf8(artist);
	KoreanToUtf8(noter);

	out.m_sSongFileName = path;
	NotesLoader::GetMainAndSubTitlesFromFullTitle(
	  title, out.m_sMainTitle, out.m_sSubTitle);
	out.m_sArtist = artist;
	out.m_sGenre = GENRES[(h.genre < 0 || h.genre > 10) ? 10 : h.genre];
	out.m_sCredit = noter;

	/* The longest sample is the backing track when there is one. ReadChart
	 * turns it into real music when the chart starts it once; otherwise it
	 * only serves the preview and song length, and AutoKeysounds won't play
	 * it on top of the keysounds. */
	{
		size_t best = 0;
		for (const auto& f : out.m_vsKeysoundFile) {
			const auto size =
			  static_cast<size_t>(std::max(GetFileSizeInBytes(sDir + f), 0));
			if (size > best) {
				best = size;
				out.m_sMusicFile = f;
			}
		}
	}

	// EX/NX/HX; the same chart is often stored more than once, keep one
	const Difficulty diffs[3] = { Difficulty_Easy,
								  Difficulty_Medium,
								  Difficulty_Hard };
	std::set<std::string> seen;
	Steps* main = nullptr;
	for (int i = 2; i >= 0; i--) {
		const auto block = ChartBlock(d, h, i);
		if (block.empty() || !seen.insert(block).second)
			continue;
		auto* steps = out.CreateSteps();
		steps->SetFilename(path);
		steps->m_StepsType = StepsType_kb7_single;
		steps->m_StepsTypeStr =
		  GAMEMAN->GetStepsTypeInfo(StepsType_kb7_single).szName;
		steps->SetDifficulty(diffs[i]);
		steps->SetMeter(h.level[i]);
		steps->SetCredit(noter);
		if (!ReadChart(block, h.bpm, *steps)) {
			delete steps;
			continue;
		}
		out.AddSteps(steps);
		if (main == nullptr)
			main = steps;
	}
	if (main == nullptr)
		return false;
	out.m_SongTiming = main->m_Timing;
	return true;
}

void
OJNLoader::SortLooseCharts(const std::string& packDir)
{
	auto dir = packDir;
	if (dir.empty())
		return;
	if (dir.back() != '/')
		dir += "/";
	std::vector<std::string> charts;
	FILEMAN->GetDirListing(dir + "*.ojn", charts, ONLY_FILE, false);
	if (charts.empty())
		return;

	std::vector<std::string> banks;
	FILEMAN->GetDirListing(dir + "*.ojm", banks, ONLY_FILE, false);
	auto findBank = [&](const std::string& name) -> std::string {
		for (const auto& b : banks)
			if (make_lower(b) == make_lower(name))
				return b;
		return "";
	};

	// which bank each chart uses, and how many charts share it
	std::vector<std::string> bankOf(charts.size());
	std::map<std::string, int> users;
	for (size_t i = 0; i < charts.size(); i++) {
		RageFile f;
		std::string head;
		if (f.Open(dir + charts[i], RageFile::READ))
			f.Read(head, HEADER_SIZE);
		OJNHeader h;
		auto bank = ParseHeader(head + std::string(HEADER_SIZE, '\0'), h)
					  ? findBank(h.ojmFile)
					  : "";
		if (bank.empty())
			bank = findBank(SetExtension(charts[i], "ojm"));
		bankOf[i] = bank;
		if (!bank.empty())
			users[bank]++;
	}

	auto moved = 0;
	for (size_t i = 0; i < charts.size(); i++) {
		const auto songDir = dir + GetFileNameWithoutExtension(charts[i]) + "/";
		if (IsAFile(songDir + charts[i])) {
			Locator::getLogger()->warn(
			  "OJN: {} is already in {}, leaving the loose copy alone",
			  charts[i],
			  songDir);
			continue;
		}
		FILEMAN->CreateDir(songDir);
		if (!FILEMAN->Move(dir + charts[i], songDir + charts[i])) {
			Locator::getLogger()->warn("OJN: couldn't move {} into {}",
									   charts[i],
									   songDir);
			continue;
		}
		const auto& bank = bankOf[i];
		if (!bank.empty() && !IsAFile(songDir + bank)) {
			if (users[bank] == 1)
				FILEMAN->Move(dir + bank, songDir + bank);
			else
				FileCopy(dir + bank, songDir + bank);
		}
		moved++;
	}
	FILEMAN->FlushDirCache(dir);
	Locator::getLogger()->info(
	  "OJN: gave {} loose O2Jam charts in {} their own folders", moved, dir);
}
