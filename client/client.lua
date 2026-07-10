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
local captureMode       = 'clothing'  -- 'clothing' | 'vehicle' | 'object'
local spawnedEntity     = nil
local vehicleColor      = { primary = 0, secondary = 0 }
local entitySpawnToken  = 0  -- increments each spawn request to cancel stale ones
local hideHeadActive    = false
local captureUploadSeq  = 0
local pendingCaptureUploads = {}

-- Orbit-camera state. Declared up here so functions defined earlier in the
-- file (CreateCaptureCamera, ...) can read the live orbit values that the
-- ORBIT CAMERA section below assigns.
local orbitCam      = nil
local orbitAngleH   = 0.0
local orbitDist     = 1.2
local orbitCenter   = vector3(0.0, 0.0, 0.0)
local orbitFov      = 40.0
local orbitBaseDist = 1.2
local orbitRoll     = 0.0
local orbitCamZ     = 0.0   -- camera Z offset (center stays fixed, camera moves up/down)

local pedAppearance = {
    model = nil, coords = nil, heading = nil,
    components = {}, props = {},
    headBlend = nil, faceFeatures = {}, headOverlays = {},
}

-- ════════════════════════════════════════════════════════
-- HELPERS
-- ════════════════════════════════════════════════════════

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

local resolvedVehicleCategories = nil

local VehicleClassNames = {
    [0]  = 'Compacts',      [1]  = 'Sedans',        [2]  = 'SUVs',
    [3]  = 'Coupes',        [4]  = 'Muscle',        [5]  = 'Sports Classics',
    [6]  = 'Sports',        [7]  = 'Super',         [8]  = 'Motorcycles',
    [9]  = 'Off-Road',      [10] = 'Industrial',    [11] = 'Utility',
    [12] = 'Vans',          [13] = 'Cycles',        [14] = 'Boats',
    [15] = 'Helicopters',   [16] = 'Planes',        [17] = 'Service',
    [18] = 'Emergency',     [19] = 'Military',      [20] = 'Commercial',
    [21] = 'Trains',        [22] = 'Open Wheel',
}

