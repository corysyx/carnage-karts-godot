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
		"name": "Sunset Shores", "blurb": "A long forest circuit with hairpins and a hidden lake.",
		"seed": 909090, "h_off": 0.46, "h_scale": 58.0, "radius": [37.0, 19.0],
		# Hand-traced layout (from the user's track editor plan), image pixels -> metres.
		"layout": {
			"scale": 0.28,
			"points": [Vector2(1075, 833), Vector2(1096, 708), Vector2(1097, 603), Vector2(1080, 533), Vector2(1045, 483), Vector2(973, 420), Vector2(885, 363), Vector2(817, 337), Vector2(758, 325), Vector2(662, 314), Vector2(527, 316), Vector2(452, 333), Vector2(428, 356), Vector2(426, 382), Vector2(440, 410), Vector2(470, 432), Vector2(513, 446), Vector2(552, 446), Vector2(584, 447), Vector2(610, 458), Vector2(621, 484), Vector2(610, 510), Vector2(584, 521), Vector2(552, 520), Vector2(495, 518), Vector2(380, 536), Vector2(300, 590), Vector2(270, 632), Vector2(262, 664), Vector2(274, 690), Vector2(302, 702), Vector2(338, 697), Vector2(376, 682), Vector2(481, 662), Vector2(620, 672), Vector2(720, 703), Vector2(755, 752), Vector2(753, 833), Vector2(720, 923), Vector2(655, 1008), Vector2(568, 1098), Vector2(483, 1192), Vector2(426, 1278), Vector2(399, 1368), Vector2(407, 1471), Vector2(470, 1549), Vector2(558, 1574), Vector2(612, 1556), Vector2(640, 1524), Vector2(644, 1492), Vector2(626, 1466), Vector2(593, 1452), Vector2(537, 1430), Vector2(497, 1397), Vector2(478, 1341), Vector2(484, 1280), Vector2(523, 1237), Vector2(584, 1207), Vector2(660, 1186), Vector2(752, 1161), Vector2(873, 1102), Vector2(990, 1021), Vector2(1048, 941)],
			"profile": [Vector2(0.0000, 11.94), Vector2(0.0312, 10.02), Vector2(0.0567, 13.62), Vector2(0.0851, 16.74), Vector2(0.1087, 17.22), Vector2(0.1295, 14.58), Vector2(0.1512, 12.42), Vector2(0.1824, 14.10), Vector2(0.2146, 11.70), Vector2(0.2363, 8.82), Vector2(0.2505, 9.54), Vector2(0.2713, 12.66), Vector2(0.2883, 11.94), Vector2(0.3072, 11.22), Vector2(0.3355, 7.14), Vector2(0.3620, 4.50), Vector2(0.3828, 8.10), Vector2(0.4083, 10.50), Vector2(0.4348, 13.86), Vector2(0.4650, 16.98), Vector2(0.4868, 14.58), Vector2(0.5198, 10.50), Vector2(0.5406, 11.46), Vector2(0.5681, 13.14), Vector2(0.5955, 14.58), Vector2(0.6229, 16.98), Vector2(0.6456, 19.62), Vector2(0.6664, 19.38), Vector2(0.6900, 19.14), Vector2(0.7136, 21.06), Vector2(0.7344, 22.02), Vector2(0.7609, 18.90), Vector2(0.7892, 18.42), Vector2(0.8129, 19.62), Vector2(0.8270, 17.22), Vector2(0.8507, 14.82), Vector2(0.8743, 11.22), Vector2(0.8932, 8.82), Vector2(0.9234, 6.90), Vector2(0.9565, 9.54), Vector2(0.9783, 11.94), Vector2(1.0000, 11.94)],
			"forest": [Vector2(250, 165), Vector2(560, 140), Vector2(1000, 150), Vector2(1160, 250), Vector2(1255, 360), Vector2(1275, 700), Vector2(1270, 1000), Vector2(1240, 1240), Vector2(1100, 1540), Vector2(700, 1545), Vector2(230, 1545), Vector2(220, 1200), Vector2(330, 960), Vector2(100, 860), Vector2(90, 450), Vector2(150, 360), Vector2(250, 330)],
			"lake": [Vector2(885, 1352), Vector2(125, 95)],
			"trees": 3200,
		},

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
