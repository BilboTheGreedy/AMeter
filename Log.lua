local _, ns = ...

local Log = {}
ns.Log = Log

local roster = {}
local owners = {}
local current
local overall
local fighting = false

local function newSegment()
	return { types = {}, active = 0, start = nil }
end

local function now()
	return GetTime and GetTime() or 0
end

local function duration(seg)
	local d = seg.active
	if seg.start then d = d + (now() - seg.start) end
	return d
end

local function addUnit(unit, petUnit)
	if not UnitExists or not UnitExists(unit) then return end
	local guid = UnitGUID(unit)
	if not guid or ns.IsSecret(guid) then return end
	local name = UnitName(unit)
	local _, class = UnitClass(unit)
	if ns.IsSecret(name) or ns.IsSecret(class) then return end
	roster[guid] = { name = name, class = class, me = UnitIsUnit and UnitIsUnit(unit, "player") or unit == "player" }
	if UnitExists(petUnit) then
		local pet = UnitGUID(petUnit)
		if pet and not ns.IsSecret(pet) then
			owners[pet] = guid
			local petName = UnitName(petUnit)
			if not ns.IsSecret(petName) then owners[pet .. "name"] = petName end
		end
	end
end

local function scan()
	roster = {}
	owners = {}
	addUnit("player", "pet")
	local raid = IsInRaid and IsInRaid()
	local n = GetNumGroupMembers and GetNumGroupMembers() or 0
	if ns.IsSecret(n) or type(n) ~= "number" then n = 0 end
	if raid then
		for i = 1, n do addUnit("raid" .. i, "raidpet" .. i) end
	else
		for i = 1, math.max(0, n - 1) do addUnit("party" .. i, "partypet" .. i) end
	end
end

local function entry(seg, kind, guid)
	local t = seg.types[kind]
	if not t then
		t = {}
		seg.types[kind] = t
	end
	local e = t[guid]
	if not e then
		local r = roster[guid]
		e = { guid = guid, name = r.name, class = r.class, me = r.me, total = 0, spells = {} }
		t[guid] = e
	end
	return e
end

local function add(kind, guid, amount, spell, spellName, pet)
	if not roster[guid] then return end
	for _, seg in ipairs({ current, overall }) do
		local e = entry(seg, kind, guid)
		e.total = e.total + amount
		local key = pet and (spell .. ":" .. pet) or spell
		local s = e.spells[key]
		if not s then
			s = { spell = spell, name = spellName, pet = pet, total = 0 }
			e.spells[key] = s
		end
		s.total = s.total + amount
	end
end

