#ifndef LIFE_METER_H
#define LIFE_METER_H

#include "Etterna/Actor/Base/ActorFrame.h"
#include "Etterna/Models/Misc/GameConstantsAndTypes.h"
#include "Etterna/Models/Misc/PlayerOptions.h"

class PlayerState;
class PlayerStageStats;

/** @brief The player's life. */
class LifeMeter : public ActorFrame
{
  public:
	LifeMeter() = default;
	~LifeMeter() override = default;

	virtual void Load(const PlayerState* pPlayerState,
					  PlayerStageStats* pPlayerStageStats)
	{
		m_pPlayerState = pPlayerState;
		m_pPlayerStageStats = pPlayerStageStats;
	}
	virtual void OnLoadSong(){};
	virtual void OnSongEnded(){};
	/**
	 * @brief Change life after receiving a tap note grade.
	 *
	 * This *is* called for the head of hold notes.
	 * @param score the tap note grade in question. */
	virtual void ChangeLife(TapNoteScore score) = 0;
	/**
	 * @brief Change life after receiving a hold note grade.
	 *
	 * @param hns the hold note grade in question.
	 * @param tns the score received for the initial tap note. */
	virtual void ChangeLife(HoldNoteScore hns, TapNoteScore tns) = 0;
	virtual void ChangeLife(float delta) = 0;
	virtual void SetLife(float value) = 0;
	virtual void HandleTapScoreNone() = 0;
	[[nodiscard]] virtual auto IsInDanger() const -> bool = 0;
	[[nodiscard]] virtual auto IsHot() const -> bool = 0;
	[[nodiscard]] virtual auto IsFailing() const -> bool = 0;
	/** @brief Whether the player fails if the song ends right now. Gauges
	 * that only judge at the end (BMS groove) differ from IsFailing. */
	[[nodiscard]] virtual auto IsFailingAtEnd() const -> bool
	{
		return IsFailing();
	}
	/** @brief BMS gauges take a judgement for every note, not every row. */
	[[nodiscard]] virtual auto IsBMSGauge() const -> bool { return false; }
	/** @brief The BMS gauge being played on (a BMSGauge), -1 for others. With
	 * gauge auto shift it is the best gauge still alive. */
	[[nodiscard]] virtual auto GetBMSGauge() const -> int { return -1; }
	/** @brief In a BMS dan course: the course gauge (0 CLASS, 1 EX CLASS,
	 * 2 EX HARD CLASS) that replaces the chosen gauge, -1 otherwise. */
	[[nodiscard]] virtual auto GetBMSClassGauge() const -> int { return -1; }
	[[nodiscard]] virtual auto GetLife() const -> float
	{
		return 0;
	} // for cosmetic use only

	static auto MakeLifeMeter(LifeType t) -> LifeMeter*;

	//
	// Lua
	//
	void PushSelf(lua_State* L) override;

  protected:
	const PlayerState* m_pPlayerState{};
	PlayerStageStats* m_pPlayerStageStats{};
};

#endif
