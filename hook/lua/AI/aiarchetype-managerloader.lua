WARN('['..string.gsub(debug.getinfo(1).source, ".*\\(.*.lua)", "%1")..', line:'..debug.getinfo(1).currentline..'] * AI-Uveso: offset aiarchetype-managerloader.lua' )
-- 200

local Buff = import('/lua/sim/Buff.lua')

-- This hook is for debug-option Platoon-Names. Hook for all AI's
OldExecutePlanFunction = ExecutePlan
function ExecutePlan(aiBrain)
    aiBrain:SetConstantEvaluate(false)
    local behaviors = import('/lua/ai/AIBehaviors.lua')
    WaitSeconds(1)
    if not aiBrain.BuilderManagers.MAIN.FactoryManager:HasBuilderList() then
        aiBrain:SetResourceSharing(true)

        -- Sorian is using its own triggers
        if aiBrain.Sorian then
            aiBrain:SetupUnderEnergyStatTriggerSorian(0.1)
            aiBrain:SetupUnderMassStatTriggerSorian(0.1)
        -- Set eco triggers for all AI's exept AI-Uveso.
        elseif not aiBrain.Uveso then
            aiBrain:SetupUnderEnergyStatTrigger(0.1)
            aiBrain:SetupUnderMassStatTrigger(0.1)
        end

        SetupMainBase(aiBrain)

        -- Get units out of pool and assign them to the managers
        local mainManagers = aiBrain.BuilderManagers.MAIN

        local pool = aiBrain:GetPlatoonUniquelyNamed('ArmyPool')
        for k,v in pool:GetPlatoonUnits() do
            if EntityCategoryContains(categories.ENGINEER, v) then
                mainManagers.EngineerManager:AddUnit(v)
            elseif EntityCategoryContains(categories.FACTORY * categories.STRUCTURE, v) then
                mainManagers.FactoryManager:AddFactory(v)
            end
        end

        -- Sorian is using a Thread for watching unitcap and Nukes
        if aiBrain.Sorian then
            aiBrain:ForkThread(UnitCapWatchThreadSorian, aiBrain)
            aiBrain:ForkThread(behaviors.NukeCheck, aiBrain)
            -- Debug for Platoon names
            if aiBrain[ScenarioInfo.Options.AIPLatoonNameDebug] or ScenarioInfo.Options.AIPLatoonNameDebug == 'all' then
                aiBrain:ForkThread(LocationRangeManagerThread, aiBrain)
            end
        -- Uveso is using a locationmanager ecomanager and BaseAlert Thread
        elseif aiBrain.Uveso then
            aiBrain:ForkThread(LocationRangeManagerThread, aiBrain)
            aiBrain:ForkThread(EcoManagerThread, aiBrain)
            aiBrain:ForkThread(BaseTargetManagerThread, aiBrain)
            aiBrain:ForkThread(MarkerGridThreatManagerThread, aiBrain)
            --aiBrain:ForkThread(MassManagerThread, aiBrain)
        -- Debug for Platoon names
        elseif aiBrain[ScenarioInfo.Options.AIPLatoonNameDebug] or ScenarioInfo.Options.AIPLatoonNameDebug == 'all' then
            aiBrain:ForkThread(LocationRangeManagerThread, aiBrain)
            aiBrain:ForkThread(UnitCapWatchThread, aiBrain)
        else
            aiBrain:ForkThread(UnitCapWatchThread, aiBrain)
        end
    end
    if aiBrain.PBM then
        aiBrain:PBMSetEnabled(false)
    end
end

-- Uveso AI

function SetArmyPoolBuff(aiBrain, CheatMult, BuildMult)
    -- Store the new mult inside options, so new builded units get the new mult automatically
    if tostring(CheatMult) == tostring(ScenarioInfo.Options.CheatMult) and tostring(BuildMult) == tostring(ScenarioInfo.Options.BuildMult) then
        --LOG('* SetArmyPoolBuff: CheatMult+BuildMult not changed. No buffing needed!')
        return
    end
    ScenarioInfo.Options.CheatMult = tostring(CheatMult)
    ScenarioInfo.Options.BuildMult = tostring(BuildMult)
    -- Modify Buildrate buff
    local buffDef = Buffs['CheatBuildRate']
    local buffAffects = buffDef.Affects
    buffAffects.BuildRate.Mult = BuildMult
    -- Modify CheatIncome buff
    buffDef = Buffs['CheatIncome']
    buffAffects = buffDef.Affects
    buffAffects.EnergyProduction.Mult = CheatMult
    buffAffects.MassProduction.Mult = CheatMult
    allUnits = aiBrain:GetListOfUnits(categories.ALLUNITS, false, false)
    for _, unit in allUnits do
        -- Remove old build rate and income buffs
        Buff.RemoveBuff(unit, 'CheatIncome', true) -- true = removeAllCounts
        Buff.RemoveBuff(unit, 'CheatBuildRate', true) -- true = removeAllCounts
        -- Apply new build rate and income buffs
        Buff.ApplyBuff(unit, 'CheatIncome')
        Buff.ApplyBuff(unit, 'CheatBuildRate')
    end
end

