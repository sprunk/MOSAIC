-- $Id$
--------------------------------------------------------------------------------
--------------------------------------------------------------------------------
--
--  author:  jK
--
--  Copyright (C) 2008,2009,2010.
--  Licensed under the terms of the GNU GPL, v2 or later.
--
--------------------------------------------------------------------------------
--------------------------------------------------------------------------------
function gadget:GetInfo()
    return {
        name = "CustomUnitShaders",
        desc = "allows to override the engine unit and feature shaders",
        author = "jK, gajop",
        date = "2008,2009,2010,2016",
        license = "GNU GPL, v2 or later",
        layer = 1,
        enabled = true --  loaded by default?
    }
end
if Spring.Utilities and Spring.Utilities.IsCurrentVersionNewerThan and
    Spring.Utilities.IsCurrentVersionNewerThan(100, 0) then return end
--------------------------------------------------------------------------------
--------------------------------------------------------------------------------
-- Synced
--------------------------------------------------------------------------------
--------------------------------------------------------------------------------

if (gadgetHandler:IsSyncedCode()) then return end

--------------------------------------------------------------------------------
--------------------------------------------------------------------------------
-- Unsynced
--------------------------------------------------------------------------------
--------------------------------------------------------------------------------

if (not gl.CreateShader) then return false end

--------------------------------------------------------------------------------
--------------------------------------------------------------------------------

VFS.Include("luarules/utilities/UnitRendering.lua", nil, VFS.ZIP)
VFS.Include("scripts/lib_UnitScript.lua")
VFS.Include("scripts/lib_Build.lua")
VFS.Include("scripts/lib_mosaic.lua")

local LuaShader = VFS.Include("LuaRules/Gadgets/Include/LuaShader.lua")

--------------------------------------------------------------------------------
--------------------------------------------------------------------------------

local MATERIALS_DIR = "materials/"

--------------------------------------------------------------------------------
--------------------------------------------------------------------------------

local shadows = false
local advShading = false
local normalmapping = (tonumber(Spring.GetConfigInt("NormalMapping", 1) or 1) ==
                          1)
local treewind = tonumber(Spring.GetConfigInt("TreeWind", 1) or 1) == 1
local sunChanged = true

local idToDefID = {}

local unitRendering = {
    drawList = {},
    materialInfos = {},
    bufMaterials = {},
    materialDefs = {},
    loadedTextures = {},

    ObjectDefNames = UnitDefNames,

    spGetAllObjects = Spring.GetAllUnits,
    spGetObjectPieceList = Spring.GetUnitPieceList,

    spGetMaterial = Spring.UnitRendering.GetMaterial,
    spSetMaterial = Spring.UnitRendering.SetMaterial,
    spActivateMaterial = Spring.UnitRendering.ActivateMaterial,
    spDeactivateMaterial = Spring.UnitRendering.DeactivateMaterial,
    spSetObjectLuaDraw = Spring.UnitRendering.SetUnitLuaDraw,
    spSetLODCount = Spring.UnitRendering.SetLODCount,
    spSetPieceList = Spring.UnitRendering.SetPieceList,

    DrawObject = "DrawUnit",
    ObjectCreated = "UnitCreated",
    ObjectDestroyed = "UnitDestroyed"
}

local featureRendering = {
    drawList = {},
    materialInfos = {},
    bufMaterials = {},
    materialDefs = {},
    loadedTextures = {},

    ObjectDefNames = FeatureDefNames,

    spGetAllObjects = Spring.GetAllFeatures,
    spGetObjectPieceList = Spring.GetFeaturePieceList,

    spGetMaterial = Spring.FeatureRendering.GetMaterial,
    spSetMaterial = Spring.FeatureRendering.SetMaterial,
    spActivateMaterial = Spring.FeatureRendering.ActivateMaterial,
    spDeactivateMaterial = Spring.FeatureRendering.DeactivateMaterial,
    spSetObjectLuaDraw = Spring.FeatureRendering.SetFeatureLuaDraw,
    spSetLODCount = Spring.FeatureRendering.SetLODCount,
    spSetPieceList = Spring.FeatureRendering.SetPieceList,

    DrawObject = "DrawFeature",
    ObjectCreated = "FeatureCreated",
    ObjectDestroyed = "FeatureDestroyed"
}

