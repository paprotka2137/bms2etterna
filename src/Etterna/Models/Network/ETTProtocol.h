#pragma once

#include "NetProtocol.h"
#include "NetworkConstants.h"

#include "rapidjson/document.h"
#include <curl/curl.h>

#include <string>
#include <mutex>
#include <thread>
#include <functional>

class NetworkSyncManager;
struct HighScore;

// Websockets using websocketpp sending json
class ETTProtocol : public NetProtocol
{
  public:
	~ETTProtocol();

	auto Connect(NetworkSyncManager* n,
				 unsigned short port,
				 std::string address) -> bool override;
	void close() override;

	void Update(NetworkSyncManager* n, float fDeltaTime) override;

	void Login(std::string user, std::string pass) override;
	void Logout() override;

	void SendChat(const std::string& message,
				  std::string tab,
				  int type) override;

	void CreateNewRoom(std::string name,
					   std::string desc,
					   std::string password) override;
	void EnterRoom(std::string name, std::string password) override;
	void LeaveRoom(NetworkSyncManager* n) override;
	bool InRoom() const { return inRoom; }
	std::string GetRoomName() { return roomName; }
	bool CreatingRoom() const { return creatingRoom; }

	void ReportSongOver(NetworkSyncManager* n) override;

	void SelectUserSong(NetworkSyncManager* n, Song* song) override;

	void OnMusicSelect() override;

	void OnOptions() override;
	void OffOptions() override;

	void OnEval() override;
	void OffEval() override;

	void SendMPLeaderboardUpdate(float wife, std::string& jdgstr) override;

	void ReportHighScore(HighScore* hs, PlayerStageStats& pss) override;

	// triggered by button presses in gameplay
	void ReportReplayInput(NetworkSyncManager* n,
						   bool isPress,
						   int col,
						   int row,
						   float fMusicSeconds,
						   float fNoteOffset,
						   int tapNoteType,
						   int tapNoteSubType) override;

	// triggered by a miss in gameplay
	void ReportReplayMiss(NetworkSyncManager* n,
						  int col,
						  int row,
						  int tapNoteType,
						  int tapNoteSubType) override;

	// triggered by completing or dropping a hold in gameplay
	void ReportReplayHold(NetworkSyncManager* n,
						  int col,
						  int row,
						  int subType) override;

	void ReportV2Data(int col, int row, float offset, int tapNoteType) override;

	// triggered by hitting a mine in gameplay
	void ReportReplayMine(NetworkSyncManager* n, int row, int col) override;
	void Send(const std::string& str);

	// reconnect support (see NetworkSyncManager::StartReconnect): while
	// holding, only the messages that log in and get back into the room go
	// out, the rest waits in heldMessages
	bool holding = false;
	std::vector<std::string> heldMessages;
	void ReleaseHeld();
	// messages queued but never sent (the connection died first)
	auto TakeUnsent() -> std::vector<std::string>;
	// the type of an outgoing message ("score", "login", ...)
	static auto MessageType(const std::string& msg) -> std::string;

private:
	std::mutex sendBufferMutex;
	std::mutex messageBufferMutex;
	std::mutex curlMutex;
	CURL* curl{ nullptr };

	std::unique_ptr<std::thread> receivingThread;
	std::unique_ptr<std::thread> sendingThread;

	std::atomic_bool stopPolling = false;
	std::atomic_bool stopSending = false;
	void LaunchPollingThread();
	void LaunchSendingThread();

	// 0 = ready, 1 = playing
	// 2 = evalScreen, 3 = options
	// 4 = notReady(unkown reason)
	int state = 0;
	std::string roomName;
	std::string roomDesc;
	bool creatingRoom{ false };
	bool inRoom{ false };
	std::string pendingRoomPass; // password of the room being created/entered
	bool rejoining{ false };	 // the enterroom of a reconnect
	bool rejoinTried{ false };

	// login timeout stuff
	bool waitingForTimeout{ false };
	clock_t timeoutStart = 0;
	double timeout = 0;
	std::function<void(void)> onTimeout;

	// json docs parsed from curl input handled at update
	std::vector<std::unique_ptr<rapidjson::Document>> newMessages;
	std::vector<std::string> messagesToSend{};
	unsigned int msgId{ 0 };

	rapidjson::Document newMsg(const ETTClientMessageTypes& msgType);
	void completeAndSend(rapidjson::Document& doc);

	void handleLogin(rapidjson::Value& payload);
	void handleHello(rapidjson::Value& payload);
	void handleReceiveScore(rapidjson::Value& payload);
	void handlePing();
	void handleSelectChart(rapidjson::Value& payload);
	void handleStartChart(rapidjson::Value& payload);
	void handleReceiveChat(rapidjson::Value& payload);
	void handleMPLeaderboardUpdate(rapidjson::Value& payload);
	void handleCreateRoomResponse(rapidjson::Value& payload);
	void handleChartRequest(rapidjson::Value& payload);
	void handleEnterRoomResponse(rapidjson::Value& payload);
	void handleNewRoom(rapidjson::Value& payload);
	void handleDeleteRoom(rapidjson::Value& payload);
	void handleUpdateRoom(rapidjson::Value& payload);
	void handleLobbyUserlist(rapidjson::Value& payload);
	void handleLobbyUserlistUpdate(rapidjson::Value& payload);
	void handleRoomlist(rapidjson::Value& payload);
	void handleRoomPacklist(rapidjson::Value& payload);
	void handleRoomUserlist(rapidjson::Value& payload);
	void handleGameplayReplayUpdate(rapidjson::Value& payload);
	void handleSpectatingUpdate(rapidjson::Value& payload);

	void FindJsonChart(NetworkSyncManager* n, rapidjson::Value& ch);


};
