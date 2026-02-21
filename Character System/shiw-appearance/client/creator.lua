RSGCore = exports['rsg-core']:GetCoreObject()
local isLoggedIn = false
BucketId = GetRandomIntInRange(0, 0xffffff)
ComponentsMale = {}
ComponentsFemale = {}
LoadedComponents = {}
CreatorCache = {}
CreatorPed = nil
IsInCharCreation = false

-- ★ NAKED BODY SYSTEM
CurrentSkinData = CurrentSkinData or {}

MenuData = {}

TriggerEvent("rsg-menubase:getData", function(call)
    MenuData = call
end)

Firstname = nil
Lastname = nil
Nationality = nil
Selectedsex = nil
Birthdate = nil
Cid = nil

local Data = require 'data.features'
local Overlays = require 'data.overlays'
local clotheslist = require 'data.clothes_list'
local hairs_list = require 'data.hairs_list'
local appearanceApplyToken = 0

exports('GetClothesList', function()
    return clotheslist
end)

exports('GetHairsList', function()
    return hairs_list
end)

-- ==========================================
-- ★ BODY MORPH: Обёртка для creator.lua
-- Лёгкая версия: для превью в реальном времени (без Wait/UpdatePedVariation)
-- ==========================================
function ApplyAndSaveBodyMorph(ped, skinData)
    if not skinData then return end
    if not ped or not DoesEntityExist(ped) then ped = PlayerPedId() end

    LoadedComponents = LoadedComponents or {}
    LoadedComponents.body_size = skinData.body_size
    LoadedComponents.body_waist = skinData.body_waist
    LoadedComponents.chest_size = skinData.chest_size
    LoadedComponents.height = skinData.height

    -- ★ Лёгкая версия: хеши + face features, БЕЗ Wait/UpdatePedVariation
    -- (для превью в меню создания персонажа)
    ApplyAllBodyMorph(ped, skinData)
end

-- ★ Тяжёлая версия: для загрузки персонажа (с Wait + UpdatePedVariation + повторное применение)
function ApplyAndSaveBodyMorphFull(ped, skinData)
    if not skinData then return end
    if not ped or not DoesEntityExist(ped) then ped = PlayerPedId() end

    LoadedComponents = LoadedComponents or {}
    LoadedComponents.body_size = skinData.body_size
    LoadedComponents.body_waist = skinData.body_waist
    LoadedComponents.chest_size = skinData.chest_size
    LoadedComponents.height = skinData.height

    -- ★ Полная версия: хеши + UpdatePedVariation + повторное face features
    LoadAllBodyShape(ped, skinData)
end

-- ==========================================
-- НЕДОСТАЮЩИЕ ФУНКЦИИ
-- ==========================================

function FixIssues(ped)
    if not ped or not DoesEntityExist(ped) then
        ped = PlayerPedId()
    end

    Citizen.InvokeNative(0xD710A5007C2AC539, ped, GetHashKey("heads"), 0)
    Citizen.InvokeNative(0xD710A5007C2AC539, ped, GetHashKey("eyes"), 0)
    Citizen.InvokeNative(0xD710A5007C2AC539, ped, GetHashKey("hair"), 0)
    Citizen.InvokeNative(0xD710A5007C2AC539, ped, GetHashKey("teeth"), 0)

    Citizen.InvokeNative(0xD710A5007C2AC539, ped, GetHashKey("shirts_full"), 0)
    Citizen.InvokeNative(0xD710A5007C2AC539, ped, GetHashKey("pants"), 0)
    Citizen.InvokeNative(0xD710A5007C2AC539, ped, GetHashKey("boots"), 0)
    Citizen.InvokeNative(0xD710A5007C2AC539, ped, GetHashKey("vests"), 0)
    Citizen.InvokeNative(0xD710A5007C2AC539, ped, GetHashKey("coats"), 0)
    Citizen.InvokeNative(0xD710A5007C2AC539, ped, GetHashKey("coats_closed"), 0)
    Citizen.InvokeNative(0xD710A5007C2AC539, ped, GetHashKey("hats"), 0)
    Citizen.InvokeNative(0xD710A5007C2AC539, ped, GetHashKey("gloves"), 0)
    Citizen.InvokeNative(0xD710A5007C2AC539, ped, GetHashKey("neckwear"), 0)
    Citizen.InvokeNative(0xD710A5007C2AC539, ped, GetHashKey("chaps"), 0)
    Citizen.InvokeNative(0xD710A5007C2AC539, ped, GetHashKey("masks"), 0)
    Citizen.InvokeNative(0xD710A5007C2AC539, ped, GetHashKey("suspenders"), 0)
    Citizen.InvokeNative(0xD710A5007C2AC539, ped, GetHashKey("cloaks"), 0)
    Citizen.InvokeNative(0xD710A5007C2AC539, ped, GetHashKey("ponchos"), 0)
    Citizen.InvokeNative(0xD710A5007C2AC539, ped, GetHashKey("spurs"), 0)
    Citizen.InvokeNative(0xD710A5007C2AC539, ped, GetHashKey("eyewear"), 0)

    Citizen.InvokeNative(0xD710A5007C2AC539, ped, GetHashKey("gunbelts"), 0)
    Citizen.InvokeNative(0xD710A5007C2AC539, ped, GetHashKey("loadouts"), 0)
    Citizen.InvokeNative(0xD710A5007C2AC539, ped, GetHashKey("holsters_left"), 0)
    Citizen.InvokeNative(0xD710A5007C2AC539, ped, GetHashKey("holsters_right"), 0)
    Citizen.InvokeNative(0xD710A5007C2AC539, ped, GetHashKey("belt_buckles"), 0)
    Citizen.InvokeNative(0xD710A5007C2AC539, ped, GetHashKey("holsters_crossdraw"), 0)
    Citizen.InvokeNative(0xD710A5007C2AC539, ped, GetHashKey("holsters_knife"), 0)
    Citizen.InvokeNative(0xD710A5007C2AC539, ped, GetHashKey("accessories"), 0)
    Citizen.InvokeNative(0xD710A5007C2AC539, ped, GetHashKey("satchels"), 0)
    Citizen.InvokeNative(0xD710A5007C2AC539, ped, GetHashKey("belts"), 0)

    Citizen.InvokeNative(0xD710A5007C2AC539, ped, 0x0662AC34, 0)
    Citizen.InvokeNative(0xD710A5007C2AC539, ped, 0xB6B6122D, 0)
    Citizen.InvokeNative(0xD710A5007C2AC539, ped, 0x777EC6EF, 0)
    Citizen.InvokeNative(0xD710A5007C2AC539, ped, 0x485EE834, 0)
    Citizen.InvokeNative(0xD710A5007C2AC539, ped, 0xE06D47B7, 0)
    Citizen.InvokeNative(0xD710A5007C2AC539, ped, 0x9925C067, 0)
    Citizen.InvokeNative(0xD710A5007C2AC539, ped, 0xF1542D11, 0)
    Citizen.InvokeNative(0xD710A5007C2AC539, ped, 0x9B2C8B89, 0)
    Citizen.InvokeNative(0xD710A5007C2AC539, ped, 0x877A2CF7, 0)
    Citizen.InvokeNative(0xD710A5007C2AC539, ped, 0x72E6EF74, 0)
    Citizen.InvokeNative(0xD710A5007C2AC539, ped, 0x3F1F01E5, 0)
    Citizen.InvokeNative(0xD710A5007C2AC539, ped, 0xDA0E2C55, 0)

    Citizen.InvokeNative(0x704C908E9C405136, ped)
    Citizen.InvokeNative(0xCC8CA3E88256E58F, ped, false, true, true, true, false)

    print('[RSG-Appearance] FixIssues: All components cleared for ped ' .. tostring(ped))
    return true
end

function FixIssuesLight(ped)
    if not ped or not DoesEntityExist(ped) then
        ped = PlayerPedId()
    end

    Citizen.InvokeNative(0xD710A5007C2AC539, ped, GetHashKey("gunbelts"), 0)
    Citizen.InvokeNative(0xD710A5007C2AC539, ped, GetHashKey("loadouts"), 0)
    Citizen.InvokeNative(0xD710A5007C2AC539, ped, GetHashKey("holsters_left"), 0)
    Citizen.InvokeNative(0xD710A5007C2AC539, ped, GetHashKey("holsters_right"), 0)
    Citizen.InvokeNative(0xD710A5007C2AC539, ped, 0xF1542D11, 0)
    Citizen.InvokeNative(0xD710A5007C2AC539, ped, 0x9B2C8B89, 0)
    Citizen.InvokeNative(0xD710A5007C2AC539, ped, 0x877A2CF7, 0)
    Citizen.InvokeNative(0xD710A5007C2AC539, ped, 0x3F1F01E5, 0)
    Citizen.InvokeNative(0xD710A5007C2AC539, ped, 0xDA0E2C55, 0)

    print('[RSG-Appearance] FixIssuesLight: Cleared gunbelts only')
    return true
end

local CreatorCoords = {
    male = {x = -559.6, y = -3781.0, z = 237.55, h = 110.0},
    female = {x = -559.6, y = -3781.0, z = 237.55, h = 110.0}
}

local CreatorCameraPos = {
    x = -559.909, y = -3776.3, z = 239.1,
    pitch = -10.0, roll = 0.0, yaw = 270.0, fov = 50.0
}

local CreatorImaps = {
    -1699673416,
    1679934574,
    183712523,
}

local CreatorCam = nil
local gPeds = {}
local ImapsLoaded = false

-- ★ FIX: Добавлен Request (0x59BD177A1A48600A) перед Apply — при высоком пинге
-- без Request компонент может не загрузиться из стриминга
local function NativeSetPedComponentEnabled(ped, componentHash)
    Citizen.InvokeNative(0x59BD177A1A48600A, ped, componentHash)
    Citizen.InvokeNative(0xD3A7B003ED343FD9, ped, componentHash, true, true, true)
end

local function NativeHasPedComponentLoaded(ped)
    return Citizen.InvokeNative(0xA0BC8FAED8CFEB3C, ped)
end

local function NativeUpdatePedVariation(ped)
    Citizen.InvokeNative(0x704C908E9C405136, ped)
    Citizen.InvokeNative(0xCC8CA3E88256E58F, ped, false, true, true, true, false)
end

local function NativeRemoveComponent(ped, categoryHash)
    Citizen.InvokeNative(0xD710A5007C2AC539, ped, categoryHash, 0)
end

local function LoadImaps()
    if ImapsLoaded then return end
    for _, imap in pairs(CreatorImaps) do
        RequestImap(imap)
    end
    ImapsLoaded = true
    Wait(500)
end

