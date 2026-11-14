#include "Etterna/Globals/global.h"
#include "NetworkSyncManager.h"
#include "Etterna/Singletons/LuaManager.h"
#include "Etterna/Singletons/SongManager.h"
#include "Etterna/Singletons/GameState.h"
#include "Etterna/Singletons/MessageManager.h"
#include "Etterna/Singletons/ProfileManager.h"
#include "Etterna/Singletons/ScreenManager.h"
#include "Etterna/Singletons/StatsManager.h"
#include "Etterna/Models/Misc/RoomWheel.h"
#include "Etterna/Models/Misc/LocalizedString.h"
#include "Core/Services/Locator.hpp"
#include "arch/LoadingWindow/LoadingWindow.h"

#include "Etterna/Models/Network/ETTProtocol.h"
#include "Etterna/Models/HighScore/Replay.h"
#include "Etterna/Models/Misc/NoteTypes.h"
#include "Etterna/Models/Misc/PlayerState.h"
#include "Etterna/Models/StepsAndStyles/Style.h"
#include "Etterna/Singletons/ReplayManager.h"

NetworkSyncManager* NSMAN;

#include <cerrno>
#include <cstdarg>
#include <cstdio>
#include <sstream>
#include <chrono>
#include <cmath>
#include <array>
#ifndef _WIN32
#include <arpa/inet.h>
#endif


extern Preference<std::string> g_sLastServer;
Preference<unsigned int> autoConnectMultiplayer("AutoConnectMultiplayer", 1);

// The live spectating stream (one message per keypress, miss and hold) is
// off: the BMS 7k server does not use it and on the free Cloudflare plan
// every message counts against the daily request limit.
static constexpr bool SEND_REPLAY_STREAM = false;


static LocalizedString CONNECTION_SUCCESSFUL("NetworkSyncManager",
											 "Connection to '%s' successful.");
static LocalizedString CONNECTION_FAILED("NetworkSyncManager",
										 "Connection failed.");

NetworkSyncManager::NetworkSyncManager(LoadingWindow* ld)
{
	NSMAN = this;
	useSMserver = false;
	isSMOnline = false;
	loggedIn = false;
	m_startupStatus = NSMANStartupStatus::INIT;
	m_ActivePlayers = 0;
	if (ld) {
		ld->SetIndeterminate(true);
		ld->SetText("\nConnecting to multiplayer server");
	}
	StartUp();

	m_iSelectMode = 0;

	// Register with Lua.
	{
		Lua* L = LUA->Get();
		lua_pushstring(L, "NSMAN");
		this->PushSelf(L);
		lua_settable(L, LUA_GLOBALSINDEX);
		LUA->Release(L);
	}
}

NetworkSyncManager::~NetworkSyncManager()
{
	if (m_ReconnectThread && m_ReconnectThread->joinable())
		m_ReconnectThread->join();
}

void
NetworkSyncManager::OnMusicSelect()
{
	if (ShouldSendMessage(true))
		curProtocol->OnMusicSelect();
}

void
NetworkSyncManager::OffMusicSelect()
{
	if (ShouldSendMessage(true))
		curProtocol->OffMusicSelect();
}

void
NetworkSyncManager::OnOptions()
{
	if (ShouldSendMessage(true))
		curProtocol->OnOptions();
}
void
NetworkSyncManager::OffOptions()
{
	if (ShouldSendMessage(true))
		curProtocol->OffOptions();
}

void
NetworkSyncManager::OnEval()
{
	if (ShouldSendMessage(true))
		curProtocol->OnEval();
}
void
NetworkSyncManager::OffEval()
{
	if (ShouldSendMessage(true))
		curProtocol->OffEval();
}

void
NetworkSyncManager::CloseConnection()
{
	if (!useSMserver)
		return;
	m_sChatText = "";
	need_to_disconnect = false;
	reconnecting = false;
	m_bReconnectLoggingIn = false;
	m_vHeldMessages.clear();
	m_sRoomName.clear();
	m_sRoomPass.clear();
	useSMserver = false;
	isSMOnline = false;
	loggedIn = false;
	loginResponse = "";
	m_startupStatus = NSMANStartupStatus::INIT;
	song = nullptr;
	steps = nullptr;
	rate = 0;
	chartkey = "";
	m_sFileHash = "";
	m_sMainTitle = "";
	m_sSubTitle = "";
	m_sArtist = "";
	difficulty = Difficulty_Invalid;
	meter = -1;
	if (curProtocol)
		curProtocol->close();
	curProtocol = nullptr;
	MESSAGEMAN->Broadcast("MultiplayerDisconnection");
}

