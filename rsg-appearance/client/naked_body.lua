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
    legsHiddenForSkirtBoots = false,  -- ★ true = меш ног (BODIES_LOWER) снят (жен.: штаны/юбка/платье + обувь)
    lastLowerTex = nil,   -- ★ Текстура при последнем применении (для переприменения при смене skin_tone)
    lastUpperTex = nil,
}

-- ★ После UpdatePedVariation нативы сбрасывают оружие; если игрок в седле — возвращаем поводья
local function RestoreReinsIfRiding(p)
    if p ~= PlayerPedId() or not IsPedOnMount(p) then return end
    local h = joaat('WEAPON_REINS')
    if h and h ~= 0 then
        GiveWeaponToPed(p, h, 0, false, true)
        SetCurrentPedWeapon(p, h, true)
    end
end

-- ★ СБРОС ФЛАГОВ (вызывается из creator.lua после SetPlayerModel)
function ResetNakedBodyFlags()
    NakedBodyState.lowerApplied = false
    NakedBodyState.upperApplied = false
    NakedBodyState.isApplying = false
    NakedBodyState.lastPedId = 0
    NakedBodyState.legsHiddenForSkirtBoots = false
    NakedBodyState.lastLowerTex = nil
    NakedBodyState.lastUpperTex = nil
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
    ['boots'] = 0x777EC6EF,    -- обувь (для женских: без naked lower — оверлей мешается с текстурой ноги и красит ботинки)
    ['neckwear'] = 0x7A96FACA,  -- платок/бандана (shiw-medic: защита от туберкулёза)
    ['neckties'] = 0x7A96FACA,  -- галстук (тот же слот)
    ['masks'] = 0x7505EF42,     -- маски (shiw-medic: защита от туберкулёза)
}

local SkinToneToTexture = {
    [1] = "008",
    [2] = "001",
    [3] = "002",
    [4] = "003",
    [5] = "004",
    [6] = "005",
}

--- JSON из БД часто даёт skin_tone строкой ("4"). Тогда SkinToneToTexture["4"] == nil и подставлялся
--- string.format("%03d",4) => "004", тогда как для тона 4 нужен суффикс "003" из таблицы — «белый низ» при тёмном верхе.
local function NormalizeSkinTone(raw)
    if raw == nil then return nil end
    local n = tonumber(raw)
    if not n then return nil end
    n = math.floor(n + 0.5)
    if n < 1 then n = 1 end
    if n > 6 then n = 6 end
    return n
end

function GetSkinTone()
    local t
    if CurrentSkinData and CurrentSkinData.skin_tone_override ~= nil then
        t = NormalizeSkinTone(CurrentSkinData.skin_tone_override)
        if t then return t end
    end
    if CurrentSkinData and CurrentSkinData.skin_tone ~= nil then
        t = NormalizeSkinTone(CurrentSkinData.skin_tone)
        if t then return t end
    end
    if CreatorCache and CreatorCache.skin_tone ~= nil then
        t = NormalizeSkinTone(CreatorCache.skin_tone)
        if t then return t end
    end
    if LoadedComponents and LoadedComponents.skin_tone ~= nil then
        t = NormalizeSkinTone(LoadedComponents.skin_tone)
        if t then return t end
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
    local t = NormalizeSkinTone(tone)
    if t then CurrentSkinData.skin_tone_override = t end
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

-- ★ FIX: Проверка верхней одежды по кэшу (рубашка/пальто/платье — то что ПОЛНОСТЬЮ закрывает торс)
-- ★ НЕ включаем vests/corsets — корсет на голом теле: naked overlay UPPERTORSO_FR1_055_CORSET001
--    остаётся под vest/corset и закрывает грудь; vest/corset рисуется поверх
local function HasUpperBodyInClothesCache(cacheOverride)
    local cache = (cacheOverride and type(cacheOverride) == 'table') and cacheOverride or _clothesCacheRef
    if not cache then return false end
    for _, cat in ipairs({'shirts_full', 'coats', 'coats_closed', 'dresses'}) do
        if cache[cat] and type(cache[cat]) == 'table'
            and cache[cat].hash and cache[cat].hash ~= 0 then
            return true
        end
    end
    return false
