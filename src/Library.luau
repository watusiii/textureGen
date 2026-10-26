--!strict
-- MudTexture · Library
-- Loads texture definitions (textures/*.json, synced by Rojo as ModuleScripts) and turns a
-- ball recipe into a stack the Sampler can paint.
--
-- recipe = { seed, body = <texture id>, corePolish = 0..1, coats = { { tex = <id>, amount, polish } }, revision }
--       or { seed, stack = { { def = <definition table>, amount, polish } }, revision }

local Library = {}
Library.__index = Library

function Library.load(folder: Instance)
	local self = setmetatable({ defs = {} :: { [string]: any } }, Library)
	for _, child in folder:GetChildren() do
		if child:IsA("ModuleScript") then
			local ok, def = pcall(require, child)
			if ok and typeof(def) == "table" then
				self.defs[def.id or child.Name] = def
			else
				warn("[MudTexture] could not load texture " .. child:GetFullName())
			end
		end
	end
	return self
end

function Library:get(id: string)
	return self.defs[id]
end

-- Recipe -> { { def, amount, polish } } (body first, then coats). Unknown ids are skipped.
-- A recipe may also carry a ready-made stack (recipe.stack) with definitions inline;
-- games use that to build a unique look per ball. It is passed through as is.
function Library:stackFor(recipe)
	if typeof(recipe.stack) == "table" then
		return recipe.stack
	end
	local stack = {}
	local body = self.defs[recipe.body]
	if body then
		table.insert(stack, { def = body, amount = 1, polish = recipe.corePolish or 0 })
	end
	for _, coat in recipe.coats or {} do
		local def = self.defs[coat.tex]
		if def then
			table.insert(stack, { def = def, amount = coat.amount or 0.7, polish = coat.polish or 0 })
		end
	end
	return stack
end

return Library
