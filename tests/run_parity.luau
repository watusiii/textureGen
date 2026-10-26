-- Compares the Luau Sampler against the JS core on the same inputs.
local Sampler = require("../src/Sampler")
local data = require("./_parity_cases")
local worst, fails = 0, 0
for i, c in data.cases do
	local stack = {}
	for _, s in c.stack do
		table.insert(stack, { def = data.defs[s.id], amount = s.amount, polish = s.polish })
	end
	local m = Sampler.sampleStack(stack, c.seed, c.u, c.v)
	for _, k in { "r", "g", "b", "roughness", "metalness", "glow" } do
		local d = math.abs(m[k] - c.m[k])
		if d > worst then
			worst = d
		end
		if d > 1e-9 then
			fails += 1
			if fails <= 5 then
				print(string.format("MISMATCH case %d %s: luau %.12f js %.12f", i, k, m[k], c.m[k]))
			end
		end
	end
end
print(string.format("parity: %d cases, worst difference %.3g, %s", #data.cases, worst, fails == 0 and "PASS" or ("FAIL x" .. fails)))
