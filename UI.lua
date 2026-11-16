local _, ns = ...
local UI = ns.UI
local C = UI.colors
local Data = ns.Data

local HEAD = 22
local ROW = 18
local SPELL_COLOR = { 0.35, 0.55, 0.85 }
local PLAIN_COLOR = { 0.5, 0.52, 0.6 }

local frame
local view = { rows = {} }
local state = { detail = nil }

local function mode()
	return ns.Mode(ns.db.mode)
end

local function has(v)
	return type(v) ~= "nil"
end

local function fmt(pattern, ...)
	local ok, s = pcall(string.format, pattern, ...)
	if ok then return s end
	return nil
end

local function spellName(d)
	local name = d.spellName
	if not name and has(d.spell) and C_Spell and C_Spell.GetSpellName then
		local ok, n = pcall(C_Spell.GetSpellName, d.spell)
		if ok and has(n) then name = n end
	end
	if not has(name) then name = "Unknown" end
	if d.pet then
		return fmt("%s (%s)", name, d.pet) or name
	end
	return name
end

local function label(d)
	if has(d.spell) or d.spellName then return spellName(d) end
	if not has(d.name) then return "Unknown" end
	return d.name
end

local function valueText(d, m, out)
	if m.deaths and not state.detail then
		return ns.Clock(d.time)
	end
	if m.count then
		return ns.Number(d.total)
	end
	if m.rate then
		return ns.Number(d.value)
	end
	if m.both and has(d.rate) then
		return fmt("%s (%s)", ns.Number(d.total), ns.Number(d.rate)) or ns.Number(d.total)
	end
	local text = ns.Number(d.value)
	if not out.secret and type(out.total) == "number" and out.total > 0 and type(d.value) == "number" then
		return string.format("%s  %d%%", text, math.floor(d.value / out.total * 100 + 0.5))
	end
	return text
end

local function rowColor(d)
	if d.kind == "note" then return 0, 0, 0, 0 end
	if has(d.spell) or d.spellName then return SPELL_COLOR[1], SPELL_COLOR[2], SPELL_COLOR[3], 0.8 end
	local c = d.class and RAID_CLASS_COLORS and RAID_CLASS_COLORS[d.class]
	if c then return c.r, c.g, c.b, 0.8 end
	return PLAIN_COLOR[1], PLAIN_COLOR[2], PLAIN_COLOR[3], 0.8
end

local function openDetail(d)
	local m = mode()
	if m.deaths or d.kind == "note" or has(d.spell) or d.spellName then return end
	state.detail = d
	UI.Refresh()
end

local function closeDetail()
	state.detail = nil
	UI.Refresh()
end

