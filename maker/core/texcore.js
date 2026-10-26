/*
 * MudTexture core: texture definition (JSON) + seed + polish -> surface material at any point
 * on a sphere. Engine-free. Runs in the browser (maker) and in Node (tests, exports).
 *
 * The Roblox reader (src/Sampler.luau) is a line-for-line port of this file.
 * Change both together, then run tests/parity.sh. They must agree to ~1e-9.
 *
 * Definition:
 * {
 *   id, name, version: 1,
 *   rough:    { roughness }               // unpolished surface
 *   polished: { roughness, metalness }    // fully polished defaults
 *   layers: [ { type, color, accent?, accentScale?, amount?, roughness?, metalness?, glow?, ...type params } ]
 * }
 * Layer types (patterns: coverage mask over `color`, with optional `accent`):
 *   fill                               solid colour
 *   clouds   scale, threshold, softness, octaves      soft mottled patches
 *   ribbons  scale, warp, width, twist                 warped flowing bands
 *   veins    scale, warp, sharpness                    thin bright lines
 *   speckle  scale, density                            fine dots
 * Generator types (paint their own colours from color / color2 / color3; `amount` = how much shows):
 *   earth    scale, detail            color dark, color2 mid, color3 light      calm mottled earth
 *   kintsugi cells, crack, jitter     color shard, color2 shard alt, color3 seam (metal)  gold-seamed shards
 *   agate    rings, warp              color, color2                             warped rings
 *   marble   scale, sharp             color base, color2 vein                   sharp veins
 *   strata   layers, bend             color, color2 (each layer between them)   sediment layers
 *   galaxy   scale, stars             color dark, color2 nebula, color3 stars (glow)
 * Stack (what one ball is): [ { def, amount, polish } ]  body first, then each coat.
 */