local allRendering = {unitRendering, featureRendering}

--------------------------------------------------------------------------------
--------------------------------------------------------------------------------

local _plugins = nil
local function InsertPlugin(str)
    -- str = str:upper()
    return (_plugins and _plugins[str]) or ""
end

local function CompileShader(shader, definitions, plugins, addName)
    shader.vertexOrig = shader.vertex
    shader.fragmentOrig = shader.fragment
    shader.geometryOrig = shader.geometry

    -- // insert small pieces of code named `plugins`
    -- // this way we can use a basic shader and add some simple vertex animations etc.
    do
        if (plugins) then _plugins = plugins end

        if (shader.vertex) then
            shader.vertex = shader.vertex:gsub("%%%%([%a_]+)%%%%", InsertPlugin);
        end
        if (shader.fragment) then
            shader.fragment = shader.fragment:gsub("%%%%([%a_]+)%%%%",
                                                   InsertPlugin);
        end
        if (shader.geometry) then
            shader.geometry = shader.geometry:gsub("%%%%([%a_]+)%%%%",
                                                   InsertPlugin);
        end

        _plugins = nil
    end

    -- // append definitions at top of the shader code
    -- // (this way we can modularize a shader and enable/disable features in it)
    if (definitions or shadows) then
        definitions = definitions or {}
        hasVersion = false
        for _, def in pairs(definitions) do
            hasVersion = hasVersion or
                             string.sub(def, 1, string.len("#version")) ==
                             "#version"
        end
        if not hasVersion then
            table.insert(definitions, 1, "#version 150 compatibility")
        end
        if (shadows) then
            table.insert(definitions, "#define use_shadows")
        end
        definitions = table.concat(definitions, "\n") .. "\n"
        if (shader.vertex) then
            shader.vertex = definitions .. shader.vertex;
        end
        if (shader.fragment) then
            shader.fragment = definitions .. shader.fragment;
        end
        if (shader.geometry) then
            shader.geometry = definitions .. shader.geometry;
        end
    end

    local luaShader = LuaShader(shader, "Custom Unit Shaders. " .. addName)
    luaShader:Initialize()

    shader.vertex = shader.vertexOrig
    shader.fragment = shader.fragmentOrig
    shader.geometry = shader.geometryOrig

    return luaShader
end

local function _CompileMaterialShaders(rendering)
    for matName, mat_src in pairs(rendering.materialDefs) do
        if mat_src.shaderSource then
            local luaShader = CompileShader(mat_src.shaderSource,
                                            mat_src.shaderDefinitions,
                                            mat_src.shaderPlugins,
                                            string.format("MatName: \"%s\"(%s)",
                                                          matName, "Standard"))

            if luaShader then
                if mat_src.standardShader then
                    if mat_src.standardShaderObj then
                        mat_src.standardShaderObj:Finalize()
                    else
                        gl.DeleteShader(mat_src.standardShader)
                    end
                end
                mat_src.standardShaderObj = luaShader
                mat_src.standardShader = luaShader:GetHandle()
                luaShader:SetUnknownUniformIgnore(true)
                luaShader:ActivateWith(function()
                    mat_src.standardUniforms =
                        {
                            cameraloc = luaShader:GetUniformLocation("camera"),
                            camerainvloc = luaShader:GetUniformLocation(
                                "cameraInv"),
                            cameraposloc = luaShader:GetUniformLocation(
                                "cameraPos"),
                            shadowmatrixloc = luaShader:GetUniformLocation(
                                "shadowMatrix"),
                            shadowparamsloc = luaShader:GetUniformLocation(
                                "shadowParams"),
                            sunposloc = luaShader:GetUniformLocation("sunPos"),
                            simframeloc = luaShader:GetUniformLocation(
                                "simFrame")
                        }
                end)
                luaShader:SetActiveStateIgnore(true)
            end
        end

        if (mat_src.deferredSource) then
            local luaShader = CompileShader(mat_src.deferredSource,
                                            mat_src.deferredDefinitions,
                                            mat_src.deferredPlugins,
                                            string.format("MatName: \"%s\"(%s)",
                                                          matName, "Deferred"))

            if luaShader then
                if mat_src.deferredShader then
                    if mat_src.deferredShaderObj then
                        mat_src.deferredShaderObj:Finalize()
                    else
                        gl.DeleteShader(mat_src.deferredShader)
                    end
                end
                mat_src.deferredShaderObj = luaShader
                mat_src.deferredShader = luaShader:GetHandle()
                luaShader:SetUnknownUniformIgnore(true)
                luaShader:ActivateWith(function()
                    mat_src.deferredUniforms =
                        {
                            cameraloc = luaShader:GetUniformLocation("camera"),
                            camerainvloc = luaShader:GetUniformLocation(
                                "cameraInv"),
                            cameraposloc = luaShader:GetUniformLocation(
                                "cameraPos"),
                            shadowmatrixloc = luaShader:GetUniformLocation(
                                "shadowMatrix"),
                            shadowparamsloc = luaShader:GetUniformLocation(
                                "shadowParams"),
                            sunposloc = luaShader:GetUniformLocation("sunPos"),
                            simframeloc = luaShader:GetUniformLocation(
                                "simFrame")
                        }
                end)
                luaShader:SetActiveStateIgnore(true)
            end
        end
    end