local function GetVehicleCategories()
    if resolvedVehicleCategories then return resolvedVehicleCategories end

    local cfg = Customize.VehicleCategories
    if type(cfg) == 'table' then
        resolvedVehicleCategories = cfg
        return cfg
    end

    -- 'auto' mode: detect all vehicle models, grouped by class
    local models = GetAllVehicleModels()
    local byClass = {}
    if models then
        for _, modelName in ipairs(models) do
            local hash = GetHashKey(modelName)
            local classId = GetVehicleClassFromName(hash)
            local className = VehicleClassNames[classId] or ('Class ' .. classId)
            if not byClass[classId] then
                byClass[classId] = { id = classId, name = className, models = {} }
            end
            byClass[classId].models[#byClass[classId].models + 1] = modelName
        end
    end

    -- Sort classes by id, models alphabetically
    local list = {}
    local classIds = {}
    for id in pairs(byClass) do classIds[#classIds + 1] = id end
    table.sort(classIds)

    for _, classId in ipairs(classIds) do
        local group = byClass[classId]
        table.sort(group.models)
        for _, modelName in ipairs(group.models) do
            list[#list + 1] = { model = modelName, label = modelName, category = group.name }
        end
    end

    resolvedVehicleCategories = list
    return list
end

local function LoadModel(modelHash)
    RequestModel(modelHash)
    local timeout = GetGameTimer() + 5000
    while not HasModelLoaded(modelHash) and GetGameTimer() < timeout do
        Wait(10)
    end
    return HasModelLoaded(modelHash)
end

-- ════════════════════════════════════════════════════════
-- CAPTURE CAMERA
-- ════════════════════════════════════════════════════════

local function CreateCaptureCamera(entity, preset, presetName)
    local pedPos = GetEntityCoords(entity)
    local saved  = presetName and savedCameraAngles[presetName]
    local camX, camY, camZ, fov, lookZ, roll

    if saved then
        local zP = saved.zPos or preset.zPos
        local cZ = saved.camZ or 0.0
        camX  = pedPos.x + saved.dist * math.sin(saved.angleH)
        camY  = pedPos.y - saved.dist * math.cos(saved.angleH)
        camZ  = pedPos.z + zP + cZ
        fov   = saved.fov or preset.fov
        lookZ = pedPos.z + zP
        roll  = saved.roll or 0.0
    elseif preset.defaultAngleH then
        -- Mirror the saved branch using the live orbit state. Reading
        -- orbitAngleH/Dist/Fov here keeps "Start without saving" framed
        -- exactly like the preview the user just left, instead of snapping
        -- back to preset.defaultAngleH (which would 180-flip whenever the
        -- user had rotated the orbit to face the ped).
        local dist = (orbitDist > 0 and orbitDist) or preset.dist or 1.2
        local aH   = orbitAngleH
        local cZ   = orbitCamZ or preset.defaultCamZ or 0.0
        camX  = pedPos.x + dist * math.sin(aH)
        camY  = pedPos.y - dist * math.cos(aH)
        camZ  = pedPos.z + preset.zPos + cZ
        fov   = (orbitFov and orbitFov > 0) and orbitFov or preset.fov
        lookZ = pedPos.z + preset.zPos
        roll  = orbitRoll or preset.defaultRoll or 0.0
    else
        -- Legacy preset without defaultAngleH: rotate ped to align with
        -- camera, then place camera behind ped's forward vector.
        local rotZ = preset.rotation.z + captureRotOffset
        SetEntityRotation(entity, preset.rotation.x, preset.rotation.y, rotZ, 2, false)
        Wait(50)
        local fwd = GetEntityForwardVector(entity)
        local dist = preset.dist or 1.2
        camX  = pedPos.x - fwd.x * dist
        camY  = pedPos.y - fwd.y * dist
        camZ  = pedPos.z - fwd.z + preset.zPos
        fov   = preset.fov
        lookZ = pedPos.z + preset.zPos
        roll  = 0.0
    end

    local cam = CreateCamWithParams('DEFAULT_SCRIPTED_CAMERA', camX, camY, camZ, 0.0, 0.0, 0.0, fov, false, 0)

    local dx = pedPos.x - camX
    local dy = pedPos.y - camY
    local dz = lookZ - camZ
    local dist2d = math.sqrt(dx * dx + dy * dy)
    local pitch  = math.deg(math.atan(dz, dist2d))
    local heading = -math.deg(math.atan(dx, dy))
    SetCamRot(cam, pitch, roll, heading, 2)

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

-- ════════════════════════════════════════════════════════
-- GREEN SCREEN + STUDIO LIGHTING
-- ════════════════════════════════════════════════════════

local function DrawQuad(x1,y1,z1, x2,y2,z2, x3,y3,z3, x4,y4,z4, r,g,b,a)
    DrawPoly(x1,y1,z1, x2,y2,z2, x3,y3,z3, r,g,b,a)
    DrawPoly(x3,y3,z3, x4,y4,z4, x1,y1,z1, r,g,b,a)
    DrawPoly(x3,y3,z3, x2,y2,z2, x1,y1,z1, r,g,b,a)
    DrawPoly(x1,y1,z1, x4,y4,z4, x3,y3,z3, r,g,b,a)
end

local function DrawGreenScreenAndLights(entity)
    local pos = GetEntityCoords(entity)
    local gs
    local lights
    if captureMode == 'vehicle' then
        gs     = Customize.VehicleGreenScreen or Customize.GreenScreen
        lights = Customize.VehicleStudioLights or Customize.StudioLights
    elseif captureMode == 'object' then
        gs     = Customize.ObjectGreenScreen or Customize.GreenScreen
        lights = Customize.StudioLights
    else
        gs     = Customize.GreenScreen
        lights = Customize.StudioLights
    end
    local r, g, b = Customize.GreenScreen.color.r, Customize.GreenScreen.color.g, Customize.GreenScreen.color.b

    local hw = gs.width  * 0.5
    local hd = gs.depth  * 0.5
    local fz = pos.z + (gs.floorOffset or -3.0)
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

    for _, light in ipairs(lights) do
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

-- ════════════════════════════════════════════════════════
-- CROP OVERLAY (preview only — shows final image bounds)
-- ════════════════════════════════════════════════════════

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

-- ════════════════════════════════════════════════════════
-- ORBIT CAMERA
-- (state variables hoisted to the top of the file so earlier functions
--  like CreateCaptureCamera can read them)
-- ════════════════════════════════════════════════════════

local function UpdateOrbitCamera()
    if not orbitCam then return end
    local camX = orbitCenter.x + orbitDist * math.sin(orbitAngleH)
    local camY = orbitCenter.y - orbitDist * math.cos(orbitAngleH)
    local camZ = orbitCenter.z + orbitCamZ
    SetCamCoord(orbitCam, camX, camY, camZ)

    local dx = orbitCenter.x - camX
    local dy = orbitCenter.y - camY
    local dz = orbitCenter.z - camZ
    local dist2d = math.sqrt(dx * dx + dy * dy)
    local pitch  = math.deg(math.atan(dz, dist2d))
    local heading = -math.deg(math.atan(dx, dy))

    SetCamRot(orbitCam, pitch, orbitRoll, heading, 2)
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
    orbitCamZ     = preset.defaultCamZ or 0.0
    orbitRoll     = preset.defaultRoll or 0.0
    if preset.defaultAngleH then
        orbitAngleH = math.rad(preset.defaultAngleH)
    end
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
    -- Match SetOrbitPreset: honor preset's defaultAngleH so the camera lands in
    -- front of the ped on entry. Falling back to GetEntityHeading + 180 keeps
    -- presets without an explicit angle on the ped's face side too — orbit math
    -- subtracts cos, so naked heading would put us behind the ped.
    if preset.defaultAngleH then
        orbitAngleH = math.rad(preset.defaultAngleH)
    else
        orbitAngleH = math.rad((GetEntityHeading(ped) + 180.0) % 360.0)
    end
    orbitCamZ     = preset.defaultCamZ or 0.0
    orbitRoll     = preset.defaultRoll or 0.0

    local camX = orbitCenter.x + orbitDist * math.sin(orbitAngleH)
    local camY = orbitCenter.y - orbitDist * math.cos(orbitAngleH)

    orbitCam = CreateCamWithParams('DEFAULT_SCRIPTED_CAMERA',
        camX, camY, orbitCenter.z, 0.0, 0.0, 0.0, orbitFov, false, 0)
    SetCamActive(orbitCam, true)
    RenderScriptCams(true, false, 0, true, true)
    UpdateOrbitCamera()
end

local function DestroyOrbitCamera()
    if orbitCam then
        RenderScriptCams(false, false, 0, true, true)
        DestroyCam(orbitCam, false)
        orbitCam = nil
    end
end

-- ════════════════════════════════════════════════════════
-- TEXTURE LOADING
-- ════════════════════════════════════════════════════════

local function ForceHighQuality()
    OverrideLodscaleThisFrame(1.0)
    SetHdArea(0.0, 0.0, -150.0, 50.0)
    SetFocusPosAndVel(0.0, 0.0, -150.0, 0.0, 0.0, 0.0)
end

local function WaitForClothingLoaded(ped, componentId, drawableId, textureId)
    -- Preload texture
    SetPedPreloadVariationData(ped, componentId, drawableId, textureId)
    local timeout = GetGameTimer() + 800
    while not HasPedPreloadVariationDataFinished(ped) and GetGameTimer() < timeout do
        Wait(0)
    end
    -- Apply
    SetPedComponentVariation(ped, componentId, drawableId, textureId, 0)
    ReleasePedPreloadVariationData(ped)
    -- Force HD + 2 render frames
    ForceHighQuality()
    SetEntityLodDist(ped, 10000)
    Wait(0)
    ForceHighQuality()
    Wait(0)
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

-- ════════════════════════════════════════════════════════
-- PAUSE / RESUME
-- ════════════════════════════════════════════════════════

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

-- ════════════════════════════════════════════════════════
-- CAPTURE & UPLOAD
-- ════════════════════════════════════════════════════════

RegisterNetEvent('uz_autoshot:client:captureProcessed', function(requestId, ok, message)
    local pending = pendingCaptureUploads[requestId]
    if not pending then return end

    pending.done = true
    pending.ok = ok == true
    pending.message = message or ''
end)

local function CaptureAndUpload(filename)
    ForceHighQuality()

    local encoding = Customize.ScreenshotFormat or 'png'
    if Customize.TransparentBg then encoding = 'png' end

    local opts = { encoding = encoding }
    if encoding ~= 'png' then
        opts.quality = Customize.ScreenshotQuality
    end

    local done, base64 = false, nil
    local screenshotOk, screenshotErr = pcall(function()
        exports['screenshot-basic']:requestScreenshot(opts, function(data)
            base64 = data
            done = true
        end)
    end)

    if not screenshotOk then
        print('^1[uz_AutoShot]^0 Screenshot request failed (' .. filename .. '): ' .. tostring(screenshotErr))
        return false
    end

    local timeout = GetGameTimer() + (Customize.ScreenshotTimeout or 15000)
    while not done and GetGameTimer() < timeout and not isCancelled do Wait(50) end

    if isCancelled then return false end

    if not done then
        print('^3[uz_AutoShot]^0 Capture timed out (' .. filename .. ')')
        return false
    end

    if not base64 or base64 == '' then
        print('^3[uz_AutoShot]^0 Capture skipped (' .. filename .. '): empty screenshot')
        return false
    end

    captureUploadSeq = captureUploadSeq + 1
    local requestId = ('%d:%d:%d'):format(GetPlayerServerId(PlayerId()), GetGameTimer(), captureUploadSeq)
    local pending = { done = false, ok = false, message = '' }
    pendingCaptureUploads[requestId] = pending

    local sendOk, sendErr = pcall(TriggerLatentServerEvent, 'uz_autoshot:server:processCapture', Customize.LatentRate or 8000000, {
        requestId   = requestId,
        filename    = filename,
        format      = Customize.ScreenshotFormat or 'png',
        transparent = Customize.TransparentBg and true or false,
        chromaKey   = Customize.ChromaKeyColor or 'green',
        width       = Customize.ScreenshotWidth or 0,
        height      = Customize.ScreenshotHeight or 0,
        imageData   = base64,
    })

    if not sendOk then
        pendingCaptureUploads[requestId] = nil
        print('^1[uz_AutoShot]^0 Upload send failed (' .. filename .. '): ' .. tostring(sendErr))
        return false
    end

    local uploadTimeout = GetGameTimer() + (Customize.UploadAckTimeout or 45000)
    while not pending.done and GetGameTimer() < uploadTimeout and not isCancelled do Wait(50) end
    pendingCaptureUploads[requestId] = nil

    if isCancelled then return false end

    if not pending.done then
        print('^3[uz_AutoShot]^0 Upload timed out (' .. filename .. ')')
        return false
    end

    if not pending.ok then
        print('^3[uz_AutoShot]^0 Upload failed (' .. filename .. '): ' .. (pending.message ~= '' and pending.message or 'server rejected capture'))
        return false
    end

    return true
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

-- ════════════════════════════════════════════════════════
-- PED APPEARANCE — Save / Restore
-- ════════════════════════════════════════════════════════

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

    -- Pre-stream the world at the restore coords. Studio sat at -150z in a
    -- separate routing bucket, so the original location's collision/IPLs were
    -- unloaded; without an explicit wait the player drops through unloaded
    -- ground the moment we re-enable collision.
    if pedAppearance.coords then
        local x, y, z = pedAppearance.coords.x, pedAppearance.coords.y, pedAppearance.coords.z

        FreezeEntityPosition(ped, true)
        SetEntityCollision(ped, false, false)
        SetEntityCoordsNoOffset(ped, x, y, z, false, false, false)
        if pedAppearance.heading then
            SetEntityHeading(ped, pedAppearance.heading)
        end

        SetFocusPosAndVel(x, y, z, 0.0, 0.0, 0.0)
        RequestCollisionAtCoord(x, y, z)
        NewLoadSceneStart(x, y, z, 100.0, 0)

        local timeout = GetGameTimer() + 5000
        while not HasCollisionLoadedAroundEntity(ped) and GetGameTimer() < timeout do
            RequestCollisionAtCoord(x, y, z)
            Wait(0)
        end

        if IsNewLoadSceneActive() then NewLoadSceneStop() end
        ClearFocus()
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

    SetEntityCollision(ped, true, true)
    FreezeEntityPosition(ped, false)
    ClearPedTasksImmediately(ped)
    Wait(100)
    ClearPedTasks(ped)
    SetPlayerControl(PlayerId(), true, 0)
end

-- ════════════════════════════════════════════════════════
-- CAPTURE PED SETUP
-- ════════════════════════════════════════════════════════

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

local function ResetPedForCategory(ped, visibleComponents, componentOverrides)
    SetPedDefaultComponentVariation(ped)
    Wait(150)

    for _, p in ipairs({0, 1, 2, 6, 7}) do ClearPedProp(ped, p) end

    SetPlayerControl(PlayerId(), false, 0)
    FreezeEntityPosition(ped, true)

    local visSet = {}
    if visibleComponents then
        for _, id in ipairs(visibleComponents) do visSet[id] = true end
    end

    local overrides = componentOverrides or {}

    for i = 0, 11 do
        if overrides[i] then
            SetPedComponentVariation(ped, i, overrides[i], 0, 0)
        elseif visSet[i] then
            SetPedComponentVariation(ped, i, 0, 0, 0)
        else
            SetPedComponentVariation(ped, i, -1, 0, 0)
        end
    end
end

-- ════════════════════════════════════════════════════════
-- VEHICLE / OBJECT SPAWN HELPERS
-- ════════════════════════════════════════════════════════

local function SpawnStudioVehicle(modelName)
    local hash = GetHashKey(modelName)
    if not LoadModel(hash) then return nil end

    local sx, sy, sz = Customize.StudioCoords.x, Customize.StudioCoords.y, Customize.StudioCoords.z

    -- Spawn at player position first (FiveM streams here), then teleport
    local playerPos = GetEntityCoords(PlayerPedId())
    local veh = CreateVehicle(hash, playerPos.x, playerPos.y, playerPos.z, Customize.StudioHeading, false, false)
    if not DoesEntityExist(veh) then return nil end

    SetEntityAsMissionEntity(veh, true, true)
    SetModelAsNoLongerNeeded(hash)
    SetEntityCollision(veh, false, false)
    FreezeEntityPosition(veh, true)

    -- Teleport to studio — raise slightly so wheels don't clip, then hard freeze
    SetEntityCoordsNoOffset(veh, sx, sy, sz + 1.0, false, false, false)
    SetEntityHeading(veh, Customize.StudioHeading)
    FreezeEntityPosition(veh, true)
    SetVehicleEngineOn(veh, false, true, true)
    SetVehicleHandbrake(veh, true)

    SetVehicleDoorsLocked(veh, 2)
    SetVehicleDirtLevel(veh, 0.0)
    SetVehicleColours(veh, vehicleColor.primary, vehicleColor.secondary)
    SetVehicleExtraColours(veh, 0, 0)
    spawnedEntity = veh
    return veh
end

local function SpawnStudioObject(modelName)
    local hash = GetHashKey(modelName)
    if not LoadModel(hash) then return nil end

    local sx, sy, sz = Customize.StudioCoords.x, Customize.StudioCoords.y, Customize.StudioCoords.z

    local playerPos = GetEntityCoords(PlayerPedId())
    local obj = CreateObject(hash, playerPos.x, playerPos.y, playerPos.z, false, false, false)
    if not DoesEntityExist(obj) then return nil end

    SetEntityAsMissionEntity(obj, true, true)
    SetModelAsNoLongerNeeded(hash)
    SetEntityCollision(obj, false, false)
    FreezeEntityPosition(obj, true)

    -- Teleport to studio — fixed ground level
    SetEntityCoordsNoOffset(obj, sx, sy, sz, false, false, false)
    PlaceObjectOnGroundProperly(obj)
    FreezeEntityPosition(obj, true)
    SetEntityHeading(obj, Customize.StudioHeading)
    spawnedEntity = obj
    return obj
end

local function DeleteStudioEntity()
    if spawnedEntity then
        local ent = spawnedEntity
        spawnedEntity = nil
        if DoesEntityExist(ent) then
            SetEntityAsMissionEntity(ent, true, true)
            DeleteEntity(ent)
            -- Fallback if still exists
            if DoesEntityExist(ent) then
                SetEntityAsNoLongerNeeded(ent)
                DeleteEntity(ent)
            end
        end
    end
end

local function GetEntityTargetPos()
    if captureMode ~= 'clothing' and spawnedEntity and DoesEntityExist(spawnedEntity) then
        return GetEntityCoords(spawnedEntity)
    end
    return GetEntityCoords(PlayerPedId())
end

-- ════════════════════════════════════════════════════════
-- ANIMATION HELPERS
-- ════════════════════════════════════════════════════════

local function LoadAnimDict(dict)
    RequestAnimDict(dict)
    local timeout = GetGameTimer() + 5000
    while not HasAnimDictLoaded(dict) and GetGameTimer() < timeout do Wait(10) end
    return HasAnimDictLoaded(dict)
end

local function PlayCategoryAnim(ped, animConfig)
    if not animConfig then return end
    if LoadAnimDict(animConfig.dict) then
        TaskPlayAnim(ped, animConfig.dict, animConfig.name, 8.0, -8.0, -1, animConfig.flag or 49, 0, false, false, false)
        Wait(500)
    end
end

local function StopCategoryAnim(ped)
    ClearPedTasks(ped)
    Wait(100)
end

-- ════════════════════════════════════════════════════════
-- CAPTURE LOOPS
-- ════════════════════════════════════════════════════════

local function SetupCategoryCamera(ped, cameraName)
    local preset   = Customize.CameraPresets[cameraName]
    local hasSaved = savedCameraAngles[cameraName] ~= nil
    DestroyCamera()
    captureCamera = CreateCaptureCamera(ped, preset, cameraName)
    return preset, hasSaved
end

local function ReapplyRotation(ped, preset, hasSaved)
    -- Only legacy presets without defaultAngleH need the ped rotated so the
    -- behind-the-back camera math frames the front. Modern (defaultAngleH)
    -- presets and the saved branch keep the ped at studio heading and let
    -- the orbit-positioned camera frame the shot — rotating here would flip
    -- the ped 180° relative to the preview the user just confirmed.
    if hasSaved or preset.defaultAngleH then return end
    SetEntityRotation(ped, preset.rotation.x, preset.rotation.y, preset.rotation.z + captureRotOffset, 2, false)
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

        ResetPedForCategory(ped, cat.visibleComponents, cat.componentOverrides)
        hideHeadActive = cat.hideHead or false
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

        ResetPedForCategory(ped, cat.visibleComponents, cat.componentOverrides)
        hideHeadActive = cat.hideHead or false
        local preset, hasSaved = SetupCategoryCamera(ped, cat.camera)
        PlayCategoryAnim(ped, cat.anim)

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

        StopCategoryAnim(ped)
        ClearPedProp(ped, cat.propId)
        ::nextProp::
    end
end

-- Helper: apply overlay with correct color from config
local function ApplyOverlayWithColor(ped, overlayIndex, variationId)
    SetPedHeadOverlay(ped, overlayIndex, variationId, 1.0)
    for _, cat in ipairs(Customize.OverlayCategories or {}) do
        if cat.overlayIndex == overlayIndex and cat.colorType then
            SetPedHeadOverlayColor(ped, overlayIndex, cat.colorType, cat.colorId or 1, cat.colorId or 1)
            break
        end
    end
end

-- ════════════════════════════════════════════════════════
-- OVERLAY CAPTURE LOOP
-- ════════════════════════════════════════════════════════

local function CaptureOverlays(ped, gender, selectedSet)
    local cats = Customize.OverlayCategories or {}
    local totalItems, captured = 0, 0

    for _, cat in ipairs(cats) do
        if not selectedSet or selectedSet[cat.overlayIndex] then
            totalItems = totalItems + GetPedHeadOverlayNum(cat.overlayIndex)
        end
    end

    for _, cat in ipairs(cats) do
        if isCancelled then return end
        if selectedSet and not selectedSet[cat.overlayIndex] then goto nextOverlay end

        ResetPedForCategory(ped, cat.visibleComponents, cat.componentOverrides)
        hideHeadActive = false

        -- Clear all overlays first so only the target overlay is visible
        for i = 0, 12 do SetPedHeadOverlay(ped, i, 255, 1.0) end

        local preset, hasSaved = SetupCategoryCamera(ped, cat.camera)
        local numVariations = GetPedHeadOverlayNum(cat.overlayIndex)

        for variationId = 0, numVariations - 1 do
            if isCancelled then return end
            WaitForResume()
            if isCancelled then return end

            ApplyOverlayWithColor(ped, cat.overlayIndex, variationId)
            ReapplyRotation(ped, preset, hasSaved)
            Wait(Customize.WaitAfterApply)

            local filename = ('%s/overlay_%d/%d'):format(gender, cat.overlayIndex, variationId)
            CaptureAndUpload(filename)

            captured = captured + 1
            SendProgress(captured, totalItems, cat.label)
            Wait(Customize.WaitAfterCapture)
            ThrottledWait()
        end

        ::nextOverlay::
    end
end

-- ════════════════════════════════════════════════════════
-- VEHICLE CAPTURE LOOP
-- ════════════════════════════════════════════════════════

local function CaptureVehicles(selectedModelSet)
    -- selectedModelSet contains individual model names: { ["adder"] = true, ["zentorno"] = true }
    local totalItems, captured = 0, 0
    local modelsToCapture = {}

    for model in pairs(selectedModelSet) do
        modelsToCapture[#modelsToCapture + 1] = model
        totalItems = totalItems + 1
    end
    table.sort(modelsToCapture)

    for _, model in ipairs(modelsToCapture) do
        if isCancelled then return end
        WaitForResume()
        if isCancelled then return end

        DeleteStudioEntity()
        local veh = SpawnStudioVehicle(model)
        if not veh then goto nextVeh end

        Wait(500)

        -- Verify entity position and create camera pointing at it
        local entityPos = GetEntityCoords(veh)
        local preset = Customize.CameraPresets['vehicle']
        DestroyCamera()
        captureCamera = CreateCaptureCamera(veh, preset, 'vehicle')
        Wait(Customize.WaitAfterApply)

        CaptureAndUpload('vehicles/' .. model)

        captured = captured + 1
        SendProgress(captured, totalItems, model)

        DeleteStudioEntity()
        Wait(Customize.WaitAfterCapture)
        ThrottledWait()

        ::nextVeh::
    end
end

-- ════════════════════════════════════════════════════════
-- OBJECT CAPTURE LOOP
-- ════════════════════════════════════════════════════════

local function CaptureObjects(selectedSet)
    local cats = Customize.ObjectCategories or {}
    local totalItems, captured = 0, 0

    for _, cat in ipairs(cats) do
        if not selectedSet or selectedSet[cat.model] then
            totalItems = totalItems + 1
        end
    end

    for _, cat in ipairs(cats) do
        if isCancelled then return end
        if selectedSet and not selectedSet[cat.model] then goto nextObj end
        WaitForResume()
        if isCancelled then return end

        DeleteStudioEntity()
        local obj = SpawnStudioObject(cat.model)
        if not obj then goto nextObj end

        Wait(500)

        local preset = Customize.CameraPresets['object']
        DestroyCamera()
        captureCamera = CreateCaptureCamera(obj, preset, 'object')
        Wait(Customize.WaitAfterApply)

        CaptureAndUpload('objects/' .. cat.model)

        captured = captured + 1
        SendProgress(captured, totalItems, cat.label)

        DeleteStudioEntity()
        Wait(Customize.WaitAfterCapture)
        ThrottledWait()

        ::nextObj::
    end
end

-- ════════════════════════════════════════════════════════
-- CLEANUP
-- ════════════════════════════════════════════════════════

local function CleanupCapture()
    DestroyCamera()
    DeleteStudioEntity()
    HideHUD(false)
    hideHeadActive = false
    isCapturing = false
    isPreview   = false
    isPaused    = false
    isCancelled = false
    captureMode = 'clothing'
    local ped = PlayerPedId()
    if not IsEntityVisible(ped) then SetEntityVisible(ped, true, false) end
    RestoreFullAppearance()
    TriggerServerEvent('uz_autoshot:server:resetBucket')
    SetNuiFocus(false, false)
end

-- ════════════════════════════════════════════════════════
-- RE-CAPTURE SPECIFIC ITEMS
-- ════════════════════════════════════════════════════════

local function RecaptureSpecificItems(items)
    local cameraMap, visibilityMap, animMap, overridesMap, hideHeadMap = {}, {}, {}, {}, {}
    for _, cat in ipairs(Customize.Categories) do
        local key = 'component_' .. cat.componentId
        cameraMap[key]     = cat.camera
        visibilityMap[key] = cat.visibleComponents
        overridesMap[key]  = cat.componentOverrides
        hideHeadMap[key]   = cat.hideHead or false
    end
    for _, cat in ipairs(Customize.PropCategories) do
        local key = 'prop_' .. cat.propId
        cameraMap[key]     = cat.camera
        visibilityMap[key] = cat.visibleComponents
        overridesMap[key]  = cat.componentOverrides
        hideHeadMap[key]   = cat.hideHead or false
        animMap[key]       = cat.anim
    end
    for _, cat in ipairs(Customize.OverlayCategories or {}) do
        local key = 'overlay_' .. cat.overlayIndex
        cameraMap[key]     = cat.camera
        visibilityMap[key] = cat.visibleComponents
        hideHeadMap[key]   = false
    end

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
    local currentAnim      = nil
    local captured = 0

    for _, item in ipairs(items) do
        if isCancelled then break end
        WaitForResume()
        if isCancelled then break end

        local itemKey     = item.type .. '_' .. item.id
        local visParts    = visibilityMap[itemKey]
        local animConfig  = animMap[itemKey]

        ResetPedForCategory(ped, visParts, overridesMap[itemKey])
        hideHeadActive = hideHeadMap[itemKey] or false

        local cameraKey = cameraMap[itemKey] or 'torso'
        local preset    = Customize.CameraPresets[cameraKey]
        local hasSaved  = savedCameraAngles[cameraKey] ~= nil

        if cameraKey ~= currentCameraKey then
            if currentAnim then StopCategoryAnim(ped) end
            DestroyCamera()
            captureCamera    = CreateCaptureCamera(ped, preset, cameraKey)
            currentCameraKey = cameraKey
            currentAnim      = nil
        end

        if animConfig and animConfig ~= currentAnim then
            PlayCategoryAnim(ped, animConfig)
            currentAnim = animConfig
        elseif not animConfig and currentAnim then
            StopCategoryAnim(ped)
            currentAnim = nil
        end

        if item.type == 'overlay' then
            for i = 0, 12 do SetPedHeadOverlay(ped, i, 255, 1.0) end
            ApplyOverlayWithColor(ped, item.id, item.drawable)
        elseif item.type == 'component' then
            WaitForClothingLoaded(ped, item.id, item.drawable, item.texture)
        else
            WaitForPropLoaded(ped, item.id, item.drawable, item.texture)
        end

        ReapplyRotation(ped, preset, hasSaved)
        Wait(Customize.WaitAfterApply)

        local filename
        if item.type == 'overlay' then
            filename = ('%s/overlay_%d/%d'):format(captureGender, item.id, item.drawable)
        elseif item.type == 'component' then
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

-- ════════════════════════════════════════════════════════
-- CAPTURE PREVIEW + RUN
-- ════════════════════════════════════════════════════════

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
    for _, cat in ipairs(Customize.OverlayCategories or {}) do
        local entry = { type = 'overlay', id = cat.overlayIndex, label = cat.label, camera = cat.camera }
        if includeDrawables then entry.drawables = GetPedHeadOverlayNum(cat.overlayIndex) end
        categories[#categories + 1] = entry
    end
    -- Group vehicles by class
    local vehCats = GetVehicleCategories()
    local classGroups = {}
    local classOrder = {}
    for _, cat in ipairs(vehCats) do
        local cls = cat.category or 'Other'
        if not classGroups[cls] then
            classGroups[cls] = {}
            classOrder[#classOrder + 1] = cls
        end
        classGroups[cls][#classGroups[cls] + 1] = cat.model
    end
    for _, cls in ipairs(classOrder) do
        categories[#categories + 1] = {
            type = 'vehicle', id = cls, label = cls, camera = 'vehicle',
            drawables = #classGroups[cls], models = classGroups[cls],
        }
    end
    for _, cat in ipairs(Customize.ObjectCategories or {}) do
        categories[#categories + 1] = { type = 'object', id = cat.model, label = cat.label, camera = 'object', drawables = 1 }
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

-- Full reset between capture phases — destroys everything, restores clean state
local function ResetCapturePhase()
    DestroyCamera()
    DeleteStudioEntity()
    hideHeadActive = false
    captureRotOffset = 0.0
    local ped = PlayerPedId()
    if not IsEntityVisible(ped) then SetEntityVisible(ped, true, false) end
    Wait(200)
end

-- Setup studio for vehicle/object capture phase
local function SetupEntityCapturePhase(mode)
    ResetCapturePhase()
    captureMode = mode
    local ped = PlayerPedId()
    SetEntityCoordsNoOffset(ped, Customize.StudioCoords.x, Customize.StudioCoords.y, Customize.StudioCoords.z, false, false, false)
    FreezeEntityPosition(ped, true)
    SetEntityVisible(ped, false, false)
    Wait(200)
end

local function RunCapture(selectedComponents, selectedProps, selectedVehicles, selectedObjects, selectedOverlays)
    captureRotOffset = math.deg(orbitAngleH) - Customize.StudioHeading
    DestroyOrbitCamera()
    DeleteStudioEntity()

    isPreview    = false
    isCapturing  = true
    isPaused     = false
    isCancelled  = false
    batchCounter = 0

    local compSet, propSet = {}, {}
    for _, id in ipairs(selectedComponents) do compSet[id] = true end
    for _, id in ipairs(selectedProps) do propSet[id] = true end

    local overlaySet = {}
    for _, id in ipairs(selectedOverlays or {}) do overlaySet[id] = true end

    local vehSet, objSet = {}, {}
    for _, id in ipairs(selectedVehicles or {}) do vehSet[id] = true end
    for _, id in ipairs(selectedObjects or {}) do objSet[id] = true end

    local hasPed = next(compSet) or next(propSet) or next(overlaySet)
    local hasVeh = next(vehSet)
    local hasObj = next(objSet)

    SendNUIMessage({ type = 'captureStart' })
    SetNuiFocus(false, false)
    Wait(300)

    -- ── Phase 1: Clothing + Ped Props + Overlays ──
    if hasPed and not isCancelled then
        captureMode = 'clothing'
        local ped = PlayerPedId()
        CaptureComponents(ped, captureGender, compSet)
        if not isCancelled then CaptureProps(ped, captureGender, propSet) end
        if not isCancelled then CaptureOverlays(ped, captureGender, overlaySet) end
    end

    -- ── Phase 2: Vehicles ──
    if hasVeh and not isCancelled then
        SetupEntityCapturePhase('vehicle')
        CaptureVehicles(vehSet)
    end

    -- ── Phase 3: Objects ──
    if hasObj and not isCancelled then
        SetupEntityCapturePhase('object')
        CaptureObjects(objSet)
    end

    local wasCancelled = isCancelled
    CleanupCapture()
    SendNUIMessage({ type = wasCancelled and 'captureCancelled' or 'captureComplete' })
end

local function CancelPreview()
    if not isPreview then return end
    isPreview = false
    DestroyOrbitCamera()
    DeleteStudioEntity()
    captureMode = 'clothing'
    local ped = PlayerPedId()
    if not IsEntityVisible(ped) then SetEntityVisible(ped, true, false) end
    HideHUD(false)
    RestoreFullAppearance()
    TriggerServerEvent('uz_autoshot:server:resetBucket')
    SetNuiFocus(false, false)
end

local function CloseBrowsing()
    isBrowsing = false
    DestroyOrbitCamera()
    DeleteStudioEntity()
    HideHUD(false)
    captureMode = 'clothing'
    local ped = PlayerPedId()
    if not IsEntityVisible(ped) then SetEntityVisible(ped, true, false) end
    RestoreFullAppearance()
    TriggerServerEvent('uz_autoshot:server:resetBucket')
    SetNuiFocus(false, false)
end

-- ════════════════════════════════════════════════════════
-- HEAD HIDE (chroma key mask)
-- ════════════════════════════════════════════════════════

local function DrawHeadChromaMask(ped)
    if not hideHeadActive then return end
    local gs = Customize.GreenScreen
    local r, g, b = gs.color.r, gs.color.g, gs.color.b
    local hm = Customize.HeadMask or {}

    local headBone = GetPedBoneCoords(ped, 31086, 0.0, 0.0, 0.0) -- SKEL_Head

    local function drawSphere(m)
        DrawMarker(28,
            headBone.x + (m.offsetX or 0.0),
            headBone.y + (m.offsetY or 0.0),
            headBone.z + (m.offsetZ or 0.138),
            0.0, 0.0, 0.0,
            m.rotX or 0.0, m.rotY or 0.0, m.rotZ or 0.0,
            m.sizeX or 0.12, m.sizeY or 0.15, m.sizeZ or 0.31,
            r, g, b, 255,
            false, false, 2, false, nil, nil, false)
    end

    -- HeadMask can be either a single mask table (legacy) or an array of
    -- mask tables (e.g. one for the head + one for the neck/jaw). The array
    -- form lets users stack multiple spheres so they can mask the head and
    -- the neck independently without one shape clipping clothing.
    if hm[1] then
        for _, m in ipairs(hm) do drawSphere(m) end
    else
        drawSphere(hm)
    end
end

-- ════════════════════════════════════════════════════════
-- CROSSHAIR OVERLAY (preview only)
-- ════════════════════════════════════════════════════════

local function DrawCrosshair()
    local cx, cy = 0.5, 0.5
    local size = 0.012
    local thick = 0.001
    local a = 120
    DrawRect(cx, cy, size * 2, thick, 255, 255, 255, a)
    DrawRect(cx, cy, thick, size * 2 * (16.0/9.0), 255, 255, 255, a)
    DrawRect(cx, cy, 0.003, 0.003 * (16.0/9.0), 255, 80, 80, 200)
end

-- ════════════════════════════════════════════════════════
-- DEBUG CAMERA OVERLAY (preview only)
-- ════════════════════════════════════════════════════════

local function DrawDebugText(x, y, text)
    SetTextFont(0)
    SetTextScale(0.30, 0.30)
    SetTextColour(255, 255, 255, 230)
    SetTextDropshadow(1, 0, 0, 0, 255)
    SetTextOutline()
    SetTextEntry('STRING')
    AddTextComponentString(text)
    DrawText(x, y)
end

local function DrawCameraDebugOverlay()
    if not orbitCam then return end
    local x = 0.01
    local gap = 0.018
    local lineCount = 7
    local startY = 1.0 - 0.02 - (lineCount * gap)

    local refZ
    if captureMode ~= 'clothing' and spawnedEntity and DoesEntityExist(spawnedEntity) then
        refZ = GetEntityCoords(spawnedEntity).z
    else
        refZ = GetEntityCoords(PlayerPedId()).z
    end
    local zPos = orbitCenter.z - refZ

    DrawDebugText(x, startY,             ('Preset: %s'):format(activePreviewCamera or '?'))
    DrawDebugText(x, startY + gap,       ('FOV: %.1f'):format(orbitFov))
    DrawDebugText(x, startY + gap * 2,   ('Dist: %.2f'):format(orbitDist))
    DrawDebugText(x, startY + gap * 3,   ('AngleH: %.1f'):format(math.deg(orbitAngleH)))
    DrawDebugText(x, startY + gap * 4,   ('CamZ: %.2f'):format(orbitCamZ))
    DrawDebugText(x, startY + gap * 5, ('zPos: %.2f'):format(zPos))
    DrawDebugText(x, startY + gap * 6, ('Roll: %.1f'):format(orbitRoll))
end

-- ════════════════════════════════════════════════════════
-- BACKGROUND THREAD
-- ════════════════════════════════════════════════════════

CreateThread(function()
    while true do
        local active = isCapturing or isPreview or isBrowsing
        if active then
            local ped = PlayerPedId()
            SuppressWorld()
            ClearPedTasksImmediately(ped)
            local target = (captureMode ~= 'clothing' and spawnedEntity and DoesEntityExist(spawnedEntity))
                and spawnedEntity or ped
            if Customize.TransparentBg then DrawGreenScreenAndLights(target) end
            if captureMode == 'clothing' then DrawHeadChromaMask(ped) end
            if (isPreview or isBrowsing) and not isCapturing then
                DrawCropOverlay()
                DrawCrosshair()
                DrawCameraDebugOverlay()
            end
        end
        Wait(active and 0 or 1000)
    end
end)

-- ════════════════════════════════════════════════════════
-- CLOTHING MENU
-- ════════════════════════════════════════════════════════

local function OpenClothingMenu()
    if isCapturing or isPreview then return end
    isBrowsing = true

    local ped = PlayerPedId()
    captureGender = GetPedGender(ped)
    SaveFullAppearance(ped)

    TriggerServerEvent('uz_autoshot:server:setBucket', Customize.RoutingBucket)
    Wait(500)
    HideHUD(true)

    ped = SetupCapturePed(pedAppearance.model)

    local categories = BuildCategoryList(true)
    CreateOrbitCamera(ped, categories[1] and categories[1].camera or 'torso')
    SetNuiFocus(true, true)

    SendNUIMessage({
        type       = 'openMenu',
        gender     = captureGender,
        categories = categories,
        imgExt     = Customize.TransparentBg and 'png' or (Customize.ScreenshotFormat or 'png'),
    })
end

-- ════════════════════════════════════════════════════════
-- NUI CALLBACKS
-- ════════════════════════════════════════════════════════

local function SafeCall(label, fn)
    local ok, err = xpcall(fn, debug.traceback)
    if not ok then
        print(('^1[uz_AutoShot]^0 %s failed: %s'):format(label, tostring(err)))
    end
    return ok
end

local function RecoverPlayerAfterError()
    SafeCall('destroy camera', DestroyCamera)
    SafeCall('destroy orbit camera', DestroyOrbitCamera)
    SafeCall('delete studio entity', DeleteStudioEntity)
    SafeCall('restore HUD', function() HideHUD(false) end)

    hideHeadActive = false
    isCapturing = false
    isBrowsing = false
    isPaused = false
    isCancelled = false
    isPreview = false
    captureMode = 'clothing'
    pendingCaptureUploads = {}

    SafeCall('restore player state', function()
        local ped = PlayerPedId()
        if not IsEntityVisible(ped) then SetEntityVisible(ped, true, false) end
        FreezeEntityPosition(ped, false)
        SetPlayerControl(PlayerId(), true, 0)
    end)
    SafeCall('restore appearance', RestoreFullAppearance)
    SafeCall('reset routing bucket', function() TriggerServerEvent('uz_autoshot:server:resetBucket') end)
    SafeCall('drop NUI focus', function() SetNuiFocus(false, false) end)
    SafeCall('notify NUI', function()
        SendNUIMessage({ type = 'forceClose' })
        SendNUIMessage({ type = 'captureCancelled' })
    end)
end

local function CreateSafeThread(label, fn)
    CreateThread(function()
        local ok, err = xpcall(fn, debug.traceback)
        if ok then return end

        print(('^1[uz_AutoShot]^0 %s failed: %s'):format(label, tostring(err)))
        RecoverPlayerAfterError()
    end)
end

RegisterNUICallback('startCapture', function(data, cb)
    cb('ok')
    if not isPreview then return end
    data = data or {}
    CreateSafeThread('capture run', function()
        RunCapture(data.selectedComponents or {}, data.selectedProps or {}, data.selectedVehicles or {}, data.selectedObjects or {}, data.selectedOverlays or {})
    end)
end)

RegisterNUICallback('cancelPreview', function(_, cb)
    cb('ok')
    CreateSafeThread('cancel preview', CancelPreview)
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
    cb('ok')
    CreateSafeThread('close menu', CloseBrowsing)
end)

RegisterNUICallback('applyClothing', function(data, cb)
    cb('ok')
    data = data or {}
    local ped = PlayerPedId()
    if data.itemType == 'component' then
        SetPedComponentVariation(ped, data.id, data.drawable, data.texture, 0)
    elseif data.itemType == 'prop' then
        if data.drawable == -1 then ClearPedProp(ped, data.id)
        else SetPedPropIndex(ped, data.id, data.drawable, data.texture, true) end
    elseif data.itemType == 'overlay' then
        -- Clear all overlays, then apply selected one with correct color
        for i = 0, 12 do SetPedHeadOverlay(ped, i, 255, 1.0) end
        ApplyOverlayWithColor(ped, data.id, data.drawable)
    elseif data.itemType == 'vehicle' and data.model then
        CreateSafeThread('vehicle preview apply', function()
            DeleteStudioEntity()
            Wait(0)
            SetEntityVisible(ped, false, false)
            captureMode = 'vehicle'
            SpawnStudioVehicle(data.model)
            Wait(300)
            if spawnedEntity and DoesEntityExist(spawnedEntity) then
                local entityPos = GetEntityCoords(spawnedEntity)
                local preset = Customize.CameraPresets['vehicle']
                if preset then
                    orbitCenter = vector3(entityPos.x, entityPos.y, entityPos.z + preset.zPos)
                    UpdateOrbitCamera()
                end
            end
        end)
    end
end)

local function HandleSetCameraPreset(data)
    data = data or {}
    local cam = data.camera or 'torso'
    activePreviewCamera = cam

    local isEntityMode = data.categoryType == 'vehicle' or data.categoryType == 'object'

    if not isEntityMode then
        SetOrbitPreset(cam)
    end

    if (isPreview or isBrowsing) and data.categoryType and data.categoryId ~= nil then
        if isEntityMode then
            -- Must run in a thread because we need Wait() for model loading
            -- Token prevents race conditions when switching quickly
            entitySpawnToken = entitySpawnToken + 1
            local myToken = entitySpawnToken

            CreateSafeThread('entity preview spawn', function()
                local ped = PlayerPedId()

                -- Delete previous entity first
                DeleteStudioEntity()
                Wait(0)
                if entitySpawnToken ~= myToken then return end

                SetEntityVisible(ped, false, false)
                hideHeadActive = false
                captureMode = data.categoryType

                if data.categoryType == 'vehicle' then
                    -- categoryId is class name; spawn first model of that class, or use firstModel if provided
                    local modelToSpawn = data.firstModel
                    if not modelToSpawn then
                        for _, cat in ipairs(GetVehicleCategories()) do
                            if cat.category == data.categoryId then
                                modelToSpawn = cat.model
                                break
                            end
                        end
                    end
                    if modelToSpawn then
                        SpawnStudioVehicle(modelToSpawn)
                    end
                else
                    SpawnStudioObject(data.categoryId)
                end

                Wait(300)
                if entitySpawnToken ~= myToken then
                    -- A newer spawn request came in, delete what we just spawned
                    DeleteStudioEntity()
                    return
                end

                if spawnedEntity and DoesEntityExist(spawnedEntity) then
                    local entityPos = GetEntityCoords(spawnedEntity)
                    local preset = Customize.CameraPresets[cam]
                    if preset then
                        orbitCenter   = vector3(entityPos.x, entityPos.y, entityPos.z + preset.zPos)
                        orbitBaseDist = preset.dist or 8.0
                        orbitDist     = orbitBaseDist
                        orbitFov      = preset.fov
                        orbitAngleH   = math.rad(preset.defaultAngleH or 225.0)
                        orbitCamZ     = preset.defaultCamZ or 0.0
                        orbitRoll     = preset.defaultRoll or 0.0
                        if orbitCam then SetCamFov(orbitCam, orbitFov) end
                        UpdateOrbitCamera()
                    end
                end
            end)
        else
            local ped = PlayerPedId()

            -- Switching to clothing/prop preview
            if captureMode ~= 'clothing' then
                DeleteStudioEntity()
                SetEntityVisible(ped, true, false)
                captureMode = 'clothing'
            end

            local visComps = {}
            local previewDraw = 0
            local compOverrides = nil
            local shouldHideHead = false

            if data.categoryType == 'component' then
                for _, cat in ipairs(Customize.Categories) do
                    if cat.componentId == data.categoryId then
                        visComps = cat.visibleComponents or {}
                        previewDraw = cat.previewDrawable or 0
                        compOverrides = cat.componentOverrides
                        shouldHideHead = cat.hideHead or false
                        break
                    end
                end
            elseif data.categoryType == 'overlay' then
                for _, cat in ipairs(Customize.OverlayCategories or {}) do
                    if cat.overlayIndex == data.categoryId then
                        visComps = cat.visibleComponents or {}
                        compOverrides = cat.componentOverrides
                        break
                    end
                end
            else
                for _, cat in ipairs(Customize.PropCategories) do
                    if cat.propId == data.categoryId then
                        visComps = cat.visibleComponents or {}
                        previewDraw = cat.previewDrawable or 0
                        compOverrides = cat.componentOverrides
                        shouldHideHead = cat.hideHead or false
                        break
                    end
                end
            end

            hideHeadActive = shouldHideHead
            ResetPedForCategory(ped, visComps, compOverrides)
            -- Always clear overlays when switching categories
            for i = 0, 12 do SetPedHeadOverlay(ped, i, 255, 1.0) end

            if data.categoryType == 'overlay' then
                -- Show first variation as preview with correct color
                ApplyOverlayWithColor(ped, data.categoryId, 0)
            elseif data.categoryType == 'component' then
                SetPedComponentVariation(ped, data.categoryId, previewDraw, 0, 0)
            else
                SetPedPropIndex(ped, data.categoryId, previewDraw, 0, true)
            end
        end
    end

    if savedCameraAngles[cam] then
        local saved = savedCameraAngles[cam]
        orbitAngleH   = saved.angleH
        orbitDist     = saved.dist
        orbitFov      = saved.fov
        orbitCamZ     = saved.camZ or 0.0
        orbitRoll     = saved.roll or 0.0
        if saved.zPos then
            local refZ
            if captureMode ~= 'clothing' and spawnedEntity and DoesEntityExist(spawnedEntity) then
                refZ = GetEntityCoords(spawnedEntity).z
            else
                refZ = GetEntityCoords(PlayerPedId()).z
            end
            orbitCenter = vector3(orbitCenter.x, orbitCenter.y, refZ + saved.zPos)
        end
        if orbitCam then SetCamFov(orbitCam, orbitFov) end
        UpdateOrbitCamera()
    end
end

RegisterNUICallback('setCameraPreset', function(data, cb)
    cb('ok')
    CreateSafeThread('set camera preset', function() HandleSetCameraPreset(data) end)
end)

RegisterNUICallback('saveCameraAngle', function(data, cb)
    data = data or {}
    local cam = data.camera or activePreviewCamera
    if cam and orbitCam then
        -- Use entity coords as reference for vehicle/object, ped coords for clothing
        local refZ
        if captureMode ~= 'clothing' and spawnedEntity and DoesEntityExist(spawnedEntity) then
            refZ = GetEntityCoords(spawnedEntity).z
        else
            refZ = GetEntityCoords(PlayerPedId()).z
        end
        savedCameraAngles[cam] = {
            angleH = orbitAngleH,
            dist   = orbitDist,   fov  = orbitFov,
            zPos   = orbitCenter.z - refZ,
            camZ   = orbitCamZ,   roll = orbitRoll,
        }
        cb({ saved = true, camera = cam })
    else
        cb({ saved = false })
    end
end)

RegisterNUICallback('getCameraValues', function(_, cb)
    if orbitCam then
        local refZ
        if captureMode ~= 'clothing' and spawnedEntity and DoesEntityExist(spawnedEntity) then
            refZ = GetEntityCoords(spawnedEntity).z
        else
            refZ = GetEntityCoords(PlayerPedId()).z
        end
        local vals = {
            preset = activePreviewCamera or '?',
            fov    = tonumber(('%.1f'):format(orbitFov)),
            dist   = tonumber(('%.2f'):format(orbitDist)),
            angleH = tonumber(('%.1f'):format(math.deg(orbitAngleH))),
            camZ   = tonumber(('%.2f'):format(orbitCamZ)),
            zPos   = tonumber(('%.2f'):format(orbitCenter.z - refZ)),
            roll   = tonumber(('%.1f'):format(orbitRoll)),
        }
        local luaStr = ('{ fov = %s, zPos = %s, rotation = vector3(0.0, 0.0, 0.0), dist = %s, defaultAngleH = %s, defaultCamZ = %s, defaultRoll = %s }'):format(
            vals.fov, vals.zPos, vals.dist, vals.angleH, vals.camZ, vals.roll)
        print(('[uz_AutoShot] %s = %s'):format(vals.preset, luaStr))
        vals.luaFormat = luaStr
        cb(vals)
    else
        cb({})
    end
end)

RegisterNUICallback('rotateCamera', function(data, cb)
    data = data or {}
    if orbitCam then
        orbitAngleH = orbitAngleH - (data.deltaX or 0) * 0.005
        orbitCamZ   = orbitCamZ - (data.deltaY or 0) * 0.003
        UpdateOrbitCamera()
    end
    cb('ok')
end)

RegisterNUICallback('zoomCamera', function(data, cb)
    data = data or {}
    if orbitCam then
        local maxDist = captureMode == 'vehicle' and 20.0 or captureMode == 'object' and 10.0 or 5.0
        orbitDist = math.max(0.1, math.min(maxDist, orbitDist + (data.delta or 0) * 0.1))
        UpdateOrbitCamera()
    end
    cb('ok')
end)

RegisterNUICallback('rollCamera', function(data, cb)
    data = data or {}
    if orbitCam then
        orbitRoll = orbitRoll + (data.deltaX or 0) * 0.3
        UpdateOrbitCamera()
    end
    cb('ok')
end)

RegisterNUICallback('adjustZPos', function(data, cb)
    data = data or {}
    if orbitCam then
        local delta = data.delta or 0
        orbitCenter = vector3(orbitCenter.x, orbitCenter.y, orbitCenter.z + delta)
        UpdateOrbitCamera()
    end
    cb('ok')
end)

RegisterNUICallback('adjustFov', function(data, cb)
    data = data or {}
    if orbitCam then
        orbitFov = math.max(5.0, math.min(120.0, orbitFov + (data.delta or 0)))
        SetCamFov(orbitCam, orbitFov)
    end
    cb('ok')
end)

RegisterNUICallback('resetCameraPreset', function(_, cb)
    if orbitCam and activePreviewCamera then
        SetOrbitPreset(activePreviewCamera)
    end
    cb('ok')
end)

RegisterNUICallback('setVehicleColor', function(data, cb)
    data = data or {}
    vehicleColor.primary   = data.primary   or vehicleColor.primary
    vehicleColor.secondary = data.secondary or vehicleColor.secondary
    if spawnedEntity and DoesEntityExist(spawnedEntity) and captureMode == 'vehicle' then
        SetVehicleColours(spawnedEntity, vehicleColor.primary, vehicleColor.secondary)
    end
    cb('ok')
end)

RegisterNUICallback('getTextures', function(data, cb)
    data = data or {}
    local ped = PlayerPedId()
    local count
    if data.itemType == 'overlay' or data.id == nil or data.drawable == nil then
        count = 0
    elseif data.itemType == 'component' then
        count = GetNumberOfPedTextureVariations(ped, data.id, data.drawable)
    else
        count = GetNumberOfPedPropTextureVariations(ped, data.id, data.drawable)
    end
    cb({ count = count })
end)

RegisterNUICallback('enterRecapturePreview', function(_, cb)
    cb('ok')
    CreateSafeThread('enter recapture preview', function()
        isPreview = true
        HideHUD(true)
        TriggerServerEvent('uz_autoshot:server:setBucket', Customize.RoutingBucket)
        Wait(500)

        local ped = SetupCapturePed(pedAppearance.model or GetEntityModel(PlayerPedId()))

        DestroyOrbitCamera()
        CreateOrbitCamera(ped)
    end)
end)

RegisterNUICallback('cancelRecapturePreview', function(_, cb)
    cb('ok')
    CreateSafeThread('cancel recapture preview', function()
        isPreview  = false
        isBrowsing = false
        DestroyOrbitCamera()
        HideHUD(false)
        RestoreFullAppearance()
        TriggerServerEvent('uz_autoshot:server:resetBucket')
        SetNuiFocus(false, false)
    end)
end)

RegisterNUICallback('recaptureItems', function(data, cb)
    cb('ok')
    data = data or {}
    local items = data.items or {}
    if #items == 0 then return end

    captureGender    = GetPedGender(PlayerPedId())
    captureRotOffset = 0.0
    isPreview        = false
    isBrowsing       = false

    local cameraMap = {}
    for _, cat in ipairs(Customize.Categories) do cameraMap['component_' .. cat.componentId] = cat.camera end
    for _, cat in ipairs(Customize.PropCategories) do cameraMap['prop_' .. cat.propId] = cat.camera end
    for _, cat in ipairs(Customize.OverlayCategories or {}) do cameraMap['overlay_' .. cat.overlayIndex] = cat.camera end

    savedCameraAngles = {}
    if orbitCam then
        local orbitState = { angleH = orbitAngleH, dist = orbitDist, fov = orbitFov, camZ = orbitCamZ, roll = orbitRoll }
        local seen = {}
        for _, item in ipairs(items) do
            local cam = cameraMap[item.type .. '_' .. item.id]
            if cam and not seen[cam] then
                savedCameraAngles[cam] = orbitState
                seen[cam] = true
            end
        end
    end

    CreateSafeThread('recapture items', function()
        DestroyOrbitCamera()
        RecaptureSpecificItems(items)
    end)
end)

-- ════════════════════════════════════════════════════════
-- COMMANDS
-- ════════════════════════════════════════════════════════

RegisterCommand(Customize.Command, function() EnterCapturePreview() end, Customize.AceRestricted)
RegisterCommand(Customize.MenuCommand, function() OpenClothingMenu() end, Customize.AceRestricted)

-- Single vehicle capture command
RegisterCommand('shotcar', function(_, args)
    if isCapturing or isPreview then return end
    if #args == 0 then
        BeginTextCommandThefeedPost('STRING')
        AddTextComponentSubstringPlayerName('Usage: /shotcar <modelname>')
        EndTextCommandThefeedPostTicker(false, false)
        return
    end

    local modelName = args[1]
    local hash = GetHashKey(modelName)
    if not IsModelAVehicle(hash) then
        BeginTextCommandThefeedPost('STRING')
        AddTextComponentSubstringPlayerName('Invalid vehicle model: ' .. modelName)
        EndTextCommandThefeedPostTicker(false, false)
        return
    end

    isPreview = true
    captureMode = 'vehicle'
    SaveFullAppearance(PlayerPedId())
    TriggerServerEvent('uz_autoshot:server:setBucket', Customize.RoutingBucket)
    Wait(500)
    HideHUD(true)

    local ped = PlayerPedId()
    SetEntityCoordsNoOffset(ped, Customize.StudioCoords.x, Customize.StudioCoords.y, Customize.StudioCoords.z, false, false, false)
    FreezeEntityPosition(ped, true)
    SetEntityVisible(ped, false, false)

    SpawnStudioVehicle(modelName)
    Wait(300)

    if spawnedEntity and DoesEntityExist(spawnedEntity) then
        local entityPos = GetEntityCoords(spawnedEntity)
        local preset = Customize.CameraPresets['vehicle']
        orbitCenter = vector3(entityPos.x, entityPos.y, entityPos.z + preset.zPos)
        orbitBaseDist = preset.dist or 8.0
        orbitDist = orbitBaseDist
        orbitFov = preset.fov
        orbitAngleH = math.rad(preset.defaultAngleH or 225.0)
        orbitCamZ = preset.defaultCamZ or 1.5
        orbitRoll = preset.defaultRoll or 0.0

        local camX = orbitCenter.x + orbitDist * math.sin(orbitAngleH)
        local camY = orbitCenter.y - orbitDist * math.cos(orbitAngleH)
        orbitCam = CreateCamWithParams('DEFAULT_SCRIPTED_CAMERA', camX, camY, orbitCenter.z, 0.0, 0.0, 0.0, orbitFov, false, 0)
        SetCamActive(orbitCam, true)
        RenderScriptCams(true, false, 0, true, true)
        UpdateOrbitCamera()

        SendNUIMessage({ type = 'singleEntityPreview', model = modelName, entityType = 'vehicle' })
        SetNuiFocus(true, true)
    else
        print('^3[uz_AutoShot]^0 Vehicle preview failed to spawn: ' .. modelName)
        CancelPreview()
    end
end, Customize.AceRestricted)

-- Single object capture command
RegisterCommand('shotprop', function(_, args)
    if isCapturing or isPreview then return end
    if #args == 0 then
        BeginTextCommandThefeedPost('STRING')
        AddTextComponentSubstringPlayerName('Usage: /shotprop <modelname>')
        EndTextCommandThefeedPostTicker(false, false)
        return
    end

    local modelName = args[1]
    local hash = GetHashKey(modelName)
    if not IsModelValid(hash) then
        BeginTextCommandThefeedPost('STRING')
        AddTextComponentSubstringPlayerName('Invalid object model: ' .. modelName)
        EndTextCommandThefeedPostTicker(false, false)
        return
    end

    isPreview = true
    captureMode = 'object'
    SaveFullAppearance(PlayerPedId())
    TriggerServerEvent('uz_autoshot:server:setBucket', Customize.RoutingBucket)
    Wait(500)
    HideHUD(true)

    local ped = PlayerPedId()
    SetEntityCoordsNoOffset(ped, Customize.StudioCoords.x, Customize.StudioCoords.y, Customize.StudioCoords.z, false, false, false)
    FreezeEntityPosition(ped, true)
    SetEntityVisible(ped, false, false)

    SpawnStudioObject(modelName)
    Wait(300)

    if spawnedEntity and DoesEntityExist(spawnedEntity) then
        local entityPos = GetEntityCoords(spawnedEntity)
        local preset = Customize.CameraPresets['object']
        orbitCenter = vector3(entityPos.x, entityPos.y, entityPos.z + preset.zPos)
        orbitBaseDist = preset.dist or 3.0
        orbitDist = orbitBaseDist
        orbitFov = preset.fov
        orbitAngleH = math.rad(preset.defaultAngleH or 225.0)
        orbitCamZ = preset.defaultCamZ or 0.5
        orbitRoll = preset.defaultRoll or 0.0

        local camX = orbitCenter.x + orbitDist * math.sin(orbitAngleH)
        local camY = orbitCenter.y - orbitDist * math.cos(orbitAngleH)
        orbitCam = CreateCamWithParams('DEFAULT_SCRIPTED_CAMERA', camX, camY, orbitCenter.z, 0.0, 0.0, 0.0, orbitFov, false, 0)
        SetCamActive(orbitCam, true)
        RenderScriptCams(true, false, 0, true, true)
        UpdateOrbitCamera()

        SendNUIMessage({ type = 'singleEntityPreview', model = modelName, entityType = 'object' })
        SetNuiFocus(true, true)
    else
        print('^3[uz_AutoShot]^0 Object preview failed to spawn: ' .. modelName)
        CancelPreview()
    end
end, Customize.AceRestricted)

-- Single entity capture confirmation
RegisterNUICallback('confirmSingleCapture', function(data, cb)
    cb('ok')
    if not isPreview or not spawnedEntity then return end
    data = data or {}
    local model = data.model or ''
    local eType = data.entityType or 'object'

    CreateSafeThread('single entity capture', function()
        captureRotOffset = math.deg(orbitAngleH) - Customize.StudioHeading
        DestroyOrbitCamera()
        isPreview = false
        isCapturing = true
        batchCounter = 0

        SendNUIMessage({ type = 'captureStart' })
        SetNuiFocus(false, false)
        Wait(300)

        local preset = Customize.CameraPresets[eType == 'vehicle' and 'vehicle' or 'object']
        DestroyCamera()
        captureCamera = CreateCaptureCamera(spawnedEntity, preset, eType)
        Wait(Customize.WaitAfterApply)

        local folder = eType == 'vehicle' and 'vehicles' or 'objects'
        CaptureAndUpload(folder .. '/' .. model)

        SendProgress(1, 1, model)
        CleanupCapture()
        SendNUIMessage({ type = 'captureComplete' })
    end)
end)

RegisterNUICallback('cancelSingleCapture', function(_, cb)
    cb('ok')
    CreateSafeThread('cancel single capture', CancelPreview)
end)

-- ════════════════════════════════════════════════════════
-- EXPORTS
-- ════════════════════════════════════════════════════════

exports('getPhotoURL', function(gender, itemType, id, drawable, texture)
    local prefix = itemType == 'overlay' and 'overlay_' or (itemType == 'prop' and 'prop_' or '')
    if itemType == 'overlay' then
        return ('https://cfx-nui-uz_AutoShot/shots/%s/%s%d/%d.%s'):format(
            gender, prefix, id, drawable, Customize.ScreenshotFormat
        )
    end
    return ('https://cfx-nui-uz_AutoShot/shots/%s/%s%d/%d_%d.%s'):format(
        gender, prefix, id, drawable, texture, Customize.ScreenshotFormat
    )
end)

exports('getShotsBaseURL', function()
    return 'https://cfx-nui-uz_AutoShot/shots'
end)

exports('getPhotoFormat', function()
    return Customize.ScreenshotFormat
end)

exports('getVehiclePhotoURL', function(modelName)
    return ('https://cfx-nui-uz_AutoShot/shots/vehicles/%s.%s'):format(modelName, Customize.ScreenshotFormat)
end)

exports('getObjectPhotoURL', function(modelName)
    return ('https://cfx-nui-uz_AutoShot/shots/objects/%s.%s'):format(modelName, Customize.ScreenshotFormat)
end)

-- ════════════════════════════════════════════════════════
-- INPUT THREAD
-- ════════════════════════════════════════════════════════

CreateThread(function()
    while true do
        -- Polling input every frame only matters when one of these states is
        -- live; otherwise sleep so the script costs ~nothing in resmon while
        -- idle. 500ms wake-up is well below the studio + bucket setup that
        -- follows /shotmaker, so user-perceptible activation lag is unchanged.
        -- Paused captures fall through here too — no input expected, sleep.
        local pollInput = isBrowsing or isPreview or (isCapturing and not isPaused)
        Wait(pollInput and 0 or 500)

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