end

-- ★ Vest/corset без рубашки — overlay уже применён при equip. Отложенные CheckNakedBody НЕ должны переприменять (рисуется поверх vest)
local function HasVestOrCorsetOnlyInCache(cacheOverride)
    local cache = (cacheOverride and type(cacheOverride) == 'table') and cacheOverride or _clothesCacheRef
    if not cache then return false end
    local hasVest = cache['vests'] and cache['vests'].hash and cache['vests'].hash ~= 0
    local hasCorset = cache['corsets'] and cache['corsets'].hash and cache['corsets'].hash ~= 0
    if not (hasVest or hasCorset) then return false end
    if HasUpperBodyInClothesCache(cacheOverride) then return false end  -- есть рубашка/пальто/платье
    return true
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
    RestoreReinsIfRiding(ped)
    NakedBodyState.lowerApplied = true
    NakedBodyState.lastLowerTex = texNum
    NakedBodyState.lastPedId = ped
    NakedBodyState.isApplying = false
    
    print('[NakedBody] ApplyLower: completed (raw overlay) tex=' .. texNum)
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
    RestoreReinsIfRiding(ped)
    NakedBodyState.upperApplied = true
    NakedBodyState.lastUpperTex = texNum
    NakedBodyState.lastPedId = ped
    NakedBodyState.isApplying = false
    
    print('[NakedBody] ApplyUpper: completed (raw overlay) tex=' .. texNum)
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

