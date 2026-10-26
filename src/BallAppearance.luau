--!nonstrict
-- MudTexture · BallAppearance
-- Client-side: builds a sphere MeshPart and paints its PBR maps from a recipe using Sampler.
-- Persist/replicate the ball recipe, never these images.
-- Originally by Hendrix (texture-system-as-is, Oct 24 2026). Changes: paints from texture
-- definitions (options.library, a Library) through Sampler.sampleStack, the port of the maker's core.
-- Official API references checked 2026-10-24:
-- https://create.roblox.com/docs/reference/engine/classes/AssetService#CreateSurfaceAppearanceAsync
-- https://create.roblox.com/docs/reference/engine/classes/EditableImage#WritePixelsBuffer
-- https://create.roblox.com/docs/reference/engine/classes/EditableMesh
local AssetService = game:GetService("AssetService")
local RunService = game:GetService("RunService")
local Sampler = require(script.Parent.Sampler)

local BallAppearance = {}
local Handle = {}
Handle.__index = Handle
local TAU = 2 * math.pi
-- All handles share one upload allowance. Multiple displayed balls cannot
-- upload their separate PBR maps in the same frame. The counter allocates no
-- tables or buffers per frame, and idle handles never enter the upload path.
local uploadFrame, lastUploadFrame = 0, -1
RunService.Heartbeat:Connect(function() uploadFrame += 1 end)
local function materialKey(ball)
	-- MudballModel increments revision only for actual finish/layer changes.
	-- Controller heat and idle timestamps do not require a new material map.
	return tostring(ball.id) .. ":" .. tostring(ball.seed) .. ":" .. tostring(ball.mud) .. ":" .. tostring(ball.revision)
end
local function point(u, v)
	local phi, theta = u * TAU, v * math.pi
	return Vector3.new(math.sin(theta) * math.cos(phi), math.cos(theta), math.sin(theta) * math.sin(phi))
end
local function byte(v) return math.floor(math.clamp(v, 0, 1) * 255 + 0.5) end
local function rgba(pixels, offset, r, g, b)
	buffer.writeu8(pixels, offset, byte(r))
	buffer.writeu8(pixels, offset + 1, byte(g))
	buffer.writeu8(pixels, offset + 2, byte(b))
	buffer.writeu8(pixels, offset + 3, 255)
end
local function safeDestroy(object) if object then object:Destroy() end end
-- Material at (u, v) in the shape the painter below expects.
local function sampleAt(stack, seed, u, v)
	local m = Sampler.sampleStack(stack, seed, u, v)
	return { color = Color3.new(m.r, m.g, m.b), roughness = m.roughness, metalness = m.metalness, glow = m.glow }
end

local function makeSphere()
	local mesh = AssetService:CreateEditableMesh()
	assert(mesh, "EditableMesh memory budget unavailable")
	local success, result = pcall(function()
		local rows, columns = 20, 32
		local vertices, normals, uvs = {}, {}, {}
		for y = 0, rows do
			vertices[y], normals[y], uvs[y] = {}, {}, {}
			for x = 0, columns do
				local direction = point(x / columns, y / rows)
				vertices[y][x] = mesh:AddVertex(direction)
				normals[y][x] = mesh:AddNormal(direction)
				uvs[y][x] = mesh:AddUV(Vector2.new(x / columns, y / rows))
			end
		end
		local function face(y1, x1, y2, x2, y3, x3)
			local id = mesh:AddTriangle(vertices[y1][x1], vertices[y2][x2], vertices[y3][x3])
			mesh:SetFaceNormals(id, {normals[y1][x1], normals[y2][x2], normals[y3][x3]})
			mesh:SetFaceUVs(id, {uvs[y1][x1], uvs[y2][x2], uvs[y3][x3]})
		end
		for y = 0, rows - 1 do
			for x = 0, columns - 1 do
				-- Outward winding; seam vertices have distinct u=0/u=1 coordinates.
				if y > 0 then face(y, x, y, x + 1, y + 1, x + 1) end
				if y < rows - 1 then face(y, x, y + 1, x + 1, y + 1, x) end
			end
		end
		local part = AssetService:CreateMeshPartAsync(Content.fromObject(mesh), {
			CollisionFidelity = Enum.CollisionFidelity.Box,
			RenderFidelity = Enum.RenderFidelity.Automatic,
		})
		part.DoubleSided = true
		return part
	end)
	if not success then mesh:Destroy(); error(result) end
	return mesh, result
end