end

local function CompileMaterialShaders()
    for _, rendering in ipairs(allRendering) do
        _CompileMaterialShaders(rendering)
    end
end
--------------------------------------------------------------------------------
--------------------------------------------------------------------------------

local function GetObjectMaterial(rendering, objectDefID)
    local mat = rendering.bufMaterials[objectDefID]
    if mat then return mat end

    local matInfo = rendering.materialInfos[objectDefID]
    local mat = rendering.materialDefs[matInfo[1]]

    if type(objectDefID) == "number" then
        -- Non-number objectDefIDs are default material overrides. They will have
        -- their textures defined in the unit materials files.
        matInfo.UNITDEFID = objectDefID
        matInfo.FEATUREDEFID = -objectDefID
    end

    -- // find unitdef tex keyword and replace it
    -- // (a shader can be just for multiple unitdefs, so we support this keywords)
    local texUnits = {}
    for texid, tex in pairs(mat.texunits or {}) do
        local tex_ = tex
        for varname, value in pairs(matInfo) do
            tex_ = tex_:gsub("%%" .. tostring(varname), value)
        end
        texUnits[texid] = {tex = tex_, enable = false}
    end

    -- // materials don't load those textures themselves
    if (texUnits[1]) then
        local texdl = gl.CreateList(function()
            for _, tex in pairs(texUnits) do
                local prefix = tex.tex:sub(1, 1)
                if (prefix ~= "%") and (prefix ~= "#") and (prefix ~= "!") and
                    (prefix ~= "$") then
                    gl.Texture(tex.tex)
                    rendering.loadedTextures[#rendering.loadedTextures + 1] =
                        tex.tex
                end
            end
        end)
        gl.DeleteList(texdl)
    end

    local luaMat = rendering.spGetMaterial("opaque", {
        standardshader = mat.standardShader,
        deferredshader = mat.deferredShader,

        standarduniforms = mat.standardUniforms,
        deferreduniforms = mat.deferredUniforms,

        usecamera = mat.usecamera,
        culling = mat.culling,
        texunits = texUnits,
        prelist = mat.predl,
        postlist = mat.postdl
    })

    rendering.bufMaterials[objectDefID] = luaMat

    return luaMat
end

--------------------------------------------------------------------------------
--------------------------------------------------------------------------------

local function ResetUnit(unitID)
    local unitDefID = Spring.GetUnitDefID(unitID)
    gadget:RenderUnitDestroyed(unitID, unitDefID)
    Spring.UnitRendering.DeactivateMaterial(unitID, 3)
    if not select(3, Spring.GetUnitIsStunned(unitID)) then -- // inbuild?
        gadget:UnitFinished(unitID, unitDefID)
    end
end

local function ResetFeature(featureID)
    gadget:FeatureDestroyed(featureID)
    Spring.FeatureRendering.DeactivateMaterial(featureID, 3)
    gadget:FeatureCreated(featureID)
end

local function ToggleShadows()
    shadows = Spring.HaveShadows()

    CompileMaterialShaders()

    unitRendering.bufMaterials = {}
    local units = Spring.GetAllUnits()
    for i = 1, #units do ResetUnit(units[i]) end

    featureRendering.bufMaterials = {}
    local features = Spring.GetAllFeatures()
    for i = 1, #features do ResetFeature(features[i]) end
end

local function ToggleAdvShading()
    advShading = Spring.HaveAdvShading()

    if (not advShading) then
        -- // unload all materials
        unitRendering.drawList = {}
        local units = Spring.GetAllUnits()
        for i = 1, #units do ResetUnit(units[i]) end

        featureRendering.drawList = {}
        local features = Spring.GetAllFeatures()
        for i = 1, #features do ResetFeature(features[i]) end
    elseif (normalmapping) then
        -- // reinitializes all shaders
        ToggleShadows()
    end
end

local n = -1
function gadget:Update()
    if (n < Spring.GetDrawFrame()) then
        n = Spring.GetDrawFrame() + Spring.GetFPS()

        if (advShading ~= Spring.HaveAdvShading()) then
            ToggleAdvShading()
        elseif advShading and normalmapping and shadows ~= Spring.HaveShadows() then
            ToggleShadows()
        end
    end
end

function gadget:SunChanged() sunChanged = true end

--------------------------------------------------------------------------------
--------------------------------------------------------------------------------

local function GetShaderOverride(objectID, objectDefID)
    if Spring.ValidUnitID(objectID) then
        return Spring.GetUnitRulesParam(objectID, "comm_texture")
    end
    return false
end

function ObjectFinished(rendering, objectID, objectDefID)
    if not advShading then return end

    objectDefID = GetShaderOverride(objectID, objectDefID) or objectDefID
    local objectMat = rendering.materialInfos[objectDefID]
    if objectMat then
        local mat = rendering.materialDefs[objectMat[1]]
        if (normalmapping or mat.force) then
            rendering.spActivateMaterial(objectID, 3)
            rendering.spSetMaterial(objectID, 3, "opaque",
                                    GetObjectMaterial(rendering, objectDefID))
            for pieceID in
                ipairs(rendering.spGetObjectPieceList(objectID) or {}) do
                rendering.spSetPieceList(objectID, 3, pieceID)
            end
            local DrawObject = mat[rendering.DrawObject]
            local ObjectCreated = mat[rendering.ObjectCreated]
            if DrawObject then
                rendering.spSetObjectLuaDraw(objectID, true)
                rendering.drawList[objectID] = mat
            end
            if ObjectCreated then ObjectCreated(objectID, mat, 3) end
        end
    end
end

iconTypeTable = getIconTypes(UnitDefs)
iconUnit = {}
function gadget:UnitCreated(unitID, unitDefID)
    if iconTypeTable[unitDefID] then
        iconUnit[unitID] = unitDefID
        spSetObjectLuaDraw(unitID, true)
    end
end

function gadget:UnitDestroyed(unitID, unitDefID)
    if iconUnit[unitID] then
        iconUnit[unitID] = nil
        spSetObjectLuaDraw(unitID, true)
    end
end

function gadget:UnitFinished(unitID, unitDefID)
    idToDefID[unitID] = unitDefID
    ObjectFinished(unitRendering, unitID, unitDefID)
end

function gadget:FeatureCreated(featureID)
    idToDefID[-featureID] = Spring.GetFeatureDefID(featureID)
    ObjectFinished(featureRendering, featureID, idToDefID[-featureID])
end

function ObjectDestroyed(rendering, objectID, objectDefID)
    rendering.spDeactivateMaterial(objectID, 3)

    local mat = rendering.drawList[objectID]
    if mat then
        local _ObjectDestroyed = mat[rendering.ObjectDestroyed]
        if _ObjectDestroyed then _ObjectDestroyed(objectID, 3) end
        rendering.drawList[objectID] = nil
    end
end

function gadget:RenderUnitDestroyed(unitID, unitDefID)
    idToDefID[unitID] = nil -- not really required
    ObjectDestroyed(unitRendering, unitID, unitDefID)
end

function gadget:FeatureDestroyed(featureID)
    idToDefID[-featureID] = nil -- not really required
    ObjectDestroyed(featureRendering, featureID,
                    Spring.GetFeatureDefID(featureID))
end

function gadget:DrawGenesis()
    for _, rendering in ipairs(allRendering) do
        for _, mat in pairs(rendering.materialDefs) do
            local SunChangedFunc = (sunChanged and mat.SunChanged) or nil
            local DrawGenesisFunc = mat.DrawGenesis

            if SunChangedFunc or DrawGenesisFunc then
                if mat.standardShaderObj then
                    mat.standardShaderObj:ActivateWith(
                        function()
                            if SunChangedFunc then
                                SunChangedFunc(mat.standardShaderObj)
                            end
                            if DrawGenesisFunc then
                                DrawGenesisFunc(mat.standardShaderObj)
                            end
                        end)
                end
                if mat.deferredShaderObj then
                    mat.deferredShaderObj:ActivateWith(
                        function()
                            if SunChangedFunc then
                                SunChangedFunc(mat.deferredShaderObj)
                            end
                            if DrawGenesisFunc then
                                DrawGenesisFunc(mat.deferredShaderObj)
                            end
                        end)
                end
            end
        end
    end

    if sunChanged then sunChanged = false end
end

local function DrawObject(rendering, objectID, objectDefID, drawMode)
    if iconUnit[objectID] and drawMode == shadowDraw then return false end

    local mat = rendering.drawList[objectID]
    if not mat then return end

    local luaShaderObj = (drawMode == 5) and mat.deferredShaderObj or
                             mat.standardShaderObj
    local _DrawObject = mat[rendering.DrawObject]
    if _DrawObject then
        return _DrawObject(objectID, objectDefID, mat, drawMode, luaShaderObj)
    end
end

---------------------------
-- DrawUnit(unitID,DrawMode)
-- With enum DrawMode {
-- notDrawing = 0,
-- normalDraw = 1,
-- shadowDraw = 2,
-- reflectionDraw = 3,
-- refractionDraw = 4,
-- gameDeferredDraw = 5,
-- };
-----------------

function gadget:DrawUnit(unitID, drawMode)
    return DrawObject(unitRendering, unitID, idToDefID[unitID], drawMode)
end

function gadget:DrawFeature(featureID, drawMode)
    return DrawObject(featureRendering, featureID, idToDefID[-featureID],
                      drawMode)
end
gadget.UnitReverseBuilt = gadget.RenderUnitDestroyed
gadget.UnitCloaked = gadget.RenderUnitDestroyed
gadget.UnitDecloaked = gadget.UnitFinished

-- NOTE: No feature equivalent (features can't change team)
function gadget:UnitGiven(unitID, ...)
    if not select(3, Spring.GetUnitIsStunned(unitID)) then
        gadget:RenderUnitDestroyed(unitID, ...)
        gadget:UnitFinished(unitID, ...)
    end
end

--------------------------------------------------------------------------------
--------------------------------------------------------------------------------

function gadget:GameFrame()
    for _, uid in ipairs(Spring.GetAllUnits()) do
        if not select(3, Spring.GetUnitIsStunned(uid)) then -- // inbuild?
            gadget:UnitFinished(uid, Spring.GetUnitDefID(uid),
                                Spring.GetUnitTeam(uid))
        end
    end
    for _, fid in ipairs(Spring.GetAllFeatures()) do
        gadget:FeatureCreated(fid, Spring.GetFeatureDefID(fid),
                              Spring.GetFeatureTeam(fid))
    end
    gadgetHandler:RemoveCallIn('GameFrame')
end

-- // Workaround: unsynced LuaRules doesn't receive Shutdown events
Shutdown = Script.CreateScream()

local function _CleanupTextures(rendering)
    for i = 1, #rendering.loadedTextures do
        gl.DeleteTexture(rendering.loadedTextures[i])
    end
    for _, oid in ipairs(rendering.spGetAllObjects()) do
        rendering.spSetLODCount(oid, 0)
    end
end

Shutdown.func = function()
    -- // unload textures, so the user can do a `/luarules reload` to reload the normalmaps
    for _, rendering in ipairs(allRendering) do _CleanupTextures(rendering) end
end

local function _LoadMaterialConfigFiles(path)
    local unitMaterialDefs = {}
    local featureMaterialDefs = {}

    local files = VFS.DirList(path)
    table.sort(files)

    for i = 1, #files do
        local mats, unitMats = VFS.Include(files[i])

        for k, v in pairs(mats) do
            -- Spring.Echo(files[i],'is a feature?',v.feature)
            local rendering
            if v.feature then
                rendering = featureRendering
            else
                rendering = unitRendering
            end
            if not rendering.materialDefs[k] then
                rendering.materialDefs[k] = v
            end
        end
        for k, v in pairs(unitMats) do
            -- // we check if the material is defined as a unit or as feature material (one namespace for both!!)
            local materialDefs
            if featureRendering.materialDefs[v[1]] then
                materialDefs = featureMaterialDefs
            else
                materialDefs = unitMaterialDefs
            end
            if not materialDefs[k] then materialDefs[k] = v end
        end
    end
    return unitMaterialDefs, featureMaterialDefs
end

local function _ProcessMaterials(rendering, materialDefs)
    local engineShaderTypes = {"3do", "s3o", "obj", "ass"}
    for _, mat_src in pairs(rendering.materialDefs) do
        -- mat_src = {shader = include(".../default.lua") or "s3o", ...}
        if mat_src.shader ~= nil and engineShaderTypes[mat_src.shader] == nil then
            mat_src.shaderSource = mat_src.shader
            mat_src.shader = nil
        end
        if mat_src.deferred ~= nil and engineShaderTypes[mat_src.deferred] ==
            nil then
            mat_src.deferredSource = mat_src.deferred
            mat_src.deferred = nil
        end
    end

    _CompileMaterialShaders(rendering)

    for objectName, materialInfo in pairs(materialDefs) do
        if (type(materialInfo) ~= "table") then
            materialInfo = {materialInfo}
        end
        rendering.materialInfos[(rendering.ObjectDefNames[objectName] or
            {id = -1}).id] = materialInfo
    end
end

function ToggleTreeWind(_, newSetting, _, playerID)
    if (playerID ~= Spring.GetMyPlayerID()) then return end
    if newSetting and newSetting ~= "" then
        treewind = (newSetting == "1")
    elseif not newSetting or newSetting == "" then
        treewind = not treewind
    end
    Spring.SetConfigInt("TreeWind", (treewind and 1) or 0)
    if Spring.GetGameFrame() > 1000 then
        Spring.Echo("TreeWind is " .. (treewind and "enabled" or "disabled"))
    end

    -- // unload normalmapped materials
    local features = Spring.GetAllFeatures()
    for _, featureID in pairs(features) do
        local featureDefID = Spring.GetFeatureDefID(featureID)
        local featureMat = featureRendering.materialInfos[featureDefID]
        if (featureMat) then
            gadget:FeatureDestroyed(featureID, featureDefID)
        end
    end

    -- reset
    featureRendering.drawList = {}
    featureRendering.materialInfos = {}
    featureRendering.bufMaterials = {}
    featureRendering.materialDefs = {}
    featureRendering.loadedTextures = {}

    -- // load the materials config files
    local unitMaterialDefs, featureMaterialDefs =
        _LoadMaterialConfigFiles(MATERIALS_DIR)
    _ProcessMaterials(featureRendering, featureMaterialDefs)

    local features = Spring.GetAllFeatures()
    for _, featureID in pairs(features) do
        local featureDefID = Spring.GetFeatureDefID(featureID)
        local featureMat = featureRendering.materialInfos[featureDefID]
        if (featureMat) then
            gadget:FeatureCreated(featureID, featureDefID)
        end
    end
end

function Reload()
    -- // unload normalmapped materials
    local features = Spring.GetAllFeatures()
    for _, featureID in pairs(features) do
        local featureDefID = Spring.GetFeatureDefID(featureID)
        local featureMat = featureRendering.materialInfos[featureDefID]
        if (featureMat) then
            local mat = featureRendering.materialDefs[featureMat[1]]
            if (not mat.force) then
                gadget:FeatureDestroyed(featureID, featureDefID)
            end
        end
    end
    -- // unload normalmapped materials
    local units = Spring.GetAllUnits()
    for _, unitID in pairs(units) do
        local unitDefID = Spring.GetUnitDefID(unitID)
        local unitMat = unitRendering.materialInfos[unitDefID]
        if (unitMat) then
            local mat = unitRendering.materialDefs[unitMat[1]]
            if (not mat.force) then
                gadget:RenderUnitDestroyed(unitID, unitDefID)
            end
        end
    end

    -- reset
    unitRendering.drawList = {}
    unitRendering.materialInfos = {}
    unitRendering.bufMaterials = {}
    unitRendering.materialDefs = {}
    unitRendering.loadedTextures = {}
    featureRendering.drawList = {}
    featureRendering.materialInfos = {}
    featureRendering.bufMaterials = {}
    featureRendering.materialDefs = {}
    featureRendering.loadedTextures = {}

    -- // load the materials config files
    local unitMaterialDefs, featureMaterialDefs =
        _LoadMaterialConfigFiles(MATERIALS_DIR)
    _ProcessMaterials(unitRendering, unitMaterialDefs)
    _ProcessMaterials(featureRendering, featureMaterialDefs)

    local features = Spring.GetAllFeatures()
    for _, featureID in pairs(features) do
        local featureDefID = Spring.GetFeatureDefID(featureID)
        local featureMat = featureRendering.materialInfos[featureDefID]
        if (featureMat) then
            local mat = featureRendering.materialDefs[featureMat[1]]
            if (not mat.force) then
                gadget:FeatureCreated(featureID, featureDefID)
            end
        end
    end
    -- // load normalmapped materials
    local units = Spring.GetAllUnits()
    for _, unitID in pairs(units) do
        local unitDefID = Spring.GetUnitDefID(unitID)
        local unitMat = unitRendering.materialInfos[unitDefID]
        if (unitMat) then
            local mat = unitRendering.materialDefs[unitMat[1]]
            if (not mat.force) then
                gadget:UnitFinished(unitID, unitDefID)
            end
        end
    end
end

function UpdateSun(_, newSetting, _, playerID) sunChanged = true end

function ReloadShaders(_, newSetting, _, playerID) Reload() end

function ToggleNormalmapping(_, newSetting, _, playerID)
    if (playerID ~= Spring.GetMyPlayerID()) then return end

    if newSetting and newSetting ~= "" then
        normalmapping = (newSetting == "1")
    elseif not newSetting or newSetting == "" then
        normalmapping = not normalmapping
    end

    Spring.SetConfigInt("NormalMapping", (normalmapping and 1) or 0)
    Spring.Echo("normalmapping is " ..
                    (normalmapping and "enabled" or "disabled"))

    Reload()
end

function gadget:Initialize()
    Spring.Echo(GetInfo().name .. " Initialization started")
    -- // check user configs
    shadows = Spring.HaveShadows()
    advShading = Spring.HaveAdvShading()

    -- // load the materials config files
    local unitMaterialDefs, featureMaterialDefs =
        _LoadMaterialConfigFiles(MATERIALS_DIR)
    -- Spring.Echo('unitMaterialDefs',to_string(unitMaterialDefs))
    -- Spring.Echo('featureMaterialDefs',to_string(featureMaterialDefs))
    -- // process the materials (compile shaders, load textures, ...)
    _ProcessMaterials(unitRendering, unitMaterialDefs)
    _ProcessMaterials(featureRendering, featureMaterialDefs)

    -- // insert synced actions

    gadgetHandler:AddSyncAction("unitshaders_reverse", UnitReverseBuilt)
    gadgetHandler:AddChatAction("normalmapping", ToggleNormalmapping)
    gadgetHandler:AddChatAction("treewind", ToggleTreeWind)
    gadgetHandler:AddChatAction("reloadshaders", ReloadShaders)
    gadgetHandler:AddChatAction("updatesun", UpdateSun)
    Spring.Echo(GetInfo().name .. " Initialization ended")
end

function to_string(data, indent)
    local str = ""

    if (indent == nil) then indent = 0 end

    -- Check the type
    if (type(data) == "string") then
        str = str .. ("    "):rep(indent) .. data .. "\n"
    elseif (type(data) == "number") then
        str = str .. ("    "):rep(indent) .. data .. "\n"
    elseif (type(data) == "boolean") then
        if (data == true) then
            str = str .. "true"
        else
            str = str .. "false"
        end
    elseif (type(data) == "table") then
        local i, v
        for i, v in pairs(data) do
            -- Check for a table in a table
            if (type(v) == "table") then
                str = str .. ("    "):rep(indent) .. i .. ":\n"
                str = str .. to_string(v, indent + 2)
            else
                str = str .. ("    "):rep(indent) .. i .. ": " ..
                          to_string(v, 0)
            end
        end
    elseif (data == nil) then
        str = str .. 'nil'
    else
        -- print_debug(1, "Error: unknown data type: %s", type(data))
        str = str .. "Error: unknown data type:" .. type(data)
        Spring.Echo('X data type')
    end

    return str
end