function SpawnPeds()
    print('[RSG-Appearance] SpawnPeds started, Selectedsex=' .. tostring(Selectedsex))

    DoScreenFadeOut(300)
    Wait(300)

    if CreatorPed and DoesEntityExist(CreatorPed) then
        DeleteEntity(CreatorPed)
        CreatorPed = nil
    end

    TriggerServerEvent('rsg-appearance:server:SetPlayerBucket', BucketId)
    Wait(100)

    LoadImaps()

    Selectedsex = Selectedsex or 1
    local isMale = Selectedsex == 1
    local modelName = isMale and 'mp_male' or 'mp_female'
    local gender = isMale and 'male' or 'female'
    local coords = isMale and CreatorCoords.male or CreatorCoords.female

    print('[RSG-Appearance] Creating ped: ' .. modelName)

    local modelHash = GetHashKey(modelName)
    RequestModel(modelHash, false)

    -- ★ FIX: Добавлен таймаут загрузки модели (до 15с вместо бесконечного цикла)
    local loadTimeout = 0
    while not HasModelLoaded(modelHash) and loadTimeout < 300 do
        Wait(50)
        loadTimeout = loadTimeout + 1
    end
    
    if not HasModelLoaded(modelHash) then
        print('[RSG-Appearance] Model load TIMEOUT for ' .. modelName .. '! Retrying...')
        RequestModel(modelHash, false)
        local retryTimeout = 0
        while not HasModelLoaded(modelHash) and retryTimeout < 200 do
            Wait(50)
            retryTimeout = retryTimeout + 1
        end
        if not HasModelLoaded(modelHash) then
            print('[RSG-Appearance] Model load FAILED after retry!')
            DoScreenFadeIn(300)
            return
        end
    end

    CreatorPed = CreatePed(modelHash, coords.x, coords.y, coords.z, coords.h, true, false, false, false)

    if not DoesEntityExist(CreatorPed) then
        print('[RSG-Appearance] Failed to create ped!')
        DoScreenFadeIn(300)
        return
    end

    print('[RSG-Appearance] Ped created: ' .. tostring(CreatorPed))

    Citizen.InvokeNative(0x283978A15512B2FE, CreatorPed, true)
    Citizen.InvokeNative(0x58A850EAEE20FAA3, CreatorPed)

    -- ★ FIX: Ждём пока пед будет готов к рендеру (вместо фиксированных 100мс)
    local readyT = 0
    while not Citizen.InvokeNative(0xA0BC8FAED8CFEB3C, CreatorPed) and readyT < 100 do
        Wait(50)
        readyT = readyT + 1
    end
    Wait(200)

    NetworkSetEntityInvisibleToNetwork(CreatorPed, true)
    SetEntityHeading(CreatorPed, coords.h)
    FreezeEntityPosition(CreatorPed, true)

    local playerPed = PlayerPedId()
    SetEntityInvincible(playerPed, true)
    SetEntityVisible(playerPed, false)
    NetworkSetEntityInvisibleToNetwork(playerPed, true)
    SetEntityCoords(playerPed, coords.x, coords.y, coords.z + 2.0, false, false, false, false)

    CreatorCache = {
        sex = Selectedsex,
        head = isMale and 18 or 2,
        skin_tone = 1,
        body_size = 3,
        body_waist = 11,
        chest_size = 6,
        height = 100,
        hair = { model = 0, color = 1 },
        beard = { model = 0, color = 1 },
        eyes_color = 5,
    }

    ApplyCreatorComponents(CreatorPed, gender, CreatorCache)

    FixIssues(CreatorPed)
    Wait(200)

    -- ★ FIX: Увеличены паузы между этапами загрузки для высокого пинга
    LoadBoody(CreatorPed, CreatorCache)
    Wait(300)
    LoadHead(CreatorPed, CreatorCache)
    Wait(200)
    LoadEyes(CreatorPed, CreatorCache)
    Wait(100)

    -- ★ В создателе используем только хеши (без face features, они конфликтуют с хешами)
    LoadBodyFeature(CreatorPed, CreatorCache.body_waist or 11, Data.Appearance.body_waist)
    LoadBodyFeature(CreatorPed, CreatorCache.body_size or 3, Data.Appearance.body_size)
    LoadBodyFeature(CreatorPed, CreatorCache.chest_size or 6, Data.Appearance.chest_size)
    LoadHeight(CreatorPed, CreatorCache)

    NativeRemoveComponent(CreatorPed, GetHashKey("pants"))

    NativeUpdatePedVariation(CreatorPed)

    CreateCreatorCamera()

    RequestCollisionAtCoord(coords.x, coords.y, coords.z)

    StartCreatorLighting()

    Wait(300)
    DoScreenFadeIn(300)

    print('[RSG-Appearance] SpawnPeds completed')

    IsInCharCreation = true
    FirstMenu()
end

