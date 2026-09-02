-- 锻炼项目解锁：派莓位于首都市中心时解锁 TECH_ALLOW_PROJECT（锻炼项目的前置科技），离开即撤销
-- 状态审计：回合开始/单位移动/传送落地/读档 四个时机核对位置并同步科技状态，
-- 不再需要"走出首都再走回来"来触发解锁
local PAIMEI_UNIT_KEY = "UNIT_PAIMEI"
local TECH_ALLOW_PROJECT_KEY = "TECH_ALLOW_PROJECT"

-- 核对某玩家的派莓是否在首都市中心，并同步训练科技状态
function SyncPaimeiTrainingTech(iPlayerID)
	local pPlayer = Players[iPlayerID];
	if pPlayer == nil then return end
	local pCapital = pPlayer:GetCities():GetCapitalCity();
	if pCapital == nil then return end
	local techInfo = GameInfo.Technologies[TECH_ALLOW_PROJECT_KEY];
	if techInfo == nil then return end
	local playerTechs = pPlayer:GetTechs();

	-- 找到该玩家的派莓，判断是否在首都市中心
	local bInCapital = false;
	for _, pUnit in pPlayer:GetUnits():Members() do
		if GameInfo.Units[pUnit:GetType()].UnitType == PAIMEI_UNIT_KEY then
			if pUnit:GetX() == pCapital:GetX() and pUnit:GetY() == pCapital:GetY() then
				bInCapital = true;
			end
			break;
		end
	end

	if bInCapital then
		-- 在首都市中心：确保训练科技处于完成状态
		if not playerTechs:HasTech(techInfo.Index) then
			local iCost = playerTechs:GetResearchCost(techInfo.Index);
			playerTechs:SetResearchProgress(techInfo.Index, iCost);
		end
	else
		-- 不在首都市中心：撤销训练科技
		if playerTechs:HasTech(techInfo.Index) then
			playerTechs:SetTech(techInfo.Index, false);
		end
	end
end

-- 所有主要文明都审计一遍
function AuditAllPaimeiTrainingTech()
	for iPlayer = 0, Game.GetNumPlayers() - 1 do
		SyncPaimeiTrainingTech(iPlayer);
	end
end

-- 单位移动完成：走进/走出首都市中心实时解锁/撤销
function OnTrainingUnitMoveComplete(iPlayerID, iUnitID, iX, iY)
	SyncPaimeiTrainingTech(iPlayerID);
end
Events.UnitMoveComplete.Add(OnTrainingUnitMoveComplete);

-- 回合开始兜底审计
function OnTrainingTurnBegin(iTurn)
	AuditAllPaimeiTrainingTech();
end
Events.TurnBegin.Add(OnTrainingTurnBegin);

Events.LoadScreenClose.Add(AuditAllPaimeiTrainingTech);

-- 开局禁止手动生产派莓（保留原有逻辑）
function BuildDisabled()
	local iPlayerID = Game.GetLocalPlayer()
	local pPlayer = Players[iPlayerID]
	local m_ePlagueDoctorUnit : number = GameInfo.Units["UNIT_PAIMEI"].Index;
	pPlayer:GetUnits():SetBuildDisabled(m_ePlagueDoctorUnit, true)
end
Events.LoadScreenClose.Add(BuildDisabled);

-- 神殿④ 杜蕾的引力：晋升"神殿④·杜蕾的庇护"后，派莓攻击的单位该回合无法行动
-- 实测结论（本机截图实证）：
--   1) Events.Combat 只在 UI 端触发，gameplay 端收不到 → 解析判写在 UI 端完成，
--      经 ExposedMembers.WS_RequestFreeze（与传送功能同款跨状态桥）把目标转过来执行定身
--   2) 耗尽移动力必须写 UnitManager.FinishMoves(pUnit)（黑死病剧本 4 处实证）
--   3) 回合钩子用 GameEvents.PlayerTurnStartComplete（gameplay 端；Events.PlayerTurnActivated 是 UI 端事件）
local GRAVITY_PROMOTION_KEY = "PROMOTION_PAIMEI_L4"
local m_tGravityFrozen = {}  -- [iPlayerID] = { [iUnitID] = true }

-- 定身执行：清空目标剩余移动力并登记；其回合开始完成、移动力刷新后再定身一次
function WS_DoFreeze(iDefPlayer, iDefUnit)
	local pPlayer = Players[iDefPlayer]
	if pPlayer == nil then return end
	local pUnit = pPlayer:GetUnits():FindID(iDefUnit)
	if pUnit == nil then return end
	UnitManager.FinishMoves(pUnit)
	if m_tGravityFrozen[iDefPlayer] == nil then m_tGravityFrozen[iDefPlayer] = {} end
	m_tGravityFrozen[iDefPlayer][iDefUnit] = true
end

-- UI 端转发入口
function WS_RequestFreeze(iDefPlayer, iDefUnit)
	local ok, err = pcall(WS_DoFreeze, iDefPlayer, iDefUnit)
	if not ok then print("WS freeze error: " .. tostring(err)) end
end

function OnWSFreezeRequest(iDefPlayer, iDefUnit)
	WS_RequestFreeze(iDefPlayer, iDefUnit)
end
LuaEvents.WS_Paimee_Freeze.Add(OnWSFreezeRequest)

-- 目标玩家回合开始完成：把登记的定身单位移动力清零（该回合不能行动），随后解除登记
function OnGravityPlayerTurn(iPlayerID)
	local tFrozen = m_tGravityFrozen[iPlayerID]
	if tFrozen == nil then return end
	local pPlayer = Players[iPlayerID]
	if pPlayer ~= nil then
		for iUnitID, _ in pairs(tFrozen) do
			local pUnit = pPlayer:GetUnits():FindID(iUnitID)
			if pUnit ~= nil then
				UnitManager.FinishMoves(pUnit)
			end
		end
	end
	m_tGravityFrozen[iPlayerID] = nil
end
GameEvents.PlayerTurnStartComplete.Add(OnGravityPlayerTurn);

-- 暴露给 UI 端（ExposedMembers 与传送功能同款跨状态桥）
ExposedMembers.Place_PAIMEI_Capital = ExposedMembers.Place_PAIMEI_Capital or {}
ExposedMembers.Place_PAIMEI_Capital.WS_RequestFreeze = WS_RequestFreeze

-- 目标玩家回合开始完成：把登记的定身单位移动力清零（该回合不能行动），随后解除登记
function OnGravityPlayerTurn(iPlayerID)
	local tFrozen = m_tGravityFrozen[iPlayerID]
	if tFrozen == nil then return end
	local nCount = 0
	local pPlayer = Players[iPlayerID]
	if pPlayer ~= nil then
		for iUnitID, _ in pairs(tFrozen) do
			local pUnit = pPlayer:GetUnits():FindID(iUnitID)
			if pUnit ~= nil then
				pUnit:FinishMoves()
				nCount = nCount + 1
			end
		end
	end
	WS_GravityDebug("回合开始: 玩家" .. tostring(iPlayerID) .. " 定身" .. tostring(nCount) .. "个单位")
	m_tGravityFrozen[iPlayerID] = nil
end
GameEvents.PlayerTurnStartComplete.Add(OnGravityPlayerTurn);