void
NetworkSyncManager::PostStartUp(const std::string& ServerIP)
{
	std::string sAddress;
	unsigned short iPort;
	m_startupStatus = NSMANStartupStatus::NOT_SUCCESSFUL;

	// "ws://host[:port][/path]" and "wss://..." are used as they are (the
	// BMS 7k server lives at wss://<ranking site>/multi); a bare
	// "host[:port]" keeps the old plain ws:// on port 8765
	if (ServerIP.starts_with("wss://") || ServerIP.starts_with("ws://")) {
		sAddress = ServerIP;
		iPort = 0;
	} else if (ServerIP.find(':') != std::string::npos) {
		const size_t cLoc = ServerIP.find(':');
		sAddress = ServerIP.substr(0, cLoc);
		char* cEnd;
		errno = 0;
		auto sub = ServerIP.substr(cLoc + 1);
		iPort = static_cast<unsigned short>(strtol(sub.c_str(), &cEnd, 10));
		if (*cEnd != 0 || errno != 0) {
			Locator::getLogger()->warn("Invalid port {}", sub);
			return;
		}
	} else {
		iPort = 8765;
		sAddress = ServerIP;
	}

	chat.rawMap.clear();
	Locator::getLogger()->info(
	  "Attempting to connect to: {}, Port: {}", sAddress.c_str(), iPort);
	curProtocol = nullptr;
	CloseConnection();

	auto ETTP = new ETTProtocol;

	if (ETTP->Connect(this, iPort, sAddress))
		curProtocol = ETTP;
	m_sServerAddress = sAddress;
	m_iServerPort = iPort;
	if (curProtocol == nullptr)
		return;
	g_sLastServer.Set(ServerIP);
	loggedIn = false;
	useSMserver = true;
	m_startupStatus = NSMANStartupStatus::SUCCESSFUL;
	song = nullptr;
	steps = nullptr;
	rate = 0;
	chartkey = "";
	m_sFileHash = "";
	m_sMainTitle = "";
	m_sSubTitle = "";
	m_sArtist = "";
	difficulty = Difficulty_Invalid;
	meter = -1;
	Locator::getLogger()->info("Server Version: {} {}",
							   curProtocol->serverVersion,
							   curProtocol->serverName.c_str());
	MESSAGEMAN->Broadcast("MultiplayerConnection");
}

bool
NetworkSyncManager::IsETTP()
{
	return true;
}

bool
NetworkSyncManager::ShouldSendMessage(bool requiresLogin) const
{
	return curProtocol != nullptr && isSMOnline &&
		   (!requiresLogin || (requiresLogin && loggedIn));
}

void
NetworkSyncManager::StartUp()
{
	std::string ServerIP;

	// EtternaOnline's multiplayer server is gone, move old settings over
	// to this build's server
	if (g_sLastServer.Get().find("etternaonline.com") != std::string::npos)
		g_sLastServer.Set(g_sLastServer.GetDefault());

	if (GetCommandlineArgument("netip", &ServerIP))
		PostStartUp(ServerIP);
	else if (autoConnectMultiplayer)
		PostStartUp(std::string(g_sLastServer));
}

std::string
NetworkSyncManager::GetServerName() const
{
	return curProtocol != nullptr ? curProtocol->serverName : "";
}

void
NetworkSyncManager::Logout()
{
	if (ShouldSendMessage(true))
		curProtocol->Logout();
}

void
NetworkSyncManager::Login(std::string user, std::string pass)
{
	if (ShouldSendMessage(false)) {
		m_sLoginUser = user;
		m_sLoginPass = pass;
		curProtocol->Login(user, pass);
	}
}

