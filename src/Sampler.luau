--!strict
-- MudTexture · Sampler (Roblox reader)
-- Line-for-line port of maker/core/texcore.js. Change both together, then run tests/parity.sh.
-- Texture definition (JSON from textures/) + seed + polish -> surface material on a sphere.
-- Pure: no instances, no services.
--
-- stack = { { def = <definition table>, amount = 0..1, polish = 0..1 } }  -- body first, then coats

local Sampler = {}

local M = 4294967296 -- 2^32
local TAU = 2 * math.pi

export type Material = { r: number, g: number, b: number, roughness: number, metalness: number, glow: number }

local function mod(x: number): number
	return x % M -- Luau % is floored: always 0..M-1
end
local function mul32(a: number, b: number): number
	local low = bit32.band(a, 65535) * b
	local high = bit32.band(bit32.rshift(a, 16) * b, 65535) * 65536
	return (low + high) % M
end
local function hash(n: number): number
	n = mod(n)
	n = bit32.bxor(n, bit32.rshift(n, 16))
	n = mul32(n, 73244475)
	n = bit32.bxor(n, bit32.rshift(n, 16))
	n = mul32(n, 73244475)
	return bit32.bxor(n, bit32.rshift(n, 16))
end
local function h3(x: number, y: number, z: number, seed: number): number
	local v = bit32.bxor(mul32(mod(x), 73856093), mul32(mod(y), 19349663), mul32(mod(z), 83492791), seed)
	return hash(v) / (M - 1)
end
local function mix(a: number, b: number, t: number): number
	return a + (b - a) * t
end
local function smooth(t: number): number
	return t * t * (3 - 2 * t)
end
local function clamp(x: number, lo: number, hi: number): number
	if x < lo then
		return lo
	elseif x > hi then
		return hi
	end
	return x
end
local function smoothstep(a: number, b: number, x: number): number
	if b <= a then
		return if x >= a then 1 else 0
	end
	return smooth(clamp((x - a) / (b - a), 0, 1))
end

local function noise(x: number, y: number, z: number, seed: number): number
	local ix, iy, iz = math.floor(x), math.floor(y), math.floor(z)
	local a, b, c = smooth(x - ix), smooth(y - iy), smooth(z - iz)
	return mix(
		mix(mix(h3(ix, iy, iz, seed), h3(ix + 1, iy, iz, seed), a), mix(h3(ix, iy + 1, iz, seed), h3(ix + 1, iy + 1, iz, seed), a), b),
		mix(mix(h3(ix, iy, iz + 1, seed), h3(ix + 1, iy, iz + 1, seed), a), mix(h3(ix, iy + 1, iz + 1, seed), h3(ix + 1, iy + 1, iz + 1, seed), a), b),
		c
	)
end
local function fbm(x: number, y: number, z: number, seed: number, octaves: number): number
	local sum, amp, norm, f = 0, 1, 0, 1
	for o = 0, octaves - 1 do
		sum += noise(x * f, y * f, z * f, mod(seed + o * 1013)) * amp
		norm += amp
		amp *= 0.5
		f *= 2
	end
	return sum / norm
end
local function ridged(x: number, y: number, z: number, seed: number, octaves: number): number
	local sum, amp, f, norm = 0, 0.5, 1, 0
	for o = 0, octaves - 1 do
		local n = 1 - math.abs(noise(x * f, y * f, z * f, mod(seed + o * 131)) * 2 - 1)
		sum += n * n * amp
		norm += amp
		amp *= 0.5
		f *= 2
	end
	return sum / norm
end
local function turb(x: number, y: number, z: number, seed: number, octaves: number): number
	local sum, amp, f, norm = 0, 0.5, 1, 0
	for o = 0, octaves - 1 do
		sum += math.abs(noise(x * f, y * f, z * f, mod(seed + o * 977)) * 2 - 1) * amp
		norm += amp
		amp *= 0.5
		f *= 2
	end
	return sum / norm