-- ★ Хеш категории BODIES_LOWER (меш ног) — для полного скрытия ног при жен. нижней одежде + обувь
local BODIES_LOWER_CATEGORY = 0x823687F5

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
        RestoreReinsIfRiding(ped)
        print('[NakedBody] RemoveLower: overlay cleared' .. (skipMetaPedRemoval and ' (clothing on)' or ''))
    end
    NakedBodyState.lowerApplied = false
    NakedBodyState.lastLowerTex = nil
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
        RestoreReinsIfRiding(ped)
        print('[NakedBody] RemoveUpper: overlay cleared' .. (skipMetaPedRemoval and ' (clothing on)' or ''))
    end
    NakedBodyState.upperApplied = false
    NakedBodyState.lastUpperTex = nil
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
        NakedBodyState.legsHiddenForSkirtBoots = false
        NakedBodyState.lastLowerTex = nil
        NakedBodyState.lastUpperTex = nil
    end
    
    local isMale = IsMale(ped)
    
    print('[NakedBody] === CHECK ===')
    
    local hasLower = IsPedWearingAnyCategory(ped, {'pants', 'skirts', 'dresses'})
    -- ★ Доп. проверка: кэш одежды — юбка/штаны/платье скрывают naked body
    if not hasLower then
        hasLower = HasLowerBodyInClothesCache(clothesCache)
    end
    -- ★ Женские + обувь: не применять naked lower — оверлей (FEET/LOWERTORSO) мешается с моделью ноги и перекрашивает ботинки
    local hasBoots = IsPedWearingCategory(ped, 'boots')
    if not hasBoots and clothesCache and type(clothesCache['boots']) == 'table' and clothesCache['boots'].hash and clothesCache['boots'].hash ~= 0 then
        hasBoots = true
    end
    local hideNakedLower = hasLower or (not isMale and hasBoots)
    
    -- ★ Женские + штаны/юбка/платье + обувь: скрываем меш ног (BODIES_LOWER), чтобы ноги не просвечивали сквозь ботинки
    local hasSkirtOrDress = IsPedWearingAnyCategory(ped, {'skirts', 'dresses'})
    if not hasSkirtOrDress and clothesCache then
        hasSkirtOrDress = (type(clothesCache['skirts']) == 'table' and clothesCache['skirts'].hash and clothesCache['skirts'].hash ~= 0)
            or (type(clothesCache['dresses']) == 'table' and clothesCache['dresses'].hash and clothesCache['dresses'].hash ~= 0)
    end
    local hasPants = IsPedWearingCategory(ped, 'pants')
    if not hasPants and clothesCache then
        hasPants = type(clothesCache['pants']) == 'table' and clothesCache['pants'].hash and clothesCache['pants'].hash ~= 0
    end
    local shouldHideLegsMesh = (not isMale and hasBoots and (hasSkirtOrDress or hasPants))
    
    if shouldHideLegsMesh then
        -- Снимаем naked overlay и убираем меш ног (BODIES_LOWER) — остаётся одежда и обувь
        if NakedBodyState.lowerApplied then
            RemoveNakedLowerBody(ped, true)
        end
        Citizen.InvokeNative(0xD710A5007C2AC539, ped, BODIES_LOWER_CATEGORY, 0)
        Citizen.InvokeNative(0x704C908E9C405136, ped)
        Citizen.InvokeNative(0xCC8CA3E88256E58F, ped, false, true, true, true, false)
        NakedBodyState.legsHiddenForSkirtBoots = true
    else
        -- Восстанавливаем меш ног, если ранее скрывали
        if NakedBodyState.legsHiddenForSkirtBoots then
            NakedBodyState.legsHiddenForSkirtBoots = false
            local ok, err = pcall(function()
                exports['rsg-appearance']:RestoreBodiesLower(ped)
            end)
            if not ok then
                print('[NakedBody] RestoreBodiesLower error: ' .. tostring(err))
            end
        end
        
    if not hideNakedLower then
        -- ★ FIX: Переприменяем overlay если skin_tone изменился (раньше применяли с default=1 до прихода данных)
        local currentTex = GetTextureNumber()
        local needApply = not NakedBodyState.lowerApplied or (NakedBodyState.lastLowerTex and NakedBodyState.lastLowerTex ~= currentTex)
        if needApply then
            if NakedBodyState.lowerApplied then RemoveNakedLowerBody(ped, true) end
            ApplyNakedLowerBody(ped, true)
        end
    else
        -- ★ Штаны/юбка/платье надеты ИЛИ жен.+обувь — убираем naked overlay
        if NakedBodyState.lowerApplied then
            RemoveNakedLowerBody(ped, true)
        end
    end
    end
    
    if not isMale then
        -- ★ Рубашка/пальто/платье или только корсет/жилет — убираем naked overlay (грудь), чтобы не просвечивало сквозь корсет
        local hasUpper = IsPedWearingAnyCategory(ped, {'shirts_full', 'dresses', 'coats', 'coats_closed'})
        if not hasUpper then
            hasUpper = HasUpperBodyInClothesCache(clothesCache)
        end
        local hasVestOnly = HasVestOrCorsetOnlyInCache(clothesCache)
        print('[NakedBody] hasUpper=' .. tostring(hasUpper) .. ' hasVestOnly=' .. tostring(hasVestOnly))
        
        if hasUpper or hasVestOnly then
            -- Рубашка/пальто/платье или корсет/жилет — УБИРАЕМ naked overlay (иначе тело просвечивает сквозь корсет)
            if NakedBodyState.upperApplied then
                RemoveNakedUpperBody(ped, true)
            end
        else
            -- Голый торс без корсета — применяем overlay если ещё не применён или skin_tone изменился
            local currentTex = GetTextureNumber()
            local needApply = not NakedBodyState.upperApplied or (NakedBodyState.lastUpperTex and NakedBodyState.lastUpperTex ~= currentTex)
            if needApply then
                if NakedBodyState.upperApplied then RemoveNakedUpperBody(ped, true) end
                ApplyNakedUpperBody(ped, true)
            end
        end
    end
end

exports('CheckAndApplyNakedBodyIfNeeded', CheckAndApplyNakedBodyIfNeeded)

