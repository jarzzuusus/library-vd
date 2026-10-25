--[[
	SourceHubUI - UI library (tema merah/hitam)
	Isinya cuma UI. Nggak ada logic game, HTTP, atau scan.

	API:
		local Library = loadstring(readfile("SourceHubUI.lua"))()
		local Window = Library:CreateWindow({ Title, Author, Size, Parent, Name, ToggleKey })

		Window:AddTab(name)                 -> Tab
		Window:SelectTab(tabOrNameOrIndex)
		Window:SetStatus(text, color3?)
		Window:SetVisible(bool) / Window:Toggle()
		Window:Destroy()

		Tab:AddSection(text)
		Tab:AddLabel(text)                  -> { Set(text) }
		Tab:AddButton({ Name, Callback })
		Tab:AddToggle({ Name, Default, Callback })                         -> { Set, Get }
		Tab:AddSlider({ Name, Min, Max, Default, Increment, Suffix, Callback }) -> { Set, Get }
		Tab:AddDropdown({ Name, Options, Default, Multi, Callback })       -> { Set, Get, Refresh }
]]

local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")

local Library = {}
Library.__index = Library

local Window = {}
Window.__index = Window

local Tab = {}
Tab.__index = Tab

-- ===== Theme =====
local WHITE = Color3.fromRGB(255, 255, 255)
local ACCENT_HI = Color3.fromRGB(255, 70, 80)
local ACCENT = Color3.fromRGB(235, 35, 50)
local ACCENT_DARK = Color3.fromRGB(120, 10, 22)
local ACCENT_DEEP = Color3.fromRGB(60, 6, 12)
local SUB_TEXT = Color3.fromRGB(175, 150, 152)
local MUTED = Color3.fromRGB(130, 95, 98)
local TRACK_OFF = Color3.fromRGB(38, 24, 26)
local DARK0 = Color3.fromRGB(44, 10, 15)
local DARK1 = Color3.fromRGB(14, 8, 9)

local FONT_BOLD = Enum.Font.GothamBold
local FONT_MED = Enum.Font.GothamMedium
local TWEEN = TweenInfo.new(0.15, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)

-- ===== Helpers =====
local function new(class, props, parent)
	local inst = Instance.new(class)
	for k, v in pairs(props) do
		inst[k] = v
	end
	if parent then
		inst.Parent = parent
	end
	return inst
end

local function corner(parent, radius)
	return new("UICorner", { CornerRadius = UDim.new(0, radius) }, parent)
end

local function stroke(parent, color, thickness, transparency)
	return new("UIStroke", {
		Color = color,
		Thickness = thickness or 1,
		Transparency = transparency or 0,
		ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
	}, parent)
end

local function gradient(parent, c0, c1, rotation)
	return new("UIGradient", {
		Color = ColorSequence.new(c0, c1),
		Rotation = rotation or 0,
	}, parent)
end

local function accentStroke(parent, thickness, transparency)
	local s = stroke(parent, WHITE, thickness, transparency)
	gradient(s, ACCENT_HI, ACCENT_DARK, 90)
	return s
end

local function label(parent, text, size, font, color, pos, sz, alignX)
	return new("TextLabel", {
		BackgroundTransparency = 1,
		Text = text,
		TextSize = size,
		Font = font,
		TextColor3 = color,
		Position = pos,
		Size = sz,
		TextXAlignment = alignX or Enum.TextXAlignment.Left,
		TextYAlignment = Enum.TextYAlignment.Center,
	}, parent)
end

local function button(parent, o)
	local bg = new("Frame", {
		AnchorPoint = o.anchor or Vector2.new(0, 0),
		Position = o.pos,
		Size = o.size,
		BackgroundColor3 = WHITE,
		BackgroundTransparency = o.bgTransparency or 0,
		BorderSizePixel = 0,
	}, parent)
	corner(bg, o.radius or 8)
	local grad = gradient(bg, o.c0, o.c1, o.rotation or 90)
	local st
	if o.strokeColor then
		st = stroke(bg, o.strokeColor, o.strokeThickness or 1.2, o.strokeTransparency or 0)
	end
	local btn = new("TextButton", {
		AutoButtonColor = false,
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		Text = o.text,
		TextSize = o.textSize or 12,
		Font = FONT_BOLD,
		TextColor3 = o.textColor or WHITE,
		BorderSizePixel = 0,
	}, bg)
	return btn, bg, grad, st