function ApplyCreatorComponents(ped, gender, cache)
    local componentsData = require 'data.clothes_list'

    local categories = {}
    for _, item in ipairs(componentsData) do
        if item.ped_type == gender and item.is_multiplayer then
            local cat = item.category_hashname
            if not categories[cat] then
                categories[cat] = {}
            end
            if item.hashname and item.hashname ~= "" then
                table.insert(categories[cat], item.hash)
            end
        end
    end

    local headIndex = cache.head or 1
    local skinTone = cache.skin_tone or 1

    if categories['heads'] and #categories['heads'] > 0 then
        local idx = math.min(headIndex, #categories['heads'])
        local hash = categories['heads'][idx]
        if hash then
            NativeSetPedComponentEnabled(ped, hash)
            WaitForComponent(ped, hash)
        end
    end

    if categories['BODIES_UPPER'] and #categories['BODIES_UPPER'] > 0 then
        local idx = math.min(skinTone, #categories['BODIES_UPPER'])
        local hash = categories['BODIES_UPPER'][idx]
        if hash then
            NativeSetPedComponentEnabled(ped, hash)
            WaitForComponent(ped, hash)
        end
    end

    if categories['eyes'] and #categories['eyes'] > 0 then
        local eyeColor = cache.eyes_color or 1
        local idx = math.min(eyeColor, #categories['eyes'])
        local hash = categories['eyes'][idx]
        if hash then
            NativeSetPedComponentEnabled(ped, hash)
            WaitForComponent(ped, hash)
        end
    end

    if categories['teeth'] and #categories['teeth'] > 0 then
        local hash = categories['teeth'][1]
        if hash then
            NativeSetPedComponentEnabled(ped, hash)
            WaitForComponent(ped, hash)
        end
    end
end

function GetComponentHash(categoryItems, modelIndex, textureIndex)
    local idx = ((modelIndex - 1) * 6) + textureIndex
    if idx < 1 then idx = 1 end
    if idx > #categoryItems then idx = #categoryItems end
    return categoryItems[idx] and categoryItems[idx].hash
end

-- ★ FIX: Увеличен таймаут с 500мс до 3с для высокого пинга
-- При повторной неудаче — перезапрос компонента
function WaitForComponent(ped, componentHash)
    local timeout = 0
    while not NativeHasPedComponentLoaded(ped) and timeout < 150 do
        Wait(20)
        timeout = timeout + 1
    end
    if timeout >= 150 and componentHash then
        print('[RSG-Appearance] WaitForComponent timeout, retrying hash: ' .. tostring(componentHash))
        Citizen.InvokeNative(0x59BD177A1A48600A, ped, componentHash)
        Citizen.InvokeNative(0xD3A7B003ED343FD9, ped, componentHash, true, true, true)
        local t2 = 0
        while not NativeHasPedComponentLoaded(ped) and t2 < 100 do
            Wait(20)
            t2 = t2 + 1
        end
    end
end

function CreateCreatorCamera()
    DestroyAllCams(true)

    local camX = -561.4157
    local camY = -3780.966
    local camZ = 239.005
    local pitch = -4.2146
    local roll = -0.0007
    local yaw = -93.8802
    local fov = 35.0

    CreatorCam = CreateCam("DEFAULT_SCRIPTED_CAMERA", true)
    SetCamCoord(CreatorCam, camX, camY, camZ)
    SetCamRot(CreatorCam, pitch, roll, yaw, 2)
    SetCamFov(CreatorCam, fov)
    SetCamActive(CreatorCam, true)
    RenderScriptCams(true, false, 500, true, true)

    local isMale = Selectedsex == 1
    local coords = isMale and CreatorCoords.male or CreatorCoords.female
    SetFocusPosAndVel(coords.x, coords.y, coords.z, 0.0, 0.0, 0.0)
end

function DestroyCreatorCamera()
    StopCreatorLighting()
    IsInCharCreation = false

    DestroyAllCams(true)
    RenderScriptCams(false, true, 500, true, true)

    if CreatorPed and DoesEntityExist(CreatorPed) then
        DeleteEntity(CreatorPed)
        CreatorPed = nil
    end

    local playerPed = PlayerPedId()
    SetFocusEntity(playerPed)
    SetEntityInvincible(playerPed, false)
    SetEntityVisible(playerPed, true)
    NetworkSetEntityInvisibleToNetwork(playerPed, false)

    TriggerServerEvent('rsg-appearance:server:SetPlayerBucket', 0)
end

function GetCreatorPed()
    return CreatorPed
end

exports('DestroyCreatorCamera', DestroyCreatorCamera)
exports('GetCreatorPed', GetCreatorPed)

-- ==========================================
-- ОСВЕЩЕНИЕ
-- ==========================================

local LightingThread = nil
local IsLightingActive = false

function StartCreatorLighting()
    if IsLightingActive then return end
    IsLightingActive = true

    pcall(function()
        exports.weathersync:setSyncEnabled(false)
        exports.weathersync:setMyWeather("sunny", 0)
        exports.weathersync:setMyTime(12, 0, 0, 0, 1)
    end)

    LightingThread = CreateThread(function()
        while IsLightingActive and IsInCharCreation do
            Wait(0)
            Citizen.InvokeNative(0x669E223E64B1903C, 12, 0, 0)
            if CreatorPed and DoesEntityExist(CreatorPed) then
                local pedCoords = GetEntityCoords(CreatorPed)
                DrawLightWithRange(pedCoords.x - 2.0, pedCoords.y, pedCoords.z + 1.0, 255, 255, 255, 5.0, 500.0)
                DrawLightWithRange(pedCoords.x - 1.0, pedCoords.y + 1.5, pedCoords.z + 0.5, 255, 255, 255, 4.0, 300.0)
                DrawLightWithRange(pedCoords.x - 1.0, pedCoords.y - 1.5, pedCoords.z + 0.5, 255, 255, 255, 4.0, 300.0)
                DrawLightWithRange(pedCoords.x, pedCoords.y, pedCoords.z + 2.5, 255, 255, 255, 5.0, 400.0)
            end
        end
    end)
end

function StopCreatorLighting()
    IsLightingActive = false
    pcall(function()
        exports.weathersync:setSyncEnabled(true)
    end)
end

function RotateCreatorPedLeft()
    if CreatorPed and DoesEntityExist(CreatorPed) then
        SetEntityHeading(CreatorPed, GetEntityHeading(CreatorPed) - 15.0)
    end
end

function RotateCreatorPedRight()
    if CreatorPed and DoesEntityExist(CreatorPed) then
        SetEntityHeading(CreatorPed, GetEntityHeading(CreatorPed) + 15.0)
    end
end

exports('StartCreatorLighting', StartCreatorLighting)
exports('StopCreatorLighting', StopCreatorLighting)
exports('RotateCreatorPedLeft', RotateCreatorPedLeft)
exports('RotateCreatorPedRight', RotateCreatorPedRight)

local CameraOffsetZ = 0.0
local CameraZoom = 0.0

function MoveCreatorCamera(direction)
    if not CreatorCam or not DoesCamExist(CreatorCam) then return end

    if direction == 'up' then
        CameraOffsetZ = CameraOffsetZ + 0.3
    elseif direction == 'down' then
        CameraOffsetZ = CameraOffsetZ - 0.3
    elseif direction == 'in' then
        CameraZoom = CameraZoom + 0.5
    elseif direction == 'out' then
        CameraZoom = CameraZoom - 0.5
    end

    CameraOffsetZ = math.max(-1.5, math.min(1.5, CameraOffsetZ))
    CameraZoom = math.max(-2.0, math.min(3.0, CameraZoom))

    SetCamCoord(CreatorCam, -561.4157 + CameraZoom, -3780.966, 239.005 + CameraOffsetZ)

    if CreatorPed and DoesEntityExist(CreatorPed) then
        local pedCoords = GetEntityCoords(CreatorPed)
        PointCamAtCoord(CreatorCam, pedCoords.x, pedCoords.y, pedCoords.z + 0.5 + CameraOffsetZ)
    end
end

function ResetCameraOffsets()
    CameraOffsetZ = 0.0
    CameraZoom = 0.0
end

function ResetCreatorCamera()
    if not CreatorCam or not DoesCamExist(CreatorCam) then return end
    CameraOffsetZ = 0.0
    CameraZoom = 0.0
    SetCamCoord(CreatorCam, -561.4157, -3780.966, 239.005)
    if CreatorPed and DoesEntityExist(CreatorPed) then
        local pedCoords = GetEntityCoords(CreatorPed)
        PointCamAtCoord(CreatorCam, pedCoords.x, pedCoords.y, pedCoords.z + 0.5)
    end
end

exports('MoveCreatorCamera', MoveCreatorCamera)
exports('ResetCreatorCamera', ResetCreatorCamera)

function LoadModel(ped, model)
    local isMpModel = (model == `mp_male` or model == `mp_female` or model == GetHashKey("mp_male") or model == GetHashKey("mp_female"))

    RequestModel(model, false)
    local timeout = 0
    while not HasModelLoaded(model) and timeout < 100 do
        Wait(100)
        timeout = timeout + 1
    end

    if not HasModelLoaded(model) then
        return false
    end

    Citizen.InvokeNative(0x00A1CADD00108836, PlayerId(), model, false, false, false, false)
    Wait(1000)

    local newPed = PlayerPedId()
    if isMpModel then
        Citizen.InvokeNative(0x283978A15512B2FE, newPed, true)
        Wait(500)
    end

    SetModelAsNoLongerNeeded(model)
    return true
end

-- ==========================================
-- ОСТАЛЬНОЙ КОД
-- ==========================================

-- ★ ФЛАГ: был ли скин уже применён (для фоллбэка)
_G._SkinAppliedThisSession = false

AddEventHandler('RSGCore:Client:OnPlayerLoaded', function()
    isLoggedIn = true
    PlayerData = RSGCore.Functions.GetPlayerData()
    
    -- ★ ФОЛЛБЭК: Если через 6 секунд скин не был применён — запрашиваем его у сервера
    -- Это решает проблему "not safe for net" когда серверный push приходит раньше регистрации
    _G._SkinAppliedThisSession = false
    SetTimeout(6000, function()
        if not _G._SkinAppliedThisSession then
            print('[RSG-Appearance] Fallback: Skin was NOT applied after 6s, requesting from server...')
            TriggerServerEvent('rsg-appearance:server:LoadSkin')
        end
    end)
end)

RegisterNetEvent('RSGCore:Client:OnPlayerUnload', function()
    isLoggedIn = false
    PlayerData = {}
end)

local MainMenus = {
    ["body"] = function() OpenBodyMenu() end,
    ["face"] = function() OpenFaceMenu() end,
    ["hair"] = function() OpenHairMenu() end,
    ["makeup"] = function() OpenMakeupMenu() end
}

local BodyFunctions = {
    ["head"] = function(target, data)
        LoadHead(target, data)
        LoadOverlays(target, data)
    end,
    ["face_width"] = function(target, data) LoadFeatures(target, data) end,
    ["skin_tone"] = function(target, data)
        LoadBoody(target, data)
        LoadOverlays(target, data)
    end,
    ["body_size"] = function(target, data)
        LoadBodyFeature(target, data.body_size, Data.Appearance.body_size)
        LoadBoody(target, data)
    end,
    ["body_waist"] = function(target, data)
        -- ★ Clamp индекс к размеру таблицы хешей
        local waistIdx = data.body_waist or 11
        if waistIdx > #Data.Appearance.body_waist then
            waistIdx = #Data.Appearance.body_waist
        end
        LoadBodyFeature(target, waistIdx, Data.Appearance.body_waist)
    end,
    ["chest_size"] = function(target, data)
        LoadBodyFeature(target, data.chest_size, Data.Appearance.chest_size)
    end,
    ["height"] = function(target, data) LoadHeight(target, data) end
}

local FaceFunctions = {
    ["eyes"] = function() OpenEyesMenu() end,
    ["eyelids"] = function() OpenEyelidsMenu() end,
    ["eyebrows"] = function() OpenEyebrowsMenu() end,
    ["nose"] = function() OpenNoseMenu() end,
    ["mouth"] = function() OpenMouthMenu() end,
    ["cheekbones"] = function() OpenCheekbonesMenu() end,
    ["jaw"] = function() OpenJawMenu() end,
    ["ears"] = function() OpenEarsMenu() end,
    ["chin"] = function() OpenChinMenu() end,
    ["defects"] = function() OpenDefectsMenu() end
}

local HairFunctions = {
    ["hair"] = function(target, data) LoadHair(target, data) end,
    ["beard"] = function(target, data) LoadBeard(target, data) end
}

local EyesFunctions = {
    ["eyes_color"] = function(target, data) LoadEyes(target, data) end,
    ["eyes_depth"] = function(target, data) LoadFeatures(target, data) end,
    ["eyes_angle"] = function(target, data) LoadFeatures(target, data) end,
    ["eyes_distance"] = function(target, data) LoadFeatures(target, data) end
}

local EyelidsFunctions = {
    ["eyelid_height"] = function(target, data) LoadFeatures(target, data) end,
    ["eyelid_width"] = function(target, data) LoadFeatures(target, data) end
}

local EyebrowsFunctions = {
    ["eyebrows_t"] = function(target, data) LoadOverlays(target, data) end,
    ["eyebrows_op"] = function(target, data) LoadOverlays(target, data) end,
    ["eyebrows_id"] = function(target, data) LoadOverlays(target, data) end,
    ["eyebrows_c1"] = function(target, data) LoadOverlays(target, data) end,
    ["eyebrow_height"] = function(target, data) LoadFeatures(target, data) end,
    ["eyebrow_width"] = function(target, data) LoadFeatures(target, data) end,
    ["eyebrow_depth"] = function(target, data) LoadFeatures(target, data) end
}

CreateThread(function()
    for i, v in pairs(clotheslist) do
        if v.category_hashname == "BODIES_LOWER" or v.category_hashname == "BODIES_UPPER" or v.category_hashname ==
            "heads" or v.category_hashname == "hair" or v.category_hashname == "teeth" or v.category_hashname == "eyes" then
            if v.ped_type == "female" and v.is_multiplayer and v.hashname ~= "" then
                if ComponentsFemale[v.category_hashname] == nil then
                    ComponentsFemale[v.category_hashname] = {}
                end
                table.insert(ComponentsFemale[v.category_hashname], v.hash)
            elseif v.ped_type == "male" and v.is_multiplayer and v.hashname ~= "" then
                if ComponentsMale[v.category_hashname] == nil then
                    ComponentsMale[v.category_hashname] = {}
                end
                table.insert(ComponentsMale[v.category_hashname], v.hash)
            end
        end
    end
    if not IsImapActive(183712523) then RequestImap(183712523) end
    if not IsImapActive(-1699673416) then RequestImap(-1699673416) end
    if not IsImapActive(1679934574) then RequestImap(1679934574) end
end)

function ApplySkin()
    local _Target = PlayerPedId()
    local citizenid = RSGCore.Functions.GetPlayerData().citizenid
    local currentHealth = LocalPlayer.state.health or GetEntityHealth(_Target)
    local dirtClothes = GetAttributeBaseRank(_Target, 16)
    local dirtHat = GetAttributeBaseRank(_Target, 17)
    local dirtSkin = GetAttributeBaseRank(_Target, 22)

    local promise = promise.new()
    RSGCore.Functions.TriggerCallback('rsg-multicharacter:server:getAppearance', function(data)
        local _SkinData = data.skin
        local _Clothes = data.clothes
        if _Target == PlayerPedId() then
            local model = GetPedModel(tonumber(_SkinData.sex))
            LoadModel(PlayerPedId(), model)
            _Target = PlayerPedId()
            SetEntityAlpha(_Target, 0)
            LoadedComponents = _SkinData
        end
        FixIssues(_Target)
        LoadHeight(_Target, _SkinData)
        LoadBoody(_Target, _SkinData)
        -- ★ Применяем body shape (хеши + face features) ПЕРЕД LoadHead
        LoadAllBodyShape(_Target, _SkinData)
        LoadHead(_Target, _SkinData)
        LoadHair(_Target, _SkinData)
        LoadBeard(_Target, _SkinData)
        LoadEyes(_Target, _SkinData)
        LoadFeatures(_Target, _SkinData)
        LoadOverlays(_Target, _SkinData)
        SetEntityAlpha(_Target, 255)
        SetAttributeCoreValue(_Target, 0, 100)
        SetAttributeCoreValue(_Target, 1, 100)
        SetEntityHealth(_Target, currentHealth, 0)
        Citizen.InvokeNative(0x8899C244EBCF70DE, PlayerId(), 0.0)
        Citizen.InvokeNative(0xDE1B1907A83A1550, _Target, 0)
        if _Target == PlayerPedId() then
            TriggerEvent('rsg-appearance:client:ApplyClothes', _Clothes, _Target, _SkinData)
            -- ★ Body morph ПОСЛЕ одежды с задержкой (полная версия для загрузки)
            SetTimeout(2000, function()
                ApplyAndSaveBodyMorphFull(PlayerPedId(), _SkinData)
                StartBodyMorphGuard(PlayerPedId(), 10000)
            end)
        else
            for i, m in pairs(Overlays.overlay_all_layers) do
                Overlays.overlay_all_layers[i] =
                { name = m.name, visibility = 0, tx_id = 1, tx_normal = 0, tx_material = 0, tx_color_type = 0, tx_opacity = 1.0, tx_unk = 0, palette = 0, palette_color_primary = 0, palette_color_secondary = 0, palette_color_tertiary = 0, var = 0, opacity = 0.0 }
            end
        end
        SetAttributeBaseRank(_Target, 16, dirtClothes)
        SetAttributeBaseRank(_Target, 17, dirtHat)
        SetAttributeBaseRank(_Target, 22, dirtSkin)
        promise:resolve()
    end, citizenid)
    Citizen.Await(promise)
end

local function ApplySkinMultiChar(SkinData, Target, ClothesData)
    FixIssues(Target)
    LoadHeight(Target, SkinData)
    LoadBoody(Target, SkinData)
    -- ★ Применяем body shape (хеши + face features)
    LoadAllBodyShape(Target, SkinData)
    LoadHead(Target, SkinData)
    LoadHair(Target, SkinData)
    LoadBeard(Target, SkinData)
    LoadEyes(Target, SkinData)
    LoadFeatures(Target, SkinData)
    LoadOverlays(Target, SkinData)
    LoadedComponents = SkinData
    TriggerEvent('rsg-appearance:client:ApplyClothes', ClothesData, Target, SkinData)
    -- ★ Body morph ПОСЛЕ одежды с задержкой
    SetTimeout(2000, function()
        ApplyAndSaveBodyMorph(Target, SkinData)
        StartBodyMorphGuard(Target, 10000)
    end)
end

exports('ApplySkinMultiChar', ApplySkinMultiChar)

-- Дополнительные recovery-проходы после ApplySkin:
-- на высоком пинге некоторые компоненты (body/head/hair/beard) догружаются позже.
local function RunAppearanceRecoveryPass(expectedToken, skinData, passLabel)
    if expectedToken ~= appearanceApplyToken then return end
    if not skinData then return end

    local ped = PlayerPedId()
    if not ped or ped == 0 or not DoesEntityExist(ped) then return end
    if IsEntityDead(ped) or GetEntityHealth(ped) <= 0 then return end

    local hasHead = GetHeadIndex and GetHeadIndex(ped)
    local shouldForce = (not hasHead)

    -- ★ Не перезагружаем рост и одежду, если всё уже корректно — избегаем "мигания" через микросекунду
    if not shouldForce then
        if Config and Config.Debug then
            print(('[RSG-Appearance] Recovery pass (%s) SKIP — components already loaded'):format(passLabel))
        end
        return
    end

    if Config and Config.Debug then
        print(('[RSG-Appearance] Recovery pass (%s), force=%s'):format(passLabel, tostring(shouldForce)))
    end

    LoadHeight(ped, skinData)
    LoadBoody(ped, skinData)
    Wait(120)
    ApplyAndSaveBodyMorph(ped, skinData)
    LoadHead(ped, skinData)
    Wait(120)
    LoadHair(ped, skinData)
    if skinData.sex == 1 then
        LoadBeard(ped, skinData)
    end
    LoadEyes(ped, skinData)
    LoadFeatures(ped, skinData)
    LoadOverlays(ped, skinData)
    EnsureBodyIntegrity(ped, true)
    if ReapplyBodyMorph then ReapplyBodyMorph(ped) end
end

local function ScheduleAppearanceRecoveryPasses(skinData)
    appearanceApplyToken = appearanceApplyToken + 1
    local token = appearanceApplyToken

    SetTimeout(1500, function()
        RunAppearanceRecoveryPass(token, skinData, 'early')
    end)
    SetTimeout(4000, function()
        RunAppearanceRecoveryPass(token, skinData, 'mid')
    end)
    SetTimeout(8000, function()
        RunAppearanceRecoveryPass(token, skinData, 'late-check')
    end)
end

-- ★ Эвент для прямого применения скина (от /loadcharacter)
RegisterNetEvent('rsg-appearance:client:ApplySkin')
AddEventHandler('rsg-appearance:client:ApplySkin', function(skinData, clothesData)
    -- ★ Отмечаем что скин был получен (для фоллбэка в OnPlayerLoaded)
    _G._SkinAppliedThisSession = true
    
    if not skinData then
        if NakedBodyState then NakedBodyState.skinLoading = false end
        return
    end

    local ped = PlayerPedId()

    local skinToneValue = skinData.skin_tone or 1
    CurrentSkinData = {
        skin_tone = skinToneValue,
        sex = skinData.sex,
        head = skinData.head,
        body_size = skinData.body_size,
        body_waist = skinData.body_waist,
        chest_size = skinData.chest_size,
        height = skinData.height,
    }

    LoadedComponents = LoadedComponents or {}
    LoadedComponents.skin_tone = skinToneValue
    LoadedComponents.BODIES_UPPER = skinToneValue
    LoadedComponents.body_size = skinData.body_size
    LoadedComponents.body_waist = skinData.body_waist
    LoadedComponents.chest_size = skinData.chest_size
    LoadedComponents.height = skinData.height

    local isDead = IsEntityDead(ped) or GetEntityHealth(ped) <= 0
    local PlayerData = RSGCore.Functions.GetPlayerData()
    local isMetaDead = PlayerData and PlayerData.metadata and PlayerData.metadata['isdead']

    if isDead or isMetaDead then
        if NakedBodyState then NakedBodyState.skinLoading = false end
        return
    end

    print('[RSG-Appearance] ApplySkin starting...')

    LocalPlayer.state:set('isLoadingCharacter', true, true)

    local coords = GetEntityCoords(ped)
    local heading = GetEntityHeading(ped)
    local groundZ = coords.z

    FreezeEntityPosition(ped, true)

    local maxHealth = 600
    local savedHealth = GetEntityHealth(ped)
    if savedHealth < 100 then savedHealth = 100 end
    if savedHealth > maxHealth then savedHealth = maxHealth end

    local modelName = (skinData.sex == 1) and 'mp_male' or 'mp_female'
    local modelHash = GetHashKey(modelName)

    RequestModel(modelHash, false)
    local timeout = 0
    while not HasModelLoaded(modelHash) and timeout < 100 do
        Wait(100)
        timeout = timeout + 1
    end

    if not HasModelLoaded(modelHash) then
        FreezeEntityPosition(ped, false)
        LocalPlayer.state:set('isLoadingCharacter', false, true)
        if NakedBodyState then NakedBodyState.skinLoading = false end
        return
    end

    SetPlayerModel(PlayerId(), modelHash, true)
    
    -- ★ FIX: Динамическое ожидание полной инициализации модели (вместо фиксированных 100мс)
    -- При высоком пинге SetPlayerModel может требовать больше времени
    local modelTimeout = 0
    ped = PlayerPedId()
    while (not ped or not DoesEntityExist(ped) or not Citizen.InvokeNative(0xA0BC8FAED8CFEB3C, ped)) and modelTimeout < 200 do
        Wait(50)
        ped = PlayerPedId()
        modelTimeout = modelTimeout + 1
    end
    if modelTimeout >= 200 then
        print('[RSG-Appearance] WARNING: SetPlayerModel timeout (10s), continuing anyway')
    end
    Wait(200) -- Дополнительный буфер после инициализации

    ped = PlayerPedId()

    if ResetNakedBodyFlags then
        ResetNakedBodyFlags()
    elseif NakedBodyState then
        NakedBodyState.lowerApplied = false
        NakedBodyState.upperApplied = false
        NakedBodyState.lastPedId = 0
    end

    FreezeEntityPosition(ped, true)
    SetEntityHeading(ped, heading)

    Citizen.InvokeNative(0x283978A15512B2FE, ped, true)
    Citizen.InvokeNative(0x58A850EAEE20FAA3, ped)
    -- ★ FIX: Ждём пока пед будет готов к рендеру после SetRandomOutfitVariation
    local readyTimeout = 0
    while not Citizen.InvokeNative(0xA0BC8FAED8CFEB3C, ped) and readyTimeout < 100 do
        Wait(50)
        readyTimeout = readyTimeout + 1
    end
    Wait(200)

    SetEntityMaxHealth(ped, maxHealth)
    SetEntityHealth(ped, savedHealth, 0)
    SetAttributeCoreValue(ped, 0, 100)
    SetAttributeCoreValue(ped, 1, 100)
    SetEntityInvincible(ped, false)
    LocalPlayer.state:set('invincible', false, true)

    if IsEntityDead(ped) or GetEntityHealth(ped) <= 0 then
        NetworkResurrectLocalPlayer(coords.x, coords.y, groundZ, heading, true, false)
        Wait(100)
        ped = PlayerPedId()
        FreezeEntityPosition(ped, true)
        SetEntityMaxHealth(ped, maxHealth)
        SetEntityHealth(ped, savedHealth, 0)
        SetEntityInvincible(ped, false)
        LocalPlayer.state:set('invincible', false, true)
    end

    FixIssues(ped)
    Wait(100)

    LoadHeight(ped, skinData)
    LoadBoody(ped, skinData)
    Wait(300)
    -- ★ Морф задаём сразу после тела (хеши + face features)
    ApplyAndSaveBodyMorph(ped, skinData)
    LoadHead(ped, skinData)
    Wait(300)

    EnsureBodyIntegrity(ped, true)
    Wait(200)

    LoadHair(ped, skinData)
    Wait(200)

    if skinData.sex == 1 then
        LoadBeard(ped, skinData)
        Wait(200)
    end

    LoadEyes(ped, skinData)
    Wait(100)

    LoadFeatures(ped, skinData)
    Wait(100)

    LoadOverlays(ped, skinData)
    Wait(200)

    Citizen.InvokeNative(0x704C908E9C405136, ped)
    if NativeUpdatePedVariation then NativeUpdatePedVariation(ped) else Citizen.InvokeNative(0xCC8CA3E88256E58F, ped, false, true, true, true, false) end
    -- ★ Восстанавливаем body morph после UpdatePedVariation
    if ReapplyBodyMorph then ReapplyBodyMorph(ped) end

    -- ★ Применяем одежду через LoadClothingFromInventory (единственный чистый путь)
    -- ВМЕСТО: ApplyClothes + delayed re-sync (двойное применение, конфликты MetaPed)
    -- ТЕПЕРЬ: Один вызов LoadClothingFromInventory который:
    --   1) Запрашивает одежду из инвентаря (актуальные данные)
    --   2) Применяет hash-based через NativeSetPedComponentEnabledClothes
    --   3) Проверяет body integrity + naked body
    --   4) После этого снятие/одевание работает штатно
    print('[RSG-Appearance] Loading clothes via clean path (LoadClothingFromInventory)...')

    local _clothesLoaded = false
    local _clothesFound = false

    if LoadClothingFromInventory then
        LoadClothingFromInventory(function(success, count)
            _clothesFound = (success == true)
            _clothesLoaded = true
            print('[RSG-Appearance] Clothes loaded: ' .. tostring(count or 0) .. ' items, success=' .. tostring(success))
        end)
    else
        print('[RSG-Appearance] WARNING: LoadClothingFromInventory not available!')
        _clothesLoaded = true
    end

    -- Ждём завершения загрузки одежды (до 15 сек)
    local waitTimeout = 0
    while not _clothesLoaded and waitTimeout < 150 do
        Wait(100)
        waitTimeout = waitTimeout + 1
    end
    Wait(100)

    -- Если одежды нет — проверяем naked body
    if not _clothesFound then
        print('[RSG-Appearance] No clothes in inventory — checking naked body')
        EnsureBodyIntegrity(ped, false)
        Wait(500)
        if NakedBodyState then
            NakedBodyState.lowerApplied = false
            NakedBodyState.upperApplied = false
        end
        if CheckAndApplyNakedBodyIfNeeded then
            CheckAndApplyNakedBodyIfNeeded(ped, {})
        else
            TriggerEvent('rsg-appearance:client:CheckNakedBody')
        end
        Wait(200)
    end

    -- ★ Body morph САМЫМ ПОСЛЕДНИМ после всех UpdatePedVariation от одежды
    ped = PlayerPedId()
    ApplyAndSaveBodyMorph(ped, skinData)
    StartBodyMorphGuard(ped, 10000)

    ped = PlayerPedId()
    local currentHealth = GetEntityHealth(ped)
    if currentHealth > maxHealth then
        SetEntityHealth(ped, maxHealth, 0)
    end

    SetEntityInvincible(ped, false)
    LocalPlayer.state:set('invincible', false, true)

    Wait(100)
    FreezeEntityPosition(ped, false)
    Wait(200)

    LocalPlayer.state:set('isLoadingCharacter', false, true)

    SetEntityInvincible(ped, false)
    LocalPlayer.state:set('invincible', false, true)

    print('[RSG-Appearance] Skin applied successfully, health: ' .. GetEntityHealth(ped) .. '/' .. maxHealth)

    if NakedBodyState then
        NakedBodyState.skinLoading = false
    end

    -- ★ Игра может сбросить морф при разморозке / снятии isLoadingCharacter — переприменяем (сокращено для уменьшения моргания)
    local function finalBodyMorphPass()
        local p = PlayerPedId()
        if not DoesEntityExist(p) then return end
        ApplyAndSaveBodyMorph(p, skinData)
    end
    SetTimeout(800, finalBodyMorphPass)
    SetTimeout(1800, finalBodyMorphPass)

    -- ★ Один отложенный CheckNakedBody (после стабилизации ClothesCache и bodies)
    SetTimeout(1200, function()
        local currentPed = PlayerPedId()
        if not DoesEntityExist(currentPed) then return end
        if NakedBodyState then
            NakedBodyState.lowerApplied = false
            NakedBodyState.upperApplied = false
        end
        local cache = nil
        pcall(function() cache = exports['rsg-appearance']:GetClothesCache() end)
        if CheckAndApplyNakedBodyIfNeeded then
            CheckAndApplyNakedBodyIfNeeded(currentPed, cache)
        else
            TriggerEvent('rsg-appearance:client:CheckNakedBody')
        end
    end)

    -- На высоком пинге часть компонентов может догрузиться с опозданием.
    -- Плановые recovery-проходы возвращают голову/тело/волосы/бороду в корректное состояние.
    ScheduleAppearanceRecoveryPasses(skinData)

    TriggerEvent('rsg-appearance:client:ApplySkinComplete')