void
NetworkSyncManager::ReportHighScore(HighScore* hs, PlayerStageStats& pss)
{
	if (ShouldSendMessage(true))
		curProtocol->ReportHighScore(hs, pss);
}

void
NetworkSyncManager::ReportReplayInput(bool isPress,
									  int col,
									  int row,
									  float fMusicSeconds,
									  float fNoteOffset,
									  int tapNoteType,
									  int tapNoteSubType)
{
	// times in microseconds: whole numbers read back the same in any locale
	if (liveBroadcast && !spectating)
		LiveEvent("I %d %d %d %lld %lld %d %d",
				  isPress ? 1 : 0,
				  col,
				  row,
				  std::llround(fMusicSeconds * 1e6),
				  std::llround(fNoteOffset * 1e6),
				  tapNoteType,
				  tapNoteSubType);
	if (SEND_REPLAY_STREAM && ShouldSendMessage(true) && !spectating)
		curProtocol->ReportReplayInput(this,
									   isPress,
									   col,
									   row,
									   fMusicSeconds,
									   fNoteOffset,
									   tapNoteType,
									   tapNoteSubType);
}

void
NetworkSyncManager::ReportReplayMiss(int col,
									 int row,
									 int tapNoteType,
									 int tapNoteSubType)
{
	if (liveBroadcast && !spectating)
		LiveEvent("M %d %d %d %d", col, row, tapNoteType, tapNoteSubType);
	if (SEND_REPLAY_STREAM && ShouldSendMessage(true) && !spectating)
		curProtocol->ReportReplayMiss(
		  this, col, row, tapNoteType, tapNoteSubType);
}

void
NetworkSyncManager::ReportReplayHold(int col, int row, int subType)
{
	if (liveBroadcast && !spectating)
		LiveEvent("H %d %d %d", col, row, subType);
	if (SEND_REPLAY_STREAM && ShouldSendMessage(true) && !spectating)
		curProtocol->ReportReplayHold(this, col, row, subType);
}

void
NetworkSyncManager::ReportReplayMine(int row, int col)
{
	if (liveBroadcast && !spectating)
		LiveEvent("N %d %d", col, row);
	if (SEND_REPLAY_STREAM && ShouldSendMessage(true) && !spectating)
		curProtocol->ReportReplayMine(this, row, col);
}

void
NetworkSyncManager::ReportV2Data(int col,
								 int row,
								 float offset,
								 int tapNoteType)
{
	if (SEND_REPLAY_STREAM && ShouldSendMessage(true) && !spectating)
		curProtocol->ReportV2Data(col, row, offset, tapNoteType);
}

// ------------------------------------------------------------ live spectating

void
NetworkSyncManager::LiveEvent(const char* fmt, ...)
{
	// only a real play of a chart is sent (not a replay, practice or spectate)
	if (GAMESTATE->GetGameplayMode() != GameplayMode_Normal ||
		GAMESTATE->m_pPlayerState == nullptr ||
		GAMESTATE->m_pPlayerState->m_PlayerController != PC_HUMAN)
		return;
	// the theme takes them every second or so; if it stops, stop growing
	if (liveEvents.size() > 4 * 1024 * 1024)
		return;
	char buf[128];
	va_list args;
	va_start(args, fmt);
	const auto n = std::vsnprintf(buf, sizeof(buf), fmt, args);
	va_end(args);
	if (n <= 0 || n >= static_cast<int>(sizeof(buf)))
		return;
	liveEvents.append(buf, n);
	liveEvents.push_back('\n');
}

