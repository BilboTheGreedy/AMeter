local _, ns = ...

local Data = {}
ns.Data = Data

local source

local function anySecret(rows)
	for _, r in ipairs(rows) do
		if ns.IsSecret(r.value) or ns.IsSecret(r.name) or ns.IsSecret(r.time) or ns.IsSecret(r.spell) then return true end
	end
	return false
end

local function finish(out)
	out.secret = anySecret(out.rows) or ns.IsSecret(out.max)
	if not out.secret then
		local max = 0
		for _, r in ipairs(out.rows) do
			if type(r.value) ~= "number" then r.value = 0 end
			if r.value > max then max = r.value end
		end
		table.sort(out.rows, function(a, b)
			if type(a.time) == "number" and type(b.time) == "number" and a.time ~= b.time then
				return a.time < b.time
			end
			if a.value ~= b.value then return a.value > b.value end
			return tostring(a.name or a.spell or "") < tostring(b.name or b.spell or "")
		end)
		out.max = max > 0 and max or 1
	end
	for i, r in ipairs(out.rows) do r.rank = i end
	return out
end

function Data.Source()
	return source and source.label
end

function Data.Status()
	if not source then return "No combat data is available on this client." end
	if source.api == ns.Native then
		local ok, reason = ns.Native.Available()
		if not ok then
			if type(reason) == "string" and not ns.IsSecret(reason) and reason ~= "" then
				return "Damage meter is unavailable: " .. reason
			end
			return "Damage meter is unavailable right now."
		end
	end
	return nil
end

function Data.Supports(mode)
	if not source then return false end
	if source.api == ns.Native then return ns.Native.Supports(mode) end
	return true
end

function Data.Session(segment, mode)
	if not source then return { rows = {} } end
	return finish(source.api.Session(segment, mode))
end

function Data.Spells(segment, mode, row)
	if not source then return { rows = {} } end
	return finish(source.api.Spells(segment, mode, row))
end

function Data.Reset()
	if source then source.api.Reset() end
	ns:Fire("DATA")
end

local lastInstance

ns:Listen("LOGIN", function()
	if ns.Native.Exists() then
		source = { api = ns.Native, label = "game meter" }
	elseif ns.Log.Exists() then
		source = { api = ns.Log, label = "combat log" }
	end
	if source then source.api.Start() end
	ns:On("PLAYER_ENTERING_WORLD", function()
		if not ns.db.autoreset or not IsInInstance or not GetInstanceInfo then return end
		local inside = IsInInstance()
		local _, _, _, _, _, _, _, id = GetInstanceInfo()
		if ns.IsSecret(inside) or ns.IsSecret(id) then return end
		if inside and id ~= lastInstance then
			Data.Reset()
		end
		lastInstance = inside and id or nil
	end)
	ns:Fire("DATA")
end)
