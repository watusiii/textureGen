# MudTexture

Procedural textures for spheres (mud balls, marbles, planets, anything round). You design looks in a
browser maker; Roblox paints a unique texture for every ball at runtime from the same recipe.

- **Maker** (browser, no install): design and explore textures, save them as small JSON files.
- **Definitions** (`textures/*.json`): the looks. Plain data any engine can read.
- **Roblox reader** (`src/`): a line-for-line Luau port of the maker's core, plus a ball renderer.

Started from **Hendrix's** texture system, restructured Oct 2026 by Law + Claude so the look lives in
plain files. Licensing between Law and Hendrix is still to be decided before it's used outside the team.

## Use it in your Roblox game

1. **Turn on image APIs** (once per place): Game Settings → Security → **Allow Mesh / Image APIs**.
2. **Bring the module in.** With Rojo, map it in your project:

   ```json
   "ReplicatedStorage": {
     "MudTexture": { "$path": "path/to/MudTexture/src", "Textures": { "$path": "path/to/MudTexture/textures" } }
   }
   ```

   Without Rojo: `rojo build package.project.json -o MudTexture.rbxm` and insert it into ReplicatedStorage.
3. **Paint a ball** (client script):

   ```luau
   local MudTexture = ReplicatedStorage.MudTexture
   local Library = require(MudTexture.Library)
   local BallAppearance = require(MudTexture.BallAppearance)

   local library = Library.load(MudTexture.Textures)
   local ball = BallAppearance.new(workspace, { library = library, resolution = 64, radius = 1, cframe = cf })
   ball:setBall({
       id = "ball-1", seed = 123,                    -- same seed = same ball everywhere
       body = "loam", corePolish = 1,                -- a texture id from textures/
       coats = { { tex = "sakura", amount = 0.7, polish = 1 } },
       revision = 1,                                 -- bump when the ball changes
   })
   -- ball:setCFrame(cf), ball:setRotation(yaw), ball:destroy()
   ```

   Or pass a ready stack instead of body/coats: `stack = { { def = <definition table>, amount = 1, polish = 1 }, ... }`
   (that's how a game can roll its own looks; see `Library:stackFor`).

Send the **recipe** (id, seed, body, coats, revision) over the network, never the images. Every client
paints its own.

## Make or change a texture

Open `maker/index.html` in a browser (double-click is fine; it loads three.js from a CDN).

1. Pick a body (and a coat to see them together). Edit layers, colours, roughness. **New** tries other seeds.
2. **Download JSON** and save it into `textures/` as `<id>.json`.
3. Run `node maker/build-library.mjs` so the maker and explorer list it.
4. Rojo syncs it into Roblox.

`maker/explore.html` shows a grid of generated textures: **Random**, **Mutate base**, **Seeds of base**.
Click a ball to keep it, Space rolls. Under each ball: **JSON** downloads it, **Edit** opens it in the maker.

`maker/lab.html` is for inventing new image functions. Write `params` and `generate(p, P, seed, N)`; the
right side shows a grid of balls. Ctrl+Enter runs, Space rolls. Helpers: noise, fbm, ridged, turb,
worley, warp, ramp, hsl, mixc, smoothstep, rand. When a generator is good, it gets ported into
`core/texcore.js` + `src/Sampler.luau` as a new layer type.

## Definition format

```json
{ "id": "loam", "name": "Garden Loam", "version": 1,
  "rough":    { "roughness": 0.92 },
  "polished": { "roughness": 0.14, "metalness": 0.02 },
  "layers": [
    { "type": "fill",    "color": "#6b4a32" },
    { "type": "clouds",  "color": "#8a6644", "amount": 0.55, "scale": 2.2, "softness": 0.5 },
    { "type": "speckle", "color": "#2b1d14", "amount": 0.4,  "scale": 70,  "density": 0.12 }
  ] }
```

- Pattern layers (a mask over `color`, optional `accent`): **fill** · **clouds** (scale, threshold,
  softness, octaves) · **ribbons** (scale, warp, width, twist) · **veins** (scale, warp, sharpness) ·
  **speckle** (scale, density).
- Generator layers (paint their own colours from `color`, `color2`, `color3`): **earth** (scale, detail) ·
  **kintsugi** (cells, crack, jitter; the seam is metal) · **agate** (rings, warp) · **marble** (scale,
  sharp) · **strata** (layers, bend) · **galaxy** (scale, stars; glows).
- Any layer: `amount`, `accent` + `accentScale`, `roughness`, `metalness`, `glow`.
- A ball is a stack: the body definition, then coats on top, each with its own amount and polish.

## Keeping JS and Luau identical

`src/Sampler.luau` is a line-for-line port of `maker/core/texcore.js`. Change one, change the other, then:

```
node tests/parity.mjs > tests/_parity_cases.luau
luau tests/run_parity.luau
```

(`tests/parity.sh` does both. Needs `node` and the `luau` CLI.) Last run: 342 cases, every texture,
worst difference 5.8e-14, PASS.

## Preview place

`rokit install`, then `rojo serve` (uses `default.project.json`), connect from a Baseplate, Play.
White studio with 6 bodies × 6 coats. N = new seeds, R = 64/128 resolution, L = labels.

## Repo layout

```
maker/                 browser tools (index = maker, explore = grid, lab = new functions)
  core/texcore.js      the texture core (the source of truth for how layers look)
  library.js           built from textures/ by build-library.mjs
textures/              the definitions (one JSON per look)
src/                   Roblox module: Sampler (port of texcore), Library, BallAppearance
preview/               preview place script (SampleCatalog.luau is unused)
tests/                 JS vs Luau parity test
default.project.json   Rojo: the preview place
package.project.json   Rojo: just the module (+ Textures), for `rojo build -o MudTexture.rbxm`
```

## Known limits

- Each textured ball holds 4 EditableImages. Texture only the balls that matter (in hand, on display).
- Not yet checked on phones or with a full server.