auto
NetworkSyncManager::FeedLiveEvents(const std::string& who,
								   const std::string& text) -> int
{
	auto* replay = REPLAYS->GetSpectateReplay(who);
	if (replay == nullptr ||
		SONGMAN->GetStepsByChartkey(replay->GetChartKey()) == nullptr)
		return 0;
	// lines come from the site: anything out of range is skipped, the
	// spectating Player indexes its columns with these
	const auto* style = GAMESTATE->GetCurrentStyle(PLAYER_1);
	const auto cols = style != nullptr ? style->m_iColsPerPlayer : 0;
	const auto okCol = [cols](int c) { return c >= 0 && c < cols; };
	// a tap has no subtype (TapNoteSubType_Invalid) and a press far from any
	// note no type either, so the _Invalid values are fine too
	const auto okTnt = [](int t) {
		return t >= 0 && t <= TapNoteType_Invalid;
	};
	const auto okTnst = [](int t) {
		return t >= 0 && t <= TapNoteSubType_Invalid;
	};

	auto n = 0;
	std::istringstream in(text);
	std::string line;
	while (std::getline(in, line)) {
		if (line.size() < 2)
			continue;
		const auto* rest = line.c_str() + 1;
		int a = 0, col = 0, row = 0, t1 = 0, t2 = 0;
		long long secs = 0, offset = 0;
		switch (line[0]) {
			case 'I':
				if (std::sscanf(rest,
								"%d %d %d %lld %lld %d %d",
								&a,
								&col,
								&row,
								&secs,
								&offset,
								&t1,
								&t2) != 7 ||
					!okCol(col) || row < -1 || !okTnt(t1) || !okTnst(t2))
					continue;
				// the Player reports minus its note offset, IngestInputData
				// takes the offset itself (ETTProtocol does the same)
				replay->IngestInputData(a != 0,
										col,
										row,
										static_cast<float>(secs / 1e6),
										static_cast<float>(-offset / 1e6),
										static_cast<TapNoteType>(t1),
										static_cast<TapNoteSubType>(t2));
				{
					Message msg(Message_SpectatorInputUpdate);
					msg.SetParam("playerID", who);
					MESSAGEMAN->Broadcast(msg);
				}
				break;
			case 'M':
				if (std::sscanf(rest, "%d %d %d %d", &col, &row, &t1, &t2) !=
					  4 ||
					!okCol(col) || row < 0 || !okTnt(t1) || !okTnst(t2))
					continue;
				replay->IngestMissData(col,
									   row,
									   static_cast<TapNoteType>(t1),
									   static_cast<TapNoteSubType>(t2));
				{
					Message msg(Message_SpectatorMissUpdate);
					msg.SetParam("playerID", who);
					MESSAGEMAN->Broadcast(msg);
				}
				break;
			case 'H':
				if (std::sscanf(rest, "%d %d %d", &col, &row, &t1) != 3 ||
					!okCol(col) || row < 0 || !okTnst(t1))
					continue;
				replay->IngestHoldDrop(
				  col, row, static_cast<TapNoteSubType>(t1));
				{
					Message msg(Message_SpectatorHoldUpdate);
					msg.SetParam("playerID", who);
					MESSAGEMAN->Broadcast(msg);
				}
				break;
			case 'N':
				if (std::sscanf(rest, "%d %d", &col, &row) != 2 ||
					!okCol(col) || row < 0)
					continue;
				replay->IngestMineHit(col, row);
				{
					Message msg(Message_SpectatorMineUpdate);
					msg.SetParam("playerID", who);
					MESSAGEMAN->Broadcast(msg);
				}
				break;
			default:
				continue;
		}
		n++;
	}
	return n;
}

void
NetworkSyncManager::ReportSongOver()
{
	if (ShouldSendMessage(true))
		curProtocol->ReportSongOver(this);
}

void
NetworkSyncManager::StartRequest(short position)
{
	// This needs to be reset before ScreenEvaluation could possibly be
	// called
	m_EvalPlayerData.clear();
	if (ShouldSendMessage(true))
		curProtocol->StartRequest(this, position);
}

void
NetworkSyncManager::DisplayStartupStatus() const
{
	std::string sMessage("");

	switch (m_startupStatus) {
		case NSMANStartupStatus::INIT:
			return;
		case NSMANStartupStatus::SUCCESSFUL:
			if (curProtocol != nullptr)
				sMessage = ssprintf(CONNECTION_SUCCESSFUL.GetValue(),
									curProtocol->serverName.c_str());
			else
				sMessage = CONNECTION_FAILED.GetValue();
			break;
		case NSMANStartupStatus::NOT_SUCCESSFUL:
			sMessage = CONNECTION_FAILED.GetValue();
			break;
	}
	SCREENMAN->SystemMessage(sMessage);
}