end
-- Cellular noise: nearest (f1), second nearest (f2), cell id 0..1.
local function worley(x: number, y: number, z: number, seed: number): (number, number, number)
	local ix, iy, iz = math.floor(x), math.floor(y), math.floor(z)
	local f1, f2, id = 9, 9, 0
	for dz = -1, 1 do
		for dy = -1, 1 do
			for dx = -1, 1 do
				local cx, cy, cz = ix + dx, iy + dy, iz + dz
				local h = hash(bit32.bxor(mul32(mod(cx), 73856093), mul32(mod(cy), 19349663), mul32(mod(cz), 83492791), seed))
				local px = cx + bit32.band(h, 1023) / 1023
				local py = cy + bit32.band(bit32.rshift(h, 10), 1023) / 1023
				local pz = cz + bit32.band(bit32.rshift(h, 20), 1023) / 1023
				local ddx, ddy, ddz = px - x, py - y, pz - z
				local d = math.sqrt(ddx * ddx + ddy * ddy + ddz * ddz)
				if d < f1 then
					f2 = f1
					f1 = d
					id = h / (M - 1)
				elseif d < f2 then
					f2 = d
				end
			end
		end
	end
	return f1, f2, id
end
-- Bend a point with noise (domain warp).
local function warp(x: number, y: number, z: number, amount: number, s: number, seed: number): (number, number, number)
	local a = noise(x * s + 11, y * s + 3, z * s + 7, seed) - 0.5
	local b = noise(x * s + 23, y * s + 17, z * s + 5, mod(seed + 1)) - 0.5
	local c = noise(x * s + 2, y * s + 29, z * s + 13, mod(seed + 2)) - 0.5
	return x + a * amount, y + b * amount, z + c * amount
end
Sampler.noise = noise
Sampler.hash = hash
Sampler.worley = worley

local hexCache: { [string]: { number } } = {}
local function hex(s: any): { number }
	local key = if typeof(s) == "string" then s else "#000000"
	local cached = hexCache[key]
	if cached then
		return cached
	end
	local h = string.gsub(key, "#", "")
	local c = {
		(tonumber(string.sub(h, 1, 2), 16) or 0) / 255,
		(tonumber(string.sub(h, 3, 4), 16) or 0) / 255,
		(tonumber(string.sub(h, 5, 6), 16) or 0) / 255,
	}
	hexCache[key] = c
	return c
end
local function num(v: any, d: number): number
	return if typeof(v) == "number" then v else d
end

local function mixc(a: { number }, b: { number }, t: number): { number }
	return { mix(a[1], b[1], t), mix(a[2], b[2], t), mix(a[3], b[3], t) }
end
local function hexOr(v: any, fallback: string): { number }
	return hex(if typeof(v) == "string" then v else fallback)
end