function EcoManagerThread(aiBrain)
    while GetGameTimeSeconds() < 15 + aiBrain:GetArmyIndex() do
        WaitTicks(10)
    end
    local personality = ScenarioInfo.ArmySetup[aiBrain.Name].AIPersonality
    local CheatMultOption = tonumber(ScenarioInfo.Options.CheatMult)
    local BuildMultOption = tonumber(ScenarioInfo.Options.BuildMult)
    local CheatMult = CheatMultOption
    local BuildMult = BuildMultOption
    if CheatMultOption ~= BuildMultOption then
        CheatMultOption = math.max(CheatMultOption,BuildMultOption)
        BuildMultOption = math.max(CheatMultOption,BuildMultOption)
        ScenarioInfo.Options.CheatMult = tostring(CheatMultOption)
        ScenarioInfo.Options.BuildMult = tostring(BuildMultOption)
    end
    LOG('* AI-Uveso: Function EcoManagerThread() started! CheatFactor:('..repr(CheatMultOption)..') - BuildFactor:('..repr(BuildMultOption)..') ['..aiBrain.Nickname..']')
    local Engineers = {}
    local paragons = {}
    local Factories = {}
    local lastCall = 0
    local ParaComplete
    local allyScore
    local enemyScore
    local MyArmyRatio
    local bussy
    while aiBrain.Result ~= "defeat" do
        --LOG('* AI-Uveso: Function EcoManagerThread() beat. ['..aiBrain.Nickname..']')
        WaitTicks(5)
        Engineers = aiBrain:GetListOfUnits(categories.ENGINEER - categories.COMMAND - categories.SUBCOMMANDER, false, false) -- also gets unbuilded units (planed to build)
        paragons = aiBrain:GetListOfUnits(categories.STRUCTURE * categories.EXPERIMENTAL * categories.ECONOMIC * categories.ENERGYPRODUCTION * categories.MASSPRODUCTION, false, false)
        Factories = aiBrain:GetListOfUnits(categories.STRUCTURE * categories.FACTORY, false, false)
        ParaComplete = 0
        bussy = false
        for unitNum, unit in paragons do
            if unit:GetFractionComplete() >= 1 then
                ParaComplete = ParaComplete + 1
            end
        end
        if ParaComplete >= 1 then
            aiBrain.HasParagon = true
        else
            aiBrain.HasParagon = false
        end
        -- Cheatbuffs
        if personality == 'uvesooverwhelm' then
            -- Check every 30 seconds for new armyStats to change ECO
            if (GetGameTimeSeconds() > 60 * 1) and lastCall+10 < GetGameTimeSeconds() then
                lastCall = GetGameTimeSeconds()
                --score of all players (unitcount)
                allyScore = 0
                enemyScore = 0
                for k, brain in ArmyBrains do
                    if ArmyIsCivilian(brain:GetArmyIndex()) then
                        --NOOP
                    elseif IsAlly( aiBrain:GetArmyIndex(), brain:GetArmyIndex() ) then
                        --allyScore = allyScore + table.getn(brain:GetListOfUnits( (categories.MOBILE + categories.DEFENSE) - categories.MASSEXTRACTION - categories.ENGINEER - categories.SCOUT, false, false))
                        allyScore = allyScore + table.getn(brain:GetListOfUnits( categories.MOBILE - categories.MASSEXTRACTION - categories.ENGINEER - categories.SCOUT, false, false))
                    elseif IsEnemy( aiBrain:GetArmyIndex(), brain:GetArmyIndex() ) then
                        --enemyScore = enemyScore + table.getn(brain:GetListOfUnits( (categories.MOBILE + categories.DEFENSE) - categories.MASSEXTRACTION - categories.ENGINEER - categories.SCOUT, false, false))
                        enemyScore = enemyScore + table.getn(brain:GetListOfUnits( categories.MOBILE - categories.MASSEXTRACTION - categories.ENGINEER - categories.SCOUT, false, false))
                    end
                end
                if enemyScore ~= 0 then
                    if allyScore == 0 then
                        allyScore = 1
                    end
                    MyArmyRatio = 100/enemyScore*allyScore
                else
                    MyArmyRatio = 100
                end

                -- Increase cheatfactor to +1.5 after 1 hour gametime
                if GetGameTimeSeconds() > 60 * 60 then
                    CheatMult = CheatMult + 0.1
                    BuildMult = BuildMult + 0.1
                    if CheatMult < tonumber(CheatMultOption) then CheatMult = tonumber(CheatMultOption) end
                    if BuildMult < tonumber(BuildMultOption) then BuildMult = tonumber(BuildMultOption) end
                    if CheatMult > tonumber(CheatMultOption) + 1.5 then CheatMult = tonumber(CheatMultOption) + 1.5 end
                    if BuildMult > tonumber(BuildMultOption) + 1.5 then BuildMult = tonumber(BuildMultOption) + 1.5 end
                    --LOG('* ECO + ally('..allyScore..') enemy('..enemyScore..') - ArmyRatio: '..math.floor(MyArmyRatio)..'% - Build/CheatMult old: '..math.floor(tonumber(ScenarioInfo.Options.BuildMult)*10)..' '..math.floor(tonumber(ScenarioInfo.Options.CheatMult)*10)..' - new: '..math.floor(BuildMult*10)..' '..math.floor(CheatMult*10)..'')
                    SetArmyPoolBuff(aiBrain, CheatMult, BuildMult)
                -- Increase cheatfactor to +0.6 after 1 hour gametime
                elseif GetGameTimeSeconds() > 60 * 35 then
                    CheatMult = CheatMult + 0.1
                    BuildMult = BuildMult + 0.1
                    if CheatMult < tonumber(CheatMultOption) then CheatMult = tonumber(CheatMultOption) end
                    if BuildMult < tonumber(BuildMultOption) then BuildMult = tonumber(BuildMultOption) end
                    if CheatMult > tonumber(CheatMultOption) + 0.6 then CheatMult = tonumber(CheatMultOption) + 0.6 end
                    if BuildMult > tonumber(BuildMultOption) + 0.6 then BuildMult = tonumber(BuildMultOption) + 0.6 end
                    --LOG('* ECO + ally('..allyScore..') enemy('..enemyScore..') - ArmyRatio: '..math.floor(MyArmyRatio)..'% - Build/CheatMult old: '..math.floor(tonumber(ScenarioInfo.Options.BuildMult)*10)..' '..math.floor(tonumber(ScenarioInfo.Options.CheatMult)*10)..' - new: '..math.floor(BuildMult*10)..' '..math.floor(CheatMult*10)..'')
                    SetArmyPoolBuff(aiBrain, CheatMult, BuildMult)
                -- Increase ECO if we have less than 40% of the enemy units
                elseif MyArmyRatio < 35 then
                    CheatMult = CheatMult + 0.4
                    BuildMult = BuildMult + 0.1
                    if CheatMult > tonumber(CheatMultOption) + 8 then CheatMult = tonumber(CheatMultOption) + 8 end
                    if BuildMult > tonumber(BuildMultOption) + 8 then BuildMult = tonumber(BuildMultOption) + 8 end
                    --LOG('* ECO + ally('..allyScore..') enemy('..enemyScore..') - ArmyRatio: '..math.floor(MyArmyRatio)..'% - Build/CheatMult old: '..math.floor(tonumber(ScenarioInfo.Options.BuildMult)*10)..' '..math.floor(tonumber(ScenarioInfo.Options.CheatMult)*10)..' - new: '..math.floor(BuildMult*10)..' '..math.floor(CheatMult*10)..'')
                    SetArmyPoolBuff(aiBrain, CheatMult, BuildMult)
                elseif MyArmyRatio < 55 then
                    CheatMult = CheatMult + 0.3
                    if CheatMult > tonumber(CheatMultOption) + 6 then CheatMult = tonumber(CheatMultOption) + 6 end
                    if BuildMult ~= tonumber(BuildMultOption) then BuildMult = tonumber(BuildMultOption) end
                    --LOG('* ECO + ally('..allyScore..') enemy('..enemyScore..') - ArmyRatio: '..math.floor(MyArmyRatio)..'% - Build/CheatMult old: '..math.floor(tonumber(ScenarioInfo.Options.BuildMult)*10)..' '..math.floor(tonumber(ScenarioInfo.Options.CheatMult)*10)..' - new: '..math.floor(BuildMult*10)..' '..math.floor(CheatMult*10)..'')
                    SetArmyPoolBuff(aiBrain, CheatMult, BuildMult)
                -- Increase ECO if we have less than 85% of the enemy units
                elseif MyArmyRatio < 75 then
                    CheatMult = CheatMult + 0.2
                    if CheatMult > tonumber(CheatMultOption) + 4 then CheatMult = tonumber(CheatMultOption) + 4 end
                    if BuildMult ~= tonumber(BuildMultOption) then BuildMult = tonumber(BuildMultOption) end
                    --LOG('* ECO + ally('..allyScore..') enemy('..enemyScore..') - ArmyRatio: '..math.floor(MyArmyRatio)..'% - Build/CheatMult old: '..math.floor(tonumber(ScenarioInfo.Options.BuildMult)*10)..' '..math.floor(tonumber(ScenarioInfo.Options.CheatMult)*10)..' - new: '..math.floor(BuildMult*10)..' '..math.floor(CheatMult*10)..'')
                    SetArmyPoolBuff(aiBrain, CheatMult, BuildMult)
                -- Decrease ECO if we have to much units
                elseif MyArmyRatio < 95 then
                    CheatMult = CheatMult + 0.1
                    if CheatMult > tonumber(CheatMultOption) + 3 then CheatMult = tonumber(CheatMultOption) + 3 end
                    if BuildMult ~= tonumber(BuildMultOption) then BuildMult = tonumber(BuildMultOption) end
                    --LOG('* ECO + ally('..allyScore..') enemy('..enemyScore..') - ArmyRatio: '..math.floor(MyArmyRatio)..'% - Build/CheatMult old: '..math.floor(tonumber(ScenarioInfo.Options.BuildMult)*10)..' '..math.floor(tonumber(ScenarioInfo.Options.CheatMult)*10)..' - new: '..math.floor(BuildMult*10)..' '..math.floor(CheatMult*10)..'')
                    SetArmyPoolBuff(aiBrain, CheatMult, BuildMult)
                -- Decrease ECO if we have to much units
                elseif MyArmyRatio > 125 then
                    CheatMult = CheatMult - 0.5
                    BuildMult = BuildMult - 0.1
                    if CheatMult < 0.9 then CheatMult = 0.9 end
                    if BuildMult < 0.9 then BuildMult = 0.9 end
                    --LOG('* ECO + ally('..allyScore..') enemy('..enemyScore..') - ArmyRatio: '..math.floor(MyArmyRatio)..'% - Build/CheatMult old: '..math.floor(tonumber(ScenarioInfo.Options.BuildMult)*10)..' '..math.floor(tonumber(ScenarioInfo.Options.CheatMult)*10)..' - new: '..math.floor(BuildMult*10)..' '..math.floor(CheatMult*10)..'')
                    SetArmyPoolBuff(aiBrain, CheatMult, BuildMult)
                elseif MyArmyRatio > 105 then
                    CheatMult = CheatMult - 0.1
                    if CheatMult < 1.0 then CheatMult = 1.0 end
                    if BuildMult ~= tonumber(BuildMultOption) then BuildMult = tonumber(BuildMultOption) end
                    --LOG('* ECO + ally('..allyScore..') enemy('..enemyScore..') - ArmyRatio: '..math.floor(MyArmyRatio)..'% - Build/CheatMult old: '..math.floor(tonumber(ScenarioInfo.Options.BuildMult)*10)..' '..math.floor(tonumber(ScenarioInfo.Options.CheatMult)*10)..' - new: '..math.floor(BuildMult*10)..' '..math.floor(CheatMult*10)..'')
                    SetArmyPoolBuff(aiBrain, CheatMult, BuildMult)
                -- Normal ECO
                else -- MyArmyRatio > 85  MyArmyRatio <= 100
                    if CheatMult > CheatMultOption then
                        CheatMult = CheatMult - 0.1
                        if CheatMult < tonumber(CheatMultOption) then CheatMult = tonumber(CheatMultOption) end
                    elseif CheatMult < CheatMultOption then
                        CheatMult = CheatMult + 0.1
                        if CheatMult > tonumber(CheatMultOption) then CheatMult = tonumber(CheatMultOption) end
                    end
                    if BuildMult > BuildMultOption then
                        BuildMult = BuildMult - 0.1
                        if BuildMult < tonumber(BuildMultOption) then BuildMult = tonumber(BuildMultOption) end
                    elseif BuildMult < BuildMultOption then
                        BuildMult = BuildMult + 0.1
                        if BuildMult > tonumber(BuildMultOption) then BuildMult = tonumber(BuildMultOption) end
                    end
                    --LOG('* ECO + ally('..allyScore..') enemy('..enemyScore..') - ArmyRatio: '..math.floor(MyArmyRatio)..'% - Build/CheatMult old: '..math.floor(tonumber(ScenarioInfo.Options.BuildMult)*10)..' '..math.floor(tonumber(ScenarioInfo.Options.CheatMult)*10)..' - new: '..math.floor(BuildMult*10)..' '..math.floor(CheatMult*10)..'')
                    SetArmyPoolBuff(aiBrain, CheatMult, BuildMult)
                end
            end
        end

        if aiBrain:GetEconomyTrend('ENERGY') < 0.0 then
            -- Emergency Low Energy
            if aiBrain:GetEconomyStoredRatio('ENERGY') < 0.75 then
                -- Disable Nuke
                if DisableUnits(aiBrain, categories.STRUCTURE * categories.NUKE * (categories.TECH3 + categories.EXPERIMENTAL), 'Nuke') then bussy = true
                -- Disable Massfabricators
                elseif DisableUnits(aiBrain, categories.STRUCTURE * categories.MASSFABRICATION, 'MassFab') then bussy = true
                -- Disable AntiNuke
                elseif DisableUnits(aiBrain, categories.STRUCTURE * categories.ANTIMISSILE * categories.SILO * categories.TECH3, 'AntiNuke') then bussy = true
                -- Disable Intel
                elseif DisableUnits(aiBrain, categories.RADAR + categories.OMNI + categories.SONAR, 'Intel') then bussy = true
                -- Disable ExperimentalShields
                elseif DisableUnits(aiBrain, categories.STRUCTURE * categories.SHIELD * categories.EXPERIMENTAL, 'ExperimentalShields') then bussy = true
                -- Disable NormalShields
                elseif DisableUnits(aiBrain, categories.STRUCTURE * categories.SHIELD - categories.EXPERIMENTAL, 'NormalShields') then bussy = true
                end
            end
        end

        if bussy then
            continue -- while true do
        end

        if aiBrain:GetEconomyTrend('MASS') < 0.0 then
            -- Emergency Low Mass
            if aiBrain:GetEconomyStoredRatio('MASS') < 0.25 then
                -- Disable AntiNuke
                if DisableUnits(aiBrain, categories.STRUCTURE * categories.ANTIMISSILE * categories.SILO * categories.TECH3, 'AntiNuke') then bussy = true
                end
            elseif aiBrain:GetEconomyStoredRatio('MASS') < 0.50 then
                -- Disable Nuke
                if DisableUnits(aiBrain, categories.STRUCTURE * categories.NUKE * (categories.TECH3 + categories.EXPERIMENTAL), 'Nuke') then bussy = true
                end
            end
        elseif aiBrain:GetEconomyStoredRatio('ENERGY') > 0.95 then
            if aiBrain:GetEconomyStoredRatio('MASS') > 0.50 then
                -- Enable NormalShields
                if EnableUnits(aiBrain, categories.STRUCTURE * categories.SHIELD - categories.EXPERIMENTAL, 'NormalShields') then bussy = true
                -- Enable ExperimentalShields
                elseif EnableUnits(aiBrain, categories.STRUCTURE * categories.SHIELD * categories.EXPERIMENTAL, 'ExperimentalShields') then bussy = true
                -- Enable Intel
                elseif EnableUnits(aiBrain, categories.RADAR + categories.OMNI + categories.SONAR, 'Intel') then bussy = true
                -- Enable AntiNuke
                elseif EnableUnits(aiBrain, categories.STRUCTURE * categories.ANTIMISSILE * categories.SILO * categories.TECH3, 'AntiNuke') then bussy = true
                -- Enable massfabricators
                elseif EnableUnits(aiBrain, categories.STRUCTURE * categories.MASSFABRICATION, 'MassFab') then bussy = true
                -- Enable Nuke
                elseif EnableUnits(aiBrain, categories.STRUCTURE * categories.NUKE * (categories.TECH3 + categories.EXPERIMENTAL), 'Nuke') then bussy = true
                end
            elseif aiBrain:GetEconomyStoredRatio('MASS') > 0.25 then
                -- Enable NormalShields
                if EnableUnits(aiBrain, categories.STRUCTURE * categories.SHIELD - categories.EXPERIMENTAL, 'NormalShields') then bussy = true
                -- Enable ExperimentalShields
                elseif EnableUnits(aiBrain, categories.STRUCTURE * categories.SHIELD * categories.EXPERIMENTAL, 'ExperimentalShields') then bussy = true
                -- Enable Intel
                elseif EnableUnits(aiBrain, categories.RADAR + categories.OMNI + categories.SONAR, 'Intel') then bussy = true
                -- Enable AntiNuke
                elseif EnableUnits(aiBrain, categories.STRUCTURE * categories.ANTIMISSILE * categories.SILO * categories.TECH3, 'AntiNuke') then bussy = true
                -- Enable massfabricators
                elseif EnableUnits(aiBrain, categories.STRUCTURE * categories.MASSFABRICATION, 'MassFab') then bussy = true
                end
            else
                -- Enable NormalShields
                if EnableUnits(aiBrain, categories.STRUCTURE * categories.SHIELD - categories.EXPERIMENTAL, 'NormalShields') then bussy = true
                -- Enable ExperimentalShields
                elseif EnableUnits(aiBrain, categories.STRUCTURE * categories.SHIELD * categories.EXPERIMENTAL, 'ExperimentalShields') then bussy = true
                -- Enable Intel
                elseif EnableUnits(aiBrain, categories.RADAR + categories.OMNI + categories.SONAR, 'Intel') then bussy = true
                -- Enable massfabricators
                elseif EnableUnits(aiBrain, categories.STRUCTURE * categories.MASSFABRICATION, 'MassFab') then bussy = true
                end
            end
        end

        if bussy then
            continue -- while true do
        end

        -- loop over assisting engineers and manage pause / unpause
        for _, unit in Engineers do
            -- if the unit is dead, continue with the next unit
            if unit.Dead then continue end
            -- Only Check units that are assisting
            if not unit.PlatoonHandle.PlatoonData.Assist.AssisteeType then continue end
            -- Only Check units that have UnitBeingAssist
            if not unit.UnitBeingAssist then continue end

            -- Is the engineer idle ?
            if aiBrain.HasParagon then
                if unit:IsPaused() then
                    unit:SetPaused( false )
                    bussy = true
                    break -- for _, unit in Engineers do
                end
            -- We have negative eco. Check if we can switch something off
            elseif aiBrain:GetEconomyTrend('MASS') < 0.0 or aiBrain:GetEconomyTrend('ENERGY') < 0.0 then
                -- if this unit is already paused, continue with the next unit
                if unit:IsPaused() then continue end
                -- Emergency low eco, disable everything
                if aiBrain:GetEconomyStoredRatio('MASS') < 0.01 or aiBrain:GetEconomyStoredRatio('ENERGY') < 0.99 then
                    -- Pause Energy assist
                    if EntityCategoryContains(categories.STRUCTURE * categories.ENERGYPRODUCTION, unit.UnitBeingAssist) then
                        unit:SetPaused( true )
                        bussy = true
                        break -- for _, unit in Engineers do
                    end
                    -- disband all other assist Platoons
                    unit.PlatoonHandle:Stop()
                    unit.PlatoonHandle:PlatoonDisband()
                    bussy = true
                    break
                -- Extreme low eco, disable everything
                elseif aiBrain:GetEconomyStoredRatio('MASS') < 0.05 or aiBrain:GetEconomyStoredRatio('ENERGY') < 0.99 then
                    -- Pause Energy assist
                    if EntityCategoryContains(categories.STRUCTURE * categories.ENERGYPRODUCTION, unit.UnitBeingAssist) then
                        unit:SetPaused( true )
                        bussy = true
                        break -- for _, unit in Engineers do
                    end
                    -- disband all other assist Platoons
                    unit.PlatoonHandle:Stop()
                    unit.PlatoonHandle:PlatoonDisband()
                    bussy = true
                    break
                -- Very low eco, disable everything but energy assister
                elseif aiBrain:GetEconomyStoredRatio('MASS') < 0.10 or aiBrain:GetEconomyStoredRatio('ENERGY') < 0.99 then
                    -- Pause Factory assist
                    if EntityCategoryContains(categories.STRUCTURE * categories.FACTORY, unit.UnitBeingAssist) then
                        unit:SetPaused( true )
                        bussy = true
                        break -- for _, unit in Engineers do
                    -- Pause Energy assist
                    elseif EntityCategoryContains(categories.STRUCTURE * categories.ENERGYPRODUCTION, unit.UnitBeingAssist) then
                        unit:SetPaused( true )
                        bussy = true
                        break -- for _, unit in Engineers do
                    end
                    -- disband all other assist Platoons
                    unit.PlatoonHandle:Stop()
                    unit.PlatoonHandle:PlatoonDisband()
                    bussy = true
                    break
                -- Very low eco, disable everything but energy assister
                elseif aiBrain:GetEconomyStoredRatio('MASS') < 0.30 or aiBrain:GetEconomyStoredRatio('ENERGY') < 0.99 then
                    -- Pause Paragon assist
                    if EntityCategoryContains(categories.STRUCTURE * categories.EXPERIMENTAL * categories.ECONOMIC, unit.UnitBeingAssist) then
                        unit:SetPaused( true )
                        bussy = true
                        break -- for _, unit in Engineers do
                    -- Pause Factory assist
                    elseif EntityCategoryContains(categories.STRUCTURE * categories.FACTORY, unit.UnitBeingAssist) then
                        unit:SetPaused( true )
                        bussy = true
                        break -- for _, unit in Engineers do
                    -- Third Pause Energy assist
                    elseif EntityCategoryContains(categories.STRUCTURE * categories.ENERGYPRODUCTION, unit.UnitBeingAssist) then
                        unit:SetPaused( true )
                        bussy = true
                        break -- for _, unit in Engineers do
                    end
                    -- disband all other assist Platoons
                    unit.PlatoonHandle:Stop()
                    unit.PlatoonHandle:PlatoonDisband()
                    bussy = true
                    break
                -- Low Eco, disable all engineers exept thosw who are assisting energy buildings
                elseif aiBrain:GetEconomyStoredRatio('MASS') < 0.40 or aiBrain:GetEconomyStoredRatio('ENERGY') < 0.99 then
                    -- Pause Experimental assist
                    if EntityCategoryContains(categories.STRUCTURE * categories.EXPERIMENTAL * categories.ECONOMIC, unit.UnitBeingAssist) then
                        unit:SetPaused( true )
                        bussy = true
                        break -- for _, unit in Engineers do
                    -- Pause Paragon assist
                    elseif EntityCategoryContains(categories.STRUCTURE * categories.EXPERIMENTAL * categories.ECONOMIC, unit.UnitBeingAssist) then
                        unit:SetPaused( true )
                        bussy = true
                        break -- for _, unit in Engineers do
                    -- Pause Factory assist
                    elseif EntityCategoryContains(categories.STRUCTURE * categories.FACTORY, unit.UnitBeingAssist) then
                        unit:SetPaused( true )
                        bussy = true
                        break -- for _, unit in Engineers do
                    -- Pause Energy assist
                    elseif EntityCategoryContains(categories.STRUCTURE * categories.ENERGYPRODUCTION, unit.UnitBeingAssist) then
                        unit:SetPaused( true )
                        bussy = true
                        break -- for _, unit in Engineers do
                    end
                    -- disband all other assist Platoons
                    unit.PlatoonHandle:Stop()
                    unit.PlatoonHandle:PlatoonDisband()
                    bussy = true
                    break
                end
            -- We have positive eco. Check if we can switch something on
            elseif aiBrain:GetEconomyTrend('MASS') >= 0.0 and aiBrain:GetEconomyTrend('ENERGY') >= 0.0 then
                -- if this unit is paused, continue with the next unit
                if not unit:IsPaused() then continue end
                if aiBrain:GetEconomyStoredRatio('MASS') >= 0.40 and aiBrain:GetEconomyStoredRatio('ENERGY') >= 0.99 then
                    unit:SetPaused( false )
                    bussy = true
                    break -- for _, unit in Engineers do
                elseif aiBrain:GetEconomyStoredRatio('MASS') >= 0.30 and aiBrain:GetEconomyStoredRatio('ENERGY') >= 0.99 then
                    -- UnPause Paragon assist
                    if EntityCategoryContains(categories.STRUCTURE * categories.EXPERIMENTAL * categories.ECONOMIC, unit.UnitBeingAssist) then
                        unit:SetPaused( true )
                        bussy = true
                        break -- for _, unit in Engineers do
                    -- UnPause Factory assist
                    elseif EntityCategoryContains(categories.STRUCTURE * categories.FACTORY, unit.UnitBeingAssist) then
                        unit:SetPaused( true )
                        bussy = true
                        break -- for _, unit in Engineers do
                    -- UnPause Energy assist
                    elseif EntityCategoryContains(categories.STRUCTURE * categories.ENERGYPRODUCTION, unit.UnitBeingAssist) then
                        unit:SetPaused( true )
                        bussy = true
                        break -- for _, unit in Engineers do
                    end
                elseif aiBrain:GetEconomyStoredRatio('MASS') >= 0.10 and aiBrain:GetEconomyStoredRatio('ENERGY') >= 0.99 then
                    -- UnPause Factory assist
                    if EntityCategoryContains(categories.STRUCTURE * categories.FACTORY, unit.UnitBeingAssist) then
                        unit:SetPaused( true )
                        bussy = true
                        break -- for _, unit in Engineers do
                    -- UnPause Energy assist
                    elseif EntityCategoryContains(categories.STRUCTURE * categories.ENERGYPRODUCTION, unit.UnitBeingAssist) then
                        unit:SetPaused( true )
                        bussy = true
                        break -- for _, unit in Engineers do
                    end
                elseif aiBrain:GetEconomyStoredRatio('MASS') >= 0.05 and aiBrain:GetEconomyStoredRatio('ENERGY') >= 0.99 then
                    -- UnPause Energy assist
                    if EntityCategoryContains(categories.STRUCTURE * categories.ENERGYPRODUCTION, unit.UnitBeingAssist) then
                        unit:SetPaused( true )
                        bussy = true
                        break -- for _, unit in Engineers do
                    end
                end
            end
        end
        if bussy then
            continue -- while true do
        end
        -- loop over Factories and manage pause / unpause
        for _, unit in Factories do
            -- if the unit is dead, continue with the next unit
            if unit.Dead then continue end
            if aiBrain.HasParagon then
                if unit:IsPaused() then
                    unit:SetPaused( false )
                    bussy = true
                    break -- for _, unit in Engineers do
                end
            -- We have negative eco. Check if we can switch something off
            elseif aiBrain:GetEconomyStoredRatio('MASS') < 0.01 or aiBrain:GetEconomyStoredRatio('ENERGY') < 0.75 then
                if unit:IsPaused() then continue end
                if not unit.UnitBeingBuilt then continue end
                if EntityCategoryContains(categories.ENGINEER + categories.TECH1, unit.UnitBeingBuilt) then continue end
                if table.getn(Factories) == 1 then continue end
                unit:SetPaused( true )
                bussy = true
                break -- for _, unit in Engineers do
            else
                if not unit:IsPaused() then continue end
                unit:SetPaused( false )
                bussy = true
                break -- for _, unit in Engineers do
            end
        end
        if bussy then
            continue -- while true do
        end
        -- loop over building engineers and manage pause / unpause
        for _, unit in Engineers do
            -- if the unit is dead, continue with the next unit
            if unit.Dead then continue end
            if unit.PlatoonHandle.PlatoonData.Assist.AssisteeType then continue end
            -- Only Check units that are assisting
            if not unit.UnitBeingBuilt then continue end
            if aiBrain.HasParagon or unit.noPause then
                if unit:IsPaused() then
                    unit:SetPaused( false )
                    bussy = true
                    break -- for _, unit in Engineers do
                end
            -- We have negative eco. Check if we can switch something off
            elseif aiBrain:GetEconomyStoredRatio('ENERGY') < 0.01 then
                if unit:IsPaused() then continue end
                if not EntityCategoryContains( categories.ENERGYPRODUCTION + ((categories.MASSEXTRACTION + categories.FACTORY + categories.ENERGYSTORAGE) * categories.TECH1) , unit.UnitBeingBuilt) then
                    unit:SetPaused( true )
                    bussy = true
                    break -- for _, unit in Engineers do
                end
            elseif aiBrain:GetEconomyStoredRatio('MASS') < 0.01 then
                if unit:IsPaused() then continue end
                if not EntityCategoryContains( categories.MASSEXTRACTION + ((categories.ENERGYPRODUCTION + categories.FACTORY + categories.MASSSTORAGE) * categories.TECH1) , unit.UnitBeingBuilt) then
                    unit:SetPaused( true )
                    bussy = true
                    break -- for _, unit in Engineers do
                end
            -- We have positive eco. Check if we can switch something on
            elseif aiBrain:GetEconomyStoredRatio('MASS') >= 0.2 and aiBrain:GetEconomyStoredRatio('ENERGY') >= 0.80 then
                if not unit:IsPaused() then continue end
                unit:SetPaused( false )
                bussy = true
                break -- for _, unit in Engineers do
            elseif aiBrain:GetEconomyStoredRatio('MASS') >= 0.01 and aiBrain:GetEconomyStoredRatio('ENERGY') >= 0.80 then
                if not unit:IsPaused() then continue end
                if EntityCategoryContains((categories.ENERGYPRODUCTION + categories.MASSEXTRACTION) - categories.EXPERIMENTAL, unit.UnitBeingBuilt) then
                    unit:SetPaused( false )
                    bussy = true
                    break -- for _, unit in Engineers do
                end
            elseif aiBrain:GetEconomyStoredRatio('ENERGY') >= 1.00 then
                if not unit:IsPaused() then continue end
                if not EntityCategoryContains(categories.ENERGYPRODUCTION - categories.EXPERIMENTAL, unit.UnitBeingBuilt) then
                    unit:SetPaused( false )
                    bussy = true
                    break -- for _, unit in Engineers do
                end
            end
        end
        if bussy then
            continue -- while true do
        end
   end