void
NetworkSyncManager::Update(float fDeltaTime)
{
	if (reconnecting) {
		UpdateReconnect(fDeltaTime);
		return;
	}
	if (curProtocol != nullptr) {
		if (need_to_disconnect) {
			// logged in: try to get the connection (and the room) back
			if (loggedIn && !m_sLoginUser.empty() && !m_sServerAddress.empty())
				StartReconnect();
			else {
				SCREENMAN->SystemMessage("Disconnected from the multiplayer server.");
				CloseConnection();
			}
		} else {
			curProtocol->Update(this, fDeltaTime);
		}
	}
}

// ------------------------------------------------------------ reconnecting

static constexpr int RECONNECT_TRIES = 6;
static constexpr float RECONNECT_LOGIN_SECONDS = 15.F;

void
NetworkSyncManager::RememberRoom(const std::string& name,
								 const std::string& pass)
{
	m_sRoomName = name;
	m_sRoomPass = pass;
}

void
NetworkSyncManager::RejoinFinished(bool ok)
{
	// only noted here: this is called from inside ETTProtocol::Update
	m_iRejoinResult = ok ? 1 : -1;
}

void
NetworkSyncManager::StartReconnect()
{
	Locator::getLogger()->warn("Multiplayer connection lost, reconnecting");
	SCREENMAN->SystemMessage("Multiplayer connection lost, reconnecting...");
	need_to_disconnect = false;
	reconnecting = true;
	m_bReconnectLoggingIn = false;
	m_iReconnectTries = 0;
	m_iRejoinResult = 0;
	m_fReconnectWait = 0.5F;
	m_sRejoinRoom = m_sRoomName;
	m_sRejoinRoomPass = m_sRoomPass;
	m_vHeldMessages.clear();
	// the old connection stays as curProtocol so whatever the game sends
	// meanwhile (the score at the end of the song) queues up in it
	if (curProtocol != nullptr) {
		curProtocol->close();
		auto* old = dynamic_cast<ETTProtocol*>(curProtocol);
		if (old != nullptr)
			old->holding = false;
	}
}

// what of the dead connection's queue is still worth sending
static bool
KeepAfterReconnect(const std::string& msg)
{
	static const std::set<std::string> keep = { "score",	   "gameover",
												"openeval",	   "closeeval",
												"openoptions", "closeoptions",
												"chat",		   "leaveroom" };
	return keep.count(ETTProtocol::MessageType(msg)) > 0;
}

