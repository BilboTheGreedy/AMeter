local ADDON, ns = ...

local defaults = {
	scale = 1,
	shown = true,
	locked = false,
	mode = "damage",
	segment = "current",
	rows = 8,
	width = 250,
	autoreset = true,
	default = { "RIGHT", "RIGHT", -60, -120 },
}

ACore.New(ADDON, ns, { db = "AMeterDB", defaults = defaults, profile = true })

ns.MODES = {
	{ key = "damage", title = "Damage", type = "DamageDone", both = true },
	{ key = "dps", title = "DPS", type = "Dps", base = "DamageDone", rate = true },
	{ key = "healing", title = "Healing", type = "HealingDone", both = true },
	{ key = "hps", title = "HPS", type = "Hps", base = "HealingDone", rate = true },
	{ key = "taken", title = "Damage taken", type = "DamageTaken" },
	{ key = "interrupts", title = "Interrupts", type = "Interrupts", count = true },
	{ key = "dispels", title = "Dispels", type = "Dispels", count = true },
	{ key = "deaths", title = "Deaths", type = "Deaths", deaths = true },
}

ns.SEGMENTS = {
	{ key = "current", title = "Current fight" },
	{ key = "overall", title = "Overall" },
}

function ns.Mode(key)
	for _, m in ipairs(ns.MODES) do
		if m.key == key then return m end
	end
	return ns.MODES[1]
end

function ns.SegmentTitle(key)
	for _, s in ipairs(ns.SEGMENTS) do
		if s.key == key then return s.title end
	end
	return ns.SEGMENTS[1].title
end

function ns.Number(v)
	if type(v) == "nil" then return "" end
	if ns.IsSecret(v) then
		if AbbreviateNumbers then
			local ok, s = pcall(AbbreviateNumbers, v)
			if ok and type(s) ~= "nil" then return s end
		end
		local ok, s = pcall(string.format, "%.0f", v)
		if ok then return s end
		return ""
	end
	if type(v) ~= "number" then return "" end
	return ACore.Short(v)
end

function ns.Clock(seconds)
	if type(seconds) ~= "number" or ns.IsSecret(seconds) then return "" end
	seconds = math.floor(seconds + 0.5)
	return string.format("%d:%02d", math.floor(seconds / 60), seconds % 60)
end

ACore.Register({
	name = "AMeter",
	title = "AMeter",
	slash = "/ameter",
	desc = "damage and healing meter",
	toggle = function() ns.UI.Toggle() end,
})

SLASH_AMETER1 = "/ameter"
SLASH_AMETER2 = "/am"
SlashCmdList["AMETER"] = function(msg)
	msg = (msg or ""):lower():gsub("^%s+", ""):gsub("%s+$", "")
	if msg == "" then
		ns.UI.Toggle()
	elseif msg == "reset" then
		ns.Data.Reset()
	elseif msg == "lock" then
		ns.db.locked = not ns.db.locked
		ns.Print(ns.db.locked and "locked" or "unlocked")
	elseif msg == "pos" then
		ns.db.pos = nil
		ns.db.scale = 1
		ns:Fire("LAYOUT_RESET")
	else
		for _, m in ipairs(ns.MODES) do
			if m.key == msg or m.title:lower() == msg then
				ns.db.mode = m.key
				ns.UI.Show()
				ns:Fire("VIEW_CHANGED")
				return
			end
		end
		ns.Print("/ameter, /ameter reset, /ameter lock, /ameter pos, /ameter <mode>")
	end
end

BINDING_HEADER_AMETER = "AMeter"
BINDING_NAME_AMETER_TOGGLE = "Toggle AMeter"
function AMeter_ToggleBinding()
	ns.UI.Toggle()
end
