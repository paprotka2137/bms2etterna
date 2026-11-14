#ifndef NetworkSyncManager_H
#define NetworkSyncManager_H

#include "Etterna/Models/Misc/Difficulty.h"
#include "Etterna/Models/HighScore/HighScore.h"

#include "Etterna/Models/Network/NetworkConstants.h"

#include <atomic>
#include <memory>
#include <thread>

class LoadingWindow;
class RoomData;
class Song;
class PlayerStageStats;
class NetProtocol;
class ETTProtocol;

const int ETTPCVERSION = 5;
const int NETNUMTAPSCORES = 8;

class EndOfGame_PlayerData
{
  public:
	int name{0};
	std::string nameStr;
	int grade;
	int score;
	Difficulty difficulty;
	int tapScores[NETNUMTAPSCORES]; // This will be a const soon enough
	HighScore hs;
	std::string playerOptions;
};

enum NSMANStartupStatus
{
	INIT,
	SUCCESSFUL,
	NOT_SUCCESSFUL, // also "connection attempt in progress"
};

/** @brief A special foreach loop going through each NSScoreBoardColumn. */
#define FOREACH_NSScoreBoardColumn(sc) FOREACH_ENUM(NSScoreBoardColumn, sc)

class ChartRequest
{
  public:
	ChartRequest(const char* ck, const char* requester, int rate)
	  : chartkey(ck)
	  , user(requester)
	  , rate(rate)
	{
	}
	const std::string chartkey;
	const std::string user; // User that requested this chart
	const int rate;			// rate * 1000
	void PushSelf(lua_State* L);
};

class GameplayScore
{
  public:
	float wife;
	std::string jdgstr;
};

// Regular pair map except [anyString, 0] is the same key
class Chat
{
  public:
	std::map<std::pair<std::string, int>, std::vector<std::string>> rawMap;

	auto operator[](const std::pair<std::string, int>& p)
	  -> std::vector<std::string>&
	{
		if (p.second == 0) {
			return rawMap.operator[](std::make_pair(std::string(""), 0));
		}
		{
			return rawMap.operator[](p);
		}
	}
};

class NetworkSyncManager
{
  public:
	NetworkSyncManager(LoadingWindow* ld = nullptr);
	~NetworkSyncManager();
	NetProtocol* curProtocol{ nullptr };

	void ReportHighScore(HighScore* hs, PlayerStageStats& pss);
	void ReportSongOver();

	// triggered by button presses in gameplay
	void ReportReplayInput(bool isPress,
						   int col,
						   int row,
						   float fMusicSeconds,
						   float fNoteOffset,
						   int tapNoteType,
						   int tapNoteSubType);

	// triggered by a miss in gameplay
	void ReportReplayMiss(int col,
						  int row,
						  int tapNoteType,
						  int tapNoteSubType);

	// triggered by completing or dropping a hold in gameplay
	void ReportReplayHold(int col, int row, int subType);

	// triggered by hitting a mine in gameplay
	void ReportReplayMine(int row, int col);

	// triggered by a judgment
	void ReportV2Data(int col, int row, float offset, int tapNoteType);

	void OnMusicSelect();
	void OffMusicSelect();

	void OnOptions();
	void OffOptions();

	void OnEval();
	void OffEval();

	// Request a start; Block until granted.
	void StartRequest(short position);

	auto GetServerName() const -> std::string;

	void CreateNewRoom(std::string name,
					   std::string desc = "",
					   std::string password = "");
	bool CreatingRoom();
	void EnterRoom(std::string name, std::string password = "");
	void LeaveRoom();
	std::string GetRoomName();

	void PostStartUp(const std::string& ServerIP);

	auto IsETTP() -> bool;

	void CloseConnection();

	// Notify user if connect attempt was
	// successful or not.
	void DisplayStartupStatus() const;

	void Update(float fDeltaTime);

	bool need_to_disconnect = false;
	bool useSMserver;
	bool isSMOnline;
	bool loggedIn;
	std::string loggedInUsername;
	std::string loginResponse; // Failure reason

	// [{Tabname, int}] = std::vector<line>
	Chat chat;

