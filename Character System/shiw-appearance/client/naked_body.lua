-- ==========================================
-- NAKED BODY SYSTEM v3.5 - MetaPed Fix
-- ==========================================

CurrentSkinData = CurrentSkinData or {}

local IsNaked = false
local SavedClothesBeforeNaked = {}

-- ★ ГЛОБАЛЬНАЯ переменная (доступна из clothes.lua!)
NakedBodyState = {
    lowerApplied = false,
    upperApplied = false,
    lastApplyTime = 0,
    isApplying = false,
    skinLoading = false,  -- ★ ФЛАГ: блокировка проверок пока ApplySkin работает
    lastPedId = 0,        -- ★ ID педа когда применяли naked body
}

-- ★ СБРОС ФЛАГОВ (вызывается из creator.lua после SetPlayerModel)
function ResetNakedBodyFlags()
    NakedBodyState.lowerApplied = false
    NakedBodyState.upperApplied = false
    NakedBodyState.isApplying = false
    NakedBodyState.lastPedId = 0
    print('[NakedBody] Flags RESET (model changed)')
end

exports('ResetNakedBodyFlags', ResetNakedBodyFlags)

local TestTextureOverride = nil

local CategoryMetaHash = {
    ['shirts_full'] = 0x2026C46D,
    ['vests'] = 0x485EE834,
    ['coats'] = 0xE06D30CE,
    ['coats_closed'] = 0x662AC34,
    ['pants'] = 0x1D4C528A,
    ['skirts'] = 0xA0E3AB7F,
    ['dresses'] = 0x0662AC34,
    ['corsets'] = 0x485EE834,  -- ★ FIX: корсет = тот же MetaPed слот что и vests
}

local SkinToneToTexture = {
    [1] = "008",
    [2] = "001",
    [3] = "002",
    [4] = "003",
    [5] = "004",
    [6] = "005",
}

function GetSkinTone()
    if CurrentSkinData and CurrentSkinData.skin_tone_override then
        return CurrentSkinData.skin_tone_override
    end
    if CurrentSkinData and CurrentSkinData.skin_tone then
        return CurrentSkinData.skin_tone
    end
    if CreatorCache and CreatorCache.skin_tone then
        return CreatorCache.skin_tone
    end
    if LoadedComponents and LoadedComponents.skin_tone then
        return LoadedComponents.skin_tone
    end
    return 1
end

function GetTextureNumber()
    if TestTextureOverride then
        return TestTextureOverride
    end
    local skinTone = GetSkinTone()
    return SkinToneToTexture[skinTone] or string.format("%03d", skinTone)
end

function SetSkinToneOverride(tone)
    if not CurrentSkinData then CurrentSkinData = {} end
    CurrentSkinData.skin_tone_override = tone
end

local function IsMale(ped)
    local result = IsPedMale(ped)
    return result == true or result == 1
end

exports('GetSkinTone', GetSkinTone)
exports('GetTextureNumber', GetTextureNumber)
exports('SetSkinToneOverride', SetSkinToneOverride)

local function IsPedWearingCategory(ped, category)
    if not ped or not DoesEntityExist(ped) then return false end
    local metaHash = CategoryMetaHash[category]
    if not metaHash then return false end
    local currentHash = Citizen.InvokeNative(0xFB4891BD7578CDC1, ped, metaHash)
    return currentHash and currentHash ~= 0
end

local function IsPedWearingAnyCategory(ped, categories)
    for _, cat in ipairs(categories) do
        if IsPedWearingCategory(ped, cat) then
            return true, cat
        end
    end
    return false, nil
end

exports('IsPedWearingCategory', IsPedWearingCategory)
exports('IsPedWearingAnyCategory', IsPedWearingAnyCategory)

-- ★ Кэш одежды из clothes.lua (для дополнительной проверки юбки)
local _clothesCacheRef = nil

RegisterNetEvent('rsg-clothing:client:clothingLoaded')
AddEventHandler('rsg-clothing:client:clothingLoaded', function(clothesCache)
    _clothesCacheRef = clothesCache
end)