end)

-- ★ Когда одежда загружена из инвентаря (OnPlayerLoaded → LoadClothingFromInventory), переприменяем морф
AddEventHandler('rsg-clothing:client:clothingLoaded', function()
    SetTimeout(500, function()
        local p = PlayerPedId()
        if not DoesEntityExist(p) then return end
        if ReapplyBodyMorph then ReapplyBodyMorph(p) end
        -- ★ УБРАНО: NativeUpdatePedVariation сбрасывает body morph face features!
    end)
end)

-- ==========================================
-- ForceReloadBodyParts
-- ==========================================
function ForceReloadBodyParts(ped, skinData)
    if not ped or not DoesEntityExist(ped) then ped = PlayerPedId() end

    local isMale = IsPedMale(ped)
    local skinTone = skinData and skinData.skin_tone or 1
    local gender = isMale and 'male' or 'female'

    local success, cl = pcall(function() return require 'data.clothes_list' end)
    if not success or not cl then return end

    local bodies_upper = {}
    local bodies_lower = {}

    for _, item in ipairs(cl) do
        if item.ped_type == gender and item.is_multiplayer then
            if item.hashname and item.hashname ~= "" then
                if item.category_hashname == 'BODIES_UPPER' then
                    table.insert(bodies_upper, {hash = item.hash, hashname = item.hashname})
                elseif item.category_hashname == 'BODIES_LOWER' then
                    table.insert(bodies_lower, {hash = item.hash, hashname = item.hashname})
                end
            end
        end
    end

    local function ApplyBodyComponent(ped, bodyData, componentName)
        if not bodyData or not bodyData.hash then return false end
        Citizen.InvokeNative(0x59BD177A1A48600A, ped, GetHashKey(string.lower(componentName)))
        Wait(50)
        Citizen.InvokeNative(0x59BD177A1A48600A, ped, bodyData.hash)
        Wait(50)
        Citizen.InvokeNative(0xD3A7B003ED343FD9, ped, bodyData.hash, true, true, true)
        local t = 0
        while not Citizen.InvokeNative(0xA0BC8FAED8CFEB3C, ped) and t < 50 do
            Wait(20)
            t = t + 1
        end
        return t < 50
    end

    if #bodies_upper > 0 then
        local idx = math.min(skinTone, #bodies_upper)
        if idx < 1 then idx = 1 end
        ApplyBodyComponent(ped, bodies_upper[idx], "BODIES_UPPER")
    end
    Wait(100)
    if #bodies_lower > 0 then
        local idx = math.min(skinTone, #bodies_lower)
        if idx < 1 then idx = 1 end
        ApplyBodyComponent(ped, bodies_lower[idx], "BODIES_LOWER")
    end
    Wait(150)
    Citizen.InvokeNative(0x704C908E9C405136, ped)
    Citizen.InvokeNative(0xCC8CA3E88256E58F, ped, false, true, true, true, false)
end

function TableLength(t)
    if not t then return 0 end
    local count = 0
    for _ in pairs(t) do count = count + 1 end
    return count
end

RegisterNetEvent('rsg-appearance:client:OpenCreator', function(data, empty)
    if data then Cid = data.cid
    elseif empty then Skinkosong = true end
    StartCreator()
end)

RegisterCommand('loadskin', function(source, args, raw)
    local ped = PlayerPedId()
    local isdead = IsEntityDead(ped) or GetEntityHealth(ped) <= 0
    local PlayerData = RSGCore.Functions.GetPlayerData()
    local isMetaDead = PlayerData and PlayerData.metadata and PlayerData.metadata['isdead']
    if isdead or isMetaDead then
        lib.notify({ title = 'Ошибка', description = 'Нельзя загрузить скин пока вы мертвы', type = 'error' })
        return
    end
    if LocalPlayer.state.invincible then return end
    local cuffed = IsPedCuffed(ped)
    local hogtied = Citizen.InvokeNative(0x3AA24CCC0D451379, ped)
    local lassoed = Citizen.InvokeNative(0x9682F850056C9ADE, ped)
    local dragged = Citizen.InvokeNative(0xEF3A8772F085B4AA, ped)
    local ragdoll = IsPedRagdoll(ped)
    local falling = IsPedFalling(ped)
    local isJailed = PlayerData and PlayerData.metadata and PlayerData.metadata["injail"] or 0
    if cuffed or hogtied or lassoed or dragged or ragdoll or falling or isJailed > 0 then return end
    LocalPlayer.state:set('invincible', true, true)
    ApplySkin()
    SetTimeout(500, function()
        LocalPlayer.state:set('invincible', false, true)
        SetEntityInvincible(PlayerPedId(), false)
    end)
end, false)

function StartCreator()
    TriggerServerEvent('rsg-appearance:server:SetPlayerBucket', BucketId)
    Wait(1)
    for i, m in pairs(Overlays.overlay_all_layers) do
        Overlays.overlay_all_layers[i] =
        {name = m.name, visibility = 0, tx_id = 1, tx_normal = 0, tx_material = 0, tx_color_type = 0, tx_opacity = 1.0, tx_unk = 0, palette = 0, palette_color_primary = 0, palette_color_secondary = 0, palette_color_tertiary = 0, var = 0, opacity = 0.0}
    end
    MenuData.CloseAll()
    SpawnPeds()
end

-- ★ Проверка строки: только кириллица, пробелы и дефисы (блокировка латиницы, цифр, спецсимволов)
function checkStrings(str)
    if not str or str == '' then
        lib.notify({ title = 'Ошибка', description = 'Поле не может быть пустым', type = 'error' })
        return false
    end
    if #str < 2 then
        lib.notify({ title = 'Ошибка', description = 'Минимум 2 символа', type = 'error' })
        return false
    end
    -- Убираем допустимые символы (пробелы и дефисы)
    local cleaned = str:gsub('[%s%-]', '')
    if cleaned == '' then
        lib.notify({ title = 'Ошибка', description = 'Поле не может состоять только из пробелов', type = 'error' })
        return false
    end
    -- Запрещаем латиницу
    if cleaned:match('[a-zA-Z]') then
        lib.notify({ title = 'Ошибка', description = 'Только кириллица. Латинские буквы запрещены', type = 'error' })
        return false
    end
    -- Запрещаем цифры
    if cleaned:match('[%d]') then
        lib.notify({ title = 'Ошибка', description = 'Цифры запрещены в имени/фамилии', type = 'error' })
        return false
    end
    -- Запрещаем спецсимволы (кроме пробелов/дефисов которые уже убрали)
    if cleaned:match('[!@#$%%%^&*%(%)_+=~`%[%]{}<>|/\\%.,%?;:\"\']') then
        lib.notify({ title = 'Ошибка', description = 'Спецсимволы запрещены', type = 'error' })
        return false
    end
    return true
end

function FirstMenu()
    MenuData.CloseAll()
    local elements = {}
    local elementIndexes = {}

    if Skinkosong then
        Labelsave = RSG.Texts.firsmenu.Start
        Valuesave = 'save'
    end

    if (IsInCharCreation or Skinkosong) then
        elements[#elements + 1] = {
            label = locale('creator.appearance.label'),
            value = "appearance",
            desc = locale('creator.appearance.desc'),
        }
    end

    if IsInCharCreation and not Skinkosong then
        elements[#elements + 1] = {
            label = Firstname or RSG.Texts.firsmenu.label_firstname .. "<br><span style='opacity:0.6;'>" .. RSG.Texts.firsmenu.none .. "</span>",
            value = "firstname",
            desc = locale('creator.firstname.desc'),
        }
        elementIndexes.firstname = #elements

        elements[#elements + 1] = {
            label = Lastname or RSG.Texts.firsmenu.label_lastname .. "<br><span style='opacity:0.6;'>" .. RSG.Texts.firsmenu.none .. "</span>",
            value = "lastname",
            desc = locale('creator.lastname.desc')
        }
        elementIndexes.lastname = #elements

        elements[#elements + 1] = {
            label = Nationality or RSG.Texts.firsmenu.Nationality .. "<br><span style='opacity:0.6;'>" .. RSG.Texts.firsmenu.none .. "</span>",
            value = "nationality",
            desc = locale('creator.nationality.desc')
        }
        elementIndexes.nationality = #elements

        elements[#elements + 1] = {
            label = Birthdate or RSG.Texts.firsmenu.Birthdate .. "<br><span style='opacity:0.6;'>" .. RSG.Texts.firsmenu.none .. "</span>",
            value = "birthdate",
            desc = locale('creator.birthdate.desc')
        }
        elementIndexes.birthdate = #elements
    end

    elements[#elements + 1] = {
        label = Labelsave or ("<span style='color: Grey;'>" .. RSG.Texts.firsmenu.Start .. "<br>" .. RSG.Texts.firsmenu.empty .. "</span>"),
        value = Valuesave or 'not',
        desc = ""
    }
    elementIndexes.save = #elements

    MenuData.Open('default', GetCurrentResourceName(), 'FirstMenu',
        {
            title = RSG.Texts.Creator,
            subtext = RSG.Texts.Options,
            align = RSG.Texts.align,
            elements = elements,
            itemHeight = "4vh"
        }, function(data, menu)
            if (data.current.value == 'appearance') then return MainMenu() end

            if (data.current.value == 'firstname') then
                :: noMatch ::
                local dialog = lib.inputDialog(locale('creator.firstname.input.header'), {{type='input',required=true,icon='user-pen',label=locale('creator.firstname.input.label'),placeholder=locale('creator.firstname.input.placeholder')}})
                if not dialog then return false end
                if not checkStrings(dialog[1]) then goto noMatch end
                Firstname = dialog[1]
                menu.setElement(elementIndexes.firstname, "label", Firstname)
                menu.setElement(elementIndexes.firstname, "itemHeight", "4vh")
                menu.refresh()
            end

            if (data.current.value == 'lastname') then
                :: noMatch ::
                local dialog = lib.inputDialog(locale('creator.lastname.input.header'), {{type='input',required=true,icon='user-pen',label=locale('creator.lastname.input.label'),placeholder=locale('creator.lastname.input.placeholder')}})
                if not dialog then return false end
                if not checkStrings(dialog[1]) then goto noMatch end
                Lastname = dialog[1]
                menu.setElement(elementIndexes.lastname, "label", Lastname)
                menu.setElement(elementIndexes.lastname, "itemHeight", "4vh")
                menu.refresh()
            end

            if (data.current.value == 'nationality') then
                :: noMatch ::
                local dialog = lib.inputDialog(locale('creator.nationality.input.header'), {{type='input',required=true,icon='user-shield',label=locale('creator.nationality.input.label'),placeholder=locale('creator.nationality.input.placeholder')}})
                if not dialog then return false end
                if not checkStrings(dialog[1]) then goto noMatch end
                Nationality = dialog[1]
                menu.setElement(elementIndexes.nationality, "label", Nationality)
                menu.setElement(elementIndexes.nationality, "itemHeight", "4vh")
                menu.refresh()
            end

            if (data.current.value == 'birthdate') then
                local dialog = lib.inputDialog(locale('creator.birthdate.input.header'), {{type='date',required=true,icon='calendar-days',label=locale('creator.birthdate.input.label'),format='YYYY-MM-DD',returnString=true,min='1750-01-01',max='1900-01-01',default='1870-01-01'}})
                if not dialog then return false end
                Birthdate = dialog[1]
                Labelsave = RSG.Texts.firsmenu.Start
                Valuesave = 'save'
                menu.setElement(elementIndexes.birthdate, "label", Birthdate)
                menu.setElement(elementIndexes.birthdate, "itemHeight", "4vh")
                menu.removeElementByIndex(elementIndexes.save)
                menu.addNewElement({label = RSG.Texts.firsmenu.Start, value = Valuesave, desc = ""})
                menu.refresh()
            end

            if data.current.value == 'save' then
                LoadedComponents = CreatorCache
                if Skinkosong then
                    MenuData.CloseAll()
                    Skinkosong = false
                    Firstname = RSGCore.Functions.GetPlayerData().charinfo.firstname
                    Lastname = RSGCore.Functions.GetPlayerData().charinfo.lastname
                    FotoMugshots()
                    Wait(2000)
                    TriggerServerEvent('rsg-clothing:server:giveStarterClothes')
                elseif Firstname and Lastname and Nationality and Selectedsex and Birthdate and Cid then
                    MenuData.CloseAll()
                    local newData = {firstname=Firstname,lastname=Lastname,nationality=Nationality,gender=Selectedsex==1 and 0 or 1,birthdate=Birthdate,cid=Cid}
                    TriggerServerEvent('rsg-multicharacter:server:createCharacter', newData)
                    Wait(500)
                    FotoMugshots()
                    Wait(2000)
                    TriggerServerEvent('rsg-clothing:server:giveStarterClothes')
                else
                    lib.notify({title=locale('missing_character_info.title'),description=locale('missing_character_info.description'),type='error',duration=7000})
                end
            end
        end, function(data, menu) end)
end

function MainMenu()
    MenuData.CloseAll()
    local elements = {
        {label=RSG.Texts.Body,value='body',desc=""},
        {label=RSG.Texts.Face,value='face',desc=""},
        {label=RSG.Texts.Hair_beard,value='hair',desc=""},
        {label=RSG.Texts.Makeup,value='makeup',desc=""},
    }
    MenuData.Open('default', GetCurrentResourceName(), 'main_character_creator_menu',
        {title=RSG.Texts.Appearance,subtext=RSG.Texts.Options,align=RSG.Texts.align,elements=elements,itemHeight="4vh"}, function(data, menu)
        MainMenus[data.current.value]()
    end, function(data, menu) FirstMenu() end)
end

function OpenBodyMenu()
    MenuData.CloseAll()
    local elements = {
        {label=RSG.Texts.Face,value=CreatorCache["head"] or 1,category="head",desc="",type="slider",min=1,max=120,hop=6},
        {label=RSG.Texts.Width,value=CreatorCache["face_width"] or 0,category="face_width",desc="",type="slider",min=-100,max=100,hop=5},
        {label=RSG.Texts.SkinTone,value=CreatorCache["skin_tone"] or 1,category="skin_tone",desc="",type="slider",min=1,max=6},
        {label=RSG.Texts.Size,value=CreatorCache["body_size"] or 1,category="body_size",desc="",type="slider",min=1,max=#Data.Appearance.body_size},
        {label=RSG.Texts.Waist,value=CreatorCache["body_waist"] or 11,category="body_waist",desc="",type="slider",min=1,max=30},
        {label=RSG.Texts.Chest,value=CreatorCache["chest_size"] or 1,category="chest_size",desc="",type="slider",min=1,max=#Data.Appearance.chest_size},
        {label=RSG.Texts.Height,value=CreatorCache["height"] or 100,category="height",desc="",type="slider",min=80,max=130}
    }
    MenuData.Open('default', GetCurrentResourceName(), 'body_character_creator_menu',
        {title=RSG.Texts.Appearance,subtext=RSG.Texts.Options,align=RSG.Texts.align,elements=elements,itemHeight="4vh"}, function(data, menu)
    end, function(data, menu) MainMenu() end, function(data, menu)
        if CreatorCache[data.current.category] ~= data.current.value then
            CreatorCache[data.current.category] = data.current.value
            BodyFunctions[data.current.category](PlayerPedId(), CreatorCache)
        end
    end)
end

function OpenFaceMenu()
    MenuData.CloseAll()
    local elements = {
        {label=RSG.Texts.Eyes,value='eyes',desc=""},
        {label=RSG.Texts.Eyelids,value='eyelids',desc=""},
        {label=RSG.Texts.Eyebrows,value='eyebrows',desc=""},
        {label=RSG.Texts.Nose,value='nose',desc=""},
        {label=RSG.Texts.Mouth,value='mouth',desc=""},
        {label=RSG.Texts.Cheekbones,value='cheekbones',desc=""},
        {label=RSG.Texts.Jaw,value='jaw',desc=""},
        {label=RSG.Texts.Ears,value='ears',desc=""},
        {label=RSG.Texts.Chin,value='chin',desc=""},
        {label=RSG.Texts.Defects,value='defects',desc=""}
    }
    MenuData.Open('default', GetCurrentResourceName(), 'face_main_character_creator_menu',
        {title=RSG.Texts.Face,subtext=RSG.Texts.Options,align=RSG.Texts.align,elements=elements,itemHeight="4vh"}, function(data, menu)
        FaceFunctions[data.current.value]()
    end, function(data, menu) MainMenu() end)
end

function OpenHairMenu()
    MenuData.CloseAll()
    local elements = {}
    if IsPedMale(PlayerPedId()) then
        local a = 1
        if CreatorCache["hair"] == nil or type(CreatorCache["hair"]) ~= "table" then
            CreatorCache["hair"] = {model=0,texture=1}
        end
        if CreatorCache["beard"] == nil or type(CreatorCache["beard"]) ~= "table" then
            CreatorCache["beard"] = {model=0,texture=1}
        end
        local maleHairMax = 29
        elements[#elements+1] = {label=RSG.Texts.HairStyle,value=CreatorCache["hair"].model or 0,category="hair",desc="",type="slider",min=0,max=maleHairMax,change_type="model",id=a}
        a=a+1
        elements[#elements+1] = {label=RSG.Texts.HairColor,value=CreatorCache["hair"].texture or 1,category="hair",desc="",type="slider",min=1,max=GetMaxTexturesForModel("hair",CreatorCache["hair"].model or 1,false),change_type="texture",id=a}
        a=a+1
        elements[#elements+1] = {label=RSG.Texts.BeardStyle,value=CreatorCache["beard"].model or 0,category="beard",desc="",type="slider",min=0,max=#hairs_list["male"]["beard"],change_type="model",id=a}
        a=a+1
        elements[#elements+1] = {label="Стиль Бороды",value=CreatorCache["beard"].texture or 1,category="beard",desc="",type="slider",min=1,max=GetMaxTexturesForModel("beard",CreatorCache["beard"].model or 1,false),change_type="texture",id=a}
    else
        local a = 1
        if CreatorCache["hair"] == nil or type(CreatorCache["hair"]) ~= "table" then
            CreatorCache["hair"] = {model=0,texture=1}
        end
        elements[#elements+1] = {label=RSG.Texts.Hair,value=CreatorCache["hair"].model or 0,category="hair",desc="",type="slider",min=0,max=#hairs_list["female"]["hair"],change_type="model",id=a}
        a=a+1
        elements[#elements+1] = {label=RSG.Texts.HairColor,value=CreatorCache["hair"].texture or 1,category="hair",desc="",type="slider",min=1,max=GetMaxTexturesForModel("hair",CreatorCache["hair"].model or 1),change_type="texture",id=a}
    end
    MenuData.Open('default', GetCurrentResourceName(), 'hair_main_character_creator_menu',
        {title=RSG.Texts.Hair_beard,subtext=RSG.Texts.Options,align=RSG.Texts.align,elements=elements,itemHeight="4vh"}, function(data, menu)
    end, function(data, menu) MainMenu() end, function(data, menu)
        if data.current.change_type == "model" then
            local newValue = data.current.value
            if data.current.category == "hair" and IsPedMale(PlayerPedId()) then
                if newValue == 19 then
                    local oldValue = CreatorCache[data.current.category].model or 0
                    newValue = newValue > oldValue and 20 or 18
                    menu.setElement(data.current.id, "value", newValue)
                end
            end
            if CreatorCache[data.current.category].model ~= newValue then
                CreatorCache[data.current.category].texture = 1
                CreatorCache[data.current.category].model = newValue
                if newValue > 0 then
                    menu.setElement(data.current.id+1,"max",GetMaxTexturesForModel(data.current.category,newValue,false))
                    menu.setElement(data.current.id+1,"min",1)
                    menu.setElement(data.current.id+1,"value",1)
                    menu.refresh()
                else
                    menu.setElement(data.current.id+1,"max",0)
                    menu.setElement(data.current.id+1,"min",0)
                    menu.setElement(data.current.id+1,"value",0)
                    menu.refresh()
                end
                HairFunctions[data.current.category](PlayerPedId(), CreatorCache)
            end
        elseif data.current.change_type == "texture" then
            if CreatorCache[data.current.category].texture ~= data.current.value then
                CreatorCache[data.current.category].texture = data.current.value
                HairFunctions[data.current.category](PlayerPedId(), CreatorCache)
            end
        else
            if CreatorCache[data.current.category] ~= data.current.value then
                CreatorCache[data.current.category] = data.current.value
                HairFunctions[data.current.category](PlayerPedId(), CreatorCache)
            end
        end
    end)
end

function OpenEyesMenu()
    MenuData.CloseAll()
    local elements = {
        {label=RSG.Texts.Color,value=CreatorCache["eyes_color"] or 1,category="eyes_color",desc="",type="slider",min=1,max=18},
        {label=RSG.Texts.Depth,value=CreatorCache["eyes_depth"] or 0,category="eyes_depth",desc="",type="slider",min=-100,max=100,hop=5},
        {label=RSG.Texts.Angle,value=CreatorCache["eyes_angle"] or 0,category="eyes_angle",desc="",type="slider",min=-100,max=100,hop=5},
        {label=RSG.Texts.Distance,value=CreatorCache["eyes_distance"] or 0,category="eyes_distance",desc="",type="slider",min=-100,max=100,hop=5}
    }
    MenuData.Open('default', GetCurrentResourceName(), 'eyes_character_creator_menu',
    {title=RSG.Texts.Eyes,subtext=RSG.Texts.Options,align=RSG.Texts.align,elements=elements,itemHeight="4vh"}, function(data, menu)
    end, function(data, menu) OpenFaceMenu() end, function(data, menu)
        if CreatorCache[data.current.category] ~= data.current.value then
            CreatorCache[data.current.category] = data.current.value
            EyesFunctions[data.current.category](PlayerPedId(), CreatorCache)
        end
    end)
end

function OpenEyelidsMenu()
    MenuData.CloseAll()
    local elements = {
        {label=RSG.Texts.Height,value=CreatorCache["eyelid_height"] or 0,category="eyelid_height",desc="",type="slider",min=-100,max=100,hop=5},
        {label=RSG.Texts.Width,value=CreatorCache["eyelid_width"] or 0,category="eyelid_width",desc="",type="slider",min=-100,max=100,hop=5}
    }
    MenuData.Open('default', GetCurrentResourceName(), 'eyelid_character_creator_menu',
        {title=RSG.Texts.Eyelids,subtext=RSG.Texts.Options,align=RSG.Texts.align,elements=elements,itemHeight="4vh"}, function(data, menu)
    end, function(data, menu) OpenFaceMenu() end, function(data, menu)
        if CreatorCache[data.current.category] ~= data.current.value then
            CreatorCache[data.current.category] = data.current.value
            EyelidsFunctions[data.current.category](PlayerPedId(), CreatorCache)
        end
    end)
end

function OpenEyebrowsMenu()
    MenuData.CloseAll()
    local elements = {
        {label=RSG.Texts.Height,value=CreatorCache["eyebrow_height"] or 0,category="eyebrow_height",desc="",type="slider",min=-100,max=100,hop=5},
        {label=RSG.Texts.Width,value=CreatorCache["eyebrow_width"] or 0,category="eyebrow_width",desc="",type="slider",min=-100,max=100,hop=5},
        {label=RSG.Texts.Depth,value=CreatorCache["eyebrow_depth"] or 0,category="eyebrow_depth",desc="",type="slider",min=-100,max=100,hop=5},
        {label=RSG.Texts.Type,value=CreatorCache["eyebrows_t"] or 1,category="eyebrows_t",desc="",type="slider",min=1,max=15},
        {label=RSG.Texts.Visibility,value=CreatorCache["eyebrows_op"] or 100,category="eyebrows_op",desc="",type="slider",min=0,max=100,hop=5},
        {label=RSG.Texts.ColorPalette,value=CreatorCache["eyebrows_id"] or 10,category="eyebrows_id",desc="",type="slider",min=1,max=25},
        {label=RSG.Texts.ColorFirstrate,value=CreatorCache["eyebrows_c1"] or 0,category="eyebrows_c1",desc="",type="slider",min=0,max=64}
    }
    MenuData.Open('default', GetCurrentResourceName(), 'eyebrows_character_creator_menu',
        {title=RSG.Texts.Eyebrows,subtext=RSG.Texts.Options,align=RSG.Texts.align,elements=elements,itemHeight="4vh"}, function(data, menu)
    end, function(data, menu) OpenFaceMenu() end, function(data, menu)
        if CreatorCache[data.current.category] ~= data.current.value then
            CreatorCache[data.current.category] = data.current.value
            EyebrowsFunctions[data.current.category](PlayerPedId(), CreatorCache)
        end
    end)
end

function OpenNoseMenu()
    MenuData.CloseAll()
    local elements = {
        {label=RSG.Texts.Width,value=CreatorCache["nose_width"] or 0,category="nose_width",desc="",type="slider",min=-100,max=100,hop=5},
        {label=RSG.Texts.Size,value=CreatorCache["nose_size"] or 0,category="nose_size",desc="",type="slider",min=-100,max=100,hop=5},
        {label=RSG.Texts.Height,value=CreatorCache["nose_height"] or 0,category="nose_height",desc="",type="slider",min=-100,max=100,hop=5},
        {label=RSG.Texts.Angle,value=CreatorCache["nose_angle"] or 0,category="nose_angle",desc="",type="slider",min=-100,max=100,hop=5},
        {label=RSG.Texts.NoseCurvature,value=CreatorCache["nose_curvature"] or 0,category="nose_curvature",desc="",type="slider",min=-100,max=100,hop=5},
        {label=RSG.Texts.Distance,value=CreatorCache["nostrils_distance"] or 0,category="nostrils_distance",desc="",type="slider",min=-100,max=100,hop=5}
    }
    MenuData.Open('default', GetCurrentResourceName(), 'nose_character_creator_menu',
        {title=RSG.Texts.Nose,subtext=RSG.Texts.Options,align=RSG.Texts.align,elements=elements,itemHeight="4vh"}, function(data, menu)
    end, function(data, menu) OpenFaceMenu() end, function(data, menu)
        if CreatorCache[data.current.category] ~= data.current.value then
            CreatorCache[data.current.category] = data.current.value
            LoadFeatures(PlayerPedId(), CreatorCache)
        end
    end)
end

function OpenMouthMenu()
    MenuData.CloseAll()
    RequestAnimDict("FACE_HUMAN@GEN_MALE@BASE")
    while not HasAnimDictLoaded("FACE_HUMAN@GEN_MALE@BASE") do Wait(100) end
    TaskPlayAnim(PlayerPedId(), "FACE_HUMAN@GEN_MALE@BASE", "Face_Dentistry_Loop", 1090519040, -4, -1, 17, 0, 0, 0, 0, 0, 0)
    local elements = {
        {label=RSG.Texts.Teeth,value=CreatorCache["teeth"] or 1,category="teeth",desc="",type="slider",min=1,max=7},
        {label=RSG.Texts.Width,value=CreatorCache["mouth_width"] or 0,category="mouth_width",desc="",type="slider",min=-100,max=100,hop=5},
        {label=RSG.Texts.Depth,value=CreatorCache["mouth_depth"] or 0,category="mouth_depth",desc="",type="slider",min=-100,max=100,hop=5},
        {label=RSG.Texts.UP_DOWN,value=CreatorCache["mouth_x_pos"] or 0,category="mouth_x_pos",desc="",type="slider",min=-100,max=100,hop=5},
        {label=RSG.Texts.left_right,value=CreatorCache["mouth_y_pos"] or 0,category="mouth_y_pos",desc="",type="slider",min=-100,max=100,hop=5},
        {label=RSG.Texts.UpperLipHeight,value=CreatorCache["upper_lip_height"] or 0,category="upper_lip_height",desc="",type="slider",min=-100,max=100,hop=5},
        {label=RSG.Texts.UpperLipWidth,value=CreatorCache["upper_lip_width"] or 0,category="upper_lip_width",desc="",type="slider",min=-100,max=100,hop=5},
        {label=RSG.Texts.UpperLipDepth,value=CreatorCache["upper_lip_depth"] or 0,category="upper_lip_depth",desc="",type="slider",min=-100,max=100,hop=5},
        {label=RSG.Texts.LowerLipHeight,value=CreatorCache["lower_lip_height"] or 0,category="lower_lip_height",desc="",type="slider",min=-100,max=100,hop=5},
        {label=RSG.Texts.LowerLipWidth,value=CreatorCache["lower_lip_width"] or 0,category="lower_lip_width",desc="",type="slider",min=-100,max=100,hop=5},
        {label=RSG.Texts.LowerLipDepth,value=CreatorCache["lower_lip_depth"] or 0,category="lower_lip_depth",desc="",type="slider",min=-100,max=100,hop=5}
    }
    MenuData.Open('default', GetCurrentResourceName(), 'mouth_character_creator_menu',
        {title=RSG.Texts.Mouth,subtext=RSG.Texts.Options,align=RSG.Texts.align,elements=elements,itemHeight="4vh"}, function(data, menu)
    end, function(data, menu) ClearPedTasks(PlayerPedId()) OpenFaceMenu() end, function(data, menu)
        if CreatorCache[data.current.category] ~= data.current.value then
            CreatorCache[data.current.category] = data.current.value
            LoadFeatures(PlayerPedId(), CreatorCache)
        end
    end)
end

function OpenCheekbonesMenu()
    MenuData.CloseAll()
    local elements = {
        {label=RSG.Texts.Height,value=CreatorCache["cheekbones_height"] or 0,category="cheekbones_height",desc="",type="slider",min=-100,max=100,hop=5},
        {label=RSG.Texts.Width,value=CreatorCache["cheekbones_width"] or 0,category="cheekbones_width",desc="",type="slider",min=-100,max=100,hop=5},
        {label=RSG.Texts.Depth,value=CreatorCache["cheekbones_depth"] or 0,category="cheekbones_depth",desc="",type="slider",min=-100,max=100,hop=5}
    }
    MenuData.Open('default', GetCurrentResourceName(), 'cheekbones_character_creator_menu',
        {title='Cheek Bones',subtext=RSG.Texts.Options,align=RSG.Texts.align,elements=elements,itemHeight="4vh"}, function(data, menu)
    end, function(data, menu) OpenFaceMenu() end, function(data, menu)
        if CreatorCache[data.current.category] ~= data.current.value then
            CreatorCache[data.current.category] = data.current.value
            LoadFeatures(PlayerPedId(), CreatorCache)
        end
    end)
end

function OpenJawMenu()
    MenuData.CloseAll()
    local elements = {
        {label=RSG.Texts.Height,value=CreatorCache["jaw_height"] or 0,category="jaw_height",desc="",type="slider",min=-100,max=100,hop=5},
        {label=RSG.Texts.Width,value=CreatorCache["jaw_width"] or 0,category="jaw_width",desc="",type="slider",min=-100,max=100,hop=5},
        {label=RSG.Texts.Depth,value=CreatorCache["jaw_depth"] or 0,category="jaw_depth",desc="",type="slider",min=-100,max=100,hop=5}
    }
    MenuData.Open('default', GetCurrentResourceName(), 'jaw_character_creator_menu',
        {title=RSG.Texts.Jaw,subtext=RSG.Texts.Options,align=RSG.Texts.align,elements=elements}, function(data, menu)
    end, function(data, menu) OpenFaceMenu() end, function(data, menu)
        if CreatorCache[data.current.category] ~= data.current.value then
            CreatorCache[data.current.category] = data.current.value
            LoadFeatures(PlayerPedId(), CreatorCache)
        end
    end)
end

function OpenEarsMenu()
    MenuData.CloseAll()
    local elements = {
        {label=RSG.Texts.Width,value=CreatorCache["ears_width"] or 0,category="ears_width",desc="",type="slider",min=-100,max=100,hop=5},
        {label=RSG.Texts.Angle,value=CreatorCache["ears_angle"] or 0,category="ears_angle",desc="",type="slider",min=-100,max=100,hop=5},
        {label=RSG.Texts.Height,value=CreatorCache["ears_height"] or 0,category="ears_height",desc="",type="slider",min=-100,max=100,hop=5},
        {label=RSG.Texts.Size,value=CreatorCache["earlobe_size"] or 0,category="earlobe_size",desc="",type="slider",min=-100,max=100,hop=5}
    }
    MenuData.Open('default', GetCurrentResourceName(), 'ears_character_creator_menu',
        {title=RSG.Texts.Ears,subtext=RSG.Texts.Options,align=RSG.Texts.align,elements=elements,itemHeight="4vh"}, function(data, menu)
    end, function(data, menu) OpenFaceMenu() end, function(data, menu)
        if CreatorCache[data.current.category] ~= data.current.value then
            CreatorCache[data.current.category] = data.current.value
            LoadFeatures(PlayerPedId(), CreatorCache)
        end
    end)
end

function OpenChinMenu()
    MenuData.CloseAll()
    local elements = {
        {label=RSG.Texts.Size,value=CreatorCache["chin_height"] or 0,category="chin_height",desc="",type="slider",min=-100,max=100,hop=5},
        {label=RSG.Texts.Size,value=CreatorCache["chin_width"] or 0,category="chin_width",desc="",type="slider",min=-100,max=100,hop=5},
        {label=RSG.Texts.Size,value=CreatorCache["chin_depth"] or 0,category="chin_depth",desc="",type="slider",min=-100,max=100,hop=5}
    }
    MenuData.Open('default', GetCurrentResourceName(), 'chin_character_creator_menu',
        {title=RSG.Texts.Chin,subtext=RSG.Texts.Options,align=RSG.Texts.align,elements=elements,itemHeight="4vh"}, function(data, menu)
    end, function(data, menu) OpenFaceMenu() end, function(data, menu)
        if CreatorCache[data.current.category] ~= data.current.value then
            CreatorCache[data.current.category] = data.current.value
            LoadFeatures(PlayerPedId(), CreatorCache)
        end
    end)
end

function OpenDefectsMenu()
    MenuData.CloseAll()
    local elements = {
        {label=RSG.Texts.Scars,value=CreatorCache["scars_t"] or 1,category="scars_t",desc="",type="slider",min=1,max=16},
        {label=RSG.Texts.Clarity,value=CreatorCache["scars_op"] or 50,category="scars_op",desc="",type="slider",min=0,max=100,hop=5},
        {label=RSG.Texts.Older,value=CreatorCache["ageing_t"] or 1,category="ageing_t",desc="",type="slider",min=1,max=24},
        {label=RSG.Texts.Clarity,value=CreatorCache["ageing_op"] or 50,category="ageing_op",desc="",type="slider",min=0,max=100,hop=5},
        {label=RSG.Texts.Freckles,value=CreatorCache["freckles_t"] or 1,category="freckles_t",desc="",type="slider",min=1,max=15},
        {label=RSG.Texts.Clarity,value=CreatorCache["freckles_op"] or 50,category="freckles_op",desc="",type="slider",min=0,max=100,hop=5},
        {label=RSG.Texts.Moles,value=CreatorCache["moles_t"] or 1,category="moles_t",desc="",type="slider",min=1,max=16},
        {label=RSG.Texts.Clarity,value=CreatorCache["moles_op"] or 50,category="moles_op",desc="",type="slider",min=0,max=100,hop=5},
        {label=RSG.Texts.Spots,value=CreatorCache["spots_t"] or 1,category="spots_t",desc="",type="slider",min=1,max=16},
        {label=RSG.Texts.Clarity,value=CreatorCache["spots_op"] or 50,category="spots_op",desc="",type="slider",min=0,max=100,hop=5}
    }
    MenuData.Open('default', GetCurrentResourceName(), 'defects_character_creator_menu',
        {title=RSG.Texts.Disadvantages,subtext=RSG.Texts.Options,align=RSG.Texts.align,elements=elements,itemHeight="4vh"}, function(data, menu)
    end, function(data, menu) OpenFaceMenu() end, function(data, menu)
        if CreatorCache[data.current.category] ~= data.current.value then
            CreatorCache[data.current.category] = data.current.value
            LoadOverlays(PlayerPedId(), CreatorCache)
        end
    end)
end

function OpenMakeupMenu()
    MenuData.CloseAll()
    local elements = {
        {label=RSG.Texts.Shadow,value=CreatorCache["shadows_t"] or 1,category="shadows_t",desc="",type="slider",min=1,max=5},
        {label=RSG.Texts.Clarity,value=CreatorCache["shadows_op"] or 0,category="shadows_op",desc="",type="slider",min=0,max=100,hop=5},
        {label=RSG.Texts.ColorShadow,value=CreatorCache["shadows_id"] or 1,category="shadows_id",desc="",type="slider",min=1,max=25},
        {label=RSG.Texts.ColorFirst_Class,value=CreatorCache["shadows_c1"] or 0,category="shadows_c1",desc="",type="slider",min=0,max=64},
        {label=RSG.Texts.Blushing_Cheek,value=CreatorCache["blush_t"] or 1,category="blush_t",desc="",type="slider",min=1,max=4},
        {label=RSG.Texts.Clarity,value=CreatorCache["blush_op"] or 0,category="blush_op",desc="",type="slider",min=0,max=100,hop=5},
        {label=RSG.Texts.blush_id,value=CreatorCache["blush_id"] or 1,category="blush_id",desc="",type="slider",min=1,max=25},
        {label=RSG.Texts.blush_c1,value=CreatorCache["blush_c1"] or 0,category="blush_c1",desc="",type="slider",min=0,max=64},
        {label=RSG.Texts.Lipstick,value=CreatorCache["lipsticks_t"] or 1,category="lipsticks_t",desc="",type="slider",min=1,max=7},
        {label=RSG.Texts.Clarity,value=CreatorCache["lipsticks_op"] or 0,category="lipsticks_op",desc="",type="slider",min=0,max=100,hop=5},
        {label=RSG.Texts.ColorLipstick,value=CreatorCache["lipsticks_id"] or 1,category="lipsticks_id",desc="",type="slider",min=1,max=25},
        {label=RSG.Texts.lipsticks_c1,value=CreatorCache["lipsticks_c1"] or 0,category="lipsticks_c1",desc="",type="slider",min=0,max=64},
        {label=RSG.Texts.lipsticks_c2,value=CreatorCache["lipsticks_c2"] or 0,category="lipsticks_c2",desc="",type="slider",min=0,max=64},
        {label=RSG.Texts.Eyeliners,value=CreatorCache["eyeliners_t"] or 1,category="eyeliners_t",desc="",type="slider",min=1,max=15},
        {label=RSG.Texts.Clarity,value=CreatorCache["eyeliners_op"] or 0,category="eyeliners_op",desc="",type="slider",min=0,max=100,hop=5},
        {label=RSG.Texts.eyeliners_id,value=CreatorCache["eyeliners_id"] or 1,category="eyeliners_id",desc="",type="slider",min=1,max=25},
        {label=RSG.Texts.eyeliners_c1,value=CreatorCache["eyeliners_c1"] or 0,category="eyeliners_c1",desc="",type="slider",min=0,max=64}
    }
    MenuData.Open('default', GetCurrentResourceName(), 'makeup_character_creator_menu',
        {title=RSG.Texts.Make_up,subtext=RSG.Texts.Options,align=RSG.Texts.align,elements=elements,itemHeight="4vh"}, function(data, menu)
    end, function(data, menu) MainMenu() end, function(data, menu)
        if CreatorCache[data.current.category] ~= data.current.value then
            CreatorCache[data.current.category] = data.current.value
            LoadOverlays(PlayerPedId(), CreatorCache)
        end
    end)
end

-- ==========================================
-- ЭКСПОРТЫ
-- ==========================================

exports('GetComponentId', function(name) return LoadedComponents[name] end)

exports('GetBodyComponents', function() return {ComponentsMale, ComponentsFemale} end)

exports('GetBodyCurrentComponentHash', function(name)
    local hash
    if name == "hair" or name == "beard" then
        local info = LoadedComponents[name]
        if not info then return end
        local texture = info.texture
        local model = info.model
        if model == 0 or texture == 0 then return end
        if type(info) == "table" then
            if IsPedMale(PlayerPedId()) then
                if hairs_list["male"][name][model] and hairs_list["male"][name][model][texture] then
                    hash = hairs_list["male"][name][model][texture].hash
                end
            else
                if hairs_list["female"][name][model] and hairs_list["female"][name][model][texture] then
                    hash = hairs_list["female"][name][model][texture].hash
                end
            end
        end
    else
        local id = LoadedComponents[name]
        if not id then return end
        if IsPedMale(PlayerPedId()) then
            if ComponentsMale[name] then hash = ComponentsMale[name][id] end
        else
            if ComponentsFemale[name] then hash = ComponentsFemale[name][id] end
        end
    end
    return hash
end)

exports('SetFaceOverlays', function(target, data) LoadOverlays(target, data) end)
exports('SetHair', function(target, data) LoadHair(target, data) end)
exports('SetBeard', function(target, data) LoadBeard(target, data) end)

exports('GetComponentsMax', function(name)
    if name == "hair" or name == "beard" then
        if IsPedMale(PlayerPedId()) then
            if hairs_list["male"][name] then return #hairs_list["male"][name] end
        else
            if hairs_list["female"][name] then return #hairs_list["female"][name] end
        end
    else
        if IsPedMale(PlayerPedId()) then
            if ComponentsMale[name] then return #ComponentsMale[name] end
        else
            if ComponentsFemale[name] then return #ComponentsFemale[name] end
        end
    end
end)

exports('GetMaxTexturesForModel', function(category, model)
    return GetMaxTexturesForModel(category, model)
end)

exports('ApplySkin', ApplySkin)

exports('GetCurrentSkinTone', function()
    if CurrentSkinData and CurrentSkinData.skin_tone then return CurrentSkinData.skin_tone end
    if CreatorCache and CreatorCache.skin_tone then return CreatorCache.skin_tone end
    return 1
end)

exports('GetCurrentSkinData', function() return CurrentSkinData or {} end)

exports('SetCurrentSkinData', function(data)
    if data and type(data) == 'table' then CurrentSkinData = data end
end)