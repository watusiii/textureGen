-- MudTexture preview: a clean white studio with a grid of polished balls, painted from
-- textures/*.json (the same files the maker edits). Rows = bodies, columns = coats
-- (first column = bare body). Every ball has its own seed.
-- Edit src/Sampler.luau, press Play again to compare.
-- Keys: N = new seeds (repaints in place), R = resolution 64 / 128, L = labels on/off.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local Lighting = game:GetService("Lighting")

local BallAppearance = require(ReplicatedStorage.MudTexture.BallAppearance)
local Library = require(ReplicatedStorage.MudTexture.Library)
local library = Library.load(ReplicatedStorage.MudTexture.Textures)

local MUDS = { "loam", "redclay", "ochre", "kaolin", "pond", "river" }
local COATS = { false, "sakura", "pearl", "obsidian", "crystal", "stardust" }
local GAP = 2.8 -- between columns
local ROW_GAP = 3.6 -- between rows (room for the labels)
local RADIUS = 1
local WHITE = Color3.new(1, 1, 1)

-------------------------------------------------------------------------------
-- White studio: floor, back wall, side walls, soft even light.

local studio = Instance.new("Folder")
studio.Name = "MudTextureStudio"
studio.Parent = workspace

local function wall(size: Vector3, cf: CFrame)
	local p = Instance.new("Part")
	p.Anchored = true
	p.Size = size
	p.CFrame = cf
	p.Color = Color3.fromRGB(245, 245, 243)
	p.Material = Enum.Material.SmoothPlastic
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.Parent = studio
	return p
end
wall(Vector3.new(120, 1, 120), CFrame.new(0, -0.45, 0)) -- floor (just above the baseplate)
wall(Vector3.new(120, 60, 1), CFrame.new(0, 30, -14)) -- back
wall(Vector3.new(1, 60, 120), CFrame.new(-30, 30, 0)) -- left
wall(Vector3.new(1, 60, 120), CFrame.new(30, 30, 0)) -- right

Lighting.ClockTime = 13
Lighting.Brightness = 2.2
Lighting.Ambient = Color3.fromRGB(150, 150, 150)
Lighting.OutdoorAmbient = Color3.fromRGB(190, 190, 190)
Lighting.EnvironmentDiffuseScale = 1
Lighting.EnvironmentSpecularScale = 1
Lighting.GlobalShadows = true
for _, fx in Lighting:GetChildren() do
	if fx:IsA("Atmosphere") or fx:IsA("BloomEffect") or fx:IsA("ColorCorrectionEffect") then
		fx:Destroy()
	end
end
local key = Instance.new("PointLight")
key.Brightness = 1.2
key.Range = 60
key.Color = WHITE
local keyPart = wall(Vector3.new(1, 1, 1), CFrame.new(-8, 14, 12))
keyPart.Transparency = 1
keyPart.CanCollide = false
key.Parent = keyPart

-- Keep the template's spawn pad and your character out of the shot.
local Players = game:GetService("Players")
for _, d in workspace:GetDescendants() do
	if d:IsA("SpawnLocation") then
		d.LocalTransparencyModifier = 1
		for _, decal in d:GetChildren() do
			if decal:IsA("Decal") then
				decal.Transparency = 1
			end
		end
	end
end
local function parkCharacter(char: Model)
	task.wait()
	char:PivotTo(CFrame.new(0, 3, 24))
end
Players.LocalPlayer.CharacterAdded:Connect(parkCharacter)
if Players.LocalPlayer.Character then
	task.spawn(parkCharacter, Players.LocalPlayer.Character)
end

-------------------------------------------------------------------------------
-- Grid of balls.

local resolution = 64
local showLabels = true
local cells = {} -- { handle, mud, coat, label, cf }

local function newSeed(): number
	return math.random(1, 2 ^ 31 - 2)
end

local function recipe(cell, seed: number)
	cell.revision = (cell.revision or 0) + 1
	return {
		id = "preview-" .. cell.mud .. "-" .. tostring(cell.coat),
		seed = seed,
		body = cell.mud,
		corePolish = 1,
		coats = cell.coat and { { tex = cell.coat, amount = 0.7, polish = 1 } } or {},
		revision = cell.revision,
	}
end

local function paint(cell)
	cell.seed = newSeed()
	cell.handle:setBall(recipe(cell, cell.seed))
	cell.label.Text = string.format("%s · %s\nseed %d", cell.mud, cell.coat or "bare", cell.seed)
end

local function makeLabel(at: Vector3): TextLabel
	local anchor = wall(Vector3.new(0.2, 0.2, 0.2), CFrame.new(at))
	anchor.Transparency = 1
	anchor.CanCollide = false
	local bb = Instance.new("BillboardGui")
	bb.Size = UDim2.new(0, 120, 0, 30)
	bb.Parent = anchor
	local t = Instance.new("TextLabel")
	t.Size = UDim2.fromScale(1, 1)
	t.BackgroundTransparency = 1
	t.TextColor3 = Color3.fromRGB(110, 110, 110)
	t.TextScaled = true
	t.Font = Enum.Font.Gotham
	t.Parent = bb
	return t
end

local function build()
	for _, cell in cells do
		cell.handle:destroy()
	end
	local old = cells
	cells = {}
	for r, mud in MUDS do
		for c, coat in COATS do
			local x = (c - (#COATS + 1) / 2) * GAP
			local z = (r - 1) * ROW_GAP - 5
			local cf = CFrame.new(x, RADIUS, z)
			local prev = old[#cells + 1]
			local cell = {
				mud = mud,
				coat = coat,
				cf = cf,
				label = prev and prev.label or makeLabel(Vector3.new(x, RADIUS * 2 + 0.45, z)),
				handle = BallAppearance.new(studio, {
					library = library,
					editable = true,
					resolution = resolution,
					radius = RADIUS,
					cframe = cf,
				}),
			}
			table.insert(cells, cell)
			paint(cell)
			cell.label.Visible = showLabels
		end
	end
	print("[MudTexture preview]", #cells, "balls at", resolution, "px")
end
build()

-------------------------------------------------------------------------------
-- Camera: front, a little above, the whole grid in view.

local camera = workspace.CurrentCamera
RunService:BindToRenderStep("MudTexturePreview", Enum.RenderPriority.Camera.Value + 1, function()
	camera.CameraType = Enum.CameraType.Scriptable
	camera.CFrame = CFrame.lookAt(Vector3.new(0, 17, 21), Vector3.new(0, 0.8, 2))
	camera.FieldOfView = 40
end)

local start = os.clock()
RunService.Heartbeat:Connect(function()
	local yaw = (os.clock() - start) * 0.25
	for _, cell in cells do
		cell.handle:setRotation(yaw)
	end
end)

UserInputService.InputBegan:Connect(function(input, processed)
	if processed then
		return
	end
	if input.KeyCode == Enum.KeyCode.N then
		for _, cell in cells do
			paint(cell)
		end
	elseif input.KeyCode == Enum.KeyCode.R then
		resolution = resolution == 64 and 128 or 64
		build()
	elseif input.KeyCode == Enum.KeyCode.L then
		showLabels = not showLabels
		for _, cell in cells do
			cell.label.Visible = showLabels
		end
	end
end)