-- Проверка нижней одежды по кэшу (юбка/штаны/платье)
-- cacheOverride: если передан — используем его вместо _clothesCacheRef
local function HasLowerBodyInClothesCache(cacheOverride)
    local cache = (cacheOverride and type(cacheOverride) == 'table') and cacheOverride or _clothesCacheRef
    if not cache then return false end
    for _, cat in ipairs({'pants', 'skirts', 'dresses'}) do
        if cache[cat] and type(cache[cat]) == 'table'
            and cache[cat].hash and cache[cat].hash ~= 0 then
            return true
        end
    end
    return false
end

-- ★ FIX: Проверка верхней одежды по кэшу (рубашка/жилетка/корсет/пальто/платье)
local function HasUpperBodyInClothesCache(cacheOverride)
    local cache = (cacheOverride and type(cacheOverride) == 'table') and cacheOverride or _clothesCacheRef
    if not cache then return false end
    for _, cat in ipairs({'shirts_full', 'vests', 'corsets', 'coats', 'coats_closed', 'dresses'}) do
        if cache[cat] and type(cache[cat]) == 'table'
            and cache[cat].hash and cache[cat].hash ~= 0 then
            return true
        end
    end
    return false
end

function ApplyNakedLowerBody(ped, force)
    if not ped or not DoesEntityExist(ped) then
        ped = PlayerPedId()
    end
    
    local now = GetGameTimer()
    if not force and NakedBodyState.isApplying and (now - NakedBodyState.lastApplyTime) < 500 then
        return false
    end
    
    NakedBodyState.isApplying = true
    NakedBodyState.lastApplyTime = now
    
    local isMale = IsMale(ped)
    local texNum = GetTextureNumber()
    
    print('[NakedBody] ApplyLower: male=' .. tostring(isMale) .. ' tex=' .. texNum)
    
    if isMale then
        local draw = GetHashKey("LOWERTORSO_MR1_000")
        local alb = GetHashKey("FEET_MR1_000_C0_" .. texNum .. "_AB")
        local norm = GetHashKey("FEET_MR1_000_C0_000_NM")
        local mati = GetHashKey("FEET_MR1_000_C0_000_M")
        
        local texture = Citizen.InvokeNative(0xC5E7204F322E49EB, alb, norm)
        if texture then Citizen.InvokeNative(0x92DAABA2C1C10B0E, texture) end
        Wait(100)
        Citizen.InvokeNative(0xBC6DF00D7A4A6819, ped, draw, alb, norm, mati, 0, 0, 0, 0)
    else
        local draw = GetHashKey("LOWERTORSO_FR1_003")
        local alb = GetHashKey("FEET_FR1_000_C0_" .. texNum .. "_AB")
        local norm = GetHashKey("FEET_FR1_000_C0_000_NM")
        local mati = GetHashKey("FEET_FR1_000_C0_000_M")
        
        local texture = Citizen.InvokeNative(0xC5E7204F322E49EB, alb, norm)
        if texture then Citizen.InvokeNative(0x92DAABA2C1C10B0E, texture) end
        Wait(100)
        Citizen.InvokeNative(0xBC6DF00D7A4A6819, ped, draw, alb, norm, mati, 0, 0, 0, 0)
    end
    
    Wait(50)
    Citizen.InvokeNative(0x704C908E9C405136, ped)
    Citizen.InvokeNative(0xCC8CA3E88256E58F, ped, false, true, true, true, false)
    if ReapplyBodyMorph then ReapplyBodyMorph(ped) end
    
    NakedBodyState.lowerApplied = true
    NakedBodyState.lastPedId = ped
    NakedBodyState.isApplying = false
    
    print('[NakedBody] ApplyLower: completed (raw overlay)')
    return true
end