-- ★ Только логика ног (штаны/юбка/платье+обувь): скрыть или восстановить BODIES_LOWER. Без naked upper/vest — для loadcharacter при _PedStateFrozen
function ApplyLegsStateForSkirtBoots(ped, clothesCache)
    if not ped or not DoesEntityExist(ped) then ped = PlayerPedId() end
    local isMale = IsMale(ped)
    if isMale then return end
    local cache = clothesCache
    if not cache then pcall(function() cache = exports['rsg-appearance']:GetClothesCache() end) end
    local hasSkirtOrDress = IsPedWearingAnyCategory(ped, {'skirts', 'dresses'})
    if not hasSkirtOrDress and cache then
        hasSkirtOrDress = (type(cache['skirts']) == 'table' and cache['skirts'].hash and cache['skirts'].hash ~= 0)
            or (type(cache['dresses']) == 'table' and cache['dresses'].hash and cache['dresses'].hash ~= 0)
    end
    local hasPants = IsPedWearingCategory(ped, 'pants')
    if not hasPants and cache then
        hasPants = type(cache['pants']) == 'table' and cache['pants'].hash and cache['pants'].hash ~= 0
    end
    local hasBoots = IsPedWearingCategory(ped, 'boots')
    if not hasBoots and cache and type(cache['boots']) == 'table' and cache['boots'].hash and cache['boots'].hash ~= 0 then
        hasBoots = true
    end
    local shouldHideLegsMesh = hasBoots and (hasSkirtOrDress or hasPants)
    if shouldHideLegsMesh then
        if NakedBodyState.lowerApplied then RemoveNakedLowerBody(ped, true) end
        -- ★ Только снять компонент BODIES_LOWER — без 0x704C/0xCC8CA, они сбрасывают корсет и дают мерцание
        Citizen.InvokeNative(0xD710A5007C2AC539, ped, BODIES_LOWER_CATEGORY, 0)
        NakedBodyState.legsHiddenForSkirtBoots = true
    else
        if NakedBodyState.legsHiddenForSkirtBoots then
            NakedBodyState.legsHiddenForSkirtBoots = false
            pcall(function() exports['rsg-appearance']:RestoreBodiesLower(ped) end)
        end
    end
end
exports('ApplyLegsStateForSkirtBoots', ApplyLegsStateForSkirtBoots)

-- ★ Перезагрузка внешности (naked/ноги): после применения одежды или по запросу из других скриптов
function RefreshCharacterNakedState(ped)
    if not ped or not DoesEntityExist(ped) then ped = PlayerPedId() end
    local cache = nil
    pcall(function() cache = exports['rsg-appearance']:GetClothesCache() end)
    CheckAndApplyNakedBodyIfNeeded(ped, cache)
end
exports('RefreshCharacterNakedState', RefreshCharacterNakedState)

RegisterNetEvent('rsg-appearance:client:ApplyClothesComplete')
AddEventHandler('rsg-appearance:client:ApplyClothesComplete', function(targetPed, skinData)
    if NakedBodyState.skinLoading then return end
    if _G._PedStateFrozen then return end
    local ped = (targetPed and DoesEntityExist(targetPed)) and targetPed or PlayerPedId()
    if ped ~= PlayerPedId() then return end
    local cache = nil
    pcall(function() cache = exports['rsg-appearance']:GetClothesCache() end)
    CheckAndApplyNakedBodyIfNeeded(ped, cache)
end)

exports('IsNakedLowerApplied', function() return NakedBodyState.lowerApplied end)
exports('IsNakedUpperApplied', function() return NakedBodyState.upperApplied end)
exports('GetNakedBodyState', function() return NakedBodyState end)

RegisterNetEvent('rsg-appearance:client:SetSkinTone')
AddEventHandler('rsg-appearance:client:SetSkinTone', function(skinTone)
    local tone = NormalizeSkinTone(skinTone)
    if tone then
        if not CurrentSkinData then CurrentSkinData = {} end
        CurrentSkinData.skin_tone = tone
        LoadedComponents = LoadedComponents or {}
        LoadedComponents.skin_tone = tone
        -- ★ FIX: Переприменяем naked body с новым skin_tone (раньше мог быть применён с default)
        SetTimeout(300, function()
            local cache = nil
            pcall(function() cache = exports['rsg-appearance']:GetClothesCache() end)
            CheckAndApplyNakedBodyIfNeeded(PlayerPedId(), cache)
        end)
    end
end)

CreateThread(function()
    Wait(5000)
    TriggerServerEvent('rsg-appearance:server:RequestSkinTone')
    local timeout = 0
    while NakedBodyState.skinLoading and timeout < 30 do
        Wait(500)
        timeout = timeout + 1
    end
    Wait(2000)
    local cache = nil
    pcall(function() cache = exports['rsg-appearance']:GetClothesCache() end)
    CheckAndApplyNakedBodyIfNeeded(PlayerPedId(), cache)
end)

