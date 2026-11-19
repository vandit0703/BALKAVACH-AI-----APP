"""What the child actually *does* in each catalogue mission, one entry per template slug.

This registry exists so that "six templates per theme" can be checked as "six different activities per theme" and
not just "six database rows". ``mission_catalogue_service.validate_catalogue`` requires an entry for every mission,
requires every ``mechanic`` to be unique across the whole catalogue and compares the English step text of missions in
the same theme. ``catalogue_health`` uses it to count the distinct activities that are actually published.

Plain data, no imports. Fields:

* ``mechanic``  - a short key for the core action (must be unique; two missions may not share one).
* ``summary``   - one sentence a reviewer can read to see the action is different from its neighbours.
* ``evidence``  - ``"guide_activity_type"`` when the *type* of activity is one the Harvard executive-function activities
  guide lists (the guide was read in full, see ``docs/mission-content-research.md``); ``"design_assumption"`` when the
  activity is this project's own design and no source was used for it. Neither is a claim that the mission improves a skill.
"""

ACTIVITIES: dict[str, dict[str, str]] = {
	# Monday: Sound Detective
	"cat1_monday_sound_detective": {
		"mechanic": "identify_everyday_sounds",
		"summary": "Listen for everyday sounds, name them and sort them (near or far, loud or soft).",
		"evidence": "guide_activity_type",
	},
	"cat1_monday_look_closer": {
		"mechanic": "visual_observation_description",
		"summary": "Look closely at one object or room and describe or draw its details.",
		"evidence": "design_assumption",
	},
	"cat1_monday_loud_and_soft": {
		"mechanic": "compare_loudness_and_pitch",
		"summary": "Tap things the same way, compare how loud or high each sound is and put the sounds in order.",
		"evidence": "design_assumption",
	},
	"cat1_monday_sound_order": {
		"mechanic": "sound_order_replay",
		"summary": "Listen to a short run of different sounds, play them back in the same order and write the order down.",
		"evidence": "guide_activity_type",
	},
	"cat1_monday_where_is_it": {
		"mechanic": "locate_sound_and_barriers",
		"summary": "Point to where a sound comes from, then test how distance and barriers change what is heard.",
		"evidence": "design_assumption",
	},
	"cat1_monday_sound_words": {
		"mechanic": "describe_sounds_in_words",
		"summary": "Find sound words and describing words for sounds and test whether a listener can guess the source.",
		"evidence": "design_assumption",
	},
	# Tuesday: Memory Master
	"cat1_tuesday_memory_master": {
		"mechanic": "object_tray_recall",
		"summary": "Look at a set of real objects, cover them and recall them (and later a change).",
		"evidence": "guide_activity_type",
	},
	"cat1_tuesday_picnic_memory": {
		"mechanic": "spoken_chain_recall",
		"summary": "Take turns repeating and extending a spoken list of items.",
		"evidence": "guide_activity_type",
	},
	"cat1_tuesday_draw_from_memory": {
		"mechanic": "visual_scene_recall",
		"summary": "Look at a picture, view or room, hide it and recall or draw what was where.",
		"evidence": "guide_activity_type",
	},
	"cat1_tuesday_what_comes_next": {
		"mechanic": "pattern_rule_continuation",
		"summary": "Find the rule in a repeating or growing pattern, continue it and spot a mistake.",
		"evidence": "design_assumption",
	},
	"cat1_tuesday_list_tricks": {
		"mechanic": "list_memory_strategies",
		"summary": "Remember an errand or list by plain repeating and again with a memory trick, then compare.",
		"evidence": "design_assumption",
	},
	"cat1_tuesday_my_day_replay": {
		"mechanic": "own_day_sequence_recall",
		"summary": "Recall things from the child's own day or week in order, with cues that jog memory.",
		"evidence": "design_assumption",
	},
	# Wednesday: Magic Story Maker
	"cat1_wednesday_magic_story_maker": {
		"mechanic": "invent_story_from_prompts",
		"summary": "Invent a story with a beginning, middle and end from toys, prompts or an object's point of view.",
		"evidence": "guide_activity_type",
	},
	"cat1_wednesday_mystery_clues": {
		"mechanic": "clue_riddles_guessing",
		"summary": "Give clues about a hidden thing so a listener can guess it.",
		"evidence": "guide_activity_type",
	},
	"cat1_wednesday_story_order": {
		"mechanic": "story_event_ordering",
		"summary": "Put the events of a story in order, shuffle them and tell the story with linking words.",
		"evidence": "design_assumption",
	},
	"cat1_wednesday_new_ending": {
		"mechanic": "alternative_story_endings",
		"summary": "Change the ending of a story the child already knows and judge which ending fits.",
		"evidence": "design_assumption",
	},
	"cat1_wednesday_character_card": {
		"mechanic": "character_building",
		"summary": "Invent a character, describe them in detail and show who they are in a small scene.",
		"evidence": "guide_activity_type",
	},
	"cat1_wednesday_what_if_place": {
		"mechanic": "imagined_setting_rules",
		"summary": "Imagine a place or a changed world and work out what follows from it.",
		"evidence": "guide_activity_type",
	},
	# Thursday: Paper Architect
	"cat1_thursday_paper_architect": {
		"mechanic": "paper_tower_and_bridge",
		"summary": "Build a tower or bridge from paper, test it and change one thing.",
		"evidence": "design_assumption",
	},
	"cat1_thursday_paper_flight": {
		"mechanic": "paper_plane_fair_test",
		"summary": "Fold paper planes and test their flights, changing one thing at a time.",
		"evidence": "design_assumption",
	},
	"cat1_thursday_strong_shapes": {
		"mechanic": "paper_shape_strength_test",
		"summary": "Roll, fold or pleat paper into shapes and test which carries the most load.",
		"evidence": "design_assumption",
	},
	"cat1_thursday_paper_boat": {
		"mechanic": "paper_boat_float_and_cargo",
		"summary": "Fold a paper boat, float it and test how much cargo it carries.",
		"evidence": "design_assumption",
	},
	"cat1_thursday_paper_shelter": {
		"mechanic": "paper_shelter_weather_test",
		"summary": "Fold a small shelter for a toy and test it against wind and a few drops of rain.",
		"evidence": "design_assumption",
	},
	"cat1_thursday_paper_weave": {
		"mechanic": "paper_weaving",
		"summary": "Weave torn paper strips over and under into a mat, a pattern or a small basket.",
		"evidence": "design_assumption",
	},
	# Friday: Emotion Detective
	"cat1_friday_emotion_detective": {
		"mechanic": "name_and_calm_own_feelings",
		"summary": "Name a feeling, notice how it changes and try a calming idea.",
		"evidence": "design_assumption",
	},
	"cat1_friday_kind_clues": {
		"mechanic": "kindness_and_other_viewpoints",
		"summary": "Notice a kind act or look at one moment from two sides and say thank you.",
		"evidence": "guide_activity_type",
	},
	"cat1_friday_face_clues": {
		"mechanic": "facial_expression_clues",
		"summary": "Make and draw faces, list what each could mean and practise asking instead of guessing.",
		"evidence": "guide_activity_type",
	},
	"cat1_friday_feelings_in_stories": {
		"mechanic": "feelings_in_fiction",
		"summary": "Follow a toy's or a story character's feelings through a situation or a scene.",
		"evidence": "design_assumption",
	},
	"cat1_friday_calm_words": {
		"mechanic": "calm_words_role_play",
		"summary": "Rehearse calm words and steps for a small pretend problem and swap roles.",
		"evidence": "design_assumption",
	},
	"cat1_friday_listen_and_help": {
		"mechanic": "listening_and_offering_help",
		"summary": "Ask whether someone wants help, hold a short check-in where anyone may pass, or listen without fixing.",
		"evidence": "design_assumption",
	},
	# Saturday: Rhythm Rockstar
	"cat1_saturday_rhythm_rockstar": {
		"mechanic": "copy_and_create_clap_patterns",
		"summary": "Copy, invent and write down clapping patterns and play them from memory.",
		"evidence": "guide_activity_type",
	},
	"cat1_saturday_mirror_moves": {
		"mechanic": "mirror_and_teach_movement_sequence",
		"summary": "Copy slow movements, learn a short move sequence and teach a routine.",
		"evidence": "guide_activity_type",
	},
	"cat1_saturday_name_rhythm": {
		"mechanic": "word_syllable_rhythm",
		"summary": "Turn the syllables and stress of names, phrases or sayings into a clapped rhythm.",
		"evidence": "guide_activity_type",
	},
	"cat1_saturday_home_band": {
		"mechanic": "household_sound_band",
		"summary": "Build sound sequences from household sound-makers and arrange a part for several players.",
		"evidence": "guide_activity_type",
	},
	"cat1_saturday_body_beats": {
		"mechanic": "body_percussion_coordination",
		"summary": "Coordinate stomps, claps and pats to a steady count, and later run two counts against each other.",
		"evidence": "guide_activity_type",
	},
	"cat1_saturday_song_speeds": {
		"mechanic": "tempo_and_volume_control",
		"summary": "Keep a steady beat while a familiar song changes speed and volume, and later arrange it in sections.",
		"evidence": "design_assumption",
	},
	# Sunday: Future Inventor
	"cat1_sunday_future_inventor": {
		"mechanic": "invent_fix_for_real_problem",
		"summary": "Spot a real everyday problem, imagine a fix and take one small real action.",
		"evidence": "guide_activity_type",
	},
	"cat1_sunday_helper_plan": {
		"mechanic": "sort_and_plan_household_job",
		"summary": "Do or plan one real helper job: sort a space, or set a goal with steps and a review day.",
		"evidence": "guide_activity_type",
	},
	"cat1_sunday_water_saver": {
		"mechanic": "water_use_measuring",
		"summary": "Notice, measure and reduce everyday water use and reuse clean rinse water.",
		"evidence": "design_assumption",
	},
	"cat1_sunday_waste_less": {
		"mechanic": "waste_reduction_audit",
		"summary": "Reuse clean, dry throw-away items or paper and test a way to throw less away.",
		"evidence": "design_assumption",
	},
	"cat1_sunday_routine_fixer": {
		"mechanic": "routine_checklist_design",
		"summary": "Design a spot, a picture chart or a tested checklist that makes a household routine easier.",
		"evidence": "design_assumption",
	},
	"cat1_sunday_many_uses": {
		"mechanic": "many_uses_brainstorming",
		"summary": "Brainstorm many uses or improvements for an ordinary thing, choose one and refine it on paper.",
		"evidence": "design_assumption",
	},
}
