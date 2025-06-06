local Name, AddOn = ...
local Gathering = AddOn.Gathering
local SharedMedia = Gathering.SharedMedia
local L = AddOn.L

local BlankTexture = "Interface\\AddOns\\Gathering\\Assets\\HydraUIBlank.tga"
local BarTexture = "Interface\\AddOns\\Gathering\\Assets\\HydraUI4.tga"
local MaxWidgets = 11
local MaxSelections = 8

SharedMedia:Register("font", "PT Sans", "Interface\\Addons\\Gathering\\Assets\\PTSans.ttf")
SharedMedia:Register("statusbar", "HydraUI 4", BarTexture)

local Outline = {
	bgFile = BlankTexture,
}

local DisplayModes = {
	[L["Time"]] = "TIME",
	[L["GPH"]] = "GPH",
	[L["Gold"]] = "GOLD",
	[L["Total"]] = "TOTAL",
	--[L["XP/hr"]] = "XPH",
	--[L["Time To Level"]] = "TTL",
}

function Gathering:CreateWindow()
	-- Main widget
	self:SetSize(self.Settings.WindowWidth, self.Settings.WindowHeight)
	self:SetBackdrop({bgFile = BlankTexture, edgeFile = BlankTexture, edgeSize = 1})
	self:SetBackdropColor(0.2, 0.2, 0.2, 0.85)
	self:SetBackdropBorderColor(0, 0, 0)
	self:SetClampedToScreen(true)
	self:RegisterForDrag("LeftButton")
	self:SetScript("OnDragStart", self.StartMoving)
	self:SetScript("OnDragStop", self.StopMovingOrSizing)

	-- Text
	local Text = self:CreateFontString(nil, "OVERLAY")
	Text:SetPoint("CENTER", self, 0, 0)
	Text:SetJustifyH("CENTER")
	Text:SetFont(SharedMedia:Fetch("font", self.Settings.WindowFont), 14, "")

	if (self.Settings.DisplayMode == "TIME") then
		Text:SetText(date("!%X", 0))
	elseif (self.Settings.DisplayMode == "GPH") then
		Text:SetFormattedText(L["GPH: %s"], self:CopperToGold(0))
		self.Int = 2
	elseif (self.Settings.DisplayMode == "GOLD") then
		Text:SetText(self:CopperToGold(0))
	elseif (self.Settings.DisplayMode == "TOTAL") then
		Text:SetFormattedText(L["Total: %s"], 0)
	end

	self.Text = Text

	-- Tooltip
	local Tooltip = CreateFrame("GameTooltip", "Gathering Tooltip", UIParent, "GameTooltipTemplate")
	Tooltip:SetFrameLevel(10)

	local TTBackdrop = CreateFrame("Frame", nil, Tooltip, "BackdropTemplate")
	TTBackdrop:SetAllPoints(Tooltip)
	TTBackdrop:SetBackdrop({bgFile = BlankTexture})
	TTBackdrop:SetBackdropColor(0.2, 0.2, 0.2, 0.8)
	TTBackdrop:SetFrameStrata("TOOLTIP")
	TTBackdrop:SetFrameLevel(1)

	Tooltip.Backdrop = TTBackdrop
	self.Tooltip = Tooltip

	-- Data
	self.Gathered = {}
	self.TotalGathered = 0
	self.Elapsed = 0
	self.Seconds = 0
	self.GoldValue = GetMoney() or 0
	self.GoldGained = 0
	self.GoldTimer = 0
	self.LastXP = UnitXP("player")
	self.LastMax = UnitXPMax("player")
	self.XPGained = 0

	-- Bag slot display
	local BagSlots = CreateFrame("Frame", nil, self, "BackdropTemplate")
	BagSlots:SetPoint("TOPLEFT", self, "BOTTOMLEFT", 0, 1)
	BagSlots:SetPoint("TOPRIGHT", self, "BOTTOMRIGHT", 0, 1)
	BagSlots:SetHeight(self.Settings.SlotBarHeight)
	BagSlots:SetBackdrop({bgFile = BlankTexture, edgeFile = BlankTexture, edgeSize = 1})
	BagSlots:SetBackdropColor(0.2, 0.2, 0.2, 0.85)
	BagSlots:SetBackdropBorderColor(0, 0, 0)
	--BagSlots:SetScript("OnEnter", function(self) self.Text:Show() end)
	--BagSlots:SetScript("OnLeave", function(self) self.Text:Hide() end)

	local BagBar = CreateFrame("StatusBar", nil, BagSlots)
	BagBar:SetPoint("TOPLEFT", BagSlots, 1, -1)
	BagBar:SetPoint("BOTTOMRIGHT", BagSlots, -1, 1)
	BagBar:SetStatusBarTexture(BlankTexture)
	BagBar:SetStatusBarColor(0.15, 0.9, 0.15)
	BagBar:SetMinMaxValues(0, 1)
	BagBar:SetValue(1)

	local BagText = BagBar:CreateFontString(nil, "OVERLAY")
	BagText:SetPoint("CENTER", BagBar, 0, 0)
	BagText:SetJustifyH("CENTER")
	BagText:SetFont(SharedMedia:Fetch("font", self.Settings.WindowFont), 14, "")
	BagText:Hide()

	BagSlots.Text = BagText
	BagSlots.Bar = BagBar

	self.BagSlots = BagSlots

	self:HookBagTooltip()

	if (not self.Settings.EnableSlotBar) then
		BagSlots:Hide()
	end
end

local ScrollIgnoredItems = function(self)
	local First = false

	for i = 1, #self.IgnoredItems do
		if (i >= self.Offset) and (i < self.Offset + 10) then
			if (not First) then
				self.IgnoredItems[i]:SetPoint("TOPLEFT", self.IgnoredList, 4, -4)
				First = true
			else
				self.IgnoredItems[i]:SetPoint("TOPLEFT", self.IgnoredItems[i-1], "BOTTOMLEFT", 0, -2)
			end

			self.IgnoredItems[i]:Show()
		else
			self.IgnoredItems[i]:Hide()
		end
	end
end