-- Generator layers: return color {r,g,b}, metal?, glow? at point (x, y, z).
type GenResult = { c: { number }, metal: number?, glow: number? }
local GENERATORS: { [string]: (any, number, number, number, number) -> GenResult } = {
	earth = function(layer, x, y, z, ls)
		local s = num(layer.scale, 2.5)
		local n = fbm(x * s, y * s, z * s, ls, math.floor(num(layer.detail, 4)))
		local m = fbm(x * s * 3 + 9, y * s * 3, z * s * 3, mod(ls + 1), 3)
		local dark, mid, light = hexOr(layer.color, "#2b1d14"), hexOr(layer.color2, "#6b4a32"), hexOr(layer.color3, "#a8845c")
		local tt = smoothstep(0.25, 0.75, n) * 2
		local c = if tt < 1 then mixc(dark, mid, tt) else mixc(mid, light, tt - 1)
		c = mixc(c, dark, smoothstep(0.62, 0.8, m) * 0.5)
		return { c = c }
	end,
	kintsugi = function(layer, x, y, z, ls)
		local qx, qy, qz = warp(x, y, z, num(layer.jitter, 0.4) * 0.6, 2, ls)
		local k = num(layer.cells, 3)
		local f1, f2, id = worley(qx * k, qy * k, qz * k, ls)
		local seam = 1 - smoothstep(0, num(layer.crack, 0.04), f2 - f1)
		local piece = mixc(hexOr(layer.color, "#1c1714"), hexOr(layer.color2, "#3b2a22"), id)
		return { c = mixc(piece, hexOr(layer.color3, "#e3b44a"), seam), metal = seam }
	end,
	agate = function(layer, x, y, z, ls)
		local qx, qy, qz = warp(x, y, z, num(layer.warp, 0.8), 1.5, ls)
		local d = qx * 0.6 + qy * 0.3 + qz * 0.74
		local band = 0.5 + 0.5 * math.sin(d * num(layer.rings, 12) + fbm(qx * 4, qy * 4, qz * 4, ls, 3) * 4)
		return { c = mixc(hexOr(layer.color, "#5a2a14"), hexOr(layer.color2, "#d8c8b0"), smoothstep(0.3, 0.7, band)) }
	end,
	marble = function(layer, x, y, z, ls)
		local qx, qy, qz = warp(x, y, z, 0.7, 1.5, ls)
		local s = num(layer.scale, 2)
		local v = ridged(qx * s, qy * s, qz * s, ls, 5) ^ (num(layer.sharp, 3) * 2)
		return { c = mixc(hexOr(layer.color, "#ece6dc"), hexOr(layer.color2, "#4a4642"), v) }
	end,
	strata = function(layer, x, y, z, ls)
		local yy = y + (fbm(x * 2, y * 2, z * 2, ls, 4) - 0.5) * num(layer.bend, 0.5)
		local i = math.floor((yy * 0.5 + 0.5) * num(layer.layers, 9))
		local t = hash(mod(ls + i * 7919 + 17)) / (M - 1)
		local c = mixc(hexOr(layer.color, "#5a3a22"), hexOr(layer.color2, "#d8b890"), t)
		local grit = (noise(x * 80, y * 80, z * 80, ls) - 0.5) * 0.08
		return { c = { c[1] + grit, c[2] + grit, c[3] + grit } }
	end,
	galaxy = function(layer, x, y, z, ls)
		local qx, qy, qz = warp(x, y, z, 1.2, 1.2, ls)
		local s = num(layer.scale, 2.2)
		local t = turb(qx * s, qy * s, qz * s, ls, 5)
		local neb = mixc(hexOr(layer.color, "#0a0614"), hexOr(layer.color2, "#8a3ad0"), smoothstep(0.2, 0.8, t))
		local st = num(layer.stars, 0.01)
		local star = smoothstep(1 - st - 0.004, 1 - st, noise(x * 150, y * 150, z * 150, mod(ls + 7)))
		return { c = mixc(neb, hexOr(layer.color3, "#ffffff"), star), glow = math.max(star, t * 0.25) }
	end,
}

local function spherePoint(u: number, v: number): (number, number, number)
	u = ((u % 1) + 1) % 1
	v = clamp(v, 0, 1)
	local lat, lon = v * math.pi, u * TAU
	local s = math.sin(lat)
	return s * math.cos(lon), math.cos(lat), s * math.sin(lon)
end

local function mask(layer, x: number, y: number, z: number, ls: number): number
	local ox = hash(mod(ls + 40503)) / (M - 1) * 64
	local oy = hash(mod(ls + 81006)) / (M - 1) * 64
	local oz = hash(mod(ls + 121509)) / (M - 1) * 64
	local kind = layer.type
	if kind == "clouds" then
		local s = num(layer.scale, 2.5)
		local n = fbm(x * s + ox, y * s + oy, z * s + oz, ls, math.floor(num(layer.octaves, 3)))
		local t, soft = num(layer.threshold, 0.5), num(layer.softness, 0.4)
		return smoothstep(t - soft / 2, t + soft / 2, n)
	elseif kind == "speckle" then
		local s, d = num(layer.scale, 60), num(layer.density, 0.2)
		local n = noise(x * s + ox, y * s + oy, z * s + oz, ls)
		return smoothstep(1 - d - 0.04, 1 - d + 0.04, n)
	elseif kind == "ribbons" or kind == "veins" then
		local warp = num(layer.warp, 1.2)
		local n = noise(x * 2.2 + ox, y * 2.2 + oy, z * 2.2 + oz, ls)
		local w = noise(x * 3.1 + oz, y * 3.1 + ox, z * 3.1 + oy, bit32.bxor(ls, 92683))
		local qx, qy, qz = x + (n - 0.5) * warp, y + (w - 0.5) * warp, z + (n - w) * warp * 0.55
		local freq = num(layer.scale, 7)
		local phase = (qx * 0.73 + qy * 0.46 + qz * 0.57) * freq + ox
		local twist = num(layer.twist, 3)
		local band = 0.5 + 0.5 * math.sin(phase + twist * math.sin(qy * 3.5) + w * 5)
		if kind == "veins" then
			return (1 - math.abs(band * 2 - 1)) ^ num(layer.sharpness, 12)
		end
		local width = num(layer.width, 0.6)
		return smoothstep(0.5 - width / 2, 0.5 + width / 2, band)
	end
	return 1 -- fill
