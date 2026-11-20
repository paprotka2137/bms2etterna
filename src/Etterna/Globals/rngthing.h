#include <random>
#include <algorithm>

using RandomGen = std::mt19937;
extern RandomGen g_RandomNumberGenerator;

void
seed_lua_prng();

inline auto
random_up_to(RandomGen& rng, int limit) -> int
{
	RandomGen::result_type res = rng();
	// Cutting off the incomplete [0,n) chunk at the max value makes the result
	// more evenly distributed. -Kyz
	RandomGen::result_type up_to_max =
	  RandomGen::max() - (RandomGen::max() % limit);
	while (res > up_to_max) {
		res = rng();
	}

	return static_cast<int>(res % limit);
}

// Multiplayer /random seeds end in this 16 bit tag (the room server makes
// them). Shuffles on such a seed use seeded_shuffle's own Fisher-Yates, which
// gives the same lanes on every OS; std::shuffle differs between MSVC and
// libstdc++. Other seeds keep std::shuffle so older replays rebuild the same.
constexpr unsigned ROOM_SEED_TAG = 0x7B4DU;
inline auto
is_room_seed(int seed) -> bool
{
	return (static_cast<unsigned>(seed) & 0xFFFFU) == ROOM_SEED_TAG;
}

template<class It>
void
seeded_shuffle(It first, It last, RandomGen& rng, int seed)
{
	if (!is_room_seed(seed)) {
		std::shuffle(first, last, rng);
		return;
	}
	for (auto i = static_cast<int>(last - first) - 1; i > 0; --i)
		std::iter_swap(first + i, first + random_up_to(rng, i + 1));
}

inline auto
random_up_to(int limit) -> int
{
	return random_up_to(g_RandomNumberGenerator, limit);
}

inline auto
RandomFloat() -> float
{
	return static_cast<float>(g_RandomNumberGenerator() / 4294967296.0);
}

inline auto
RandomFloat(float fLow, float fHigh) -> float
{
	// SCALE() but l1 = 0 and h1 = 1 so simplifies to this
	return (RandomFloat() * (fHigh - fLow)) + fLow;
}

inline auto
RandomInt(int low, int high) -> int
{
	return random_up_to(g_RandomNumberGenerator, high - low + 1) + low;
}

inline auto
RandomInt(int n) -> int
{
	return random_up_to(g_RandomNumberGenerator, n);
}

inline auto
RandomInt(RandomGen& rng, int n) -> int
{
	return random_up_to(rng, n);
}


inline auto
randomf(const float low = -1.F, const float high = 1.F) -> float
{
	return RandomFloat(low, high);
}