(function (root) {
  "use strict";
  const M = 4294967296; // 2^32
  const TAU = Math.PI * 2;

  const mod = (x) => ((x % M) + M) % M;
  const mul32 = (a, b) => Math.imul(a, b) >>> 0;
  function hash(n) {
    n = n >>> 0;
    n = (n ^ (n >>> 16)) >>> 0;
    n = mul32(n, 73244475);
    n = (n ^ (n >>> 16)) >>> 0;
    n = mul32(n, 73244475);
    return (n ^ (n >>> 16)) >>> 0;
  }
  function h3(x, y, z, seed) {
    const v = (mul32(mod(x), 73856093) ^ mul32(mod(y), 19349663) ^ mul32(mod(z), 83492791) ^ seed) >>> 0;
    return hash(v) / (M - 1);
  }
  const mix = (a, b, t) => a + (b - a) * t;
  const smooth = (t) => t * t * (3 - 2 * t);
  const clamp = (x, lo, hi) => (x < lo ? lo : x > hi ? hi : x);
  function smoothstep(a, b, x) {
    if (b <= a) return x >= a ? 1 : 0;
    return smooth(clamp((x - a) / (b - a), 0, 1));
  }

  // Smooth 3-D value noise, 0..1.
  function noise(x, y, z, seed) {
    const ix = Math.floor(x), iy = Math.floor(y), iz = Math.floor(z);
    const a = smooth(x - ix), b = smooth(y - iy), c = smooth(z - iz);
    return mix(
      mix(mix(h3(ix, iy, iz, seed), h3(ix + 1, iy, iz, seed), a), mix(h3(ix, iy + 1, iz, seed), h3(ix + 1, iy + 1, iz, seed), a), b),
      mix(mix(h3(ix, iy, iz + 1, seed), h3(ix + 1, iy, iz + 1, seed), a), mix(h3(ix, iy + 1, iz + 1, seed), h3(ix + 1, iy + 1, iz + 1, seed), a), b),
      c
    );
  }
  function fbm(x, y, z, seed, octaves) {
    let sum = 0, amp = 1, norm = 0, f = 1;
    for (let o = 0; o < octaves; o++) {
      sum += noise(x * f, y * f, z * f, mod(seed + o * 1013)) * amp;
      norm += amp;
      amp *= 0.5;
      f *= 2;
    }
    return sum / norm;
  }

  function ridged(x, y, z, seed, octaves) {
    let sum = 0, amp = 0.5, f = 1, norm = 0;
    for (let o = 0; o < octaves; o++) {
      const n = 1 - Math.abs(noise(x * f, y * f, z * f, mod(seed + o * 131)) * 2 - 1);
      sum += n * n * amp; norm += amp; amp *= 0.5; f *= 2;
    }
    return sum / norm;
  }
  function turb(x, y, z, seed, octaves) {
    let sum = 0, amp = 0.5, f = 1, norm = 0;
    for (let o = 0; o < octaves; o++) {
      sum += Math.abs(noise(x * f, y * f, z * f, mod(seed + o * 977)) * 2 - 1) * amp;
      norm += amp; amp *= 0.5; f *= 2;
    }
    return sum / norm;
  }
  // Cellular noise: distance to nearest (f1) and second nearest (f2) cell point, and the cell's id 0..1.
  function worley(x, y, z, seed) {
    const ix = Math.floor(x), iy = Math.floor(y), iz = Math.floor(z);
    let f1 = 9, f2 = 9, id = 0;
    for (let dz = -1; dz <= 1; dz++) {
      for (let dy = -1; dy <= 1; dy++) {
        for (let dx = -1; dx <= 1; dx++) {
          const cx = ix + dx, cy = iy + dy, cz = iz + dz;
          const h = hash((mul32(mod(cx), 73856093) ^ mul32(mod(cy), 19349663) ^ mul32(mod(cz), 83492791) ^ seed) >>> 0);
          const px = cx + (h & 1023) / 1023, py = cy + ((h >>> 10) & 1023) / 1023, pz = cz + ((h >>> 20) & 1023) / 1023;
          const ddx = px - x, ddy = py - y, ddz = pz - z;
          const d = Math.sqrt(ddx * ddx + ddy * ddy + ddz * ddz);
          if (d < f1) { f2 = f1; f1 = d; id = h / (M - 1); } else if (d < f2) { f2 = d; }
        }
      }
    }
    return [f1, f2, id];
  }
  // Bend a point with noise (domain warp).
  function warp(x, y, z, amount, s, seed) {
    const a = noise(x * s + 11, y * s + 3, z * s + 7, seed) - 0.5;
    const b = noise(x * s + 23, y * s + 17, z * s + 5, mod(seed + 1)) - 0.5;
    const c = noise(x * s + 2, y * s + 29, z * s + 13, mod(seed + 2)) - 0.5;
    return [x + a * amount, y + b * amount, z + c * amount];
  }
  const mixc = (a, b, t) => [mix(a[0], b[0], t), mix(a[1], b[1], t), mix(a[2], b[2], t)];

  function hex(s) {
    s = String(s || "#000000").replace("#", "");
    return [parseInt(s.slice(0, 2), 16) / 255, parseInt(s.slice(2, 4), 16) / 255, parseInt(s.slice(4, 6), 16) / 255];
  }
  const num = (v, d) => (typeof v === "number" ? v : d);

  // Point on the unit sphere for texture coordinate (u, v). No seam, no pole pinch.
  function spherePoint(u, v) {
    u = ((u % 1) + 1) % 1;
    v = clamp(v, 0, 1);
    const lat = v * Math.PI, lon = u * TAU;
    const s = Math.sin(lat);
    return [s * Math.cos(lon), Math.cos(lat), s * Math.sin(lon)];
  }

  // Coverage 0..1 of one layer at point p.
  function mask(layer, p, ls) {
    const ox = (hash(mod(ls + 40503)) / (M - 1)) * 64;
    const oy = (hash(mod(ls + 81006)) / (M - 1)) * 64;
    const oz = (hash(mod(ls + 121509)) / (M - 1)) * 64;
    const x = p[0], y = p[1], z = p[2];
    switch (layer.type) {
      case "clouds": {
        const s = num(layer.scale, 2.5);
        const n = fbm(x * s + ox, y * s + oy, z * s + oz, ls, Math.floor(num(layer.octaves, 3)));
        const t = num(layer.threshold, 0.5), soft = num(layer.softness, 0.4);
        return smoothstep(t - soft / 2, t + soft / 2, n);
      }
      case "speckle": {
        const s = num(layer.scale, 60), d = num(layer.density, 0.2);
        const n = noise(x * s + ox, y * s + oy, z * s + oz, ls);
        return smoothstep(1 - d - 0.04, 1 - d + 0.04, n);
      }
      case "ribbons":
      case "veins": {
        const warp = num(layer.warp, 1.2);
        const n = noise(x * 2.2 + ox, y * 2.2 + oy, z * 2.2 + oz, ls);
        const w = noise(x * 3.1 + oz, y * 3.1 + ox, z * 3.1 + oy, (ls ^ 92683) >>> 0);
        const qx = x + (n - 0.5) * warp, qy = y + (w - 0.5) * warp, qz = z + (n - w) * warp * 0.55;
        const freq = num(layer.scale, 7);
        const phase = (qx * 0.73 + qy * 0.46 + qz * 0.57) * freq + ox;
        const twist = num(layer.twist, 3);
        const band = 0.5 + 0.5 * Math.sin(phase + twist * Math.sin(qy * 3.5) + w * 5);
        if (layer.type === "veins") return Math.pow(1 - Math.abs(band * 2 - 1), num(layer.sharpness, 12));
        const width = num(layer.width, 0.6);
        return smoothstep(0.5 - width / 2, 0.5 + width / 2, band);
      }
      default: // fill
        return 1;
    }
  }

  // Generator layers: return { c: [r,g,b], metal?, glow? } at point (x, y, z).
  const GENERATORS = {
    earth(layer, x, y, z, ls) {
      const s = num(layer.scale, 2.5);
      const n = fbm(x * s, y * s, z * s, ls, Math.floor(num(layer.detail, 4)));
      const m = fbm(x * s * 3 + 9, y * s * 3, z * s * 3, mod(ls + 1), 3);
      const dark = hex(layer.color || "#2b1d14"), mid = hex(layer.color2 || "#6b4a32"), light = hex(layer.color3 || "#a8845c");
      const tt = smoothstep(0.25, 0.75, n) * 2;
      let c = tt < 1 ? mixc(dark, mid, tt) : mixc(mid, light, tt - 1);
      c = mixc(c, dark, smoothstep(0.62, 0.8, m) * 0.5);
      return { c };
    },
    kintsugi(layer, x, y, z, ls) {
      const q = warp(x, y, z, num(layer.jitter, 0.4) * 0.6, 2, ls);
      const k = num(layer.cells, 3);
      const w = worley(q[0] * k, q[1] * k, q[2] * k, ls);
      const seam = 1 - smoothstep(0, num(layer.crack, 0.04), w[1] - w[0]);
      const piece = mixc(hex(layer.color || "#1c1714"), hex(layer.color2 || "#3b2a22"), w[2]);
      return { c: mixc(piece, hex(layer.color3 || "#e3b44a"), seam), metal: seam };
    },
    agate(layer, x, y, z, ls) {
      const q = warp(x, y, z, num(layer.warp, 0.8), 1.5, ls);
      const d = q[0] * 0.6 + q[1] * 0.3 + q[2] * 0.74;
      const band = 0.5 + 0.5 * Math.sin(d * num(layer.rings, 12) + fbm(q[0] * 4, q[1] * 4, q[2] * 4, ls, 3) * 4);
      return { c: mixc(hex(layer.color || "#5a2a14"), hex(layer.color2 || "#d8c8b0"), smoothstep(0.3, 0.7, band)) };
    },
    marble(layer, x, y, z, ls) {
      const q = warp(x, y, z, 0.7, 1.5, ls);
      const s = num(layer.scale, 2);
      const v = Math.pow(ridged(q[0] * s, q[1] * s, q[2] * s, ls, 5), num(layer.sharp, 3) * 2);
      return { c: mixc(hex(layer.color || "#ece6dc"), hex(layer.color2 || "#4a4642"), v) };
    },
    strata(layer, x, y, z, ls) {
      const yy = y + (fbm(x * 2, y * 2, z * 2, ls, 4) - 0.5) * num(layer.bend, 0.5);
      const i = Math.floor((yy * 0.5 + 0.5) * num(layer.layers, 9));
      const t = hash(mod(ls + i * 7919 + 17)) / (M - 1);
      const c = mixc(hex(layer.color || "#5a3a22"), hex(layer.color2 || "#d8b890"), t);
      const grit = (noise(x * 80, y * 80, z * 80, ls) - 0.5) * 0.08;
      return { c: [c[0] + grit, c[1] + grit, c[2] + grit] };
    },
    galaxy(layer, x, y, z, ls) {
      const q = warp(x, y, z, 1.2, 1.2, ls);
      const s = num(layer.scale, 2.2);
      const t = turb(q[0] * s, q[1] * s, q[2] * s, ls, 5);
      const neb = mixc(hex(layer.color || "#0a0614"), hex(layer.color2 || "#8a3ad0"), smoothstep(0.2, 0.8, t));
      const st = num(layer.stars, 0.01);
      const star = smoothstep(1 - st - 0.004, 1 - st, noise(x * 150, y * 150, z * 150, mod(ls + 7)));
      return { c: mixc(neb, hex(layer.color3 || "#ffffff"), star), glow: Math.max(star, t * 0.25) };
    },
  };

  // Material at (u, v) for a stack of definitions. Returns { r, g, b, roughness, metalness, glow }.
  function sampleStack(stack, seed, u, v) {
    seed = mod(Math.floor(num(seed, 0)));
    const p = spherePoint(u, v);
    let col = [0, 0, 0], rough = 0.9, metal = 0, glow = 0;
    for (let si = 0; si < stack.length; si++) {
      const item = stack[si], def = item.def;
      const amount = num(item.amount, 1), polish = clamp(num(item.polish, 0), 0, 1);
      const baseRough = num(def.rough && def.rough.roughness, 0.9);
      const polRough = num(def.polished && def.polished.roughness, 0.2);
      const polMetal = num(def.polished && def.polished.metalness, 0);
      const layers = def.layers || [];
      for (let li = 0; li < layers.length; li++) {
        const layer = layers[li];
        const ls = hash(mod(seed + (si * 97 + li + 1) * 7109));
        const gen = GENERATORS[layer.type];
        const g = gen ? gen(layer, p[0], p[1], p[2], ls) : null;
        const cov = clamp(amount * num(layer.amount, 1) * (g ? 1 : mask(layer, p, ls)), 0, 1);
        if (cov <= 0) continue;
        let c = g ? g.c : hex(layer.color);
        if (!g && layer.accent) {
          const as = num(layer.accentScale, 2);
          const t = smooth(noise(p[0] * as + 17, p[1] * as + 31, p[2] * as + 47, (ls ^ 7777) >>> 0));
          const a = hex(layer.accent);
          c = [mix(c[0], a[0], t), mix(c[1], a[1], t), mix(c[2], a[2], t)];
        }
        col = [mix(col[0], c[0], cov), mix(col[1], c[1], cov), mix(col[2], c[2], cov)];
        let lm = num(layer.metalness, polMetal);
        let lg = num(layer.glow, 0);
        if (g && g.metal !== undefined) lm = Math.max(lm, g.metal);
        if (g && g.glow !== undefined) lg = Math.max(lg, g.glow);
        rough = mix(rough, mix(baseRough, num(layer.roughness, polRough), polish), cov);
        metal = mix(metal, lm * polish, cov);
        glow = mix(glow, lg * (0.1 + 0.9 * polish), cov);
      }
    }
    return {
      r: clamp(col[0], 0, 1), g: clamp(col[1], 0, 1), b: clamp(col[2], 0, 1),
      roughness: clamp(rough, 0.04, 1), metalness: clamp(metal, 0, 1), glow: clamp(glow, 0, 1),
    };
  }

  // Paint RGBA maps (Uint8ClampedArray, size×size) for color, roughness, metalness, glow.
  function paintMaps(stack, seed, size) {
    const maps = { color: new Uint8ClampedArray(size * size * 4), roughness: new Uint8ClampedArray(size * size * 4),
      metalness: new Uint8ClampedArray(size * size * 4), glow: new Uint8ClampedArray(size * size * 4) };
    for (let y = 0; y < size; y++) {
      for (let x = 0; x < size; x++) {
        const m = sampleStack(stack, seed, x / (size - 1), y / (size - 1));
        const o = (y * size + x) * 4;
        maps.color.set([m.r * 255, m.g * 255, m.b * 255, 255], o);
        maps.roughness.set([m.roughness * 255, m.roughness * 255, m.roughness * 255, 255], o);
        maps.metalness.set([m.metalness * 255, m.metalness * 255, m.metalness * 255, 255], o);
        maps.glow.set([m.glow * 255, m.glow * 255, m.glow * 255, 255], o);
      }
    }
    return maps;
  }

  const api = { sampleStack, paintMaps, spherePoint, noise, fbm, ridged, turb, worley, warp, hash, mask,
    LAYER_TYPES: ["fill", "clouds", "ribbons", "veins", "speckle", "earth", "kintsugi", "agate", "marble", "strata", "galaxy"],
    GENERATOR_TYPES: Object.keys(GENERATORS) };
  if (typeof module !== "undefined" && module.exports) module.exports = api;
  root.TexCore = api;
})(typeof window !== "undefined" ? window : globalThis);