end

local function makeCard(parent, height, order)
	local card = new("Frame", {
		LayoutOrder = order,
		Size = UDim2.new(1, 0, 0, height),
		BackgroundColor3 = WHITE,
		BackgroundTransparency = 0.05,
		BorderSizePixel = 0,
		ClipsDescendants = true,
	}, parent)
	corner(card, 10)
	gradient(card, Color3.fromRGB(46, 9, 15), Color3.fromRGB(12, 9, 10), 0)
	accentStroke(card, 1.2, 0.2)
	return card
end

local function fire(cb, ...)
	if type(cb) ~= "function" then
		return
	end
	local args = table.pack(...)
	task.spawn(function()
		local ok, err = pcall(cb, table.unpack(args, 1, args.n))
		if not ok then
			warn("[SourceHubUI] callback error:", err)
		end
	end)
end

local function isPress(input)
	return input.UserInputType == Enum.UserInputType.MouseButton1
		or input.UserInputType == Enum.UserInputType.Touch
end

local function isMove(input)
	return input.UserInputType == Enum.UserInputType.MouseMovement
		or input.UserInputType == Enum.UserInputType.Touch
end

-- ===== Window =====
function Library:CreateWindow(opts)
	opts = opts or {}
	local self = setmetatable({}, Window)
	self.Tabs = {}
	self.ActiveTab = nil
	self._conns = {}

	local title = opts.Title or "Source Hub"
	local author = opts.Author
	local guiName = opts.Name or "SourceHubUI"
	local parent = opts.Parent or Players.LocalPlayer:WaitForChild("PlayerGui")
	local size = opts.Size or Vector2.new(800, 502)

	local old = parent:FindFirstChild(guiName)
	if old then
		old:Destroy()
	end

	local gui = new("ScreenGui", {
		Name = guiName,
		ResetOnSpawn = false,
		ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
		IgnoreGuiInset = true,
	}, parent)
	self.Gui = gui

	local main = new("Frame", {
		Name = "Main",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(size.X, size.Y),
		BackgroundColor3 = WHITE,
		BackgroundTransparency = 0.06,
		BorderSizePixel = 0,
		ClipsDescendants = true,
	}, gui)
	corner(main, 14)
	accentStroke(main, 1.6, 0)
	new("UIGradient", {
		Color = ColorSequence.new({
			ColorSequenceKeypoint.new(0, Color3.fromRGB(52, 8, 16)),
			ColorSequenceKeypoint.new(0.45, Color3.fromRGB(14, 8, 10)),
			ColorSequenceKeypoint.new(1, Color3.fromRGB(4, 4, 5)),
		}),
		Rotation = 35,
	}, main)
	local uiScale = new("UIScale", { Scale = 1 }, main)
	self.Main = main

	-- ===== Sidebar =====
	local sidebar = new("Frame", {
		Name = "Sidebar",
		Size = UDim2.new(0, 160, 1, 0),
		BackgroundColor3 = WHITE,
		BorderSizePixel = 0,
	}, main)
	gradient(sidebar, Color3.fromRGB(8, 6, 7), Color3.fromRGB(58, 8, 17), 90)
	corner(sidebar, 14)
	local sidebarFill = new("Frame", {
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, 0, 0, 0),
		Size = UDim2.new(0, 20, 1, 0),
		BackgroundColor3 = WHITE,
		BorderSizePixel = 0,
	}, sidebar)
	gradient(sidebarFill, Color3.fromRGB(8, 6, 7), Color3.fromRGB(58, 8, 17), 90)

	local divider = new("Frame", {
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, 0, 0, 0),
		Size = UDim2.new(0, 1, 1, 0),
		BackgroundColor3 = WHITE,
		BorderSizePixel = 0,
	}, sidebar)
	gradient(divider, ACCENT_HI, ACCENT_DARK, 90)

	local titleLabel = label(sidebar, title, 13, FONT_BOLD, WHITE,
		UDim2.fromOffset(12, 20), UDim2.fromOffset(146, 20))
	gradient(titleLabel, WHITE, ACCENT_HI, 0)

	local statusDot = new("Frame", {
		Position = UDim2.fromOffset(16, 56),
		Size = UDim2.fromOffset(6, 6),
		BackgroundColor3 = ACCENT_HI,
		BorderSizePixel = 0,
	}, sidebar)
	corner(statusDot, 3)
	local statusLabel = label(sidebar, "Ready", 9, FONT_MED, SUB_TEXT,
		UDim2.fromOffset(28, 51), UDim2.fromOffset(120, 16))
	self._statusDot, self._statusLabel = statusDot, statusLabel

	-- tab list
	local tabList = new("ScrollingFrame", {
		Position = UDim2.fromOffset(8, 76),
		Size = UDim2.new(1, -16, 1, -222),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		ScrollBarThickness = 2,
		ScrollBarImageColor3 = ACCENT,
		CanvasSize = UDim2.new(),
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
	}, sidebar)
	new("UIListLayout", {
		Padding = UDim.new(0, 6),
		SortOrder = Enum.SortOrder.LayoutOrder,
	}, tabList)
	self._tabList = tabList

	if author then
		local authorLabel = label(sidebar, "Author: " .. author, 10, FONT_BOLD, SUB_TEXT,
			UDim2.new(0, 12, 1, -138), UDim2.fromOffset(142, 18))
		gradient(authorLabel, WHITE, ACCENT_HI, 0)
	end

	-- zoom
	local W_MIN, H_MIN, MARGIN = 640, 300, 8
	local W_MAX, H_MAX = size.X, size.Y
	local userScale = 1

	local zoomOut = button(sidebar, {
		text = "-", textSize = 16,
		anchor = Vector2.new(0, 1),
		pos = UDim2.new(0, 8, 1, -67),
		size = UDim2.fromOffset(40, 28),
		c0 = DARK0, c1 = DARK1,
		strokeColor = ACCENT, strokeTransparency = 0.25, radius = 8,
	})
	local zoomLabel = label(sidebar, "100%", 10, FONT_BOLD, WHITE,
		UDim2.new(0, 52, 1, -95), UDim2.fromOffset(58, 28), Enum.TextXAlignment.Center)
	local zoomIn = button(sidebar, {
		text = "+", textSize = 16,
		anchor = Vector2.new(0, 1),
		pos = UDim2.new(0, 114, 1, -67),
		size = UDim2.fromOffset(40, 28),
		c0 = DARK0, c1 = DARK1,
		strokeColor = ACCENT, strokeTransparency = 0.25, radius = 8,
	})

	local function applyLayout()
		local vp = gui.AbsoluteSize
		if vp.X <= 0 or vp.Y <= 0 then
			return
		end
		local cap = math.min((vp.X - MARGIN * 2) / W_MIN, (vp.Y - MARGIN * 2) / H_MIN)
		local s = math.max(0.3, math.min(userScale, cap))
		uiScale.Scale = s
		main.Size = UDim2.fromOffset(
			math.clamp((vp.X - MARGIN * 2) / s, W_MIN, W_MAX),
			math.clamp((vp.Y - MARGIN * 2) / s, H_MIN, H_MAX))
		zoomLabel.Text = math.floor(s * 100 + 0.5) .. "%"
	end

	local function stepZoom(d)
		userScale = math.clamp(math.floor((uiScale.Scale + d) * 10 + 0.5) / 10, 0.4, 1.6)
		applyLayout()
	end

	zoomOut.MouseButton1Click:Connect(function() stepZoom(-0.1) end)
	zoomIn.MouseButton1Click:Connect(function() stepZoom(0.1) end)
	gui:GetPropertyChangedSignal("AbsoluteSize"):Connect(applyLayout)
	applyLayout()

	-- hide / show
	local hideBtn = button(sidebar, {
		text = "Hide", textSize = 12,
		anchor = Vector2.new(0, 1),
		pos = UDim2.new(0, 11, 1, -23),
		size = UDim2.fromOffset(138, 36),
		c0 = DARK0, c1 = DARK1,
		strokeColor = ACCENT, strokeTransparency = 0.25, radius = 10,
	})

	local showBtn, showBg = button(gui, {
		text = title, textSize = 12,
		anchor = Vector2.new(0.5, 0),
		pos = UDim2.new(0.5, 0, 0, 12),
		size = UDim2.fromOffset(150, 30),
		c0 = Color3.fromRGB(60, 10, 17), c1 = Color3.fromRGB(12, 8, 9),
		strokeColor = ACCENT, strokeTransparency = 0.15, radius = 10,
	})
	showBg.Visible = false
	self._showBg = showBg

	hideBtn.MouseButton1Click:Connect(function() self:SetVisible(false) end)
	showBtn.MouseButton1Click:Connect(function() self:SetVisible(true) end)

	-- drag (dari sidebar saja, biar slider nggak narik window)
	do
		local dragging, dragStart, startPos
		self:_connect(sidebar.InputBegan, function(input)
			if isPress(input) then
				dragging = true
				dragStart = input.Position
				startPos = main.Position
			end
		end)
		self:_connect(UserInputService.InputChanged, function(input)
			if dragging and isMove(input) then
				local d = input.Position - dragStart
				main.Position = UDim2.new(startPos.X.Scale, startPos.X.Offset + d.X,
					startPos.Y.Scale, startPos.Y.Offset + d.Y)
			end
		end)
		self:_connect(UserInputService.InputEnded, function(input)
			if isPress(input) then
				dragging = false
			end
		end)
	end

	if opts.ToggleKey then
		self:_connect(UserInputService.InputBegan, function(input, processed)
			if not processed and input.KeyCode == opts.ToggleKey then
				self:Toggle()
			end
		end)
	end

	-- content
	self.Content = new("Frame", {
		Name = "Content",
		Position = UDim2.fromOffset(182, 0),
		Size = UDim2.new(1, -182, 1, 0),
		BackgroundTransparency = 1,
	}, main)

	return self
