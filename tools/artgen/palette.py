"""BulletHwaven master palette.

Ramps run dark -> light. Rules (see docs/game-design.md, section 11c):
- Environment and resting aliens use warm, desaturated desert ramps.
- Bioluminescence (GLOW) is the only cold saturated colour: aliens and their projectiles.
- Player projectiles and fire are always warm (FIRE).
"""

OUTLINE = "#1c1416"
SHADOW = "#2f2a3d"  # cool blue-violet shadow (orange/teal look)

SAND = ["#6e4a36", "#8e6145", "#ad7d55", "#c99c6b", "#e0bd8c", "#f0d9b0"]
SALT = ["#8f8a80", "#b3ada0", "#d2ccbd", "#e8e3d6", "#f7f4ec"]
CANYON = ["#3d2420", "#5e342a", "#7e4634", "#a05c40", "#bf7a55", "#d89a72"]
ROCK = ["#2e2528", "#4a3c3a", "#665249", "#86705f", "#a69079", "#c4b096"]
BONE = ["#5c5047", "#8a7d6c", "#b8ab94", "#ddd2bb", "#f2ead8"]
OBSIDIAN = ["#120e10", "#211b1e", "#352c2d", "#4d4240", "#8a7f74", "#e8dcc4"]

STEEL = ["#1f1e24", "#34343c", "#4c4e58", "#6c707a", "#959aa3", "#c3c7cc"]
RUST = ["#3b1f17", "#5e2f1e", "#843f24", "#a85a30", "#c97c45", "#e0a066"]
TYRE = ["#141113", "#221d1f", "#332c2d", "#4a4142"]
KHAKI = ["#2f2e1d", "#4a4930", "#6a6845", "#8c8a5e", "#ada97a"]
LEATHER = ["#2a1a14", "#47291c", "#6b3d26", "#8f5534"]
BRASS = ["#4a3414", "#7a5a24", "#a8823a", "#d2ad5c"]
BURLAP = ["#3f3122", "#5f4a32", "#82694a", "#a48a63", "#bea57c"]
HAZARD = "#c9a227"

CHITIN = ["#3a2a24", "#5a4234", "#7d5d45", "#a07c5a", "#c4a076", "#dcc099"]
GLOW = ["#0f3a40", "#16646a", "#1fa3a3", "#4fe0d4", "#a8fff2", "#effffc"]
GLASS = ["#7fa9ae", "#a9cfd0", "#cfe8e6", "#eef8f6"]
CRYSTAL = ["#2c4257", "#3d5a73", "#6b93b0", "#a7c9dc", "#e3f2f7"]
VOLATILE = ["#5a1e0c", "#a8401a", "#e8772a", "#ffc061", "#fff0b8"]
SPORE = ["#2a2433", "#463a52", "#665173", "#8a6d8f", "#ad91a8"]

FIRE = ["#3a1a14", "#7a2a14", "#c4481c", "#ef7d22", "#ffb53d", "#ffe48a", "#fffbe0"]
SMOKE = ["#2a2426", "#433a3a", "#605453", "#807272", "#9e9088"]

# Player paint jobs, in SimVehicle.color_index order (0..7). Eight clearly distinct paints
# (design doc 11c): never cyan/teal (GLOW is the aliens' colour), never yellow/orange (FIRE is
# the player tracers'), and each must read on sand by day and on dark ground at night.
# Step 3 is the "paint" colour used for name tags and UI swatches.
PLAYERS = {
    "red": ["#4a0f12", "#7d1a1d", "#b02a28", "#d9473a", "#f07560"],
    "magenta": ["#3c1238", "#6a1f60", "#9c3089", "#c84aae", "#e57fcf"],
    "blue": ["#121a4f", "#1d2d80", "#2a46b4", "#3f6ae4", "#7d9ff7"],
    "green": ["#10301a", "#1a5226", "#287a34", "#3fa449", "#7fd07a"],
    "white": ["#4e4b4a", "#85817d", "#b7b3ab", "#e4e1da", "#fbfaf5"],
    "purple": ["#26113f", "#401c6c", "#5f2b9e", "#8549d0", "#b283ee"],
    "lime": ["#283809", "#486212", "#6f941c", "#9fcb2c", "#d0ec72"],
    "black": ["#08080a", "#121114", "#1b1a1e", "#27262c", "#45434d"],
}

UI_TEXT = "#f0d9b0"
UI_PLATE = ["#2a2224", "#3d3233", "#56473f", "#6f5c4d"]

RAMPS = {
    "SAND": SAND, "SALT": SALT, "CANYON": CANYON, "ROCK": ROCK, "BONE": BONE,
    "STEEL": STEEL, "RUST": RUST, "TYRE": TYRE, "KHAKI": KHAKI, "BRASS": BRASS, "BURLAP": BURLAP,
    "CHITIN": CHITIN, "GLOW": GLOW, "CRYSTAL": CRYSTAL, "VOLATILE": VOLATILE,
    "FIRE": FIRE, "SMOKE": SMOKE,
    **{f"PLAYER {k.upper()}": v for k, v in PLAYERS.items()},
}