end

function DisableUnits(aiBrain, Category, UnitType)
    local Units = aiBrain:GetListOfUnits(Category, false, false) -- also gets unbuilded units (planed to build)
    for _, unit in Units do
        if unit.Dead then continue end
        if unit:GetFractionComplete() ~= 1 then continue end
        -- Units that only needs to be set on pause
        if UnitType == 'Nuke' or UnitType == 'AntiNuke' then
            if not unit:IsPaused() then
                --LOG('*DisableUnits: Unit :SetPaused true'..UnitType..' - '..unit:GetBlueprint().BlueprintId..' - '..aiBrain.Name)
                unit:SetPaused( true )
                -- now return, we only want do disable one unit per loop
                return true
            end
        end
        -- Maintenance -- for units that are usually "on": radar, mass extractors, etc.
        if unit.MaintenanceConsumption == true then
            unit:OnProductionPaused()
            --LOG('*DisableUnits: Unit OnProductionPaused '..UnitType..' - '..unit:GetBlueprint().BlueprintId..' - '..aiBrain.Name)
            return true
        end
        -- Active -- when upgrading, constructing, or something similar.
        if unit.ActiveConsumption == true then
            unit:SetActiveConsumptionInactive()
            --LOG('*DisableUnits: Unit SetActiveConsumptionInactive '..UnitType..' - '..unit:GetBlueprint().BlueprintId..' - '..aiBrain.Name)
            return true
        end
    end
    return false
