// Builds a Luau test file from the JSON textures + JS core results.
// Usage: node tests/parity.mjs > tests/_parity_cases.luau ; luau tests/run_parity.luau
import fs from "fs";
import path from "path";
import { createRequire } from "module";
const require = createRequire(import.meta.url);
const root = path.resolve(path.dirname(new URL(import.meta.url).pathname), "..");
const TexCore = require(path.join(root, "maker/core/texcore.js"));

const defs = {};
for (const f of fs.readdirSync(path.join(root, "textures"))) {
  if (f.endsWith(".json")) defs[f.replace(".json", "")] = JSON.parse(fs.readFileSync(path.join(root, "textures", f), "utf8"));
}
const ids = Object.keys(defs).sort();

function lua(v) {
  if (Array.isArray(v)) return "{" + v.map(lua).join(", ") + "}";
  if (v && typeof v === "object") return "{" + Object.entries(v).map(([k, x]) => `[${JSON.stringify(k)}] = ${lua(x)}`).join(", ") + "}";
  if (typeof v === "string") return JSON.stringify(v);
  return String(v);
}

const cases = [];
let rng = 12345;
const rand = () => ((rng = (rng * 1103515245 + 12345) % 2147483648) / 2147483648);
// Every texture appears as a body at least once, then random pairs.
for (let i = 0; i < ids.length + 40; i++) {
  const body = i < ids.length ? ids[i] : ids[Math.floor(rand() * ids.length)];
  const coat = ids[Math.floor(rand() * ids.length)];
  const stack = [{ id: body, amount: 1, polish: rand() }, { id: coat, amount: 0.7, polish: rand() }];
  const seed = Math.floor(rand() * 2147483646) + 1;
  for (let k = 0; k < 6; k++) {
    const u = rand(), v = rand();
    const m = TexCore.sampleStack(stack.map((s) => ({ def: defs[s.id], amount: s.amount, polish: s.polish })), seed, u, v);
    cases.push({ stack, seed, u, v, m });
  }
}
let out = "return {\n  defs = " + lua(defs) + ",\n  cases = {\n";
for (const c of cases) out += "    " + lua(c) + ",\n";
out += "  },\n}\n";
process.stdout.write(out);