function Handle:_fallback()
	local root = Instance.new("Part")
	root.Name, root.Shape = "Dorodango", Enum.PartType.Ball
	root.Anchored, root.CanCollide, root.CanTouch, root.CanQuery = true, false, false, false
	root.Size, root.Material = Vector3.one * 2, Enum.Material.SmoothPlastic
	root.Parent = self.model
	self.part = root
	self.patches = {}
	-- Small colored shell samples provide an honest low-detail procedural fallback.
	-- These are not PBR textures, transparency maps, or an emissive shader.
	for y = 1, 7 do
		for x = 0, 15 do
			local u, v = x / 16, y / 8
			local patch = Instance.new("Part")
			patch.Name, patch.Shape = "Pigment", Enum.PartType.Ball
			patch.Anchored, patch.CanCollide, patch.CanTouch, patch.CanQuery = true, false, false, false
			patch.Size, patch.Material = Vector3.new(0.28, 0.28, 0.012), Enum.Material.SmoothPlastic
			patch.Parent = self.model
			local normal = point(u, v)
			table.insert(self.patches, {part = patch, u = u, v = v, normal = normal, offset = normal * 0.994})
		end
	end
	self:_position()
end

function Handle:_position()
	if self.destroyed then return end
	local transform = self.cframe * CFrame.Angles(0, self.yaw, 0)
	self.part.CFrame, self.part.Size = transform, Vector3.one * (2 * self.radius)
	for _, patch in self.patches do
		local position = patch.offset * self.radius
		patch.part.CFrame = transform * CFrame.lookAt(position, position + patch.normal)
		patch.part.Size = Vector3.new(0.28, 0.28, 0.012) * self.radius
	end
end

function Handle:_initializeEditable()
	local mesh, meshPart, images, appearance
	local ok, problem = pcall(function()
		mesh, meshPart = makeSphere()
		images = {}
		for _, key in {"color", "roughness", "metalness", "emissive"} do
			images[key] = AssetService:CreateEditableImage({Size = Vector2.new(self.resolution, self.resolution)})
			assert(images[key], "EditableImage memory budget unavailable")
		end
		local success, created = pcall(function()
			return AssetService:CreateSurfaceAppearanceAsync({
				ColorMap = Content.fromObject(images.color),
				RoughnessMap = Content.fromObject(images.roughness),
				MetalnessMap = Content.fromObject(images.metalness),
				EmissiveMask = Content.fromObject(images.emissive),
			})
		end)
		if success then
			appearance = created
			appearance.EmissiveStrength = 2
			appearance.Parent = meshPart
		else
			meshPart.TextureContent = Content.fromObject(images.color)
			for _, key in {"roughness", "metalness", "emissive"} do safeDestroy(images[key]); images[key] = nil end
		end
		if self.destroyed then error("Appearance was disposed") end
		self.part:Destroy()
		for _, patch in self.patches do patch.part:Destroy() end
		self.patches = {}
		self.part, self.mesh, self.images, self.appearance = meshPart, mesh, images, appearance
		meshPart.Name, meshPart.Anchored = "Dorodango", true
		meshPart.CanCollide, meshPart.CanTouch, meshPart.CanQuery = false, false, false
		meshPart.Color, meshPart.Material = Color3.new(1, 1, 1), Enum.Material.SmoothPlastic
		meshPart.Parent = self.model
		self.mode = if appearance then "PBR" else "texture"
		self.model:SetAttribute("AppearanceMode", self.mode)
		self.model:SetAttribute("RenderMode", self.mode)
		self:_position()
		self.requestedKey = nil -- Newly allocated maps must be populated once.
		if self.ball then self:setBall(self.ball) end
	end)
	if not ok then
		if images then for _, image in images do safeDestroy(image) end end
		safeDestroy(appearance); safeDestroy(meshPart); safeDestroy(mesh)
		self.reason = tostring(problem)
		if not self.destroyed then self.model:SetAttribute("AppearanceFallbackReason", self.reason) end
	end
	if self.onModeChanged and not self.destroyed then self.onModeChanged(self.mode) end
end