local function death(guid)
	if not roster[guid] then return end
	for _, seg in ipairs({ current, overall }) do
		local t = seg.types.Deaths
		if not t then
			t = {}
			seg.types.Deaths = t
		end
		local r = roster[guid]
		t[#t + 1] = { guid = guid, name = r.name, class = r.class, me = r.me, total = 1, time = duration(seg), spells = {} }
	end
end

local DAMAGE = {
	RANGE_DAMAGE = true, SPELL_DAMAGE = true, SPELL_PERIODIC_DAMAGE = true,
	DAMAGE_SHIELD = true, SPELL_BUILDING_DAMAGE = true,
}
local HEAL = { SPELL_HEAL = true, SPELL_PERIODIC_HEAL = true }

local function num(v)
	if type(v) ~= "number" or ns.IsSecret(v) then return nil end
	return v
end

local function handle(...)
	local _, sub, _, src, _, _, _, dst, _, _, _, a12, a13, _, a15, a16 = ...
	if ns.IsSecret(sub) or ns.IsSecret(src) or ns.IsSecret(dst) or type(sub) ~= "string" then return end
	local pet
	local owner = src and owners[src]
	if owner then
		pet = owners[src .. "name"]
		src = owner
	end
	if sub == "SWING_DAMAGE" then
		local amount = num(a12)
		if not amount then return end
		if src then add("DamageDone", src, amount, 6603, "Melee", pet) end
		if dst then add("DamageTaken", dst, amount, 6603, "Melee") end
	elseif DAMAGE[sub] then
		local amount = num(a15)
		if not amount or ns.IsSecret(a12) or ns.IsSecret(a13) then return end
		if src then add("DamageDone", src, amount, a12 or 0, a13, pet) end
		if dst then add("DamageTaken", dst, amount, a12 or 0, a13) end
	elseif sub == "ENVIRONMENTAL_DAMAGE" then
		local amount = num(a13)
		if amount and dst and not ns.IsSecret(a12) then add("DamageTaken", dst, amount, 0, tostring(a12 or "Environment")) end
	elseif HEAL[sub] then
		local amount = num(a15)
		if not amount or ns.IsSecret(a12) or ns.IsSecret(a13) then return end
		amount = amount - (num(a16) or 0)
		if amount > 0 and src then add("HealingDone", src, amount, a12 or 0, a13, pet) end
	elseif sub == "SPELL_INTERRUPT" then
		if src and not ns.IsSecret(a15) and not ns.IsSecret(a16) then add("Interrupts", src, 1, a15 or 0, a16, pet) end
	elseif sub == "SPELL_DISPEL" or sub == "SPELL_STOLEN" then
		if src and not ns.IsSecret(a15) and not ns.IsSecret(a16) then add("Dispels", src, 1, a15 or 0, a16, pet) end
	elseif sub == "UNIT_DIED" then
		if dst and not owners[dst] then death(dst) end
	else
		return
	end
	ns.Debounce("log", 0.5, function() ns:Fire("DATA") end)
end

function Log.Exists()
	return CombatLogGetCurrentEventInfo ~= nil
end

local function segment(key)
	if key == "overall" then return overall end
	return current
end

function Log.Session(key, mode)
	local seg = segment(key)
	local out = { rows = {}, duration = duration(seg) }
	local kind = mode.base or mode.type
	local t = seg.types[kind]
	if not t then return out end
	local d = out.duration
	local total = 0
	for _, e in pairs(t) do
		local rate = d > 0 and e.total / d or 0
		out.rows[#out.rows + 1] = {
			name = e.name, guid = e.guid, class = e.class, me = e.me,
			total = e.total, rate = rate, value = mode.rate and rate or e.total,
			time = e.time, entry = e,
		}
		total = total + e.total
	end
	out.total = total
	return out
end

function Log.Spells(key, mode, row)
	local seg = segment(key)
	local out = { rows = {} }
	local e = row.entry
	if not e then return out end
	local d = duration(seg)
	for _, s in pairs(e.spells) do
		local rate = d > 0 and s.total / d or 0
		out.rows[#out.rows + 1] = {
			spell = s.spell, spellName = s.name, pet = s.pet,
			total = s.total, rate = rate, value = mode.rate and rate or s.total,
		}
	end
	out.total = e.total
	return out
end

function Log.Reset()
	current = newSegment()
	overall = newSegment()
	if fighting then
		current.start = now()
		overall.start = now()
	end
	ns:Fire("DATA")
end

function Log.Start()
	current = newSegment()
	overall = newSegment()
	scan()
	ns:On("GROUP_ROSTER_UPDATE", scan)
	ns:On("UNIT_PET", scan)
	ns:On("PLAYER_ENTERING_WORLD", scan)
	ns:On("PLAYER_REGEN_DISABLED", function()
		fighting = true
		current = newSegment()
		current.start = now()
		overall.start = now()
		ns:Fire("DATA")
	end)
	ns:On("PLAYER_REGEN_ENABLED", function()
		fighting = false
		for _, seg in ipairs({ current, overall }) do
			if seg.start then
				seg.active = seg.active + (now() - seg.start)
				seg.start = nil
			end
		end
		ns:Fire("DATA")
	end)
	ns:On("COMBAT_LOG_EVENT_UNFILTERED", function()
		local ok, err = pcall(function() handle(CombatLogGetCurrentEventInfo()) end)
		if not ok and ns.debug then ns.Print(err) end
	end)
end