end

function EnableUnits(aiBrain, Category, UnitType)
    local Units = aiBrain:GetListOfUnits(Category, false, false) -- also gets unbuilded units (planed to build)
    for _, unit in Units do
        if unit.Dead then continue end
        if unit:GetFractionComplete() ~= 1 then continue end
        -- Units that only needs to be set on pause
        if UnitType == 'Nuke' or UnitType == 'AntiNuke' then
            if unit:IsPaused() then
                --LOG('*EnableUnits: Unit :SetPaused false '..UnitType..' - '..unit:GetBlueprint().BlueprintId..' - '..aiBrain.Name)
                unit:SetPaused( false )
                -- now return, we only want do disable one unit per loop
                return true
            end
        end
        -- Maintenance -- for units that are usually "on": radar, mass extractors, etc.
        if unit.MaintenanceConsumption == false then
            unit:OnProductionUnpaused()
            --LOG('*EnableUnits: Unit OnProductionUnpaused '..UnitType..' - '..unit:GetBlueprint().BlueprintId..' - '..aiBrain.Name)
            return true
        end
        -- Active -- when upgrading, constructing, or something similar.
        if unit.ActiveConsumption == false then
            unit:SetActiveConsumptionActive()
            --LOG('*EnableUnits: Unit SetActiveConsumptionActive '..UnitType..' - '..unit:GetBlueprint().BlueprintId..' - '..aiBrain.Name)
            return true
        end
    end
    return false