function Handle:_paint(ball)
	if self.destroyed then return end
	local stack = self.library:stackFor(ball)
	local center = sampleAt(stack, ball.seed, 0.5, 0.5)
	if not self.images then
		self.part.Color, self.part.Reflectance = center.color, math.clamp((1 - center.roughness) * 0.22, 0, 0.22)
		for _, patch in self.patches do
			local sample = sampleAt(stack, ball.seed, patch.u, patch.v)
			patch.part.Color = sample.color
			patch.part.Material = if sample.glow > 0.3 then Enum.Material.Neon else Enum.Material.SmoothPlastic
		end
		return
	end
	local size = self.resolution
	local pixels = {color = buffer.create(size * size * 4)}
	for _, key in {"roughness", "metalness", "emissive"} do
		if self.images[key] then pixels[key] = buffer.create(size * size * 4) end
	end
	for y = 0, size - 1 do
		for x = 0, size - 1 do
			local sample = sampleAt(stack, ball.seed, x / (size - 1), y / (size - 1))
			local offset = (y * size + x) * 4
			rgba(pixels.color, offset, sample.color.R, sample.color.G, sample.color.B)
			if pixels.roughness then rgba(pixels.roughness, offset, sample.roughness, sample.roughness, sample.roughness) end
			if pixels.metalness then rgba(pixels.metalness, offset, sample.metalness, sample.metalness, sample.metalness) end
			if pixels.emissive then rgba(pixels.emissive, offset, sample.glow, sample.glow, sample.glow) end
		end
		if y % 12 == 11 then task.wait(); if self.destroyed then return end end
	end
	for key, pixelsBuffer in pixels do
		while lastUploadFrame == uploadFrame and not self.destroyed do RunService.Heartbeat:Wait() end
		if self.destroyed then return end
		lastUploadFrame = uploadFrame
		self.images[key]:WritePixelsBuffer(Vector2.zero, Vector2.new(size, size), pixelsBuffer)
		self.textureUploadCount = (self.textureUploadCount or 0) + 1
		self.model:SetAttribute("TextureUploadCount", self.textureUploadCount)
	end
	-- The core stays opaque. Crystal clarity in MudballModel reveals underlying coats.
end

function Handle:setBall(ball)
	if self.destroyed or not ball then return end
	self.ball = ball
	local key = materialKey(ball)
	if self.requestedKey == key then return end
	self.requestedKey = key
	self.pending = {ball = ball, key = key}
	self.model:SetAttribute("BallId", ball.id)
	self.model:SetAttribute("BallSeed", ball.seed)
	self.model:SetAttribute("VisualRevision", ball.revision)
	if self.painting then return end
	self.painting = true
	task.spawn(function()
		while self.pending and not self.destroyed do
			local nextPaint = self.pending; self.pending = nil
			local ok, problem = pcall(function() self:_paint(nextPaint.ball) end)
			if ok and not self.destroyed then
				self.paintCount = (self.paintCount or 0) + 1
				self.model:SetAttribute("PaintCount", self.paintCount)
			end
			if not ok then
				self.reason = tostring(problem)
				if self.images and not self.destroyed then
					self.part:Destroy()
					for _, image in self.images do safeDestroy(image) end
					self.images = nil
					safeDestroy(self.mesh); self.mesh = nil
					self.mode = "geometry"
					self.model:SetAttribute("AppearanceMode", self.mode)
					self.model:SetAttribute("RenderMode", self.mode)
					self.model:SetAttribute("AppearanceFallbackReason", self.reason)
					self:_fallback()
					self.requestedKey = nil
					self:setBall(self.ball)
					if self.onModeChanged then self.onModeChanged(self.mode) end
				end
			end
		end
		self.painting = false
	end)
end

function Handle:setRotation(yaw) self.yaw = yaw; self:_position() end
function Handle:setCFrame(cframe) self.cframe = cframe; self:_position() end
function Handle:destroy()
	if self.destroyed then return end
	self.destroyed, self.pending = true, nil
	self.model:Destroy()
	if self.images then for _, image in self.images do image:Destroy() end end
	safeDestroy(self.mesh)
end

function BallAppearance.new(parent, options)
	options = options or {}
	local self = setmetatable({
		model = Instance.new("Model"), mode = "geometry", patches = {},
		radius = options.radius or 1, cframe = options.cframe or CFrame.new(), yaw = 0,
		resolution = math.clamp(options.resolution or 96, 32, 128),
		onModeChanged = options.onModeChanged,
		library = assert(options.library, "BallAppearance.new needs options.library (MudTexture Library)"),
	}, Handle)
	self.model.Name, self.model.Parent = "ProceduralMudball", parent
	self.model:SetAttribute("AppearanceMode", self.mode)
	self.model:SetAttribute("RenderMode", self.mode)
	self.model:SetAttribute("TextureResolution", self.resolution)
	self.model:SetAttribute("EditableRequested", options.editable ~= false)
	self:_fallback()
	if options.editable ~= false then task.spawn(function() self:_initializeEditable() end) end
	return self
end

return BallAppearance