function ApplyNakedUpperBody(ped, force)
    if not ped or not DoesEntityExist(ped) then
        ped = PlayerPedId()
    end
    
    if IsMale(ped) then
        return false
    end
    
    local now = GetGameTimer()
    if not force and NakedBodyState.isApplying and (now - NakedBodyState.lastApplyTime) < 500 then
        return false
    end
    
    NakedBodyState.isApplying = true
    NakedBodyState.lastApplyTime = now
    
    local texNum = GetTextureNumber()
    
    print('[NakedBody] ApplyUpper: tex=' .. texNum)
    
    local draw = GetHashKey("UPPERTORSO_FR1_055_CORSET001")
    local alb = GetHashKey("HAND_FR1_000_C0_" .. texNum .. "_AB")
    local norm = GetHashKey("HAND_FR1_000_C0_000_NM")
    local mati = GetHashKey("HAND_FR1_000_C0_000_M")
    
    local texture = Citizen.InvokeNative(0xC5E7204F322E49EB, alb, norm)
    if texture then Citizen.InvokeNative(0x92DAABA2C1C10B0E, texture) end
    Wait(100)
    Citizen.InvokeNative(0xBC6DF00D7A4A6819, ped, draw, alb, norm, mati, 0, 0, 0, 0)
    
    Wait(50)
    Citizen.InvokeNative(0x704C908E9C405136, ped)
    Citizen.InvokeNative(0xCC8CA3E88256E58F, ped, false, true, true, true, false)
    if ReapplyBodyMorph then ReapplyBodyMorph(ped) end
    
    NakedBodyState.upperApplied = true
    NakedBodyState.lastPedId = ped
    NakedBodyState.isApplying = false
    
    print('[NakedBody] ApplyUpper: completed (raw overlay)')
    return true
end

exports('ApplyNakedLowerBody', ApplyNakedLowerBody)
exports('ApplyNakedUpperBody', ApplyNakedUpperBody)

-- ★ v3.5: Naked body использует raw overlay (0xBC6DF00D7A4A6819).
-- Для удаления: перезаписываем оверлей нулями + удаляем MetaPed компонент.
-- При снятии одежды — naked body переприменяется через raw overlay.

-- ★ Хеши naked body (для перезаписи при удалении)
local NakedUpperDraw = GetHashKey("UPPERTORSO_FR1_055_CORSET001")
local NakedLowerDrawMale = GetHashKey("LOWERTORSO_MR1_000")
local NakedLowerDrawFemale = GetHashKey("LOWERTORSO_FR1_003")

-- skipMetaPedRemoval = true когда снимаем при надевании одежды — только overlay clear, слоты чистит clothes.lua
function RemoveNakedLowerBody(ped, skipMetaPedRemoval)
    if not ped or not DoesEntityExist(ped) then ped = PlayerPedId() end
    if NakedBodyState.lowerApplied then
        local draw = IsMale(ped) and NakedLowerDrawMale or NakedLowerDrawFemale
        Citizen.InvokeNative(0xBC6DF00D7A4A6819, ped, draw, 0, 0, 0, 0, 0, 0, 0)
        if not skipMetaPedRemoval then
            Citizen.InvokeNative(0xD710A5007C2AC539, ped, 0x1D4C528A, 0)
            Citizen.InvokeNative(0xD710A5007C2AC539, ped, 0xA0E3AB7F, 0)
        end
        Citizen.InvokeNative(0x704C908E9C405136, ped)
        Citizen.InvokeNative(0xCC8CA3E88256E58F, ped, false, true, true, true, false)
        print('[NakedBody] RemoveLower: overlay cleared' .. (skipMetaPedRemoval and ' (clothing on)' or ''))
    end
    NakedBodyState.lowerApplied = false
end

function RemoveNakedUpperBody(ped, skipMetaPedRemoval)
    if not ped or not DoesEntityExist(ped) then ped = PlayerPedId() end
    if NakedBodyState.upperApplied then
        Citizen.InvokeNative(0xBC6DF00D7A4A6819, ped, NakedUpperDraw, 0, 0, 0, 0, 0, 0, 0)
        if not skipMetaPedRemoval then
            Citizen.InvokeNative(0xD710A5007C2AC539, ped, 0x2026C46D, 0)
        end
        Citizen.InvokeNative(0x704C908E9C405136, ped)
        Citizen.InvokeNative(0xCC8CA3E88256E58F, ped, false, true, true, true, false)
        print('[NakedBody] RemoveUpper: overlay cleared' .. (skipMetaPedRemoval and ' (clothing on)' or ''))
    end
    NakedBodyState.upperApplied = false
end

exports('RemoveNakedLowerBody', RemoveNakedLowerBody)
exports('RemoveNakedUpperBody', RemoveNakedUpperBody)

