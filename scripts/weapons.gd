extends RefCounted

enum Type { GUN, SWORD, LAUNCHER }

const BALLS := [
	{"tex": "res://weapons/redball.png", "region": Rect2(28, 37, 7, 6), "color": Color(1.0, 0.2, 0.2)},
	{"tex": "res://weapons/blueball.png", "region": Rect2(39, 34, 7, 6), "color": Color(0.25, 0.45, 1.0)},
	{"tex": "res://weapons/orangeball.png", "region": Rect2(26, 34, 7, 6), "color": Color(1.0, 0.6, 0.15)},
	{"tex": "res://weapons/greenball.png", "region": Rect2(30, 35, 7, 6), "color": Color(0.3, 0.9, 0.3)},
	{"tex": "res://weapons/pinkball.png", "region": Rect2(38, 36, 7, 6), "color": Color(1.0, 0.45, 0.8)},
]

# indexed by Type. ai_super is the distance window where bots use their super
const DATA := [
	{
		"name": "Blaster", "blurb": "FOUR-ROUND BURSTS FROM LONG RANGE.", "super": "BULLET STORM, A STREAM OF PIERCING SHOTS",
		"tex": "res://weapons/gun.png", "region": Rect2(19, 35, 59, 26),
		"offset": Vector2(-29.5, -13), "sprite_rot": 0.0, "sprite_pos": Vector2(20, 0), "muzzle": 50.0,
		"max_hp": 4000.0, "speed": 195.0, "damage": 115.0, "reach": 480.0, "proj_speed": 800.0,
		"reload": 1.25, "cooldown": 0.4, "super_cost": 2400.0, "super_damage": 210.0,
		"ai_range": 390.0, "ai_min": 230.0, "ai_fire": 460.0, "ai_super": Vector2(0, 470),
	},
	{
		"name": "Blade", "blurb": "THE TOUGHEST FIGHTER. WIDE SWINGS UP CLOSE.", "super": "WHIRLWIND DASH THROUGH ENEMIES",
		"tex": "res://weapons/sword.png", "region": Rect2(24, 15, 42, 42),
		"offset": Vector2(-3, -39), "sprite_rot": PI / 4.0 - 0.6, "sprite_pos": Vector2(10, -7),
		"max_hp": 11200.0, "speed": 250.0, "damage": 480.0, "reach": 92.0, "arc": 130.0,
		"reload": 1.0, "cooldown": 0.38, "super_cost": 2400.0, "super_damage": 1200.0,
		"ai_range": 62.0, "ai_min": 0.0, "ai_fire": 104.0, "ai_super": Vector2(90, 300),
	},
	{
		"name": "Ball Launcher", "blurb": "TWO HEAVY BALLS A SHOT THAT BOUNCE OFF WALLS.", "super": "RAINBOW BURST OF FIVE EXTRA-BOUNCY BALLS",
		"tex": "res://weapons/ball_launcher.png", "region": Rect2(39, 22, 28, 32),
		"offset": Vector2(-6.5, -32), "sprite_rot": PI / 2.0, "sprite_pos": Vector2(8, 0), "muzzle": 42.0,
		"max_hp": 4600.0, "speed": 195.0, "damage": 325.0, "reach": 600.0, "proj_speed": 540.0,
		"reload": 1.5, "cooldown": 0.45, "super_cost": 2600.0, "super_damage": 560.0,
		"ai_range": 400.0, "ai_min": 200.0, "ai_fire": 500.0, "ai_super": Vector2(0, 430),
	},
]
