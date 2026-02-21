-- ==========================================
-- RSG-APPEARANCE LOAD FUNCTIONS
-- ★ ВЕРСИЯ 3: BODY MORPH БЕЗ РЕКУРСИИ
-- Используем глобальную таблицу _G._BodyMorphData
-- для хранения ХЕШЕЙ (не индексов) body morph
-- ==========================================

local Data = require 'data.features'
local Overlays = require 'data.overlays'

-- ★ ГЛОБАЛЬНОЕ ХРАНИЛИЩЕ body morph (значения 0-100 для SetPedFaceFeature + хеши для совместимости)
_G._BodyMorphData = _G._BodyMorphData or {
    active = false,
    size_hash = nil,
    waist_hash = nil,
    chest_hash = nil,
    -- Значения для морфа через Face Feature (0-100), реально работают в RDR2
    waist_value = nil,   -- 0-100 (талия / пузо)
    chest_value = nil,   -- 0-100 (грудь)
    size_value = nil,    -- 0-100 (телосложение, бёдра/руки)
}

-- ==========================================
-- НАТИВЫ
-- ==========================================

local function SetPedFaceFeature(ped, feature, value)
    Citizen.InvokeNative(0x5653AB26C82938CF, ped, feature, value / 100.0)
end

-- ★ НЕ вызывает UpdatePedVariation
local function SetPedBodyComponent(ped, hash)
    Citizen.InvokeNative(0x1902C4CFCC5BE57C, ped, hash)
end

local function SetPedComponent(ped, hash)
    Citizen.InvokeNative(0x59BD177A1A48600A, ped, hash)
    Citizen.InvokeNative(0xD3A7B003ED343FD9, ped, hash, true, true, true)
end

-- ==========================================
-- ЗАГРУЗКА ГОЛОВЫ
-- ==========================================

