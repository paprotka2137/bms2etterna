#ifndef NOTES_LOADER_OJN_H
#define NOTES_LOADER_OJN_H

#include <string>
#include <vector>

class Song;
class Steps;

/** @brief Reads a Song from an O2Jam .ojn chart and its .ojm sample bank.
 *
 * The samples in the .ojm are written out once into a _o2jam folder next to
 * the chart, so the engine can play them as ordinary keysounds. */
namespace OJNLoader {
void
GetApplicableFiles(const std::string& sPath, std::vector<std::string>& out);
bool
LoadFromDir(const std::string& sDir, Song& out);
bool
LoadNoteDataFromSimfile(const std::string& path, Steps& out);
/** O2Jam keeps every .ojn/.ojm loose in one folder. Give each chart lying
 * directly in a pack folder its own song folder, so a pack can be filled the
 * same way as O2Jam's Music folder. */
void
SortLooseCharts(const std::string& packDir);
} // namespace OJNLoader

#endif
