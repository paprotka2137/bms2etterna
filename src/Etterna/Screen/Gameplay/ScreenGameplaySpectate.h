#ifndef ScreenGameplaySpectate_H
#define ScreenGameplaySpectate_H

#include "ScreenGameplay.h"
#include "Etterna/Models/Misc/PlayerOptions.h"
#include "Etterna/Models/Songs/SongOptions.h"

class ScreenGameplaySpectate : public ScreenGameplay
{
  public:
	void FillPlayerInfo(std::vector<PlayerInfo>& playerInfoOut) override;
	ScreenGameplaySpectate();
	void Init() override;
	~ScreenGameplaySpectate() override;

	void Update(float fDeltaTime) override;
	bool Input(const InputEventPlus& input) override;

	void HandleScreenMessage(const ScreenMessage& SM) override;

	// Lua
	void PushSelf(lua_State* L) override;

  protected:
	// live spectating through the ranking site: the spectator's own options,
	// rate and seed, put back when the screen goes away
	bool m_bRestoreOptions{ false };
	PlayerOptions m_OldPlayerOptions;
	SongOptions m_OldSongOptions;
	int m_iOldStageSeed{ 0 };
	int m_iSpectateSeed{ 0 };

	void SaveStats() override;
	void StageFinished(bool bBackedOut) override;
	void LoadPlayer() override;
	void LoadScoreKeeper() override;
};

#endif
