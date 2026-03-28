local isCapturing       = false
local isBrowsing        = false
local isPaused          = false
local isCancelled       = false
local isPreview         = false
local captureCamera     = nil
local captureGender     = 'male'
local captureRotOffset  = 0.0
local savedCameraAngles = {}
local activePreviewCamera = nil

local pedAppearance = {
    model = nil, coords = nil, heading = nil,
    components = {}, props = {},
    headBlend = nil, faceFeatures = {}, headOverlays = {},
}

-- HELPERS

local function HideHUD(state)
    DisplayRadar(not state)
    DisplayHud(not state)
end

local function SuppressWorld()
    SetVehicleDensityMultiplierThisFrame(0.0)
    SetPedDensityMultiplierThisFrame(0.0)
    SetRandomVehicleDensityMultiplierThisFrame(0.0)
    SetParkedVehicleDensityMultiplierThisFrame(0.0)
    SetScenarioPedDensityMultiplierThisFrame(0.0, 0.0)
    SetGarbageTrucks(false)
    SetRandomBoats(false)
    SetRandomTrains(false)
end

local function GetPedGender(ped)
    return (GetEntityModel(ped) == GetHashKey('mp_m_freemode_01')) and 'male' or 'female'
end

local function LoadModel(modelHash)
    RequestModel(modelHash)
    local timeout = GetGameTimer() + 5000
    while not HasModelLoaded(modelHash) and GetGameTimer() < timeout do
        Wait(10)
    end
    return HasModelLoaded(modelHash)
end

-- CAPTURE CAMERA

local function CreateCaptureCamera(ped, preset, presetName)
    local pedPos = GetEntityCoords(ped)
    local saved  = presetName and savedCameraAngles[presetName]
    local camX, camY, camZ, fov

    if saved then
        camX = pedPos.x + saved.dist * math.sin(saved.angleH)
        camY = pedPos.y - saved.dist * math.cos(saved.angleH)
        camZ = pedPos.z + preset.zPos + saved.dist * math.sin(saved.angleV)
        fov  = saved.fov or preset.fov
    else
        local rotZ = preset.rotation.z + captureRotOffset
        SetEntityRotation(ped, preset.rotation.x, preset.rotation.y, rotZ, 2, false)
        Wait(50)
        local fwd = GetEntityForwardVector(ped)
        local dist = preset.dist or 1.2
        camX = pedPos.x - fwd.x * dist
        camY = pedPos.y - fwd.y * dist
        camZ = pedPos.z - fwd.z + preset.zPos
        fov  = preset.fov
    end

    local cam = CreateCamWithParams('DEFAULT_SCRIPTED_CAMERA', camX, camY, camZ, 0.0, 0.0, 0.0, fov, false, 0)
    PointCamAtCoord(cam, pedPos.x, pedPos.y, pedPos.z + preset.zPos)
    SetCamActive(cam, true)
    RenderScriptCams(true, false, 0, true, true)
    return cam
end

local function DestroyCamera()
    if captureCamera then
        RenderScriptCams(false, false, 0, true, true)
        DestroyCam(captureCamera, false)
        captureCamera = nil
    end
end

-- GREEN SCREEN + STUDIO LIGHTING

local function DrawQuad(x1,y1,z1, x2,y2,z2, x3,y3,z3, x4,y4,z4, r,g,b,a)
    DrawPoly(x1,y1,z1, x2,y2,z2, x3,y3,z3, r,g,b,a)
    DrawPoly(x3,y3,z3, x4,y4,z4, x1,y1,z1, r,g,b,a)
    DrawPoly(x3,y3,z3, x2,y2,z2, x1,y1,z1, r,g,b,a)
    DrawPoly(x1,y1,z1, x4,y4,z4, x3,y3,z3, r,g,b,a)
end

local function DrawGreenScreenAndLights(ped)
    local pos = GetEntityCoords(ped)
    local gs  = Customize.GreenScreen
    local r, g, b = gs.color.r, gs.color.g, gs.color.b

    local hw = gs.width  * 0.5
    local hd = gs.depth  * 0.5
    local fz = pos.z + gs.floorOffset
    local cz = fz + gs.height

    local x1, y1 = pos.x - hw, pos.y - hd
    local x2, y2 = pos.x + hw, pos.y - hd
    local x3, y3 = pos.x - hw, pos.y + hd
    local x4, y4 = pos.x + hw, pos.y + hd

    DrawQuad(x1,y1,fz, x2,y2,fz, x2,y2,cz, x1,y1,cz, r,g,b,255)
    DrawQuad(x4,y4,fz, x3,y3,fz, x3,y3,cz, x4,y4,cz, r,g,b,255)
    DrawQuad(x3,y3,fz, x1,y1,fz, x1,y1,cz, x3,y3,cz, r,g,b,255)
    DrawQuad(x2,y2,fz, x4,y4,fz, x4,y4,cz, x2,y2,cz, r,g,b,255)
    DrawQuad(x1,y1,fz, x2,y2,fz, x4,y4,fz, x3,y3,fz, r,g,b,255)
    DrawQuad(x3,y3,cz, x4,y4,cz, x2,y2,cz, x1,y1,cz, r,g,b,255)

    for _, light in ipairs(Customize.StudioLights) do
        DrawLightWithRange(
            pos.x + light.offset.x,
            pos.y + light.offset.y,
            pos.z + light.offset.z,
            255, 255, 255,
            light.range,
            light.intensity
        )
    end