function CheckAndApplyNakedBodyIfNeeded(ped, clothesCache)
    if not ped or not DoesEntityExist(ped) then
        ped = PlayerPedId()
    end
    
    -- ★ БЛОКИРОВКА: Не проверяем пока ApplySkin работает
    if NakedBodyState.skinLoading then
        print('[NakedBody] === CHECK SKIPPED (skinLoading=true) ===')
        return
    end
    
    -- ★ АВТО-СБРОС: Если пед сменился (после SetPlayerModel), сбрасываем флаги
    if NakedBodyState.lastPedId ~= 0 and NakedBodyState.lastPedId ~= ped then
        print('[NakedBody] Ped changed (' .. tostring(NakedBodyState.lastPedId) .. ' -> ' .. tostring(ped) .. '), resetting flags')
        NakedBodyState.lowerApplied = false
        NakedBodyState.upperApplied = false
        NakedBodyState.lastPedId = 0
    end
    
    local isMale = IsMale(ped)
    
    print('[NakedBody] === CHECK ===')
    
    local hasLower = IsPedWearingAnyCategory(ped, {'pants', 'skirts', 'dresses'})
    -- ★ Доп. проверка: кэш одежды (с учётом переданного ClothesCache если есть)
    if not hasLower then
        hasLower = HasLowerBodyInClothesCache(clothesCache)
    end
    print('[NakedBody] hasLower=' .. tostring(hasLower))
    
    if not hasLower then
        if not NakedBodyState.lowerApplied then
            ApplyNakedLowerBody(ped, true)
        end
    else
        -- ★ Штаны надеты — УБИРАЕМ naked overlay (skipMetaPed=true чтобы не снять одежду)
        if NakedBodyState.lowerApplied then
            RemoveNakedLowerBody(ped, true)
        end
    end
    
    if not isMale then
        local hasUpper = IsPedWearingAnyCategory(ped, {'shirts_full', 'dresses', 'coats', 'coats_closed', 'vests', 'corsets'})
        -- ★ FIX: Доп. проверка по кэшу (с учётом переданного ClothesCache — актуально при экипировке)
        if not hasUpper then
            hasUpper = HasUpperBodyInClothesCache(clothesCache)
        end
        print('[NakedBody] hasUpper=' .. tostring(hasUpper))
        
        if not hasUpper then
            if not NakedBodyState.upperApplied then
                ApplyNakedUpperBody(ped, true)
            end
        else
            -- ★ Рубашка/корсет надеты — УБИРАЕМ naked overlay (skipMetaPed=true)
            if NakedBodyState.upperApplied then
                RemoveNakedUpperBody(ped, true)
            end
        end
    end
end

exports('CheckAndApplyNakedBodyIfNeeded', CheckAndApplyNakedBodyIfNeeded)

exports('IsNakedLowerApplied', function() return NakedBodyState.lowerApplied end)
exports('IsNakedUpperApplied', function() return NakedBodyState.upperApplied end)
exports('GetNakedBodyState', function() return NakedBodyState end)

RegisterNetEvent('rsg-appearance:client:SetSkinTone')
AddEventHandler('rsg-appearance:client:SetSkinTone', function(skinTone)
    if skinTone then
        if not CurrentSkinData then CurrentSkinData = {} end
        CurrentSkinData.skin_tone = skinTone
        LoadedComponents = LoadedComponents or {}
        LoadedComponents.skin_tone = skinTone
    end
end)

CreateThread(function()
    Wait(5000)
    TriggerServerEvent('rsg-appearance:server:RequestSkinTone')
    -- Ждём пока ApplySkin закончит работу
    local timeout = 0
    while NakedBodyState.skinLoading and timeout < 30 do
        Wait(500)
        timeout = timeout + 1
    end
    Wait(2000)
    print('[NakedBody] Startup thread: Final naked body check')
    CheckAndApplyNakedBodyIfNeeded(PlayerPedId())
end)

RegisterNetEvent('RSGCore:Client:OnPlayerLoaded')
AddEventHandler('RSGCore:Client:OnPlayerLoaded', function()
    Wait(3000)
    TriggerServerEvent('rsg-appearance:server:RequestSkinTone')
    -- Ждём пока ApplySkin закончит работу
    local timeout = 0
    while NakedBodyState.skinLoading and timeout < 30 do
        Wait(500)
        timeout = timeout + 1
    end
    Wait(2000)
    print('[NakedBody] OnPlayerLoaded: Final naked body check')
    CheckAndApplyNakedBodyIfNeeded(PlayerPedId())
end)