end

function LocationRangeManagerThread(aiBrain)
    LOG('* AI-Uveso: Function LocationRangeManagerThread() started. ['..aiBrain.Nickname..']')
    local unitcounterdelayer = 0
    local ArmyUnits = {}
    -- wait at start of the game for delayed AI message
    while GetGameTimeSeconds() < 20 + aiBrain:GetArmyIndex() do
        WaitTicks(10)
    end
    if not import('/lua/AI/sorianutilities.lua').CheckForMapMarkers(aiBrain) then
        import('/lua/AI/sorianutilities.lua').AISendChat('all', ArmyBrains[aiBrain:GetArmyIndex()].Nickname, 'badmap')
    end

    while aiBrain.Result ~= "defeat" do
        --LOG('* AI-Uveso: Function LocationRangeManagerThread() beat. ['..aiBrain.Nickname..']')
        -- loop over all location managers
--        for baseLocation, managers in aiBrain.BuilderManagers do
            -- get all factories from this location
--            local Factories = managers.FactoryManager.FactoryList
            -- loop over all factories
--            for k,factory in Factories do
                -- is our factory not building or upgrading ?
--                if factory and not factory.Dead and not factory:BeenDestroyed() and factory:IsUnitState('Building') == false and factory:IsUnitState('Upgrading') == false then
                    -- check if our factory is more then 30 seconds inactice
--                    if factory.LastActive and GetGameTimeSeconds() - factory.LastActive > 30 then
                        --SPEW('* AI-Uveso: LocationRangeManagerThread: "Factory '..k..'" at location "'..baseLocation..'" is not working. Last activity "'.. math.floor(GetGameTimeSeconds() - factory.LastActive) ..'" seconds ago. Reforking FactoryManager.')
                        -- fork a new build thread for our factory
                        --managers.FactoryManager:ForkThread(managers.FactoryManager.DelayBuildOrder, factory, factory.BuilderManagerData.BuilderType, 1)
--                        if not factory.ForkedDelayThread then
--                            LOG('factory.ForkedDelayThread FALSE')
--                        else
--                            LOG('factory.ForkedDelayThread true')
--                        end
--                    end
--                end
--            end
--        end
        -- Check engineers
        -- at the moment engineers are working well. no need to validate