void
NetworkSyncManager::UpdateReconnect(float fDeltaTime)
{
	auto* cur = dynamic_cast<ETTProtocol*>(curProtocol);

	// connected again: logging in and getting back into the room
	if (m_bReconnectLoggingIn) {
		if (cur != nullptr)
			cur->Update(this, fDeltaTime);
		m_fReconnectWait += fDeltaTime;
		const bool failed = need_to_disconnect || m_iRejoinResult < 0 ||
							m_fReconnectWait > RECONNECT_LOGIN_SECONDS;
		if (m_iRejoinResult > 0 && !need_to_disconnect) {
			// back: everything held goes out now
			reconnecting = false;
			m_bReconnectLoggingIn = false;
			if (cur != nullptr) {
				for (auto& m : m_vHeldMessages)
					cur->Send(m);
				m_vHeldMessages.clear();
				cur->ReleaseHeld();
			}
			Locator::getLogger()->info("Multiplayer reconnected");
			SCREENMAN->SystemMessage("Reconnected to the multiplayer server.");
			return;
		}
		if (!failed)
			return;
		// the room is gone or the login was refused: give up
		if (m_iRejoinResult < 0) {
			SCREENMAN->SystemMessage(
			  "Reconnected, but could not get back into the room.");
			CloseConnection();
			return;
		}
		// the new connection died too: keep what it held and try again
		need_to_disconnect = false;
		m_bReconnectLoggingIn = false;
		if (cur != nullptr) {
			cur->close();
			for (auto& m : cur->heldMessages)
				if (KeepAfterReconnect(m))
					m_vHeldMessages.push_back(m);
			cur->heldMessages.clear();
		}
		m_fReconnectWait = 2.F;
	}

	// a connection attempt is running in the background
	if (m_ReconnectThread) {
		if (!m_bReconnectDone)
			return;
		m_ReconnectThread->join();
		m_ReconnectThread.reset();
		auto* fresh = m_pReconnected;
		m_pReconnected = nullptr;
		if (fresh != nullptr) {
			// move what the old connection never sent over to the new one
			if (cur != nullptr) {
				for (auto& m : cur->TakeUnsent())
					if (KeepAfterReconnect(m))
						m_vHeldMessages.push_back(m);
				for (auto& m : cur->heldMessages)
					if (KeepAfterReconnect(m))
						m_vHeldMessages.push_back(m);
				cur->heldMessages.clear();
				delete cur;
			}
			fresh->holding = true;
			curProtocol = fresh;
			isSMOnline = true;
			m_iRejoinResult = 0;
			m_fReconnectWait = 0.F;
			m_bReconnectLoggingIn = true;
			fresh->Login(m_sLoginUser, m_sLoginPass);
			return;
		}
		m_fReconnectWait = std::min(1.F * (1 << m_iReconnectTries), 8.F);
		return;
	}

	m_fReconnectWait -= fDeltaTime;
	if (m_fReconnectWait > 0.F)
		return;
	if (m_iReconnectTries >= RECONNECT_TRIES) {
		Locator::getLogger()->error("Multiplayer reconnect failed");
		SCREENMAN->SystemMessage(
		  "Could not reconnect to the multiplayer server.");
		CloseConnection();
		return;
	}
	m_iReconnectTries++;
	m_bReconnectDone = false;
	const auto address = m_sServerAddress;
	const auto port = m_iServerPort;
	m_ReconnectThread = std::make_unique<std::thread>([this, address, port]() {
		auto* p = new ETTProtocol;
		if (!p->Connect(nullptr, port, address)) {
			delete p;
			p = nullptr;
		}
		m_pReconnected = p;
		m_bReconnectDone = true;
	});
}

void
NetworkSyncManager::SendChat(const std::string& message,
							 std::string tab,
							 int type)
{
	if (ShouldSendMessage(true))
		curProtocol->SendChat(message, tab, type);
}

void
NetworkSyncManager::SendMPLeaderboardUpdate(float wife, std::string& jdgstr)
{
	if (ShouldSendMessage(true) && !spectating)
		curProtocol->SendMPLeaderboardUpdate(wife, jdgstr);
}

int
NetworkSyncManager::GetServerVersion()
{
	return curProtocol != nullptr ? curProtocol->serverVersion : -1;
}
void
NetworkSyncManager::SelectUserSong()
{
	m_EvalPlayerData.clear();
	if (ShouldSendMessage(true))
		curProtocol->SelectUserSong(this, GAMESTATE->m_pCurSong);
}

void
NetworkSyncManager::EnterRoom(std::string name, std::string password)
{
	if (ShouldSendMessage(true))
		curProtocol->EnterRoom(name, password);
}

void
NetworkSyncManager::LeaveRoom()
{
	if (ShouldSendMessage (true))
		curProtocol->LeaveRoom(this);
}

void
NetworkSyncManager::CreateNewRoom(std::string name,
								  std::string desc,
								  std::string password)
{
	if (ShouldSendMessage(true))
		curProtocol->CreateNewRoom(name, desc, password);
}

void
NetworkSyncManager::PushMPLeaderboard(lua_State* L)
{
	lua_newtable(L);
	int i = 1;
	for (auto& pair : mpleaderboard) {
		lua_newtable(L);
		lua_pushnumber(L, pair.second.wife);
		lua_setfield(L, -2, "wife");
		lua_pushstring(L, pair.second.jdgstr.c_str());
		lua_setfield(L, -2, "jdgstr");
		lua_pushstring(L, pair.first.c_str());
		lua_setfield(L, -2, "user");
		lua_rawseti(L, -2, i);
		i++;
	}
}

std::string
NetworkSyncManager::GetRoomName()
{
	if (curProtocol == nullptr) {
		return "";
	}
	if (!IsETTP()) {
		return "";
	}
	auto ettp = dynamic_cast<ETTProtocol*>(curProtocol);
	if (!ettp->InRoom()) {
		return "";
	}
	return ettp->GetRoomName();
}

