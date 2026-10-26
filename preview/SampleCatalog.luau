-- A small catalog for previewing MudTexture on its own (Hendrix's original muds and dusts).
-- Games pass their own catalog with the same fields.
local C = Color3.new
return {
	Muds = {
		river = { Color = C(0.34, 0.40, 0.37), Accent = C(0.73, 0.69, 0.51), Grain = 0.40 },
		redclay = { Color = C(0.54, 0.19, 0.105), Accent = C(0.93, 0.62, 0.34), Grain = 0.25 },
		darkpond = { Color = C(0.045, 0.09, 0.11), Accent = C(0.15, 0.40, 0.36), Grain = 0.58 },
	},
	Dusts = {
		sakura = { Color = C(0.96, 0.48, 0.63), Accent = C(1, 0.85, 0.76), Kind = "swirl", Gloss = 0.72, Reflectivity = 0.16, Clarity = 0.14, Glow = 0 },
		pearl = { Color = C(0.77, 0.84, 0.89), Accent = C(1, 0.91, 0.66), Kind = "speckle", Gloss = 0.97, Reflectivity = 0.94, Clarity = 0.26, Glow = 0 },
		crystal = { Color = C(0.49, 0.82, 0.92), Accent = C(0.85, 0.96, 1), Kind = "veil", Gloss = 1, Reflectivity = 0.70, Clarity = 0.91, Glow = 0 },
		stardust = { Color = C(0.38, 0.33, 0.83), Accent = C(0.54, 0.95, 1), Kind = "vein", Gloss = 0.88, Reflectivity = 0.42, Clarity = 0.44, Glow = 1 },
		obsidian = { Color = C(0.065, 0.055, 0.13), Accent = C(0.46, 0.29, 0.57), Kind = "smoke", Gloss = 0.94, Reflectivity = 0.72, Clarity = 0.22, Glow = 0 },
	},
}