--        EngineerUnits = aiBrain:GetListOfUnits(categories.MOBILE * categories.ENGINEER * categories.TECH1, false, false) -- also gets unbuilded units (planed to build)
--        for k, engineer in EngineerUnits do
--            if engineer.LastActive then
--                local LastActive = GetGameTimeSeconds() - engineer.LastActive
--                engineer:SetCustomName(LastActive)
--                if LastActive > 70 then
--                    WARN('* AI-Uveso: LocationRangeManagerThread: "engineer '..k..'" at location "'..'X'..'" is not working. Last activity "'.. math.floor(LastActive) ..'" seconds ago.')
--                end
--            end
--        end

        -- Check and set the location radius of our main base and expansions
        local BasePositions = BaseRanger(aiBrain)
        -- Check if we have units outside the range of any BaseManager
        -- Get all units from our ArmyPool. These are units without a special platoon or task. They have nothing to do.
        ArmyUnits = aiBrain:GetListOfUnits(categories.MOBILE - categories.MOBILESONAR, false, false) -- also gets unbuilded units (planed to build)
        -- Loop over every unit that has no platton and is idle
        local LoopDelay = 0
        for _, unit in ArmyUnits do
            if unit.Dead then
                continue
            end
            -- check if we have name debugging enabled (ScenarioInfo.Options.AIPLatoonNameDebug = Uveso or Sorian or Dilli)
            if (aiBrain[ScenarioInfo.Options.AIPLatoonNameDebug] or ScenarioInfo.Options.AIPLatoonNameDebug == 'all')  then
                if unit.PlatoonHandle then
                    local Plan = unit.PlatoonHandle.PlanName
                    local Builder = unit.PlatoonHandle.BuilderName
                    if Plan or Builder then
                        unit:SetCustomName(''..(Builder or 'Unknown')..' ('..(Plan or 'Unknown')..')')
                        unit.LastPlatoonHandle = {}
                        unit.LastPlatoonHandle.PlanName = unit.PlatoonHandle.PlanName
                        unit.LastPlatoonHandle.BuilderName = unit.PlatoonHandle.BuilderName
                    else
                        if unit.LastPlatoonHandle then
                            local Plan = unit.LastPlatoonHandle.PlanName
                            local Builder = unit.LastPlatoonHandle.BuilderName
                            unit:SetCustomName('+ no Plan, Old: '..(Builder or 'Unknown')..' ('..(Plan or 'Unknown')..')')
                        else
                            unit:SetCustomName('+ Platoon, no Plan')
                        end
                    end
                else
                    unit:SetCustomName('- ArmyPool')
                end
            end
            local WeAreInRange = false
            local nearestbase
            if not unit.Dead
                and EntityCategoryContains(categories.MOBILE - categories.COMMAND - categories.ENGINEER, unit)
                and unit:GetFractionComplete() == 1
                and unit:IsIdleState()
                and not unit:IsMoving()
                and (not unit.PlatoonHandle or (not unit.PlatoonHandle.PlanName and not unit.PlatoonHandle.BuilderName))
            then
                local UnitPos = unit:GetPosition()
                local NeedNavalBase = EntityCategoryContains(categories.NAVAL, unit)
                -- loop over every location and check the distance between the unit and the location
                for location, base in BasePositions do
                    -- If we need a naval base then skip all non naval areas
                    if NeedNavalBase and base.Type ~= 'Naval Area' then
                        --LOG('Need naval; but got land base: '..base.Type)
                        continue
                    end
                    -- If we need a land base then skip all naval areas
                    if not NeedNavalBase and base.Type == 'Naval Area' then
                        --LOG('Need land; but got naval base: '..base.Type)
                        continue
                    end
                    local dist = VDist2( UnitPos[1], UnitPos[3], base.Pos[1], base.Pos[3] )
                    -- if we are in range of a base, continue. We don't need to move the unit. It's in range of a basemanager
                    if dist < base.Rad then
                        WeAreInRange = true
                        break
                    end
                    -- remember the nearest base. We will move to it.
                    if not nearestbase or nearestbase.dist > dist then
                        nearestbase = {}
                        nearestbase.Pos = base.Pos
                        nearestbase.dist = dist
                    end
                end
                -- if we are not in range of an base, then move closer to a base.
                if WeAreInRange == false and not unit.Dead then
                    if nearestbase then
                        if aiBrain[ScenarioInfo.Options.AIPLatoonNameDebug] or ScenarioInfo.Options.AIPLatoonNameDebug == 'all' then
                            unit:SetCustomName('Outside LocationManager')
                        end
                        IssueClearCommands({unit})
                        IssueStop({unit})
                        IssueMove({unit}, nearestbase.Pos)
                    end
                end
            end
            -- delay the loop after every 50 units. looping over 1000 units will take 2 seconds
            LoopDelay = LoopDelay + 1
            if LoopDelay > 50 then
                LoopDelay = 0
                WaitTicks(1)
            end
        end
        if 1 == 2 then
        -- watching the unit Cap for AI balance.
            unitcounterdelayer = unitcounterdelayer + 1
            if unitcounterdelayer > 12 then
                unitcounterdelayer = 0
                local MaxCap = GetArmyUnitCap(aiBrain:GetArmyIndex())
                LOG('  ')
                LOG(' 05.0 | '..math.floor(100 / MaxCap * table.getn(aiBrain:GetListOfUnits(categories.MOBILE * categories.ENGINEER * categories.TECH1, false, false) ) )..' -  Engineers TECH1  - ' )
                LOG(' 05.0 | '..math.floor(100 / MaxCap * table.getn(aiBrain:GetListOfUnits(categories.MOBILE * categories.ENGINEER * categories.TECH2, false, false) ) )..' -  Engineers TECH2  - ' )
                LOG(' 05.0 | '..math.floor(100 / MaxCap * table.getn(aiBrain:GetListOfUnits(categories.MOBILE * categories.ENGINEER * categories.TECH3 - categories.SUBCOMMANDER, false, false) ) )..' -  Engineers TECH3  - ' )
                LOG(' 03.0 | '..math.floor(100 / MaxCap * table.getn(aiBrain:GetListOfUnits(categories.MOBILE * categories.SUBCOMMANDER, false, false) ) )..' -  SubCommander   - ' )
                LOG(' 45.0 | '..math.floor(100 / MaxCap * table.getn(aiBrain:GetListOfUnits(categories.MOBILE - (categories.ENGINEER * categories.MOBILE), false, false) ) )..' -  Mobile Attack Force  - ' )
                LOG(' 10.0 | '..math.floor(100 / MaxCap * table.getn(aiBrain:GetListOfUnits(categories.STRUCTURE * categories.MASSEXTRACTION, false, false) ) )..' -  Extractors    - ' )
                LOG(' 12.0 | '..math.floor(100 / MaxCap * table.getn(aiBrain:GetListOfUnits(categories.STRUCTURE * categories.DEFENSE, false, false) ) )..' -  Structures Defense   - ' )
                LOG(' 12.0 | '..math.floor(100 / MaxCap * table.getn(aiBrain:GetListOfUnits(categories.STRUCTURE - categories.MASSEXTRACTION - categories.DEFENSE - (categories.STRUCTURE * categories.FACTORY), false, false) ) )..' -  Structures all   - ' )
                LOG(' 02.4 | '..math.floor(100 / MaxCap * table.getn(aiBrain:GetListOfUnits(categories.STRUCTURE * categories.FACTORY * categories.LAND, false, false) ) )..' -  Factory Land  - ' )
                LOG(' 02.4 | '..math.floor(100 / MaxCap * table.getn(aiBrain:GetListOfUnits(categories.STRUCTURE * categories.FACTORY * categories.AIR, false, false) ) )..' -  Factory Air   - ' )
                LOG(' 02.4 | '..math.floor(100 / MaxCap * table.getn(aiBrain:GetListOfUnits(categories.STRUCTURE * categories.FACTORY * categories.NAVAL, false, false) ) )..' -  Factory Sea   - ' )
                LOG('------|------')
                LOG('100.0 | '..math.floor(100 / MaxCap * table.getn(aiBrain:GetListOfUnits(categories.STRUCTURE + categories.MOBILE, false, false) ) )..' -  Structure + Mobile   - ' )
--                UNITS = aiBrain:GetListOfUnits(categories.STRUCTURE - categories.MASSEXTRACTION - categories.DEFENSE - (categories.STRUCTURE * categories.FACTORY), false, false)
--                for k,unit in UNITS do
--                    local description = unit:GetBlueprint().Description
--                    local location = unit:GetPosition()
--                    LOG('K='..k..' - Unit= '..description..' - '..repr(location))
--                end
            end
        end
        WaitTicks(50)

--        local SUtils = import('/lua/AI/sorianutilities.lua')
--        SUtils.AIRandomizeTaunt(aiBrain)

    end
end