bool
NetworkSyncManager::CreatingRoom()
{
	if (curProtocol == nullptr) {
		return false;
	}
	if (!IsETTP()) {
		return false;
	}
	auto ettp = dynamic_cast<ETTProtocol*>(curProtocol);
	return ettp->CreatingRoom();
}

static bool
ConnectToServer(const std::string& t)
{
	NSMAN->PostStartUp(t);
	return true;
}

LuaFunction(ConnectToServer,
			ConnectToServer((std::string(SArg(1)).length() == 0)
							  ? std::string(g_sLastServer)
							  : std::string(SArg(1))))

static bool
CloseNetworkConnection()
{
	NSMAN->CloseConnection();
	return true;
}

LuaFunction(IsSMOnlineLoggedIn, NSMAN->loggedIn)
LuaFunction(IsNetConnected, NSMAN->useSMserver)
LuaFunction(IsNetSMOnline, NSMAN->isSMOnline)
LuaFunction(GetServerName, NSMAN->GetServerName())
LuaFunction(CloseConnection, CloseNetworkConnection())

// lua start
#include "Etterna/Models/Lua/LuaBinding.h"

class LunaNetworkSyncManager : public Luna<NetworkSyncManager>
{
  public:
	static int IsETTP(T* p, lua_State* L)
	{
		lua_pushboolean(L, p->IsETTP());
		return 1;
	}
	static int GetMPLeaderboard(T* p, lua_State* L)
	{
		NSMAN->PushMPLeaderboard(L);
		return 1;
	}
	static int RemoveChartRequest(T* p, lua_State* L)
	{
		auto& reqs = p->requests;
		auto reqPtrToRemove = Luna<ChartRequest>::check(L, 1, true);
		auto new_end = remove_if(
		  reqs.begin(), reqs.end(), [reqPtrToRemove](ChartRequest* req) {
			  return req == reqPtrToRemove;
		  });
		reqs.erase(new_end, reqs.end());
		// Keep it in case lua keeps a reference to it
		p->staleRequests.push_back(reqPtrToRemove);
		return 0;
	}
	static int GetChartRequests(T* p, lua_State* L)
	{
		auto& reqs = p->requests;
		lua_newtable(L);
		int i = 1;
		for (auto& req : reqs) {
			req->PushSelf(L);
			lua_rawseti(L, -2, 0);
			i++;
		}
		return 1;
	}
	static int GetChatMsg(T* p, lua_State* L)
	{
		unsigned int l = IArg(1);
		int tabType = IArg(2);
		std::string tabName = SArg(3);
		lua_pushstring(L, p->chat[{ tabName, tabType }][l].c_str());
		return 1;
	}
	static int GetCurrentRoomName(T* p, lua_State* L)
	{
		auto roomname = p->GetRoomName();
		if (roomname == "") {
			lua_pushnil(L);
		}
		lua_pushstring(L, roomname.c_str());
		return 1;
	}
	static int SendChatMsg(T* p, lua_State* L)
	{
		std::string msg = SArg(1);
		int tabType = IArg(2);
		std::string tabName = SArg(3);
		p->SendChat(msg, tabName, tabType);
		return 1;
	}
	static int Logout(T* p, lua_State* L)
	{
		p->Logout();
		return 1;
	}
	static int Login(T* p, lua_State* L)
	{
		std::string user = SArg(1);
		std::string pass = SArg(2);
		p->Login(user, pass);
		return 1;
	}
	static int GetEvalScores(T* p, lua_State* L)
	{
		int i = 1;
		lua_newtable(L);
		for (auto& evalData : NSMAN->m_EvalPlayerData) {
			lua_newtable(L);
			lua_pushstring(L, evalData.nameStr.c_str());
			lua_setfield(L, -2, "user");
			evalData.hs.PushSelf(L);
			lua_setfield(L, -2, "highscore");
			lua_pushstring(L, evalData.playerOptions.c_str());
			lua_setfield(L, -2, "options");
			lua_rawseti(L, -2, i);
			i++;
		}
		return 1;
	}
	static int GetLoggedInUsername(T* p, lua_State* L)
	{
		lua_pushstring(L, NSMAN->loggedInUsername.c_str());
		return 1;
	}
	static int GetLobbyUserList(T* p, lua_State* L)
	{
		lua_newtable(L);
		int i = 1;
		for (auto& user : NSMAN->lobbyuserlist) {
			lua_pushstring(L, user.c_str());
			lua_rawseti(L, -2, i);
			i++;
		}
		return 1;
	}
	// live spectating through the ranking site (Scripts/BMSSpectate.lua)
	static int SetLiveBroadcast(T* p, lua_State* L)
	{
		p->liveBroadcast = BArg(1);
		p->liveEvents.clear();
		return 0;
	}
	static int TakeLiveEvents(T* p, lua_State* L)
	{
		lua_pushlstring(L, p->liveEvents.data(), p->liveEvents.size());
		p->liveEvents.clear();
		return 1;
	}
	static int GetStageSeed(T* p, lua_State* L)
	{
		lua_pushinteger(L, GAMESTATE->m_iStageSeed);
		return 1;
	}
	// StartLiveSpectate(who, chartkey, rate, songoffset, globaloffset, rng, mods)
	static int StartLiveSpectate(T* p, lua_State* L)
	{
		const std::string who = SArg(1);
		const std::string ck = SArg(2);
		if (who.empty() || SONGMAN->GetStepsByChartkey(ck) == nullptr) {
			lua_pushboolean(L, false);
			return 1;
		}
		p->spectating = true;
		p->spectatingWho = who;
		p->liveSpectate = true;
		REPLAYS->InitReplayPlaybackForSpectate(
		  who, ck, FArg(3), FArg(4), FArg(5), IArg(6), SArg(7));
		lua_pushboolean(L, true);
		return 1;
	}
	static int FeedLiveEvents(T* p, lua_State* L)
	{
		if (!p->liveSpectate) {
			lua_pushinteger(L, 0);
			return 1;
		}
		lua_pushinteger(L, p->FeedLiveEvents(SArg(1), SArg(2)));
		return 1;
	}
	static int StopLiveSpectate(T* p, lua_State* L)
	{
		if (p->liveSpectate) {
			p->spectating = false;
			p->spectatingWho.clear();
			p->liveSpectate = false;
		}
		return 0;
	}
	static int IsLiveSpectating(T* p, lua_State* L)
	{
		lua_pushboolean(L, p->liveSpectate);
		return 1;
	}
	LunaNetworkSyncManager()
	{
		ADD_METHOD(SetLiveBroadcast);
		ADD_METHOD(TakeLiveEvents);
		ADD_METHOD(GetStageSeed);
		ADD_METHOD(StartLiveSpectate);
		ADD_METHOD(FeedLiveEvents);
		ADD_METHOD(StopLiveSpectate);
		ADD_METHOD(IsLiveSpectating);
		ADD_METHOD(GetEvalScores);
		ADD_METHOD(GetMPLeaderboard);
		ADD_METHOD(GetChartRequests);
		ADD_METHOD(GetChatMsg);
		ADD_METHOD(SendChatMsg);
		ADD_METHOD(Login);
		ADD_METHOD(Logout);
		ADD_METHOD(IsETTP);
		ADD_METHOD(GetCurrentRoomName);
		ADD_METHOD(GetLobbyUserList);
		ADD_METHOD(GetLoggedInUsername);
	}
};

LUA_REGISTER_CLASS(NetworkSyncManager)

class LunaChartRequest : public Luna<ChartRequest>
{
  public:
	static int GetChartkey(T* p, lua_State* L)
	{
		lua_pushstring(L, p->chartkey.c_str());
		return 1;
	}
	static int GetUser(T* p, lua_State* L)
	{
		lua_pushstring(L, p->user.c_str());
		return 1;
	}
	static int GetRate(T* p, lua_State* L)
	{
		lua_pushnumber(L, p->rate / 1000);
		return 1;
	}

	LunaChartRequest()
	{
		ADD_METHOD(GetChartkey);
		ADD_METHOD(GetUser);
		ADD_METHOD(GetRate);
	}
};

LUA_REGISTER_CLASS(ChartRequest)

// lua end
