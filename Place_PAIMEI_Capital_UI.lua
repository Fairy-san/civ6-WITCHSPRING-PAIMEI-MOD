-- 单位面板按钮：空运（城市传送），弹窗与按钮同一上下文（RMT 结构）
-- 点按钮显示弹窗列出己方城市，点城市名传送；再点一次或取消选中即关闭
local PAIMEI_UNIT_KEY = "UNIT_PAIMEI"
local MAX_CITY_BUTTONS = 12

local m_bPickerOpen = false

-- 错误上屏：初始化若出错，用游戏原生弹窗显示原因
function ShowError(sWhere, err)
	local sMsg = "WS UI Error [" .. tostring(sWhere) .. "]: " .. tostring(err)
	print(sMsg)
	local dlg = PopupDialogInGame:new("WS_Paimee_ErrorDialog")
	dlg:ShowOkDialog(sMsg)
end

-- ============ 初始化：先把按钮挂进单位面板，再做其余收尾 ============
function Setup()
	-- 第一步：ChangeParent（最关键，单独 pcall）
	local ok1, err1 = pcall(function()
		local ActionStack = ContextPtr:LookUpControl("/InGame/UnitPanel/StandardActionsStack")
		if ActionStack ~= nil then
			Controls.TeleportActionGrid:ChangeParent(ActionStack)
		else
			print("StandardActionsStack not found.")
		end
	end)
	if not ok1 then ShowError("Setup挂载按钮", err1) return end

	-- 第二步：提示文字、回调、默认隐藏
	local ok2, err2 = pcall(function()
		Controls.TeleportActionButton:SetToolTipString(Locale.Lookup("LOC_PLACE_PAIMEI_CITY_TELEPORT_BTN_TT"))
		Controls.TeleportActionButton:RegisterCallback(Mouse.eLClick, ToggleCityPicker)
		Controls.TeleportCloseButton:RegisterCallback(Mouse.eLClick, CloseCityPicker)
		ContextPtr:SetHide(true) -- AddUserInterfaces 的上下文默认隐藏，先确保关着
		Controls.TeleportActionGrid:SetHide(true)
		-- 加载时恰好已选中派莓的话，直接把按钮显示出来
		local pUnit = UI.GetHeadSelectedUnit()
		if pUnit ~= nil then
			local unitInfo = GameInfo.Units[pUnit:GetType()]
			if unitInfo ~= nil and unitInfo.UnitType == PAIMEI_UNIT_KEY then
				Controls.TeleportActionGrid:SetHide(false)
			end
		end
	end)
	if not ok2 then ShowError("Setup收尾", err2) end
end

function OnUnitSelectionChanged(iPlayerID, iUnitID, iPlotX, iPlotY, iPlotZ, bSelected, bEditable)
	local ok, err = pcall(function()
		local bShowButton = false
		if bSelected then
			local pUnit = UnitManager.GetUnit(iPlayerID, iUnitID)
			if pUnit ~= nil then
				local unitInfo = GameInfo.Units[pUnit:GetType()]
				bShowButton = (unitInfo ~= nil and unitInfo.UnitType == PAIMEI_UNIT_KEY)
			end
		end
		Controls.TeleportActionGrid:SetHide(not bShowButton)
		if not bShowButton then
			CloseCityPicker() -- 取消选中/切换单位时自动关闭弹窗
		end
	end)
	if not ok then ShowError("选中处理", err) end
end

-- ============ 城市传送（空运） ============
function ToggleCityPicker()
	if m_bPickerOpen then
		CloseCityPicker()
	else
		OpenCityPicker()
	end
end

function CloseCityPicker()
	m_bPickerOpen = false
	ContextPtr:SetHide(true) -- 关闭整个上下文（AddUserInterfaces 上下文默认隐藏）
	Controls.TeleportPopupBG:SetHide(true)
	Controls.TeleportPopupContainer:SetHide(true)
end

function OpenCityPicker()
	local ok, err = pcall(BuildCityList)
	if not ok then ShowError("打开城市列表", err) end
	m_bPickerOpen = true
	ContextPtr:SetHide(false) -- 显示整个上下文（按钮已移入单位面板，上下文里只剩弹窗）
	Controls.TeleportPopupBG:SetHide(false)
	Controls.TeleportPopupContainer:SetHide(false)
end

