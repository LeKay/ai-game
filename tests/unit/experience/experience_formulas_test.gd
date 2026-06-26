class_name ExperienceFormulasTest
extends GdUnitTestSuite
## Unit tests for the Experience System curve (design/gdd/experience-system.md, F2/F3).
## Covers AC-3 (level derivation incl. inclusive boundaries) and AC-6 (cap behaviour).

# ---- F2: xp_to_advance (per-level cost) --------------------------------------

func test_xp_to_advance_matches_default_curve() -> void:
	# Arrange / Act / Assert — the published default curve (rounded to XP_ROUNDING = 10).
	assert_int(ExperienceFormulas.xp_to_advance(1)).is_equal(100)
	assert_int(ExperienceFormulas.xp_to_advance(2)).is_equal(280)
	assert_int(ExperienceFormulas.xp_to_advance(3)).is_equal(520)
	assert_int(ExperienceFormulas.xp_to_advance(4)).is_equal(800)
	assert_int(ExperienceFormulas.xp_to_advance(5)).is_equal(1120)
	assert_int(ExperienceFormulas.xp_to_advance(6)).is_equal(1470)
	assert_int(ExperienceFormulas.xp_to_advance(7)).is_equal(1850)
	assert_int(ExperienceFormulas.xp_to_advance(8)).is_equal(2260)
	assert_int(ExperienceFormulas.xp_to_advance(9)).is_equal(2700)

func test_xp_to_advance_at_and_beyond_max_is_zero() -> void:
	assert_int(ExperienceFormulas.xp_to_advance(ExperienceFormulas.MAX_LEVEL)).is_equal(0)
	assert_int(ExperienceFormulas.xp_to_advance(ExperienceFormulas.MAX_LEVEL + 5)).is_equal(0)

func test_xp_to_advance_clamps_low_input() -> void:
	# level < 1 is treated as level 1.
	assert_int(ExperienceFormulas.xp_to_advance(0)).is_equal(100)
	assert_int(ExperienceFormulas.xp_to_advance(-3)).is_equal(100)

# ---- F2: cumulative_xp (threshold to reach a level) --------------------------

func test_cumulative_xp_matches_default_curve() -> void:
	assert_int(ExperienceFormulas.cumulative_xp(1)).is_equal(0)
	assert_int(ExperienceFormulas.cumulative_xp(2)).is_equal(100)
	assert_int(ExperienceFormulas.cumulative_xp(3)).is_equal(380)
	assert_int(ExperienceFormulas.cumulative_xp(4)).is_equal(900)
	assert_int(ExperienceFormulas.cumulative_xp(5)).is_equal(1700)
	assert_int(ExperienceFormulas.cumulative_xp(10)).is_equal(11100)

# ---- F2: level_for_total_xp --------------------------------------------------

func test_level_for_total_xp_zero_is_level_one() -> void:
	assert_int(ExperienceFormulas.level_for_total_xp(0)).is_equal(1)

func test_level_for_total_xp_below_first_threshold_is_level_one() -> void:
	assert_int(ExperienceFormulas.level_for_total_xp(99)).is_equal(1)

func test_level_for_total_xp_threshold_is_inclusive() -> void:
	# Reaching exactly cumulative_xp(2) = 100 counts as level 2 (AC-3, EC-8).
	assert_int(ExperienceFormulas.level_for_total_xp(100)).is_equal(2)
	assert_int(ExperienceFormulas.level_for_total_xp(380)).is_equal(3)

func test_level_for_total_xp_between_thresholds() -> void:
	assert_int(ExperienceFormulas.level_for_total_xp(500)).is_equal(3)
	assert_int(ExperienceFormulas.level_for_total_xp(899)).is_equal(3)

func test_level_for_total_xp_caps_at_max() -> void:
	# At and beyond the level-10 threshold the level never exceeds MAX_LEVEL (AC-6).
	assert_int(ExperienceFormulas.level_for_total_xp(11100)).is_equal(10)
	assert_int(ExperienceFormulas.level_for_total_xp(11099)).is_equal(9)
	assert_int(ExperienceFormulas.level_for_total_xp(999999)).is_equal(10)

# ---- F3: progress within a level ---------------------------------------------

func test_xp_into_level_and_span() -> void:
	# total 500 at level 3: 500 - cumulative_xp(3)=380 → 120 into level 3, whose span is
	# xp_to_advance(3) = 520 (the XP needed to clear level 3 and reach level 4).
	assert_int(ExperienceFormulas.xp_into_level(500, 3)).is_equal(120)
	assert_int(ExperienceFormulas.xp_span_of_level(3)).is_equal(520)

func test_progress_in_level_is_fraction() -> void:
	assert_float(ExperienceFormulas.progress_in_level(500, 3)).is_equal_approx(120.0 / 520.0, 0.0001)

func test_progress_in_level_at_max_is_full() -> void:
	# xp_span is 0 at MAX_LEVEL → progress reports a full bar (no division by zero).
	assert_float(ExperienceFormulas.progress_in_level(11100, ExperienceFormulas.MAX_LEVEL)).is_equal(1.0)
	assert_int(ExperienceFormulas.xp_span_of_level(ExperienceFormulas.MAX_LEVEL)).is_equal(0)