end

-- CROP OVERLAY (preview only — shows what area will be in the final image)

local cropBars = nil

local function ComputeCropBars()
    local tw = Customize.ScreenshotWidth or 0
    local th = Customize.ScreenshotHeight or 0
    if tw <= 0 or th <= 0 then cropBars = false return end

    local sw, sh = GetActiveScreenResolution()
    local screenAspect = sw / sh
    local targetAspect = tw / th

    if screenAspect > targetAspect then
        local barW = (1.0 - targetAspect / screenAspect) / 2.0
        cropBars = { mode = 'v', x1 = barW / 2.0, x2 = 1.0 - barW / 2.0, size = barW }
    elseif screenAspect < targetAspect then
        local barH = (1.0 - screenAspect / targetAspect) / 2.0
        cropBars = { mode = 'h', y1 = barH / 2.0, y2 = 1.0 - barH / 2.0, size = barH }
    else
        cropBars = false
    end
end

local function DrawCropOverlay()
    if cropBars == nil then ComputeCropBars() end
    if not cropBars then return end

    if cropBars.mode == 'v' then
        DrawRect(cropBars.x1, 0.5, cropBars.size, 1.0, 0, 0, 0, 150)
        DrawRect(cropBars.x2, 0.5, cropBars.size, 1.0, 0, 0, 0, 150)
    else
        DrawRect(0.5, cropBars.y1, 1.0, cropBars.size, 0, 0, 0, 150)
        DrawRect(0.5, cropBars.y2, 1.0, cropBars.size, 0, 0, 0, 150)
    end
end

-- ORBIT CAMERA

local orbitCam      = nil
local orbitAngleH   = 0.0
local orbitAngleV   = 0.0
local orbitDist     = 1.2
local orbitCenter   = vector3(0.0, 0.0, 0.0)
local orbitFov      = 40.0
local orbitBaseDist = 1.2

local function UpdateOrbitCamera()
    if not orbitCam then return end
    local camX = orbitCenter.x + orbitDist * math.sin(orbitAngleH)
    local camY = orbitCenter.y - orbitDist * math.cos(orbitAngleH)
    local camZ = orbitCenter.z + orbitDist * math.sin(orbitAngleV)
    SetCamCoord(orbitCam, camX, camY, camZ)
    PointCamAtCoord(orbitCam, orbitCenter.x, orbitCenter.y, orbitCenter.z)
end

local function SetOrbitPreset(presetName)
    if not orbitCam then return end
    local preset = Customize.CameraPresets[presetName]
    if not preset then return end

    local pedPos = GetEntityCoords(PlayerPedId())
    orbitCenter   = vector3(pedPos.x, pedPos.y, pedPos.z + preset.zPos)
    orbitBaseDist = preset.dist or 1.2
    orbitDist     = orbitBaseDist
    orbitFov      = preset.fov
    orbitAngleV   = 0.0
    SetCamFov(orbitCam, orbitFov)
    UpdateOrbitCamera()
end

local function CreateOrbitCamera(ped, presetName)
    local pName = presetName or (Customize.Categories[1] and Customize.Categories[1].camera) or 'torso'
    local preset = Customize.CameraPresets[pName]
    local pedPos = GetEntityCoords(ped)

    orbitCenter   = vector3(pedPos.x, pedPos.y, pedPos.z + preset.zPos)
    orbitBaseDist = preset.dist or 1.2
    orbitDist     = orbitBaseDist
    orbitFov      = preset.fov
    orbitAngleH   = math.rad(GetEntityHeading(ped))
    orbitAngleV   = 0.0

    local camX = orbitCenter.x + orbitDist * math.sin(orbitAngleH)
    local camY = orbitCenter.y - orbitDist * math.cos(orbitAngleH)

    orbitCam = CreateCamWithParams('DEFAULT_SCRIPTED_CAMERA',
        camX, camY, orbitCenter.z, 0.0, 0.0, 0.0, orbitFov, false, 0)
    PointCamAtCoord(orbitCam, orbitCenter.x, orbitCenter.y, orbitCenter.z)
    SetCamActive(orbitCam, true)
    RenderScriptCams(true, false, 0, true, true)