end

function Window:_connect(signal, fn)
	local c = signal:Connect(fn)
	table.insert(self._conns, c)
	return c
end

function Window:SetStatus(text, color)
	self._statusLabel.Text = tostring(text)
	self._statusDot.BackgroundColor3 = color or ACCENT_HI
end

function Window:SetVisible(v)
	self.Main.Visible = v
	self._showBg.Visible = not v
end

function Window:Toggle()
	self:SetVisible(not self.Main.Visible)
end

function Window:Destroy()
	for _, c in ipairs(self._conns) do
		c:Disconnect()
	end
	table.clear(self._conns)
	self.Gui:Destroy()
end

function Window:SelectTab(t)
	local target = t
	if type(t) == "string" then
		target = nil
		for _, tab in ipairs(self.Tabs) do
			if tab.Name == t then
				target = tab
				break
			end
		end
	elseif type(t) == "number" then
		target = self.Tabs[t]
	end
	if not target then
		return
	end
	for _, tab in ipairs(self.Tabs) do
		local on = tab == target
		tab.Page.Visible = on
		tab:_style(on)
	end
	self.ActiveTab = target
end

function Window:AddTab(name)
	local tab = setmetatable({ Window = self, Name = name, _n = 0 }, Tab)

	local btn, bg, grad, st = button(self._tabList, {
		text = name, textSize = 12,
		pos = UDim2.new(),
		size = UDim2.new(1, 0, 0, 38),
		c0 = DARK0, c1 = DARK1, rotation = 0,
		strokeColor = ACCENT, strokeTransparency = 0.25, radius = 10,
	})
	bg.LayoutOrder = #self.Tabs + 1
	tab._grad, tab._stroke = grad, st

	local page = new("ScrollingFrame", {
		Name = name,
		Position = UDim2.fromOffset(0, 16),
		Size = UDim2.new(1, -2, 1, -32),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		ScrollBarThickness = 3,
		ScrollBarImageColor3 = ACCENT,
		CanvasSize = UDim2.new(),
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		Visible = false,
	}, self.Content)
	new("UIListLayout", {
		Padding = UDim.new(0, 8),
		SortOrder = Enum.SortOrder.LayoutOrder,
	}, page)
	new("UIPadding", { PaddingRight = UDim.new(0, 8) }, page)
	tab.Page = page
	tab.Button = btn

	btn.MouseButton1Click:Connect(function()
		self:SelectTab(tab)
	end)

	table.insert(self.Tabs, tab)
	tab:_style(false)
	if #self.Tabs == 1 then
		self:SelectTab(tab)
	end
	return tab