function BaseRanger(aiBrain)
    local BaseRanger = {}
    if aiBrain.BuilderManagers then
        local BaseLocations = {
            [1] = 'MAIN',
            [2] = 'Naval Area',
            [3] = 'Blank Marker',
            [4] = 'Large Expansion Area',
            [5] = 'Expansion Area',
        }
        -- Check BaseLocations
        for Index, BaseType in BaseLocations do
            -- loop over BuilderManagers and check every location
            for k,v in aiBrain.BuilderManagers do
                -- Check baselocations sorted by BaseLocations Index
                if k ~= BaseType and Scenario.MasterChain._MASTERCHAIN_.Markers[v.FactoryManager.LocationType].type ~= BaseType then
                    -- No BaseLocation. Continue with the next array-key
                    continue
                end
                -- We found a BaseLocation
                local StartPos = v.FactoryManager.Location
                local StartRad = v.FactoryManager.Radius
                local V1Naval = string.find(k, 'Naval Area')
                -- This is the maximum base radius.
                local NewMax = 120
                -- Now check against every other baseLocation, and see if we need to reduce our base radius.
                for k2,v2 in aiBrain.BuilderManagers do
                    local V2Naval = string.find(k2, 'Naval Area')
                    -- Only check, if base markers are not the same. Exclude compare between land and water locations
                    if v ~= v2 and ((V1Naval and V2Naval) or (not V1Naval and not V2Naval)) then
                        local EndPos = v2.FactoryManager.Location
                        local EndRad = v2.FactoryManager.Radius
                        local dist = VDist2( StartPos[1], StartPos[3], EndPos[1], EndPos[3] )
                        -- If this is true, then we compare our MAIN base versus expansion location
                        if k == 'MAIN' then
                            -- Mainbase can use 66% of the distance to the next location (minimum 90). But only if we have enough space for the second base (>=30)
                            if NewMax > dist/3*2 and dist/3*2 > 90 and dist/3 >= 30 then
                                NewMax = dist/3*2
                                --LOG('Distance from mainbase['..k..']->['..k2..']='..dist..' Mainbase radius='..StartRad..' Set Radius to '..dist/3*2)
                            -- If we have not enough spacee for the second base, then use half the distance as location radius
                            elseif NewMax > dist/2 and dist/2 > 90 and dist/2 >= 30 then
                                NewMax = dist/2
                                --LOG('Distance to location['..k..']->['..k2..']='..dist..' location radius='..StartRad..' Set Radius to '..dist/2)
                            -- We have not enough space for the mainbase. Set it to 90. Wee need this radius for gathering plattons etc
                            else
                                NewMax = 90
                            end
                        -- This is true, then we compare expansion location versus MAIN base
                        elseif k2 == 'MAIN' then
                            -- Expansion can use 33% of the distance to the Mainbase.
                            if NewMax > dist - EndRad and dist - EndRad >= 30 then
                                NewMax = dist - EndRad
                                --LOG('Distance to mainbase['..k..']->['..k2..']='..dist..' Mainbase radius='..EndRad..' Set Radius to '..dist - EndRad)
                            end
                        -- Use as base radius half the way to the next marker.
                        else
                            -- if we dont compare against the mainbase then use 50% of the distance to the next location
                            if NewMax > dist/2 and dist/2 >= 30 then
                                NewMax = dist/2
                                --LOG('Distance to location['..k..']->['..k2..']='..dist..' location radius='..StartRad..' Set Radius to '..dist/2)
                            end
                        end
                    end
                end
                -- Now check for existing managers and set the new value to it
                if v.FactoryManager then
                    v.FactoryManager.Radius = NewMax
                end
                if v.EngineerManager then
                    v.EngineerManager.Radius = NewMax
                end
                if v.PlatoonFormManager then
                    v.PlatoonFormManager.Radius = NewMax
                end
                if v.StrategyManager then
                    v.StrategyManager.Radius = NewMax
                end
                -- Check if we have a terranhigh (or we can't draw the debug baseRanger)
                if StartPos[2] == 0 then
                    StartPos[2] = GetTerrainHeight(StartPos[1], StartPos[3])
                    -- store the TerranHeight inside Factorymanager
                    v.FactoryManager.Location = StartPos
                end
                -- Add the position and radius to the BaseRanger table
                BaseRanger[k] = {Pos = StartPos, Rad = math.floor(NewMax), Type = BaseType}
            end
        end
        -- store all bases ang radii global inside Scenario.MasterChain
        -- Wee need this to draw the debug circles
        if aiBrain.Uveso then
            if ScenarioInfo.Options.AIPathingDebug == 'pathlocation' then
                Scenario.MasterChain._MASTERCHAIN_.BaseRanger = Scenario.MasterChain._MASTERCHAIN_.BaseRanger or {}
                Scenario.MasterChain._MASTERCHAIN_.BaseRanger[aiBrain:GetArmyIndex()] = BaseRanger
            end
        end
    end
    return BaseRanger
end

function BaseTargetManagerThread(aiBrain)
    while GetGameTimeSeconds() < 25 + aiBrain:GetArmyIndex() do
        WaitTicks(10)
    end
    LOG('* AI-Uveso: Function BaseTargetManagerThread() started. ['..aiBrain.Nickname..']')
    local BasePanicZone, BaseMilitaryZone, BaseEnemyZone = import('/mods/AI-Uveso/lua/AI/uvesoutilities.lua').GetDangerZoneRadii()
    local targets = {}
    local baseposition, radius
    local ClosestTarget
    local distance
    while aiBrain.Result ~= "defeat" do
        --LOG('* AI-Uveso: Function BaseTargetManagerThread() beat. ['..aiBrain.Nickname..']')
        ClosestTarget = nil
        distance = 1024
        WaitTicks(50)
        if not baseposition then
            if aiBrain:PBMHasPlatoonList() then
                for k,v in aiBrain.PBM.Locations do
                    if v.LocationType == 'MAIN' then
                        baseposition = v.Location
                        radius = v.Radius
                        break
                    end
                end
            elseif aiBrain.BuilderManagers['MAIN'] then
                baseposition = aiBrain.BuilderManagers['MAIN'].FactoryManager:GetLocationCoords()
                radius = aiBrain.BuilderManagers['MAIN'].FactoryManager:GetLocationRadius()
            end
            if not baseposition then
                continue
            end
        end
        -- Search for experimentals in BasePanicZone
        targets = aiBrain:GetUnitsAroundPoint(categories.EXPERIMENTAL - categories.AIR - categories.INSIGNIFICANTUNIT, baseposition, 120, 'Enemy')
        for _, unit in targets do
            if not unit.Dead then
                if not IsEnemy( aiBrain:GetArmyIndex(), unit:GetAIBrain():GetArmyIndex() ) then continue end
                local TargetPosition = unit:GetPosition()
                local targetRange = VDist2(baseposition[1], baseposition[3], TargetPosition[1], TargetPosition[3])
                if targetRange < distance then
                    distance = targetRange
                    ClosestTarget = unit
                end
            end
        end
        WaitTicks(1)
        -- Search for experimentals in BaseMilitaryZone
        if not ClosestTarget then
            targets = aiBrain:GetUnitsAroundPoint(categories.EXPERIMENTAL - categories.AIR - categories.INSIGNIFICANTUNIT, baseposition, BaseMilitaryZone, 'Enemy')
            for _, unit in targets do
                if not unit.Dead then
                    if not IsEnemy( aiBrain:GetArmyIndex(), unit:GetAIBrain():GetArmyIndex() ) then continue end
                    local TargetPosition = unit:GetPosition()
                    local targetRange = VDist2(baseposition[1], baseposition[3], TargetPosition[1], TargetPosition[3])
                    if targetRange < distance then
                        distance = targetRange
                        ClosestTarget = unit
                    end
                end
            end
        end
        WaitTicks(1)
        -- Search for Paragons in EnemyZone
        if not ClosestTarget then
            targets = aiBrain:GetUnitsAroundPoint(categories.EXPERIMENTAL * categories.ECONOMIC, baseposition, BaseEnemyZone, 'Enemy')
            for _, unit in targets do
                if not unit.Dead then
                    if not IsEnemy( aiBrain:GetArmyIndex(), unit:GetAIBrain():GetArmyIndex() ) then continue end
                    local TargetPosition = unit:GetPosition()
                    local targetRange = VDist2(baseposition[1], baseposition[3], TargetPosition[1], TargetPosition[3])
                    if targetRange < distance then
                        distance = targetRange
                        ClosestTarget = unit
                    end
                end
            end
        end
        WaitTicks(1)
        -- Search for Shields in EnemyZone
        if not ClosestTarget then
            targets = aiBrain:GetUnitsAroundPoint(categories.STRUCTURE * categories.SHIELD, baseposition, BaseEnemyZone, 'Enemy')
            for _, unit in targets do
                if not unit.Dead then
                    if not IsEnemy( aiBrain:GetArmyIndex(), unit:GetAIBrain():GetArmyIndex() ) then continue end
                    local TargetPosition = unit:GetPosition()
                    local targetRange = VDist2(baseposition[1], baseposition[3], TargetPosition[1], TargetPosition[3])
                    if targetRange < distance then
                        distance = targetRange
                        ClosestTarget = unit
                    end
                end
            end
        end
        WaitTicks(1)
        -- Search for experimentals in EnemyZone
        if not ClosestTarget then
            targets = aiBrain:GetUnitsAroundPoint(categories.EXPERIMENTAL - categories.AIR - categories.INSIGNIFICANTUNIT, baseposition, BaseEnemyZone, 'Enemy')
            for _, unit in targets do
                if not unit.Dead then
                    if not IsEnemy( aiBrain:GetArmyIndex(), unit:GetAIBrain():GetArmyIndex() ) then continue end
                    local TargetPosition = unit:GetPosition()
                    local targetRange = VDist2(baseposition[1], baseposition[3], TargetPosition[1], TargetPosition[3])
                    if targetRange < distance then
                        distance = targetRange
                        ClosestTarget = unit
                    end
                end
            end
        end
        WaitTicks(1)
        -- Search for T3 Factories / Gates in EnemyZone
        if not ClosestTarget then
            targets = aiBrain:GetUnitsAroundPoint((categories.STRUCTURE * categories.GATE) + (categories.STRUCTURE * categories.FACTORY * categories.TECH3 - categories.SUPPORTFACTORY), baseposition, BaseEnemyZone, 'Enemy')
            for _, unit in targets do
                if not unit.Dead then
                    if not IsEnemy( aiBrain:GetArmyIndex(), unit:GetAIBrain():GetArmyIndex() ) then continue end
                    local TargetPosition = unit:GetPosition()
                    local targetRange = VDist2(baseposition[1], baseposition[3], TargetPosition[1], TargetPosition[3])
                    if targetRange < distance then
                        distance = targetRange
                        ClosestTarget = unit
                    end
                end
            end
        end
        aiBrain.PrimaryTarget = ClosestTarget
    end
end

function MarkerGridThreatManagerThread(aiBrain)
    while GetGameTimeSeconds() < 30 + aiBrain:GetArmyIndex() do
        WaitTicks(10)
    end
    LOG('* AI-Uveso: Function MarkerGridThreatManagerThread() started. ['..aiBrain.Nickname..']')
    local AIAttackUtils = import('/lua/ai/aiattackutilities.lua')
    local numTargetTECH123 = 0
    local numTargetTECH4 = 0
    local numTargetCOM = 0
    local armyIndex = aiBrain:GetArmyIndex()
    local PathGraphs = AIAttackUtils.GetPathGraphs()
    local Delayer = -1
    local vector
    if not (PathGraphs['Land'] or PathGraphs['Amphibious'] or PathGraphs['Air'] or PathGraphs['Water']) then
        WARN('* AI-Uveso: Function MarkerGridThreatManagerThread() No AI path markers found on map. Threat handling diabled!  '..ScenarioInfo.ArmySetup[aiBrain.Name].AIPersonality)
        -- end this forked thead
        return
    end
    while aiBrain.Result ~= "defeat" do
        ----LOG('* AI-Uveso: Function MarkerGridThreatManagerThread() beat. ['..aiBrain.Nickname..']')
        for Layer, LayerMarkers in PathGraphs do
            for graph, GraphMarkers in LayerMarkers do
                for nodename, markerInfo in GraphMarkers do
                    vector = Vector(markerInfo.position[1],markerInfo.position[2],markerInfo.position[3])
                    if markerInfo.layer == 'Land' then
                        numTargetTECH123 = aiBrain:GetNumUnitsAroundPoint( (categories.DIRECTFIRE + categories.INDIRECTFIRE + categories.GROUNDATTACK + categories.BOMBER) - categories.EXPERIMENTAL, vector , 30 , 'Enemy')
                        numTargetTECH4   = aiBrain:GetNumUnitsAroundPoint( (categories.DIRECTFIRE + categories.INDIRECTFIRE + categories.GROUNDATTACK + categories.BOMBER) * categories.EXPERIMENTAL, vector , 60 , 'Enemy')
                        numTargetCOM     = aiBrain:GetNumUnitsAroundPoint(categories.COMMAND, vector , 30 , 'Enemy')
                    end
                    if markerInfo.layer == 'Water' then
                        numTargetTECH123 = aiBrain:GetNumUnitsAroundPoint( (categories.NAVAL + categories.GROUNDATTACK + categories.BOMBER) - categories.EXPERIMENTAL, vector , 30 , 'Enemy')
                        numTargetTECH4   = aiBrain:GetNumUnitsAroundPoint( (categories.NAVAL + categories.GROUNDATTACK + categories.BOMBER) * categories.EXPERIMENTAL, vector , 60 , 'Enemy')
                    end
                    if markerInfo.layer == 'Air' then
                        numTargetTECH123 = aiBrain:GetNumUnitsAroundPoint(categories.ANTIAIR - categories.EXPERIMENTAL, vector , 60 , 'Enemy')
                        numTargetTECH4   = aiBrain:GetNumUnitsAroundPoint(categories.ANTIAIR * categories.EXPERIMENTAL, vector , 60 , 'Enemy')
                    end
                    if markerInfo.layer == 'Amphibious' then
                        numTargetTECH123 = aiBrain:GetNumUnitsAroundPoint( (categories.DIRECTFIRE + categories.INDIRECTFIRE + categories.GROUNDATTACK + categories.BOMBER) - categories.EXPERIMENTAL, vector , 30 , 'Enemy')
                        numTargetTECH4   = aiBrain:GetNumUnitsAroundPoint( (categories.DIRECTFIRE + categories.INDIRECTFIRE + categories.GROUNDATTACK + categories.BOMBER) * categories.EXPERIMENTAL, vector , 60 , 'Enemy')
                        numTargetCOM     = aiBrain:GetNumUnitsAroundPoint(categories.COMMAND, vector , 30 , 'Enemy')
                    end
                    local Threat = numTargetTECH123 * 15 + numTargetTECH4 * 60 + numTargetCOM * 30
                    --LOG('* MarkerGridThreatManagerThread: 1='..numTargetTECH1..'  2='..numTargetTECH2..'  3='..numTargetTECH123..'  4='..numTargetTECH4..' - Threat='..Threat..'.' )
                    Scenario.MasterChain._MASTERCHAIN_.Markers[nodename][armyIndex] = Threat
                    Delayer = Delayer + 1
                    if Delayer > 5 then
                        Delayer = 0
                        coroutine.yield(1)
                    end
                end
            end
        end
        coroutine.yield(1)
    end
end

function MassManagerThread(aiBrain)
    -- This function is not active!
    if 1 == 1 then
        return
    end
    
    while GetGameTimeSeconds() < 10 do
        WaitTicks(10)
    end
    LOG('* AI-Uveso: Function MassManagerThread() started. ['..aiBrain.Nickname..']')
    local PlatoonList
    local Engineers = {}
    local basePosition = aiBrain.BuilderManagers['MAIN'].Position

    -- create a list of mass markers sorted by distance to main base
    local MassMarker = {}
--    for _, v in Scenario.MasterChain._MASTERCHAIN_.Markers do
    for _, v in import('/lua/sim/ScenarioUtilities.lua').GetMarkers() do
        if v.type == 'Mass' then
            if v.position[1] <= 8 or v.position[1] >= ScenarioInfo.size[1] - 8 or v.position[3] <= 8 or v.position[3] >= ScenarioInfo.size[2] - 8 then
                -- mass marker is too close to border, skip it.
                continue
            end 
            table.insert(MassMarker, {Position = v.position, Distance = VDist3( v.position, basePosition ), NearestMarker = {} })
        end
    end
    table.sort(MassMarker, function(a,b) return a.Distance < b.Distance end)

    -- create a table for each marker with markers nearby
    for _,marker1 in MassMarker do
        for k2,marker2 in MassMarker do
            if VDist3( marker1.Position, marker2.Position ) < 35 and VDist3( marker1.Position, basePosition ) > 50 then
                table.insert(marker1.NearestMarker, k2)
            end
        end
    end
    --LOG('* AI-Uveso: Function MassManagerThread() ['..repr(MassMarker)..']')

    while aiBrain.Result ~= "defeat" do
        --LOG('* AI-Uveso: Function MassManagerThread() PULSE. ['..aiBrain.Nickname..']')
        -- make a table of all engineers with BuildOnMassAI AIPlan
        Engineers = {}
        PlatoonList = aiBrain:GetPlatoonsList()
        for _,Platoon in PlatoonList do
            if Platoon.PlanName and Platoon.PlanName == 'BuildOnMassAI' then
                --LOG('* AI-Uveso: Function MassManagerThread() Found Platton with plan '..Platoon.PlanName)
                local platoonUnits = Platoon:GetPlatoonUnits()
                for k, v in platoonUnits do
                    table.insert(Engineers, v )
                end
            end
        end
        --LOG('* AI-Uveso: Function MassManagerThread() engineer count: '..table.getn(Engineers))

        -- check if we have an idle engineer
        local IdleCount = 0
        for ke, Engineer in Engineers do
            if Engineer.Dead or Engineer:BeenDestroyed() then
                continue
            end
            if not Engineer:IsUnitState('Building') and Engineer:IsIdleState() then
                IdleCount = IdleCount + 1
            end
        end
        --LOG('* AI-Uveso: Function MassManagerThread() engineers that can work: '..repr(IdleCount))

        if IdleCount > 0 then
            local EngiOnTheWay
            local MexToCap
            local dist
            -- loop over all engineers and find the closest mass spot to move on
            for ke, Engineer in Engineers do
                if Engineer.Dead or Engineer:BeenDestroyed() or Engineer:IsUnitState('Building') or not Engineer:IsIdleState() or Engineer.MexToCap then
                    --LOG('* AI-Uveso: Engineer ['..ke..'] is bussy.')
                    continue
                end
                --LOG('* AI-Uveso: Engineer ['..ke..'] Searching for closest mass spot')
                EngiPos = Engineer:GetPosition()
                MexToCap = nil
                dist = nil
                -- loop over all mass points
                for km, marker in MassMarker do
                    --LOG('* AI-Uveso: Engineer ['..ke..'] check mass spot = ('..km..')')
                    -- is this the closest massmarker ?
                    if not dist or dist > VDist3( marker.Position, EngiPos ) then
                        --LOG('* AI-Uveso: Engineer ['..ke..'] closest mass spot = ('..km..') - distance = ('..VDist3( marker.Position, EngiPos )..')')
                        -- This could be our next mass spot, check if another engineer is already on the way to it
                        EngiOnTheWay = false
                        for kC, EngineerC in Engineers do
                            if EngineerC.Dead or EngineerC:BeenDestroyed() then
                                continue
                            end
                            -- don't check against yourself
                            if ke == kC then
                                continue
                            end
                            EngineerC.nextmex = EngineerC.nextmex or {}
                            for knm, mex in EngineerC.nextmex do
                                if mex == km then
                                    --LOG('* AI-Uveso: Engineer ['..ke..'] Engineer ['..kC..'] is already moving to ('..km..')')
                                    EngiOnTheWay = true
                                    break -- for knm, mex in EngineerC.nextmex do
                                end
                            end
                            -- Ther is already a engineer on the way to this spot, no need to search for another engineer.
                            if EngiOnTheWay then
                                break -- for kC, EngineerC in Engineers do
                            end
                        end
                        -- If no engineer is on the way, then this spot can be used. save it until we find maybe a closer one
                        if not EngiOnTheWay then
                            if not aiBrain:CanBuildStructureAt('ueb1103', marker.Position) then
                                local checkUnits = aiBrain:GetUnitsAroundPoint(categories.MASSEXTRACTION, marker.Position, 1, 'Ally')
                                if checkUnits and table.getn(checkUnits) > 0 then
                                    --LOG('* AI-Uveso: Engineer ['..ke..'] Found own/allied extractor at mass spot ['..km..']')
                                    continue
                                end
                            end
                            MexToCap = marker
                            MexToCapIndex = km
                            dist = VDist3( marker.Position, EngiPos )
                        end
                    end
                end
                if MexToCap then
                    --LOG('* AI-Uveso: Engineer ['..ke..'] moving to closest mass spot = ('..MexToCapIndex..')')
                    Engineer.MexToCap = MexToCap
                    Engineer.nextmex = MexToCap.NearestMarker
                    IdleCount = IdleCount - 1
                end
                -- check if we have still available engineers, if not break
                if IdleCount < 1 then
                    break -- for km, marker in MassMarker do
                end
            end

        end

        coroutine.yield(10)
    end
end