end

local function DestroyOrbitCamera()
    if orbitCam then
        RenderScriptCams(false, false, 0, true, true)
        DestroyCam(orbitCam, false)
        orbitCam = nil
    end
end

-- TEXTURE LOADING

local function WaitForClothingLoaded(ped, componentId, drawableId, textureId)
    SetPedPreloadVariationData(ped, componentId, drawableId, textureId)
    local timeout = GetGameTimer() + 3000
    while not HasPedPreloadVariationDataFinished(ped) and GetGameTimer() < timeout do
        Wait(10)
    end
    SetPedComponentVariation(ped, componentId, drawableId, textureId, 0)
    ReleasePedPreloadVariationData(ped)

    local coords = GetEntityCoords(ped)
    RequestCollisionAtCoord(coords.x, coords.y, coords.z)
    local streamTimeout = GetGameTimer() + 1500
    while not HasCollisionLoadedAroundEntity(ped) and GetGameTimer() < streamTimeout do
        Wait(10)
    end
    Wait(Customize.TextureLoadWait)
end

local function WaitForPropLoaded(ped, propId, drawableId, textureId)
    SetPedPropIndex(ped, propId, drawableId, textureId, true)
    Wait(0)
    local timeout = GetGameTimer() + 2000
    while GetPedPropIndex(ped, propId) ~= drawableId and GetGameTimer() < timeout do
        Wait(10)
    end

    local coords = GetEntityCoords(ped)
    RequestCollisionAtCoord(coords.x, coords.y, coords.z)
    local streamTimeout = GetGameTimer() + 1500
    while not HasCollisionLoadedAroundEntity(ped) and GetGameTimer() < streamTimeout do
        Wait(10)
    end
    Wait(Customize.TextureLoadWait)
end

-- PAUSE / RESUME

local function WaitForResume()
    if not isPaused then return end
    SendNUIMessage({ type = 'setCapturePaused', paused = true })
    SetNuiFocus(true, true)

    while isPaused and not isCancelled do Wait(200) end

    if not isCancelled then
        SendNUIMessage({ type = 'setCapturePaused', paused = false })
        SetNuiFocus(false, false)
        Wait(50)
    end
end

-- CAPTURE & UPLOAD

local function CaptureAndUpload(filename)
    local done = false
    local encoding = Customize.ScreenshotFormat or 'png'
    if Customize.TransparentBg then encoding = 'png' end

    local opts = {
        encoding = encoding,
        headers  = {
            ['X-Filename']    = filename,
            ['X-Format']      = Customize.ScreenshotFormat or 'png',
            ['X-Transparent'] = Customize.TransparentBg and '1' or '0',
            ['X-ChromaKey']   = Customize.ChromaKeyColor or 'green',
            ['X-Width']       = tostring(Customize.ScreenshotWidth or 0),
            ['X-Height']      = tostring(Customize.ScreenshotHeight or 0),
        },
    }
    if encoding ~= 'png' then
        opts.quality = Customize.ScreenshotQuality
    end

    exports['screenshot-basic']:requestScreenshotUpload(
        Customize.BackendURL, 'files[]', opts,
        function() done = true end
    )

    local timeout = GetGameTimer() + 10000
    while not done and GetGameTimer() < timeout do Wait(50) end
end

local function SendProgress(current, total, category)
    SendNUIMessage({ type = 'captureProgress', current = current, total = total, category = category })
end

local batchCounter = 0
local function ThrottledWait()
    batchCounter = batchCounter + 1
    if batchCounter % Customize.GCInterval == 0 then collectgarbage('collect') end
    if batchCounter % Customize.BatchSize == 0 then Wait(Customize.BatchPauseWait) end
end

-- PED APPEARANCE — Save / Restore

local function SaveFullAppearance(ped)
    pedAppearance.model   = GetEntityModel(ped)
    pedAppearance.coords  = GetEntityCoords(ped)
    pedAppearance.heading = GetEntityHeading(ped)

    pedAppearance.components = {}
    for i = 0, 11 do
        pedAppearance.components[i] = {
            drawable = GetPedDrawableVariation(ped, i),
            texture  = GetPedTextureVariation(ped, i),
            palette  = GetPedPaletteVariation(ped, i),
        }
    end

    pedAppearance.props = {}
    for i = 0, 7 do
        pedAppearance.props[i] = {
            drawable = GetPedPropIndex(ped, i),
            texture  = GetPedPropTextureIndex(ped, i),
        }
    end

    local ok, hbData = pcall(GetPedHeadBlendData, ped)
    if ok and hbData and type(hbData) == 'table' then
        pedAppearance.headBlend = {
            shapeFirst  = hbData.shapeFirst  or hbData[1] or 0,
            shapeSecond = hbData.shapeSecond or hbData[2] or 0,
            shapeThird  = hbData.shapeThird  or hbData[3] or 0,
            skinFirst   = hbData.skinFirst   or hbData[4] or 0,
            skinSecond  = hbData.skinSecond  or hbData[5] or 0,
            skinThird   = hbData.skinThird   or hbData[6] or 0,
            shapeMix    = (hbData.shapeMix   or hbData[7] or 0.0) + 0.0,
            skinMix     = (hbData.skinMix    or hbData[8] or 0.0) + 0.0,
            thirdMix    = (hbData.thirdMix   or hbData[9] or 0.0) + 0.0,
        }
    else
        pedAppearance.headBlend = nil
    end

    pedAppearance.faceFeatures = {}
    for i = 0, 19 do pedAppearance.faceFeatures[i] = GetPedFaceFeature(ped, i) end

    pedAppearance.headOverlays = {}
    for i = 0, 12 do pedAppearance.headOverlays[i] = GetPedHeadOverlayValue(ped, i) end