end

-- ===== Tab =====
function Tab:_order()
	self._n += 1
	return self._n
end

function Tab:_style(on)
	if on then
		self._grad.Color = ColorSequence.new(ACCENT, ACCENT_DARK)
		if self._stroke then
			self._stroke.Color = ACCENT_HI
			self._stroke.Transparency = 0.1
		end
	else
		self._grad.Color = ColorSequence.new(DARK0, DARK1)
		if self._stroke then
			self._stroke.Color = ACCENT
			self._stroke.Transparency = 0.25
		end
	end
end

function Tab:AddSection(text)
	local lbl = label(self.Page, string.upper(tostring(text)), 9, FONT_BOLD, ACCENT_HI,
		UDim2.new(), UDim2.new(1, 0, 0, 16))
	lbl.LayoutOrder = self:_order()
	return { Instance = lbl, Set = function(_, t) lbl.Text = string.upper(tostring(t)) end }
end

function Tab:AddLabel(text)
	local lbl = label(self.Page, tostring(text), 11, FONT_MED, SUB_TEXT,
		UDim2.new(), UDim2.new(1, 0, 0, 20))
	lbl.LayoutOrder = self:_order()
	lbl.TextWrapped = true
	local obj = { Instance = lbl }
	function obj:Set(t)
		lbl.Text = tostring(t)
	end
	return obj