local function report(channel)
	local m = mode()
	if view.secret then
		ns.Print("numbers are hidden during combat, report after the fight")
		return
	end
	local lines = {}
	local head = "AMeter: " .. m.title .. ", " .. ns.SegmentTitle(ns.db.segment)
	if state.detail and type(state.detail.name) == "string" and not ns.IsSecret(state.detail.name) then
		head = head .. ", " .. state.detail.name
	end
	local clock = ns.Clock(view.duration)
	if clock ~= "" then head = head .. " (" .. clock .. ")" end
	lines[1] = head
	for i, d in ipairs(view.rows) do
		if i > 10 or d.kind == "note" then break end
		local name = label(d)
		local text = valueText(d, m, view)
		if type(name) == "string" and type(text) == "string" and not ns.IsSecret(name) and not ns.IsSecret(text) then
			lines[#lines + 1] = i .. ". " .. name .. "  " .. text
		end
	end
	if #lines == 1 then
		ns.Print("nothing to report")
		return
	end
	local send = (C_ChatInfo and C_ChatInfo.SendChatMessage) or SendChatMessage
	if not send then return end
	for _, line in ipairs(lines) do
		local ok = pcall(send, line, channel)
		if not ok then
			ns.Print("could not send to " .. channel:lower())
			return
		end
	end
end

local function resize()
	if not frame then return end
	frame:SetSize(ns.db.width, HEAD + ns.db.rows * ROW + 2)
	frame.list:Refresh()
end

local function modeMenu(anchor)
	local entries = { { text = "Show", title = true } }
	for _, m in ipairs(ns.MODES) do
		if Data.Supports(m) then
			entries[#entries + 1] = {
				text = m.title, checked = ns.db.mode == m.key,
				func = function()
					ns.db.mode = m.key
					state.detail = nil
					UI.Refresh()
				end,
			}
		end
	end
	entries[#entries + 1] = { text = "Fight", title = true }
	for _, s in ipairs(ns.SEGMENTS) do
		entries[#entries + 1] = {
			text = s.title, checked = ns.db.segment == s.key,
			func = function()
				ns.db.segment = s.key
				state.detail = nil
				UI.Refresh()
			end,
		}
	end
	UI.Menu(anchor, entries)
end

local function gearMenu(anchor)
	local db = ns.db
	local entries = {
		{ text = "Reset data", func = function() Data.Reset() end },
		{ text = "Report to", title = true },
		{ text = "Say", func = function() report("SAY") end },
		{ text = "Party", func = function() report("PARTY") end },
		{ text = "Raid", func = function() report("RAID") end },
		{ text = "Guild", func = function() report("GUILD") end },
		{ text = "Options", title = true },
		ACore.UI.Toggle(db, "locked", "Lock position"),
		ACore.UI.Toggle(db, "autoreset", "Reset when entering an instance"),
		{ text = "Rows", title = true },
	}
	for _, n in ipairs({ 5, 8, 10, 15 }) do
		entries[#entries + 1] = {
			text = tostring(n), checked = db.rows == n,
			func = function()
				db.rows = n
				resize()
			end,
		}
	end
	for _, e in ipairs(UI.ScaleEntries(db, function(s) frame:SetScale(s) end)) do
		entries[#entries + 1] = e
	end
	entries[#entries + 1] = { text = "Hide AMeter", func = function() UI.Hide() end }
	UI.Menu(anchor, entries)
end

local function showTooltip(bar)
	local d = bar.data
	if not d or d.kind == "note" or not GameTooltip then return end
	local m = mode()
	GameTooltip:SetOwner(bar, "ANCHOR_LEFT")
	GameTooltip:AddLine(label(d), 1, 0.82, 0)
	if has(d.total) and not m.deaths then
		GameTooltip:AddDoubleLine(m.count and "Count" or "Total", ns.Number(d.total), 0.9, 0.9, 0.92, 1, 1, 1)
	end
	if has(d.rate) and not m.count and not m.deaths then
		GameTooltip:AddDoubleLine("Per second", ns.Number(d.rate), 0.9, 0.9, 0.92, 1, 1, 1)
	end
	if m.deaths and not state.detail then
		GameTooltip:AddDoubleLine("Died at", ns.Clock(d.time), 0.9, 0.9, 0.92, 1, 1, 1)
	end
	if state.detail then
		GameTooltip:AddLine("Click to go back", 0.58, 0.6, 0.65)
	elseif not m.deaths then
		GameTooltip:AddLine("Click for spells, right-click for the menu", 0.58, 0.6, 0.65)
	end
	GameTooltip:Show()
end

local function createRow(list)
	local bar = UI.Bar(list, ROW)
	bar:EnableMouse(true)
	bar:SetScript("OnMouseUp", function(self, button)
		local d = self.data
		if state.detail then
			closeDetail()
		elseif button == "RightButton" then
			gearMenu(self)
		elseif d then
			openDetail(d)
		end
	end)
	bar:SetScript("OnEnter", function(self)
		list.hovered = self
		showTooltip(self)
	end)
	bar:SetScript("OnLeave", function()
		list.hovered = nil
		if GameTooltip then GameTooltip:Hide() end
	end)
	return bar
end

local function updateRow(bar, d)
	local m = mode()
	local r, g, b, a = rowColor(d)
	bar:SetColor(r, g, b, a)
	if d.kind == "note" then
		bar:SetMinMaxValues(0, 1)
		bar:SetValue(0)
		bar.left:SetText(d.text)
		bar.left:SetTextColor(C.dim[1], C.dim[2], C.dim[3])
		bar.right:SetText("")
		return
	end
	if d.me then
		bar.left:SetTextColor(C.accent[1], C.accent[2], C.accent[3])
	else
		bar.left:SetTextColor(C.text[1], C.text[2], C.text[3])
	end
	local max, value = view.max, d.value
	if not has(max) then max = 1 end
	if not has(value) then value = 0 end
	local okRange = pcall(bar.SetMinMaxValues, bar, 0, max)
	if not okRange then bar:SetMinMaxValues(0, 1) end
	local okValue = pcall(bar.SetValue, bar, value)
	if not okValue then bar:SetValue(0) end
	local name = label(d)
	local text = fmt("%d. %s", d.rank or 0, name)
	if not has(text) then text = name end
	pcall(bar.left.SetText, bar.left, text)
	pcall(bar.right.SetText, bar.right, valueText(d, m, view))
end

local function build()
	local db = ns.db
	frame = CreateFrame("Frame", "AMeterFrame", UIParent)
	frame:SetFrameStrata("MEDIUM")
	frame:EnableMouse(true)
	UI.Fill(frame, { C.bg[1], C.bg[2], C.bg[3], 0.85 })
	UI.Border(frame)
	UI.Movable(frame, db)

	local head = CreateFrame("Frame", nil, frame)
	head:SetPoint("TOPLEFT")
	head:SetPoint("TOPRIGHT")
	head:SetHeight(HEAD)
	head:EnableMouse(true)
	head:RegisterForDrag("LeftButton")
	head:SetScript("OnDragStart", function() frame:StartDrag() end)
	head:SetScript("OnDragStop", function() frame:StopDrag() end)
	head:SetScript("OnMouseUp", function(self, button)
		if button == "RightButton" then gearMenu(self) end
	end)
	UI.Fill(head, C.bar)

	local gear = UI.Button(head, "...", function(self) gearMenu(self) end)
	gear:SetHeight(18)
	gear:SetWidth(24)
	gear:SetPoint("RIGHT", -2, 0)

	local reset = UI.Button(head, "Reset", function() Data.Reset() end)
	reset:SetHeight(18)
	reset:SetPoint("RIGHT", gear, "LEFT", -2, 0)

	local seg = UI.Button(head, "Current", function()
		ns.db.segment = ns.db.segment == "current" and "overall" or "current"
		state.detail = nil
		UI.Refresh()
	end)
	seg:SetHeight(18)
	seg:SetPoint("RIGHT", reset, "LEFT", -2, 0)
	frame.segButton = seg

	local title = CreateFrame("Button", nil, head)
	title:SetPoint("TOPLEFT")
	title:SetPoint("BOTTOMLEFT")
	title:SetPoint("RIGHT", seg, "LEFT", -4, 0)
	title:RegisterForClicks("LeftButtonUp", "RightButtonUp")
	title:RegisterForDrag("LeftButton")
	title:SetScript("OnDragStart", function() frame:StartDrag() end)
	title:SetScript("OnDragStop", function() frame:StopDrag() end)
	title.text = UI.Text(title, "GameFontNormalSmall", "LEFT", C.accent)
	title.text:SetPoint("LEFT", 6, 0)
	title.text:SetPoint("RIGHT", 0, 0)
	title:SetScript("OnClick", function(self, button)
		if state.detail then
			closeDetail()
		elseif button == "RightButton" then
			gearMenu(self)
		else
			modeMenu(self)
		end
	end)
	frame.titleButton = title

	local list = UI.List(frame, ROW, createRow, updateRow)
	list:SetPoint("TOPLEFT", 1, -HEAD)
	list:SetPoint("BOTTOMRIGHT", -1, 1)
	frame.list = list

	local elapsed = 0
	frame:SetScript("OnUpdate", function(_, dt)
		elapsed = elapsed + (dt or 0)
		if elapsed < 1 then return end
		elapsed = 0
		UI.Refresh(true)
	end)

	resize()
end

function UI.Refresh(keep)
	if not frame or not frame:IsShown() then return end
	local m = mode()
	if not Data.Supports(m) then
		ns.db.mode = ns.MODES[1].key
		m = mode()
	end
	local out
	local status = Data.Status()
	if status then
		out = { rows = { { kind = "note", text = status } } }
	elseif state.detail then
		out = Data.Spells(ns.db.segment, m, state.detail)
		if #out.rows == 0 then
			out.rows[1] = { kind = "note", text = "No spell details" }
		end
	else
		out = Data.Session(ns.db.segment, m)
		if #out.rows == 0 then
			out.rows[1] = { kind = "note", text = "No data yet" }
		end
	end
	view = out

	local title
	if state.detail then
		title = fmt("< %s", label(state.detail)) or "< Back"
	else
		title = m.title
		local clock = ns.Clock(out.duration)
		if clock ~= "" then title = title .. "  " .. clock end
	end
	pcall(frame.titleButton.text.SetText, frame.titleButton.text, title)
	frame.segButton:SetLabel(ns.db.segment == "overall" and "Overall" or "Current")
	frame.segButton:SetActive(ns.db.segment == "overall")
	frame.list:SetData(out.rows, keep)
end

function UI.Show()
	if not ns.db then return end
	if not frame then build() end
	ns.db.shown = true
	frame:Show()
	UI.Refresh()
end

function UI.Hide()
	if not ns.db then return end
	ns.db.shown = false
	if frame then frame:Hide() end
end

function UI.Toggle()
	if frame and frame:IsShown() then
		UI.Hide()
	else
		UI.Show()
	end
end

ns:Listen("LOGIN", function()
	if ns.db.shown then UI.Show() end
end)

ns:Listen("DATA", function()
	ns.Debounce("refresh", 0.2, function() UI.Refresh(true) end)
end)

ns:Listen("VIEW_CHANGED", function()
	state.detail = nil
	UI.Refresh()
end)

ns:Listen("LAYOUT_RESET", function()
	if frame then frame:Restore() end
end)
