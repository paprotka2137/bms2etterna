#include "Etterna/Globals/global.h"
#include "LifeMeter.h"
#include "LifeMeterBar.h"

LifeMeter*
LifeMeter::MakeLifeMeter(LifeType t)
{
	switch (t) {
		case LifeType_Bar:
			return new LifeMeterBar;
		default:
			FAIL_M(ssprintf("Unrecognized LifeMeter type: %i", t));
	}
}

// lua start
#include "Etterna/Models/Lua/LuaBinding.h"

/** @brief Allow Lua to have access to the LifeMeter. */
class LunaLifeMeter : public Luna<LifeMeter>
{
  public:
	static int GetLife(T* p, lua_State* L)
	{
		LuaHelpers::Push(L, p->GetLife());
		return 1;
	}
	static int IsInDanger(T* p, lua_State* L)
	{
		LuaHelpers::Push(L, p->IsInDanger());
		return 1;
	}
	static int IsHot(T* p, lua_State* L)
	{
		LuaHelpers::Push(L, p->IsHot());
		return 1;
	}
	static int IsFailing(T* p, lua_State* L)
	{
		LuaHelpers::Push(L, p->IsFailing());
		return 1;
	}

	// the BMS gauge in effect ("Easy", "Normal", "Hard", "ExHard",
	// "Death"), nil when the bar is not a BMS gauge
	static int GetBMSGauge(T* p, lua_State* L)
	{
		const auto g = p->GetBMSGauge();
		if (g < 0 || g >= NUM_BMSGauge)
			lua_pushnil(L);
		else
			LuaHelpers::Push(L, BMSGaugeToString(static_cast<BMSGauge>(g)));
		return 1;
	}

	// in a BMS dan course the course gauge ("Class", "ExClass",
	// "ExHardClass") played instead of the chosen one, nil otherwise
	static int GetBMSClassGauge(T* p, lua_State* L)
	{
		static const char* names[] = { "Class", "ExClass", "ExHardClass" };
		const auto g = p->GetBMSClassGauge();
		if (g < 0 || g > 2)
			lua_pushnil(L);
		else
			lua_pushstring(L, names[g]);
		return 1;
	}

	LunaLifeMeter()
	{
		ADD_METHOD(GetBMSClassGauge);
		ADD_METHOD(GetLife);
		ADD_METHOD(IsInDanger);
		ADD_METHOD(IsHot);
		ADD_METHOD(IsFailing);
		ADD_METHOD(GetBMSGauge);
	}
};

LUA_REGISTER_DERIVED_CLASS(LifeMeter, ActorFrame)
// lua end