end

local function RestoreFullAppearance()
    local model = pedAppearance.model
    if not model then return end

    if LoadModel(model) then
        SetPlayerModel(PlayerId(), model)
        Wait(150)
        SetModelAsNoLongerNeeded(model)
        Wait(150)
    end

    local ped = PlayerPedId()

    if pedAppearance.coords then
        SetEntityCoordsNoOffset(ped, pedAppearance.coords.x, pedAppearance.coords.y, pedAppearance.coords.z, false, false, false)
    end
    if pedAppearance.heading then
        SetEntityHeading(ped, pedAppearance.heading)
    end

    if pedAppearance.headBlend then
        local hb = pedAppearance.headBlend
        SetPedHeadBlendData(ped, hb.shapeFirst, hb.shapeSecond, hb.shapeThird, hb.skinFirst, hb.skinSecond, hb.skinThird, hb.shapeMix, hb.skinMix, hb.thirdMix, false)
    end

    for i = 0, 19 do
        if pedAppearance.faceFeatures[i] then SetPedFaceFeature(ped, i, pedAppearance.faceFeatures[i]) end
    end
    for i = 0, 12 do
        local val = pedAppearance.headOverlays[i]
        if val and val >= 0 then SetPedHeadOverlay(ped, i, val, 1.0) end
    end
    for i = 0, 11 do
        local comp = pedAppearance.components[i]
        if comp then SetPedComponentVariation(ped, i, comp.drawable, comp.texture, comp.palette) end
    end
    for i = 0, 7 do
        local prop = pedAppearance.props[i]
        if prop then
            if prop.drawable == -1 then ClearPedProp(ped, i)
            else SetPedPropIndex(ped, i, prop.drawable, prop.texture, true) end
        end
    end

    FreezeEntityPosition(ped, false)
    ClearPedTasksImmediately(ped)
    Wait(100)
    ClearPedTasks(ped)
    SetPlayerControl(PlayerId(), true, 0)
    SetEntityCollision(ped, true, true)
end

-- CAPTURE PED SETUP

local function SetupCapturePed(modelHash)
    if not LoadModel(modelHash) then return PlayerPedId() end

    SetPlayerModel(PlayerId(), modelHash)
    Wait(150)
    SetModelAsNoLongerNeeded(modelHash)
    Wait(150)

    local ped = PlayerPedId()
    SetPedHeadBlendData(ped, 0, 0, 0, 0, 0, 0, 0.0, 0.0, 0.0, false)
    SetEntityCoordsNoOffset(ped, Customize.StudioCoords.x, Customize.StudioCoords.y, Customize.StudioCoords.z, false, false, false)
    SetEntityHeading(ped, Customize.StudioHeading)
    FreezeEntityPosition(ped, true)
    Wait(50)
    SetPlayerControl(PlayerId(), false, 0)
    return ped
end

local function ResetPedToDefault(ped)
    SetPedDefaultComponentVariation(ped)
    Wait(150)

    for _, p in ipairs({0, 1, 2, 6, 7}) do ClearPedProp(ped, p) end

    SetPlayerControl(PlayerId(), false, 0)
    FreezeEntityPosition(ped, true)

    SetPedComponentVariation(ped, 0, 0, 0, 0)
    SetPedComponentVariation(ped, 1, 0, 0, 0)
    SetPedComponentVariation(ped, 2, -1, 0, 0)
    SetPedComponentVariation(ped, 3, -1, 0, 0)
    SetPedComponentVariation(ped, 4, -1, 0, 0)
    SetPedComponentVariation(ped, 5, 0, 0, 0)
    SetPedComponentVariation(ped, 6, -1, 0, 0)
    SetPedComponentVariation(ped, 7, 0, 0, 0)
    SetPedComponentVariation(ped, 8, -1, 0, 0)
    SetPedComponentVariation(ped, 9, 0, 0, 0)
    SetPedComponentVariation(ped, 11, -1, 0, 0)