function Gathering:AddIgnoredItem(text)
	if (text == "") then
		return
	end

	local ID = tonumber(text)
	local Page = Gathering:GetPage("Ignore")
	local Name, Link = GetItemInfo(ID or text)

	if ID then
		if GatheringIgnore[ID] then
			print(Link .. " is already ignored")

			return
		end

		GatheringIgnore[ID] = true

		print(format(ERR_IGNORE_ADDED_S, Link or Name))
	else
		if GatheringIgnore[text] then
			print(text .. " is already ignored")

			return
		end

		GatheringIgnore[text] = true

		print(format(ERR_IGNORE_ADDED_S, Link or text))
	end

	if (Name and Link) then
		local Line = CreateFrame("Frame", nil, Page, "BackdropTemplate")
		Line:SetSize(Page.IgnoredList:GetWidth() - 24, 22)
		Line.Item = ID

		local Text = Line:CreateFontString(nil, "OVERLAY")
		Text:SetFont(SharedMedia:Fetch("font", Gathering.Settings["WindowFont"]), 14, "")
		Text:SetPoint("LEFT", Line, 5, 0)
		Text:SetJustifyH("LEFT")
		Text:SetShadowColor(0, 0, 0)
		Text:SetShadowOffset(1, -1)
		Text:SetText(Link)

		local CloseButton = CreateFrame("Frame", nil, Line)
		CloseButton:SetPoint("RIGHT", Line, 0, 0)
		CloseButton:SetSize(24, 24)
		CloseButton:SetScript("OnEnter", function(self) self.Texture:SetVertexColor(1, 0, 0) end)
		CloseButton:SetScript("OnLeave", function(self) self.Texture:SetVertexColor(1, 1, 1) end)
		CloseButton:SetScript("OnMouseUp", function(self) Gathering:RemoveIgnoredItem(self:GetParent().Item) end)

		local CloseButtonTexture = CloseButton:CreateTexture(nil, "OVERLAY")
		CloseButtonTexture:SetPoint("CENTER", CloseButton, 0, -0.5)
		CloseButtonTexture:SetTexture("Interface\\AddOns\\Gathering\\Assets\\HydraUIClose.tga")

		Line.Text = Text
		Line.CloseButton = CloseButton
		CloseButton.Texture = CloseButtonTexture

		tinsert(Page.IgnoredItems, Line)

		Page.ScrollBar:SetMinMaxValues(1, math.max(1, #Page.IgnoredItems - 9))

		ScrollIgnoredItems(Page)
	end
end

function Gathering:RemoveIgnoredItem(text)
	if ((not GatheringIgnore) or (text == "")) then
		return
	end

	local ID = tonumber(text)

	if ID then
		GatheringIgnore[ID] = nil
	else
		GatheringIgnore[text] = nil
	end

	local Name, Link = GetItemInfo(ID)

	if Link then
		print(format(L["%s is now being unignored."], Link))
	else
		print(format(L["%s is now being unignored."], text))
	end

	local Page = Gathering:GetPage("Ignore")

	for i = 1, #Page.IgnoredItems do
		if (Page.IgnoredItems[i].Item == ID) then
			Page.IgnoredItems[i]:Hide()

			table.remove(Page.IgnoredItems, i)

			Page.ScrollBar:SetMinMaxValues(1, math.max(1, #Page.IgnoredItems - 9))

			ScrollIgnoredItems(Page)

			return
		end
	end
end

function Gathering:SetFrameWidth(text)
	Gathering:SetWidth(tonumber(self:GetText()))
end

function Gathering:SetFrameHeight(text)
	Gathering:SetHeight(tonumber(self:GetText()))
end

function Gathering:ToggleTimerPanel(value)
	if (value and (not Gathering:GetScript("OnUpdate"))) then
		Gathering:Hide()
	else
		Gathering:Show()
	end
end

function Gathering:ToggleSlotBar(value)
	if value then
		Gathering.BagSlots:Show()
	else
		Gathering.BagSlots:Hide()
	end
end

function Gathering:UpdateSlotBarHeight(value)
	if (value > 20) then -- Clamp the value until I add sliders
		value = 20
	elseif (0 > value) then
		value = 1
	end

	Gathering.BagSlots:SetHeight(value)
end

function Gathering:UpdateTooltipFont()
	local Font = SharedMedia:Fetch("font", self.Settings.WindowFont, "")

	if self.Tooltip.NineSlice then
		self.Tooltip.NineSlice:Hide()
	end

	for i = 1, self.Tooltip:GetNumRegions() do
		local Region = select(i, self.Tooltip:GetRegions())

		if (Region:GetObjectType() == "FontString") then
			Region:SetFont(Font, 14)
			Region:SetShadowColor(0, 0, 0)
			Region:SetShadowOffset(1, -1)
		end
	end
end

function Gathering:OnUpdate(ela)
	self.Elapsed = self.Elapsed + ela

	if (self.Elapsed >= self.Int) then
		self.Seconds = self.Seconds + self.Int

		if (self.Settings.DisplayMode == "TIME") then
			self.Text:SetText(date("!%X", self.Seconds))
		elseif (self.Settings.DisplayMode == "GPH") then
			if (self.GoldGained > 0) then
				self.Text:SetFormattedText(L["GPH: %s"], self:CopperToGold(floor((self.GoldGained / max(GetTime() - self.GoldTimer, 1)) * 60 * 60)))
			end
		end

		if self.MouseIsOver then
			self:OnLeave()
			self:OnEnter()
		end

		self.Elapsed = 0
	end
end

function Gathering:StartTimer()
	if (self.Settings["hide-idle"] and not self:IsVisible()) then
		self:Show()
	end

	self:SetScript("OnUpdate", self.OnUpdate)
end

function Gathering:PauseTimer()
	self:SetScript("OnUpdate", nil)
end

function Gathering:ToggleTimer()
	if (self.Settings.DisplayMode ~= "TIME") then
		return
	end

	if (not self:GetScript("OnUpdate")) then
		self:StartTimer()
	else
		self:PauseTimer()
	end
end

function Gathering:Reset()
	self:SetScript("OnUpdate", nil)

	wipe(self.Gathered)

	self.TotalGathered = 0
	self.Seconds = 0
	self.Elapsed = 0
	self.GoldValue = GetMoney() or 0
	self.GoldGained = 0
	self.GoldTimer = 0
	self.LastXP = UnitXP("player")
	self.LastMax = UnitXPMax("player")
	self.XPGained = 0
	self.XPStartTime = GetTime()

	if (self.Settings.DisplayMode == "TIME") then
		self.Text:SetText(date("!%X", 0))
	elseif (self.Settings.DisplayMode == "GPH") then
		self.Text:SetFormattedText(L["GPH: %s"], self:CopperToGold(0))
		self.Int = 2
	elseif (self.Settings.DisplayMode == "GOLD") then
		self.Text:SetText(self:CopperToGold(0))
	elseif (self.Settings.DisplayMode == "TOTAL") then
		self.Text:SetFormattedText(L["Total: %s"], 0)
	end

	if self.MouseIsOver then
		self:OnLeave()
	end

	if self.Settings["hide-idle"] then
		self:Hide()
	end
end

function Gathering:OnResetAccept()
	Gathering:ToggleResetPopup()
	Gathering:Reset()

	self.Text:SetPoint("CENTER", self, 0, -0.5)
end

function Gathering:OnResetCancel()
	Gathering:ToggleResetPopup()

	self.Text:SetPoint("CENTER", self, 0, -0.5)
end

function Gathering:PopupButtonOnEnter()
	self.Text:SetTextColor(1, 1, 0)
end

function Gathering:PopupButtonOnLeave()
	self.Text:SetTextColor(1, 1, 1)
end

function Gathering:PopupButtonOnMouseDown()
	self.Text:SetPoint("CENTER", self, 1, -1.5)
end

function Gathering:ToggleResetPopup()
	local Popup = self.Popup

	if (not Popup) then
		local Popup = CreateFrame("Frame", nil, self, "BackdropTemplate")
		Popup:SetSize(240, 80)
		Popup:SetPoint("CENTER", UIParent, 0, 120)
		Popup:SetBackdrop({bgFile = BlankTexture, edgeFile = BlankTexture, edgeSize = 1})
		Popup:SetBackdropColor(0.2, 0.2, 0.2, 0.85)
		Popup:SetBackdropBorderColor(0, 0, 0)
		Popup:SetClampedToScreen(true)
		Popup:RegisterForDrag("LeftButton")
		Popup:SetScript("OnDragStart", Popup.StartMoving)
		Popup:SetScript("OnDragStop", Popup.StopMovingOrSizing)

		Popup.Text = Popup:CreateFontString(nil, "OVERLAY")
		Popup.Text:SetPoint("TOP", Popup, 0, -4)
		Popup.Text:SetSize(234, 40)
		Popup.Text:SetJustifyH("CENTER")
		Popup.Text:SetFont(SharedMedia:Fetch("font", self.Settings.WindowFont), 14, "")
		Popup.Text:SetText(L["Are you sure you would like to reset current data?"])

		Popup.Accept = CreateFrame("Frame", nil, Popup, "BackdropTemplate")
		Popup.Accept:SetSize(114, 20)
		Popup.Accept:SetPoint("BOTTOMLEFT", Popup, 4, 4)
		Popup.Accept:SetBackdrop({bgFile = BlankTexture, edgeFile = BlankTexture, edgeSize = 1})
		Popup.Accept:SetBackdropColor(0.2, 0.2, 0.2, 0.9)
		Popup.Accept:SetBackdropBorderColor(0, 0, 0)
		Popup.Accept:SetScript("OnMouseUp", self.OnResetAccept)
		Popup.Accept:SetScript("OnEnter", self.PopupButtonOnEnter)
		Popup.Accept:SetScript("OnLeave", self.PopupButtonOnLeave)
		Popup.Accept:SetScript("OnMouseDown", self.PopupButtonOnMouseDown)

		Popup.Accept.Text = Popup.Accept:CreateFontString(nil, "OVERLAY")
		Popup.Accept.Text:SetPoint("CENTER", Popup.Accept, 0, -0.5)
		Popup.Accept.Text:SetJustifyH("CENTER")
		Popup.Accept.Text:SetFont(SharedMedia:Fetch("font", self.Settings.WindowFont), 14, "")
		Popup.Accept.Text:SetText(RESET)

		Popup.Cancel = CreateFrame("Frame", nil, Popup, "BackdropTemplate")
		Popup.Cancel:SetSize(114, 20)
		Popup.Cancel:SetPoint("LEFT", Popup.Accept, "RIGHT", 4, 0)
		Popup.Cancel:SetBackdrop({bgFile = BlankTexture, edgeFile = BlankTexture, edgeSize = 1})
		Popup.Cancel:SetBackdropColor(0.2, 0.2, 0.2, 0.9)
		Popup.Cancel:SetBackdropBorderColor(0, 0, 0)
		Popup.Cancel:SetScript("OnMouseUp", self.OnResetCancel)
		Popup.Cancel:SetScript("OnEnter", self.PopupButtonOnEnter)
		Popup.Cancel:SetScript("OnLeave", self.PopupButtonOnLeave)
		Popup.Cancel:SetScript("OnMouseDown", self.PopupButtonOnMouseDown)

		Popup.Cancel.Text = Popup.Cancel:CreateFontString(nil, "OVERLAY")
		Popup.Cancel.Text:SetPoint("CENTER", Popup.Cancel, 0, -0.5)
		Popup.Cancel.Text:SetJustifyH("CENTER")
		Popup.Cancel.Text:SetFont(SharedMedia:Fetch("font", self.Settings.WindowFont), 14, "")
		Popup.Cancel.Text:SetText(CANCEL)

		self.Popup = Popup

		return
	end

	if Popup:IsShown() then
		Popup:Hide()
	else
		Popup:Show()
	end
end

function Gathering:CreateHeader(page, text)
	local Header = CreateFrame("Frame", nil, page, "BackdropTemplate")
	Header:SetSize(page:GetWidth() - 8, 22)
	Header:SetBackdrop(Outline)
	Header:SetBackdropColor(0.25, 0.266, 0.294)

	local Text = Header:CreateFontString(nil, "OVERLAY")
	Text:SetFont(SharedMedia:Fetch("font", self.Settings.WindowFont), 14, "")
	Text:SetPoint("LEFT", Header, 5, 0)
	Text:SetJustifyH("LEFT")
	Text:SetShadowColor(0, 0, 0)
	Text:SetShadowOffset(1, -1)
	Text:SetText(format("|cffFFC44D%s|r", text))

	Header.Text = Text

	tinsert(page, Header)
end

function Gathering:UpdateSettingValue(key, value)
	if (value == self.DefaultSettings[key]) then
		GatheringSettings[key] = nil
	else
		GatheringSettings[key] = value
	end

	self.Settings[key] = value
end

function Gathering:CheckBoxOnMouseUp()
	if (Gathering.Settings[self.Setting] == true) then
		self.Tex:SetVertexColor(0.125, 0.133, 0.145)
		Gathering:UpdateSettingValue(self.Setting, false)

		if self.Hook then
			self:Hook(false)
		end
	else
		self.Tex:SetVertexColor(1, 0.7686, 0.3019)
		Gathering:UpdateSettingValue(self.Setting, true)

		if self.Hook then
			self:Hook(true)
		end
	end
end

function Gathering:CreateCheckbox(page, key, text, func)
	local Line = CreateFrame("Frame", nil, page)
	Line:SetSize(129, 22)

	local Checkbox = CreateFrame("Frame", nil, Line)
	Checkbox:SetSize(18, 18)
	Checkbox:SetPoint("LEFT", Line, 4, 0)
	Checkbox:SetScript("OnMouseUp", self.CheckBoxOnMouseUp)
	Checkbox:SetScript("OnEnter", function(self) self.Overlay:Show() end)
	Checkbox:SetScript("OnLeave", function(self) self.Overlay:Hide() end)
	Checkbox.Setting = key

	local Tex = Checkbox:CreateTexture(nil, "OVERLAY")
	Tex:SetTexture(BlankTexture)
	Tex:SetPoint("TOPLEFT", Checkbox, 1, -1)
	Tex:SetPoint("BOTTOMRIGHT", Checkbox, -1, 1)

	local Overlay = Checkbox:CreateTexture(nil, "OVERLAY")
	Overlay:SetTexture(BlankTexture)
	Overlay:SetPoint("TOPLEFT", Checkbox, 1, -1)
	Overlay:SetPoint("BOTTOMRIGHT", Checkbox, -1, 1)
	Overlay:SetAlpha(0.2)
	Overlay:Hide()

	local Text = Checkbox:CreateFontString(nil, "OVERLAY")
	Text:SetFont(SharedMedia:Fetch("font", self.Settings.WindowFont), 14, "")
	Text:SetPoint("LEFT", Checkbox, "RIGHT", 6, 0)
	Text:SetJustifyH("LEFT")
	Text:SetShadowColor(0, 0, 0)
	Text:SetShadowOffset(1, -1)
	Text:SetText(text)

	Checkbox.Tex = Tex
	Checkbox.Overlay = Overlay
	Checkbox.Text = Text

	if self.Settings[key] then
		Tex:SetVertexColor(1, 0.7686, 0.3019)
	else
		Tex:SetVertexColor(0.125, 0.133, 0.145)
	end

	if func then
		Checkbox.Hook = func
	end

	tinsert(page, Line)
end

local ListOnEnter = function(self)
	self.Tex:SetVertexColor(0.3, 0.3, 0.34)
end

local ListOnLeave = function(self)
	self.Tex:SetVertexColor(0.184, 0.192, 0.211)
end

local WidgetOnLeave = function(self)
	self.Tex:SetVertexColor(0.125, 0.133, 0.145)
end

function Gathering:EditBoxOnEnterPressed()
	local Text = self:GetText()

	self:SetAutoFocus(false)
	self:ClearFocus()

	if self.Hook then
		self:Hook(Text)
	end

	self:SetText(L["Ignore items"])
end

function Gathering:OnEscapePressed()
	self:SetAutoFocus(false)
	self:ClearFocus()
	self:SetText(L["Ignore items"])
end

function Gathering:EditBoxOnMouseDown()
	local Type, ID, Link = GetCursorInfo()

	self:SetAutoFocus(true)

	if (Type and Type == "item") then
		self:SetText(ID)
		self.Icon:SetTexture(C_Item.GetItemIconByID(ID))
	else
		self:SetText("")
	end

	ClearCursor()
end

function Gathering:OnEditFocusLost()
	self:SetText("")
	self.Icon:SetTexture("Interface\\ICONS\\INV_Misc_QuestionMark")

	ClearCursor()
end

function Gathering:OnEditChar(text)
	local ID = tonumber(self:GetText())

	if (not ID) then
		self.Icon:SetTexture("Interface\\ICONS\\INV_Misc_QuestionMark")

		return
	end

	local IconID = C_Item.GetItemIconByID(ID)

	if (IconID and IconID ~= 134400) then
		self.Icon:SetTexture(IconID)
	else
		self.Icon:SetTexture("Interface\\ICONS\\INV_Misc_QuestionMark")
	end
end

function Gathering:CreateEditBox(page, text, func)
	local Line = CreateFrame("Frame", nil, page)
	Line:SetSize(page:GetWidth() - 8, 22)

	local EditBox = CreateFrame("EditBox", nil, Line)
	EditBox:SetSize(170, 22)
	EditBox:SetPoint("LEFT", Line, -1, 0)
	EditBox:SetFont(SharedMedia:Fetch("font", self.Settings.WindowFont), 14, "")
	EditBox:SetShadowColor(0, 0, 0)
	EditBox:SetShadowOffset(1, -1)
	EditBox:SetJustifyH("LEFT")
	EditBox:SetAutoFocus(false)
	EditBox:EnableKeyboard(true)
	EditBox:EnableMouse(true)
	EditBox:SetMaxLetters(255)
	EditBox:SetTextInsets(5, 0, 0, 0)
	EditBox:SetText(text)
	EditBox:SetScript("OnEnterPressed", self.EditBoxOnEnterPressed)
	EditBox:SetScript("OnEscapePressed", self.OnEscapePressed)
	EditBox:SetScript("OnMouseDown", self.EditBoxOnMouseDown)
	EditBox:SetScript("OnEditFocusLost", self.OnEditFocusLost)
	EditBox:SetScript("OnEnter", ListOnEnter)
	EditBox:SetScript("OnLeave", WidgetOnLeave)
	EditBox:SetScript("OnChar", self.OnEditChar)

	local Tex = EditBox:CreateTexture(nil, "ARTWORK")
	Tex:SetTexture(BlankTexture)
	Tex:SetPoint("TOPLEFT", EditBox, 1, -1)
	Tex:SetPoint("BOTTOMRIGHT", EditBox, -1, 1)
	Tex:SetVertexColor(0.125, 0.133, 0.145)

	local Icon = EditBox:CreateTexture(nil, "ARTWORK")
	Icon:SetPoint("LEFT", EditBox, "RIGHT", 1, 0)
	Icon:SetSize(20, 20)
	Icon:SetTexture("Interface\\ICONS\\INV_Misc_QuestionMark")
	Icon:SetTexCoord(0.1, 0.9, 0.1, 0.9)

	EditBox.Tex = Tex
	EditBox.Icon = Icon

	if func then
		EditBox.Hook = func
	end

	tinsert(page, Line)
end

function Gathering:NumberEditBoxOnEnterPressed()
	local Text = self:GetText()

	self:SetAutoFocus(false)
	self:ClearFocus()

	Gathering:UpdateSettingValue(self.Setting, tonumber(Text))

	if self.Hook then
		self:Hook(tonumber(Text))
	end
end

function Gathering:NumberOnEscapePressed()
	self:SetAutoFocus(false)
	self:ClearFocus()
end

function Gathering:NumberEditBoxOnMouseDown()
	self:SetAutoFocus(true)
	ClearCursor()
end

function Gathering:NumberOnEditFocusLost()
	ClearCursor()
end

function Gathering:CreateNumberEditBox(page, key, text, func)
	local Line = CreateFrame("Frame", nil, page)
	Line:SetSize(page:GetWidth() - 8, 22)

	local EditBox = CreateFrame("EditBox", nil, Line)
	EditBox:SetSize(60, 22)
	EditBox:SetPoint("LEFT", Line, 0, 0)
	EditBox:SetFont(SharedMedia:Fetch("font", self.Settings.WindowFont), 14, "")
	EditBox:SetShadowColor(0, 0, 0)
	EditBox:SetShadowOffset(1, -1)
	EditBox:SetJustifyH("LEFT")
	EditBox:SetAutoFocus(false)
	EditBox:EnableKeyboard(true)
	EditBox:EnableMouse(true)
	EditBox:SetMaxLetters(3)
	EditBox:SetNumeric(true)
	EditBox:SetTextInsets(5, 0, 0, 0)
	EditBox:SetText(self.Settings[key])
	EditBox:SetScript("OnEnterPressed", self.NumberEditBoxOnEnterPressed)
	EditBox:SetScript("OnEscapePressed", self.NumberOnEscapePressed)
	EditBox:SetScript("OnMouseDown", self.NumberEditBoxOnMouseDown)
	EditBox:SetScript("OnEnter", ListOnEnter)
	EditBox:SetScript("OnLeave", WidgetOnLeave)
	EditBox.Setting = key

	local Tex = EditBox:CreateTexture(nil, "ARTWORK")
	Tex:SetTexture(BlankTexture)
	Tex:SetPoint("TOPLEFT", EditBox, 1, -1)
	Tex:SetPoint("BOTTOMRIGHT", EditBox, -1, 1)
	Tex:SetVertexColor(0.125, 0.133, 0.145)

	local Text = EditBox:CreateFontString(nil, "OVERLAY")
	Text:SetFont(SharedMedia:Fetch("font", self.Settings.WindowFont), 14, "")
	Text:SetPoint("LEFT", EditBox, "RIGHT", 6, 0)
	Text:SetJustifyH("LEFT")
	Text:SetShadowColor(0, 0, 0)
	Text:SetShadowOffset(1, -1)
	Text:SetText(text)

	EditBox.Tex = Tex
	EditBox.Text = Text

	if func then
		EditBox.Hook = func
	end

	tinsert(page, Line)
end

local ScrollSelections = function(self)
	local First = false

	for i = 1, #self do
		if (i >= self.Offset) and (i <= self.Offset + MaxSelections - 1) then
			if (not First) then
				self[i]:SetPoint("TOPLEFT", self, -1, 1)
				First = true
			else
				self[i]:SetPoint("TOPLEFT", self[i-1], "BOTTOMLEFT", 0, 0)
			end

			self[i]:Show()
		else
			self[i]:Hide()
		end
	end

	if self.ScrollBar then
		self.ScrollBar:SetValue(self.Offset)
	end
end

local SelectionOnMouseWheel = function(self, delta)
	if (delta == 1) then
		self.Offset = self.Offset - 1

		if (self.Offset <= 1) then
			self.Offset = 1
		end
	else
		self.Offset = self.Offset + 1

		if (self.Offset > (#self - (MaxSelections - 1))) then
			self.Offset = self.Offset - 1
		end
	end

	ScrollSelections(self)
end

local SelectionScrollBarOnValueChanged = function(self)
	local Parent = self:GetParent()
	Parent.Offset = self:GetValue()

	ScrollSelections(Parent)
end

local ScrollBarOnEnter = function(self)
	self:GetThumbTexture():SetVertexColor(0.4, 0.4, 0.4)
end

local ScrollBarOnLeave = function(self)
	if (not self.OverrideThumb) then
		self:GetThumbTexture():SetVertexColor(0.25, 0.266, 0.294)
	end
end

local ScrollBarOnMouseDown = function(self)
	self.OverrideThumb = true
	self:GetThumbTexture():SetVertexColor(0.4, 0.4, 0.4)
end

local ScrollBarOnMouseUp = function(self)
	self.OverrideThumb = false
	self:GetThumbTexture():SetVertexColor(0.25, 0.266, 0.294)
end

local SelectionScrollBarOnMouseWheel = function(self, delta)
	SelectionOnMouseWheel(self:GetParent(), delta)
end

local FontListOnMouseUp = function(self)
	local Selection = self:GetParent():GetParent()

	Selection.Current:SetFont(SharedMedia:Fetch("font", self.Key), 14, "")
	Selection.Current:SetText(self.Key)

	Selection.List:Hide()

	Gathering:UpdateSettingValue(Selection.Setting, self.Key)

	if Selection.Hook then
		Selection:Hook(self.Key)
	end

	Selection.Arrow:SetTexture("Interface\\AddOns\\Gathering\\Assets\\GatheringArrowDown.tga")
end

local FontSelectionOnMouseUp = function(self)
	if (not self.List) then
		local List = CreateFrame("Frame", nil, self)
		List:SetSize(150, (20 * MaxSelections) - 2)
		List:SetPoint("TOP", self, "BOTTOM", 0, -1)
		List.Offset = 1
		List:EnableMouseWheel(true)
		List:SetScript("OnMouseWheel", SelectionOnMouseWheel)
		List:SetFrameStrata("TOOLTIP")
		List:SetFrameLevel(20)
		List:Hide()

		local Tex = List:CreateTexture(nil, "ARTWORK")
		Tex:SetTexture(BlankTexture)
		Tex:SetPoint("TOPLEFT", List, -2, 2)
		Tex:SetPoint("BOTTOMRIGHT", List, 2, -2)
		Tex:SetVertexColor(0.125, 0.133, 0.145)

		for Key, Path in next, self.Selections do
			local Selection = CreateFrame("Frame", nil, List)
			Selection:SetSize(140, 20)
			Selection.Key = Key
			Selection.Path = Path
			Selection:SetScript("OnMouseUp", FontListOnMouseUp)
			Selection:SetScript("OnEnter", ListOnEnter)
			Selection:SetScript("OnLeave", ListOnLeave)

			local Tex = Selection:CreateTexture(nil, "ARTWORK")
			Tex:SetTexture(BlankTexture)
			Tex:SetPoint("TOPLEFT", Selection, 1, -1)
			Tex:SetPoint("BOTTOMRIGHT", Selection, -1, 1)
			Tex:SetVertexColor(0.184, 0.192, 0.211)

			local Text = Selection:CreateFontString(nil, "OVERLAY")
			Text:SetFont(Path, 14)
			Text:SetSize(134, 18)
			Text:SetPoint("LEFT", Selection, 5, 0)
			Text:SetJustifyH("LEFT")
			Text:SetShadowColor(0, 0, 0)
			Text:SetShadowOffset(1, -1)
			Text:SetText(Key)

			Selection.Tex = Tex
			Selection.Text = Text

			tinsert(List, Selection)
		end

		table.sort(List, function(a, b)
			return a.Key < b.Key
		end)

		local ScrollBar = CreateFrame("Slider", nil, List)
		ScrollBar:SetPoint("TOPRIGHT", List, 0, 0)
		ScrollBar:SetPoint("BOTTOMRIGHT", List, 0, 0)
		ScrollBar:SetWidth(10)
		ScrollBar:SetThumbTexture(BlankTexture)
		ScrollBar:SetOrientation("VERTICAL")
		ScrollBar:SetValueStep(1)
		ScrollBar:SetMinMaxValues(1, (#List - (MaxSelections - 1)))
		ScrollBar:SetValue(1)
		ScrollBar:SetObeyStepOnDrag(true)
		ScrollBar:EnableMouseWheel(true)
		ScrollBar:SetScript("OnMouseWheel", SelectionScrollBarOnMouseWheel)
		ScrollBar:SetScript("OnValueChanged", SelectionScrollBarOnValueChanged)
		ScrollBar:SetScript("OnEnter", ScrollBarOnEnter)
		ScrollBar:SetScript("OnLeave", ScrollBarOnLeave)
		ScrollBar:SetScript("OnMouseDown", ScrollBarOnMouseDown)
		ScrollBar:SetScript("OnMouseUp", ScrollBarOnMouseUp)

		local Thumb = ScrollBar:GetThumbTexture()
		Thumb:SetSize(10, 18)
		Thumb:SetVertexColor(0.25, 0.266, 0.294)

		List.Tex = Tex
		List.ScrollBar = ScrollBar

		self.List = List

		ScrollSelections(List)
	end

	if self.List:IsShown() then
		self.List:Hide()
		self.Arrow:SetTexture("Interface\\AddOns\\Gathering\\Assets\\GatheringArrowDown.tga")
	else
		self.List:Show()
		self.Arrow:SetTexture("Interface\\AddOns\\Gathering\\Assets\\GatheringArrowUp.tga")
	end
end

function Gathering:CreateFontSelection(page, key, text, selections, func)
	local Line = CreateFrame("Frame", nil, page)
	Line:SetSize(page:GetWidth() - 8, 22)

	local Selection = CreateFrame("Frame", nil, Line)
	Selection:SetSize(Line:GetWidth(), 22)
	Selection:SetPoint("LEFT", Line, 0, 0)
	Selection:SetScript("OnMouseUp", FontSelectionOnMouseUp)
	Selection:SetScript("OnEnter", ListOnEnter)
	Selection:SetScript("OnLeave", WidgetOnLeave)
	Selection.Selections = selections
	Selection.Setting = key

	local Tex = Selection:CreateTexture(nil, "ARTWORK")
	Tex:SetTexture(BlankTexture)
	Tex:SetPoint("TOPLEFT", Selection, 1, -1)
	Tex:SetPoint("BOTTOMRIGHT", Selection, -1, 1)
	Tex:SetVertexColor(0.125, 0.133, 0.145)

	local Arrow = Selection:CreateTexture(nil, "OVERLAY")
	Arrow:SetTexture("Interface\\AddOns\\Gathering\\Assets\\GatheringArrowDown.tga")
	Arrow:SetPoint("RIGHT", Selection, -3, 0)
	Arrow:SetVertexColor(1, 0.7686, 0.3019)

	local Current = Selection:CreateFontString(nil, "OVERLAY")
	Current:SetFont(SharedMedia:Fetch("font", self.Settings[key]), 14, "")
	Current:SetSize(122, 18)
	Current:SetPoint("LEFT", Selection, 5, -0.5)
	Current:SetJustifyH("LEFT")
	Current:SetShadowColor(0, 0, 0)
	Current:SetShadowOffset(1, -1)
	Current:SetText(self.Settings[key])

	local Text = Selection:CreateFontString(nil, "OVERLAY")
	Text:SetFont(SharedMedia:Fetch("font", self.Settings.WindowFont), 14, "")
	Text:SetPoint("LEFT", Selection, "RIGHT", 3, 0)
	Text:SetJustifyH("LEFT")
	Text:SetShadowColor(0, 0, 0)
	Text:SetShadowOffset(1, -1)
	Text:SetText(text)

	Selection.Tex = Tex
	Selection.Arrow = Arrow
	Selection.Current = Current
	Selection.Text = Text

	if func then
		Selection.Hook = func
	end

	tinsert(page, Line)
end

local ListOnMouseUp = function(self)
	local Selection = self:GetParent():GetParent()

	Selection.Current:SetText(self.Key)
	Selection.List:Hide()

	Gathering:UpdateSettingValue(Selection.Setting, self.Value)
	--Gathering:UpdateSettingValue(Selection.Setting, self.Key)

	if Selection.Hook then
		Selection:Hook(self.Value)
		--Selection:Hook(self.Key)
	end

	Selection.Arrow:SetTexture("Interface\\AddOns\\Gathering\\Assets\\GatheringArrowDown.tga")
end

local SelectionOnMouseUp = function(self)
	if (not self.List) then
		local List = CreateFrame("Frame", nil, self)
		List:SetSize(150, 22 * MaxSelections)
		List:SetPoint("TOP", self, "BOTTOM", 0, -1)
		List.Offset = 1
		List:EnableMouseWheel(true)
		List:SetScript("OnMouseWheel", SelectionOnMouseWheel)
		List:SetFrameStrata("TOOLTIP")
		List:SetFrameLevel(20)
		List:Hide()

		local Tex = List:CreateTexture(nil, "ARTWORK")
		Tex:SetTexture(BlankTexture)
		Tex:SetPoint("TOPLEFT", List, -2, 2)
		Tex:SetPoint("BOTTOMRIGHT", List, 2, -2)
		Tex:SetVertexColor(0.125, 0.133, 0.145)

		for Key, Value in next, self.Selections do
			local Selection = CreateFrame("Frame", nil, List)
			Selection:SetSize(140, 22)
			Selection.Key = Key
			Selection.Value = Value
			Selection:SetScript("OnMouseUp", ListOnMouseUp)
			Selection:SetScript("OnEnter", ListOnEnter)
			Selection:SetScript("OnLeave", ListOnLeave)

			local Tex = Selection:CreateTexture(nil, "ARTWORK")
			Tex:SetTexture(BlankTexture)
			Tex:SetPoint("TOPLEFT", Selection, 1, -1)
			Tex:SetPoint("BOTTOMRIGHT", Selection, -1, 1)
			Tex:SetVertexColor(0.184, 0.192, 0.211)

			local Text = Selection:CreateFontString(nil, "OVERLAY")
			Text:SetFont(SharedMedia:Fetch("font", Gathering.Settings["WindowFont"]), 14, "")
			Text:SetSize(134, 18)
			Text:SetPoint("LEFT", Selection, 5, 0)
			Text:SetJustifyH("LEFT")
			Text:SetShadowColor(0, 0, 0)
			Text:SetShadowOffset(1, -1)
			Text:SetText(Key)

			Selection.Tex = Tex
			Selection.Text = Text

			tinsert(List, Selection)
		end

		table.sort(List, function(a, b)
			return a.Key < b.Key
		end)

		if #List > (MaxSelections - 1) then
			local ScrollBar = CreateFrame("Slider", nil, List)
			ScrollBar:SetPoint("TOPLEFT", List, "TOPRIGHT", 0, 0)
			ScrollBar:SetPoint("BOTTOMLEFT", List, "BOTTOMRIGHT", 0, 0)
			ScrollBar:SetWidth(10)
			ScrollBar:SetThumbTexture(BlankTexture)
			ScrollBar:SetOrientation("VERTICAL")
			ScrollBar:SetValueStep(1)
			ScrollBar:SetMinMaxValues(1, (#List - (MaxSelections - 1)))
			ScrollBar:SetValue(1)
			ScrollBar:SetObeyStepOnDrag(true)
			ScrollBar:EnableMouseWheel(true)
			ScrollBar:SetScript("OnMouseWheel", SelectionScrollBarOnMouseWheel)
			ScrollBar:SetScript("OnValueChanged", SelectionScrollBarOnValueChanged)
			ScrollBar:SetScript("OnEnter", ScrollBarOnEnter)
			ScrollBar:SetScript("OnLeave", ScrollBarOnLeave)
			ScrollBar:SetScript("OnMouseDown", ScrollBarOnMouseDown)
			ScrollBar:SetScript("OnMouseUp", ScrollBarOnMouseUp)

			local Thumb = ScrollBar:GetThumbTexture()
			Thumb:SetSize(10, 18)
			Thumb:SetVertexColor(0.25, 0.266, 0.294)

			List.ScrollBar = ScrollBar
		else
			List:SetHeight((22 * #List) - 2)
			List:SetWidth(139)
		end

		List.Tex = Tex
		self.List = List

		ScrollSelections(List)
	end

	if self.List:IsShown() then
		self.List:Hide()
		self.Arrow:SetTexture("Interface\\AddOns\\Gathering\\Assets\\GatheringArrowDown.tga")
	else
		self.List:Show()
		self.Arrow:SetTexture("Interface\\AddOns\\Gathering\\Assets\\GatheringArrowUp.tga")
	end
end

function Gathering:CreateSelection(page, key, text, selections, func)
	local Line = CreateFrame("Frame", nil, page)
	Line:SetSize(page:GetWidth() - 8, 22)

	local Selection = CreateFrame("Frame", nil, Line)
	Selection:SetSize(Line:GetWidth(), 22)
	Selection:SetPoint("LEFT", Line, 0, 0)
	Selection:SetScript("OnMouseUp", SelectionOnMouseUp)
	Selection:SetScript("OnEnter", ListOnEnter)
	Selection:SetScript("OnLeave", WidgetOnLeave)
	Selection.Selections = selections
	Selection.Setting = key

	local Name

	for k, v in next, selections do
		if (v == self.Settings[key]) then
			Name = k
		end
	end

	local Tex = Selection:CreateTexture(nil, "ARTWORK")
	Tex:SetTexture(BlankTexture)
	Tex:SetPoint("TOPLEFT", Selection, 1, -1)
	Tex:SetPoint("BOTTOMRIGHT", Selection, -1, 1)
	Tex:SetVertexColor(0.125, 0.133, 0.145)

	local Arrow = Selection:CreateTexture(nil, "OVERLAY")
	Arrow:SetTexture("Interface\\AddOns\\Gathering\\Assets\\GatheringArrowDown.tga")
	Arrow:SetPoint("RIGHT", Selection, -3, 0)
	Arrow:SetVertexColor(1, 0.7686, 0.3019)

	local Current = Selection:CreateFontString(nil, "OVERLAY")
	Current:SetFont(SharedMedia:Fetch("font", self.Settings.WindowFont), 14, "")
	Current:SetSize(122, 18)
	Current:SetPoint("LEFT", Selection, 5, -0.5)
	Current:SetJustifyH("LEFT")
	Current:SetShadowColor(0, 0, 0)
	Current:SetShadowOffset(1, -1)
	--Current:SetText(selections[self.Settings[key]])
	Current:SetText(Name)

	local Text = Selection:CreateFontString(nil, "OVERLAY")
	Text:SetFont(SharedMedia:Fetch("font", self.Settings.WindowFont), 14, "")
	Text:SetPoint("LEFT", Selection, "RIGHT", 3, 0)
	Text:SetJustifyH("LEFT")
	Text:SetShadowColor(0, 0, 0)
	Text:SetShadowOffset(1, -1)
	Text:SetText(text)

	Selection.Tex = Tex
	Selection.Arrow = Arrow
	Selection.Current = Current
	Selection.Text = Text

	if func then
		Selection.Hook = func
	end

	tinsert(page, Line)
end

local Scroll = function(self)
	local First = false

	for i = 1, #Gathering.GUI.LeftWidgets do
		if (i >= self.Offset) and (i <= self.Offset + MaxWidgets - 1) then
			if (not First) then
				Gathering.GUI.LeftWidgets[i]:SetPoint("TOPLEFT", Gathering.GUI.LeftWidgets, 4, -4)
				First = true
			else
				Gathering.GUI.LeftWidgets[i]:SetPoint("TOPLEFT", Gathering.GUI.LeftWidgets[i-1], "BOTTOMLEFT", 0, -2)
			end

			Gathering.GUI.LeftWidgets[i]:Show()
		else
			Gathering.GUI.LeftWidgets[i]:Hide()
		end
	end

	First = false

	for i = 1, #Gathering.GUI.RightWidgets do
		if (i >= self.Offset) and (i <= self.Offset + MaxWidgets - 1) then
			if (not First) then
				Gathering.GUI.RightWidgets[i]:SetPoint("TOPLEFT", Gathering.GUI.RightWidgets, 4, -4)
				First = true
			else
				Gathering.GUI.RightWidgets[i]:SetPoint("TOPLEFT", Gathering.GUI.RightWidgets[i-1], "BOTTOMLEFT", 0, -2)
			end

			Gathering.GUI.RightWidgets[i]:Show()
		else
			Gathering.GUI.RightWidgets[i]:Hide()
		end
	end
end

local WindowOnMouseWheel = function(self, delta)
	if (delta == 1) then
		self.Offset = self.Offset - 1

		if (self.Offset <= 1) then
			self.Offset = 1
		end
	else
		self.Offset = self.Offset + 1

		if (self.Offset > (Gathering.GUI.MaxScroll - (MaxWidgets - 1))) then
			self.Offset = self.Offset - 1
		end
	end

	Scroll(self)
	self.ScrollBar:SetValue(self.Offset)
end

local ScrollBarOnValueChanged = function(self, value)
	local Value = floor(value + 0.5)

	self.Parent.Offset = Value

	Scroll(self.Parent)
end

function Gathering:UpdateFontSetting(value)
	Gathering.Text:SetFont(SharedMedia:Fetch("font", value), 14, "")
	Gathering:UpdateTooltipFont()
end

function Gathering:UpdateDisplayMode(value)
	if (value == "TIME") then
		Gathering.Text:SetText(date("!%X", Gathering.Seconds))

		Gathering.Int = 1
	elseif (value == "GPH") then
		if (Gathering.GoldGained > 0) then
			Gathering.Text:SetFormattedText("GPH: %s", Gathering:CopperToGold(floor((Gathering.GoldGained / max(GetTime() - Gathering.GoldTimer, 1)) * 60 * 60)))
		else
			Gathering.Text:SetFormattedText("GPH: %s", Gathering:CopperToGold(0))
		end

		Gathering.Int = 2
	elseif (value == "GOLD") then
		Gathering.Text:SetText(Gathering:CopperToGold(Gathering.GoldGained))
	elseif (value == "TOTAL") then
		Gathering.Text:SetFormattedText("Total: %s", Gathering.TotalGathered)
	end
end

function Gathering:ShowPage(name)
	for i = 1, #self.Windows do
		if (self.Windows[i].Name == name) then
			self.Windows[i]:Show()
		else
			self.Windows[i]:Hide()
		end
	end
end

function Gathering:GetPage(name)
	for i = 1, #self.Windows do
		if (self.Windows[i].Name == name) then
			return self.Windows[i]
		end
	end
end

function Gathering:PageTabOnEnter()
	self:SetBackdropColor(0.25, 0.266, 0.294)
end

function Gathering:PageTabOnLeave()
	self:SetBackdropColor(0.184, 0.192, 0.211)
end

function Gathering:PageTabOnMouseUp()
	Gathering:ShowPage(self.Name)

	self.Text:ClearAllPoints()
	self.Text:SetPoint("LEFT", self, 5, -0.5)
end

function Gathering:PageTabOnMouseDown()
	self.Text:ClearAllPoints()
	self.Text:SetPoint("LEFT", self, 6, -1.5)
end

function Gathering:AddPage(name)
	local Tab = CreateFrame("Frame", nil, self.GUI.TabParent, "BackdropTemplate")
	Tab:SetSize(72, 22)
	Tab:SetBackdrop(Outline)
	Tab:SetBackdropColor(0.184, 0.192, 0.211)
	Tab:SetScript("OnEnter", self.PageTabOnEnter)
	Tab:SetScript("OnLeave", self.PageTabOnLeave)
	Tab:SetScript("OnMouseUp", self.PageTabOnMouseUp)
	Tab:SetScript("OnMouseDown", self.PageTabOnMouseDown)

	local Text = Tab:CreateFontString(nil, "OVERLAY")
	Text:SetPoint("LEFT", Tab, 5, -0.5)
	Text:SetFont(SharedMedia:Fetch("font", self.Settings.WindowFont), 14, "")
	Text:SetJustifyH("LEFT")
	Text:SetShadowColor(0, 0, 0)
	Text:SetShadowOffset(1, -1)
	Text:SetText(name)

	Tab.Name = name
	Tab.Text = Text

	local Page = CreateFrame("Frame", nil, self.GUI.Window)
	Page:SetAllPoints()
	Page.Name = name

	table.insert(self.Tabs, Tab)
	table.insert(self.Windows, Page)

	return Page
end

function Gathering:SortWidgets(widgets)
	for i = 1, #widgets do
		if (i == 1) then
			widgets[i]:SetPoint("TOPLEFT", widgets, 4, -4)
		else
			widgets[i]:SetPoint("TOPLEFT", widgets[i-1], "BOTTOMLEFT", 0, -4)
		end
	end
end

function Gathering:SortWidgetsWide(widgets)
	for i = 1, #widgets do
		if (i == 1) then
			widgets[i]:SetPoint("TOPLEFT", widgets, 4, -30)
		elseif ((i - 1) % 3 == 0) then
			widgets[i]:SetPoint("TOPLEFT", widgets[i-3], "BOTTOMLEFT", 0, -4)
		else
			widgets[i]:SetPoint("LEFT", widgets[i-1], "RIGHT", 4, 0)
		end
	end
end

function Gathering:SetupTrackingPage(page)
	local TopWidgets = CreateFrame("Frame", nil, page, "BackdropTemplate")
	TopWidgets:SetSize(page:GetWidth(), 133)
	TopWidgets:SetPoint("TOPLEFT", page, 0, 0)
	TopWidgets:EnableMouse(true)
	TopWidgets:SetBackdrop(Outline)
	TopWidgets:SetBackdropColor(0.184, 0.192, 0.211)

	local LeftWidgets = CreateFrame("Frame", nil, page, "BackdropTemplate")
	LeftWidgets:SetSize(199, 107)
	LeftWidgets:SetPoint("TOPLEFT", TopWidgets, "BOTTOMLEFT", 0, -6)
	LeftWidgets:EnableMouse(true)
	LeftWidgets:SetBackdrop(Outline)
	LeftWidgets:SetBackdropColor(0.184, 0.192, 0.211)

	page.TopWidgets = TopWidgets
	page.LeftWidgets = LeftWidgets

	self:CreateHeader(TopWidgets, TRACKING)

	self:SortWidgets(TopWidgets)

	table.remove(TopWidgets, 1)

	self:CreateCheckbox(TopWidgets, "track-herbs", L["Herbs"], self.UpdateHerbTracking)
	self:CreateCheckbox(TopWidgets, "track-cloth", L["Cloth"], self.UpdateClothTracking)
	self:CreateCheckbox(TopWidgets, "track-leather", L["Leather"], self.UpdateLeatherTracking)
	self:CreateCheckbox(TopWidgets, "track-ore", L["Ore"], self.UpdateOreTracking)
	self:CreateCheckbox(TopWidgets, "track-jewelcrafting", L["Jewelcrafting"], self.UpdateJewelcraftingTracking)
	self:CreateCheckbox(TopWidgets, "track-enchanting", L["Enchanting"], self.UpdateEnchantingTracking)
	self:CreateCheckbox(TopWidgets, "track-cooking", L["Cooking"], self.UpdateCookingTracking)
	self:CreateCheckbox(TopWidgets, "track-reagents", L["Reagents"], self.UpdateReagentTracking)
	self:CreateCheckbox(TopWidgets, "track-consumable", L["Consumables"], self.UpdateConsumableTracking)
	self:CreateCheckbox(TopWidgets, "track-holiday", L["Holiday"], self.UpdateHolidayTracking)
	self:CreateCheckbox(TopWidgets, "track-quest", L["Quests"], self.UpdateQuestTracking)
	self:CreateCheckbox(TopWidgets, "track-xp", L["XP"])

	self:CreateHeader(LeftWidgets, MISCELLANEOUS)

	self:CreateCheckbox(LeftWidgets, "ignore-bop", L["Ignore Bind on Pickup"])
	self:CreateCheckbox(LeftWidgets, "IgnoreMailItems", L["Ignore mail items"])
	self:CreateCheckbox(LeftWidgets, "IgnoreMailMoney", L["Ignore mail gold"])

	self:SortWidgetsWide(TopWidgets)
	self:SortWidgets(LeftWidgets)
end

function Gathering:SetupSettingsPage(page)
	local LeftWidgets = CreateFrame("Frame", nil, page, "BackdropTemplate")
	LeftWidgets:SetSize(199, 246)
	LeftWidgets:SetPoint("LEFT", page, 0, 0)
	LeftWidgets:EnableMouse(true)
	LeftWidgets:SetBackdrop(Outline)
	LeftWidgets:SetBackdropColor(0.184, 0.192, 0.211)

	local RightWidgets = CreateFrame("Frame", nil, page, "BackdropTemplate")
	RightWidgets:SetSize(198, 246)
	RightWidgets:SetPoint("LEFT", LeftWidgets, "RIGHT", 6, 0)
	RightWidgets:EnableMouse(true)
	RightWidgets:SetBackdrop(Outline)
	RightWidgets:SetBackdropColor(0.184, 0.192, 0.211)

	page.LeftWidgets = LeftWidgets
	page.RightWidgets = RightWidgets

	self:CreateHeader(LeftWidgets, L["Display Mode"])
	self:CreateSelection(LeftWidgets, "DisplayMode", "", DisplayModes, self.UpdateDisplayMode)

	self:CreateHeader(LeftWidgets, L["Set Font"])

	self:CreateFontSelection(LeftWidgets, "WindowFont", "", self.Fonts, self.UpdateFontSetting)

	self:CreateHeader(LeftWidgets, WINDOW_SIZE_LABEL)

	self:CreateNumberEditBox(LeftWidgets, "WindowWidth", COMPACT_UNIT_FRAME_PROFILE_FRAMEWIDTH, self.SetFrameWidth)
	self:CreateNumberEditBox(LeftWidgets, "WindowHeight", COMPACT_UNIT_FRAME_PROFILE_FRAMEHEIGHT, self.SetFrameHeight)

	self:CreateHeader(RightWidgets, MISCELLANEOUS)

	self:CreateCheckbox(RightWidgets, "hide-idle", L["Hide while idle"], self.ToggleTimerPanel)
	self:CreateCheckbox(RightWidgets, "ShowTooltipHelp", L["Show tooltip help"])


	self:CreateHeader(RightWidgets, BAGSLOTTEXT)

	self:CreateCheckbox(RightWidgets, "EnableSlotBar", SHOW_FREE_BAG_SLOTS_TEXT, self.ToggleSlotBar)
	self:CreateCheckbox(RightWidgets, "SlotBarTooltip", L["Enable Tooltip"])
	self:CreateNumberEditBox(RightWidgets, "SlotBarHeight", COMPACT_UNIT_FRAME_PROFILE_FRAMEHEIGHT, self.UpdateSlotBarHeight)

	self:SortWidgets(LeftWidgets)
	self:SortWidgets(RightWidgets)
end

local IgnoreWindowOnMouseWheel = function(self, delta)
	if (delta == 1) then
		self.Offset = self.Offset - 1

		if (self.Offset <= 1) then
			self.Offset = 1
		end
	else
		self.Offset = self.Offset + 1

		if (self.Offset > (#page.IgnoredItems - 11)) then
			self.Offset = self.Offset - 1
		end
	end

	ScrollIgnoredItems(self)
	self.ScrollBar:SetValue(self.Offset)
end

local IgnoreScrollBarOnValueChanged = function(self, value)
	local Value = floor(value + 0.5)

	self.Parent.Offset = Value

	ScrollIgnoredItems(self.Parent)
end

function Gathering:SetupIgnorePage(page)
	local LeftWidgets = CreateFrame("Frame", nil, page, "BackdropTemplate")
	LeftWidgets:SetSize(199, 246)
	LeftWidgets:SetPoint("LEFT", page, 0, 0)
	LeftWidgets:EnableMouse(true)
	LeftWidgets:SetBackdrop(Outline)
	LeftWidgets:SetBackdropColor(0.184, 0.192, 0.211)

	local IgnoredList = CreateFrame("Frame", nil, page, "BackdropTemplate")
	IgnoredList:SetSize(198, 246)
	IgnoredList:SetPoint("LEFT", LeftWidgets, "RIGHT", 6, 0)
	IgnoredList:EnableMouse(true)
	IgnoredList:SetBackdrop(Outline)
	IgnoredList:SetBackdropColor(0.184, 0.192, 0.211)

	page.LeftWidgets = LeftWidgets
	page.IgnoredList = IgnoredList

	page.IgnoredItems = {}

	self:CreateHeader(LeftWidgets, IGNORE)

	self:CreateEditBox(LeftWidgets, L["Ignore items"], self.AddIgnoredItem)

	self:SortWidgets(LeftWidgets)

	-- Add ignored items
	if GatheringIgnore then
		local Name, Link

		for ID in next, GatheringIgnore do
			Name, Link = GetItemInfo(ID)

			if (Name and Link) then
				local Line = CreateFrame("Frame", nil, page, "BackdropTemplate")
				Line:SetSize(IgnoredList:GetWidth() - 24, 22)
				Line.Item = ID

				Line.Text = Line:CreateFontString(nil, "OVERLAY")
				Line.Text:SetFont(SharedMedia:Fetch("font", self.Settings.WindowFont), 14, "")
				Line.Text:SetPoint("LEFT", Line, 5, 0)
				Line.Text:SetJustifyH("LEFT")
				Line.Text:SetShadowColor(0, 0, 0)
				Line.Text:SetShadowOffset(1, -1)
				Line.Text:SetText(Link or Name)

				Line.CloseButton = CreateFrame("Frame", nil, Line)
				Line.CloseButton:SetPoint("RIGHT", Line, 0, 0)
				Line.CloseButton:SetSize(24, 24)
				Line.CloseButton:SetScript("OnEnter", function(self) self.Texture:SetVertexColor(1, 0, 0) end)
				Line.CloseButton:SetScript("OnLeave", function(self) self.Texture:SetVertexColor(1, 1, 1) end)
				Line.CloseButton:SetScript("OnMouseUp", function(self) Gathering:RemoveIgnoredItem(self:GetParent().Item) end)

				Line.CloseButton.Texture = Line.CloseButton:CreateTexture(nil, "OVERLAY")
				Line.CloseButton.Texture:SetPoint("CENTER", Line.CloseButton, 0, -0.5)
				Line.CloseButton.Texture:SetTexture("Interface\\AddOns\\Gathering\\Assets\\HydraUIClose.tga")

				tinsert(page.IgnoredItems, Line)
			else
				Item:CreateFromItemID(ID):ContinueOnItemLoad(function()
					Name, Link = GetItemInfo(ID)

					local Line = CreateFrame("Frame", nil, page, "BackdropTemplate")
					Line:SetSize(IgnoredList:GetWidth() - 24, 22)
					Line.Item = ID

					Line.Text = Line:CreateFontString(nil, "OVERLAY")
					Line.Text:SetFont(SharedMedia:Fetch("font", self.Settings.WindowFont), 14, "")
					Line.Text:SetPoint("LEFT", Line, 5, 0)
					Line.Text:SetJustifyH("LEFT")
					Line.Text:SetShadowColor(0, 0, 0)
					Line.Text:SetShadowOffset(1, -1)
					Line.Text:SetText(Link or Name)

					Line.CloseButton = CreateFrame("Frame", nil, Line)
					Line.CloseButton:SetPoint("RIGHT", Line, 0, 0)
					Line.CloseButton:SetSize(24, 24)
					Line.CloseButton:SetScript("OnEnter", function(self) self.Texture:SetVertexColor(1, 0, 0) end)
					Line.CloseButton:SetScript("OnLeave", function(self) self.Texture:SetVertexColor(1, 1, 1) end)
					Line.CloseButton:SetScript("OnMouseUp", function(self) Gathering:RemoveIgnoredItem(self:GetParent().Item) end)

					Line.CloseButton.Texture = Line.CloseButton:CreateTexture(nil, "OVERLAY")
					Line.CloseButton.Texture:SetPoint("CENTER", Line.CloseButton, 0, -0.5)
					Line.CloseButton.Texture:SetTexture("Interface\\AddOns\\Gathering\\Assets\\HydraUIClose.tga")

					tinsert(page.IgnoredItems, Line)

					ScrollIgnoredItems(page)
				end)
			end
		end
	end

	page.Offset = 1

	-- Scroll bar
	local ScrollBar = CreateFrame("Slider", nil, page.IgnoredList)
	ScrollBar:SetWidth(12)
	ScrollBar:SetPoint("TOPRIGHT", page.IgnoredList, -4, -4)
	ScrollBar:SetPoint("BOTTOMRIGHT", page.IgnoredList, -4, 4)
	ScrollBar:SetFrameStrata("HIGH")
	ScrollBar:SetFrameLevel(20)
	ScrollBar:SetThumbTexture(BlankTexture)
	ScrollBar:SetOrientation("VERTICAL")
	ScrollBar:SetValueStep(1)
	ScrollBar:SetMinMaxValues(1, math.max(1, #page.IgnoredItems - 9))
	ScrollBar:SetValue(1)
	ScrollBar:EnableMouse(true)
	ScrollBar:SetScript("OnValueChanged", IgnoreScrollBarOnValueChanged)
	ScrollBar:SetScript("OnMouseWheel", IgnoreWindowOnMouseWheel)
	ScrollBar:SetScript("OnEnter", ScrollBarOnEnter)
	ScrollBar:SetScript("OnLeave", ScrollBarOnLeave)
	ScrollBar:SetScript("OnMouseDown", ScrollBarOnMouseDown)
	ScrollBar:SetScript("OnMouseUp", ScrollBarOnMouseUp)
	ScrollBar.Parent = page

	local Thumb = ScrollBar:GetThumbTexture()
	Thumb:SetSize(12, 22)
	Thumb:SetVertexColor(0.25, 0.266, 0.294)

	page.ScrollBar = ScrollBar

	ScrollIgnoredItems(page)
end

Gathering.Donors = {
	"Innie", "Brightsides", "Erthelmi", "Gene", "JDoubleU00", "Duds", "Shazlen", "Shawna W", "Dillan", "Bruce N","last", "Wrynn",
	"Ryxân", "Andrei B", "Anthony M", "AtticaOnline", "Hawksworth", "WingZero", "Elizabeth T", "Quadra", "Brandon W", "Richard S",
	"Andreas M", "Morgana N", "LeeMcMurtry",
}

--local Tiers = {"FF8000", "A335EE", "0070DD", "1EFF00", "FFFFFF"}

Gathering.Patrons = {
	"|cffFF8000Dragonhawk|r", "|cffFF8000Halven|r",
	"|cff0070DDdeck|r",
	"|cff1EFF00JDoubleU00|r", "|cff1EFF00sylvester|r", "|cff1EFF00thurin|r",
	--
	"Paul D.",
}

Gathering.ExPatrons = {
	"|cffFF8000SwoopCrown|r", "|cffFF8000Cheeso_76|r", "|cffFF8000Erieeroot|r", "|cffFF8000last|r",
	"|cffA335EESmelly|r", "|cffA335EETrix|r", "|cffA335EEwolimazo|r", "|cffA335EEAri|r", "|cffA335EEMrPoundsign|r",
	"|cff0070DDEuphoria|r", "|cff0070DDMitooshin|r", "|cff0070DDMisseFar|r", "|cff0070DDFrankPatten|r", "|cff0070DDDillan|r", "|cff0070DDQuiet|r",
	"|cff1EFF00Maski|r", "|cff1EFF00Raze|r", "|cff1EFF00Ingrimmosch|r", "|cff1EFF00Chris B.|r", "|cff1EFF00Suppabad|r", "|cff1EFF00Aaron B.|r", "|cff1EFF00Steve R.|r", "|cff1EFF00Angel|r", "|cff1EFF00Jeor|r", "|cff1EFF00Mcbooze|r", "|cff1EFF00stko|r", "|cff1EFF00Syn|r", "|cff1EFF00Rytok|r", "|cff1EFF00Ryex|r", "|cff1EFF00Blom|r", "|cff1EFF00Innie|r", "|cff1EFF00Cyber|r", "|cff1EFF00protocol7|r", "|cff1EFF00Dellamaik|r",
	"Akab00m", "OzzFreak", "madmaddy", "Uzify", "Erthelmi", "silence", "momzzze", "Oxymorphone",
}

function Gathering:CreateNameButton(list, parent, name, size)
	local Button = CreateFrame("Frame", nil, parent, "BackdropTemplate")
	Button:EnableMouse(true)
	Button:SetBackdrop(Outline)
	Button:SetBackdropColor(0.184, 0.192, 0.211)
	--Button:SetScript("OnEnter", function(self) self:SetBackdropColor(0.25, 0.266, 0.294) self.Text:SetTextColor(1, 1, 0) end)
	--Button:SetScript("OnLeave", function(self) self:SetBackdropColor(0.184, 0.192, 0.211) self.Text:SetTextColor(1, 1, 1) end)

	Button:SetScript("OnEnter", function(self) self.Text:SetTextColor(1, 1, 0) end)
	Button:SetScript("OnLeave", function(self) self.Text:SetTextColor(1, 1, 1) end)

	local Text = Button:CreateFontString(nil, "OVERLAY")
	Text:SetFont(SharedMedia:Fetch("font", self.Settings.WindowFont), size, "")
	Text:SetPoint("CENTER", Button, 0, -1)
	Text:SetJustifyH("LEFT")
	Text:SetShadowColor(0, 0, 0)
	Text:SetShadowOffset(1, -1)
	Text:SetText(name)

	Button:SetSize(Text:GetStringWidth() + 2, size + 2)

	Button.Text = Text

	table.insert(list, Button)
end

function Gathering:SortNameButtons(list, parent)
	local Length = 0
	local LastAnchor = list[1]
	local CurrentWidth = 0

	for i = 1, #list do
		CurrentWidth = list[i]:GetWidth() + 2

		if (i == 1) then
			list[i]:SetPoint("TOPLEFT", parent, 3, -33)
			Length = Length + CurrentWidth
		elseif ((Length + CurrentWidth) >= (parent:GetWidth() - 4)) then
			list[i]:SetPoint("TOPLEFT", LastAnchor, "BOTTOMLEFT", 0, -2)
			LastAnchor = list[i]
			Length = CurrentWidth
		else
			list[i]:SetPoint("LEFT", list[i-1], "RIGHT", 2, 0)
			Length = Length + CurrentWidth
		end
	end
end

function Gathering:SetupSupporterPage(page)
	local PatronWidgets = CreateFrame("Frame", nil, page, "BackdropTemplate")
	PatronWidgets:SetSize(199, 68)
	PatronWidgets:SetPoint("TOPLEFT", page, 0, 0)
	PatronWidgets:EnableMouse(true)
	PatronWidgets:SetBackdrop(Outline)
	PatronWidgets:SetBackdropColor(0.184, 0.192, 0.211)

	local ExPatronWidgets = CreateFrame("Frame", nil, page, "BackdropTemplate")
	ExPatronWidgets:SetSize(199, 172)
	ExPatronWidgets:SetPoint("TOPLEFT", PatronWidgets, "BOTTOMLEFT", 0, -6)
	ExPatronWidgets:EnableMouse(true)
	ExPatronWidgets:SetBackdrop(Outline)
	ExPatronWidgets:SetBackdropColor(0.184, 0.192, 0.211)

	local DonorWidgets = CreateFrame("Frame", nil, page, "BackdropTemplate")
	DonorWidgets:SetSize(198, 246)
	DonorWidgets:SetPoint("TOPLEFT", PatronWidgets, "TOPRIGHT", 6, 0)
	DonorWidgets:EnableMouse(true)
	DonorWidgets:SetBackdrop(Outline)
	DonorWidgets:SetBackdropColor(0.184, 0.192, 0.211)

	page.PatronWidgets = PatronWidgets
	page.ExPatronWidgets = ExPatronWidgets
	page.DonorWidgets = DonorWidgets

	local DonorButtons = {}
	local PatronButtons = {}
	local ExPatronButtons = {}

	for i = 1, #self.Patrons do
		Gathering:CreateNameButton(PatronButtons, PatronWidgets, self.Patrons[i], 12)
	end

	for i = 1, #self.Donors do
		Gathering:CreateNameButton(DonorButtons, DonorWidgets, self.Donors[i], 12)
	end

	for i = 1, #self.ExPatrons do
		Gathering:CreateNameButton(ExPatronButtons, ExPatronWidgets, self.ExPatrons[i], 10)
	end

	Gathering:SortNameButtons(PatronButtons, PatronWidgets)
	Gathering:SortNameButtons(DonorButtons, DonorWidgets)
	Gathering:SortNameButtons(ExPatronButtons, ExPatronWidgets)

	self:CreateHeader(PatronWidgets, "Patrons")
	self:CreateHeader(DonorWidgets, "Donors")
	self:CreateHeader(ExPatronWidgets, "Former Patrons")

	self:SortWidgets(PatronWidgets)
	self:SortWidgets(DonorWidgets)
	self:SortWidgets(ExPatronWidgets)
end

function Gathering:CreateStatLine(page, text)
	local Line = CreateFrame("Frame", nil, page, "BackdropTemplate")
	Line:SetSize(page:GetWidth() - 8, 22)
	Line:SetBackdrop(Outline)
	Line:SetBackdropColor(0.184, 0.192, 0.211)
	Line:SetScript("OnEnter", self.PageTabOnEnter)
	Line:SetScript("OnLeave", self.PageTabOnLeave)

	local Text = Line:CreateFontString(nil, "OVERLAY")
	Text:SetFont(SharedMedia:Fetch("font", self.Settings.WindowFont), 14, "")
	Text:SetPoint("LEFT", Line, 5, 0)
	Text:SetJustifyH("LEFT")
	Text:SetShadowColor(0, 0, 0)
	Text:SetShadowOffset(1, -1)
	Text:SetText(text)

	Line.Text = Text

	tinsert(page, Line)

	return Line
end

function Gathering:StatsPageOnUpdate(elapsed)
	self.Ela = self.Ela + elapsed

	if (self.Ela > 10) then
		Gathering:UpdateMoneyStat()
		Gathering:UpdateXPStat()
		Gathering:UpdateItemsStat()
		self.Ela = 0
	end
end

function Gathering:StatsPageOnShow()
	self.Ela = 0

	Gathering:UpdateMoneyStat()
	Gathering:UpdateXPStat()
	Gathering:UpdateItemsStat()

	self:SetScript("OnUpdate", Gathering.StatsPageOnUpdate)
end

function Gathering:StatsPageOnHide()
	self:SetScript("OnUpdate", nil)
end

function Gathering:SetupStatsPage(page)
	local LeftWidgets = CreateFrame("Frame", nil, page, "BackdropTemplate")
	LeftWidgets:SetSize(199, 246)
	LeftWidgets:SetPoint("LEFT", page, 0, 0)
	LeftWidgets:EnableMouse(true)
	LeftWidgets:SetBackdrop(Outline)
	LeftWidgets:SetBackdropColor(0.184, 0.192, 0.211)

	local RightWidgets = CreateFrame("Frame", nil, page, "BackdropTemplate")
	RightWidgets:SetSize(198, 246)
	RightWidgets:SetPoint("LEFT", LeftWidgets, "RIGHT", 6, 0)
	RightWidgets:EnableMouse(true)
	RightWidgets:SetBackdrop(Outline)
	RightWidgets:SetBackdropColor(0.184, 0.192, 0.211)

	page.LeftWidgets = LeftWidgets
	page.RightWidgets = RightWidgets

	page:SetScript("OnShow", self.StatsPageOnShow)
	page:SetScript("OnHide", self.StatsPageOnHide)

	page.Stats = {}

	if (not GatheringStats) then
		GatheringStats = {}
	end

	local PerSec = (self.XPGained / (GetTime() - self.XPStartTime)) or 0

	self:CreateHeader(RightWidgets, L["XP"])
	page.Stats.sessionxp = self:CreateStatLine(RightWidgets, format(L["Session: %s"], self.SessionStats.xp or 0))
	page.Stats.PerHour = self:CreateStatLine(RightWidgets, format(L["XP / Hr: %s"], self:Comma((PerSec * 60) * 60)))

	if (self.XPGained and self.XPGained > 0) then
		page.Stats.TTL = self:CreateStatLine(RightWidgets, format(L["%s until level"], self:FormatFullTime((UnitXPMax("player") - UnitXP("player")) / PerSec)))
	else
		page.Stats.TTL = self:CreateStatLine(RightWidgets, L["0s until level"])
	end

	self:CreateHeader(RightWidgets, L["Overall stats"])
	page.Stats.xp = self:CreateStatLine(RightWidgets, format(L["XP Gained: %s"], self:Comma(GatheringStats.xp) or 0))
	page.Stats.levels = self:CreateStatLine(RightWidgets, format(L["Levels Gained: %s"], GatheringStats.levels or 0))
	page.Stats.totalgold = self:CreateStatLine(RightWidgets, format(L["Gold Looted: %s"], self:CopperToGold(GatheringStats.gold or 0)))
	page.Stats.totalitems = self:CreateStatLine(RightWidgets, format(L["Items Looted: %s"], self:Comma(GatheringStats.total) or 0))

	self:CreateHeader(LeftWidgets, L["Gold"])
	page.Stats.sessiongold = self:CreateStatLine(LeftWidgets, format(L["Profit: %s"], self:CopperToGold(Gathering.GoldGained or 0)))
	page.Stats.gph = self:CreateStatLine(LeftWidgets, format(L["Gold Per Hour: %s"], self:CopperToGold(Gathering.GoldGained or 0)))
	page.Stats.bagvalue = self:CreateStatLine(LeftWidgets, format(L["Inventory Trash Value: %s"], self:CopperToGold(self:GetTrashValue())))

	self:CreateHeader(LeftWidgets, L["Items"])
	page.Stats.items = self:CreateStatLine(LeftWidgets, format(L["Items Looted: %s"], self.SessionStats.total or 0))
	--page.Stats.itemsphr = self:CreateStatLine(LeftWidgets, format("Items Per Hour: %s", 0))

	if GatheringStats.clouds then
		page.Stats.clouds = self:CreateStatLine(LeftWidgets, format(L["Gas Clouds: %s"], self:Comma(GatheringStats.clouds) or 0))
	end

	self:SortWidgets(LeftWidgets)
	self:SortWidgets(RightWidgets)
end

function Gathering:UpdateItemsStat()
	if (not self.Windows) then
		return
	end

	local page = self:GetPage(L["Stats"])

	if (not page) then
		return
	end

	if page.Stats.totalitems then
		page.Stats.totalitems.Text:SetText(format(L["Items Looted: %s"], self:Comma(GatheringStats.total) or 0))
	end

	if page.Stats.items then
		page.Stats.items.Text:SetText(format(L["Items Looted: %s"], self:Comma(self.SessionStats.total) or 0))
	end

	if page.Stats.bagvalue then
		page.Stats.bagvalue.Text:SetText(format(L["Inventory Trash Value: %s"], self:CopperToGold(self:GetTrashValue())))
	end
end

function Gathering:UpdateXPStat()
	if (not self.Windows) then
		return
	end

	local page = self:GetPage(L["Stats"])

	if (not page) then
		return
	end

	if page.Stats.xp then
		page.Stats.xp.Text:SetText(format(L["XP Gained: %s"], self:Comma(GatheringStats.xp) or 0))
	end

	if page.Stats.sessionxp then
		page.Stats.sessionxp.Text:SetText(format(L["Session: %s"], self:Comma(Gathering.XPGained) or 0))
	end

	local PerSec = (self.XPGained / (GetTime() - self.XPStartTime)) or 0

	if page.Stats.PerHour then
		page.Stats.PerHour.Text:SetText(format(L["XP / Hr: %s"], self:Comma((PerSec * 60) * 60)))
	end

	if page.Stats.TTL then
		if (self.XPGained > 0) then
			page.Stats.TTL.Text:SetText(format(L["%s until level"], self:FormatFullTime((UnitXPMax("player") - UnitXP("player")) / PerSec)))
		else
			page.Stats.TTL.Text:SetText(L["0s until level"])
		end
	end

	if page.Stats.levels then
		page.Stats.levels.Text:SetText(format(L["Levels Gained: %s"], GatheringStats.levels or 0))
	end
end

function Gathering:UpdateMoneyStat()
	if (not self.Windows) then
		return
	end

	local page = self:GetPage(L["Stats"])

	if (not page) then
		return
	end

	if page.Stats.totalgold then
		page.Stats.totalgold.Text:SetText(format(L["Gold Looted: %s"], self:CopperToGold(GatheringStats.gold) or 0))
	end

	if page.Stats.sessiongold then
		page.Stats.sessiongold.Text:SetText(format(L["Profit: %s"], self:CopperToGold(Gathering.GoldGained) or 0))
	end

	if page.Stats.gph then
		page.Stats.gph.Text:SetText(format(L["GPH: %s"], self:CopperToGold(floor((self.GoldGained / max(GetTime() - self.GoldTimer, 1)) * 60 * 60))))
	end
end

function Gathering:CreateGUI()
	self.Windows = {}
	self.Tabs = {}

	-- Window
	local GUI = CreateFrame("Frame", "Gathering Settings", UIParent, "BackdropTemplate")
	GUI:SetSize(490, 24)
	GUI:SetPoint("CENTER", UIParent, 0, 160)
	GUI:SetMovable(true)
	GUI:EnableMouse(true)
	GUI:SetUserPlaced(true)
	GUI:SetClampedToScreen(true)
	GUI:RegisterForDrag("LeftButton")
	GUI:SetScript("OnDragStart", GUI.StartMoving)
	GUI:SetScript("OnDragStop", GUI.StopMovingOrSizing)
	GUI:SetBackdrop(Outline)
	GUI:SetBackdropColor(0.184, 0.192, 0.211)
	GUI:SetFrameStrata("DIALOG")
	GUI:SetFrameLevel(20)

	local HeaderText = GUI:CreateFontString(nil, "OVERLAY")
	HeaderText:SetPoint("LEFT", GUI, 6, -0.5)
	HeaderText:SetFont(SharedMedia:Fetch("font", self.Settings.WindowFont), 12, "")
	HeaderText:SetJustifyH("LEFT")
	HeaderText:SetShadowColor(0, 0, 0)
	HeaderText:SetShadowOffset(1, -1)
	HeaderText:SetText("|cffFFC44DGathering|r " .. (C_AddOns and C_AddOns.GetAddOnMetadata or GetAddOnMetadata)("Gathering", "Version"))

	local CloseButton = CreateFrame("Frame", nil, GUI)
	CloseButton:SetPoint("RIGHT", GUI, 0, 0)
	CloseButton:SetSize(24, 24)
	CloseButton:SetScript("OnEnter", function(self) self.Texture:SetVertexColor(1, 0, 0) end)
	CloseButton:SetScript("OnLeave", function(self) self.Texture:SetVertexColor(1, 1, 1) end)
	CloseButton:SetScript("OnMouseUp", function() GUI:Hide() end)

	local CloseTexture = CloseButton:CreateTexture(nil, "OVERLAY")
	CloseTexture:SetPoint("CENTER", CloseButton, 0, -0.5)
	CloseTexture:SetTexture("Interface\\AddOns\\Gathering\\Assets\\HydraUIClose.tga")

	local TabParent = CreateFrame("Frame", nil, GUI, "BackdropTemplate")
	TabParent:SetSize(80, 246)
	TabParent:SetPoint("TOPLEFT", GUI, "BOTTOMLEFT", 0, -6)
	TabParent:SetBackdrop(Outline)
	TabParent:SetBackdropColor(0.184, 0.192, 0.211)

	local Window = CreateFrame("Frame", nil, GUI)
	Window:SetSize(403, 246)
	Window:SetPoint("LEFT", TabParent, "RIGHT", 7, 0)

	local OuterBackdrop = CreateFrame("Frame", nil, Window, "BackdropTemplate")
	OuterBackdrop:SetPoint("TOPLEFT", GUI, -6, 6)
	OuterBackdrop:SetPoint("BOTTOMRIGHT", Window, 6, -6)
	OuterBackdrop:SetBackdrop(Outline)
	OuterBackdrop:SetBackdropColor(0.125, 0.133, 0.145)
	OuterBackdrop:SetFrameStrata("BACKGROUND")
	OuterBackdrop:SetFrameLevel(0)

	CloseButton.Texture = CloseTexture
	GUI.TabParent = TabParent
	GUI.Window = Window

	self.GUI = GUI

	local SettingsPage = self:AddPage(L["Settings"])
	self:SetupSettingsPage(SettingsPage)

	local TrackingPage = self:AddPage(L["Tracking"])
	self:SetupTrackingPage(TrackingPage)

	local IgnorePage = self:AddPage(L["Ignore"])
	self:SetupIgnorePage(IgnorePage)

	local StatsPage = self:AddPage(L["Stats"])
	self:SetupStatsPage(StatsPage)

	for i = 1, #self.Tabs do
		if (i == 1) then
			self.Tabs[i]:SetPoint("TOPLEFT", self.GUI.TabParent, 4, -4)
		else
			self.Tabs[i]:SetPoint("TOPLEFT", self.Tabs[i-1], "BOTTOMLEFT", 0, -4)
		end
	end

	-- Separate tab at bottom of the list
	-- local SupporterPage = self:AddPage("Supporters")
	-- self:SetupSupporterPage(SupporterPage)
	-- self.Tabs[#self.Tabs]:SetPoint("BOTTOMLEFT", self.GUI.TabParent, 4, 4)

	self:ShowPage(L["Settings"])
end

function Gathering:MODIFIER_STATE_CHANGED()
	if self.MouseIsOver then
		self.Tooltip:ClearLines()
		self:OnEnter()
	end
end

function Gathering:OnTooltipSetItem()
	if (not Gathering.Settings["show-tooltip"]) then
		return
	end

	local Item, Link = self:GetItem()

	if Item then
		local Price = Gathering:GetPrice(Link)

		if (Price and Price > 0) then
			self:AddLine(" ")
			self:AddLine("|cffFFC44DGathering|r")
			self:AddLine(format(L["Price per unit: %s"], Gathering:CopperToGold(Price)), 1, 1, 1)
		end
	end
end

function Gathering:PLAYER_ENTERING_WORLD()
	if (not self.Initial) then
		local IsAddOnLoaded = C_AddOns and C_AddOns.IsAddOnLoaded or IsAddOnLoaded

		self.Ignored = GatheringIgnore or {}

		if IsAddOnLoaded("TradeSkillMaster") then
			self.HasTSM = true
		end

		--[[if TooltipDataProcessor then
			TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Item, self.OnTooltipSetItem)
		else
			GameTooltip:HookScript("OnTooltipSetItem", self.OnTooltipSetItem)
		end]]

		if (not GatheringSettings) then
			GatheringSettings = {}
		end

		self.Settings = setmetatable(GatheringSettings, {__index = self.DefaultSettings})

		self:CreateWindow()

		self:UpdateHerbTracking(self.Settings["track-herbs"])
		self:UpdateClothTracking(self.Settings["track-cloth"])
		self:UpdateLeatherTracking(self.Settings["track-leather"])
		self:UpdateOreTracking(self.Settings["track-ore"])
		self:UpdateJewelcraftingTracking(self.Settings["track-jewelcrafting"])
		self:UpdateEnchantingTracking(self.Settings["track-enchanting"])
		self:UpdateCookingTracking(self.Settings["track-cooking"])
		self:UpdateReagentTracking(self.Settings["track-reagents"])
		self:UpdateConsumableTracking(self.Settings["track-consumable"])
		self:UpdateHolidayTracking(self.Settings["track-holiday"])
		self:UpdateQuestTracking(self.Settings["track-quest"])

		if self.Settings["hide-idle"] then
			self:Hide()
		end

		self.XPStartTime = GetTime()
		self.StartingGold = GetMoney()

		self.Initial = true
	end

	if GatheringItemStats then -- Temp from 2.00, remove later
		GatheringItemStats = nil
	end

	if (self.GameVersion < 90000 and not IsInInstance()) then
		C_Timer.After(6, function()
			ChatThrottleLib:SendAddonMessage("NORMAL", "GATHERING_VRSN", GetAddOnMetadata("Gathering", "Version"), "YELL")
		end)
	end

	self:GROUP_ROSTER_UPDATE()
	self:BAG_UPDATE()
end

function Gathering:OnEnter()
	local TotalGathered = self.TotalGathered
	local GoldGained = self.GoldGained
	local XPGained = self.XPGained

	self.MouseIsOver = true

	local Now = GetTime()
	local MarketTotal = 0
	local X, Y = self:GetCenter()
	local ShiftDown = IsShiftKeyDown()
	local Tooltip = self.Tooltip

	Tooltip:SetOwner(self, "ANCHOR_NONE")

	if (Y > UIParent:GetHeight() / 2) then
		Tooltip:SetPoint("TOP", self, "BOTTOM", 0, -2)
	else
		Tooltip:SetPoint("BOTTOM", self, "TOP", 0, 2)
	end

	Tooltip:ClearLines()

	if (TotalGathered > 0) then
		for SubType, Info in next, self.Gathered do
			Tooltip:AddLine(SubType, 1, 1, 0)

			for ID, Value in next, Info do
				local Name, Link, Rarity = GetItemInfo(ID)
				local Hex = "|cffFFFFFF"

				if Rarity then
					Hex = ITEM_QUALITY_COLORS[Rarity].hex
				end

				if (WOW_PROJECT_ID == WOW_PROJECT_MAINLINE) then
					local RQuality = C_TradeSkillUI.GetItemReagentQualityByItemInfo(Link)

					if RQuality then
						Name = Name .. " " .. C_Texture.GetCraftingReagentQualityChatIcon(RQuality)
					end
				end

				local Price = self:GetPrice(Link)

				if Price then
					MarketTotal = MarketTotal + (Price * Value.Collected)
				end

				if (ShiftDown and Price) then
					Tooltip:AddDoubleLine(format("%s%s|r:", Hex, Name), format("%s (%s/%s)", Value.Collected, self:CopperToGold((Price * Value.Collected / max(Now - Value.Initial, 1)) * 60 * 60), L["Hr"]), 1, 1, 1, 1, 1, 1)
				elseif IsControlKeyDown() then
					Tooltip:AddDoubleLine(format("%s%s|r:", Hex, Name), format("%s (%s%%)", Value.Collected, floor((Value.Collected / TotalGathered * 100 + 0.05) * 10) / 10), 1, 1, 1, 1, 1, 1)
				elseif IsAltKeyDown() then
					Tooltip:AddDoubleLine(format("%s%s|r:", Hex, Name), format("%s %s", L["Recently Gathered: "], date("!%X", Now - Value.Last)), 1, 1, 1, 1, 1, 1)
				else
					Tooltip:AddDoubleLine(format("%s%s|r:", Hex, Name), format("%s (%s/%s)", Value.Collected, floor((Value.Collected / max(Now - Value.Initial, 1)) * 60 * 60), L["Hr"]), 1, 1, 1, 1, 1, 1)
				end
			end

			Tooltip:AddLine(" ")
		end
	end

	if (GoldGained ~= 0) then
		Tooltip:AddLine(MONEY_LOOT, 1, 1, 0)

		if (GoldGained > 0) then
			if ShiftDown then
				Tooltip:AddDoubleLine(BONUS_ROLL_REWARD_MONEY, format("%s (%s %s)", self:CopperToGold(GoldGained), self:CopperToGold(floor((GoldGained / max(Now - self.GoldTimer, 1)) * 60 * 60)), L["Hr"]), 1, 1, 1, 1, 1, 1)
			else
				Tooltip:AddDoubleLine(BONUS_ROLL_REWARD_MONEY, self:CopperToGold(GoldGained), 1, 1, 1, 1, 1, 1)
			end
		else
			if ShiftDown then
				Tooltip:AddDoubleLine(BONUS_ROLL_REWARD_MONEY, format("|cffff5555-%s|r (%s %s)", self:CopperToGold(abs(GoldGained)), self:CopperToGold(floor((abs(GoldGained) / max(Now - self.GoldTimer, 1)) * 60 * 60)), L["Hr"]), 1, 1, 1, 1, 1, 1)
			else
				Tooltip:AddDoubleLine(BONUS_ROLL_REWARD_MONEY, format("|cffff5555-%s|r", self:CopperToGold(abs(GoldGained))), 1, 1, 1, 1, 1, 1)
			end
		end
	end

	if (self.Settings["track-xp"] and XPGained > 0) then
		if (GoldGained > 0) then
			Tooltip:AddLine(" ")
		end

		local PerSec = XPGained / (Now - self.XPStartTime)

		Tooltip:AddLine(COMBAT_XP_GAIN, 1, 1, 0)
		Tooltip:AddDoubleLine("XP Gained", self:Comma(XPGained), 1, 1, 1, 1, 1, 1)
		Tooltip:AddDoubleLine("XP / hr", self:Comma((PerSec * 60) * 60), 1, 1, 1, 1, 1, 1)
		Tooltip:AddDoubleLine("Time to level", self:FormatFullTime((UnitXPMax("player") - UnitXP("player")) / PerSec), 1, 1, 1, 1, 1, 1)
	end

	if (TotalGathered > 0) then
		if (XPGained > 0) then
			Tooltip:AddLine(" ")
		end

		Tooltip:AddDoubleLine(L["Total Gathered:"], TotalGathered, nil, nil, nil, 1, 1, 1)

		if (ShiftDown and MarketTotal > 0) then
			Tooltip:AddDoubleLine(L["Total Average Per Hour:"], self:CopperToGold((MarketTotal / max(self.Seconds, 1)) * 60 * 60), nil, nil, nil, 1, 1, 1)
		else
			Tooltip:AddDoubleLine(L["Total Average Per Hour:"], self:Comma(floor(((TotalGathered / max(self.Seconds, 1)) * 60 * 60))), nil, nil, nil, 1, 1, 1)
		end

		if (MarketTotal > 0) then
			Tooltip:AddDoubleLine(L["Total Value:"], self:CopperToGold(MarketTotal), nil, nil, nil, 1, 1, 1)
		end
	end

	if self.Settings.ShowTooltipHelp then
		if (not (TotalGathered == 0 and GoldGained == 0 and XPGained == 0)) then
			Tooltip:AddLine(" ")
		end
		Tooltip:AddLine(L["Left click: Toggle timer"])
		Tooltip:AddLine(L["Right click: Reset data"])
		Tooltip:AddLine(L["Shift + Left/Right click: Toggle settings"])
	end

	self:UpdateTooltipFont()

	self:RegisterEvent("MODIFIER_STATE_CHANGED")

	Tooltip:Show()
end

function Gathering:OnLeave()
	if self.Tooltip.Override then
		return
	end

	self.MouseIsOver = false

	self:UnregisterEvent("MODIFIER_STATE_CHANGED")

	self.Tooltip:Hide()
end

function Gathering:OnMouseUp(button)
	if IsShiftKeyDown() then
		SlashCmdList["GATHERING"]()
	elseif (button == "LeftButton") then
		self:ToggleTimer()
	elseif (button == "RightButton") then
		self:ToggleResetPopup()
	elseif (button == "MiddleButton") then
		if (self.Tooltip.Override == true) then
			self.Tooltip.Override = false
		else
			self.Tooltip.Override = true
		end
	end
end

Gathering:RegisterEvent("PLAYER_ENTERING_WORLD")

Gathering:SetScript("OnEvent", Gathering.OnEvent)
Gathering:SetScript("OnEnter", Gathering.OnEnter)
Gathering:SetScript("OnLeave", Gathering.OnLeave)
Gathering:SetScript("OnMouseUp", Gathering.OnMouseUp)