end

function Sampler.sampleStack(stack, seed: number, u: number, v: number): Material
	seed = mod(math.floor(num(seed, 0)))
	local x, y, z = spherePoint(u, v)
	local cr, cg, cb = 0, 0, 0
	local rough, metal, glow = 0.9, 0, 0
	for si, item in stack do
		local def = item.def
		local amount, polish = num(item.amount, 1), clamp(num(item.polish, 0), 0, 1)
		local baseRough = num(def.rough and def.rough.roughness, 0.9)
		local polRough = num(def.polished and def.polished.roughness, 0.2)
		local polMetal = num(def.polished and def.polished.metalness, 0)
		for li, layer in def.layers or {} do
			-- JS indexes from 0; keep the same salts.
			local ls = hash(mod(seed + ((si - 1) * 97 + (li - 1) + 1) * 7109))
			local gen = GENERATORS[layer.type]
			local gr = if gen then gen(layer, x, y, z, ls) else nil
			local cov = clamp(amount * num(layer.amount, 1) * (if gr then 1 else mask(layer, x, y, z, ls)), 0, 1)
			if cov > 0 then
				local c = if gr then gr.c else hex(layer.color)
				local r, g, b = c[1], c[2], c[3]
				if not gr and layer.accent then
					local as = num(layer.accentScale, 2)
					local t = smooth(noise(x * as + 17, y * as + 31, z * as + 47, bit32.bxor(ls, 7777)))
					local a = hex(layer.accent)
					r, g, b = mix(r, a[1], t), mix(g, a[2], t), mix(b, a[3], t)
				end
				cr, cg, cb = mix(cr, r, cov), mix(cg, g, cov), mix(cb, b, cov)
				local lm = num(layer.metalness, polMetal)
				local lg = num(layer.glow, 0)
				if gr and gr.metal ~= nil then
					lm = math.max(lm, gr.metal)
				end
				if gr and gr.glow ~= nil then
					lg = math.max(lg, gr.glow)
				end
				rough = mix(rough, mix(baseRough, num(layer.roughness, polRough), polish), cov)
				metal = mix(metal, lm * polish, cov)
				glow = mix(glow, lg * (0.1 + 0.9 * polish), cov)
			end
		end
	end
	return {
		r = clamp(cr, 0, 1),
		g = clamp(cg, 0, 1),
		b = clamp(cb, 0, 1),
		roughness = clamp(rough, 0.04, 1),
		metalness = clamp(metal, 0, 1),
		glow = clamp(glow, 0, 1),
	}
end

-- One representative material for the whole ball (equal-area samples).
function Sampler.average(stack, seed: number): Material
	local r, g, b, rough, metal, glow, count = 0, 0, 0, 0, 0, 0, 0
	for j = 0, 3 do
		local v = math.acos(1 - (j + 0.5) / 4 * 2) / math.pi
		for i = 0, 5 do
			local m = Sampler.sampleStack(stack, seed, (i + 0.5) / 6, v)
			r += m.r
			g += m.g
			b += m.b
			rough += m.roughness
			metal += m.metalness
			glow += m.glow
			count += 1
		end
	end
	return { r = r / count, g = g / count, b = b / count, roughness = rough / count, metalness = metal / count, glow = glow / count }
end

return Sampler