end

-- CAPTURE LOOPS

local function SetupCategoryCamera(ped, cameraName)
    local preset   = Customize.CameraPresets[cameraName]
    local hasSaved = savedCameraAngles[cameraName] ~= nil
    DestroyCamera()
    captureCamera = CreateCaptureCamera(ped, preset, cameraName)
    return preset, hasSaved
end

local function ReapplyRotation(ped, preset, hasSaved)
    if not hasSaved then
        SetEntityRotation(ped, preset.rotation.x, preset.rotation.y, preset.rotation.z + captureRotOffset, 2, false)
    end
end

local function CaptureComponents(ped, gender, selectedSet)
    local totalItems, captured = 0, 0

    for _, cat in ipairs(Customize.Categories) do
        if not selectedSet or selectedSet[cat.componentId] then
            local n = GetNumberOfPedDrawableVariations(ped, cat.componentId)
            if Customize.CaptureAllTextures then
                for d = 0, n - 1 do totalItems = totalItems + GetNumberOfPedTextureVariations(ped, cat.componentId, d) end
            else
                totalItems = totalItems + n
            end
        end
    end

    for _, cat in ipairs(Customize.Categories) do
        if isCancelled then return end
        if selectedSet and not selectedSet[cat.componentId] then goto nextComp end

        ResetPedToDefault(ped)
        local preset, hasSaved = SetupCategoryCamera(ped, cat.camera)

        for drawableId = 0, GetNumberOfPedDrawableVariations(ped, cat.componentId) - 1 do
            if isCancelled then return end
            local maxTex = Customize.CaptureAllTextures and GetNumberOfPedTextureVariations(ped, cat.componentId, drawableId) - 1 or 0

            for textureId = 0, maxTex do
                if isCancelled then return end
                WaitForResume()
                if isCancelled then return end

                WaitForClothingLoaded(ped, cat.componentId, drawableId, textureId)
                ReapplyRotation(ped, preset, hasSaved)
                Wait(Customize.WaitAfterApply)

                local filename = textureId > 0
                    and ('%s/%d/%d_%d'):format(gender, cat.componentId, drawableId, textureId)
                    or  ('%s/%d/%d'):format(gender, cat.componentId, drawableId)
                CaptureAndUpload(filename)

                captured = captured + 1
                SendProgress(captured, totalItems, cat.label)
                Wait(Customize.WaitAfterCapture)
                ThrottledWait()
            end
        end

        ::nextComp::
    end
end

local function CaptureProps(ped, gender, selectedSet)
    local totalItems, captured = 0, 0

    for _, cat in ipairs(Customize.PropCategories) do
        if not selectedSet or selectedSet[cat.propId] then
            local n = GetNumberOfPedPropDrawableVariations(ped, cat.propId)
            if Customize.CaptureAllTextures then
                for d = 0, n - 1 do totalItems = totalItems + GetNumberOfPedPropTextureVariations(ped, cat.propId, d) end
            else
                totalItems = totalItems + n
            end
        end
    end

    for _, cat in ipairs(Customize.PropCategories) do
        if isCancelled then return end
        if selectedSet and not selectedSet[cat.propId] then goto nextProp end

        ResetPedToDefault(ped)
        local preset, hasSaved = SetupCategoryCamera(ped, cat.camera)

        for drawableId = 0, GetNumberOfPedPropDrawableVariations(ped, cat.propId) - 1 do
            if isCancelled then return end
            local maxTex = Customize.CaptureAllTextures and GetNumberOfPedPropTextureVariations(ped, cat.propId, drawableId) - 1 or 0

            for textureId = 0, maxTex do
                if isCancelled then return end
                WaitForResume()
                if isCancelled then return end

                WaitForPropLoaded(ped, cat.propId, drawableId, textureId)
                ReapplyRotation(ped, preset, hasSaved)
                Wait(Customize.WaitAfterApply)

                local filename = textureId > 0
                    and ('%s/prop_%d/%d_%d'):format(gender, cat.propId, drawableId, textureId)
                    or  ('%s/prop_%d/%d'):format(gender, cat.propId, drawableId)
                CaptureAndUpload(filename)

                captured = captured + 1
                SendProgress(captured, totalItems, cat.label)
                Wait(Customize.WaitAfterCapture)
                ThrottledWait()
            end
        end

        ClearPedProp(ped, cat.propId)
        ::nextProp::
    end
end

-- CLEANUP

local function CleanupCapture()
    DestroyCamera()
    HideHUD(false)
    isCapturing = false
    isPreview   = false
    isPaused    = false
    isCancelled = false
    RestoreFullAppearance()
    TriggerServerEvent('uz_autoshot:server:resetBucket')
    SetNuiFocus(false, false)
end

