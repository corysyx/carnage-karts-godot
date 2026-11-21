class_name Tracks
extends RefCounted
## The courses. Each one is generated from its seed and dressed with its theme.
## To add a track, copy an entry and change the seed and colours.

const THEMES := [
	{
		"name": "Meadow Loop", "blurb": "Rolling hills, picket fences and a big blue lake.",
		"seed": 20261112, "h_off": 0.40, "h_scale": 64.0, "radius": [36.0, 20.0],
		"grass_a": "6cc65c", "grass_b": "a3dc6c", "sand": "f3dc9c", "rock": "9c88ae", "snow": "f6f4ff",
		"water": "62b4f0", "verge": "8fd770", "far": "86cf6c", "asphalt": "5f5a70",
		"hills": ["b49bd6", "8fcf88"], "fence": "e6b47a", "post": "8a5634",
		"trees": {"pine": 0.4, "round": 0.3, "candy": 0.15, "bush": 0.15},
		"pine_col": "3fae5a", "round_col": "5cc860", "candy_col": "ff92c8", "bush_col": "4fb85a", "trunk": "9a6640",
		"sky_top": "5fb0ff", "sky_horizon": "ffe0f3", "fog": "ffe0f3", "ambient": "c9c0ff", "sun": "fff6e8",
	},
	{
		"name": "Candy Canyon", "blurb": "Sugar-pink cliffs and lollipop forests. Sticky.",
		"seed": 777123, "h_off": 0.36, "h_scale": 82.0, "radius": [38.0, 18.0],
		"grass_a": "ffb3d6", "grass_b": "ffd3ea", "sand": "fff0c8", "rock": "c590e8", "snow": "ffffff",
		"water": "8fe8ff", "verge": "ffc6e2", "far": "ffc0de", "asphalt": "6a5478",
		"hills": ["d6a0f0", "ff9fcf"], "fence": "fff0f6", "post": "ff6fa8",
		"trees": {"pine": 0.05, "round": 0.2, "candy": 0.6, "bush": 0.15},
		"pine_col": "7be0b0", "round_col": "ffd36e", "candy_col": "ff6fb0", "bush_col": "a0e8ff", "trunk": "fff4fa",
		"sky_top": "b88cff", "sky_horizon": "ffd6f0", "fog": "ffd6f0", "ambient": "e0c8ff", "sun": "fff0f8",
	},
	{
		"name": "Frosty Peaks", "blurb": "Snowy switchbacks between pine forests. Brrr.",
		"seed": 424242, "h_off": 0.37, "h_scale": 74.0, "radius": [35.0, 21.0],
		"grass_a": "eaf2ff", "grass_b": "d6e6ff", "sand": "cfdcef", "rock": "8f9fc8", "snow": "ffffff",
		"water": "7ccaff", "verge": "e4eeff", "far": "dfe9fb", "asphalt": "545a72",
		"hills": ["c6d4f5", "eef4ff"], "fence": "c99a6a", "post": "6e4630",
		"trees": {"pine": 0.75, "round": 0.0, "candy": 0.0, "bush": 0.25},
		"pine_col": "2f8f6a", "round_col": "5cc860", "candy_col": "ff92c8", "bush_col": "d8eaff", "trunk": "7a5236",
		"sky_top": "7fb4ff", "sky_horizon": "eef4ff", "fog": "eef4ff", "ambient": "c8d8ff", "sun": "ffffff",
	},
	{
		"name": "Sunset Shores", "blurb": "Beaches, palms and lagoons. Mind the water.",
		"seed": 909090, "h_off": 0.46, "h_scale": 58.0, "radius": [37.0, 19.0],
		"grass_a": "8ccf5a", "grass_b": "bddd6a", "sand": "ffd99a", "rock": "d8936a", "snow": "fff2dc",
		"water": "3fc4d8", "verge": "a7dd7a", "far": "9fd468", "asphalt": "655a6e",
		"hills": ["e8a07a", "c68ad0"], "fence": "f0c890", "post": "9a5a34",
		"trees": {"pine": 0.0, "round": 0.55, "candy": 0.2, "bush": 0.25},
		"pine_col": "3fae5a", "round_col": "4cc070", "candy_col": "ff9f6e", "bush_col": "5cc860", "trunk": "b07a48",
		"sky_top": "7a7cff", "sky_horizon": "ffc890", "fog": "ffcca0", "ambient": "ffd2c8", "sun": "ffd2a0",
	},
]

static func col(theme: Dictionary, key: String) -> Color:
	return Color(String(theme[key]))