end

function Tab:AddButton(opts)
	opts = opts or {}
	local card = makeCard(self.Page, 46, self:_order())
	local btn = button(card, {
		text = opts.Name or "Button", textSize = 12,
		pos = UDim2.fromOffset(6, 6),
		size = UDim2.new(1, -12, 1, -12),
		c0 = ACCENT, c1 = ACCENT_DARK, rotation = 0,
		strokeColor = ACCENT_HI, strokeTransparency = 0.2, radius = 8,
	})
	btn.MouseButton1Click:Connect(function()
		fire(opts.Callback)
	end)
	return { Instance = card }
end

function Tab:AddToggle(opts)
	opts = opts or {}
	local callback = opts.Callback
	local card = makeCard(self.Page, 46, self:_order())

	label(card, opts.Name or "Toggle", 12, FONT_BOLD, WHITE,
		UDim2.fromOffset(14, 0), UDim2.new(1, -90, 1, 0))

	local track = new("TextButton", {
		AutoButtonColor = false,
		Text = "",
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, -12, 0.5, 0),
		Size = UDim2.fromOffset(48, 26),
		BackgroundColor3 = TRACK_OFF,
		BorderSizePixel = 0,
	}, card)
	corner(track, 13)
	stroke(track, ACCENT_DARK, 1, 0.2)
	gradient(track, WHITE, Color3.fromRGB(165, 165, 165), 90)

	local knob = new("Frame", {
		AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.new(0, 4, 0.5, 0),
		Size = UDim2.fromOffset(20, 20),
		BackgroundColor3 = WHITE,
		BorderSizePixel = 0,
	}, track)
	corner(knob, 10)

	local obj = { Instance = card, Value = false }

	local function render(v, instant)
		local info = instant and TweenInfo.new(0) or TWEEN
		TweenService:Create(knob, info, {
			Position = v and UDim2.new(1, -24, 0.5, 0) or UDim2.new(0, 4, 0.5, 0),
		}):Play()
		TweenService:Create(track, info, {
			BackgroundColor3 = v and ACCENT or TRACK_OFF,
		}):Play()
	end

	function obj:Set(v, silent)
		v = v and true or false
		if v == self.Value then
			return
		end
		self.Value = v
		render(v)
		if not silent then
			fire(callback, v)
		end
	end

	function obj:Get()
		return self.Value
	end

	if opts.Default then
		obj.Value = true
		render(true, true)
	end

	track.MouseButton1Click:Connect(function()
		obj:Set(not obj.Value)
	end)

	return obj
end