-- RE-CAPTURE SPECIFIC ITEMS

local function RecaptureSpecificItems(items)
    local cameraMap = {}
    for _, cat in ipairs(Customize.Categories) do cameraMap['component_' .. cat.componentId] = cat.camera end
    for _, cat in ipairs(Customize.PropCategories) do cameraMap['prop_' .. cat.propId] = cat.camera end

    local total = #items
    local model = pedAppearance.model or GetEntityModel(PlayerPedId())

    HideHUD(true)
    TriggerServerEvent('uz_autoshot:server:setBucket', Customize.RoutingBucket)
    Wait(500)

    local ped = SetupCapturePed(model)
    isCapturing  = true
    isPaused     = false
    isCancelled  = false
    batchCounter = 0

    SendNUIMessage({ type = 'captureStart' })
    SetNuiFocus(false, false)
    Wait(300)

    local currentCameraKey = nil
    local captured = 0

    for _, item in ipairs(items) do
        if isCancelled then break end
        WaitForResume()
        if isCancelled then break end

        ResetPedToDefault(ped)

        local cameraKey = cameraMap[item.type .. '_' .. item.id] or 'torso'
        local preset    = Customize.CameraPresets[cameraKey]
        local hasSaved  = savedCameraAngles[cameraKey] ~= nil

        if cameraKey ~= currentCameraKey then
            DestroyCamera()
            captureCamera    = CreateCaptureCamera(ped, preset, cameraKey)
            currentCameraKey = cameraKey
        end

        if item.type == 'component' then
            WaitForClothingLoaded(ped, item.id, item.drawable, item.texture)
        else
            WaitForPropLoaded(ped, item.id, item.drawable, item.texture)
        end

        ReapplyRotation(ped, preset, hasSaved)
        Wait(Customize.WaitAfterApply)

        local filename
        if item.type == 'component' then
            filename = item.texture > 0
                and ('%s/%d/%d_%d'):format(captureGender, item.id, item.drawable, item.texture)
                or  ('%s/%d/%d'):format(captureGender, item.id, item.drawable)
        else
            filename = item.texture > 0
                and ('%s/prop_%d/%d_%d'):format(captureGender, item.id, item.drawable, item.texture)
                or  ('%s/prop_%d/%d'):format(captureGender, item.id, item.drawable)
        end

        CaptureAndUpload(filename)
        captured = captured + 1
        SendProgress(captured, total, item.type == 'component' and tostring(item.id) or ('prop_' .. item.id))
        Wait(Customize.WaitAfterCapture)
        ThrottledWait()
    end

    local wasCancelled = isCancelled
    CleanupCapture()
    SendNUIMessage({ type = 'forceClose' })
    SendNUIMessage({ type = wasCancelled and 'captureCancelled' or 'captureComplete' })
end

-- CAPTURE PREVIEW + RUN

