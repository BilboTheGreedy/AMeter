local _, ns = ...

local Native = {}
ns.Native = Native

local TYPE_IDS = {
	DamageDone = 0, Dps = 1, HealingDone = 2, Hps = 3, Absorbs = 4, Interrupts = 5,
	Dispels = 6, DamageTaken = 7, AvoidableDamageTaken = 8, Deaths = 9, EnemyDamageTaken = 10,
}

local function typeId(name)
	local e = Enum and Enum.DamageMeterType
	if e and e[name] ~= nil then return e[name] end
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
	if type(v) == "nil" or ns.IsSecret(v) then return nil end
	if kind and type(v) ~= kind then return nil end
	return v
end

function Native.Session(segment, mode)
	local out = { rows = {} }
	local id = typeId(mode.type)
	if id == nil then return out end
	local st = sessionType(segment)
	local ok, session = pcall(C_DamageMeter.GetCombatSessionFromType, st, id)
	if not ok or type(session) ~= "table" or ns.IsSecret(session) then return out end
	local sources = session.combatSources
	if type(sources) ~= "table" or ns.IsSecret(sources) then return out end
	out.max = session.maxAmount
	out.total = session.totalAmount
	if C_DamageMeter.GetSessionDurationSeconds then
		local dok, d = pcall(C_DamageMeter.GetSessionDurationSeconds, st)
		if dok then out.duration = d end
	end
	if type(out.duration) == "nil" then out.duration = session.durationSeconds end
	for _, src in ipairs(sources) do
		if type(src) == "table" and not ns.IsSecret(src) then
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
	local ok, src = pcall(C_DamageMeter.GetCombatSessionSourceFromType, sessionType(segment), id, row.guid, row.creatureID)
	if not ok or type(src) ~= "table" or ns.IsSecret(src) then return out end
	local spells = src.combatSpells
	if type(spells) ~= "table" or ns.IsSecret(spells) then return out end
	out.max = src.maxAmount
	out.total = src.totalAmount
	for _, sp in ipairs(spells) do
		if type(sp) == "table" and not ns.IsSecret(sp) then
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
