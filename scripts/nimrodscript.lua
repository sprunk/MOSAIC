include "createCorpse.lua"
include "lib_OS.lua"
include "lib_UnitScript.lua"
include "lib_Animation.lua"
--include "lib_Build.lua"

TablesOfPiecesGroups = {}
center = piece "center"
base = piece "base"
slider = piece "slider"
turret = piece "turret"
projectile = piece "projectile"
Icon2 = piece "Icon2"
local SIG_AIM_ORBITAL = 1
GameConfig = getGameConfig()
local houseTypeTable = getCultureUnitModelTypes(GameConfig.instance.culture,
                                                "house", UnitDefs)

if not GG.UnitHeldByHouseMap then GG.UnitHeldByHouseMap = {} end

boolBuilding = false
function script.Create()
    Spring.SetUnitBlocking(unitID, false, false, false)
    TablesOfPiecesGroups = getPieceTableByNameGroups(false, true)
    Hide(projectile)
    Move(projectile, z_axis, -210, 0)
    T = foreach(getAllNearUnit(unitID, GameConfig.buildSafeHouseRange * 2),
                function(id)
        if houseTypeTable[Spring.GetUnitDefID(id)] then return id end
    end)

    GG.UnitHeldByHouseMap[unitID] = T[1]
    StartThread(mortallyDependant, unitID, T[1], 15, false, true)
    StartThread(goToFireMode)
    StartThread(modeChangeOS)
end

producedUnits = {}

function script.HitByWeapon(x, z, weaponDefID, damage) end

function modeChangeOS()
    goToFireMode()
    while true do
        buildID = Spring.GetUnitIsBuilding(unitID)
        if buildID then
            boolBuilding = true
            producedUnits[buildID]=  buildID
            StartThread(goToSpaceMode)
            waitTillComplete(builID)
            if doesUnitExistAlive(builID) then
                goToFireMode()
            end
            boolBuilding = false

        end
        Sleep(100)
    end
end

function goToSpaceMode()
    WTurn(turret, x_axis, math.rad(-90), math.pi)
    Move(slider, z_axis, -350, 50)

end

function goToFireMode()
    WMove(slider, z_axis, 0, 50)
    WTurn(turret, x_axis, math.rad(0), math.pi)
end

--- -aimining & fire weapon
function script.AimFromWeapon1() return projectile end

function script.QueryWeapon1() return projectile end

boolOrbitalRailGunAiming = false
function script.AimWeapon1(Heading, pitch)
    -- aiming animation: instantly turn the gun towards the enemy
    if boolBuilding == true then return false end
    if boolOrbitalRailGunAiming == true then return false end

    Turn(center, y_axis, Heading, 0.4)
    Turn(turret, x_axis, -pitch, 0.8)
    WaitForTurns(center, turret)
    return false
end

function script.FireWeapon1() 
    spawnCegNearUnitGround(unitID, "railgunshine")
    return true 
end

--- -aimining & fire weapon
function script.AimFromWeapon2() return Icon2 end

function script.QueryWeapon2() return Icon2 end

function aimOrbital()
    Signal(SIG_AIM_ORBITAL)
    SetSignalMask(SIG_AIM_ORBITAL)
    boolOrbitalRailGunAiming = true
    Sleep(2000)
    boolOrbitalRailGunAiming = false
end

function script.AimWeapon2(Heading, pitch)
    -- aiming animation: instantly turn the gun towards the enemy
    if boolBuilding == true then return false end
    StartThread(aimOrbital)
    Turn(center, y_axis, Heading, 0.4)
    Turn(turret, x_axis, -pitch, 0.8)
    WaitForTurns(center, turret)
    return true
end

function script.FireWeapon2() 
    spawnCegNearUnitGround(unitID, "railgunshine")
return true 
end

function script.StartBuilding() end

function script.StopBuilding() end
function script.Activate()
    SetUnitValue(COB.YARD_OPEN, 1)
    SetUnitValue(COB.BUGGER_OFF, 1)
    SetUnitValue(COB.INBUILDSTANCE, 1)
    return 1
end

function script.Deactivate()
    SetUnitValue(COB.YARD_OPEN, 0)
    SetUnitValue(COB.BUGGER_OFF, 0)
    SetUnitValue(COB.INBUILDSTANCE, 0)
    return 0
end

function script.QueryBuildInfo() return projectile end

Spring.SetUnitNanoPieces(unitID, {projectile})

function script.Killed(recentDamage, _)
    GG.UnitHeldByHouseMap[unitID] = nil
    -- createCorpseCUnitGeneric(recentDamage)
    return 1
end

producedUnits={}
function TurnProducedUnitsOverToTeam(teamID)
    for id, uid in pairs(producedUnits) do
        if doesUnitExistAlive(id) == true then
            transferUnitTeam(id,teamID)
        end
    end
end

boolLocalCloaked = false
function showHideIcon(boolCloaked)
    boolLocalCloaked = boolCloaked
    if boolCloaked == true then
        hideAll(unitID)
        if TablesOfPiecesGroups then showT(TablesOfPiecesGroups["Icon"]) end
    else
        showAll(unitID)
        if TablesOfPiecesGroups then hideT(TablesOfPiecesGroups["Icon"]) end
    end
end