function BuildCityList()
	local pSelectedUnit = UI.GetHeadSelectedUnit()
	if pSelectedUnit == nil then return end

	Controls.TeleportErrorHint:SetHide(true)
	Controls.TeleportNoCityHint:SetHide(true)
	Controls.TeleportFailHint:SetHide(true)
	Controls.CityCurrentLabel:SetHide(true)

	local iUnitX = pSelectedUnit:GetX()
	local iUnitY = pSelectedUnit:GetY()
	local pLocalPlayer = Players[Game.GetLocalPlayer()]
	local iButtonIndex = 0
	local iCityCount = 0
	for _, pCity in pLocalPlayer:GetCities():Members() do
		iCityCount = iCityCount + 1
		-- GetName() 返回的是文本标签，需经 Locale.Lookup 转成当前语言文字
		local sName = Locale.Lookup(pCity:GetName())
		if sName == nil or sName == "" then
			sName = pCity:GetName()
		end
		if pCity:IsCapital() then
			sName = sName .. "(首都)"
		end
		if pCity:GetX() == iUnitX and pCity:GetY() == iUnitY then
			-- 派莓当前所在的城市：单独一行提示，不可点
			Controls.CityCurrentLabel:SetText(sName .. " (当前位置)")
			Controls.CityCurrentLabel:SetHide(false)
		else
			iButtonIndex = iButtonIndex + 1
			if iButtonIndex <= MAX_CITY_BUTTONS then
				local kButton = Controls["CityButton" .. (iButtonIndex - 1)]
				kButton:SetText(sName)
				kButton:SetHide(false)
				local iCityID = pCity:GetID()
				kButton:RegisterCallback(Mouse.eLClick, function() TeleportToCity(iCityID) end)
			end
		end
	end
	-- 没用到的按钮藏起来
	for i = iButtonIndex, MAX_CITY_BUTTONS - 1 do
		Controls["CityButton" .. i]:SetHide(true)
	end

	Controls.TeleportNoCityHint:SetHide(iCityCount > 0)
	Controls.CityScrollPanel:SetHide(iCityCount == 0)
	Controls.CityButtonStack:CalculateSize()
	Controls.CityScrollPanel:CalculateInternalSize(Controls.CityButtonStack:GetSizeX(), Controls.CityButtonStack:GetSizeY())
end

function TeleportToCity(iCityID)
	local pSelectedUnit = UI.GetHeadSelectedUnit()
	if pSelectedUnit == nil then return end
	if ExposedMembers.Place_PAIMEI_Capital ~= nil and ExposedMembers.Place_PAIMEI_Capital.Place_PAIMEI_CityTeleport_GamePlay ~= nil then
		ExposedMembers.Place_PAIMEI_Capital.Place_PAIMEI_CityTeleport_GamePlay(pSelectedUnit:GetOwner(), pSelectedUnit:GetID(), iCityID)
	else
		ShowError("传送", "gameplay 函数未注册")
	end
end

-- gameplay 回报结果：成功关闭弹窗；失败（市中心和周围都堵死）在弹窗里显示提示
function OnTeleportResult(bSuccess)
	local ok, err = pcall(function()
		if bSuccess then
			CloseCityPicker()
		else
			Controls.TeleportFailHint:SetHide(false)
		end
	end)
	if not ok then ShowError("传送结果", err) end
end
LuaEvents.WS_PaimeeTeleport_Result.Add(OnTeleportResult)

-- ============ 神殿④引力定身：战斗检测（Events.Combat 只在 UI 端触发，本机实证） ============
-- 参战者结构（仙舟 mod 实证）：combatResult[ATTACKER/DEFENDER][CombatResultParameters.ID] = { player=, id= }
-- 攻击者是持有神殿④的派莓时，经 ExposedMembers 转发定身请求给 gameplay 执行
function OnWSUICombat(combatResult)
	if CombatResultParameters == nil then return end
	local attacker = combatResult[CombatResultParameters.ATTACKER]
	if attacker == nil then return end
	local attInfo = attacker[CombatResultParameters.ID]
	if attInfo == nil then return end
	local defender = combatResult[CombatResultParameters.DEFENDER]
	if defender == nil then return end
	local defInfo = defender[CombatResultParameters.ID]
	if defInfo == nil then return end

	-- 只处理派莓的攻击，且需持有神殿④
	local pAttacker = UnitManager.GetUnit(attInfo.player, attInfo.id)
	if pAttacker == nil then return end
	if GameInfo.Units[pAttacker:GetType()].UnitType ~= PAIMEI_UNIT_KEY then return end
	local pExp = pAttacker:GetExperience()
	local promoInfo = GameInfo.UnitPromotions["PROMOTION_PAIMEI_L4"]
	if promoInfo == nil or pExp == nil or not pExp:HasPromotion(promoInfo.Index) then return end

	if ExposedMembers.Place_PAIMEI_Capital ~= nil and ExposedMembers.Place_PAIMEI_Capital.WS_RequestFreeze ~= nil then
		ExposedMembers.Place_PAIMEI_Capital.WS_RequestFreeze(defInfo.player, defInfo.id)
	end
end
Events.Combat.Add(OnWSUICombat)

Events.LoadScreenClose.Add(Setup)
Events.UnitSelectionChanged.Add(OnUnitSelectionChanged)