function LoadHead(ped, data)
    if not ped or not DoesEntityExist(ped) then
        ped = CreatorPed
        if not ped or not DoesEntityExist(ped) then
            print('[RSG-Appearance] LoadHead: No valid ped')
            return
        end
    end

    local isMale = IsPedMale(ped)
    local headIndex = data.head or 1
    local skinTone = data.skin_tone or 1
    local gender = isMale and 'male' or 'female'

    print('[RSG-Appearance] LoadHead: head=' .. tostring(headIndex) .. ' skinTone=' .. tostring(skinTone))

    local clotheslist = require 'data.clothes_list'

    local heads = {}
    for _, item in ipairs(clotheslist) do
        if item.category_hashname == 'heads' and item.ped_type == gender and item.is_multiplayer then
            if item.hashname and item.hashname ~= "" then
                table.insert(heads, {hash = item.hash, hashname = item.hashname})
            end
        end
    end

    print('[RSG-Appearance] LoadHead: Found ' .. #heads .. ' heads')

    if #heads > 0 then
        local tonesPerModel = 6
        local idx = ((headIndex - 1) * tonesPerModel) + skinTone
        if idx < 1 then idx = 1 end
        if idx > #heads then
            idx = math.min(headIndex, #heads)
        end

        local headData = heads[idx]
        if headData and headData.hash then
            print('[RSG-Appearance] LoadHead: Applying hash ' .. tostring(headData.hash) .. ' (idx=' .. idx .. ')')
            Citizen.InvokeNative(0x59BD177A1A48600A, ped, headData.hash) -- ★ FIX: Request перед Apply
            Citizen.InvokeNative(0xD3A7B003ED343FD9, ped, headData.hash, true, true, true)

            -- ★ FIX: Увеличен таймаут с 300мс до 2с для высокого пинга
            local timeout = 0
            while not Citizen.InvokeNative(0xA0BC8FAED8CFEB3C, ped) and timeout < 100 do
                Wait(20)
                timeout = timeout + 1
            end
            
            -- ★ FIX: Повторная попытка при таймауте
            if timeout >= 100 then
                print('[RSG-Appearance] LoadHead: Streaming timeout, retrying...')
                Citizen.InvokeNative(0x59BD177A1A48600A, ped, headData.hash)
                Citizen.InvokeNative(0xD3A7B003ED343FD9, ped, headData.hash, true, true, true)
                local timeout2 = 0
                while not Citizen.InvokeNative(0xA0BC8FAED8CFEB3C, ped) and timeout2 < 100 do
                    Wait(20)
                    timeout2 = timeout2 + 1
                end
            end

            Citizen.InvokeNative(0x704C908E9C405136, ped)
            if NativeUpdatePedVariation then NativeUpdatePedVariation(ped) else Citizen.InvokeNative(0xCC8CA3E88256E58F, ped, false, true, true, true, false) end
            -- ★ Восстанавливаем body morph после UpdatePedVariation
            if _G._BodyMorphData and _G._BodyMorphData.active then
                ReapplyBodyMorph(ped)
            end
        end
    end
end

-- ==========================================
-- ЗАГРУЗКА ТЕЛА
-- ==========================================

function LoadBoody(ped, data)
    if not ped or not DoesEntityExist(ped) then
        ped = CreatorPed
        if not ped or not DoesEntityExist(ped) then
            print('[RSG-Appearance] LoadBoody: No valid ped')
            return
        end
    end

    local isMale = IsPedMale(ped)
    local skinTone = data.skin_tone or 1
    local gender = isMale and 'male' or 'female'

    print('[RSG-Appearance] LoadBoody: gender=' .. gender .. ' skinTone=' .. tostring(skinTone))

    local clotheslist = require 'data.clothes_list'

    local bodies_upper = {}
    local bodies_lower = {}

    for _, item in ipairs(clotheslist) do
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

    print('[RSG-Appearance] LoadBoody: Found ' .. #bodies_upper .. ' BODIES_UPPER, ' .. #bodies_lower .. ' BODIES_LOWER')

    -- ★ FIX: Увеличены таймауты для высокого пинга (с 500мс до 2с)
    if #bodies_upper > 0 then
        local idx = math.min(skinTone, #bodies_upper)
        if idx < 1 then idx = 1 end

        local bodyData = bodies_upper[idx]
        if bodyData and bodyData.hash then
            Citizen.InvokeNative(0x59BD177A1A48600A, ped, bodyData.hash)
            Citizen.InvokeNative(0xD3A7B003ED343FD9, ped, bodyData.hash, true, true, true)

            local timeout = 0
            while not Citizen.InvokeNative(0xA0BC8FAED8CFEB3C, ped) and timeout < 100 do
                Wait(20)
                timeout = timeout + 1
            end

            if timeout >= 100 then
                print('[RSG-Appearance] LoadBoody upper: Streaming timeout, retrying...')
                Citizen.InvokeNative(0x59BD177A1A48600A, ped, bodyData.hash)
                Citizen.InvokeNative(0xD3A7B003ED343FD9, ped, bodyData.hash, true, true, true)
                local t2 = 0
                while not Citizen.InvokeNative(0xA0BC8FAED8CFEB3C, ped) and t2 < 100 do
                    Wait(20)
                    t2 = t2 + 1
                end
            end
        end
    end

    if #bodies_lower > 0 then
        local idx = math.min(skinTone, #bodies_lower)
        if idx < 1 then idx = 1 end

        local bodyData = bodies_lower[idx]
        if bodyData and bodyData.hash then
            Citizen.InvokeNative(0x59BD177A1A48600A, ped, bodyData.hash)
            Citizen.InvokeNative(0xD3A7B003ED343FD9, ped, bodyData.hash, true, true, true)

            local timeout = 0
            while not Citizen.InvokeNative(0xA0BC8FAED8CFEB3C, ped) and timeout < 100 do
                Wait(20)
                timeout = timeout + 1
            end

            if timeout >= 100 then
                print('[RSG-Appearance] LoadBoody lower: Streaming timeout, retrying...')
                Citizen.InvokeNative(0x59BD177A1A48600A, ped, bodyData.hash)
                Citizen.InvokeNative(0xD3A7B003ED343FD9, ped, bodyData.hash, true, true, true)
                local t2 = 0
                while not Citizen.InvokeNative(0xA0BC8FAED8CFEB3C, ped) and t2 < 100 do
                    Wait(20)
                    t2 = t2 + 1
                end
            end
        end
    end

    Wait(50)
    Citizen.InvokeNative(0x704C908E9C405136, ped)
    Citizen.InvokeNative(0xCC8CA3E88256E58F, ped, false, true, true, true, false)

    if isMale then
        Wait(100)
        local componentsLoaded = Citizen.InvokeNative(0xA0BC8FAED8CFEB3C, ped)
        if not componentsLoaded then
            if #bodies_upper > 0 then
                local idx = math.min(skinTone, #bodies_upper)
                local bodyData = bodies_upper[idx]
                if bodyData and bodyData.hash then
                    Citizen.InvokeNative(0x59BD177A1A48600A, ped, bodyData.hash)
                    Citizen.InvokeNative(0xD3A7B003ED343FD9, ped, bodyData.hash, true, true, true)
                end
            end

            if #bodies_lower > 0 then
                local idx = math.min(skinTone, #bodies_lower)
                local bodyData = bodies_lower[idx]
                if bodyData and bodyData.hash then
                    Citizen.InvokeNative(0x59BD177A1A48600A, ped, bodyData.hash)
                    Citizen.InvokeNative(0xD3A7B003ED343FD9, ped, bodyData.hash, true, true, true)
                end
            end

            Wait(100)
            Citizen.InvokeNative(0x704C908E9C405136, ped)
            Citizen.InvokeNative(0xCC8CA3E88256E58F, ped, false, true, true, true, false)
        end
    end

    print('[RSG-Appearance] LoadBoody: Completed for ' .. gender)
    -- ★ Восстанавливаем body morph после LoadBoody (UpdatePedVariation сбрасывает face features)
    if _G._BodyMorphData and _G._BodyMorphData.active then
        ReapplyBodyMorph(ped)
    end
end

-- ==========================================
-- ЗАГРУЗКА РОСТА
-- ==========================================

function LoadHeight(ped, data)
    if not ped or not DoesEntityExist(ped) then return end

    local height = data.height or 100
    local scale = height / 100.0

    -- ★ Расширенный диапазон: 80-130
    scale = math.max(0.80, math.min(1.30, scale))
    SetPedScale(ped, scale)
end

-- ==========================================
-- ЗАГРУЗКА ВОЛОС
-- ==========================================

function LoadHair(ped, data)
    if not ped or not DoesEntityExist(ped) then
        ped = CreatorPed
        if not ped then return end
    end

    if data.hair_hashname and data.hair_hashname ~= "" then
        local hash = GetHashKey(data.hair_hashname)
        Citizen.InvokeNative(0xD710A5007C2AC539, ped, GetHashKey("hair"), 0)
        Wait(50)
        Citizen.InvokeNative(0x59BD177A1A48600A, ped, hash)
        Citizen.InvokeNative(0xD3A7B003ED343FD9, ped, hash, true, true, true)
        -- ★ FIX: Ждём стриминг
        local ht = 0
        while not Citizen.InvokeNative(0xA0BC8FAED8CFEB3C, ped) and ht < 100 do Wait(20) ht = ht + 1 end
        Citizen.InvokeNative(0x704C908E9C405136, ped)
        Citizen.InvokeNative(0xCC8CA3E88256E58F, ped, false, true, true, true, false)
        return
    end

    local hairData = data.hair or data
    local model = 0
    local color = 1

    if type(hairData) == 'table' then
        model = hairData.model or 0
        color = hairData.color or hairData.texture or 1
    elseif type(hairData) == 'number' then
        model = hairData
        color = data.hair_color or 1
    end

    if model == 0 then
        Citizen.InvokeNative(0xD710A5007C2AC539, ped, GetHashKey("hair"), 0)
        Citizen.InvokeNative(0x704C908E9C405136, ped)
        Citizen.InvokeNative(0xCC8CA3E88256E58F, ped, false, true, true, true, false)
        return
    end

    local isMale = IsPedMale(ped)
    local gender = isMale and 'male' or 'female'

    local hairs_list = nil
    pcall(function()
        hairs_list = require 'data.hairs_list'
    end)

    local targetHash = nil

    if hairs_list and hairs_list[gender] and hairs_list[gender]['hair'] then
        local hairModels = hairs_list[gender]['hair']
        if hairModels[model] and hairModels[model][color] then
            targetHash = hairModels[model][color].hash
        elseif hairModels[model] and hairModels[model][1] then
            targetHash = hairModels[model][1].hash
        end
    end

    if not targetHash then
        local clotheslist = require 'data.clothes_list'
        local hairs = {}
        for _, item in ipairs(clotheslist) do
            if item.category_hashname == 'hair' and item.ped_type == gender and item.is_multiplayer then
                table.insert(hairs, item.hash)
            end
        end
        if #hairs > 0 then
            local idx = ((model - 1) * 15) + color
            if idx < 1 then idx = 1 end
            if idx > #hairs then idx = math.min(model, #hairs) end
            targetHash = hairs[idx]
        end
    end

    if targetHash then
        Citizen.InvokeNative(0x59BD177A1A48600A, ped, targetHash) -- ★ FIX: Request перед Apply
        Citizen.InvokeNative(0xD3A7B003ED343FD9, ped, targetHash, true, true, true)
        -- ★ FIX: Ждём стриминг
        local ht = 0
        while not Citizen.InvokeNative(0xA0BC8FAED8CFEB3C, ped) and ht < 100 do Wait(20) ht = ht + 1 end
        Citizen.InvokeNative(0x704C908E9C405136, ped)
        Citizen.InvokeNative(0xCC8CA3E88256E58F, ped, false, true, true, true, false)
    end
end

-- ==========================================
-- ЗАГРУЗКА БОРОДЫ
-- ==========================================

function LoadBeard(ped, data)
    if not ped or not DoesEntityExist(ped) then
        ped = CreatorPed
        if not ped then return end
    end

    if not IsPedMale(ped) then return end

    if data.beard_hashname and data.beard_hashname ~= "" then
        local hash = GetHashKey(data.beard_hashname)
        Citizen.InvokeNative(0xD710A5007C2AC539, ped, GetHashKey("beards_complete"), 0)
        Citizen.InvokeNative(0xD710A5007C2AC539, ped, GetHashKey("beards_stubble"), 0)
        Citizen.InvokeNative(0xD710A5007C2AC539, ped, GetHashKey("mustache"), 0)
        Wait(50)
        Citizen.InvokeNative(0x59BD177A1A48600A, ped, hash)
        Citizen.InvokeNative(0xD3A7B003ED343FD9, ped, hash, true, true, true)
        -- ★ FIX: Ждём стриминг
        local bt = 0
        while not Citizen.InvokeNative(0xA0BC8FAED8CFEB3C, ped) and bt < 100 do Wait(20) bt = bt + 1 end
        Citizen.InvokeNative(0x704C908E9C405136, ped)
        Citizen.InvokeNative(0xCC8CA3E88256E58F, ped, false, true, true, true, false)
        return
    end

    local beardData = data.beard or data
    local model = 0
    local color = 1

    if type(beardData) == 'table' then
        model = beardData.model or 0
        color = beardData.color or beardData.texture or 1
    elseif type(beardData) == 'number' then
        model = beardData
        color = data.beard_color or 1
    end

    if model == 0 then
        Citizen.InvokeNative(0xD710A5007C2AC539, ped, GetHashKey("beards_complete"), 0)
        Citizen.InvokeNative(0xD710A5007C2AC539, ped, GetHashKey("beards_stubble"), 0)
        Citizen.InvokeNative(0xD710A5007C2AC539, ped, GetHashKey("mustache"), 0)
        Citizen.InvokeNative(0x704C908E9C405136, ped)
        Citizen.InvokeNative(0xCC8CA3E88256E58F, ped, false, true, true, true, false)
        return
    end

    local hairs_list = nil
    pcall(function()
        hairs_list = require 'data.hairs_list'
    end)

    local targetHash = nil

    if hairs_list and hairs_list['male'] and hairs_list['male']['mustache'] then
        local beardModels = hairs_list['male']['mustache']
        if beardModels[model] and beardModels[model][color] then
            targetHash = beardModels[model][color].hash
        elseif beardModels[model] and beardModels[model][1] then
            targetHash = beardModels[model][1].hash
        end
    end

    if not targetHash then
        local clotheslist = require 'data.clothes_list'
        local beards = {}
        for _, item in ipairs(clotheslist) do
            if (item.category_hashname == 'beards_complete' or item.category_hashname == 'beard' or item.category_hashname == 'mustache')
               and item.ped_type == 'male' and item.is_multiplayer then
                table.insert(beards, item.hash)
            end
        end
        if #beards > 0 then
            local idx = ((model - 1) * 15) + color
            if idx < 1 then idx = 1 end
            if idx > #beards then idx = math.min(model, #beards) end
            targetHash = beards[idx]
        end
    end

    if targetHash then
        Citizen.InvokeNative(0x59BD177A1A48600A, ped, targetHash) -- ★ FIX: Request перед Apply
        Citizen.InvokeNative(0xD3A7B003ED343FD9, ped, targetHash, true, true, true)
        -- ★ FIX: Ждём стриминг
        local bt = 0
        while not Citizen.InvokeNative(0xA0BC8FAED8CFEB3C, ped) and bt < 100 do Wait(20) bt = bt + 1 end
        Citizen.InvokeNative(0x704C908E9C405136, ped)
        Citizen.InvokeNative(0xCC8CA3E88256E58F, ped, false, true, true, true, false)
    end
end

-- ==========================================
-- ЗАГРУЗКА ГЛАЗ
-- ==========================================

local EyesHashCache = { male = {}, female = {} }
local EyesCacheBuilt = false

local function BuildEyesCache()
    if EyesCacheBuilt then return end
    local clotheslist = require 'data.clothes_list'
    for _, item in ipairs(clotheslist) do
        if item.category_hashname == 'eyes' and item.is_multiplayer then
            if item.hashname and item.hashname ~= "" and string.find(item.hashname, "EYES_001_TINT") then
                local gender = item.ped_type
                if EyesHashCache[gender] then
                    table.insert(EyesHashCache[gender], { hash = item.hash, hashname = item.hashname })
                end
            end
        end
    end
    EyesCacheBuilt = true
end

function LoadEyes(ped, data)
    if not ped or not DoesEntityExist(ped) then
        ped = CreatorPed
        if not ped then return end
    end

    local eyeColor = data.eyes_color or data.eyes or 1
    local isMale = IsPedMale(ped)
    local gender = isMale and 'male' or 'female'

    BuildEyesCache()

    local targetHash = nil
    local eyesList = EyesHashCache[gender]
    if eyesList and #eyesList > 0 then
        local idx = math.max(1, math.min(eyeColor, #eyesList))
        targetHash = eyesList[idx].hash
    end

    if targetHash then
        Citizen.InvokeNative(0xD710A5007C2AC539, ped, GetHashKey("eyes"), 0)
        Wait(50)
        Citizen.InvokeNative(0x59BD177A1A48600A, ped, targetHash) -- ★ FIX: Request перед Apply
        Citizen.InvokeNative(0xD3A7B003ED343FD9, ped, targetHash, true, true, true)
        -- ★ FIX: Увеличен таймаут с 500мс до 2с
        local timeout = 0
        while not Citizen.InvokeNative(0xA0BC8FAED8CFEB3C, ped) and timeout < 100 do
            Wait(20)
            timeout = timeout + 1
        end
        Citizen.InvokeNative(0x704C908E9C405136, ped)
        Citizen.InvokeNative(0xCC8CA3E88256E58F, ped, false, true, true, true, false)
    end
end

-- ==========================================
-- ЗАГРУЗКА ЧЕРТ ЛИЦА
-- ★ ИСПРАВЛЕНО v7: Исключаем body morph features — они управляются LoadAllBodyShape
-- ==========================================

local BodyMorphFeatureNames = {
    waist_width = true,
    chest_size = true,
    hips_size = true,
    arms_size = true,
    tight_size = true,
    calves_size = true,
    uppr_shoulder_size = true,
    back_shoulder_thickness = true,
    back_muscle = true,
}

function LoadFeatures(ped, data)
    if not ped or not DoesEntityExist(ped) then return end
    if type(data) ~= 'table' then return end
    for featureName, featureHash in pairs(Data.features) do
        -- ★ Пропускаем body morph features — они управляются отдельно
        if not BodyMorphFeatureNames[featureName] then
            -- Применяем только явно заданные значения.
            -- Это предотвращает перезатирание активного слайдера "нулём"
            -- из неинициализированных полей (особенно заметно на бровях).
            local value = tonumber(data[featureName])
            if value ~= nil then
                if value > 100 then value = 100 end
                if value < -100 then value = -100 end
                SetPedFaceFeature(ped, featureHash, value)
            end
        end
    end
    -- ★ После LoadFeatures — восстанавливаем body morph
    if _G._BodyMorphData and _G._BodyMorphData.active then
        ReapplyBodyMorph(ped)
    end
end

-- ==========================================
-- ★ ЗАГРУЗКА РАЗМЕРА ТЕЛА (БЕЗ UpdatePedVariation)
-- ==========================================

function LoadBodyFeature(ped, value, hashTable)
    if not ped or not DoesEntityExist(ped) then return end
    if not hashTable or not value then return end

    local index = math.floor(value)
    if index < 1 then index = 1 end
    if index > #hashTable then index = #hashTable end

    local hash = hashTable[index]
    if hash and hash ~= 0 then
        SetPedBodyComponent(ped, hash)
    end
end

-- ==========================================
-- ★ BODY MORPH SYSTEM v7 — ОБЪЕДИНЁННАЯ СИСТЕМА
-- Использует ОБА механизма:
-- 1. SetPedBodyComponent (0x1902C4CFCC5BE57C) — хеш-компоненты тела
-- 2. SetPedFaceFeature (0x5653AB26C82938CF) — face features для тонкой настройки
-- ==========================================

local F = Data.features

local function toPct(value, minVal, maxVal)
    if not value then return nil end
    local v = math.floor(value)
    if v < minVal then v = minVal end
    if v > maxVal then v = maxVal end
    return math.floor((v - minVal) / (maxVal - minVal) * 100)
end

-- ★ Для расширенного waist: 1-21 → 0-100, 22-30 → 105-145
local function waistToPct(value)
    if not value then return nil end
    local v = math.floor(value)
    if v < 1 then v = 1 end
    if v > 30 then v = 30 end
    if v <= 21 then
        return math.floor((v - 1) / 20 * 100)
    else
        return 100 + math.floor((v - 21) / 9 * 45)
    end
end

-- ★ Применяет ТОЛЬКО face features для body morph (без хешей)
-- ★ v8: Талия (waist) теперь также увеличивает бёдра для более округлого пуза
function ApplyBodyMorphFaceFeatures(ped, waistVal, chestVal, sizeVal)
    if not ped or not DoesEntityExist(ped) then return end

    -- ★ Талия/пузо
    if waistVal ~= nil and F.waist_width then
        SetPedFaceFeature(ped, F.waist_width, waistVal)
    end

    -- ★ Грудь
    if chestVal ~= nil then
        if F.chest_size then SetPedFaceFeature(ped, F.chest_size, chestVal) end
        if F.back_muscle then SetPedFaceFeature(ped, F.back_muscle, chestVal) end
        if F.back_shoulder_thickness then SetPedFaceFeature(ped, F.back_shoulder_thickness, math.floor(chestVal * 0.7)) end
    end

    -- ★ Комбинируем hips/thighs из body_size И waist для более округлого тела
    -- Талия > 50% добавляет объём к бёдрам и бёдрам — это даёт эффект большого пуза
    local baseSize = sizeVal or 0
    local waistBonus = 0
    if waistVal and waistVal > 30 then
        waistBonus = math.floor((waistVal - 30) * 0.7)
    end

    local combinedHips = math.min(100, baseSize + waistBonus)
    local combinedThighs = math.min(100, math.floor(baseSize * 0.8) + math.floor(waistBonus * 0.4))

    if F.hips_size then SetPedFaceFeature(ped, F.hips_size, combinedHips) end
    if F.tight_size then SetPedFaceFeature(ped, F.tight_size, combinedThighs) end
    if F.calves_size then SetPedFaceFeature(ped, F.calves_size, math.floor(baseSize * 0.6)) end
    if F.arms_size then SetPedFaceFeature(ped, F.arms_size, baseSize) end
    if F.uppr_shoulder_size then SetPedFaceFeature(ped, F.uppr_shoulder_size, math.floor(baseSize * 0.7)) end
end

-- ★ ГЛАВНАЯ ФУНКЦИЯ: Применяет body morph хешами + face features + сохраняет в _G
function ApplyAllBodyMorph(ped, skinData)
    if not ped or not DoesEntityExist(ped) then return end
    if not skinData then return end

    local bodyWaist = skinData.body_waist or 11
    local bodySize = skinData.body_size or 3
    local chestSize = skinData.chest_size or 6

    -- Вычисляем face feature проценты
    local waistVal = waistToPct(bodyWaist)
    local chestVal = toPct(chestSize, 1, 11)
    local sizeVal = toPct(bodySize, 1, 5)

    -- ★ Сохраняем в глобальное хранилище для guard и ReapplyBodyMorph
    _G._BodyMorphData = {
        active = true,
        -- Индексы слайдеров (для LoadBodyFeature)
        body_waist = bodyWaist,
        body_size = bodySize,
        chest_size = chestSize,
        -- Face feature проценты
        waist_value = waistVal,
        chest_value = chestVal,
        size_value = sizeVal,
        -- Legacy хеши
        size_hash = nil,
        waist_hash = nil,
        chest_hash = nil,
    }

    -- ★ ШАГ 1: Применяем hash-based body components (основной визуальный эффект)
    local waistIdx = math.min(bodyWaist, #Data.Appearance.body_waist)
    if waistIdx < 1 then waistIdx = 1 end
    LoadBodyFeature(ped, waistIdx, Data.Appearance.body_waist)

    LoadBodyFeature(ped, bodySize, Data.Appearance.body_size)
    LoadBodyFeature(ped, chestSize, Data.Appearance.chest_size)

    -- ★ ШАГ 2: Применяем face features (дополнительная тонкая настройка)
    ApplyBodyMorphFaceFeatures(ped, waistVal, chestVal, sizeVal)

    -- НЕ вызываем UpdatePedVariation — она сбрасывает морфы!

    print('[BodyMorph] Applied (v7 combined): waist=' .. tostring(bodyWaist) .. '→' .. tostring(waistVal) .. '% chest=' .. tostring(chestSize) .. '→' .. tostring(chestVal) .. '% size=' .. tostring(bodySize) .. '→' .. tostring(sizeVal) .. '%')
end

-- ★ Переприменяет body morph из _G._BodyMorphData
-- Вызывается из guard, LoadFeatures, clothes.lua и т.д.
function ReapplyBodyMorph(ped)
    if not _G._BodyMorphData or not _G._BodyMorphData.active then return end
    if not ped or not DoesEntityExist(ped) then ped = PlayerPedId() end

    local bm = _G._BodyMorphData

    -- ★ Hash-based body components
    if bm.body_waist then
        local waistIdx = math.min(bm.body_waist, #Data.Appearance.body_waist)
        if waistIdx < 1 then waistIdx = 1 end
        local hash = Data.Appearance.body_waist[waistIdx]
        if hash and hash ~= 0 then
            SetPedBodyComponent(ped, hash)
        end
    end
    if bm.body_size then
        LoadBodyFeature(ped, bm.body_size, Data.Appearance.body_size)
    end
    if bm.chest_size then
        LoadBodyFeature(ped, bm.chest_size, Data.Appearance.chest_size)
    end

    -- ★ Face features
    ApplyBodyMorphFaceFeatures(ped, bm.waist_value, bm.chest_value, bm.size_value)

    -- Legacy хеши (если были)
    if bm.size_hash then SetPedBodyComponent(ped, bm.size_hash) end
    if bm.waist_hash then SetPedBodyComponent(ped, bm.waist_hash) end
    if bm.chest_hash then SetPedBodyComponent(ped, bm.chest_hash) end
end

-- ★ Полная загрузка формы тела (вызывается при загрузке персонажа)
-- Делает ОБЕ механики + UpdatePedVariation + повторное применение face features
function LoadAllBodyShape(ped, skinData)
    if not ped or not DoesEntityExist(ped) then ped = PlayerPedId() end
    if not skinData then return end

    -- Применяем всё
    ApplyAllBodyMorph(ped, skinData)

    -- UpdatePedVariation чтобы хеш-компоненты вступили в силу
    Citizen.InvokeNative(0x704C908E9C405136, ped)
    Citizen.InvokeNative(0xCC8CA3E88256E58F, ped, false, true, true, true, false)
    Wait(50)

    -- ★ Повторно применяем face features ПОСЛЕ UpdatePedVariation
    -- (потому что UpdatePedVariation может сбросить face features)
    local bm = _G._BodyMorphData
    if bm and bm.active then
        ApplyBodyMorphFaceFeatures(ped, bm.waist_value, bm.chest_value, bm.size_value)
    end

    print('[BodyMorph] LoadAllBodyShape complete')
end

-- ★ Guard: быстрый + постоянный фоновый
local _bodyMorphGuardActive = false
local _bodyMorphPersistentActive = false

function StartBodyMorphGuard(ped, duration_ms)
    -- Быстрый guard (каждые 200мс) на первые N секунд
    if not _bodyMorphGuardActive then
        _bodyMorphGuardActive = true
        duration_ms = duration_ms or 15000

        CreateThread(function()
            local endTime = GetGameTimer() + duration_ms
            while GetGameTimer() < endTime do
                Wait(200)
                local p = PlayerPedId()
                if DoesEntityExist(p) and _G._BodyMorphData and _G._BodyMorphData.active then
                    ReapplyBodyMorph(p)
                end
            end
            _bodyMorphGuardActive = false
        end)
    end

    -- Постоянный фоновый guard (каждые 5 сек) — навсегда
    if not _bodyMorphPersistentActive then
        _bodyMorphPersistentActive = true

        CreateThread(function()
            while true do
                Wait(5000)
                if _G._BodyMorphData and _G._BodyMorphData.active then
                    local p = PlayerPedId()
                    if DoesEntityExist(p) then
                        ReapplyBodyMorph(p)
                    end
                end
            end
        end)
    end
end

-- ==========================================
-- ЗАГРУЗКА ОВЕРЛЕЕВ
-- ==========================================

local textureId = -1

function ChangeOverlays(name, visibility, tx_id, tx_normal, tx_material, tx_color_type, tx_opacity, tx_unk, palette_id,
    palette_color_primary, palette_color_secondary, palette_color_tertiary, var, opacity)
    for k, v in pairs(Overlays.overlay_all_layers) do
        if v.name == name then
            v.visibility = visibility
            if visibility ~= 0 then
                v.tx_normal = tx_normal
                v.tx_material = tx_material
                v.tx_color_type = tx_color_type
                v.tx_opacity = tx_opacity
                v.tx_unk = tx_unk
                if tx_color_type == 0 then
                    v.palette = Overlays.color_palettes[palette_id] and Overlays.color_palettes[palette_id][1] or 0
                    v.palette_color_primary = palette_color_primary
                    v.palette_color_secondary = palette_color_secondary
                    v.palette_color_tertiary = palette_color_tertiary
                end
                if name == "shadows" or name == "eyeliners" or name == "lipsticks" then
                    v.var = var
                    v.tx_id = Overlays.overlays_info[name] and Overlays.overlays_info[name][1] and Overlays.overlays_info[name][1].id or 0
                else
                    v.var = 0
                    v.tx_id = Overlays.overlays_info[name] and Overlays.overlays_info[name][tx_id] and Overlays.overlays_info[name][tx_id].id or 0
                end
                v.opacity = opacity
            end
        end
    end
end

function GetHeadIndex(ped)
    local numComponents = Citizen.InvokeNative(0x90403E8107B60E81, ped)
    if not numComponents then return false end
    for i = 0, numComponents - 1, 1 do
        local componentCategory = Citizen.InvokeNative(0x9b90842304c938a7, ped, i, 0, Citizen.ResultAsInteger())
        if componentCategory == GetHashKey('heads') then
            return i
        end
    end
    return false
end

function GetMetaPedAssetGuids(ped, index)
    return Citizen.InvokeNative(0xA9C28516A6DC9D56, ped, index, Citizen.PointerValueInt(), Citizen.PointerValueInt(), Citizen.PointerValueInt(), Citizen.PointerValueInt())
end

function ApplyOverlays(overlayTarget)
    if IsPedMale(overlayTarget) then
        Overlays.current_texture_settings = Overlays.texture_types["male"]
    else
        Overlays.current_texture_settings = Overlays.texture_types["female"]
    end

    if textureId ~= -1 then
        Citizen.InvokeNative(0xB63B9178D0F58D82, textureId)
        Citizen.InvokeNative(0x6BEFAA907B076859, textureId)
    end

    local index = GetHeadIndex(overlayTarget)
    if not index then return end

    local _, albedo, normal, material = GetMetaPedAssetGuids(overlayTarget, index)
    textureId = Citizen.InvokeNative(0xC5E7204F322E49EB, albedo, normal, material)

    for k, v in pairs(Overlays.overlay_all_layers) do
        if v.visibility ~= 0 then
            local overlay_id = Citizen.InvokeNative(0x86BB5FF45F193A02, textureId, v.tx_id, v.tx_normal, v.tx_material,
                v.tx_color_type, v.tx_opacity, v.tx_unk)
            if v.tx_color_type == 0 then
                Citizen.InvokeNative(0x1ED8588524AC9BE1, textureId, overlay_id, v.palette)
                Citizen.InvokeNative(0x2DF59FFE6FFD6044, textureId, overlay_id, v.palette_color_primary,
                    v.palette_color_secondary, v.palette_color_tertiary)
            end
            Citizen.InvokeNative(0x3329AAE2882FC8E4, textureId, overlay_id, v.var)
            Citizen.InvokeNative(0x6C76BC24F8BB709A, textureId, overlay_id, v.opacity)
        end
    end

    -- ★ FIX: Увеличен таймаут с 1с до 3с для высокого пинга
    local timeout = 0
    while not Citizen.InvokeNative(0x31DC8D3F216D8509, textureId) and timeout < 150 do
        Wait(20)
        timeout = timeout + 1
    end

    Citizen.InvokeNative(0x92DAABA2C1C10B0E, textureId)
    Citizen.InvokeNative(0x8472A1789478F82F, textureId)
    Citizen.InvokeNative(0x0B46E25761519058, overlayTarget, GetHashKey("heads"), textureId)
    Citizen.InvokeNative(0x704C908E9C405136, overlayTarget)
    Citizen.InvokeNative(0xCC8CA3E88256E58F, overlayTarget, false, true, true, true, false)
end

function LoadOverlays(ped, data)
    if not ped or not DoesEntityExist(ped) then
        ped = CreatorPed
        if not ped then return end
    end

    -- ★ FIX: Увеличен таймаут с 5с до 10с для высокого пинга
    local timeout = 0
    local headIndex = GetHeadIndex(ped)
    while not headIndex and timeout < 100 do
        Wait(100)
        headIndex = GetHeadIndex(ped)
        timeout = timeout + 1
    end

    -- ★ СБРОС ВСЕХ ОВЕРЛЕЕВ перед загрузкой нового персонажа
    -- Без этого данные предыдущего персонажа (шрамы, веснушки, родинки и т.д.)
    -- остаются в кэше Overlays.overlay_all_layers и применяются к новому персонажу
    for _, layer in pairs(Overlays.overlay_all_layers) do
        layer.visibility = 0
        layer.tx_id = 1
        layer.tx_normal = 0
        layer.tx_material = 0
        layer.tx_color_type = 0
        layer.tx_opacity = 1.0
        layer.tx_unk = 0
        layer.palette = 0
        layer.palette_color_primary = 0
        layer.palette_color_secondary = 0
        layer.palette_color_tertiary = 0
        layer.var = 0
        layer.opacity = 0.0
    end

    if tonumber(data.eyebrows_t) ~= nil and tonumber(data.eyebrows_op) ~= nil then
        ChangeOverlays("eyebrows", 1, tonumber(data.eyebrows_t), 0, 0, 0, 1.0, 0, tonumber(data.eyebrows_id) or 10,
            tonumber(data.eyebrows_c1) or 0, 0, 0, 0, tonumber(data.eyebrows_op) / 100)
    else
        ChangeOverlays("eyebrows", 1, 1, 0, 0, 0, 1.0, 0, 10, 0, 0, 0, 0, 1.0)
    end

    if tonumber(data.scars_t) ~= nil and tonumber(data.scars_op) ~= nil then
        ChangeOverlays("scars", 1, tonumber(data.scars_t), 0, 0, 1, 1.0, 0, 0, 0, 0, 0, 0, tonumber(data.scars_op) / 100)
    end

    if tonumber(data.ageing_t) ~= nil and tonumber(data.ageing_op) ~= nil then
        ChangeOverlays("ageing", 1, tonumber(data.ageing_t), 0, 0, 1, 1.0, 0, 0, 0, 0, 0, 0, tonumber(data.ageing_op) / 100)
    end

    if tonumber(data.freckles_t) ~= nil and tonumber(data.freckles_op) ~= nil then
        ChangeOverlays("freckles", 1, tonumber(data.freckles_t), 0, 0, 1, 1.0, 0, 0, 0, 0, 0, 0, tonumber(data.freckles_op) / 100)
    end

    if tonumber(data.moles_t) ~= nil and tonumber(data.moles_op) ~= nil then
        ChangeOverlays("moles", 1, tonumber(data.moles_t), 0, 0, 1, 1.0, 0, 0, 0, 0, 0, 0, tonumber(data.moles_op) / 100)
    end

    if tonumber(data.spots_t) ~= nil and tonumber(data.spots_op) ~= nil then
        ChangeOverlays("spots", 1, tonumber(data.spots_t), 0, 0, 1, 1.0, 0, 0, 0, 0, 0, 0, tonumber(data.spots_op) / 100)
    end

    ApplyOverlays(ped)
    -- ★ Восстанавливаем body morph после ApplyOverlays (UpdatePedVariation сбрасывает face features)
    if _G._BodyMorphData and _G._BodyMorphData.active then
        ReapplyBodyMorph(ped)
    end
end

-- ==========================================
-- ЗАГРУЗКА СТАРТОВОЙ ОДЕЖДЫ
-- ==========================================

function LoadStarterClothing(ped, category, model, texture)
    if not ped or not DoesEntityExist(ped) then
        ped = CreatorPed
        if not ped then return end
    end

    local isMale = IsPedMale(ped)
    local gender = isMale and 'male' or 'female'

    if model == 0 then
        Citizen.InvokeNative(0xD710A5007C2AC539, ped, GetHashKey(category), 0)
        Citizen.InvokeNative(0x704C908E9C405136, ped)
        Citizen.InvokeNative(0xCC8CA3E88256E58F, ped, false, true, true, true, false)
        return
    end

    local clothing = require 'data.clothing'
    local targetHash = nil
    texture = texture or 1

    if clothing[gender] and clothing[gender][category] then
        local categoryData = clothing[gender][category]
        if categoryData[model] then
            if categoryData[model][texture] and categoryData[model][texture].hash then
                targetHash = categoryData[model][texture].hash
            elseif categoryData[model][1] and categoryData[model][1].hash then
                targetHash = categoryData[model][1].hash
            end
        end
    end

    if not targetHash then
        local clotheslist = require 'data.clothes_list'
        local items = {}
        for _, item in ipairs(clotheslist) do
            if item.category_hashname == category and item.ped_type == gender and item.is_multiplayer then
                if item.hashname and item.hashname ~= "" then
                    table.insert(items, item.hash)
                end
            end
        end
        if #items > 0 then
            local idx = ((model - 1) * 10) + texture
            if idx < 1 then idx = 1 end
            if idx > #items then idx = math.min(model, #items) end
            targetHash = items[idx]
        end
    end

    if targetHash then
        Citizen.InvokeNative(0xD3A7B003ED343FD9, ped, targetHash, true, true, true)
        Citizen.InvokeNative(0x704C908E9C405136, ped)
        Citizen.InvokeNative(0xCC8CA3E88256E58F, ped, false, true, true, true, false)
    end
end

-- ==========================================
-- ЭКСПОРТЫ
-- ==========================================

exports('LoadHead', LoadHead)
exports('LoadBoody', LoadBoody)
exports('LoadHeight', LoadHeight)
exports('LoadHair', LoadHair)
exports('LoadBeard', LoadBeard)
exports('LoadEyes', LoadEyes)
exports('LoadFeatures', LoadFeatures)
exports('LoadBodyFeature', LoadBodyFeature)
exports('ApplyAllBodyMorph', ApplyAllBodyMorph)
exports('ReapplyBodyMorph', ReapplyBodyMorph)
exports('LoadAllBodyShape', LoadAllBodyShape)
exports('StartBodyMorphGuard', StartBodyMorphGuard)
exports('LoadOverlays', LoadOverlays)
exports('LoadStarterClothing', LoadStarterClothing)

exports('GetHairsList', function()
    local hairs_list = nil
    pcall(function()
        hairs_list = require 'data.hairs_list'
    end)
    return hairs_list
end)

print('[RSG-Appearance] Load functions initialized (v3 - global body morph)')