function Tab:AddSlider(opts)
	opts = opts or {}
	local callback = opts.Callback
	local min, max = opts.Min or 0, opts.Max or 100
	local inc = opts.Increment or 1
	local suffix = opts.Suffix or ""
	local decimals = #(tostring(inc):match("%.(%d+)") or "")
	local fmt = "%." .. decimals .. "f"

	local card = makeCard(self.Page, 58, self:_order())
	label(card, opts.Name or "Slider", 12, FONT_BOLD, WHITE,
		UDim2.fromOffset(14, 6), UDim2.new(1, -120, 0, 20))
	local valLbl = label(card, "", 11, FONT_BOLD, ACCENT_HI,
		UDim2.new(1, -114, 0, 6), UDim2.fromOffset(100, 20), Enum.TextXAlignment.Right)

	local track = new("Frame", {
		Position = UDim2.new(0, 14, 1, -18),
		Size = UDim2.new(1, -28, 0, 6),
		BackgroundColor3 = TRACK_OFF,
		BorderSizePixel = 0,
	}, card)
	corner(track, 3)
	local fill = new("Frame", {
		Size = UDim2.fromScale(0, 1),
		BackgroundColor3 = WHITE,
		BorderSizePixel = 0,
	}, track)
	corner(fill, 3)
	gradient(fill, ACCENT_DARK, ACCENT_HI, 0)
	local knob = new("Frame", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.new(0, 0, 0.5, 0),
		Size = UDim2.fromOffset(14, 14),
		BackgroundColor3 = WHITE,
		BorderSizePixel = 0,
	}, track)
	corner(knob, 7)
	stroke(knob, ACCENT_HI, 1.5, 0)

	local hit = new("TextButton", {
		Text = "",
		AutoButtonColor = false,
		BackgroundTransparency = 1,
		Position = UDim2.new(0, 8, 1, -30),
		Size = UDim2.new(1, -16, 0, 28),
	}, card)

	local obj = { Instance = card, Value = min }

	local function snap(v)
		v = math.clamp(v, min, max)
		v = min + math.floor((v - min) / inc + 0.5) * inc
		return math.clamp(tonumber(fmt:format(v)) or min, min, max)
	end

	local function render(v)
		local ratio = (max == min) and 0 or (v - min) / (max - min)
		fill.Size = UDim2.new(ratio, 0, 1, 0)
		knob.Position = UDim2.new(ratio, 0, 0.5, 0)
		valLbl.Text = fmt:format(v) .. suffix
	end

	function obj:Set(v, silent)
		v = snap(tonumber(v) or min)
		if v == self.Value then
			return
		end
		self.Value = v
		render(v)
		if not silent then
			fire(callback, v)
		end
	end

	function obj:Get()
		return self.Value
	end

	obj.Value = snap(opts.Default or min)
	render(obj.Value)

	local dragging = false
	local function fromInput(input)
		local rel = math.clamp(
			(input.Position.X - track.AbsolutePosition.X) / math.max(track.AbsoluteSize.X, 1), 0, 1)
		obj:Set(min + rel * (max - min))
	end

	hit.InputBegan:Connect(function(input)
		if isPress(input) then
			dragging = true
			fromInput(input)
		end
	end)
	self.Window:_connect(UserInputService.InputChanged, function(input)
		if dragging and isMove(input) then
			fromInput(input)
		end
	end)
	self.Window:_connect(UserInputService.InputEnded, function(input)
		if isPress(input) then
			dragging = false
		end
	end)

	return obj
end

