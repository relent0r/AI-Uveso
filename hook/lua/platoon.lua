WARN('['..string.gsub(debug.getinfo(1).source, ".*\\(.*.lua)", "%1")..', line:'..debug.getinfo(1).currentline..'] * Uveso-AI: offset platoon.lua' )
-- 6627
local UUtils = import('/mods/AI-Uveso/lua/AI/uvesoutilities.lua')
oldPlatoon = Platoon
Platoon = Class(oldPlatoon) {

-- For AI Patch V3. 
    EngineerBuildAI = function(self)
        local aiBrain = self:GetBrain()
        local platoonUnits = self:GetPlatoonUnits()
        local armyIndex = aiBrain:GetArmyIndex()
        local x,z = aiBrain:GetArmyStartPos()
        local cons = self.PlatoonData.Construction
        local buildingTmpl, buildingTmplFile, baseTmpl, baseTmplFile

        -- Old version of delaying the build of an experimental.
        -- This was implemended but a depricated function from sorian AI. 
        -- makes the same as the new DelayEqualBuildPlattons. Can be deleted if all platoons are rewritten to DelayEqualBuildPlattons
        -- (This is also the wrong place to do it. Should be called from Buildermanager BEFORE the builder is selected)
        if cons.T4 then
            if not aiBrain.T4Building then
                --LOG('EngineerBuildAI'..repr(cons))
                aiBrain.T4Building = true
                ForkThread(SUtils.T4Timeout, aiBrain)
                --LOG('Building T4 uinit, delaytime started')
            else
                --LOG('BLOCK building T4 unit; aiBrain.T4Building = TRUE')
                WaitTicks(1)
                self:PlatoonDisband()
                return
            end
        end

        local eng
        for k, v in platoonUnits do
            if not v.Dead and EntityCategoryContains(categories.ENGINEER, v) then --DUNCAN - was construction
                IssueClearCommands({v})
                if not eng then
                    eng = v
                else
                    IssueGuard({v}, eng)
                end
            end
        end

        if not eng or eng.Dead then
            WaitTicks(1)
            self:PlatoonDisband()
            return
        end

        --DUNCAN - added
        if eng:IsUnitState('Building') or eng:IsUnitState('Upgrading') or eng:IsUnitState("Enhancing") then
           return
        end

        local FactionToIndex  = { UEF = 1, AEON = 2, CYBRAN = 3, SERAPHIM = 4, NOMADS = 5}
        local factionIndex = cons.FactionIndex or FactionToIndex[eng.factionCategory]

        buildingTmplFile = import(cons.BuildingTemplateFile or '/lua/BuildingTemplates.lua')
        baseTmplFile = import(cons.BaseTemplateFile or '/lua/BaseTemplates.lua')
        buildingTmpl = buildingTmplFile[(cons.BuildingTemplate or 'BuildingTemplates')][factionIndex]
        baseTmpl = baseTmplFile[(cons.BaseTemplate or 'BaseTemplates')][factionIndex]

        --LOG('*AI DEBUG: EngineerBuild AI ' .. eng.Sync.id)

        if self.PlatoonData.NeedGuard then
            eng.NeedGuard = true
        end

        -------- CHOOSE APPROPRIATE BUILD FUNCTION AND SETUP BUILD VARIABLES --------
        local reference = false
        local refName = false
        local buildFunction
        local closeToBuilder
        local relative
        local baseTmplList = {}

        -- if we have nothing to build, disband!
        if not cons.BuildStructures then
            WaitTicks(1)
            self:PlatoonDisband()
            return
        end
        if cons.NearUnitCategory then
            self:SetPrioritizedTargetList('support', {ParseEntityCategory(cons.NearUnitCategory)})
            local unitNearBy = self:FindPrioritizedUnit('support', 'Ally', false, self:GetPlatoonPosition(), cons.NearUnitRadius or 50)
            --LOG("ENGINEER BUILD: " .. cons.BuildStructures[1] .." attempt near: ", cons.NearUnitCategory)
            if unitNearBy then
                reference = table.copy(unitNearBy:GetPosition())
                -- get commander home position
                --LOG("ENGINEER BUILD: " .. cons.BuildStructures[1] .." Near unit: ", cons.NearUnitCategory)
                if cons.NearUnitCategory == 'COMMAND' and unitNearBy.CDRHome then
                    reference = unitNearBy.CDRHome
                end
            else
                reference = table.copy(eng:GetPosition())
            end
            relative = false
            buildFunction = AIBuildStructures.AIExecuteBuildStructure
            table.insert(baseTmplList, AIBuildStructures.AIBuildBaseTemplateFromLocation(baseTmpl, reference))
        elseif cons.Wall then
            local pos = aiBrain:PBMGetLocationCoords(cons.LocationType) or cons.Position or self:GetPlatoonPosition()
            local radius = cons.LocationRadius or aiBrain:PBMGetLocationRadius(cons.LocationType) or 100
            relative = false
            reference = AIUtils.GetLocationNeedingWalls(aiBrain, 200, 4, 'STRUCTURE - WALLS', cons.ThreatMin, cons.ThreatMax, cons.ThreatRings)
            table.insert(baseTmplList, 'Blank')
            buildFunction = AIBuildStructures.WallBuilder
        elseif cons.NearBasePatrolPoints then
            relative = false
            reference = AIUtils.GetBasePatrolPoints(aiBrain, cons.Location or 'MAIN', cons.Radius or 100)
            baseTmpl = baseTmplFile['ExpansionBaseTemplates'][factionIndex]
            for k,v in reference do
                table.insert(baseTmplList, AIBuildStructures.AIBuildBaseTemplateFromLocation(baseTmpl, v))
            end
            -- Must use BuildBaseOrdered to start at the marker; otherwise it builds closest to the eng
            buildFunction = AIBuildStructures.AIBuildBaseTemplateOrdered
        elseif cons.FireBase and cons.FireBaseRange then
            --DUNCAN - pulled out and uses alt finder
            reference, refName = AIUtils.AIFindFirebaseLocation(aiBrain, cons.LocationType, cons.FireBaseRange, cons.NearMarkerType,
                                                cons.ThreatMin, cons.ThreatMax, cons.ThreatRings, cons.ThreatType,
                                                cons.MarkerUnitCount, cons.MarkerUnitCategory, cons.MarkerRadius)
            if not reference or not refName then
                self:PlatoonDisband()
                return
            end

        elseif cons.NearMarkerType and cons.ExpansionBase then
            local pos = aiBrain:PBMGetLocationCoords(cons.LocationType) or cons.Position or self:GetPlatoonPosition()
            local radius = cons.LocationRadius or aiBrain:PBMGetLocationRadius(cons.LocationType) or 100

            if cons.NearMarkerType == 'Expansion Area' then
                reference, refName = AIUtils.AIFindExpansionAreaNeedsEngineer(aiBrain, cons.LocationType,
                        (cons.LocationRadius or 100), cons.ThreatMin, cons.ThreatMax, cons.ThreatRings, cons.ThreatType)
                -- didn't find a location to build at
                if not reference or not refName then
                    self:PlatoonDisband()
                    return
                end
            elseif cons.NearMarkerType == 'Naval Area' then
                reference, refName = AIUtils.AIFindNavalAreaNeedsEngineer(aiBrain, cons.LocationType,
                        (cons.LocationRadius or 100), cons.ThreatMin, cons.ThreatMax, cons.ThreatRings, cons.ThreatType)
                -- didn't find a location to build at
                if not reference or not refName then
                    self:PlatoonDisband()
                    return
                end
            else
                --DUNCAN - use my alternative expansion finder on large maps below a certain time
                local mapSizeX, mapSizeZ = GetMapSize()
                if GetGameTimeSeconds() <= 780 and mapSizeX > 512 and mapSizeZ > 512 then
                    reference, refName = AIUtils.AIFindFurthestStartLocationNeedsEngineer(aiBrain, cons.LocationType,
                        (cons.LocationRadius or 100), cons.ThreatMin, cons.ThreatMax, cons.ThreatRings, cons.ThreatType)
                    if not reference or not refName then
                        reference, refName = AIUtils.AIFindStartLocationNeedsEngineer(aiBrain, cons.LocationType,
                            (cons.LocationRadius or 100), cons.ThreatMin, cons.ThreatMax, cons.ThreatRings, cons.ThreatType)
                    end
                else
                    reference, refName = AIUtils.AIFindStartLocationNeedsEngineer(aiBrain, cons.LocationType,
                        (cons.LocationRadius or 100), cons.ThreatMin, cons.ThreatMax, cons.ThreatRings, cons.ThreatType)
                end
                -- didn't find a location to build at
                if not reference or not refName then
                    self:PlatoonDisband()
                    return
                end
            end

            -- If moving far from base, tell the assisting platoons to not go with
            if cons.FireBase or cons.ExpansionBase then
                local guards = eng:GetGuards()
                for k,v in guards do
                    if not v.Dead and v.PlatoonHandle then
                        v.PlatoonHandle:PlatoonDisband()
                    end
                end
            end

            if not cons.BaseTemplate and (cons.NearMarkerType == 'Naval Area' or cons.NearMarkerType == 'Defensive Point' or cons.NearMarkerType == 'Expansion Area') then
                baseTmpl = baseTmplFile['ExpansionBaseTemplates'][factionIndex]
            end
            if cons.ExpansionBase and refName then
                AIBuildStructures.AINewExpansionBase(aiBrain, refName, reference, eng, cons)
            end
            relative = false
            if reference and aiBrain:GetThreatAtPosition(reference , 1, true, 'AntiSurface') > 0 then
                --aiBrain:ExpansionHelp(eng, reference)
            end
            table.insert(baseTmplList, AIBuildStructures.AIBuildBaseTemplateFromLocation(baseTmpl, reference))
            -- Must use BuildBaseOrdered to start at the marker; otherwise it builds closest to the eng
            --buildFunction = AIBuildStructures.AIBuildBaseTemplateOrdered
            buildFunction = AIBuildStructures.AIBuildBaseTemplate
        elseif cons.NearMarkerType and cons.NearMarkerType == 'Defensive Point' then
            baseTmpl = baseTmplFile['ExpansionBaseTemplates'][factionIndex]

            relative = false
            local pos = self:GetPlatoonPosition()
            reference, refName = AIUtils.AIFindDefensivePointNeedsStructure(aiBrain, cons.LocationType, (cons.LocationRadius or 100),
                            cons.MarkerUnitCategory, cons.MarkerRadius, cons.MarkerUnitCount, (cons.ThreatMin or 0), (cons.ThreatMax or 1),
                            (cons.ThreatRings or 1), (cons.ThreatType or 'AntiSurface'))

            table.insert(baseTmplList, AIBuildStructures.AIBuildBaseTemplateFromLocation(baseTmpl, reference))

            buildFunction = AIBuildStructures.AIExecuteBuildStructure
        elseif cons.NearMarkerType and cons.NearMarkerType == 'Naval Defensive Point' then
            baseTmpl = baseTmplFile['ExpansionBaseTemplates'][factionIndex]

            relative = false
            local pos = self:GetPlatoonPosition()
            reference, refName = AIUtils.AIFindNavalDefensivePointNeedsStructure(aiBrain, cons.LocationType, (cons.LocationRadius or 100),
                            cons.MarkerUnitCategory, cons.MarkerRadius, cons.MarkerUnitCount, (cons.ThreatMin or 0), (cons.ThreatMax or 1),
                            (cons.ThreatRings or 1), (cons.ThreatType or 'AntiSurface'))

            table.insert(baseTmplList, AIBuildStructures.AIBuildBaseTemplateFromLocation(baseTmpl, reference))

            buildFunction = AIBuildStructures.AIExecuteBuildStructure
        elseif cons.NearMarkerType and (cons.NearMarkerType == 'Rally Point' or cons.NearMarkerType == 'Protected Experimental Construction') then
            --DUNCAN - add so experimentals build on maps with no markers.
            if not cons.ThreatMin or not cons.ThreatMax or not cons.ThreatRings then
                cons.ThreatMin = -1000000
                cons.ThreatMax = 1000000
                cons.ThreatRings = 0
            end
            relative = false
            local pos = self:GetPlatoonPosition()
            reference, refName = AIUtils.AIGetClosestThreatMarkerLoc(aiBrain, cons.NearMarkerType, pos[1], pos[3],
                                                            cons.ThreatMin, cons.ThreatMax, cons.ThreatRings)
            if not reference then
                reference = pos
            end
            table.insert(baseTmplList, AIBuildStructures.AIBuildBaseTemplateFromLocation(baseTmpl, reference))
            buildFunction = AIBuildStructures.AIExecuteBuildStructure
        elseif cons.NearMarkerType then
            --WARN('*Data weird for builder named - ' .. self.BuilderName)
            if not cons.ThreatMin or not cons.ThreatMax or not cons.ThreatRings then
                cons.ThreatMin = -1000000
                cons.ThreatMax = 1000000
                cons.ThreatRings = 0
            end
            if not cons.BaseTemplate and (cons.NearMarkerType == 'Defensive Point' or cons.NearMarkerType == 'Expansion Area') then
                baseTmpl = baseTmplFile['ExpansionBaseTemplates'][factionIndex]
            end
            relative = false
            local pos = self:GetPlatoonPosition()
            reference, refName = AIUtils.AIGetClosestThreatMarkerLoc(aiBrain, cons.NearMarkerType, pos[1], pos[3],
                                                            cons.ThreatMin, cons.ThreatMax, cons.ThreatRings)
            if cons.ExpansionBase and refName then
                AIBuildStructures.AINewExpansionBase(aiBrain, refName, reference, (cons.ExpansionRadius or 100), cons.ExpansionTypes, nil, cons)
            end
            if reference and aiBrain:GetThreatAtPosition(reference, 1, true) > 0 then
                --aiBrain:ExpansionHelp(eng, reference)
            end
            table.insert(baseTmplList, AIBuildStructures.AIBuildBaseTemplateFromLocation(baseTmpl, reference))
            buildFunction = AIBuildStructures.AIExecuteBuildStructure
        elseif cons.AvoidCategory then
            relative = false
            local pos = aiBrain.BuilderManagers[eng.BuilderManagerData.LocationType].EngineerManager:GetLocationCoords()
            local cat = cons.AdjacencyCategory
            -- convert text categories like 'MOBILE AIR' to 'categories.MOBILE * categories.AIR'
            if type(cat) == 'string' then
                cat = ParseEntityCategory(cat)
            end
            local avoidCat = cons.AvoidCategory
            -- convert text categories like 'MOBILE AIR' to 'categories.MOBILE * categories.AIR'
            if type(avoidCat) == 'string' then
                avoidCat = ParseEntityCategory(avoidCat)
            end
            local radius = (cons.AdjacencyDistance or 50)
            if not pos or not pos then
                WaitTicks(1)
                self:PlatoonDisband()
                return
            end
            reference  = AIUtils.FindUnclutteredArea(aiBrain, cat, pos, radius, cons.maxUnits, cons.maxRadius, avoidCat)
            buildFunction = AIBuildStructures.AIBuildAdjacency
            table.insert(baseTmplList, baseTmpl)
        elseif cons.AdjacencyCategory then
            relative = false
            local pos = aiBrain.BuilderManagers[eng.BuilderManagerData.LocationType].EngineerManager:GetLocationCoords()
            local cat = cons.AdjacencyCategory
            -- convert text categories like 'MOBILE AIR' to 'categories.MOBILE * categories.AIR'
            if type(cat) == 'string' then
                cat = ParseEntityCategory(cat)
            end
            local radius = (cons.AdjacencyDistance or 50)
            local radius = (cons.AdjacencyDistance or 50)
            if not pos or not pos then
                WaitTicks(1)
                self:PlatoonDisband()
                return
            end
            reference  = AIUtils.GetOwnUnitsAroundPoint(aiBrain, cat, pos, radius, cons.ThreatMin,
                                                        cons.ThreatMax, cons.ThreatRings)
            buildFunction = AIBuildStructures.AIBuildAdjacency
            table.insert(baseTmplList, baseTmpl)
        else
            table.insert(baseTmplList, baseTmpl)
            relative = true
            reference = true
            buildFunction = AIBuildStructures.AIExecuteBuildStructure
        end
        if cons.BuildClose then
            closeToBuilder = eng
        end
        if cons.BuildStructures[1] == 'T1Resource' or cons.BuildStructures[1] == 'T2Resource' or cons.BuildStructures[1] == 'T3Resource' then
            relative = true
            closeToBuilder = eng
            local guards = eng:GetGuards()
            for k,v in guards do
                if not v.Dead and v.PlatoonHandle and aiBrain:PlatoonExists(v.PlatoonHandle) then
                    v.PlatoonHandle:PlatoonDisband()
                end
            end
        end

        --LOG("*AI DEBUG: Setting up Callbacks for " .. eng.Sync.id)
        self.SetupEngineerCallbacks(eng)

        -------- BUILD BUILDINGS HERE --------
        for baseNum, baseListData in baseTmplList do
            for k, v in cons.BuildStructures do
                if aiBrain:PlatoonExists(self) then
                    if not eng.Dead then
                        local faction = SUtils.GetEngineerFaction(eng)
                        if aiBrain.CustomUnits[v] and aiBrain.CustomUnits[v][faction] then
                            local replacement = SUtils.GetTemplateReplacement(aiBrain, v, faction, buildingTmpl)
                            if replacement then
                                buildFunction(aiBrain, eng, v, closeToBuilder, relative, replacement, baseListData, reference, cons.NearMarkerType)
                            else
                                buildFunction(aiBrain, eng, v, closeToBuilder, relative, buildingTmpl, baseListData, reference, cons.NearMarkerType)
                            end
                        else
                            buildFunction(aiBrain, eng, v, closeToBuilder, relative, buildingTmpl, baseListData, reference, cons.NearMarkerType)
                        end
                    else
                        if aiBrain:PlatoonExists(self) then
                            WaitTicks(1)
                            self:PlatoonDisband()
                            return
                        end
                    end
                end
            end
        end

        -- wait in case we're still on a base
        if not eng.Dead then
            local count = 0
            while eng:IsUnitState('Attached') and count < 2 do
                WaitSeconds(6)
                count = count + 1
            end
        end

        if not eng:IsUnitState('Building') then
            return self.ProcessBuildCommand(eng, false)
        end
    end,


-- For AI Patch V2. Unpause engineers and set AssistPlatoon to nil
    PlatoonDisband = function(self)
        local aiBrain = self:GetBrain()
        if self.BuilderHandle then
            self.BuilderHandle:RemoveHandle(self)
        end
        for k,v in self:GetPlatoonUnits() do
            v.PlatoonHandle = nil
            v.AssistSet = nil
            v.AssistPlatoon = nil
            v.UnitBeingAssist = nil
            v.UnitBeingBuilt = nil
            if v:IsPaused() then
                v:SetPaused( false )
            end
            if not v.Dead and v.BuilderManagerData then
                if self.CreationTime == GetGameTimeSeconds() and v.BuilderManagerData.EngineerManager then
                    if self.BuilderName then
                        --LOG('*PlatoonDisband: ERROR - Platoon disbanded same tick as created - ' .. self.BuilderName .. ' - Army: ' .. aiBrain:GetArmyIndex() .. ' - Location: ' .. repr(v.BuilderManagerData.LocationType))
                        v.BuilderManagerData.EngineerManager:AssignTimeout(v, self.BuilderName)
                    else
                        --LOG('*PlatoonDisband: ERROR - Platoon disbanded same tick as created - Army: ' .. aiBrain:GetArmyIndex() .. ' - Location: ' .. repr(v.BuilderManagerData.LocationType))
                    end
                    v.BuilderManagerData.EngineerManager:DelayAssign(v)
                elseif v.BuilderManagerData.EngineerManager then
                    v.BuilderManagerData.EngineerManager:TaskFinished(v)
                end
            end
            if not v.Dead then
                IssueStop({v})
                IssueClearCommands({v})
            end
        end
        if self.AIThread then
            self.AIThread:Destroy()
        end
        aiBrain:DisbandPlatoon(self)
    end,


-- For AI Patch V2. Enhancement, new flag for assis: AssistUntilFinished
    ManagerEngineerAssistAI = function(self)
        local aiBrain = self:GetBrain()
        local eng = self:GetPlatoonUnits()[1]
        self:EconAssistBody()
        WaitTicks(10)
        -- do we assist until the building is finished ?
        if self.PlatoonData.Assist.AssistUntilFinished then
            local guardedUnit
            if eng.UnitBeingAssist then
                guardedUnit = eng.UnitBeingAssist
            else 
                guardedUnit = eng:GetGuardedUnit()
            end
            -- loop as long as we are not dead and not idle
            while eng and not eng.Dead and aiBrain:PlatoonExists(self) and not eng:IsIdleState() do
                if not guardedUnit or guardedUnit.Dead or guardedUnit:BeenDestroyed() then
                    break
                end
                -- stop if our target is finished
                if guardedUnit:GetFractionComplete() == 1 and not guardedUnit:IsUnitState('Upgrading') then
                    --LOG('* ManagerEngineerAssistAI: Engineer Builder ['..self.BuilderName..'] - ['..self.PlatoonData.Assist.AssisteeType..'] - Target unit ['..guardedUnit:GetBlueprint().BlueprintId..'] ('..guardedUnit:GetBlueprint().Description..') is finished')
                    break
                end
                -- wait 1.5 seconds until we loop again
                WaitTicks(15)
            end
        else
            WaitSeconds(self.PlatoonData.Assist.Time or 60)
        end
        if not aiBrain:PlatoonExists(self) then
            return
        end
        self.AssistPlatoon = nil
        eng.UnitBeingAssist = nil
        self:Stop()
        self:PlatoonDisband()
    end,

-- For AI Patch V3. Bugfix GetGuards count, cap to 20 assisters per unit to assist.
    EconAssistBody = function(self)
        local aiBrain = self:GetBrain()
        local eng = self:GetPlatoonUnits()[1]
        if not eng or eng:IsUnitState('Building') or eng:IsUnitState('Upgrading') or eng:IsUnitState("Enhancing") then
           return
        end
        local assistData = self.PlatoonData.Assist
        if not assistData.AssistLocation then
            WARN('*AI WARNING: Builder '..repr(self.BuilderName)..' is missing AssistLocation')
            return
        end
        if not assistData.AssisteeType then
            WARN('*AI WARNING: Builder '..repr(self.BuilderName)..' is missing AssisteeType')
            return
        end
        eng.AssistPlatoon = self
        local assistee = false
        local assistRange = assistData.AssistRange or 80
        local platoonPos = self:GetPlatoonPosition()
        local beingBuilt = assistData.BeingBuiltCategories or { 'ALLUNITS' }
        local assisteeCat = assistData.AssisteeCategory or categories.ALLUNITS
        if type(assisteeCat) == 'string' then
            assisteeCat = ParseEntityCategory(assisteeCat)
        end

        -- loop through different categories we are looking for
        for _,catString in beingBuilt do
            -- Track all valid units in the assist list so we can load balance for builders
            local category = ParseEntityCategory(catString)
            local assistList = AIUtils.GetAssistees(aiBrain, assistData.AssistLocation, assistData.AssisteeType, category, assisteeCat)
            if table.getn(assistList) > 0 then
                -- only have one unit in the list; assist it
                local low = false
                local bestUnit = false
                for k,v in assistList do
                    --DUNCAN - check unit is inside assist range 
                    local unitPos = v:GetPosition()
                    local UnitAssist = v.UnitBeingBuilt or v.UnitBeingAssist or v
                    local NumAssist = table.getn(UnitAssist:GetGuards())
                    local dist = VDist2(platoonPos[1], platoonPos[3], unitPos[1], unitPos[3])
                    -- Find the closest unit to assist
                    if assistData.AssistClosestUnit then
                        if (not low or dist < low) and NumAssist < 20 and dist < assistRange then
                            low = dist
                            bestUnit = v
                        end
                    -- Find the unit with the least number of assisters; assist it
                    else
                        if (not low or NumAssist < low) and NumAssist < 20 and dist < assistRange then
                            low = NumAssist
                            bestUnit = v
                        end
                    end
                end
                assistee = bestUnit
                break
            end
        end
        -- assist unit
        if assistee  then
            self:Stop()
            eng.AssistSet = true
            eng.UnitBeingAssist = assistee.UnitBeingBuilt or assistee.UnitBeingAssist or assistee
            --LOG('* EconAssistBody: Assisting now: ['..eng.UnitBeingAssist:GetBlueprint().BlueprintId..'] ('..eng.UnitBeingAssist:GetBlueprint().Description..')')
            IssueGuard({eng}, eng.UnitBeingAssist)
        else
            self.AssistPlatoon = nil
            eng.UnitBeingAssist = nil
            -- stop the platoon from endless assisting
            self:PlatoonDisband()
        end
    end,

-- For AI Patch V2. Bugfix endless assisting
    ManagerEngineerFindUnfinished = function(self)
        local aiBrain = self:GetBrain()
        local eng = self:GetPlatoonUnits()[1]
        local guardedUnit
        self:EconUnfinishedBody()
        WaitTicks(10)
        -- do we assist until the building is finished ?
        if self.PlatoonData.Assist.AssistUntilFinished then
            local guardedUnit
            if eng.UnitBeingAssist then
                guardedUnit = eng.UnitBeingAssist
            else 
                guardedUnit = eng:GetGuardedUnit()
            end
            -- loop as long as we are not dead and not idle
            while eng and not eng.Dead and aiBrain:PlatoonExists(self) and not eng:IsIdleState() do
                if not guardedUnit or guardedUnit.Dead or guardedUnit:BeenDestroyed() then
                    break
                end
                -- stop if our target is finished
                if guardedUnit:GetFractionComplete() == 1 and not guardedUnit:IsUnitState('Upgrading') then
                    --LOG('* ManagerEngineerAssistAI: Engineer Builder ['..self.BuilderName..'] - ['..self.PlatoonData.Assist.AssisteeType..'] - Target unit ['..guardedUnit:GetBlueprint().BlueprintId..'] ('..guardedUnit:GetBlueprint().Description..') is finished')
                    break
                end
                -- wait 1.5 seconds until we loop again
                WaitTicks(15)
            end
        else
            WaitSeconds(self.PlatoonData.Assist.Time or 60)
        end
        if not aiBrain:PlatoonExists(self) then
            return
        end
        self.AssistPlatoon = nil
        eng.UnitBeingAssist = nil
        self:Stop()
        self:PlatoonDisband()
    end,

-- For AI Patch V2. Bugfix eng.UnitBeingBuilt = assistee
    EconUnfinishedBody = function(self)
        local aiBrain = self:GetBrain()
        local eng = self:GetPlatoonUnits()[1]
        if not eng then
            self:PlatoonDisband()
            return
        end
        local assistData = self.PlatoonData.Assist
        local assistee = false

        eng.AssistPlatoon = self

        if not assistData.AssistLocation then
            WARN('*AI WARNING: Disbanding EconUnfinishedBody platoon that does not AssistLocation')
            self:PlatoonDisband()
            return
        end

        local beingBuilt = assistData.BeingBuiltCategories or { 'ALLUNITS' }

        -- loop through different categories we are looking for
        for _,catString in beingBuilt do

            local category = ParseEntityCategory(catString)

            local assistList = SUtils.FindUnfinishedUnits(aiBrain, assistData.AssistLocation, category)

            if assistList then
                assistee = assistList
                break
            end
        end
        -- assist unit
        if assistee then
            self:Stop()
            eng.AssistSet = true
            eng.UnitBeingAssist = assistee.UnitBeingBuilt or assistee.UnitBeingAssist or assistee
            --LOG('* EconUnfinishedBody: Assisting now: ['..eng.UnitBeingBuilt:GetBlueprint().BlueprintId..'] ('..eng.UnitBeingBuilt:GetBlueprint().Description..')')
            IssueGuard({eng}, assistee)
        else
            self.AssistPlatoon = nil
            eng.UnitBeingAssist = nil
            -- stop the platoon from endless assisting
            self:PlatoonDisband()
        end
    end,

-- For AI Patch V3. changed :GetLocationRadius() to .Radius
    RepairAI = function(self)
        local aiBrain = self:GetBrain()
        if not self.PlatoonData or not self.PlatoonData.LocationType then
            self:PlatoonDisband()
            return
        end
        local eng = self:GetPlatoonUnits()[1]
        local engineerManager = aiBrain.BuilderManagers[self.PlatoonData.LocationType].EngineerManager
        local Structures = AIUtils.GetOwnUnitsAroundPoint(aiBrain, categories.STRUCTURE - (categories.TECH1 - categories.FACTORY), engineerManager:GetLocationCoords(), engineerManager:GetLocationRadius())
        for k,v in Structures do
            -- prevent repairing a unit while reclaim is in progress (see ReclaimStructuresAI)
            if not v.Dead and not v.ReclaimInProgress and v:GetHealthPercent() < .8 then
                self:Stop()
                IssueRepair(self:GetPlatoonUnits(), v)
                break
            end
        end
        local count = 0
        repeat
            WaitSeconds(2)
            if not aiBrain:PlatoonExists(self) then
                return
            end
            count = count + 1
            if eng:IsIdleState() then break end
        until count >= 30
        self:PlatoonDisband()
    end,

-- For AI Patch V3. ParseEntityCategory as string and userdata
    ReclaimStructuresAI = function(self)
        self:Stop()
        local aiBrain = self:GetBrain()
        local data = self.PlatoonData
        local radius = aiBrain:PBMGetLocationRadius(data.Location)
        local categories = data.Reclaim
        local counter = 0
        local reclaimcat
        local reclaimables
        local unitPos
        local reclaimunit
        local distance
        local allIdle
        while aiBrain:PlatoonExists(self) do
            unitPos = self:GetPlatoonPosition()
            reclaimunit = false
            distance = false
            for num,cat in categories do
                if type(cat) == 'string' then
                    reclaimcat = ParseEntityCategory(cat)
                else
                    reclaimcat = cat
                end
                reclaimables = aiBrain:GetListOfUnits(reclaimcat, false)
                for k,v in reclaimables do
                    if not v.Dead and (not reclaimunit or VDist3(unitPos, v:GetPosition()) < distance) and unitPos then
                        reclaimunit = v
                        distance = VDist3(unitPos, v:GetPosition())
                    end
                end
                if reclaimunit then break end
            end
            if reclaimunit and not reclaimunit.Dead then
                counter = 0
                IssueReclaim(self:GetPlatoonUnits(), reclaimunit)
                -- Set ReclaimInProgress to prevent repairing (see RepairAI)
                reclaimunit.ReclaimInProgress = true
                repeat
                    WaitSeconds(2)
                    if not aiBrain:PlatoonExists(self) then
                        return
                    end
                    allIdle = true
                    for k,v in self:GetPlatoonUnits() do
                        if not v.Dead and not v:IsIdleState() then
                            allIdle = false
                            break
                        end
                    end
                until allIdle
            elseif not reclaimunit or counter >= 5 then
                self:PlatoonDisband()
                return
            else
                counter = counter + 1
                WaitSeconds(5)
            end
        end
    end,
    
-- For AI Patch V3. change platoon disband and stop. Was stopping ALL factories on disband
    UnitUpgradeAI = function(self)
        local aiBrain = self:GetBrain()
        local platoonUnits = self:GetPlatoonUnits()
        local factionIndex = aiBrain:GetFactionIndex()
        local FactionToIndex  = { UEF = 1, AEON = 2, CYBRAN = 3, SERAPHIM = 4, NOMADS = 5}
        local UnitBeingUpgradeFactionIndex = nil
        local upgradeIssued = false
        self:Stop()
        --LOG('* UnitUpgradeAI: PlatoonName:'..repr(self.BuilderName))
        for k, v in platoonUnits do
            --LOG('* UnitUpgradeAI: Upgrading unit '..v:GetUnitId()..' ('..v.factionCategory..')')
            local upgradeID
            -- Get the factionindex from the unit to get the right update (in case we have captured this unit from another faction)
            UnitBeingUpgradeFactionIndex = FactionToIndex[v.factionCategory] or factionIndex
            --LOG('* UnitUpgradeAI: UnitBeingUpgradeFactionIndex '..UnitBeingUpgradeFactionIndex)
            if self.PlatoonData.OverideUpgradeBlueprint then
                local tempUpgradeID = self.PlatoonData.OverideUpgradeBlueprint[UnitBeingUpgradeFactionIndex]
                if v:CanBuild(tempUpgradeID) then
                    upgradeID = tempUpgradeID
                else
                    -- in case the unit can't upgrade with OverideUpgradeBlueprint, warn the programmer
                    -- this can happen if the AI relcaimed a factory and tries to upgrade to a support factory without having a HQ factory from the reclaimed factory faction.
                    -- in this case we fall back to HQ upgrade template and upgrade to a HQ factory instead of support.
                    -- Output: WARNING: [platoon.lua, line:xxx] *UnitUpgradeAI WARNING: OverideUpgradeBlueprint UnitId:CanBuild(tempUpgradeID) failed!
                    WARN('['..string.gsub(debug.getinfo(1).source, ".*\\(.*.lua)", "%1")..', line:'..debug.getinfo(1).currentline..'] *UnitUpgradeAI WARNING: OverideUpgradeBlueprint ' .. repr(v:GetUnitId()) .. ':CanBuild( '..tempUpgradeID..' ) failed. (Override tree not available, upgrading to default instead.)' )
                end
            end
            if not upgradeID and EntityCategoryContains(categories.MOBILE, v) then
                upgradeID = aiBrain:FindUpgradeBP(v:GetUnitId(), UnitUpgradeTemplates[UnitBeingUpgradeFactionIndex])
                -- if we can't find a UnitUpgradeTemplate for this unit, warn the programmer
                if not upgradeID then
                    -- Output: WARNING: [platoon.lua, line:xxx] *UnitUpgradeAI ERROR: Can\'t find UnitUpgradeTemplate for mobile unit: ABC1234
                    WARN('['..string.gsub(debug.getinfo(1).source, ".*\\(.*.lua)", "%1")..', line:'..debug.getinfo(1).currentline..'] *UnitUpgradeAI ERROR: Can\'t find UnitUpgradeTemplate for mobile unit: ' .. repr(v:GetUnitId()) )
                end
            elseif not upgradeID then
                upgradeID = aiBrain:FindUpgradeBP(v:GetUnitId(), StructureUpgradeTemplates[UnitBeingUpgradeFactionIndex])
                -- if we can't find a StructureUpgradeTemplate for this unit, warn the programmer
                if not upgradeID then
                    -- Output: WARNING: [platoon.lua, line:xxx] *UnitUpgradeAI ERROR: Can\'t find StructureUpgradeTemplate for structure: ABC1234
                    WARN('['..string.gsub(debug.getinfo(1).source, ".*\\(.*.lua)", "%1")..', line:'..debug.getinfo(1).currentline..'] *UnitUpgradeAI ERROR: Can\'t find StructureUpgradeTemplate for structure: ' .. repr(v:GetUnitId()) .. '  faction: ' .. repr(v.factionCategory) )
                end
            end
            if upgradeID and EntityCategoryContains(categories.STRUCTURE, v) and not v:CanBuild(upgradeID) then
                -- in case the unit can't upgrade with upgradeID, warn the programmer
                -- Output: WARNING: [platoon.lua, line:xxx] *UnitUpgradeAI ERROR: UnitId:CanBuild(upgradeID) failed!
                WARN('['..string.gsub(debug.getinfo(1).source, ".*\\(.*.lua)", "%1")..', line:'..debug.getinfo(1).currentline..'] *UnitUpgradeAI ERROR: ' .. repr(v:GetUnitId()) .. ':CanBuild( '..upgradeID..' ) failed!' )
                continue
            end
            if upgradeID then
                upgradeIssued = true
                IssueUpgrade({v}, upgradeID)
                --LOG('-- Upgrading unit '..v:GetUnitId()..' ('..v.factionCategory..') with '..upgradeID)
            end
        end
        if not upgradeIssued then
            self:PlatoonDisband()
            return
        end
        local upgrading = true
        while aiBrain:PlatoonExists(self) and upgrading do
            WaitSeconds(3)
            upgrading = false
            for k, v in platoonUnits do
                if v and not v.Dead then
                    upgrading = true
                end
            end
        end
        if not aiBrain:PlatoonExists(self) then
            return
        end
        WaitTicks(1)
        self:PlatoonDisband()
    end,

-- For AI Patch V2. Bugfix if not eng.AssistSet and not eng.AssistPlatoon then
    ProcessBuildCommand = function(eng, removeLastBuild)
        --DUNCAN - Trying to stop commander leaving projects
        if not eng or eng.Dead or not eng.PlatoonHandle or eng.GoingHome or eng.UnitBeingBuiltBehavior or eng:IsUnitState("Upgrading") or eng:IsUnitState("Enhancing") or eng:IsUnitState("Guarding") then
            if eng then eng.ProcessBuild = nil end
            --LOG('*AI DEBUG: Commander skipping process build.')
            return
        end

        if eng.CDRHome then
            --LOG('*AI DEBUG: Commander starting process build...')
        end

        local aiBrain = eng.PlatoonHandle:GetBrain()
        if not aiBrain or eng.Dead or not eng.EngineerBuildQueue or table.getn(eng.EngineerBuildQueue) == 0 then
            if aiBrain:PlatoonExists(eng.PlatoonHandle) then
                --LOG("*AI DEBUG: Disbanding Engineer Platoon in ProcessBuildCommand top " .. eng.Sync.id)
                --if eng.CDRHome then LOG('*AI DEBUG: Commander process build platoon disband...') end
                if not eng.AssistSet and not eng.AssistPlatoon and not eng.UnitBeingAssist then
                    eng.PlatoonHandle:PlatoonDisband()
                end
            end
            if eng then eng.ProcessBuild = nil end
            return
        end

        -- it wasn't a failed build, so we just finished something
        if removeLastBuild then
            table.remove(eng.EngineerBuildQueue, 1)
        end

        function BuildToNormalLocation(location)
            return {location[1], 0, location[2]}
        end

        function NormalToBuildLocation(location)
            return {location[1], location[3], 0}
        end

        eng.ProcessBuildDone = false
        IssueClearCommands({eng})
        local commandDone = false
        while not eng.Dead and not commandDone and table.getn(eng.EngineerBuildQueue) > 0  do
            local whatToBuild = eng.EngineerBuildQueue[1][1]
            local buildLocation = BuildToNormalLocation(eng.EngineerBuildQueue[1][2])
            local buildRelative = eng.EngineerBuildQueue[1][3]
            -- see if we can move there first
            if AIUtils.EngineerMoveWithSafePath(aiBrain, eng, buildLocation) then
                if not eng or eng.Dead or not eng.PlatoonHandle or not aiBrain:PlatoonExists(eng.PlatoonHandle) then
                    if eng then eng.ProcessBuild = nil end
                    return
                end

                if not eng.NotBuildingThread then
                    eng.NotBuildingThread = eng:ForkThread(eng.PlatoonHandle.WatchForNotBuilding)
                end

                local engpos = eng:GetPosition()
                while not eng.Dead and eng:IsUnitState("Moving") and VDist2(engpos[1], engpos[3], buildLocation[1], buildLocation[3]) > 15 do
                    WaitSeconds(2)
                end

                -- check to see if we need to reclaim or capture...
                if not AIUtils.EngineerTryReclaimCaptureArea(aiBrain, eng, buildLocation) then
                    -- check to see if we can repair
                    if not AIUtils.EngineerTryRepair(aiBrain, eng, whatToBuild, buildLocation) then
                        -- otherwise, go ahead and build the next structure there
                        aiBrain:BuildStructure(eng, whatToBuild, NormalToBuildLocation(buildLocation), buildRelative)
                        if not eng.NotBuildingThread then
                            eng.NotBuildingThread = eng:ForkThread(eng.PlatoonHandle.WatchForNotBuilding)
                        end
                    end
                end
                commandDone = true
            else
                -- we can't move there, so remove it from our build queue
                table.remove(eng.EngineerBuildQueue, 1)
            end
        end

        -- final check for if we should disband
        if not eng or eng.Dead or table.getn(eng.EngineerBuildQueue) <= 0 then
            if eng.PlatoonHandle and aiBrain:PlatoonExists(eng.PlatoonHandle) then
                --LOG("*AI DEBUG: Disbanding Engineer Platoon in ProcessBuildCommand bottom " .. eng.Sync.id)
                eng.PlatoonHandle:PlatoonDisband()
            end
            if eng then eng.ProcessBuild = nil end
            return
        end
        if eng then eng.ProcessBuild = nil end
    end,

-- UVESO's Stuff: ------------------------------------------------------------------------------------

    InterceptorAIUveso = function(self)
        AIAttackUtils.GetMostRestrictiveLayer(self) -- this will set self.MovementLayer to the platoon
        local aiBrain = self:GetBrain()
        -- Search all platoon units and activate Stealth and Cloak (mostly Modded units)
        local platoonUnits = self:GetPlatoonUnits()
        local PlatoonStrength = table.getn(platoonUnits)
        if platoonUnits and PlatoonStrength > 0 then
            for k, v in platoonUnits do
                if not v.Dead then
                    if v:TestToggleCaps('RULEUTC_StealthToggle') then
                        --LOG('* InterceptorAIUveso: Switching RULEUTC_StealthToggle')
                        v:SetScriptBit('RULEUTC_StealthToggle', false)
                    end
                    if v:TestToggleCaps('RULEUTC_CloakToggle') then
                        --LOG('* InterceptorAIUveso: Switching RULEUTC_CloakToggle')
                        v:SetScriptBit('RULEUTC_CloakToggle', false)
                    end
                end
            end
        end
        local PrioritizedTargetList = {}
        if self.PlatoonData.PrioritizedCategories then
            for k,v in self.PlatoonData.PrioritizedCategories do
                table.insert(PrioritizedTargetList, ParseEntityCategory(v))
            end
        end
        self:SetPrioritizedTargetList('Attack', PrioritizedTargetList)
        local target
        local bAggroMove = self.PlatoonData.AggressiveMove
        local path
        local reason
        local maxRadius = self.PlatoonData.SearchRadius or 100
        local PlatoonPos = self:GetPlatoonPosition()
        local LastTargetPos = PlatoonPos
        local basePosition
        if self.MovementLayer == 'Water' then
            -- we could search for the nearest naval base here, but buildposition is almost at the same location
            basePosition = PlatoonPos
        else
            -- land and air units are assigned to mainbase
            basePosition = aiBrain.BuilderManagers['MAIN'].Position
        end
        local GetTargetsFromBase = self.PlatoonData.GetTargetsFromBase
        local GetTargetsFrom = basePosition
        local TargetSearchCategory = self.PlatoonData.TargetSearchCategory or 'ALLUNITS'
        local LastTargetCheck
        local DistanceToBase = 0
        while aiBrain:PlatoonExists(self) do
            if self:IsOpponentAIRunning() then
                PlatoonPos = self:GetPlatoonPosition()
                if not GetTargetsFromBase then
                    GetTargetsFrom = PlatoonPos
                else
                    DistanceToBase = VDist2(PlatoonPos[1] or 0, PlatoonPos[3] or 0, basePosition[1] or 0, basePosition[3] or 0)
                    if DistanceToBase > maxRadius then
                        target = nil
                    end
                end
                -- only get a new target and make a move command if the target is dead
                if not target or target.Dead or target:BeenDestroyed() then
                    UnitWithPath, UnitNoPath, path, reason = AIUtils.AIFindNearestCategoryTargetInRange(aiBrain, self, 'Attack', GetTargetsFrom, maxRadius, PrioritizedTargetList, TargetSearchCategory, false )
                    if UnitWithPath then
                        self:Stop()
                        target = UnitWithPath
                        if self.PlatoonData.IgnorePathing then
                            self:Stop()
                            self:AttackTarget(UnitWithPath)
                        elseif path then
                            self:MovePath(aiBrain, path, bAggroMove, UnitWithPath)
                        -- if we dont have a path, but UnitWithPath is true, then we have no map markers but PathCanTo() found a direct path
                        else
                            self:MoveDirect(aiBrain, bAggroMove, UnitWithPath)
                        end
                        -- We moved to the target, attack it now if its still exists
                        if aiBrain:PlatoonExists(self) and UnitWithPath and not UnitWithPath.Dead and not UnitWithPath:BeenDestroyed() then
                            self:AttackTarget(UnitWithPath)
                        end
                    elseif UnitNoPath then
                        self:Stop()
                        target = UnitNoPath
                        self:Stop()
                        if self.MovementLayer == 'Air' then
                            self:AttackTarget(UnitNoPath)
                        else
                            self:SimpleReturnToBase(basePosition)
                        end
                    else
                        -- we have no target return to main base
                        self:Stop()
                        if self.MovementLayer == 'Air' then
                            if VDist2(PlatoonPos[1] or 0, PlatoonPos[3] or 0, basePosition[1] or 0, basePosition[3] or 0) > 30 then
                                self:MoveToLocation(basePosition, false)
                            else
                                -- we are at home and we don't have a target. Disband!
                                if aiBrain:PlatoonExists(self) then
                                    self:PlatoonDisband()
                                    return
                                end
                            end
                        else
                            self:SimpleReturnToBase(basePosition)
                        end
                    end
                -- targed exists and is not dead
                end
                WaitTicks(1)
                if aiBrain:PlatoonExists(self) and target and not target.Dead then
                    LastTargetPos = target:GetPosition()
                    if VDist2(basePosition[1] or 0, basePosition[3] or 0, LastTargetPos[1] or 0, LastTargetPos[3] or 0) < maxRadius then
                        self:Stop()
                        if self.PlatoonData.IgnorePathing then
                            self:AttackTarget(target)
                        else
                            self:MoveToLocation(LastTargetPos, false)
                        end
                    else
                        target = nil
                    end
                    WaitTicks(40)
                end
            end
            WaitTicks(10)
        end
    end,

    AttackPrioritizedLandTargetsAIUveso = function(self)
        AIAttackUtils.GetMostRestrictiveLayer(self) -- this will set self.MovementLayer to the platoon
        -- Search all platoon units and activate Stealth and Cloak (mostly Modded units)
        local platoonUnits = self:GetPlatoonUnits()
        local PlatoonStrength = table.getn(platoonUnits)
        local ExperimentalInPlatoon = false
        if platoonUnits and PlatoonStrength > 0 then
            for k, v in platoonUnits do
                if not v.Dead then
                    if v:TestToggleCaps('RULEUTC_StealthToggle') then
                        v:SetScriptBit('RULEUTC_StealthToggle', false)
                    end
                    if v:TestToggleCaps('RULEUTC_CloakToggle') then
                        v:SetScriptBit('RULEUTC_CloakToggle', false)
                    end
                end
                if EntityCategoryContains(categories.EXPERIMENTAL, v) then
                    ExperimentalInPlatoon = true
                end
            end
        end
        local PrioritizedTargetList = {}
        if self.PlatoonData.PrioritizedCategories then
            for k,v in self.PlatoonData.PrioritizedCategories do
                table.insert(PrioritizedTargetList, ParseEntityCategory(v))
            end
        end
        -- Set the target list to all platoon units
        self:SetPrioritizedTargetList('Attack', PrioritizedTargetList)
        local aiBrain = self:GetBrain()
        local target
        local bAggroMove = self.PlatoonData.AggressiveMove
        local WantsTransport = self.PlatoonData.RequireTransport
        local maxRadius = self.PlatoonData.SearchRadius or 250
        local TargetSearchCategory = self.PlatoonData.TargetSearchCategory or 'ALLUNITS'
        local PlatoonPos = self:GetPlatoonPosition()
        local LastTargetPos = PlatoonPos
        local DistanceToTarget = 0
        local basePosition = aiBrain.BuilderManagers['MAIN'].Position
        local losttargetnum = 0
        while aiBrain:PlatoonExists(self) do
            if self:IsOpponentAIRunning() then
                PlatoonPos = self:GetPlatoonPosition()
                -- only get a new target and make a move command if the target is dead or after 10 seconds
                if not target or target.Dead then
                    UnitWithPath, UnitNoPath, path, reason = AIUtils.AIFindNearestCategoryTargetInRange(aiBrain, self, 'Attack', PlatoonPos, maxRadius, PrioritizedTargetList, TargetSearchCategory, false )
                    if UnitWithPath then
                        losttargetnum = 0
                        self:Stop()
                        target = UnitWithPath
                        LastTargetPos = table.copy(target:GetPosition())
                        DistanceToTarget = VDist2(PlatoonPos[1] or 0, PlatoonPos[3] or 0, LastTargetPos[1] or 0, LastTargetPos[3] or 0)
                        if DistanceToTarget > 30 then
                            -- if we have a path then use the waypoints
                            if self.PlatoonData.IgnorePathing then
                                self:Stop()
                                self:SetPlatoonFormationOverride('AttackFormation')
                                self:AttackTarget(UnitWithPath)
                            elseif path then
--                                self:MovePath(aiBrain, path, bAggroMove, target)
                                self:MoveToLocationInclTransport(target, LastTargetPos, bAggroMove, WantsTransport, basePosition, ExperimentalInPlatoon)
                            -- if we dont have a path, but UnitWithPath is true, then we have no map markers but PathCanTo() found a direct path
                            else
                                self:MoveDirect(aiBrain, bAggroMove, target)
                            end
                            -- We moved to the target, attack it now if its still exists
                            if aiBrain:PlatoonExists(self) and UnitWithPath and not UnitWithPath.Dead and not UnitWithPath:BeenDestroyed() then
                                self:Stop()
                                self:SetPlatoonFormationOverride('AttackFormation')
                                self:AttackTarget(UnitWithPath)
                            end
                        end
                    elseif UnitNoPath then
                        losttargetnum = 0
                        self:Stop()
                        target = UnitNoPath
                        self:MoveWithTransport(aiBrain, bAggroMove, target, basePosition, ExperimentalInPlatoon)
                        -- We moved to the target, attack it now if its still exists
                        if aiBrain:PlatoonExists(self) and UnitNoPath and not UnitNoPath.Dead and not UnitNoPath:BeenDestroyed() then
                            self:SetPlatoonFormationOverride('AttackFormation')
                            self:AttackTarget(UnitNoPath)
                        end
                    else
                        -- we have no target return to main base
                        losttargetnum = losttargetnum + 1
                        if losttargetnum > 2 then
                            self:Stop()
                            self:SetPlatoonFormationOverride('NoFormation')
                            self:ForceReturnToNearestBaseAIUveso()
                        end
                    end
                else
                    if aiBrain:PlatoonExists(self) and target and not target.Dead and not target:BeenDestroyed() then
                        self:SetPlatoonFormationOverride('AttackFormation')
                        self:AttackTarget(target)
                        WaitSeconds(2)
                    end
                end
            end
            WaitSeconds(1)
        end
    end,

    AttackPrioritizedSeaTargetsAIUveso = function(self)
        AIAttackUtils.GetMostRestrictiveLayer(self) -- this will set self.MovementLayer to the platoon
        -- Search all platoon units and activate Stealth and Cloak (mostly Modded units)
        local platoonUnits = self:GetPlatoonUnits()
        local PlatoonStrength = table.getn(platoonUnits)
        local ExperimentalInPlatoon = false
        if platoonUnits and PlatoonStrength > 0 then
            for k, v in platoonUnits do
                if not v.Dead then
                    if v:TestToggleCaps('RULEUTC_StealthToggle') then
                        v:SetScriptBit('RULEUTC_StealthToggle', false)
                    end
                    if v:TestToggleCaps('RULEUTC_CloakToggle') then
                        v:SetScriptBit('RULEUTC_CloakToggle', false)
                    end
                end
                if EntityCategoryContains(categories.EXPERIMENTAL, v) then
                    ExperimentalInPlatoon = true
                end
            end
        end
        local PrioritizedTargetList = {}
        if self.PlatoonData.PrioritizedCategories then
            for k,v in self.PlatoonData.PrioritizedCategories do
                table.insert(PrioritizedTargetList, ParseEntityCategory(v))
            end
        end
        -- Set the target list to all platoon units
        self:SetPrioritizedTargetList('Attack', PrioritizedTargetList)
        local aiBrain = self:GetBrain()
        local target
        local bAggroMove = self.PlatoonData.AggressiveMove
        local maxRadius = self.PlatoonData.SearchRadius or 250
        local TargetSearchCategory = self.PlatoonData.TargetSearchCategory or 'ALLUNITS'
        local PlatoonPos = self:GetPlatoonPosition()
        local LastTargetPos = PlatoonPos
        local DistanceToTarget = 0
        local basePosition = PlatoonPos   -- Platoons will be created near a base, so we can return to this position if we don't have targets.
        local losttargetnum = 0
        while aiBrain:PlatoonExists(self) do
            if self:IsOpponentAIRunning() then
                PlatoonPos = self:GetPlatoonPosition()
                -- only get a new target and make a move command if the target is dead or after 10 seconds
                if not target or target.Dead then
                    UnitWithPath, UnitNoPath, path, reason = AIUtils.AIFindNearestCategoryTargetInRange(aiBrain, self, 'Attack', PlatoonPos, maxRadius, PrioritizedTargetList, TargetSearchCategory, false )
                    if UnitWithPath then
                        losttargetnum = 0
                        self:Stop()
                        target = UnitWithPath
                        LastTargetPos = table.copy(target:GetPosition())
                        DistanceToTarget = VDist2(PlatoonPos[1] or 0, PlatoonPos[3] or 0, LastTargetPos[1] or 0, LastTargetPos[3] or 0)
                        if DistanceToTarget > 30 then
                            -- if we have a path then use the waypoints
                            if self.PlatoonData.IgnorePathing then
                                self:Stop()
                                self:AttackTarget(UnitWithPath)
                            elseif path then
                                self:MovePath(aiBrain, path, bAggroMove, target)
                            -- if we dont have a path, but UnitWithPath is true, then we have no map markers but PathCanTo() found a direct path
                            else
                                self:MoveDirect(aiBrain, bAggroMove, target)
                            end
                            -- We moved to the target, attack it now if its still exists
                            if aiBrain:PlatoonExists(self) and UnitWithPath and not UnitWithPath.Dead and not UnitWithPath:BeenDestroyed() then
                                self:Stop()
                                self:AttackTarget(UnitWithPath)
                            end
                        end
                    else
                        -- we have no target return to main base
                        losttargetnum = losttargetnum + 1
                        if losttargetnum > 2 then
                            self:Stop()
                            self:ForceReturnToNavalBaseAIUveso(aiBrain, basePosition)
                        end
                    end
                else
                    if aiBrain:PlatoonExists(self) and target and not target.Dead and not target:BeenDestroyed() then
                        self:AttackTarget(target)
                        WaitSeconds(2)
                    end
                end
            end
            WaitSeconds(1)
        end
    end,
    
    CommanderAIUveso = function(self)
        --LOG('* CommanderAIUveso: START '..self.BuilderName)
        AIAttackUtils.GetMostRestrictiveLayer(self) -- this will set self.MovementLayer to the platoon
        local aiBrain = self:GetBrain()
        local cdr = self:GetPlatoonUnits()[1]
        if not cdr then
            WARN('* CommanderAIUveso: Platoon formed but Commander unit not found!')
            self:PlatoonDisband()
            return
        end
        cdr.HealthOLD = 100
        cdr.CDRHome = aiBrain.BuilderManagers['MAIN'].Position
        -- Search all platoon units and activate Stealth and Cloak (mostly Modded units)
        local PrioritizedTargetList = {}
        if self.PlatoonData.PrioritizedCategories then
            for k,v in self.PlatoonData.PrioritizedCategories do
                table.insert(PrioritizedTargetList, ParseEntityCategory(v))
            end
        end
        self:SetPrioritizedTargetList('Attack', PrioritizedTargetList)
        local UnitWithPath, DistanceToTarget
        local PlatoonPos = self:GetPlatoonPosition()
        -- land and air units are assigned to mainbase
        local GetTargetsFromBase = self.PlatoonData.GetTargetsFromBase
        local GetTargetsFrom = cdr.CDRHome
        local TargetSearchCategory = self.PlatoonData.TargetSearchCategory or 'ALLUNITS'
        local LastTargetCheck
        local DistanceToBase = 0
        local UnitsInBasePanicZone
        local ReturnToBaseAfterGameTime = self.PlatoonData.ReturnToBaseAfterGameTime or false
        local DoNotLeavePlatoonUnderHealth = self.PlatoonData.DoNotLeavePlatoonUnderHealth or 30
        local maxRadius
        local SearchRadius = self.PlatoonData.SearchRadius or 250
        while aiBrain:PlatoonExists(self) do
            if cdr.Dead then break end
            cdr.position = self:GetPlatoonPosition()
            -- leave the loop and disband this platton in time
            if ReturnToBaseAfterGameTime and ReturnToBaseAfterGameTime < GetGameTimeSeconds()/60 then
                --LOG('* CommanderAIUveso: ReturnToBaseAfterGameTime:'..ReturnToBaseAfterGameTime..' >= '..GetGameTimeSeconds()/60)
                UUtils.CDRParkingHome(self,cdr)
                break
            end
            -- the maximum radis that the ACU can be away from base
            maxRadius = (UUtils.ComHealth(cdr)-50)*5 -- If the comanders health is 100% then we have a maxtange of ~250 = (100-50)*5
            if maxRadius > SearchRadius then
                maxRadius = SearchRadius
            end
            UnitsInBasePanicZone = aiBrain:GetUnitsAroundPoint( TargetSearchCategory, cdr.CDRHome, maxRadius, 'Enemy')
            -- get the position of this platoon (ACU)
            if not GetTargetsFromBase then
                -- we don't get out targets relativ to base position. Use the ACU position
                GetTargetsFrom = cdr.position
            end
            ----------------------------------------------
            --- This is the start of the main ACU loop ---
            ----------------------------------------------
            if aiBrain:GetEconomyStoredRatio('ENERGY') > 0.95 and UUtils.ComHealth(cdr) < 100 then
                cdr:SetAutoOvercharge(true)
            else
                cdr:SetAutoOvercharge(false)
            end            
            
            
            -- check if we are further away from base then the closest enemy
            if UUtils.CDRRunHomeEnemyNearBase(self,cdr,UnitsInBasePanicZone) then
                UnitWithPath = false
            -- check if we get actual damage, then move home
            elseif UUtils.CDRRunHomeAtDamage(self,cdr) then
                UnitWithPath = false
            -- check how much % health we have and go closer to our base
            elseif UUtils.CDRRunHomeHealthRange(self,cdr,maxRadius) then
                UnitWithPath = false
            -- can we upgrade ?
            elseif self:BuildACUEnhancememnts(cdr) then
                -- Do nothing if BuildACUEnhancememnts is true.
            -- only get a new target and make a move command if the target is dead
            else
                -- ToDo: scann for enemy COM and change target if needed
                UnitWithPath, _, _, _ = AIUtils.AIFindNearestCategoryTargetInRangeCDR(aiBrain, GetTargetsFrom, maxRadius, PrioritizedTargetList, TargetSearchCategory, false)
                -- if we have a target, move to the target and attack
                if UnitWithPath then
                    if aiBrain:PlatoonExists(self) and UnitWithPath and not UnitWithPath.Dead and not UnitWithPath:BeenDestroyed() then
                        self:Stop()
                        self:AttackTarget(UnitWithPath)
                        WaitTicks(1)
                        local cdrNewPos = {}
                        local targetPos = UnitWithPath:GetPosition()
                        cdrNewPos[1] = targetPos[1] + Random(-3, 3)
                        cdrNewPos[2] = targetPos[2]
                        cdrNewPos[3] = targetPos[3] + Random(-3, 3)
                        self:MoveToLocation(cdrNewPos, false)
                    end
                -- if we have no target, move to base. If we are at base, dance. (random moves)
                elseif UUtils.CDRForceRunHome(self,cdr) then
                    --LOG('* CommanderAIUveso: CDRForceRunHome true. we are running home')
                -- we are at home, dance if we have nothing to do.
                else
                    --LOG('* CommanderAIUveso:We are at home and dancing')
                end
            end
            --DrawCircle(cdr.CDRHome, maxRadius, '00FFFF')
            WaitTicks(10)
            --------------------------------------------
            --- This is the end of the main ACU loop ---
            --------------------------------------------
        end
        --LOG('* CommanderAIUveso: END '..self.BuilderName)
        self:PlatoonDisband()
    end,
    
    BuildACUEnhancememnts = function(platoon,cdr)
        if VDist2(cdr.position[1], cdr.position[3], cdr.CDRHome[1], cdr.CDRHome[3]) > 50 then
            --LOG('* CommanderAIUveso: BuildACUEnhancememnts: ACU outside upgrade range')
            return false
        end
        local EnhancementsByUnitID = {
            -- UEF
            ['uel0001'] = {'HeavyAntiMatterCannon', 'DamageStabilization', 'Shield', 'ShieldGeneratorField'},
            -- Aeon
            ['ual0001'] = {'HeatSink', 'CrysalisBeam', 'Shield', 'ShieldHeavy'},
            -- Cybram
            ['url0001'] = {'CoolingUpgrade', 'StealthGenerator', 'MicrowaveLaserGenerator', 'CloakingGenerator'},
            -- Seraphim
            ['xsl0001'] = {'RateOfFire', 'DamageStabilization', 'BlastAttack', 'DamageStabilizationAdvanced'},
            -- Nomads
            ['inu0001'] = {'GunUpgrade', 'MovementSpeedIncrease', 'RapidRepair', 'DoubleGuns', 'PowerArmor'},

            -- UEF - Black Ops ACU
            ['eel0001'] = {'GatlingEnergyCannon', 'CombatEngineering', 'ShieldBattery', 'AutomaticBarrelStabalizers', 'AssaultEngineering', 'ImprovedShieldBattery', 'EnhancedPowerSubsystems', 'ApocalypticEngineering', 'AdvancedShieldBattery'},
            -- Aeon
            ['eal0001'] = {'PhasonBeamCannon', 'CombatEngineering', 'ShieldBattery', 'DualChannelBooster', 'AssaultEngineering', 'ImprovedShieldBattery', 'EnergizedMolecularInducer', 'ApocalypticEngineering', 'AdvancedShieldBattery'},
            -- Cybram
            ['erl0001'] = {'EMPArray', 'CombatEngineering', 'ArmorPlating', 'AdjustedCrystalMatrix', 'AssaultEngineering', 'StructuralIntegrityFields', 'EnhancedLaserEmitters', 'ApocalypticEngineering', 'CompositeMaterials'},
            -- Seraphim
            ['esl0001'] = {'PlasmaGatlingCannon', 'CombatEngineering', 'LambdaFieldEmitters', 'PhasedEnergyFields', 'AssaultEngineering', 'EnhancedLambdaEmitters', 'SecondaryPowerFeeds', 'ApocalypticEngineering', 'ControlledQuantumRuptures'},
            
            
        }
        local CRDBlueprint = cdr:GetBlueprint()
        --LOG('BlueprintId '..repr(CRDBlueprint.BlueprintId))
        local ACUUpgradeList = EnhancementsByUnitID[CRDBlueprint.BlueprintId]
        --LOG('ACUUpgradeList '..repr(ACUUpgradeList))
        local NextEnhancement = false
        local HaveEcoForEnhancement = false
        for _,enhancement in ACUUpgradeList or {} do
            local wantedEnhancementBP = CRDBlueprint.Enhancements[enhancement]
            --LOG('wantedEnhancementBP '..repr(wantedEnhancementBP))
            if cdr:HasEnhancement(enhancement) then
                NextEnhancement = false
                --LOG('* CommanderAIUveso: BuildACUEnhancememnts: Enhancement is already installed: '..enhancement)
            elseif platoon:EcoGoodForUpgrade(cdr, wantedEnhancementBP) then
                --LOG('* CommanderAIUveso: BuildACUEnhancememnts: Eco is good for '..enhancement)
                if not NextEnhancement then
                    NextEnhancement = enhancement
                    HaveEcoForEnhancement = true
                    --LOG('* CommanderAIUveso: *** Set as Enhancememnt: '..NextEnhancement)
                end
            else
                --LOG('* CommanderAIUveso: BuildACUEnhancememnts: Eco is bad for '..enhancement)
                if not NextEnhancement then
                    NextEnhancement = enhancement
                    HaveEcoForEnhancement = false
                    -- if we don't have the eco for this ugrade, stop the search
                    --LOG('* CommanderAIUveso: canceled search. no eco available')
                    break
                end
            end
        end
        if NextEnhancement and HaveEcoForEnhancement then
            --LOG('* CommanderAIUveso: BuildACUEnhancememnts Building '..NextEnhancement)
            if platoon:BuildEnhancememnt(cdr, NextEnhancement) then
                --LOG('* CommanderAIUveso: BuildACUEnhancememnts returned true'..NextEnhancement)
                return true
            else
                --LOG('* CommanderAIUveso: BuildACUEnhancememnts returned false'..NextEnhancement)
                return false
            end
        end
        return false
    end,
    
    EcoGoodForUpgrade = function(platoon,cdr,enhancement)
        local aiBrain = platoon:GetBrain()
        local BuildRate = cdr:GetBuildRate()
        --LOG('cdr:GetBuildRate() '..BuildRate..'')
        local drainMass = (BuildRate / enhancement.BuildTime) * enhancement.BuildCostMass
        local drainEnergy = (BuildRate / enhancement.BuildTime) * enhancement.BuildCostEnergy
        --LOG('drain: m'..drainMass..'  e'..drainEnergy..'')
        --LOG('Pump: m'..math.floor(aiBrain:GetEconomyTrend('MASS')*10)..'  e'..math.floor(aiBrain:GetEconomyTrend('ENERGY')*10)..'')
        if aiBrain.HasParagon then
            return true
        elseif aiBrain:GetEconomyTrend('MASS')*10 >= drainMass and aiBrain:GetEconomyTrend('ENERGY')*10 >= drainEnergy
        and aiBrain:GetEconomyStoredRatio('MASS') > 0.05 and aiBrain:GetEconomyStoredRatio('ENERGY') > 0.95 then
            return true
        end
        return false
    end,
    
    BuildEnhancememnt = function(platoon,cdr,enhancement)
        --LOG('* CommanderAIUveso: BuildEnhancememnt '..enhancement)
        local aiBrain = platoon:GetBrain()

        IssueStop({cdr})
        IssueClearCommands({cdr})
        
        if not cdr:HasEnhancement(enhancement) then
            local order = { TaskName = "EnhanceTask", Enhancement = enhancement }
            --LOG('* CommanderAIUveso: BuildEnhancememnt: '..platoon:GetBrain().Nickname..' IssueScript: '..enhancement)
            IssueScript({cdr}, order)
        end
        while not cdr.Dead and not cdr:HasEnhancement(enhancement) do
            if UUtils.ComHealth(cdr) < 60 then
                --LOG('* CommanderAIUveso: BuildEnhancememnt: '..platoon:GetBrain().Nickname..' Emergency!!! low health, canceling Enhancement '..enhancement)
                IssueStop({cdr})
                IssueClearCommands({cdr})
                return false
            end
            WaitTicks(10)
        end
        --LOG('* CommanderAIUveso: BuildEnhancememnt: '..platoon:GetBrain().Nickname..' Upgrade finished '..enhancement)
        return true
    end,

    MoveWithTransport = function(self, aiBrain, bAggroMove, target, basePosition, ExperimentalInPlatoon)
        local TargetPosition = table.copy(target:GetPosition())
        local usedTransports = false
        self:SetPlatoonFormationOverride('NoFormation')
        --LOG('* MoveWithTransport: CanPathTo() failed for '..repr(TargetPosition)..' forcing SendPlatoonWithTransportsNoCheck.')
        if not ExperimentalInPlatoon and aiBrain:PlatoonExists(self) then
            usedTransports = AIAttackUtils.SendPlatoonWithTransportsNoCheck(aiBrain, self, TargetPosition, true, false)
        end
        if not usedTransports then
            --LOG('* MoveWithTransport: SendPlatoonWithTransportsNoCheck failed.')
            local PlatoonPos = self:GetPlatoonPosition() or TargetPosition
            local DistanceToTarget = VDist2(PlatoonPos[1] or 0, PlatoonPos[3] or 0, TargetPosition[1] or 0, TargetPosition[3] or 0)
            local DistanceToBase = VDist2(PlatoonPos[1] or 0, PlatoonPos[3] or 0, basePosition[1] or 0, basePosition[3] or 0)
            if DistanceToBase < DistanceToTarget or DistanceToTarget > 50 then
                --LOG('* MoveWithTransport: base is nearer then distance to target or distance to target over 50. Return To base')
                self:SimpleReturnToBase(basePosition)
            else
                --LOG('* MoveWithTransport: Direct move to Target')
                if bAggroMove then
                    self:AggressiveMoveToLocation(TargetPosition)
                else
                    self:MoveToLocation(TargetPosition, false)
                end
            end
        else
            --LOG('* MoveWithTransport: We got a transport!!')
        end
    end,

    MoveDirect = function(self, aiBrain, bAggroMove, target)
        local TargetPosition = table.copy(target:GetPosition())
        local PlatoonPosition
        local Lastdist
        local dist
        local Stuck = 0
        self:SetPlatoonFormationOverride('NoFormation')
        if bAggroMove then
            self:AggressiveMoveToLocation(TargetPosition)
        else
            self:MoveToLocation(TargetPosition, false)
        end
        while aiBrain:PlatoonExists(self) do
            PlatoonPosition = self:GetPlatoonPosition() or TargetPosition
            dist = VDist2( TargetPosition[1], TargetPosition[3], PlatoonPosition[1], PlatoonPosition[3] )
            --LOG('* MoveDirect: dist to next Waypoint: '..dist)
            if dist < 20 then
                return
            end
            -- Do we move ?
            if Lastdist ~= dist then
                Stuck = 0
                Lastdist = dist
            -- No, we are not moving, wait 100 ticks then break and use the next weaypoint
            else
                Stuck = Stuck + 1
                if Stuck > 20 then
                    --LOG('* MoveDirect: Stucked while moving to target. Stuck='..Stuck)
                    self:Stop()
                    return
                end
            end
            -- If we lose our target, stop moving to it.
            if not target or target.Dead then
                --LOG('* MoveDirect: Lost target while moving to target. ')
                return
            end
            WaitTicks(10)
        end
    end,

    MovePath = function(self, aiBrain, path, bAggroMove, target)
        self:SetPlatoonFormationOverride('NoFormation')
        for i=1, table.getn(path) do
            local PlatoonPosition
            local Lastdist
            local dist
            local Stuck = 0
            --LOG('* MovePath: moving to destination. i: '..i..' coords '..repr(path[i]))
            if bAggroMove then
                self:AggressiveMoveToLocation(path[i])
            else
                self:MoveToLocation(path[i], false)
            end
            while aiBrain:PlatoonExists(self) do
                PlatoonPosition = self:GetPlatoonPosition() or path[i]
                dist = VDist2( path[i][1], path[i][3], PlatoonPosition[1], PlatoonPosition[3] )
                --LOG('* MovePath: dist to next Waypoint: '..dist)
                -- are we closer then 20 units from the next marker ? Then break and move to the next marker
                if dist < 20 then
                    -- If we don't stop the movement here, then we have heavy traffic on this Map marker with blocking units
                    self:Stop()
                    break
                end
                -- Do we move ?
                if Lastdist ~= dist then
                    Stuck = 0
                    Lastdist = dist
                -- No, we are not moving, wait 20 ticks then break and use the next weaypoint
                else
                    Stuck = Stuck + 1
                    if Stuck > 20 then
                        --LOG('* MovePath: Stucked while moving to Waypoint. Stuck='..Stuck..' - '..repr(path[i]))
                        self:Stop()
                        break -- break the while aiBrain:PlatoonExists(self) do loop and move to the next waypoint
                    end
                end
                -- If we lose our target, stop moving to it.
                if not target or target.Dead then
                    --LOG('* MovePath: Lost target while moving to Waypoint. '..repr(path[i]))
                    return
                end
                WaitTicks(10)
            end
        end
    end,

    MoveToLocationInclTransport = function(self, target, TargetPosition, bAggroMove, WantsTransport, basePosition, ExperimentalInPlatoon)
        self:SetPlatoonFormationOverride('NoFormation')
        if not TargetPosition then
            TargetPosition = table.copy(target:GetPosition())
        end
        local aiBrain = self:GetBrain()
        -- this will be true if we got our units transported to the destination
        local usedTransports = false
        local TransportNotNeeded, bestGoalPos
        -- check, if we can reach the destination without a transport
        local unit = AIAttackUtils.GetMostRestrictiveLayer(self) -- this will set self.MovementLayer to the platoon
        local path, reason = AIAttackUtils.PlatoonGenerateSafePathTo(aiBrain, self.MovementLayer or 'Land' , self:GetPlatoonPosition(), TargetPosition, 1000, 512)
        if not aiBrain:PlatoonExists(self) then
            return
        end
        -- use a transporter if we don't have a path, or if we want a transport
        if not ExperimentalInPlatoon and ((not path and reason ~= 'NoGraph') or WantsTransport)  then
            --LOG('* MoveToLocationInclTransport: SendPlatoonWithTransportsNoCheck')
            usedTransports = AIAttackUtils.SendPlatoonWithTransportsNoCheck(aiBrain, self, TargetPosition, true, false)
        end
        -- if we don't got a transport, try to reach the destination by path or directly
        if not usedTransports then
            -- clear commands, so we don't get stuck if we have an unreachable destination
            IssueClearCommands(self:GetPlatoonUnits())
            if path then
                --LOG('* MoveToLocationInclTransport: No transport used, and we dont need it.')
                if table.getn(path) > 1 then
                    --LOG('* MoveToLocationInclTransport: table.getn(path): '..table.getn(path))
                end
                for i=1, table.getn(path) do
                    --LOG('* MoveToLocationInclTransport: moving to destination. i: '..i..' coords '..repr(path[i]))
                    if bAggroMove then
                        self:AggressiveMoveToLocation(path[i])
                    else
                        self:MoveToLocation(path[i], false)
                    end
                    local PlatoonPosition
                    local Lastdist
                    local dist
                    local Stuck = 0
                    while aiBrain:PlatoonExists(self) do
                        PlatoonPosition = self:GetPlatoonPosition() or nil
                        if not PlatoonPosition then break end
                        dist = VDist2( path[i][1], path[i][3], PlatoonPosition[1], PlatoonPosition[3] )
                        --LOG('* MoveToLocationInclTransport: dist to next Waypoint: '..dist)
                        -- are we closer then 20 units from the next marker ? Then break and move to the next marker
                        if dist < 20 then
                            -- If we don't stop the movement here, then we have heavy traffic on this Map marker with blocking units
                            self:Stop()
                            break
                        end
                        -- Do we move ?
                        if Lastdist ~= dist then
                            Stuck = 0
                            Lastdist = dist
                        -- No, we are not moving, wait 100 ticks then break and use the next weaypoint
                        else
                            Stuck = Stuck + 1
                            if Stuck > 20 then
                                --LOG('* MoveToLocationInclTransport: Stucked while moving to Waypoint. Stuck='..Stuck..' - '..repr(path[i]))
                                self:Stop()
                                break -- break the while aiBrain:PlatoonExists(self) do loop and move to the next waypoint
                            end
                        end
                        -- If we lose our target, stop moving to it.
                        if not target then
                            --LOG('* MoveToLocationInclTransport: Lost target while moving to Waypoint. '..repr(path[i]))
                            self:Stop()
                            return
                        end
                        WaitTicks(10)
                    end
                end
            else
                --LOG('* MoveToLocationInclTransport: No transport used, and we have no Graph to reach the destination. Checking CanPathTo()')
                if reason == 'NoGraph' then
                    local success, bestGoalPos = AIAttackUtils.CheckPlatoonPathingEx(self, TargetPosition)
                    if success then
                        --LOG('* MoveToLocationInclTransport: No transport used, found a way with CanPathTo(). moving to destination')
                        if bAggroMove then
                            self:AggressiveMoveToLocation(bestGoalPos)
                        else
                            self:MoveToLocation(bestGoalPos, false)
                        end
                        local PlatoonPosition
                        local Lastdist
                        local dist
                        local Stuck = 0
                        while aiBrain:PlatoonExists(self) do
                            PlatoonPosition = self:GetPlatoonPosition() or nil
                            if not PlatoonPosition then continue end
                            dist = VDist2( bestGoalPos[1], bestGoalPos[3], PlatoonPosition[1], PlatoonPosition[3] )
                            if dist < 20 then
                                break
                            end
                            -- Do we move ?
                            if Lastdist ~= dist then
                                Stuck = 0
                                Lastdist = dist
                            -- No, we are not moving, wait 100 ticks then break and use the next weaypoint
                            else
                                Stuck = Stuck + 1
                                if Stuck > 20 then
                                    --LOG('* MoveToLocationInclTransport: Stucked while moving to target. Stuck='..Stuck)
                                    self:Stop()
                                    break -- break the while aiBrain:PlatoonExists(self) do loop and move to the next waypoint
                                end
                            end
                            -- If we lose our target, stop moving to it.
                            if not target then
                                --LOG('* MoveToLocationInclTransport: Lost target while moving to target. ')
                                self:Stop()
                                return
                            end
                            WaitTicks(10)
                        end
                    else
                        --LOG('* MoveToLocationInclTransport: CanPathTo() failed for '..repr(TargetPosition)..' forcing SendPlatoonWithTransportsNoCheck.')
                        if not ExperimentalInPlatoon then
                            usedTransports = AIAttackUtils.SendPlatoonWithTransportsNoCheck(aiBrain, self, TargetPosition, true, false)
                        end
                        if not usedTransports then
                            --LOG('* MoveToLocationInclTransport: CanPathTo() and SendPlatoonWithTransportsNoCheck failed. SimpleReturnToBase!')
                            local PlatoonPos = self:GetPlatoonPosition()
                            local DistanceToTarget = VDist2(PlatoonPos[1] or 0, PlatoonPos[3] or 0, TargetPosition[1] or 0, TargetPosition[3] or 0)
                            local DistanceToBase = VDist2(PlatoonPos[1] or 0, PlatoonPos[3] or 0, basePosition[1] or 0, basePosition[3] or 0)
                            if DistanceToBase < DistanceToTarget and DistanceToTarget > 50 then
                                --LOG('* MoveToLocationInclTransport: base is nearer then distance to target and distance to target over 50. Return To base')
                                self:SimpleReturnToBase(basePosition)
                            else
                                --LOG('* MoveToLocationInclTransport: Direct move to Target')
                                if bAggroMove then
                                    self:AggressiveMoveToLocation(TargetPosition)
                                else
                                    self:MoveToLocation(TargetPosition, false)
                                end
                            end
                        else
                            --LOG('* MoveToLocationInclTransport: CanPathTo() failed BUT we got an transport!!')
                        end

                    end
                else
                    --LOG('* MoveToLocationInclTransport: We have no path but there is a Graph with markers. So why we don\'t get a path ??? (Island or threat too high?) - reason: '..repr(reason))
                end
            end
        else
            --LOG('* MoveToLocationInclTransport: TRANSPORTED.')
        end
    end,

    TransferAIUveso = function(self)
        local aiBrain = self:GetBrain()
        if not aiBrain.BuilderManagers[self.PlatoonData.MoveToLocationType] then
            --LOG('* TransferAIUveso: Location ('..self.PlatoonData.MoveToLocationType..') has no BuilderManager!')
            self:PlatoonDisband()
            return
        end
        local eng = self:GetPlatoonUnits()[1]
        if eng and not eng.Dead and eng.BuilderManagerData.EngineerManager then
            --LOG('* TransferAIUveso: '..repr(self.BuilderName))
            eng.BuilderManagerData.EngineerManager:RemoveUnit(eng)
            --LOG('* TransferAIUveso: AddUnit units to - BuilderManagers: '..self.PlatoonData.MoveToLocationType..' - ' .. aiBrain.BuilderManagers[self.PlatoonData.MoveToLocationType].EngineerManager:GetNumCategoryUnits('Engineers', categories.ALLUNITS) )
            aiBrain.BuilderManagers[self.PlatoonData.MoveToLocationType].EngineerManager:AddUnit(eng, true)
            -- Move the unit to the desired base after transfering BuilderManagers to the new LocationType
            local basePosition = aiBrain.BuilderManagers[self.PlatoonData.MoveToLocationType].Position
            --LOG('* TransferAIUveso: Moving transfer-units to - ' .. self.PlatoonData.MoveToLocationType)
            self:SimpleReturnToBase(basePosition)
        end
        if aiBrain:PlatoonExists(self) then
            self:PlatoonDisband()
        end
    end,

    ReclaimAIUveso = function(self)
        local aiBrain = self:GetBrain()
        local platoonUnits = self:GetPlatoonUnits()
        local eng
        for k, v in platoonUnits do
            if not v.Dead and EntityCategoryContains(categories.MOBILE * categories.ENGINEER, v) then
                eng = v
                break
            end
        end
        UUtils.ReclaimAIThread(self,eng,aiBrain)
        self:PlatoonDisband()
    end,

    FinisherAI = function(self)
        local aiBrain = self:GetBrain()
        -- Only use this with AI-Uveso
        if not self.PlatoonData or not self.PlatoonData.LocationType then
            self:PlatoonDisband()
            return
        end
        local eng = self:GetPlatoonUnits()[1]
        local engineerManager = aiBrain.BuilderManagers[self.PlatoonData.LocationType].EngineerManager
        if not engineerManager then
            self:PlatoonDisband()
            return
        end
        local unfinishedUnits = aiBrain:GetUnitsAroundPoint(categories.STRUCTURE + categories.EXPERIMENTAL, engineerManager:GetLocationCoords(), engineerManager.Radius, 'Ally')
        for k,v in unfinishedUnits do
            local FractionComplete = v:GetFractionComplete()
            if FractionComplete < 1 and table.getn(v:GetGuards()) < 1 then
                self:Stop()
                IssueRepair(self:GetPlatoonUnits(), v)
                break
            end
        end
        local count = 0
        repeat
            WaitSeconds(2)
            if not aiBrain:PlatoonExists(self) then
                return
            end
            count = count + 1
            if eng:IsIdleState() then break end
        until count >= 30
        self:PlatoonDisband()
    end,

    TMLAIUveso = function(self)
        local aiBrain = self:GetBrain()
        local platoonUnits = self:GetPlatoonUnits()
        local TML
        for k, v in platoonUnits do
            if not v.Dead and EntityCategoryContains(categories.STRUCTURE * categories.TACTICALMISSILEPLATFORM * categories.TECH2, v) then
                TML = v
                break
            end
        end
        UUtils.TMLAIThread(self,TML,aiBrain)
        self:PlatoonDisband()
    end,

    PlatoonMerger = function(self)
        --LOG('* PlatoonMerger: called from Builder: '..(self.BuilderName or 'Unknown'))
        local aiBrain = self:GetBrain()
        local PlatoonPlan = self.PlatoonData.AIPlan
        --LOG('* PlatoonMerger: AIPlan: '..(PlatoonPlan or 'Unknown'))
        if not PlatoonPlan then
            return
        end
        -- Get all units from the platoon
        local platoonUnits = self:GetPlatoonUnits()
        -- check if we have already a Platoon for MassExtractor Upgrades
        local AlreadyMergedPlatoon
        PlatoonList = aiBrain:GetPlatoonsList()
        for _,Platoon in PlatoonList do
            if Platoon:GetPlan() == PlatoonPlan then
                --LOG('* PlatoonMerger: Found Platton with plan '..PlatoonPlan)
                AlreadyMergedPlatoon = Platoon
                break
            end
            --LOG('* PlatoonMerger: Found '..repr(Platoon:GetPlan()))
        end
        -- If we dont have already a platton for upgrades, create one.
        if not AlreadyMergedPlatoon then
            AlreadyMergedPlatoon = aiBrain:MakePlatoon( PlatoonPlan..'Platoon', PlatoonPlan )
            AlreadyMergedPlatoon.PlanName = PlatoonPlan
            AlreadyMergedPlatoon.BuilderName = PlatoonPlan..'Platoon'
            AlreadyMergedPlatoon:UniquelyNamePlatoon(PlatoonPlan)
        end
        -- Add our unit(s) to the upgrade platoon
        aiBrain:AssignUnitsToPlatoon( AlreadyMergedPlatoon, platoonUnits, 'support', 'none' )
        -- Disband this platoon, it's no longer needed.
        self:PlatoonDisbandNoAssign()
    end,

    ExtractorUpgradeAI = function(self)
        --LOG('+++ ExtractorUpgradeAI: START')
        local aiBrain = self:GetBrain()
        while aiBrain:PlatoonExists(self) do
            local ratio = 0.3
            if aiBrain.HasParagon then
                -- if we have a paragon, upgrade mex as fast as possible. Mabye we lose the paragon and need mex again.
                ratio = 1.0
            elseif aiBrain:GetEconomyIncome('MASS') * 10 > 600 then
                --LOG('Mass over 200. Eco running with 30%')
                ratio = 0.25
            elseif GetGameTimeSeconds() > 1800 then -- 30 * 60
                ratio = 0.25
            elseif GetGameTimeSeconds() > 1200 then -- 20 * 60
                ratio = 0.20
            elseif GetGameTimeSeconds() > 900 then -- 15 * 60
                ratio = 0.15
            elseif GetGameTimeSeconds() > 600 then -- 10 * 60
                ratio = 0.15
            elseif GetGameTimeSeconds() > 360 then -- 6 * 60
                ratio = 0.10
            elseif GetGameTimeSeconds() <= 360 then -- 6 * 60 run the first 6 minutes with 0% Eco and 100% Army
                ratio = 0.00
            end
            local platoonUnits = self:GetPlatoonUnits()
            local MassExtractorUnitList = aiBrain:GetListOfUnits(categories.MASSEXTRACTION * (categories.TECH1 + categories.TECH2 + categories.TECH3), false, false)
            -- Check if we can pause/unpause TECH3 Extractors (for more energy)
            if not UUtils.ExtractorPause( self, aiBrain, MassExtractorUnitList, ratio, 'TECH3') then
                -- Check if we can pause/unpause TECH2 Extractors
                if not UUtils.ExtractorPause( self, aiBrain, MassExtractorUnitList, ratio, 'TECH2') then
                    -- Check if we can pause/unpause TECH1 Extractors
                    if not UUtils.ExtractorPause( self, aiBrain, MassExtractorUnitList, ratio, 'TECH1') then
                        -- We have nothing to pause or unpause, lets upgrade more extractors
                        -- if we have 10% TECH1 extractors left (and 90% TECH2), then upgrade TECH2 to TECH3
                        if UUtils.HaveUnitRatio( aiBrain, 0.90, categories.MASSEXTRACTION * categories.TECH1, '<=', categories.MASSEXTRACTION * categories.TECH2 ) then
                            -- Try to upgrade a TECH2 extractor.
                            if not UUtils.ExtractorUpgrade(self, aiBrain, MassExtractorUnitList, ratio, 'TECH2', UnitUpgradeTemplates, StructureUpgradeTemplates) then
                                -- We can't upgrade a TECH2 extractor. Try to upgrade from TECH1 to TECH2
                                UUtils.ExtractorUpgrade(self, aiBrain, MassExtractorUnitList, ratio, 'TECH1', UnitUpgradeTemplates, StructureUpgradeTemplates)
                            end
                        else
                            -- We have less than 90% TECH2 extractors compared to TECH1. Upgrade more TECH1
                            UUtils.ExtractorUpgrade(self, aiBrain, MassExtractorUnitList, ratio, 'TECH1', UnitUpgradeTemplates, StructureUpgradeTemplates)
                        end
                    end
                end
            end
            -- Check the Eco every x Ticks
            WaitTicks(10)
            -- find dead units inside the platoon and disband if we find one
            for k,v in self:GetPlatoonUnits() do
                if not v or v.Dead or v:BeenDestroyed() then
                    -- We found a dead unit inside this platoon. Disband the platton; It will be reformed
                    --LOG('+++ ExtractorUpgradeAI: Found Dead unit, self:PlatoonDisbandNoAssign()')
                    -- needs PlatoonDisbandNoAssign, or extractors will stop upgrading if the platton is disbanded
                    self:PlatoonDisbandNoAssign()
                    return
                end
            end
        end
        -- No return here. We will never reach this position. After disbanding this platoon, the forked 'ExtractorUpgradeAI' thread will be terminated from outside.
    end,

    SimpleReturnToBase = function(self, basePosition)
        local aiBrain = self:GetBrain()
        local PlatoonPosition
        local Lastdist
        local dist
        local Stuck = 0
        self:Stop()
        self:MoveToLocation(basePosition, false)
        while aiBrain:PlatoonExists(self) do
            PlatoonPosition = self:GetPlatoonPosition()
            if not PlatoonPosition then
                --LOG('* SimpleReturnToBase: no Platoon Position')
                break
            end
            dist = VDist2( basePosition[1], basePosition[3], PlatoonPosition[1], PlatoonPosition[3] )
            if dist < 20 then
                break
            end
            -- Do we move ?
            if Lastdist ~= dist then
                Stuck = 0
                Lastdist = dist
            -- No, we are not moving, wait 100 ticks then break and use the next weaypoint
            else
                Stuck = Stuck + 1
                if Stuck > 20 then
                    self:Stop()
                    break
                end
            end
            WaitTicks(10)
        end
        self:PlatoonDisband()
    end,

    ForceReturnToNearestBaseAIUveso = function(self)
        local platPos = self:GetPlatoonPosition() or false
        if not platPos then
            return
        end
        local aiBrain = self:GetBrain()
        local nearestbase = false
        for k,v in aiBrain.BuilderManagers do
            -- check if we can move to this base
            if not AIUtils.ValidateLayer(v.FactoryManager.Location,self.MovementLayer) then
                --LOG('ForceReturnToNearestBaseAIUveso Can\'t return to This base. Wrong movementlayer: '..repr(v.FactoryManager.LocationType))
                continue
            end
            local dist = VDist2( platPos[1], platPos[3], v.FactoryManager.Location[1], v.FactoryManager.Location[3] )
            if not nearestbase or nearestbase.dist > dist then
                nearestbase = {}
                nearestbase.Pos = v.FactoryManager.Location
                nearestbase.dist = dist
            end
        end
        if not nearestbase then
            return
        end
        self:Stop()
        self:MoveToLocationInclTransport(true, nearestbase.Pos, false, false, nearestbase.Pos, false)
        -- Disband the platoon so the locationmanager can assign a new task to the units.
        WaitTicks(30)
        self:PlatoonDisband()
    end,

    ForceReturnToNavalBaseAIUveso = function(self, aiBrain, basePosition)
        local path, reason = AIAttackUtils.PlatoonGenerateSafePathTo(aiBrain, self.MovementLayer or 'Water' , self:GetPlatoonPosition(), basePosition, 1000, 512)
        -- clear commands, so we don't get stuck if we have an unreachable destination
        IssueClearCommands(self:GetPlatoonUnits())
        if path then
            if table.getn(path) > 1 then
                --LOG('* ForceReturnToNavalBaseAIUveso: table.getn(path): '..table.getn(path))
            end
            --LOG('* ForceReturnToNavalBaseAIUveso: moving to destination by path.')
            for i=1, table.getn(path) do
                --LOG('* ForceReturnToNavalBaseAIUveso: moving to destination. i: '..i..' coords '..repr(path[i]))
                self:MoveToLocation(path[i], false)
                --LOG('* ForceReturnToNavalBaseAIUveso: moving to Waypoint')
                local PlatoonPosition
                local Lastdist
                local dist
                local Stuck = 0
                while aiBrain:PlatoonExists(self) do
                    PlatoonPosition = self:GetPlatoonPosition()
                    dist = VDist2( path[i][1], path[i][3], PlatoonPosition[1], PlatoonPosition[3] )
                    -- are we closer then 15 units from the next marker ? Then break and move to the next marker
                    if dist < 20 then
                        -- If we don't stop the movement here, then we have heavy traffic on this Map marker with blocking units
                        self:Stop()
                        break
                    end
                    -- Do we move ?
                    if Lastdist ~= dist then
                        Stuck = 0
                        Lastdist = dist
                    -- No, we are not moving, wait 100 ticks then break and use the next weaypoint
                    else
                        Stuck = Stuck + 1
                        if Stuck > 15 then
                            --LOG('* ForceReturnToNavalBaseAIUveso: Stucked while moving to Waypoint. Stuck='..Stuck..' - '..repr(path[i]))
                            self:Stop()
                            break
                        end
                    end
                    WaitTicks(10)
                end
            end
        else
            --LOG('* ForceReturnToNavalBaseAIUveso: we have no Graph to reach the destination. Checking CanPathTo()')
            if reason == 'NoGraph' then
                local success, bestGoalPos = AIAttackUtils.CheckPlatoonPathingEx(self, basePosition)
                if success then
                    --LOG('* ForceReturnToNavalBaseAIUveso: found a way with CanPathTo(). moving to destination')
                    self:MoveToLocation(basePosition, false)
                else
                    --LOG('* ForceReturnToNavalBaseAIUveso: CanPathTo() failed for '..repr(basePosition)..'.')
                end
            end
        end
        local oldDist = 100000
        local platPos = self:GetPlatoonPosition() or basePosition
        local Stuck = 0
        while aiBrain:PlatoonExists(self) do
            self:MoveToLocation(basePosition, false)
            --LOG('* ForceReturnToNavalBaseAIUveso: Waiting for moving to base')
            platPos = self:GetPlatoonPosition() or basePosition
            dist = VDist2(platPos[1], platPos[3], basePosition[1], basePosition[3])
            if dist < 20 then
                --LOG('* ForceReturnToNavalBaseAIUveso: We are home! disband!')
                -- Wait some second, so all platoon units have time to reach the base.
                WaitSeconds(5)
                self:Stop()
                break
            end
            -- if we haven't moved in 5 seconds... leave the loop
            if oldDist - dist < 0 then
                break
            end
            oldDist = dist
            Stuck = Stuck + 1
            if Stuck > 4 then
                self:Stop()
                break
            end
            WaitSeconds(5)
        end
        -- Disband the platoon so the locationmanager can assign a new task to the units.
        WaitTicks(30)
        self:PlatoonDisband()
    end,

    AntiNukePlatoonAI = function(self)
        local aiBrain = self:GetBrain()
        while aiBrain:PlatoonExists(self) do
            local platoonUnits = self:GetPlatoonUnits()
            -- find dead units inside the platoon and disband if we find one
            for k,unit in platoonUnits do
                if not unit or unit.Dead or unit:BeenDestroyed() then
                    -- We found a dead unit inside this platoon. Disband the platton; It will be reformed
                    -- needs PlatoonDisbandNoAssign, or launcher will stop building nukes if the platton is disbanded
                    self:PlatoonDisbandNoAssign()
                    --LOG('* AntiNukePlatoonAI: PlatoonDisband')
                    return
                else
                    unit:SetAutoMode(true)
                end
            end
            WaitTicks(50)
        end
    end,

    ArtilleryPlatoonAI = function(self)
    --NO crash at 002cbc63
        local aiBrain = self:GetBrain()
        local ClosestTarget = nil
        local LastTarget = nil
        while aiBrain:PlatoonExists(self) do
            -- Primary Target
            ClosestTarget = nil
            if aiBrain.PrimaryTarget and not aiBrain.PrimaryTarget.Dead then
                ClosestTarget = aiBrain.PrimaryTarget
            else
                local basePosition = aiBrain.BuilderManagers['MAIN'].Position or nil
                if not basePosition then continue end
                local TargetsInBaseRange = aiBrain:GetUnitsAroundPoint( categories.MOBILE * categories.EXPERIMENTAL - categories.AIR, basePosition, 512, 'Enemy')
                local distance = 512
                for num, Target in TargetsInBaseRange do
                    if Target and not Target.Dead then
                        local TargetPosition = Target:GetPosition() or nil
                        if TargetPosition then
                            local targetRange = VDist2(basePosition[1],basePosition[3],TargetPosition[1],TargetPosition[3])
                            if targetRange < distance then
                                distance = targetRange
                                ClosestTarget = Target
                            end
                        end
                    end
                end
            end
            
            if ClosestTarget == LastTarget then
                --LOG('* ArtilleryPlatoonAI: ClosestTarget == LastTarget')
            elseif ClosestTarget and not ClosestTarget.Dead then
                local BlueprintID = ClosestTarget:GetBlueprint().BlueprintId
                LastTarget = ClosestTarget
                -- Wait until the target is dead
                while ClosestTarget and not ClosestTarget.Dead do
                    if aiBrain.PrimaryTarget and aiBrain.PrimaryTarget ~= ClosestTarget then
                        break
                    end
                    platoonUnits = self:GetPlatoonUnits()
                    for _, Arty in platoonUnits do
                        if not Arty or Arty.Dead then
                            return
                        end
                        local Target = Arty:GetTargetEntity()
                        if Target == ClosestTarget then
                            --Arty:SetCustomName('continue '..BlueprintID)
                        else
                            --Arty:SetCustomName('Attacking '..BlueprintID)
                            --IssueStop({v})
                            IssueClearCommands({Arty})
                            WaitTicks(1)
                            if ClosestTarget and not ClosestTarget.Dead then
                                IssueAttack({Arty}, ClosestTarget)
                            end
                        end
                    end
                    WaitSeconds(5)
                end
            end
            WaitSeconds(5)
            -- find dead units inside the platoon and disband if we find one
        end
    end,

    ShieldRepairAI = function(self)
    --NO crash at 002cbc63
        local aiBrain = self:GetBrain()
        local BuilderManager = aiBrain.BuilderManagers['MAIN']
        local lastSHIELD = 0
        local lastSUB = 0
        while aiBrain:PlatoonExists(self) do
            local numSUB = 0
            for i,unit in self:GetPlatoonUnits() do
                if not unit or unit.Dead or unit:BeenDestroyed() then
                    self:PlatoonDisbandNoAssign()
                    return
                end
                numSUB = numSUB + 1
            end
            -- Wait for stopping assist
            WaitTicks(1)
            local Shields = AIUtils.GetOwnUnitsAroundPoint(aiBrain, categories.STRUCTURE * categories.SHIELD, BuilderManager.Position, 256)
            local lasthighestHealth
            local highestHealth
            local numSHIELD = 0
            -- get the shield with the highest health
            for k,Shield in Shields do
                if not Shield or Shield.Dead then continue end
                if not highestHealth or Shield.MyShield:GetMaxHealth() > highestHealth then
                    highestHealth = Shield.MyShield:GetMaxHealth()
                end
                numSHIELD = numSHIELD + 1
            end
            for k,Shield in Shields do
                if not Shield or Shield.Dead then continue end
                if (not lasthighestHealth or Shield.MyShield:GetMaxHealth() > lasthighestHealth) and Shield.MyShield:GetMaxHealth() < highestHealth then
                    lasthighestHealth = Shield.MyShield:GetMaxHealth()
                end
            end
            if numSUB ~= lastSUB or numSHIELD ~= lastSHIELD then
                lastSUB = numSUB
                lastSHIELD = numSHIELD
                for i,unit in self:GetPlatoonUnits() do
--                    IssueClearCommands({unit})
                    unit.AssistSet = nil
                    unit.UnitBeingAssist = nil
                end
                while true do
                    local numAssisters
                    local ShieldWithleastAssisters
                    -- get a shield with highest Health and lowest assistees
                    numAssisters = nil
                    -- Fist check all shields with the highest health
                    for k,Shield in Shields do
                        if not Shield or Shield.Dead or Shield.MyShield:GetMaxHealth() ~= highestHealth then continue end
                        if not numAssisters or table.getn(Shield:GetGuards()) < numAssisters  then
                            numAssisters = table.getn(Shield:GetGuards())
                            -- set a maximum of 10 assisters per shield
                            if numAssisters < 10 then
                                ShieldWithleastAssisters = Shield
                            end
                        end
                    end
                    -- If we have assister on all high shilds then spread the remaining SUBCOMs over lower shields
                    if not ShieldWithleastAssisters and lasthighestHealth and lasthighestHealth ~= highestHealth then
                        for k,Shield in Shields do
                            if not Shield or Shield.Dead or Shield.MyShield:GetMaxHealth() ~= lasthighestHealth then continue end
                            if not numAssisters or table.getn(Shield:GetGuards()) < numAssisters  then
                                numAssisters = table.getn(Shield:GetGuards())
                                ShieldWithleastAssisters = Shield
                            end
                        end
                    end
                    
                    if not ShieldWithleastAssisters then
                        --LOG('*ShieldRepairAI: not ShieldWithleastAssisters. break!')
                        break
                    end
                    local shieldPos = ShieldWithleastAssisters:GetPosition() or nil
                    -- search for the closest idle unit
                    local closest
                    local bestUnit
                    for i,unit in self:GetPlatoonUnits() do
                        if not unit or unit.Dead or unit:BeenDestroyed() then
                            self:PlatoonDisbandNoAssign()
                            return
                        end
                        if unit.AssistSet then continue end
                        local unitPos = unit:GetPosition() or nil
                        if unitPos and shieldPos then
                            local dist = VDist2(shieldPos[1], shieldPos[3], unitPos[1], unitPos[3])
                            if not closest or dist < closest then
                                closest = dist
                                bestUnit = unit
                            end
                        end
                    end
                    if not bestUnit then
                        --LOG('*ShieldRepairAI: not bestUnit. break!')
                        break
                    end
                    IssueClearCommands({bestUnit})
                    WaitTicks(1)
                    IssueGuard({bestUnit}, ShieldWithleastAssisters)
                    bestUnit.AssistSet = true
                    bestUnit.UnitBeingAssist = ShieldWithleastAssisters
                    WaitTicks(1)
                end

            end
            WaitTicks(30)
        end
    end,

    NukePlatoonAI = function(self)
    --NO crash at 002cbc63
        local aiBrain = self:GetBrain()
        local ECOLoopCounter = 0
        local mapSizeX, mapSizeZ = GetMapSize()
        local platoonUnits
        local LauncherFull
        local LauncherReady
        local EnemyAntiMissile
        local EnemyUnits
        local EnemyTargetPositions
        local MissileCount
        local EnemyTarget
        while aiBrain:PlatoonExists(self) do
            ---------------------------------------------------------------------------------------------------
            -- Count Launchers, set them to automode, count stored missiles
            ---------------------------------------------------------------------------------------------------
            platoonUnits = self:GetPlatoonUnits()
            LauncherFull = {}
            LauncherReady = {}
            MissileCount = 0
            for _, Launcher in platoonUnits do
                -- We found a dead unit inside this platoon. Disband the platton; It will be reformed
                -- needs PlatoonDisbandNoAssign, or launcher will stop building nukes if the platton is disbanded
                if not Launcher or Launcher.Dead or Launcher:BeenDestroyed() then
                    self:PlatoonDisbandNoAssign()
                    return
                end
                local NukeSiloAmmoCount = Launcher:GetNukeSiloAmmoCount() or 0
                Launcher:SetAutoMode(true)
                IssueClearCommands({Launcher})
                if NukeSiloAmmoCount > 4 then
                    table.insert(LauncherFull, Launcher)
                end
                if NukeSiloAmmoCount > 0 then
                    table.insert(LauncherReady, Launcher)
                    MissileCount = MissileCount + NukeSiloAmmoCount
                end
            end
            EnemyAntiMissile = aiBrain:GetUnitsAroundPoint(categories.STRUCTURE * ((categories.DEFENSE * categories.ANTIMISSILE * categories.TECH3) + (categories.SHIELD * categories.EXPERIMENTAL)), Vector(mapSizeX/2,0,mapSizeZ/2), mapSizeX+mapSizeZ, 'Enemy')
            ---------------------------------------------------------------------------------------------------
            -- check if the enemy has more then 2 Anti Missiles, if yes, stop building nukes. It's to much ECO
            ---------------------------------------------------------------------------------------------------
            if not aiBrain.HasParagon and ( table.getn(EnemyAntiMissile) or 0 > 3 or aiBrain:GetEconomyStoredRatio('ENERGY') < 0.90 or aiBrain:GetEconomyStoredRatio('MASS') < 0.90 ) then
                -- We don't want to attack. Save the eco and disable launchers.
                --LOG('* NukePlatoonAI: Too much Antimissiles or low mass/energy, deactivating all nuke launchers')
                for k,Launcher in platoonUnits do
                    if not Launcher or Launcher.Dead or Launcher:BeenDestroyed() then
                        -- We found a dead unit inside this platoon. Disband the platton; It will be reformed
                        -- needs PlatoonDisbandNoAssign, or launcher will stop building nukes if the platton is disbanded
                        self:PlatoonDisbandNoAssign()
                        return
                    end
                    -- Check if the launcher is active
                    if not Launcher:IsPaused() then
                        -- yes, its active. Disable it.
                        Launcher:SetPaused( true )
                        -- now break, we only want do disable one launcher per loop
                        break
                    end
                end
            elseif aiBrain.HasParagon or ( aiBrain:GetEconomyStoredRatio('MASS') > 0.90 and aiBrain:GetEconomyTrend('ENERGY') >= 600.0 ) then
                -- Enemy has less then 3 Anti Missiles. And we have good eco. Activate nukes!
                --LOG('* NukePlatoonAI: Activating all nuke launchers')
                for k,Launcher in platoonUnits do
                    if not Launcher or Launcher.Dead or Launcher:BeenDestroyed() then
                        -- We found a dead unit inside this platoon. Disband the platton; It will be reformed
                        -- needs PlatoonDisbandNoAssign, or launcher will stop building nukes if the platton is disbanded
                        self:PlatoonDisbandNoAssign()
                        return
                    end
                    -- Check if the launcher is deactivated
                    if Launcher:IsPaused() then
                        -- yes, it's off. Turn it on.
                        Launcher:SetPaused( false )
                        break
                    end
                end

            end
            -- At this point we have only checked the eco for our launchers. Only check targetting and missile launching every 10th loop
            ECOLoopCounter = ECOLoopCounter + 1
            if ECOLoopCounter < 10 then
                WaitTicks(1)
                -- start the "while aiBrain:PlatoonExists(self) do" loop from the beginning
                continue
            end
            ECOLoopCounter = 0
            ---------------------------------------------------------------------------------------------------
            -- If we have a PrimaryTarget, launch nukes
            ---------------------------------------------------------------------------------------------------
            if 1 == 1 and aiBrain.PrimaryTarget and not aiBrain.PrimaryTarget.Dead and table.getn(LauncherReady) > 0 and EntityCategoryContains(categories.EXPERIMENTAL, aiBrain.PrimaryTarget) then
                local TargetPos
                local LauncherPos
                local dist
                -- loop over all nuke launcher
                for k, Launcher in LauncherReady do
                    if not Launcher or Launcher.Dead or Launcher:BeenDestroyed() then
                        -- We found a dead unit inside this platoon. Disband the platton; It will be reformed
                        -- needs PlatoonDisbandNoAssign, or launcher will stop building nukes if the platton is disbanded
                        self:PlatoonDisbandNoAssign()
                        return
                    end
                    if not aiBrain.PrimaryTarget or aiBrain.PrimaryTarget.Dead then
                        -- Our Target is dead. break
                        break
                    end
                    -- check if the target is closer then 20000 and farther then 200
                    TargetPos = aiBrain.PrimaryTarget:GetPosition() or nil
                    if not TargetPos then
                        -- Our Target is dead. break
                        break
                    end
                    LauncherPos = Launcher:GetPosition() or nil
                    if not LauncherPos then
                        -- Our Launcher is Dead ? failsafe, continue with the next Launcher
                        continue
                    end
                    dist = VDist2(LauncherPos[1],LauncherPos[3],TargetPos[1],TargetPos[3])
                    if dist < 200 or dist > 20000 then
                        -- Target is out of range, skip this launcher
                        continue
                    end
                    -- Lead target function
                    TargetPos = self:LeadNukeTarget(aiBrain.PrimaryTarget)
                    if not TargetPos then
                        -- Our Target is dead. break
                        break
                    end
                    -- check if we have friendly Buildings in blastradius. If yes don't fire
                    if aiBrain:GetNumUnitsAroundPoint(categories.STRUCTURE, TargetPos, 50 , 'Ally') > 1 then
                        break
                    end
                    -- Attack the target
                    IssueNuke({Launcher}, TargetPos)
                    table.remove(LauncherReady, k)
                    MissileCount = MissileCount - 1
                    WaitTicks(200)-- wait 8 seconds then fire the next missile
                end
                WaitTicks(450)-- wait 45 seconds for the missile flight, then get new targets
            end
            ---------------------------------------------------------------------------------------------------
            -- first try to target all targets that are not protected from enemy anti missile
            ---------------------------------------------------------------------------------------------------
            EnemyUnits = aiBrain:GetUnitsAroundPoint(categories.STRUCTURE - categories.MASSEXTRACTION - categories.TECH1 - categories.TECH2 , Vector(mapSizeX/2,0,mapSizeZ/2), mapSizeX+mapSizeZ, 'Enemy')
            EnemyTargetPositions = {}
            --LOG('* NukePlatoonAI: (Unprotected) EnemyUnits '..table.getn(EnemyUnits))
            for _, EnemyTarget in EnemyUnits do
                -- get position of the possible next target
                local EnemyTargetPos = EnemyTarget:GetPosition() or nil
                if not EnemyTargetPos then continue end
                local ToClose = false
                -- loop over all already attacked targets
                for _, ETargetPosition in EnemyTargetPositions do
                    -- Check if the target is closeer then 40 to an already attacked target
                    if VDist2(EnemyTargetPos[1],EnemyTargetPos[3],ETargetPosition[1],ETargetPosition[3]) < 40 then
                        ToClose = true
                        break -- break out of the EnemyTargetPositions loop
                    end
                end
                if ToClose then
                    continue -- Skip this enemytarget and check the next
                end
                -- loop over all Enemy anti nuke launchers.
                for _, AntiMissile in EnemyAntiMissile do
                    if not AntiMissile or AntiMissile.Dead or AntiMissile:BeenDestroyed() then continue end
                    -- if the launcher is still in build, don't count it.
                    local FractionComplete = AntiMissile:GetFractionComplete() or nil
                    if not FractionComplete then continue end
                    if FractionComplete < 1 then
                        continue
                    end
                    -- get the location of AntiMissile
                    local AntiMissilePos = AntiMissile:GetPosition() or nil
                    if not AntiMissilePos then continue end
                    -- Check if our target is inside range of an antimissile
                    if VDist2(EnemyTargetPos[1],EnemyTargetPos[3],AntiMissilePos[1],AntiMissilePos[3]) < 90 then
                       --LOG('* NukePlatoonAI: (Unprotected) Target in range of Nuke Anti Missile. Skiped')
                        ToClose = true
                        break -- break out of the EnemyTargetPositions loop
                    end
                end
                if ToClose then
                    continue -- Skip this enemytarget and check the next
                end
                table.insert(EnemyTargetPositions, EnemyTargetPos)
            end
            ---------------------------------------------------------------------------------------------------
            -- Now, if we have unprotected targets, shot at it
            ---------------------------------------------------------------------------------------------------
            --LOG('* NukePlatoonAI: (Unprotected) table.getn(EnemyTargetPositions) '..table.getn(EnemyTargetPositions))
            if 1 == 1 and table.getn(EnemyTargetPositions) > 0 and table.getn(LauncherReady) > 0 then
                -- loopß over all targets
                for _, ActualTargetPos in EnemyTargetPositions do
                    -- loop over all nuke launcher
                    for k, Launcher in LauncherReady do
                        if not Launcher or Launcher.Dead or Launcher:BeenDestroyed() then
                            -- We found a dead unit inside this platoon. Disband the platton; It will be reformed
                            -- needs PlatoonDisbandNoAssign, or launcher will stop building nukes if the platton is disbanded
                            self:PlatoonDisbandNoAssign()
                            return
                        end
                        -- check if the target is closer then 20000
                        LauncherPos = Launcher:GetPosition() or nil
                        if not LauncherPos then continue end
                        if VDist2(LauncherPos[1],LauncherPos[3],ActualTargetPos[1],ActualTargetPos[3]) > 20000 then
                            --LOG('* NukePlatoonAI: (Unprotected) Target out of range. Skiped')
                            -- Target is out of range, skip this launcher
                            continue
                        end
                        -- Attack the target
                        --LOG('* NukePlatoonAI: (Unprotected) Attacking Enemy Position!')
                        IssueNuke({Launcher}, ActualTargetPos)
                        table.remove(LauncherReady, k)
                        MissileCount = MissileCount - 1
                        break -- stop seraching for available launchers and check the next target
                    end
                    if table.getn(LauncherReady) < 1 then
                        --LOG('* NukePlatoonAI: (Unprotected) All Launchers are bussy! Break!')
                        break  -- stop seraching for targets, we don't hava a launcher ready.
                    end
                    WaitTicks(40)-- wait 4 seconds between each Missile shoot
                end
                WaitTicks(450)-- wait 45 seconds for the missile flight, then get new targets
            end
            ---------------------------------------------------------------------------------------------------
            -- Try to overwhelm anti nuke, search for targets
            ---------------------------------------------------------------------------------------------------
            EnemyProtectorsNum = 0
            --LOG('* NukePlatoonAI: MissileCountB '..MissileCount..' Overwhelm!')
            if 1 == 1 and MissileCount > 8 and table.getn(EnemyAntiMissile) > 0 then
                --LOG('* NukePlatoonAI: (Overwhelm) MissileCount ('..MissileCount..') > EnemyAntiMissile )'..table.getn(EnemyAntiMissile)..')')
                local AntiMissileRanger = {}
                -- get a list with all antinukes and distance to each other
                for MissileIndex, AntiMissileSTART in EnemyAntiMissile do
                    AntiMissileRanger[MissileIndex] = 0
                    -- get the location of AntiMissile
                    local AntiMissilePosSTART = AntiMissileSTART:GetPosition() or nil
                    if not AntiMissilePosSTART then break end
                    for _, AntiMissileEND in EnemyAntiMissile do
                        local AntiMissilePosEND = AntiMissileSTART:GetPosition() or nil
                        if not AntiMissilePosEND then continue end
                        local dist = VDist2(AntiMissilePosSTART[1],AntiMissilePosSTART[3],AntiMissilePosEND[1],AntiMissilePosEND[3])
                        AntiMissileRanger[MissileIndex] = AntiMissileRanger[MissileIndex] + dist
                    end
                end
                -- find the least protected anti missile
                local HighestDistance = 0
                local HighIndex = false
                for MissileIndex, MissileRange in AntiMissileRanger do
                    if MissileRange > HighestDistance then
                        HighestDistance = MissileRange
                        HighIndex = MissileIndex
                    end
                end
                local TargetPosition = false
                if HighIndex and EnemyAntiMissile[HighIndex] and not EnemyAntiMissile[HighIndex].Dead then
                    --LOG('* NukePlatoonAI: (Overwhelm) Antimissile with highest dinstance to other antimisiiles has HighIndex= '..HighIndex)
                    -- kill the launcher will all missiles we have
                    EnemyTarget = EnemyAntiMissile[HighIndex]
                    TargetPosition = EnemyTarget:GetPosition() or false
                elseif EnemyAntiMissile[1] and not EnemyAntiMissile[1].Dead then
                    --LOG('* NukePlatoonAI: (Overwhelm) Targetting Antimissile[1]')
                    EnemyTarget = EnemyAntiMissile[1]
                    TargetPosition = EnemyTarget:GetPosition() or false
                end
                -- Scan how many antinukes are protecting the least defended target:
                local ProtectorUnits = aiBrain:GetUnitsAroundPoint(categories.STRUCTURE * ((categories.DEFENSE * categories.ANTIMISSILE * categories.TECH3) + (categories.SHIELD * categories.EXPERIMENTAL)), TargetPosition, 90, 'Enemy')
                if ProtectorUnits then
                    EnemyProtectorsNum = table.getn(ProtectorUnits)
                end
            end
            ---------------------------------------------------------------------------------------------------
            -- Try to overwhelm anti nuke, search for targets
            ---------------------------------------------------------------------------------------------------
            if 1 == 1 and EnemyTarget and EnemyProtectorsNum > 0 and MissileCount > EnemyProtectorsNum * 8 then
                -- Fire as long as the target exists
                --LOG('* NukePlatoonAI: while EnemyTarget do ')
                while EnemyTarget and not EnemyTarget.Dead do
                    --LOG('* NukePlatoonAI: (Overwhelm) Loop!')
                    local missile = false
                    for k, Launcher in platoonUnits do
                        if not Launcher or Launcher.Dead or Launcher:BeenDestroyed() then
                            -- We found a dead unit inside this platoon. Disband the platton; It will be reformed
                            -- needs PlatoonDisbandNoAssign, or launcher will stop building nukes if the platton is disbanded
                            self:PlatoonDisbandNoAssign()
                            return
                        end
                        --LOG('* NukePlatoonAI: (Overwhelm) Fireing Nuke: '..repr(Index))
                        if Launcher:GetNukeSiloAmmoCount() > 0 then
                            if Launcher:GetNukeSiloAmmoCount() > 1 then
                                missile = true
                            end
                            IssueNuke({Launcher}, TargetPosition)
                            table.remove(LauncherReady, k)
                            MissileCount = MissileCount - 1
                        end
                        if not EnemyTarget or EnemyTarget.Dead then
                            --LOG('* NukePlatoonAI: (Overwhelm) Target is dead. break fire loop')
                            break -- break the "for Index, Launcher in platoonUnits do" loop
                        end
                    end
                    if not missile then
                        --LOG('* NukePlatoonAI: (Overwhelm) Nukes are empty')
                        break -- break the "while EnemyTarget do" loop
                    end
                    -- Wait for the missleflight of all missiles, then shoot again.
                    WaitTicks(450)
                end
            end
            ---------------------------------------------------------------------------------------------------
            -- Jericho! Check if we can attack all targets at the same time
            ---------------------------------------------------------------------------------------------------
            EnemyTargetPositions = {}
            --LOG('* NukePlatoonAI: (Jericho) LauncherReady ('..LauncherReady..') > platoonUnits-3 )'..table.getn(platoonUnits)..')')
            for _, EnemyTarget in EnemyUnits do
                -- get position of the possible next target
                local EnemyTargetPos = EnemyTarget:GetPosition() or nil
                if not EnemyTargetPos then continue end
                local ToClose = false
                -- loop over all already attacked targets
                for _, ETargetPosition in EnemyTargetPositions do
                    -- Check if the target is closer then 40 to an already attacked target
                    if VDist2(EnemyTargetPos[1],EnemyTargetPos[3],ETargetPosition[1],ETargetPosition[3]) < 40 then
                        ToClose = true
                        break -- break out of the EnemyTargetPositions loop
                    end
                end
                if ToClose then
                    continue -- Skip this enemytarget and check the next
                end
                table.insert(EnemyTargetPositions, EnemyTargetPos)
            end
            ---------------------------------------------------------------------------------------------------
            -- Now, if we have more launchers ready then targets start Jericho bombardment
            ---------------------------------------------------------------------------------------------------
            if 1 != 1 and table.getn(LauncherReady) >= table.getn(EnemyTargetPositions) and table.getn(EnemyTargetPositions) > 0 and table.getn(LauncherFull) > 0 then
                -- loopß over all targets
                for _, ActualTargetPos in EnemyTargetPositions do
                    -- loop over all nuke launcher
                    for k, Launcher in LauncherReady do
                        if not Launcher or Launcher.Dead or Launcher:BeenDestroyed() then
                            -- We found a dead unit inside this platoon. Disband the platton; It will be reformed
                            -- needs PlatoonDisbandNoAssign, or launcher will stop building nukes if the platton is disbanded
                            self:PlatoonDisbandNoAssign()
                            return
                        end
                        -- check if the target is closer then 20000
                        LauncherPos = Launcher:GetPosition() or nil
                        if not LauncherPos then continue end
                        if VDist2(LauncherPos[1],LauncherPos[3],ActualTargetPos[1],ActualTargetPos[3]) > 20000 then
                            -- Target is out of range, skip this launcher
                            continue
                        end
                        -- Attack the target
                        IssueNuke({Launcher}, ActualTargetPos)
                        MissileCount = MissileCount - 1
                        table.remove(LauncherReady, k)
                        break -- stop seraching for available launchers and check the next target
                    end
                    if table.getn(LauncherReady) < 1 then
                        break  -- stop seraching for targets, we don't hava a launcher ready.
                    end
                    WaitTicks(40)-- wait 4 seconds between each Missile shoot
                end
                WaitTicks(450)-- wait 45 seconds for the missile flight, then get new targets
            end
            ---------------------------------------------------------------------------------------------------
            -- If we have an launcher with 5 missiles fire one.
            ---------------------------------------------------------------------------------------------------
            if 1 == 1 and table.getn(LauncherFull) > 0 then
                EnemyUnits = aiBrain:GetUnitsAroundPoint(categories.STRUCTURE * categories.EXPERIMENTAL, Vector(mapSizeX/2,0,mapSizeZ/2), mapSizeX+mapSizeZ, 'Enemy')
                if not EnemyUnits then
                    EnemyUnits = aiBrain:GetUnitsAroundPoint(categories.STRUCTURE * categories.TECH3 , Vector(mapSizeX/2,0,mapSizeZ/2), mapSizeX+mapSizeZ, 'Enemy')
                end
                if not EnemyUnits then
                    EnemyUnits = aiBrain:GetUnitsAroundPoint(categories.STRUCTURE , Vector(mapSizeX/2,0,mapSizeZ/2), mapSizeX+mapSizeZ, 'Enemy')
                end
                -- if we don't have any enemy structures, then attack mobile units.
                if not EnemyUnits then
                    EnemyUnits = aiBrain:GetUnitsAroundPoint(categories.MOBILE - categories.AIR, Vector(mapSizeX/2,0,mapSizeZ/2), mapSizeX+mapSizeZ, 'Enemy')
                end
                if table.getn(EnemyUnits) > 0 then
                    --LOG('* NukePlatoonAI: (Launcher Full) MissileCount ('..MissileCount..') > EnemyUnits ('..table.getn(EnemyUnits)..')')
                    EnemyTargetPositions = {}
                    -- get enemy target positions
                    for _, EnemyTarget in EnemyUnits do
                        -- get position of the possible next target
                        local EnemyTargetPos = EnemyTarget:GetPosition() or nil
                        if not EnemyTargetPos then continue end
                        local ToClose = false
                        -- loop over all already attacked targets
                        for _, ETargetPosition in EnemyTargetPositions do
                            -- Check if the target is closeer then 40 to an already attacked target
                            if VDist2(EnemyTargetPos[1],EnemyTargetPos[3],ETargetPosition[1],ETargetPosition[3]) < 40 then
                                ToClose = true
                                break -- break out of the EnemyTargetPositions loop
                            end
                        end
                        if ToClose then
                            continue -- Skip this enemytarget and check the next
                        end
                        table.insert(EnemyTargetPositions, EnemyTargetPos)
                    end
                end
            end
            ---------------------------------------------------------------------------------------------------
            -- Now, if we have targets, shot at it
            ---------------------------------------------------------------------------------------------------
            --LOG('* NukePlatoonAI: (Unprotected) table.getn(EnemyTargetPositions) '..table.getn(EnemyTargetPositions))
            if 1 == 1 and table.getn(EnemyTargetPositions) > 0 and table.getn(LauncherFull) > 0 then
                -- loopß over all targets
                for _, ActualTargetPos in EnemyTargetPositions do
                    -- loop over all nuke launcher
                    for k, Launcher in LauncherFull do
                        if not Launcher or Launcher.Dead or Launcher:BeenDestroyed() then
                            -- We found a dead unit inside this platoon. Disband the platton; It will be reformed
                            -- needs PlatoonDisbandNoAssign, or launcher will stop building nukes if the platton is disbanded
                            self:PlatoonDisbandNoAssign()
                            return
                        end
                        -- check if the target is closer then 20000
                        LauncherPos = Launcher:GetPosition() or nil
                        if not LauncherPos then continue end
                        if VDist2(LauncherPos[1],LauncherPos[3],ActualTargetPos[1],ActualTargetPos[3]) > 20000 then
                            --LOG('* NukePlatoonAI: (Unprotected) Target out of range. Skiped')
                            -- Target is out of range, skip this launcher
                            continue
                        end
                        -- Attack the target
                        --LOG('* NukePlatoonAI: (Unprotected) Attacking Enemy Position!')
                        IssueNuke({Launcher}, ActualTargetPos)
                        table.remove(LauncherFull, k)
                        MissileCount = MissileCount - 1
                        break -- stop seraching for available launchers and check the next target
                    end
                    if table.getn(LauncherFull) < 1 then
                        --LOG('* NukePlatoonAI: (Unprotected) All Launchers are bussy! Break!')
                        break  -- stop seraching for targets, we don't hava a launcher ready.
                    end
                    WaitTicks(40)-- wait 4 seconds between each Missile shoot
                end
                WaitTicks(450)-- wait 45 seconds for the missile flight, then get new targets
            end

        end -- while aiBrain:PlatoonExists(self) do
    end,
    
    LeadNukeTarget = function(self, target)
        local TargetPos
        -- Get target position in 1 second intervals.
        -- This allows us to get speed and direction from the target
        local TargetStartPosition=0
        local Target1SecPos=0
        local Target2SecPos=0
        local XmovePerSec=0
        local YmovePerSec=0
        local XmovePerSecCheck=-1
        local YmovePerSecCheck=-1
        -- Check if the target is runing straight or circling
        -- If x/y and xcheck/ycheck are equal, we can be sure the target is moving straight
        -- in one direction. At least for the last 2 seconds.
        local LoopSaveGuard = 0
        while target and not target.Dead and (XmovePerSec ~= XmovePerSecCheck or YmovePerSec ~= YmovePerSecCheck) and LoopSaveGuard < 10 do
            if not target or target.Dead then return false end
            -- 1st position of target
            TargetPos = target:GetPosition()
            TargetStartPosition = {TargetPos[1], 0, TargetPos[3]}
            WaitTicks(10)
            -- 2nd position of target after 1 second
            TargetPos = target:GetPosition()
            Target1SecPos = {TargetPos[1], 0, TargetPos[3]}
            XmovePerSec = (TargetStartPosition[1] - Target1SecPos[1])
            YmovePerSec = (TargetStartPosition[3] - Target1SecPos[3])
            WaitTicks(10)
            -- 3rd position of target after 2 seconds to verify straight movement
            TargetPos = target:GetPosition()
            Target2SecPos = {TargetPos[1], TargetPos[2], TargetPos[3]}
            XmovePerSecCheck = (Target1SecPos[1] - Target2SecPos[1])
            YmovePerSecCheck = (Target1SecPos[3] - Target2SecPos[3])
            --We leave the while-do check after 10 loops (20 seconds) and try collateral damage
            --This can happen if a player try to fool the targetingsystem by circling a unit.
            LoopSaveGuard = LoopSaveGuard + 1
        end
        local MissileImpactTime = 25
        -- Create missile impact corrdinates based on movePerSec * MissileImpactTime
        local MissileImpactX = Target2SecPos[1] - (XmovePerSec * MissileImpactTime)
        local MissileImpactY = Target2SecPos[3] - (YmovePerSec * MissileImpactTime)
        return {MissileImpactX, Target2SecPos[2], MissileImpactY}
    end,

    TEST = function(self, EnemyAntiMissile)
    end,
    RenamePlatoon = function(self, text)
        for k, v in self:GetPlatoonUnits() do
            if v and not v.Dead then
                v:SetCustomName(text..' '..math.floor(GetGameTimeSeconds()))
            end
        end
    end,

}


