#ifndef LIFEMETERBAR_H
#define LIFEMETERBAR_H

#include "Etterna/Actor/Base/AutoActor.h"
#include "LifeMeter.h"
#include "Etterna/Models/Misc/ThemeMetric.h"

class StreamDisplay;
class Song;
class Steps;

/** @brief The player's life represented as a bar. */
class LifeMeterBar : public LifeMeter
{
  public:
	LifeMeterBar();
	~LifeMeterBar() override;

	void Load(const PlayerState* pPlayerState,
			  PlayerStageStats* pPlayerStageStats) override;

	void Update(float fDeltaTime) override;

	void ChangeLife(TapNoteScore score) override;
	void ChangeLife(HoldNoteScore score, TapNoteScore tscore) override;
	void ChangeLife(float fDeltaLifePercent) override;
	void SetLife(float value) override;
	void HandleTapScoreNone() override;
	virtual void AfterLifeChanged();
	bool IsInDanger() const override;
	bool IsHot() const override;
	bool IsFailing() const override;
	bool IsFailingAtEnd() const override;
	bool IsBMSGauge() const override { return m_bBMS; }
	int GetBMSGauge() const override { return m_bBMS ? m_BMSGauge : -1; }
	int GetBMSClassGauge() const override
	{
		return m_bBMS ? m_iBMSClassGauge : -1;
	}
	float GetLife() const override { return m_fLifePercentage; }

	void FillForHowToPlay(int NumT2s, int NumMisses);
	static float MapTNSToDeltaLife(TapNoteScore s);
	static float MapHNSToDeltaLife(HoldNoteScore score);
	/** @brief BMS TOTAL of a chart and where it came from ("#TOTAL",
	 * "json md5", "json title" or "default") */
	static float GetBMSTotal(const Song* song,
							 const Steps* steps,
							 std::string& source);
	/** @brief BMS #RANK of a chart (0 VERY HARD, 1 HARD, 2 NORMAL, 3 EASY,
	 * 4 VERY EASY) and where it came from, -1 when the chart doesn't say */
	static int GetBMSRank(const Song* song,
						  const Steps* steps,
						  std::string& source);

  private:
	// BMS (beatoraja) gauge, used instead of the normal bar on 7k charts.
	// Values are in gauge percent (0-100), in the order PG GR GD BD PR MS.
	enum BMSJudge
	{
		BMS_PG,
		BMS_GR,
		BMS_GD,
		BMS_BD,
		BMS_PR,
		BMS_MS,
		NUM_BMSJudge
	};
	void LoadBMSGauge();
	static float FindBMSTotal(const Song* song,
							  const Steps* steps,
							  std::string& source);
	void ChangeBMSLife(BMSJudge judge);
	void RecordBMSGauges(float fStepsSecond);
	void SetBMSCurrentGauge(BMSGauge gauge);
	BMSGauge PickBMSAutoShiftGauge() const;
	bool m_bBMS{ false };
	// O2Jam chart: the O2Jam hard gauge, filed under BMSGauge_Hard
	bool m_bO2Jam{ false };
	bool m_bBMSAutoShift{ false };
	// the gauge shown and judged on, with auto shift it moves down
	BMSGauge m_BMSGauge{ BMSGauge_Normal };
	// every gauge runs when auto shift tracks it, values in gauge percent
	bool m_bBMSTracked[NUM_BMSGauge]{};
	float m_fBMSValue[NUM_BMSGauge]{};
	float m_fBMSChange[NUM_BMSGauge][NUM_BMSJudge]{};
	// BMS dan course: one course gauge (CLASS / EX CLASS / EX HARD CLASS)
	// instead of the chosen one, its value carried over the songs since the
	// life meter lives for the whole course. -1 outside a course.
	// With auto shift every course gauge below the chosen one runs too and
	// the shown one drops to the strongest that is still alive.
	int m_iBMSClassGauge{ -1 };
	int m_iBMSClassTop{ -1 };
	bool m_bBMSClassAutoShift{ false };
	float m_fBMSClassValues[3]{ 100.f, 100.f, 100.f };
	void ChangeBMSClassLife(BMSJudge judge);
	void SaveBMSClassState() const;
	void RecordBMSClassGauge(float fStepsSecond) const;
	float m_fBMSMin{ 0.f };
	float m_fBMSBorder{ 0.f };

	ThemeMetric<float> DANGER_THRESHOLD;
	ThemeMetric<float> INITIAL_VALUE;
	ThemeMetric<float> HOT_VALUE;
	ThemeMetric<float> LIFE_MULTIPLIER;
	ThemeMetric<TapNoteScore> MIN_STAY_ALIVE;

	ThemeMetric1D<float> m_fLifePercentChange;

	// Doing this proper, let's not vector lookup for these values every update
	// - Mina
	float m_Change_SE_W1;
	float m_Change_SE_W2;
	float m_Change_SE_W3;
	float m_Change_SE_W4;
	float m_Change_SE_W5;
	float m_Change_SE_Miss;
	float m_Change_SE_HitMine;
	float m_Change_SE_CheckpointHit;
	float m_Change_SE_CheckpointMiss;
	float m_Change_SE_Held;
	float m_Change_SE_LetGo;

	AutoActor m_sprUnder;
	AutoActor m_sprDanger;
	StreamDisplay* m_pStream;
	AutoActor m_sprOver;

	float m_fLifePercentage;

	float m_fPassingAlpha;
	float m_fHotAlpha;

	float m_fBaseLifeDifficulty;
	float m_fLifeDifficulty; // essentially same as pref

	int m_iProgressiveLifebar; // cached from prefs
	/** @brief The current number of progressive W5/miss rankings. */
	int m_iMissCombo;
	/** @brief The combo needed before the life bar starts to fill up after a
	 * Player failed. */
	int m_iComboToRegainLife;
};

#endif