RegisterNetEvent('RSGCore:Client:OnPlayerLoaded')
AddEventHandler('RSGCore:Client:OnPlayerLoaded', function()
    Wait(3000)
    TriggerServerEvent('rsg-appearance:server:RequestSkinTone')
    local timeout = 0
    while NakedBodyState.skinLoading and timeout < 30 do
        Wait(500)
        timeout = timeout + 1
    end
    Wait(2000)
    local cache = nil
    pcall(function() cache = exports['rsg-appearance']:GetClothesCache() end)
    CheckAndApplyNakedBodyIfNeeded(PlayerPedId(), cache)
end)

RegisterNetEvent('rsg-appearance:client:ApplySkinComplete')
AddEventHandler('rsg-appearance:client:ApplySkinComplete', function()
    -- ★ НЕ ПРОВЕРЯЕМ если скин ещё грузится - creator.lua сам вызовет проверку
    if NakedBodyState.skinLoading then
        print('[NakedBody] ApplySkinComplete: Skipped (skinLoading=true)')
        return
    end
    -- ★ Пропускаем при _PedStateFrozen (loadcharacter) — переприменение рисовало naked overlay поверх vest
    if _G._PedStateFrozen then
        print('[NakedBody] ApplySkinComplete: Skipped (_PedStateFrozen)')
        return
    end
    Wait(1500)
    -- ★ FIX: Передаём ClothesCache — иначе при корсете+юбке натив может вернуть false и применится naked body
    local cache = nil
    pcall(function() cache = exports['rsg-appearance']:GetClothesCache() end)
    CheckAndApplyNakedBodyIfNeeded(PlayerPedId(), cache)
end)

RegisterNetEvent('rsg-appearance:client:CheckNakedBody')
AddEventHandler('rsg-appearance:client:CheckNakedBody', function()
    Wait(300)
    local cache = nil
    pcall(function() cache = exports['rsg-appearance']:GetClothesCache() end)
    CheckAndApplyNakedBodyIfNeeded(PlayerPedId(), cache)
end)

RegisterNetEvent('rsg-appearance:client:ApplyClothes')
AddEventHandler('rsg-appearance:client:ApplyClothes', function(clothesData, ped, skinData)
    if skinData and skinData.skin_tone ~= nil then
        local t = NormalizeSkinTone(skinData.skin_tone)
        if t then
            CurrentSkinData = CurrentSkinData or {}
            CurrentSkinData.skin_tone = t
        end
    end
    -- ★ НЕ ПРОВЕРЯЕМ если скин ещё грузится - creator.lua сам вызовет проверку
    if NakedBodyState.skinLoading then
        print('[NakedBody] ApplyClothes: Skipped check (skinLoading=true)')
        return
    end
    SetTimeout(2000, function()
        local cache = nil
        pcall(function() cache = exports['rsg-appearance']:GetClothesCache() end)
        CheckAndApplyNakedBodyIfNeeded(PlayerPedId(), cache)
    end)
end)

-- ★ RegisterNetEvent здесь И в creator.lua — это нормально, RegisterNetEvent идемпотентен
RegisterNetEvent('rsg-appearance:client:ApplySkin')
AddEventHandler('rsg-appearance:client:ApplySkin', function(skinData, clothesData)
    if skinData and skinData.skin_tone ~= nil then
        local t = NormalizeSkinTone(skinData.skin_tone)
        if t then
            CurrentSkinData = CurrentSkinData or {}
            CurrentSkinData.skin_tone = t
        end
    end
    -- ★ Устанавливаем флаг загрузки (creator.lua снимет его когда закончит)
    NakedBodyState.skinLoading = true
    -- Сбрасываем флаги т.к. SetPlayerModel создаст нового педа
    NakedBodyState.lowerApplied = false
    NakedBodyState.upperApplied = false
    NakedBodyState.lastPedId = 0
    NakedBodyState.lastLowerTex = nil
    NakedBodyState.lastUpperTex = nil
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