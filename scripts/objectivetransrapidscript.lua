include "createCorpse.lua"
include "lib_OS.lua"
include "lib_UnitScript.lua"
include "lib_Animation.lua"
--include "lib_Build.lua"

TablesOfPiecesGroups = {}

function script.HitByWeapon(x, z, weaponDefID, damage) end
local trainAxis = x_axis
local maxDistanceTrain = 120000
local trainspeed = 9000
center = piece"center"

function script.Create()
    TablesOfPiecesGroups = getPieceTableByNameGroups(false, true)
    hideT(TablesOfPiecesGroups["Tunnel1_"])
    hideT(TablesOfPiecesGroups["Tunnel2_"])
    StartThread(setup)
end

function setup()
    Sleep(10)
    hideT(TablesOfPiecesGroups["Rail"])
    hideT(TablesOfPiecesGroups["Endstation"])
    StartThread(trainLoop, 1)
    StartThread(trainLoop, 2)
    rVal = math.random(0,360)
    WTurn(center, y_axis, math.rad(rVal),0)
     if validTrackPart( TablesOfPiecesGroups["Rail"][13], TablesOfPiecesGroups["Sub"][1]) then Show(TablesOfPiecesGroups["Endstation"][1]) end
     if validTrackPart( TablesOfPiecesGroups["Rail"][24], TablesOfPiecesGroups["Sub"][2]) then Show(TablesOfPiecesGroups["Endstation"][2]) end

      StartThread(showRail,1, 12)
      StartThread(showRail,14, 23)

    StartThread(deployTunnels, 1)
    StartThread(deployTunnels, 2)
  

end

function showRail(start, ends)

        local xMax = Game.mapSizeX 
        local zMax = Game.mapSizeZ 
    for i=start, ends do 
        id =TablesOfPiecesGroups["Rail"][i]

        x,_,z = Spring.GetUnitPiecePosDir(unitID, id)
        if (not x or not z or  x  <= 0 or x >= xMax or z <= 0 or z >= zMax) then
            return id
        end

            Show(id)
    end
end

function validTrackPart( EndPiece, DetectorPiece)
    Hide(DetectorPiece)
    Hide(EndPiece)
    x,y,z = Spring.GetUnitPiecePosDir(unitID, DetectorPiece)
    gh = Spring.GetGroundHeight(x,z)

    boolUnderground =  gh +10 > y
    boolOutsideMap = (x > Game.mapSizeX or x <= 0) or  (z > Game.mapSizeZ or z <= 0)
    return boolUnderground or boolOutsideMap
end

local boolOldState = false
    function detectRisingEdge(boolActive)
        boolResult = false
        if boolOldState == false and boolActive == true then
            boolResult = true
        end

        return boolResult
    end

    function detectFallingEdge(boolActive)
        boolResult = false
        if boolOldState == true and boolActive == false then
            boolResult = true
        end

        return boolResult
    end

    tunnelMultiple = 5

function deployTunnels(nr)
    boolOldState = false
    Sleep(nr)
detectionPiece = piece("TunnelDetection"..nr) 
tunnelIndex = 1
local xMax = Game.mapSizeX 
local zMax = Game.mapSizeZ 
Hide(detectionPiece)
    for distanceTunnel = maxDistanceTrain, -1*maxDistanceTrain, -32 do
    	WMove(detectionPiece,trainAxis, distanceTunnel, 0)
    	boolAboveGround,x, z = isPieceAboveGround(unitID, detectionPiece, 0)
        if not (not x or not z or  x  <= 0 or x >= xMax or z <= 0 or z >= zMax) then
        --Spring.Echo("Checking tunnel "..nr.." for"..distanceTunnel)
        	if detectRisingEdge(boolAboveGround) or detectFallingEdge(boolAboveGround) then
        		tunnelIndexPiece = piece("Tunnel"..nr.."_"..tunnelIndex)
        		if tunnelIndexPiece then
            		WMove(tunnelIndexPiece, trainAxis, distanceTunnel, 0)
            		Show(tunnelIndexPiece)
                    tunnelIndex = tunnelIndex + 1
                    if tunnelIndex >= 6 then
                     return 
                    end
        		end
        	end
        end
    	boolOldState = boolAboveGround
    end
end

function buildTrain(nr)
    assert(TablesOfPiecesGroups["Train"][nr],nr)
	Show(TablesOfPiecesGroups["Train"][nr])
    indexStart, indexStop =1, 2
    if nr ==1 then 
        indexStart = 1
        indexStop = 4
    elseif nr == 2 then
        indexStart = 5
        indexStop = 8
    end

    for i=indexStart,indexStop do
        if maRa() == true then 
            Show(TablesOfPiecesGroups["Container"][i])
        end
    end

end

function hideTrain(nr)
    assert(TablesOfPiecesGroups["Train"][nr],nr)
	Hide(TablesOfPiecesGroups["Train"][nr])
        indexStart, indexStop =1, 2
    if nr ==1 then 
        indexStart = 1
        indexStop = 4
    elseif nr == 2 then
        indexStart = 5
        indexStop = 8
    end

    for i=indexStart,indexStop do        
        Hide(TablesOfPiecesGroups["Container"][i])
    end
end

function trainLoop(nr)
	rSleepValue = math.random(1,100)*100
	Sleep(rSleepValue)
	local train = piece("Train"..nr)

	while true do
        direction = randSign()
        WMove(train, trainAxis, maxDistanceTrain*direction, 0)
		buildTrain(nr)
		WMove(train, trainAxis, 0, trainspeed)
		breakTime = math.random(0,10)*1000
		Sleep(breakTime)
        buildTrain(nr)
    	WMove(train, trainAxis, maxDistanceTrain*direction*-1, trainspeed)
        hideTrain(nr)
		betweenInterval = math.random(0,3)*60*1000+1
		Sleep(betweenInterval)
	end
end


function script.Killed(recentDamage, _)
    return 1
end