local function BuildCategoryList(includeDrawables)
    local categories = {}
    for _, cat in ipairs(Customize.Categories) do
        local entry = { type = 'component', id = cat.componentId, label = cat.label, camera = cat.camera }
        if includeDrawables then entry.drawables = GetNumberOfPedDrawableVariations(PlayerPedId(), cat.componentId) end
        categories[#categories + 1] = entry
    end
    for _, cat in ipairs(Customize.PropCategories) do
        local entry = { type = 'prop', id = cat.propId, label = cat.label, camera = cat.camera }
        if includeDrawables then entry.drawables = GetNumberOfPedPropDrawableVariations(PlayerPedId(), cat.propId) end
        categories[#categories + 1] = entry
    end
    return categories
end

local function EnterCapturePreview()
    if isCapturing or isPreview then
        BeginTextCommandThefeedPost('STRING')
        AddTextComponentSubstringPlayerName('Capture already in progress!')
        EndTextCommandThefeedPostTicker(false, false)
        return
    end

    savedCameraAngles   = {}
    activePreviewCamera = nil
    isPreview           = true

    local ped = PlayerPedId()
    captureGender = GetPedGender(ped)
    SaveFullAppearance(ped)

    TriggerServerEvent('uz_autoshot:server:setBucket', Customize.RoutingBucket)
    Wait(500)
    HideHUD(true)

    ped = SetupCapturePed(pedAppearance.model)

    local categories = BuildCategoryList(false)
    CreateOrbitCamera(ped, categories[1] and categories[1].camera or 'torso')

    SendNUIMessage({ type = 'capturePreview', categories = categories })
    SetNuiFocus(true, true)
end

local function RunCapture(selectedComponents, selectedProps)
    captureRotOffset = math.deg(orbitAngleH) - Customize.StudioHeading
    DestroyOrbitCamera()

    isPreview    = false
    isCapturing  = true
    isPaused     = false
    isCancelled  = false
    batchCounter = 0

    local compSet, propSet = {}, {}
    for _, id in ipairs(selectedComponents) do compSet[id] = true end
    for _, id in ipairs(selectedProps) do propSet[id] = true end

    SendNUIMessage({ type = 'captureStart' })
    SetNuiFocus(false, false)
    Wait(300)

    local ped = PlayerPedId()
    CaptureComponents(ped, captureGender, compSet)
    if not isCancelled then CaptureProps(ped, captureGender, propSet) end

    local wasCancelled = isCancelled
    CleanupCapture()
    SendNUIMessage({ type = wasCancelled and 'captureCancelled' or 'captureComplete' })
end

local function CancelPreview()
    if not isPreview then return end
    isPreview = false
    DestroyOrbitCamera()
    HideHUD(false)
    RestoreFullAppearance()
    TriggerServerEvent('uz_autoshot:server:resetBucket')
    SetNuiFocus(false, false)
end

-- CLOSE BROWSING (shared logic)

local function CloseBrowsing()
    isBrowsing = false
    DestroyOrbitCamera()
    RestoreFullAppearance()
    SetNuiFocus(false, false)
end

-- BACKGROUND THREAD

CreateThread(function()
    while true do
        local active = isCapturing or isPreview
        if active then
            local ped = PlayerPedId()
            SuppressWorld()
            ClearPedTasksImmediately(ped)
            if Customize.TransparentBg then DrawGreenScreenAndLights(ped) end
            if isPreview and not isCapturing then DrawCropOverlay() end
        end
        Wait(active and 0 or 1000)
    end
end)

-- CLOTHING MENU

local function OpenClothingMenu()
    if isCapturing then return end
    isBrowsing = true

    local ped = PlayerPedId()
    SaveFullAppearance(ped)
    CreateOrbitCamera(ped)
    SetNuiFocus(true, true)

    SendNUIMessage({
        type       = 'openMenu',
        gender     = GetPedGender(ped),
        categories = BuildCategoryList(true),
        imgExt     = Customize.TransparentBg and 'png' or (Customize.ScreenshotFormat or 'png'),
    })
end

-- NUI CALLBACKS

RegisterNUICallback('startCapture', function(data, cb)
    cb('ok')
    if not isPreview then return end
    CreateThread(function() RunCapture(data.selectedComponents or {}, data.selectedProps or {}) end)
end)

RegisterNUICallback('cancelPreview', function(_, cb)
    CancelPreview()
    cb('ok')
end)

RegisterNUICallback('pauseCapture', function(_, cb)
    isPaused = true
    cb('ok')
end)

RegisterNUICallback('resumeCapture', function(_, cb)
    isPaused = false
    cb('ok')
end)

RegisterNUICallback('cancelCapture', function(_, cb)
    isCancelled = true
    isPaused = false
    cb('ok')
end)

RegisterNUICallback('closeMenu', function(_, cb)
    CloseBrowsing()
    cb('ok')
end)

RegisterNUICallback('applyClothing', function(data, cb)
    local ped = PlayerPedId()
    if data.itemType == 'component' then
        SetPedComponentVariation(ped, data.id, data.drawable, data.texture, 0)
    elseif data.itemType == 'prop' then
        if data.drawable == -1 then ClearPedProp(ped, data.id)
        else SetPedPropIndex(ped, data.id, data.drawable, data.texture, true) end
    end
    cb('ok')
end)

RegisterNUICallback('setCameraPreset', function(data, cb)
    local cam = data.camera or 'torso'
    activePreviewCamera = cam
    SetOrbitPreset(cam)

    if savedCameraAngles[cam] then
        local saved = savedCameraAngles[cam]
        orbitAngleH = saved.angleH
        orbitAngleV = saved.angleV
        orbitDist   = saved.dist
        orbitFov    = saved.fov
        if orbitCam then SetCamFov(orbitCam, orbitFov) end
        UpdateOrbitCamera()
    end
    cb('ok')
end)

RegisterNUICallback('saveCameraAngle', function(data, cb)
    local cam = data.camera or activePreviewCamera
    if cam and orbitCam then
        savedCameraAngles[cam] = {
            angleH = orbitAngleH, angleV = orbitAngleV,
            dist   = orbitDist,   fov    = orbitFov,
        }
        cb({ saved = true, camera = cam })
    else
        cb({ saved = false })
    end
end)

RegisterNUICallback('rotateCamera', function(data, cb)
    if orbitCam then
        orbitAngleH = orbitAngleH - (data.deltaX or 0) * 0.005
        orbitAngleV = math.max(-0.8, math.min(0.8, orbitAngleV - (data.deltaY or 0) * 0.005))
        UpdateOrbitCamera()
    end
    cb('ok')
end)

RegisterNUICallback('zoomCamera', function(data, cb)
    if orbitCam then
        orbitDist = math.max(orbitBaseDist * 0.3, math.min(orbitBaseDist * 3.0, orbitDist + (data.delta or 0) * 0.1))
        UpdateOrbitCamera()
    end
    cb('ok')
end)

RegisterNUICallback('getTextures', function(data, cb)
    local ped = PlayerPedId()
    local count = data.itemType == 'component'
        and GetNumberOfPedTextureVariations(ped, data.id, data.drawable)
        or  GetNumberOfPedPropTextureVariations(ped, data.id, data.drawable)
    cb({ count = count })
end)

RegisterNUICallback('enterRecapturePreview', function(_, cb)
    isPreview = true
    HideHUD(true)
    TriggerServerEvent('uz_autoshot:server:setBucket', Customize.RoutingBucket)
    Wait(500)

    local ped = SetupCapturePed(pedAppearance.model or GetEntityModel(PlayerPedId()))

    DestroyOrbitCamera()
    CreateOrbitCamera(ped)
    cb('ok')
end)

RegisterNUICallback('cancelRecapturePreview', function(_, cb)
    isPreview  = false
    isBrowsing = false
    DestroyOrbitCamera()
    HideHUD(false)
    RestoreFullAppearance()
    TriggerServerEvent('uz_autoshot:server:resetBucket')
    SetNuiFocus(false, false)
    cb('ok')
end)

RegisterNUICallback('recaptureItems', function(data, cb)
    cb('ok')
    local items = data.items or {}
    if #items == 0 then return end

    captureGender    = GetPedGender(PlayerPedId())
    captureRotOffset = 0.0
    isPreview        = false
    isBrowsing       = false

    local cameraMap = {}
    for _, cat in ipairs(Customize.Categories) do cameraMap['component_' .. cat.componentId] = cat.camera end
    for _, cat in ipairs(Customize.PropCategories) do cameraMap['prop_' .. cat.propId] = cat.camera end

    savedCameraAngles = {}
    if orbitCam then
        local orbitState = { angleH = orbitAngleH, angleV = orbitAngleV, dist = orbitDist, fov = orbitFov }
        local seen = {}
        for _, item in ipairs(items) do
            local cam = cameraMap[item.type .. '_' .. item.id]
            if cam and not seen[cam] then
                savedCameraAngles[cam] = orbitState
                seen[cam] = true
            end
        end
    end

    DestroyOrbitCamera()
    CreateThread(function() RecaptureSpecificItems(items) end)
end)

-- COMMANDS

RegisterCommand(Customize.Command, function() EnterCapturePreview() end, false)
RegisterCommand(Customize.MenuCommand, function() OpenClothingMenu() end, false)

-- EXPORTS (see DOCS.md for full usage examples)

exports('getPhotoURL', function(gender, itemType, id, drawable, texture)
    local prefix = itemType == 'prop' and 'prop_' or ''
    return ('http://127.0.0.1:3959/shots/%s/%s%d/%d_%d.%s'):format(
        gender, prefix, id, drawable, texture, Customize.ScreenshotFormat
    )
end)

exports('getShotsBaseURL', function()
    return 'http://127.0.0.1:3959/shots'
end)

exports('getManifestURL', function(gender, itemType, id)
    local base = 'http://127.0.0.1:3959/api/manifest'
    if not gender then return base end
    if not itemType then return base .. '/' .. gender end
    return ('%s/%s/%s/%d'):format(base, gender, itemType, id)
end)

exports('getPhotoFormat', function()
    return Customize.ScreenshotFormat
end)

exports('getServerPort', function()
    return 3959
end)

-- INPUT THREAD

CreateThread(function()
    while true do
        Wait(0)
        if isBrowsing then
            DisableControlAction(0, 1, true)
            DisableControlAction(0, 2, true)
            DisableControlAction(0, 142, true)
            DisableControlAction(0, 18, true)
            DisableControlAction(0, 322, true)
            DisableControlAction(0, 200, true)

            if IsDisabledControlJustReleased(0, 322) or IsDisabledControlJustReleased(0, 200) then
                SendNUIMessage({ type = 'forceClose' })
                CloseBrowsing()
            end

        elseif isPreview then
            DisableControlAction(0, 322, true)
            DisableControlAction(0, 200, true)
            if IsDisabledControlJustReleased(0, 322) or IsDisabledControlJustReleased(0, 200) then
                SendNUIMessage({ type = 'forceClose' })
                CancelPreview()
            end

        elseif isCapturing and not isPaused then
            DisableControlAction(0, 22, true)
            DisableControlAction(0, 322, true)
            DisableControlAction(0, 200, true)
            if IsDisabledControlJustReleased(0, 22) then isPaused = true end
            if IsDisabledControlJustReleased(0, 322) or IsDisabledControlJustReleased(0, 200) then
                isCancelled = true
                isPaused = false
            end
        end
    end
end)