	std::vector<int> m_PlayerStatus;
	int m_ActivePlayers;
	std::vector<int> m_ActivePlayer;
	std::vector<std::string> m_PlayerNames;
	std::vector<bool> m_PlayerReady;
	std::vector<std::string> commonpacks;

	// Used for ScreenNetEvaluation
	std::vector<EndOfGame_PlayerData> m_EvalPlayerData;

	std::set<std::string> lobbyuserlist;

	void SendMPLeaderboardUpdate(float wife, std::string& jdgstr);

	// Used for chatting
	// 0=lobby (ettp only)
	void SendChat(const std::string& message,
				  std::string tab = "",
				  int type = 0);

	/////////////////////////
	// Used for song checking/changing
	std::string m_sMainTitle;
	std::string m_sArtist;
	std::string m_sSubTitle;
	std::string m_sFileHash;
	std::string chartkey;
	Song* song{ nullptr };
	Steps* steps{ nullptr };
	std::map<std::string, GameplayScore> mpleaderboard;
	void PushMPLeaderboard(lua_State* L);
	Difficulty difficulty;
	int meter;
	int rate;
	/////////////////////////

	int m_iSelectMode;
	void SelectUserSong();

	std::string m_sChatText;

	// Used to see if attempt was successful or not.
	NSMANStartupStatus m_startupStatus;

	void Login(std::string user, std::string pass);
	void Logout();
	auto GetServerVersion() -> int;

	std::vector<RoomData> m_Rooms;
	std::vector<ChartRequest*> requests;
	std::vector<ChartRequest*> staleRequests;

	bool spectating = false;
	std::string spectatingWho{};

	// Live spectating through the ranking site (Scripts/BMSSpectate.lua),
	// no multiplayer room needed. The player: while liveBroadcast is on, what
	// the Player reports (presses, misses, dropped holds, mines) is kept in
	// liveEvents as text lines until the theme takes and sends them. The
	// spectator: FeedLiveEvents gives the lines back to the spectate replay
	// that ScreenGameplaySpectate plays.
	bool liveBroadcast = false;
	bool liveSpectate = false; // spectating is the site's live mode
	std::string liveEvents{};
	void LiveEvent(const char* fmt, ...);
	auto FeedLiveEvents(const std::string& who, const std::string& text)
	  -> int;

	// After a network error the connection is made again in the background
	// (also during a song), logged in with the same account and put back in
	// the same room, without leaving the current screen. Score and status
	// messages sent meanwhile wait and go out once the room is joined again.
	bool reconnecting = false;
	// set by ETTProtocol: the room could be joined again / could not
	void RejoinFinished(bool ok);
	[[nodiscard]] auto RejoinRoom() const -> const std::string&
	{
		return m_sRejoinRoom;
	}
	[[nodiscard]] auto RejoinRoomPassword() const -> const std::string&
	{
		return m_sRejoinRoomPass;
	}
	// remembered for a reconnect (ETTProtocol keeps them when a room is
	// created or entered)
	void RememberRoom(const std::string& name, const std::string& pass);

	// Lua
	void PushSelf(lua_State* L);

  private:
	void StartUp();
	void StartReconnect();
	void UpdateReconnect(float fDeltaTime);

	std::string m_sServerAddress; // what PostStartUp connected to
	unsigned short m_iServerPort = 0;
	std::string m_sLoginUser, m_sLoginPass;
	std::string m_sRoomName, m_sRoomPass; // the room we are in
	std::string m_sRejoinRoom, m_sRejoinRoomPass; // the room to get back to
	int m_iReconnectTries = 0;
	int m_iRejoinResult = 0; // set by RejoinFinished: 1 ok, -1 failed
	float m_fReconnectWait = 0.F;
	bool m_bReconnectLoggingIn = false;
	std::unique_ptr<std::thread> m_ReconnectThread;
	std::atomic<bool> m_bReconnectDone{ false };
	ETTProtocol* m_pReconnected = nullptr; // set by the thread
	std::vector<std::string> m_vHeldMessages; // sent once the room is back

	bool ShouldSendMessage(bool requiresLogin = false) const;
};

extern NetworkSyncManager* NSMAN;

#endif