function Tab:AddDropdown(opts)
	opts = opts or {}
	local callback = opts.Callback
	local multi = opts.Multi == true
	local HEADER, ITEM, MAXLIST = 46, 24, 132

	local options = {}
	local function setOptions(list)
		options = {}
		for _, o in ipairs(list or {}) do
			table.insert(options, tostring(o))
		end
	end
	setOptions(opts.Options)

	local card = makeCard(self.Page, HEADER, self:_order())
	label(card, opts.Name or "Dropdown", 12, FONT_BOLD, WHITE,
		UDim2.fromOffset(14, 0), UDim2.new(1, -200, 0, HEADER))

	local head, headBg = button(card, {
		text = "", textSize = 11,
		anchor = Vector2.new(1, 0),
		pos = UDim2.new(1, -12, 0, 10),
		size = UDim2.fromOffset(170, 26),
		c0 = DARK0, c1 = DARK1,
		strokeColor = ACCENT, strokeTransparency = 0.3, radius = 8,
	})
	head.TextXAlignment = Enum.TextXAlignment.Left
	head.TextTruncate = Enum.TextTruncate.AtEnd
	new("UIPadding", { PaddingLeft = UDim.new(0, 8), PaddingRight = UDim.new(0, 22) }, head)
	local arrow = label(headBg, "v", 10, FONT_BOLD, ACCENT_HI,
		UDim2.new(1, -20, 0, 0), UDim2.new(0, 16, 1, 0), Enum.TextXAlignment.Center)

	local list = new("ScrollingFrame", {
		Position = UDim2.fromOffset(10, HEADER + 2),
		Size = UDim2.new(1, -20, 0, 0),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		ScrollBarThickness = 2,
		ScrollBarImageColor3 = ACCENT,
		CanvasSize = UDim2.new(),
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
	}, card)
	new("UIListLayout", {
		Padding = UDim.new(0, 2),
		SortOrder = Enum.SortOrder.LayoutOrder,
	}, list)

	local obj = { Instance = card }
	local open = false
	local selected = {} -- multi: set
	local value = nil -- single
	local optButtons = {}

	local function getValue()
		if multi then
			local t = {}
			for _, o in ipairs(options) do
				if selected[o] then
					table.insert(t, o)
				end
			end
			return t
		end
		return value
	end

	local function paint()
		if multi then
			local v = getValue()
			head.Text = #v == 0 and "None" or table.concat(v, ", ")
		else
			head.Text = value or "Select"
		end
		for name, b in pairs(optButtons) do
			local on = multi and selected[name] or (not multi and value == name)
			b.BackgroundColor3 = on and ACCENT_DEEP or Color3.fromRGB(24, 12, 14)
			b.TextColor3 = on and WHITE or SUB_TEXT
		end
	end

	local function resize()
		local lh = math.min(MAXLIST, #options * (ITEM + 2))
		list.Size = UDim2.new(1, -20, 0, lh)
		local h = open and (HEADER + 2 + lh + 8) or HEADER
		TweenService:Create(card, TWEEN, { Size = UDim2.new(1, 0, 0, h) }):Play()
		TweenService:Create(arrow, TWEEN, { Rotation = open and 180 or 0 }):Play()
	end

	local function pick(name)
		if multi then
			selected[name] = not selected[name] or nil
		else
			value = name
			open = false
		end
		paint()
		resize()
		fire(callback, getValue())
	end

	local function build()
		for _, c in ipairs(list:GetChildren()) do
			if c:IsA("TextButton") then
				c:Destroy()
			end
		end
		table.clear(optButtons)
		for i, name in ipairs(options) do
			local b = new("TextButton", {
				LayoutOrder = i,
				AutoButtonColor = false,
				Size = UDim2.new(1, -4, 0, ITEM),
				BorderSizePixel = 0,
				Text = name,
				TextSize = 11,
				Font = FONT_BOLD,
				TextTruncate = Enum.TextTruncate.AtEnd,
				BackgroundColor3 = Color3.fromRGB(24, 12, 14),
				TextColor3 = SUB_TEXT,
			}, list)
			corner(b, 6)
			optButtons[name] = b
			b.MouseButton1Click:Connect(function()
				pick(name)
			end)
		end
		paint()
		resize()
	end

	function obj:Set(v, silent)
		if multi then
			selected = {}
			local src = type(v) == "table" and v or { v }
			for _, n in ipairs(src) do
				selected[tostring(n)] = true
			end
		else
			value = v ~= nil and tostring(v) or nil
		end
		paint()
		if not silent then
			fire(callback, getValue())
		end
	end

	function obj:Get()
		return getValue()
	end

	function obj:Refresh(newOptions)
		setOptions(newOptions)
		local valid = {}
		for _, o in ipairs(options) do
			valid[o] = true
		end
		for k in pairs(selected) do
			if not valid[k] then
				selected[k] = nil
			end
		end
		if value and not valid[value] then
			value = nil
		end
		build()
	end

	if opts.Default ~= nil then
		obj:Set(opts.Default, true)
	end
	build()

	head.MouseButton1Click:Connect(function()
		open = not open
		resize()
	end)

	return obj
end

return Library