RegisterNetEvent('rsg-appearance:client:ApplySkinComplete')
AddEventHandler('rsg-appearance:client:ApplySkinComplete', function()
    -- ★ НЕ ПРОВЕРЯЕМ если скин ещё грузится - creator.lua сам вызовет проверку
    if NakedBodyState.skinLoading then
        print('[NakedBody] ApplySkinComplete: Skipped (skinLoading=true)')
        return
    end
    Wait(1500)
    CheckAndApplyNakedBodyIfNeeded(PlayerPedId())
end)

RegisterNetEvent('rsg-appearance:client:CheckNakedBody')
AddEventHandler('rsg-appearance:client:CheckNakedBody', function()
    Wait(300)
    CheckAndApplyNakedBodyIfNeeded(PlayerPedId())
end)

RegisterNetEvent('rsg-appearance:client:ApplyClothes')
AddEventHandler('rsg-appearance:client:ApplyClothes', function(clothesData, ped, skinData)
    if skinData and skinData.skin_tone then
        CurrentSkinData.skin_tone = skinData.skin_tone
    end
    -- ★ НЕ ПРОВЕРЯЕМ если скин ещё грузится - creator.lua сам вызовет проверку
    if NakedBodyState.skinLoading then
        print('[NakedBody] ApplyClothes: Skipped check (skinLoading=true)')
        return
    end
    SetTimeout(2000, function()
        CheckAndApplyNakedBodyIfNeeded(PlayerPedId())
    end)
end)

-- ★ RegisterNetEvent здесь И в creator.lua — это нормально, RegisterNetEvent идемпотентен
RegisterNetEvent('rsg-appearance:client:ApplySkin')
AddEventHandler('rsg-appearance:client:ApplySkin', function(skinData, clothesData)
    if skinData and skinData.skin_tone then
        CurrentSkinData.skin_tone = skinData.skin_tone
    end
    -- ★ Устанавливаем флаг загрузки (creator.lua снимет его когда закончит)
    NakedBodyState.skinLoading = true
    -- Сбрасываем флаги т.к. SetPlayerModel создаст нового педа
    NakedBodyState.lowerApplied = false
    NakedBodyState.upperApplied = false
    NakedBodyState.lastPedId = 0
    print('[NakedBody] ApplySkin received: skinLoading=true, flags RESET')
end)

RegisterCommand('testnaked', function()
    local ped = PlayerPedId()
    print('=== NAKED TEST ===')
    print('SkinTone: ' .. GetSkinTone())
    print('IsMale: ' .. tostring(IsMale(ped)))
    print('lowerApplied: ' .. tostring(NakedBodyState.lowerApplied))
    print('upperApplied: ' .. tostring(NakedBodyState.upperApplied))
    print('--- Native check ---')
    for _, cat in ipairs({'pants', 'skirts', 'dresses', 'shirts_full', 'coats', 'vests'}) do
        print('  ' .. cat .. ': ' .. tostring(IsPedWearingCategory(ped, cat)))
    end
end, false)

RegisterCommand('checknaked', function()
    NakedBodyState.lowerApplied = false
    NakedBodyState.upperApplied = false
    CheckAndApplyNakedBodyIfNeeded(PlayerPedId())
end, false)

RegisterCommand('forcenaked', function()
    local ped = PlayerPedId()
    NakedBodyState.lowerApplied = false
    NakedBodyState.upperApplied = false
    ApplyNakedLowerBody(ped, true)
    Wait(300)
    if not IsMale(ped) then
        ApplyNakedUpperBody(ped, true)
    end
end, false)

RegisterCommand('resetnaked', function()
    NakedBodyState.lowerApplied = false
    NakedBodyState.upperApplied = false
    print('[NakedBody] Flags reset')
end, false)

RegisterCommand('fixskintone', function(src, args)
    local tone = tonumber(args[1])
    if tone and tone >= 1 and tone <= 6 then
        SetSkinToneOverride(tone)
        TriggerServerEvent('rsg-appearance:server:FixSkinTone', tone)
    else
        print('Usage: /fixskintone [1-6]')
    end
end, false)

print('[NakedBody] v3.5 loaded (raw overlay + active removal)')