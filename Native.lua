local _, ns = ...

local Native = {}
ns.Native = Native

local TYPE_IDS = {
	DamageDone = 0, Dps = 1, HealingDone = 2, Hps = 3, Absorbs = 4, Interrupts = 5,
	Dispels = 6, DamageTaken = 7, AvoidableDamageTaken = 8, Deaths = 9, EnemyDamageTaken = 10,
}

local function typeId(name)
	local e = Enum and Enum.DamageMeterType
	if e then return e[name] end
	return TYPE_IDS[name]
end

local function sessionType(segment)
	local e = Enum and Enum.DamageMeterSessionType
	if segment == "overall" then
		return e and e.Overall or 0
	end
	return e and e.Current or 1
end

function Native.Exists()
	return C_DamageMeter ~= nil and C_DamageMeter.GetCombatSessionFromType ~= nil
end

function Native.Available()
	if not Native.Exists() then return false end
	if not C_DamageMeter.IsDamageMeterAvailable then return true end
	local ok, available, reason = pcall(C_DamageMeter.IsDamageMeterAvailable)
	if not ok then return false end
	if ns.IsSecret(available) then return true end
	if available then return true end
	return false, reason
end

function Native.Supports(mode)
	return typeId(mode.type) ~= nil
end

local function plain(v, kind)
	if ns.IsSecret(v) or type(v) == "nil" then return nil end
	if kind and type(v) ~= kind then return nil end
	return v
end

function Native.Sessions()
	local out = {}
	if not C_DamageMeter.GetAvailableCombatSessions or not C_DamageMeter.GetCombatSessionFromID then return out end
	local ok, list = pcall(C_DamageMeter.GetAvailableCombatSessions)
	if not ok or ns.IsSecret(list) or type(list) ~= "table" then return out end
	for _, s in ipairs(list) do
		if not ns.IsSecret(s) and type(s) == "table" then
			local id = plain(s.sessionID, "number")
			if id then
				out[#out + 1] = { id = id, name = plain(s.name, "string"), duration = plain(s.durationSeconds, "number") }
			end
		end
	end
	return out
end

local function session(segment, id)
	if type(segment) == "number" then
		if not C_DamageMeter.GetCombatSessionFromID then return false end
		return pcall(C_DamageMeter.GetCombatSessionFromID, segment, id)
	end
	return pcall(C_DamageMeter.GetCombatSessionFromType, sessionType(segment), id)
end

local function source(segment, id, guid, creature)
	if type(segment) == "number" then
		if not C_DamageMeter.GetCombatSessionSourceFromID then return false end
		return pcall(C_DamageMeter.GetCombatSessionSourceFromID, segment, id, guid, creature)
	end
	return pcall(C_DamageMeter.GetCombatSessionSourceFromType, sessionType(segment), id, guid, creature)
end

function Native.Session(segment, mode)
	local out = { rows = {} }
	local id = typeId(mode.type)
	if id == nil then return out end
	local ok, data = session(segment, id)
	if not ok or ns.IsSecret(data) or type(data) ~= "table" then return out end
	local sources = data.combatSources
	if ns.IsSecret(sources) or type(sources) ~= "table" then return out end
	out.max = data.maxAmount
	out.total = data.totalAmount
	if type(segment) ~= "number" and C_DamageMeter.GetSessionDurationSeconds then
		local dok, d = pcall(C_DamageMeter.GetSessionDurationSeconds, sessionType(segment))
		if dok then out.duration = d end
	end
	if type(out.duration) == "nil" then out.duration = data.durationSeconds end
	for _, src in ipairs(sources) do
		if not ns.IsSecret(src) and type(src) == "table" then
			local value = src.totalAmount
			if mode.rate and type(src.amountPerSecond) ~= "nil" then value = src.amountPerSecond end
			out.rows[#out.rows + 1] = {
				name = src.name,
				guid = src.sourceGUID,
				creatureID = src.sourceCreatureID,
				class = plain(src.classFilename, "string"),
				me = plain(src.isLocalPlayer) and true or false,
				value = value,
				total = src.totalAmount,
				rate = src.amountPerSecond,
				time = src.deathTimeSeconds,
			}
		end
	end
	return out
end

function Native.Spells(segment, mode, row)
	local out = { rows = {} }
	local id = typeId(mode.type)
	if id == nil then return out end
	local guid, creature = row.guid, row.creatureID
	if row.me and UnitGUID then
		local own = UnitGUID("player")
		if plain(own, "string") then guid, creature = own, nil end
	end
	local ok, src = source(segment, id, guid, creature)
	if not ok or ns.IsSecret(src) or type(src) ~= "table" then
		out.hidden = ns.IsSecret(guid) or ns.IsSecret(creature)
		return out
	end
	local spells = src.combatSpells
	if ns.IsSecret(spells) or type(spells) ~= "table" then return out end
	out.max = src.maxAmount
	out.total = src.totalAmount
	for _, sp in ipairs(spells) do
		if not ns.IsSecret(sp) and type(sp) == "table" then
			local value = sp.totalAmount
			if mode.rate and type(sp.amountPerSecond) ~= "nil" then value = sp.amountPerSecond end
			out.rows[#out.rows + 1] = {
				spell = sp.spellID,
				pet = plain(sp.creatureName, "string"),
				value = value,
				total = sp.totalAmount,
				rate = sp.amountPerSecond,
			}
		end
	end
	return out
end

function Native.Reset()
	if C_DamageMeter.ResetAllCombatSessions then
		pcall(C_DamageMeter.ResetAllCombatSessions)
	end
end

function Native.Start()
	local function changed()
		ns:Fire("DATA")
	end
	ns:On("DAMAGE_METER_COMBAT_SESSION_UPDATED", changed)
	ns:On("DAMAGE_METER_CURRENT_SESSION_UPDATED", changed)
	ns:On("DAMAGE_METER_RESET", changed)
end
