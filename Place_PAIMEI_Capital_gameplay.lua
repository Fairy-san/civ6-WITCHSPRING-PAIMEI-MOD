-- 传送回首都（原功能保留）+ 传送到指定城市市中心（空运）
-- 校验派莓本人；市中心已有单位时落到相邻陆地空地；落地后立即刷新锻炼解锁状态
function Place_PAIMEI_Capital_GamePlay(iPlayerID,iUnitID)
    local pPlayerCities = Players[iPlayerID]:GetCities()
    local pCity = pPlayerCities:GetCapitalCity()
    local iX = pCity:GetX()
    local iY = pCity:GetY()
    local pUnit = UnitManager.GetUnit(iPlayerID, iUnitID);
    local tNeighborPlots = Map.GetAdjacentPlots(iX, iY);
	for _, pNeighborPlot in ipairs(tNeighborPlots) do
		if (not pNeighborPlot:IsWater() and not pNeighborPlot:IsMountain() and not pNeighborPlot:IsUnit()) then
			UnitManager.PlaceUnit(pUnit, pNeighborPlot:GetX(), pNeighborPlot:GetY());
		end
	end
	UnitManager.RestoreMovementToFormation(pUnit)
	UnitManager.MoveUnit(pUnit, iX, iY)
end

-- 传送到指定城市：市中心没驻军就直接 PlaceUnit 落进去；有驻军就自动找相邻的陆地空地落脚
-- 传送后派莓行动力耗尽，本回合不能行动；结果码通过 LuaEvents.WS_PaimeeTeleport_Result(bSuccess) 回报给 UI
function Place_PAIMEI_CityTeleport_GamePlay(iPlayerID, iUnitID, iCityID)
	local bSuccess = false
	local pUnit = UnitManager.GetUnit(iPlayerID, iUnitID)
	-- 校验是派莓本人
	if pUnit ~= nil then
		local unitInfo = GameInfo.Units[pUnit:GetType()]
		if unitInfo ~= nil and unitInfo.UnitType == "UNIT_PAIMEI" then
			local pCity = Players[iPlayerID]:GetCities():FindID(iCityID)
			if pCity ~= nil then
				local iX = pCity:GetX()
				local iY = pCity:GetY()
				local pPlot = Map.GetPlot(iX, iY)
				if (pPlot ~= nil and not pPlot:IsUnit()) then
					UnitManager.PlaceUnit(pUnit, iX, iY)
					UnitManager.FinishMoves(pUnit) -- 传送耗尽行动力，落地后本回合不能行动（黑死病剧本写法）
					bSuccess = true
				else
					-- 市中心已有单位：落到相邻的陆地空地
					for _, pNeighborPlot in ipairs(Map.GetAdjacentPlots(iX, iY)) do
						if (not pNeighborPlot:IsWater() and not pNeighborPlot:IsMountain() and not pNeighborPlot:IsUnit()) then
							UnitManager.PlaceUnit(pUnit, pNeighborPlot:GetX(), pNeighborPlot:GetY())
							UnitManager.FinishMoves(pUnit) -- 传送耗尽行动力，落地后本回合不能行动
							bSuccess = true
							break
						end
					end
				end
				-- 传送落地后立即刷新锻炼解锁状态（进城解锁/出城锁定）
				if bSuccess and SyncPaimeiTrainingTech ~= nil then
					SyncPaimeiTrainingTech(iPlayerID)
				end
			end
		end
	end
	LuaEvents.WS_PaimeeTeleport_Result(bSuccess)
end

-- 兼容旧函数名
Place_PAIMEI_City_GamePlay = Place_PAIMEI_CityTeleport_GamePlay

ExposedMembers.Place_PAIMEI_Capital = ExposedMembers.Place_PAIMEI_Capital or {}
ExposedMembers.Place_PAIMEI_Capital.Place_PAIMEI_Capital_GamePlay = Place_PAIMEI_Capital_GamePlay
ExposedMembers.Place_PAIMEI_Capital.Place_PAIMEI_CityTeleport_GamePlay = Place_PAIMEI_CityTeleport_GamePlay
ExposedMembers.Place_PAIMEI_Capital.Place_PAIMEI_City_GamePlay = Place_PAIMEI_CityTeleport_GamePlay
