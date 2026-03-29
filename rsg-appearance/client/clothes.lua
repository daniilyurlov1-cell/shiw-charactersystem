local RSGCore = exports['rsg-core']:GetCoreObject()

-- ★★★ ДИАГНОСТИЧЕСКИЕ КОМАНДЫ — используйте /debugcloth и /testequip в F8 ★★★

RegisterCommand('debugcloth', function()
    local ped = PlayerPedId()
    local model = GetEntityModel(ped)
    local mp_male_hash = GetHashKey('mp_male')
    local mp_female_hash = GetHashKey('mp_female')
    print('====== CLOTHING DEBUG ======')
    print('PedId: ' .. tostring(ped))
    print('Model hash: ' .. tostring(model))
    print('Is mp_male: ' .. tostring(model == mp_male_hash))
    print('Is mp_female: ' .. tostring(model == mp_female_hash))
    print('IsPedMale: ' .. tostring(IsPedMale(ped)))
    print('DoesEntityExist: ' .. tostring(DoesEntityExist(ped)))
    print('IsReadyToRender: ' .. tostring(Citizen.InvokeNative(0xA0BC8FAED8CFEB3C, ped)))
    print('--- ClothesCache ---')
    local count = 0
    for k, v in pairs(ClothesCache or {}) do
        if type(v) == 'table' then
            print('  ' .. tostring(k) .. ': hash=' .. tostring(v.hash) .. ', model=' .. tostring(v.model) .. ', tex=' .. tostring(v.texture))
            count = count + 1
        end
    end
    print('Total cached: ' .. count)
    print('============================')
end, false)

RegisterCommand('testequip', function()
    local ped = PlayerPedId()
    print('====== TEST EQUIP ======')
    -- Берём первый элемент из ClothesCache и переприменяем его напрямую
    local testHash = nil
    local testCat = nil
    for k, v in pairs(ClothesCache or {}) do
        if type(v) == 'table' and v.hash and v.hash ~= 0 then
            testHash = v.hash
            testCat = k
            break
        end
    end
    if testHash then
        print('Re-applying ' .. tostring(testCat) .. ' hash=' .. tostring(testHash))
        Citizen.InvokeNative(0x59BD177A1A48600A, ped, testHash)
        print('  > 0x59BD177A1A48600A (Request) called')
        Citizen.InvokeNative(0xD3A7B003ED343FD9, ped, testHash, true, true, true)
        print('  > 0xD3A7B003ED343FD9 (Apply, immediately=true) called')
        Citizen.InvokeNative(0x704C908E9C405136, ped)
        print('  > 0x704C908E9C405136 (Finalize) called')
        Citizen.InvokeNative(0xCC8CA3E88256E58F, ped, false, true, true, true, false)
        print('  > 0xCC8CA3E88256E58F (UpdateVariation) called')
        print('DONE! Check if the clothing item appeared visually.')
    else
        print('ClothesCache is empty! Equip something first, then run /debugcloth')
    end
    print('========================')
end, false)

RegisterCommand('testremove', function(source, args)
    local ped = PlayerPedId()
    local category = args[1] or 'hats'
    print('====== TEST REMOVE ======')
    print('Removing category: ' .. category)
    local compHash = GetHashKey(category)
    Citizen.InvokeNative(0xD710A5007C2AC539, ped, compHash, 0)
    print('  > 0xD710A5007C2AC539 (Remove by name) called')
    Citizen.InvokeNative(0x704C908E9C405136, ped)
    print('  > 0x704C908E9C405136 (Finalize) called')
    Citizen.InvokeNative(0xCC8CA3E88256E58F, ped, false, true, true, true, false)
    print('  > 0xCC8CA3E88256E58F (UpdateVariation) called')
    print('DONE! Check if the item was removed visually.')
    print('=========================')
end, false)

-- ★★★ КОНЕЦ ДИАГНОСТИЧЕСКИХ КОМАНД ★★★

local ClothingCamera = nil
local c_zoom = 2.4
local c_offset = -0.15
local CurrentPrice = 0
local CurentCoords = {}
local playerHeading = nil
local RoomPrompts = GetRandomIntInRange(0, 0xffffff)
local ClothesCache = {}
-- Время последней полной загрузки одежды (для защиты шляпы от ложной очистки после релоада)
local lastClothingLoadTime = 0
local OldClothesCache = {}
local PromptsEnabled = false
local IsInCharCreation = false
local Skinkosong = false
local ScheduleClothingResyncFromInventory = nil
local Divider = "<img style='margin-top: 10px;margin-bottom: 10px; margin-left: -10px;'src='nui://rsg-appearance/img/divider_line.png'>"
local image = "<img style='max-height:250px;max-width:250px;float: center;'src='nui://rsg-appearance/img/%s.png'>"

-- ★ После смены одежды: body morph + событие для nativepaint/раскраски (раскраска и морф слетают при UpdatePedVariation)
-- ★ FIX: При _PedStateFrozen не переприменяем — ReapplyBodyMorph мог вызывать лишние UpdatePedVariation
local function ReapplyAppearanceAfterClothing(ped)
    if not ped or not DoesEntityExist(ped) then return end
    if _G._PedStateFrozen then return end
    if ReapplyBodyMorph then ReapplyBodyMorph(ped) end
    TriggerEvent('rsg-appearance:client:clothingApplied', ped)
end

-- ★ МАППИНГ КАТЕГОРИЙ НА ХЕШИ КОМПОНЕНТОВ (для Ped одежды)
local CategoryComponentHash = {
    ['hats'] = 0x9925C067,
    ['shirts_full'] = 0x2026C46D,  -- ★ ОТЛИЧАЕТСЯ!
    ['shirts'] = 0x2026C46D,
    ['pants'] = 0x1D4C528A,        -- ★ ОТЛИЧАЕТСЯ!
    ['boots'] = 0x777EC6EF,
    ['vests'] = 0x485EE834,
    ['coats'] = 0xE06D30CE,        -- ★ ОТЛИЧАЕТСЯ!
    ['coats_closed'] = 0x662AC34,  -- ★ ОТЛИЧАЕТСЯ!
    ['gloves'] = 0xEABE0032,
    ['neckwear'] = 0x7A96FACA,     -- ★ ОТЛИЧАЕТСЯ!
    ['neckties'] = 0x7A96FACA,
    ['masks'] = 0x7505EF42,
    ['eyewear'] = 0x5F1BE9EC,      -- ★ ОТЛИЧАЕТСЯ!
    ['gunbelts'] = 0xF1542D11,     -- ★ ОТЛИЧАЕТСЯ!
    ['satchels'] = 0x94504D26,
    ['suspenders'] = 0x877A2CF7,
    ['chaps'] = 0x3107499B,
    ['spurs'] = 0x18729F39,
    ['cloaks'] = 0x3C1A74CD,
    ['ponchos'] = 0xAF14310B,
    ['skirts'] = 0xA0E3AB7F,
    ['belts'] = 0x9B2C8B89,
    ['belt_buckles'] = 0xDA0E2C55,
    ['dresses'] = 0x0662AC34,
    ['corsets'] = 0x485EE834,
    ['loadouts'] = 0x83887E88,
    ['gauntlets'] = 0x91CE9B20,
    ['holsters_left'] = 0x7A6BBD0B,
    ['holsters_right'] = 0x0B3966C9,
    ['accessories'] = 0x79D7DF96,
    ['badges'] = 0x79D7DF96,
    -- Дополнительные категории
    ['hair_accessories'] = 0x79D7DF96,
    ['boot_accessories'] = 0x18729F39,
    ['talisman_belt'] = 0x1AECF7DC,
    -- Украшения — отдельные слоты (rdr2mods)
    ['jewelry_bracelets'] = 0x7BC10759,
    ['jewelry_rings_left'] = 0xF16A1D23,
    ['jewelry_rings_right'] = 0x7A6BBD0B,
    ['rings_rh'] = 0x7A6BBD0B,
    ['rings_lh'] = 0xF16A1D23,
    ['bracelets'] = 0x7BC10759,
    -- Серьги (слот 0x72E6EF74 — у женщин серьги, у мужчин брошь/броня)
    ['earrings'] = 0x72E6EF74,
    ['armor'] = 0x72E6EF74,
}

local clothing = require 'data.clothing'
local hashToCache = require 'client.hashtocache'
-- Проверка что RSG доступен
if not RSG then
    print('[RSG-Clothing] ERROR: RSG config not loaded!')
    RSG = {}
end

-- Проверка цен
CreateThread(function()
    Wait(1000)
    if RSG.Price then
        print('[RSG-Clothing] Prices loaded: ' .. TableLength(RSG.Price) .. ' categories')
    else
        print('[RSG-Clothing] ERROR: RSG.Price not found!')
    end
end)

function TableLength(t)
    local count = 0
    for _ in pairs(t) do count = count + 1 end
    return count
end

-- Функция для сортировки таблицы по ключам
function pairsByKeys(t, f)
    local a = {}
    for n in pairs(t) do
        table.insert(a, n)
    end
    table.sort(a, f)
    local i = 0
    local iter = function()
        i = i + 1
        if a[i] == nil then
            return nil
        else
            return a[i], t[a[i]]
        end
    end
    return iter
end

-- Получить максимальное количество текстур для модели
function GetMaxTexturesForModel(category, model, checkGender)
    if model <= 0 then return 0 end
    
    local isMale = IsPedMale(PlayerPedId())
    local gender = isMale and "male" or "female"
    
    if not clothing[gender] or not clothing[gender][category] then
        return 0
    end
    
    if not clothing[gender][category][model] then
        return 0
    end
    
    local count = 0
    for texture, _ in pairs(clothing[gender][category][model]) do
        if texture > count then
            count = texture
        end
    end
    
    return count
end
-- ==========================================
-- СИСТЕМА ВОССТАНОВЛЕНИЯ ЧАСТЕЙ ТЕЛА
-- ==========================================

-- Категории которые "обрезают" нижнюю часть тела
local LowerBodyCutoffCategories = {
    'boots',
    'chaps', 
    'spurs',
    'boot_accessories',
    'spats'
}

-- Категории которые "обрезают" верхнюю часть тела
local UpperBodyCutoffCategories = {
    'vests',
    'coats',
    'coats_closed',
    'suspenders',
    'gunbelts',
    'loadouts',
    'ponchos',
    'cloaks'
}

-- Категории которые ПОКРЫВАЮТ нижнюю часть тела
local LowerBodyCoverCategories = {
    'pants',
    'skirts',
    'dresses'
}

-- Категории которые ПОКРЫВАЮТ верхнюю часть тела  
local UpperBodyCoverCategories = {
    'shirts_full',
    'dresses',
    'vests',
    'corsets',  -- ★ корсет/жилетка — один слот, оба покрывают грудь
}

-- Проверка наличия категории в кэше
local function IsCategoryEquipped(category)
    if not ClothesCache or not ClothesCache[category] then
        return false
    end
    
    local data = ClothesCache[category]
    if type(data) ~= 'table' then
        return false
    end
    
    -- Проверяем hash или model
    if data.hash and data.hash ~= 0 then
        return true
    end
    
    if data.model and data.model > 0 then
        return true
    end
    
    return false
end

-- Проверка есть ли хотя бы одна категория из списка
local function HasAnyCategory(categoryList)
    for _, cat in ipairs(categoryList) do
        if IsCategoryEquipped(cat) then
            return true
        end
    end
    return false
end

-- Получить hash базового тела из rsg-appearance
local function GetBodyHash(bodyType)
    local success, hash = pcall(function()
        return exports['rsg-appearance']:GetBodyCurrentComponentHash(bodyType)
    end)
    
    if success and hash and hash ~= 0 then
        return hash
    end
    
    return nil
end

-- Альтернативный способ получения hash тела через натив
local function GetBodyHashNative(ped, bodyType)
    local categoryHash = GetHashKey(bodyType == "BODIES_UPPER" and "bodies_upper" or "bodies_lower")
    local currentHash = Citizen.InvokeNative(0xFB4891BD7578CDC1, ped, categoryHash)
    return currentHash
end

-- ★ Fallback: hash тела из clothes_list (когда naked overlay — GetBodyHashNative вернёт 0)
local function GetBodyHashFromClothesList(ped, bodyType)
    local isMale = (IsPedMale(ped) == 1 or IsPedMale(ped) == true)
    local gender = isMale and "male" or "female"
    local skinTone = 1
    pcall(function()
        skinTone = exports['rsg-appearance']:GetCurrentSkinTone() or LoadedComponents and LoadedComponents.skin_tone or 1
    end)
    if not skinTone or skinTone < 1 then skinTone = 1 end
    local list = require 'data.clothes_list'
    local bodies = {}
    for _, item in ipairs(list) do
        if item.ped_type == gender and item.hash and item.hash ~= 0 and item.category_hashname == bodyType then
            if item.is_multiplayer then table.insert(bodies, item.hash) end
        end
    end
    -- ★ FIX: у male первые BODIES_LOWER с is_multiplayer=false — fallback без фильтра
    if #bodies == 0 then
        for _, item in ipairs(list) do
            if item.ped_type == gender and item.hash and item.hash ~= 0 and item.category_hashname == bodyType then
                table.insert(bodies, item.hash)
            end
        end
    end
    if #bodies > 0 then
        local idx = math.min(skinTone, #bodies)
        return bodies[idx]
    end
    return nil
end

-- ГЛАВНАЯ ФУНКЦИЯ: Обеспечить целостность тела
function EnsureBodyIntegrity(ped, forceUpdate)
    if not ped or not DoesEntityExist(ped) then
        ped = PlayerPedId()
    end
    
    -- ★ НОВОЕ: Проверяем глобальный флаг naked body
    -- Если naked body активен - НЕ трогаем тело!
    local nakedState = nil
    pcall(function()
        nakedState = exports['rsg-appearance']:GetNakedBodyState()
    end)
    
    -- ★ Также проверяем глобальную переменную (если экспорт не сработал)
    if not nakedState and NakedBodyState then
        nakedState = NakedBodyState
    end
    
    local needsUpdate = false
    
    -- ===============================
    -- ПРОВЕРКА НИЖНЕЙ ЧАСТИ ТЕЛА
    -- ===============================
    
    -- ★ ПРОПУСКАЕМ если naked lower применён
    local skipLower = nakedState and nakedState.lowerApplied
    
    if not skipLower then
        local hasLowerCutoff = HasAnyCategory(LowerBodyCutoffCategories)
        local hasLowerCover = HasAnyCategory(LowerBodyCoverCategories)
        
        if hasLowerCutoff and not hasLowerCover then
            local bodyHash = GetBodyHash("BODIES_LOWER")
            
            if not bodyHash or bodyHash == 0 then
                bodyHash = GetBodyHashNative(ped, "BODIES_LOWER")
            end
            
            if bodyHash and bodyHash ~= 0 then
                Citizen.InvokeNative(0x59BD177A1A48600A, ped, GetHashKey("bodies_lower"))
                Citizen.InvokeNative(0xD3A7B003ED343FD9, ped, bodyHash, true, true, true)
                -- ★ FIX: Увеличен таймаут ожидания (с 300мс до 2с)
                local t = 0
                while not Citizen.InvokeNative(0xA0BC8FAED8CFEB3C, ped) and t < 100 do Wait(20) t = t + 1 end
                needsUpdate = true
            else
                Citizen.InvokeNative(0x59BD177A1A48600A, ped, GetHashKey("bodies_lower"))
                needsUpdate = true
            end
        end
    end
    
    -- ===============================
    -- ПРОВЕРКА ВЕРХНЕЙ ЧАСТИ ТЕЛА
    -- ===============================
    
    -- ★ ПРОПУСКАЕМ если naked upper применён
    local skipUpper = nakedState and nakedState.upperApplied
    
    if not skipUpper then
        local hasUpperCutoff = HasAnyCategory(UpperBodyCutoffCategories)
        local hasUpperCover = HasAnyCategory(UpperBodyCoverCategories)
        -- ★ Только корсет/жилет без рубашки: НЕ применяем BODIES_UPPER — корсет рассчитан на голое тело, иначе стандартное тело просвечивает
        local vestOrCorsetOnly = (IsCategoryEquipped('vests') or IsCategoryEquipped('corsets')) and not IsCategoryEquipped('shirts_full') and not IsCategoryEquipped('dresses')
        local needUpperBody = (hasUpperCutoff and not hasUpperCover) and not vestOrCorsetOnly
        
        if needUpperBody then
            local bodyHash = GetBodyHash("BODIES_UPPER")
            
            if not bodyHash or bodyHash == 0 then
                bodyHash = GetBodyHashNative(ped, "BODIES_UPPER")
            end
            
            if bodyHash and bodyHash ~= 0 then
                Citizen.InvokeNative(0x59BD177A1A48600A, ped, GetHashKey("bodies_upper"))
                Citizen.InvokeNative(0xD3A7B003ED343FD9, ped, bodyHash, true, true, true)
                -- ★ FIX: Увеличен таймаут ожидания (с 300мс до 2с)
                local t = 0
                while not Citizen.InvokeNative(0xA0BC8FAED8CFEB3C, ped) and t < 100 do Wait(20) t = t + 1 end
                needsUpdate = true
            else
                Citizen.InvokeNative(0x59BD177A1A48600A, ped, GetHashKey("bodies_upper"))
                needsUpdate = true
            end
            -- ★ FIX: жилетка/корсет без рубашки — после bodies_upper переприменяем vest/corset поверх
            if vestOrCorsetOnly then
                local item = (ClothesCache and ClothesCache['vests'] and ClothesCache['vests'].hash and ClothesCache['vests'].hash ~= 0) and ClothesCache['vests']
                    or (ClothesCache and ClothesCache['corsets'] and ClothesCache['corsets'].hash and ClothesCache['corsets'].hash ~= 0) and ClothesCache['corsets']
                if item then
                    NativeSetPedComponentEnabledClothes(ped, item.hash, false, true, true)
                    needsUpdate = true
                end
            end
        elseif vestOrCorsetOnly then
            -- ★ Только корсет/жилет: тело не трогаем, только убеждаемся что корсет надет (без BODIES_UPPER)
            local item = (ClothesCache and ClothesCache['vests'] and ClothesCache['vests'].hash and ClothesCache['vests'].hash ~= 0) and ClothesCache['vests']
                or (ClothesCache and ClothesCache['corsets'] and ClothesCache['corsets'].hash and ClothesCache['corsets'].hash ~= 0) and ClothesCache['corsets']
            if item then
                NativeSetPedComponentEnabledClothes(ped, item.hash, false, true, true)
                needsUpdate = true
            end
        end
    end
    
    -- Обновляем вариацию если были изменения
    if needsUpdate or forceUpdate then
        Wait(50)
        NativeUpdatePedVariation(ped, true)
        -- ★ После UpdatePedVariation корсет/жилет может "уехать" под тело — переприменяем поверх (стандартная моделька просвечивает)
        local vestOnly = (IsCategoryEquipped('vests') or IsCategoryEquipped('corsets')) and not IsCategoryEquipped('shirts_full') and not IsCategoryEquipped('dresses')
        if vestOnly then
            local item = (ClothesCache and ClothesCache['vests'] and ClothesCache['vests'].hash and ClothesCache['vests'].hash ~= 0) and ClothesCache['vests']
                or (ClothesCache and ClothesCache['corsets'] and ClothesCache['corsets'].hash and ClothesCache['corsets'].hash ~= 0) and ClothesCache['corsets']
            if item then
                Wait(30)
                NativeSetPedComponentEnabledClothes(ped, item.hash, false, true, true)
                if NativeUpdatePedVariationClothes then NativeUpdatePedVariationClothes(ped) end
            end
        end
    end
    
    return needsUpdate
end

-- Экспорт функции
exports('EnsureBodyIntegrity', EnsureBodyIntegrity)
exports('ReapplyVestIfEquipped', ReapplyVestIfEquipped)
exports('HasVestEquipped', function()
    -- ★ vests и corsets — один слот (0x485EE834), оба закрывают грудь, chest_size пропускаем
    if ClothesCache and ClothesCache['vests'] and ClothesCache['vests'].hash and ClothesCache['vests'].hash ~= 0 then return true end
    if ClothesCache and ClothesCache['corsets'] and ClothesCache['corsets'].hash and ClothesCache['corsets'].hash ~= 0 then return true end
    return false
end)
-- ==========================================
-- СОСТОЯНИЕ МОДИФИКАЦИЙ ОДЕЖДЫ
-- ==========================================

local ClothingModifications = {
    sleeves = false, -- false = обычные, true = закатаны
    collar = false,  -- false = застегнут, true = расстегнут
}

-- ==========================================
-- СОСТОЯНИЕ МОДИФИКАЦИЙ ОДЕЖДЫ
-- ==========================================

local ClothingModifications = {
    sleeves = false, -- false = обычные, true = закатаны
    collar = false,  -- false = застегнут, true = расстегнут
}

-- Маппинг вариаций рубашек (примеры хешей)
local ShirtVariations = {
    -- Мужские рубашки
    male = {
        -- [обычная модель] = {sleeves = закатанная модель, collar = расстегнутая модель}
        [0x339C7959] = {sleeves = 0x4B3D4EF5, collar = 0x1FCD2EAB}, -- Everyday Shirt
        [0x21A1A7A] = {sleeves = 0x5F622EED, collar = 0x12D463B0},  -- Work Shirt
        [0x5C43B130] = {sleeves = 0x7A96766B, collar = 0x2B3C5E3D}, -- French Dress Shirt
        -- Добавьте больше рубашек по мере необходимости
    },
    -- Женские рубашки
    female = {
        [0x4869A5] = {sleeves = 0x6AC3C4F5, collar = 0x8B5D2CAD},   -- Shirtwaist
        [0x3D88E07C] = {sleeves = 0x5E4D3B2F, collar = 0x7C2A1DEF}, -- Casual Shirtwaist
        -- Добавьте больше рубашек
    }
}
function GetTintCategoryHash(category)
    return CategoryTintHash[category] or CategoryComponentHash[category] or GetHashKey(category)
end
-- ==========================================
-- ИКОНКИ КАТЕГОРИЙ
-- ==========================================

local CategoryIcons = {
    -- Голова
    ['hats'] = 'hats',
    ['eyewear'] = 'eyewear',
    ['masks'] = 'masks',
    ['neckwear'] = 'neckwear',
    ['neckties'] = 'neckties',
    
    -- Торс
    ['cloaks'] = 'cloaks',
    ['vests'] = 'vests',
    ['shirts_full'] = 'shirts_full',
    ['holsters_knife'] = 'holsters_knife',
    ['loadouts'] = 'loadouts',
    ['suspenders'] = 'suspenders',
    ['gunbelts'] = 'gunbelts',
    ['belts'] = 'belts',
    ['holsters_left'] = 'holsters_left',
    ['holsters_right'] = 'holsters_right',
    ['coats'] = 'coats',
    ['coats_closed'] = 'coats_closed',
    ['ponchos'] = 'ponchos',
    ['dresses'] = 'dresses',
    
    -- Ноги
    ['pants'] = 'pants',
    ['chaps'] = 'chaps',
    ['skirts'] = 'skirts',
    
    -- Ноги (обувь)
    ['boots'] = 'boots',
    ['spats'] = 'spats',
    ['boot_accessories'] = 'boot_accessories',
    
    -- Руки
    ['jewelry_rings_right'] = 'jewelry_rings_right',
    ['jewelry_rings_left'] = 'jewelry_rings_left',
    ['jewelry_bracelets'] = 'jewelry_bracelets',
    ['gauntlets'] = 'gauntlets',
    ['gloves'] = 'gloves',
    
    -- Аксессуары
    ['talisman_wrist'] = 'talisman_wrist',
    ['talisman_holster'] = 'talisman_holster',
    ['belt_buckles'] = 'belt_buckles',
    ['holsters_crossdraw'] = 'holsters_crossdraw',
    ['aprons'] = 'aprons',
    ['bows'] = 'bows',
    ['hair_accessories'] = 'hair_accessories',
    
    -- Главные категории
    ['head'] = 'head',
    ['torso'] = 'torso',
    ['legs'] = 'legs',
    ['foot'] = 'foot',
    ['hands'] = 'hands',
    ['accessories'] = 'accessories',
}

function GetCategoryIcon(category)
    return CategoryIcons[category] or category
end

-- ==========================================
-- КОНФЛИКТУЮЩИЕ КАТЕГОРИИ ОДЕЖДЫ
-- ==========================================

local ConflictingCategories = {
    ['coats'] = 'coats_closed',
    ['coats_closed'] = 'coats',
    ['cloaks'] = 'ponchos',
    ['ponchos'] = 'cloaks',
}

-- Anti-clipping fix for outerwear from clothingstore:
-- 1) Нормализация вариации рубашки с учётом закатанных рукавов (не сбрасываем /sleeves при надевании пальто)
-- 2) Finalize + UpdatePedVariation
local function ApplyCoatAntiClipFix(ped, equippedCategory)
    if not ped or not DoesEntityExist(ped) then return end
    if equippedCategory ~= 'coats' and equippedCategory ~= 'coats_closed' then return end

    local shirtVar = joaat('BASE')
    if ClothesCache and ClothesCache['shirts_full'] and ClothesCache['shirts_full'].hash and ClothesCache['shirts_full'].hash ~= 0 then
        if ClothingModState and ClothingModState.sleeves_rolled_open then
            shirtVar = joaat(ClothingVariations and ClothingVariations.shirts and ClothingVariations.shirts.rolled_open or 'open_collar_rolled_sleeve')
        elseif ClothingModState and ClothingModState.sleeves_rolled then
            shirtVar = joaat(ClothingVariations and ClothingVariations.shirts and ClothingVariations.shirts.rolled_closed or 'Closed_Collar_Rolled_Sleeve')
        end
        Citizen.InvokeNative(0x66B957AAC2EAAEAB, ped, ClothesCache['shirts_full'].hash, shirtVar, 0, true, 1)
    end

    Citizen.InvokeNative(0x704C908E9C405136, ped)
    Citizen.InvokeNative(0xCC8CA3E88256E58F, ped, false, true, true, true, false)
end
exports('ApplyCoatAntiClipFix', ApplyCoatAntiClipFix)

local function IsClosedCoatVisualOverrideActive()
    return ClothesCache
        and ClothesCache['coats_closed']
        and type(ClothesCache['coats_closed']) == 'table'
        and ClothesCache['coats_closed'].hash
        and ClothesCache['coats_closed'].hash ~= 0
end

local function IsHiddenUnderClosedCoat(category)
    -- Ничего не скрываем — всё остаётся видимым под пальто
    return false
end
-- ==========================================
-- НАТИВНЫЕ ФУНКЦИИ
-- ==========================================

-- ★ NativeFixMeshIssues (hate_framework): фикс мешей/клиппинга при применении одежды
local function NativeFixMeshIssues(ped, categoryHash)
    if ped and DoesEntityExist(ped) and categoryHash then
        Citizen.InvokeNative(0x59BD177A1A48600A, ped, categoryHash)
    end
end

function NativeSetPedComponentEnabledClothes(ped, hash, immediately, isMp01, isPlayer)
    local catHash = Citizen.InvokeNative(0x5FF9A878C3D115B8, hash, not IsPedMale(ped), true) -- NativeGetPedComponentCategory
    NativeFixMeshIssues(ped, catHash)
    Citizen.InvokeNative(0x59BD177A1A48600A, ped, hash)
    -- ★ ИСПРАВЛЕНО: Всегда immediately=true, isMp=true, isMultiplayer=true
    Citizen.InvokeNative(0xD3A7B003ED343FD9, ped, hash, true, true, true)
    NativeFixMeshIssues(ped, catHash)

    -- ★ FIX: Ждём пока MetaPed компонент загрузится (увеличено для высокого пинга)
    -- 0xA0BC8FAED8CFEB3C = IsPedReadyToRender — ждём пока все MetaPed операции завершатся
    -- Было: 50 * 10мс = 500мс. Стало: 100 * 20мс = 2с
    local timeout = 0
    while not Citizen.InvokeNative(0xA0BC8FAED8CFEB3C, ped) and timeout < 100 do
        Wait(20)
        timeout = timeout + 1
    end

    -- Если не загрузилось за 2с — повторный Request+Apply
    if timeout >= 100 then
        print('[RSG-Clothing] Component streaming timeout (2s), retrying hash: ' .. tostring(hash))
        Citizen.InvokeNative(0x59BD177A1A48600A, ped, hash)
        Citizen.InvokeNative(0xD3A7B003ED343FD9, ped, hash, true, true, true)
        -- Повторное ожидание (ещё 2с)
        local timeout2 = 0
        while not Citizen.InvokeNative(0xA0BC8FAED8CFEB3C, ped) and timeout2 < 100 do
            Wait(20)
            timeout2 = timeout2 + 1
        end
    end
    -- ★ Как в hate_framework: UpdatePedVariation после каждого компонента (БЕЗ ReapplyBodyMorph — иначе просвечивает на полных)
    if NativeUpdatePedVariationClothes then NativeUpdatePedVariationClothes(ped) end
end

-- ★ Лёгкая версия: без ReapplyBodyMorph (как в hate_framework) — при equip одежды не ломает меш на полных персонажах
function NativeUpdatePedVariationClothes(ped)
    Citizen.InvokeNative(0x704C908E9C405136, ped)
    Citizen.InvokeNative(0xCC8CA3E88256E58F, ped, false, true, true, true, false)
    -- После "лёгкого" обновления вариации тоже могут слетать overlays (в т.ч. брови).
    -- Синхронизируем поведение с NativeUpdatePedVariation: переприменяем тату/оверлеи.
    if ped == PlayerPedId() then
        SetTimeout(120, function()
            TriggerEvent('shiw-tattoos:client:afterPedVariation')
            TriggerEvent('rsg-appearance:client:afterPedVariation')
        end)
    end
end

-- skipBodyMorph = true — не вызывать ReapplyBodyMorph (фикс вылезающей одежды на полных персонажах)
function NativeUpdatePedVariation(ped, skipBodyMorph)
    -- ★ ИСПРАВЛЕНО: Добавлен 0x704C908E9C405136 (_FINAL_PED_META_CHANGE_APPLY)
    -- Без этого вызова MetaPed компоненты одежды НЕ отображаются визуально!
    -- ★ ИСПРАВЛЕНО: Параметры 0xCC8CA3E88256E58F теперь boolean (не integer)
    Citizen.InvokeNative(0x704C908E9C405136, ped)
    Citizen.InvokeNative(0xCC8CA3E88256E58F, ped, false, true, true, true, false)
    if not skipBodyMorph and ReapplyBodyMorph then ReapplyBodyMorph(ped) end
    -- ★ Поводья: нативы выше сбрасывают текущее оружие педа; если это игрок и он в седле — возвращаем поводья в руки
    if ped == PlayerPedId() and IsPedOnMount(ped) then
        local reinsHash = joaat('WEAPON_REINS')
        if reinsHash and reinsHash ~= 0 then
            GiveWeaponToPed(ped, reinsHash, 0, false, true)
            SetCurrentPedWeapon(ped, reinsHash, true)
        end
    end
    -- ★ Тату: после каждого UpdatePedVariation оверлей сбрасывается; shiw-tattoos переприменяет с задержкой
    -- ★ Макияж: UpdatePedVariation сбрасывает overlays (shadows, blush, lipsticks, eyeliners) — переприменяем
    if ped == PlayerPedId() then
        SetTimeout(120, function()
            TriggerEvent('shiw-tattoos:client:afterPedVariation')
            TriggerEvent('rsg-appearance:client:afterPedVariation')
        end)
    end
end

-- ==========================================
-- НАТИВЫ ДЛЯ ЦВЕТА ОДЕЖДЫ v3.0
-- ==========================================

function SetTextureOutfitTints(ped, categoryHash, paletteHash, tint0, tint1, tint2)
    Citizen.InvokeNative(0x4EFC1F8FF1AD94DE, ped, categoryHash, paletteHash, tint0, tint1, tint2)
end

local function IsPedStyleItem(itemData)
    if type(itemData) ~= 'table' then return false end
    if itemData.kaf == 'Ped' or itemData._kaf == 'Ped' then return true end
    if itemData.draw and itemData.draw ~= '' and itemData.draw ~= '_' then return true end
    if itemData.albedo and itemData.albedo ~= '' and itemData.albedo ~= '_' then return true end
    if itemData.normal and itemData.normal ~= '' and itemData.normal ~= '_' then return true end
    if itemData.material and itemData.material ~= 0 and itemData.material ~= '' and itemData.material ~= '0' then return true end
    return false
end

local function IsPedCoatItem(category, itemData)
    return (category == 'coats' or category == 'coats_closed') and IsPedStyleItem(itemData)
end

function ApplyClothingColor(ped, category, palette, tints)
    if not category then return end
    
    -- Используем правильные хеши категорий
    local categoryHashes = {
    ['hats'] = 0x9925C067,
    ['shirts_full'] = 0x2026C46D,  -- ★ ОТЛИЧАЕТСЯ!
    ['shirts'] = 0x2026C46D,
    ['pants'] = 0x1D4C528A,        -- ★ ОТЛИЧАЕТСЯ!
    ['boots'] = 0x777EC6EF,
    ['vests'] = 0x485EE834,
    ['coats'] = 0xE06D30CE,        -- ★ ОТЛИЧАЕТСЯ!
    ['coats_closed'] = 0x662AC34,  -- ★ ОТЛИЧАЕТСЯ!
    ['gloves'] = 0xEABE0032,
    ['neckwear'] = 0x7A96FACA,     -- ★ ОТЛИЧАЕТСЯ!
    ['neckties'] = 0x7A96FACA,
    ['masks'] = 0x7505EF42,
    ['eyewear'] = 0x5F1BE9EC,      -- ★ ОТЛИЧАЕТСЯ!
    ['gunbelts'] = 0xF1542D11,     -- ★ ОТЛИЧАЕТСЯ!
    ['satchels'] = 0x94504D26,
    ['suspenders'] = 0x877A2CF7,
    ['chaps'] = 0x3107499B,
    ['spurs'] = 0x18729F39,
    ['cloaks'] = 0x3C1A74CD,
    ['ponchos'] = 0xAF14310B,
    ['skirts'] = 0xA0E3AB7F,
    ['belts'] = 0x9B2C8B89,
    ['belt_buckles'] = 0xDA0E2C55,
    ['dresses'] = 0x0662AC34,
    ['corsets'] = 0x485EE834,
    ['loadouts'] = 0x83887E88,
    ['gauntlets'] = 0x91CE9B20,
    ['holsters_left'] = 0x7A6BBD0B,
    ['holsters_right'] = 0x0B3966C9,
    ['accessories'] = 0x79D7DF96,
    ['badges'] = 0x79D7DF96,
    }
    
    local categoryHash = categoryHashes[category] or GetHashKey(category)
    
    -- Проверяем на дефолтную палитру
    local isDefaultPalette = (not palette or palette == 'tint_generic_clean' or palette == 'metaped_tint_generic_clean')
    local hasNonZeroTints = tints and (tints[1] > 0 or tints[2] > 0 or tints[3] > 0)
    -- Для большинства категорий не трогаем "чистую" палитру с нулевыми tint:
    -- у Classic-одежды цвет уже зашит в hash, лишний tint может давать неверный цвет (например, рубашки).
    if isDefaultPalette and not hasNonZeroTints then
        return
    end
    
    -- Если palette не задан, используем дефолт
    if not palette then
        palette = 'tint_generic_clean'
    end
    
    local paletteHash = GetHashKey(palette)
    
    -- Если palette не содержит metaped_, добавляем
    if not string.find(palette, 'metaped_') then
        paletteHash = GetHashKey('metaped_' .. palette)
    end
    
    local tint0 = tints and tints[1] or 0
    local tint1 = tints and tints[2] or 0
    local tint2 = tints and tints[3] or 0
    
    print('[RSG-Clothing] ApplyColor: cat=' .. category .. ' catHash=' .. tostring(categoryHash) .. ' palette=' .. palette)
    
    SetTextureOutfitTints(ped, categoryHash, paletteHash, tint0, tint1, tint2)
    Citizen.InvokeNative(0xAAB86462966168CE, ped, true)
    -- ★ Для shirts_full/vests/corsets — лёгкий UpdatePedVariation (0,1,1,1,false) как рукава/kaf_bulletproof.
    -- Полный UpdatePedVariation ломает меш окрашенной одежды на полных персонажах (просвечивает).
    if category == 'shirts_full' or category == 'vests' or category == 'corsets' then
        Citizen.InvokeNative(0x704C908E9C405136, ped)
        Citizen.InvokeNative(0xCC8CA3E88256E58F, ped, 0, 1, 1, 1, false)
    else
        NativeUpdatePedVariation(ped, false)
    end
    
    print('[RSG-Clothing] Applied color: tints=' .. tint0 .. ',' .. tint1 .. ',' .. tint2)
end


-- ==========================================
-- СТАРТОВАЯ ОДЕЖДА
-- ==========================================

local starterRequested = false
local isNewCharacter = false

RegisterNetEvent('rsg-clothing:client:applyStarterClothes', function(clothes)
    local ped = PlayerPedId()
    
    for _, item in ipairs(clothes) do
        if item.hash and item.hash ~= 0 then
            Citizen.InvokeNative(0x59BD177A1A48600A, ped, item.hash)
            Citizen.InvokeNative(0xD3A7B003ED343FD9, ped, item.hash, true, true, true)
            
            ClothesCache[item.category] = {
                hash = item.hash,
                model = item.model or 1,
                texture = item.texture or 1
            }
        end
        Wait(100)
    end
    
    Citizen.InvokeNative(0x704C908E9C405136, ped)
    Citizen.InvokeNative(0xCC8CA3E88256E58F, ped, false, true, true, true, false)
end)

RegisterNetEvent('rsg-appearance:client:finishedCreation', function()
    isNewCharacter = true
end)

RegisterNetEvent('rsg-spawn:client:spawned', function()
    Wait(2000)
    
    if isNewCharacter then
        isNewCharacter = false
        if not starterRequested then
            starterRequested = true
            TriggerServerEvent('rsg-clothing:server:giveStarterClothes')
        end
        return
    end
    
    -- ★ Не вызываем LoadClothingFromInventory для существующих персонажей!
    -- ApplySkin уже обрабатывает: SetPlayerModel → skin → ApplyClothes → delayed LoadClothingFromInventory.
    -- Параллельный вызов здесь создавал конфликт MetaPed и ломал снятие одежды.
    -- Но проверяем: если у персонажа НЕТ одежды вообще — даём стартовую.
    RSGCore.Functions.TriggerCallback('rsg-clothing:server:hasClothing', function(hasClothing)
        if not hasClothing and not starterRequested then
            starterRequested = true
            TriggerServerEvent('rsg-clothing:server:giveStarterClothes')
        else
            print('[RSG-Clothing] spawned: skipping LoadClothingFromInventory (handled by ApplySkin)')
        end
    end)
end)

RegisterNetEvent('RSGCore:Client:OnPlayerLoaded', function()
    Wait(3000)
    starterRequested = false
    isNewCharacter = false
    -- ★ НЕ вызываем LoadClothingFromInventory здесь!
    -- ApplySkin (RSGCore:Server:PlayerLoaded → 3s delay) уже делает:
    --   SetPlayerModel → skin → ApplyClothes → delayed LoadClothingFromInventory
    -- Параллельный вызов создавал конфликт MetaPed: одежда применялась к старому педу
    -- до SetPlayerModel, или перекрывала ApplyClothes → невозможно было снять.
    print('[RSG-Clothing] OnPlayerLoaded: skipping LoadClothingFromInventory (handled by ApplySkin)')
end)

RegisterCommand('requeststarter', function()
    starterRequested = false
    TriggerServerEvent('rsg-clothing:server:giveStarterClothes')
end, false)

-- ==========================================
-- ЗАГРУЗКА ОДЕЖДЫ ИЗ ИНВЕНТАРЯ
-- ==========================================

function LoadClothingFromInventory(callback)
    RSGCore.Functions.TriggerCallback('rsg-clothing:server:getEquippedClothing', function(equippedItems)
        local ped = PlayerPedId()
        
        -- ★ FIX: Снимаем дефолтную шляпу (кепка конфедерата) при заходе, если в инвентаре нет надетой шляпы
        if not equippedItems or not equippedItems['hats'] then
            Citizen.InvokeNative(0xDF631E4BCE1B1FC4, ped, 0x9925C067)
            Citizen.InvokeNative(0x704C908E9C405136, ped)
            Citizen.InvokeNative(0xCC8CA3E88256E58F, ped, false, true, true, true, false)
            if ClothesCache then ClothesCache['hats'] = nil end
        end
        
        if not equippedItems or not next(equippedItems) then
            if callback then callback(false) end
            return
        end
        
        local count = 0
        local isMale = IsPedMale(ped)
        local genderKey = isMale and 'male' or 'female'
        
        -- Сначала очищаем кэш и применяем все предметы в кэш
        ClothesCache = {}
        for category, data in pairs(equippedItems) do
            local hashToUse = nil
            
            -- ПРИОРИТЕТ 1: Используем hash напрямую если есть
            if data.hash and data.hash ~= 0 then
                hashToUse = data.hash
                print('[RSG-Clothing] LoadClothingFromInventory: ' .. category .. ' using direct hash=' .. tostring(hashToUse))
            
            -- ПРИОРИТЕТ 2: Получаем hash из clothing.lua по model/texture
            elseif data.model and data.model > 0 then
                local model = data.model
                local texture = data.texture or 1
                
                if clothing[genderKey] and clothing[genderKey][category] then
                    if clothing[genderKey][category][model] then
                        if clothing[genderKey][category][model][texture] then
                            hashToUse = clothing[genderKey][category][model][texture].hash
                            print('[RSG-Clothing] LoadClothingFromInventory: ' .. category .. ' got hash from clothing[' .. model .. '][' .. texture .. ']=' .. tostring(hashToUse))
                        elseif clothing[genderKey][category][model][1] then
                            hashToUse = clothing[genderKey][category][model][1].hash
                            print('[RSG-Clothing] LoadClothingFromInventory: ' .. category .. ' got hash from clothing[' .. model .. '][1]=' .. tostring(hashToUse))
                        end
                    end
                end
            end
            
            if hashToUse and hashToUse ~= 0 then
                ClothesCache[category] = {
                    hash = hashToUse,
                    model = data.model or 0,
                    texture = data.texture or 0,
                    palette = data.palette or 'tint_generic_clean',
                    tints = data.tints or {0, 0, 0},
                    kaf = data.kaf or data._kaf or "Classic",
                    _kaf = data._kaf or data.kaf or "Classic",
                    draw = data.draw or "",
                    albedo = data.albedo or "",
                    normal = data.normal or "",
                    material = data.material or 0,
                }
            else
                print('[RSG-Clothing] LoadClothingFromInventory: WARNING - no hash for ' .. category)
            end
        end
        
        -- Проверяем целостность тела ПЕРЕД надеванием одежды
        EnsureBodyIntegrity(ped, true)
        Wait(100)
        
        -- ★ ФИКС: Надеваем одежду В ПРАВИЛЬНОМ ПОРЯДКЕ с промежуточными Finalize+Update
        -- ★ С ПОДДЕРЖКОЙ PED-ТИПА: Ped-одежда применяется через draw/albedo/normal/material
        local lowerOrder = {'pants', 'skirts', 'dresses'}
        local upperOrder = {'shirts_full', 'vests', 'coats', 'coats_closed'}
        local lateOrder = {'boots', 'boot_accessories', 'spurs', 'chaps', 'spats'}
        local applied = {}
        local phaseCount = 0

        -- ★ FIX naked_body после /pee /poo: Убираем naked overlay ДО применения штанов (как в equipClothing)
        local hasLowerToApply = false
        for _, cat in ipairs(lowerOrder) do
            if ClothesCache[cat] and ClothesCache[cat].hash and ClothesCache[cat].hash ~= 0 then
                hasLowerToApply = true
                break
            end
        end
        if hasLowerToApply and RemoveNakedLowerBody then
            RemoveNakedLowerBody(ped, true)
            Wait(50)
        end

        -- ★ Функция применения одного предмета (Classic или Ped)
        local function ApplyItemOriginal(cat, itemData)
            if itemData.kaf == "Ped" and itemData.draw and itemData.draw ~= "" then
                if itemData.draw ~= "" and itemData.draw ~= "_" then
                    local drawHash = GetHashKey(itemData.draw)
                    Citizen.InvokeNative(0x59BD177A1A48600A, ped, drawHash)
                    Citizen.InvokeNative(0xD3A7B003ED343FD9, ped, drawHash, true, true, true)
                end
                if itemData.albedo and itemData.albedo ~= "" then
                    local albHash = GetHashKey(itemData.albedo)
                    Citizen.InvokeNative(0x59BD177A1A48600A, ped, albHash)
                    Citizen.InvokeNative(0xD3A7B003ED343FD9, ped, albHash, true, true, true)
                end
                if itemData.normal and itemData.normal ~= "" then
                    local normHash = GetHashKey(itemData.normal)
                    Citizen.InvokeNative(0x59BD177A1A48600A, ped, normHash)
                    Citizen.InvokeNative(0xD3A7B003ED343FD9, ped, normHash, true, true, true)
                end
                if itemData.material and itemData.material ~= 0 then
                    local matHash = itemData.material
                    if type(matHash) == "string" then matHash = GetHashKey(matHash) end
                    Citizen.InvokeNative(0x59BD177A1A48600A, ped, matHash)
                    Citizen.InvokeNative(0xD3A7B003ED343FD9, ped, matHash, true, true, true)
                end
            else
                NativeSetPedComponentEnabledClothes(ped, itemData.hash, false, true, true)
            end
        end
        
        -- Фаза 1: Нижнее тело (штаны, юбки, платья)
        phaseCount = 0
        for _, category in ipairs(lowerOrder) do
            if ClothesCache[category] and ClothesCache[category].hash and ClothesCache[category].hash ~= 0 then
                ApplyItemOriginal(category, ClothesCache[category])
                applied[category] = true
                count = count + 1
                phaseCount = phaseCount + 1
            end
        end
        -- ★ БЕЗ промежуточных UpdatePedVariation — одежда встаёт корректно, а каждый вызов сбрасывает bodymorph
        if phaseCount > 0 then
            Wait(200)
            print('[RSG-Clothing] Phase 1 (lower body): ' .. phaseCount .. ' items applied')
        end
        
        -- Фаза 2a: Рубашки (базовый верхний слой)
        if ClothesCache['shirts_full'] and ClothesCache['shirts_full'].hash and ClothesCache['shirts_full'].hash ~= 0 then
            ApplyItemOriginal('shirts_full', ClothesCache['shirts_full'])
            applied['shirts_full'] = true
            count = count + 1
            Wait(150)
            print('[RSG-Clothing] Phase 2a (shirts): applied')
        end

        -- Фаза 2b: Жилетки/корсеты (средний слой, один слот 0x485EE834)
        local cat = (ClothesCache['vests'] and ClothesCache['vests'].hash and ClothesCache['vests'].hash ~= 0) and 'vests'
            or (ClothesCache['corsets'] and ClothesCache['corsets'].hash and ClothesCache['corsets'].hash ~= 0) and 'corsets'
        if cat then
            ApplyItemOriginal(cat, ClothesCache[cat])
            applied[cat] = true
            count = count + 1
            Wait(150)
            print('[RSG-Clothing] Phase 2b (' .. cat .. '): applied')
        end

        -- Фаза 2c: Пальто (внешний слой)
        phaseCount = 0
        for _, cat in ipairs({'coats', 'coats_closed'}) do
            if ClothesCache[cat] and ClothesCache[cat].hash and ClothesCache[cat].hash ~= 0 then
                ApplyItemOriginal(cat, ClothesCache[cat])
                applied[cat] = true
                count = count + 1
                phaseCount = phaseCount + 1
            end
        end
        if phaseCount > 0 then
            Wait(150)
            if applied['coats_closed'] then
                ApplyCoatAntiClipFix(ped, 'coats_closed')
            elseif applied['coats'] then
                ApplyCoatAntiClipFix(ped, 'coats')
            end
            print('[RSG-Clothing] Phase 2c (coats): ' .. phaseCount .. ' items applied')
        end
        
        -- Фаза 3: Всё остальное (аксессуары, шляпы, перчатки и т.д.)
        phaseCount = 0
        for category, data in pairs(ClothesCache) do
            if not applied[category] and data.hash and data.hash ~= 0 then
                local isLate = false
                for _, lc in ipairs(lateOrder) do
                    if category == lc then isLate = true break end
                end
                if not isLate then
                    ApplyItemOriginal(category, data)
                    applied[category] = true
                    count = count + 1
                    phaseCount = phaseCount + 1
                end
            end
        end
        if phaseCount > 0 then
            Wait(200)
            print('[RSG-Clothing] Phase 3 (accessories): ' .. phaseCount .. ' items applied')
        end
        
        -- Фаза 4: Обувь и аксессуары ног В ПОСЛЕДНЮЮ ОЧЕРЕДЬ (поверх штанов)
        phaseCount = 0
        for _, category in ipairs(lateOrder) do
            if ClothesCache[category] and ClothesCache[category].hash and ClothesCache[category].hash ~= 0 and not applied[category] then
                ApplyItemOriginal(category, ClothesCache[category])
                applied[category] = true
                count = count + 1
                phaseCount = phaseCount + 1
            end
        end
        if phaseCount > 0 then
            Wait(200)
            -- ★ Женские персонажи: сразу снимаем naked lower после применения обуви — оверлей ног иначе просвечивает сквозь ботинки
            if not IsPedMale(ped) and applied['boots'] and RemoveNakedLowerBody then
                RemoveNakedLowerBody(ped, true)
                if NakedBodyState then NakedBodyState.lowerApplied = false end
                Wait(50)
            end
            print('[RSG-Clothing] Phase 4 (boots): ' .. phaseCount .. ' items applied')
        end
        
        -- ПРИМЕНЯЕМ ЦВЕТА!
        for category, data in pairs(ClothesCache) do
            if data.palette and data.tints then
                local isPedCoat = IsPedCoatItem(category, data)
                if isPedCoat or
                   data.palette ~= 'tint_generic_clean' or 
                   (data.tints[1] and data.tints[1] > 0) or 
                   (data.tints[2] and data.tints[2] > 0) or 
                   (data.tints[3] and data.tints[3] > 0) then
                    ApplyClothingColor(ped, category, data.palette, data.tints)
                    Wait(50)
                end
            end
        end
        
        -- Финальная проверка
        Wait(100)
        EnsureBodyIntegrity(ped, false)
        
        -- ★ Один раз UpdatePedVariation. skipBodyMorph=true — окрашенная рубашка на полных иначе просвечивает
        NativeUpdatePedVariation(ped, true)

        -- ★ NAKED BODY: Проверяем нужно ли голое тело
        Wait(100)
        -- ★ FIX LoadCharacter: явно применяем bodies при наличии одежды — стабилизация для первого снятия/надевания
        -- ★ НЕ применяем BODIES_LOWER при жен.+штаны/юбка/платье+обувь — ноги должны быть скрыты (naked_body уберёт меш)
        local hasLower = applied['pants'] or applied['skirts'] or applied['dresses']
        local hasUpper = applied['shirts_full'] or applied['vests'] or applied['coats'] or applied['coats_closed'] or applied['dresses']
        local skipBodiesLower = (not IsPedMale(ped)) and (applied['pants'] or applied['skirts'] or applied['dresses']) and (ClothesCache['boots'] and ClothesCache['boots'].hash and ClothesCache['boots'].hash ~= 0)
        if hasLower and not skipBodiesLower then
            local bh = GetBodyHash("BODIES_LOWER") or GetBodyHashNative(ped, "BODIES_LOWER") or GetBodyHashFromClothesList(ped, "BODIES_LOWER")
            if (not bh or bh == 0) then bh = GetBodyHashFromClothesList(ped, "BODIES_LOWER") end
            if bh and bh ~= 0 then
                Citizen.InvokeNative(0x59BD177A1A48600A, ped, GetHashKey("bodies_lower"))
                Citizen.InvokeNative(0xD3A7B003ED343FD9, ped, bh, true, true, true)
                Citizen.InvokeNative(0x704C908E9C405136, ped)
                Citizen.InvokeNative(0xCC8CA3E88256E58F, ped, false, true, true, true, false)
            end
        elseif skipBodiesLower then
            -- ★ Жен.+штаны/юбка/платье+обувь: сразу убираем меш ног, чтобы не просвечивали после reload
            Citizen.InvokeNative(0xD710A5007C2AC539, ped, BODIES_LOWER_CATEGORY, 0)
            Citizen.InvokeNative(0x704C908E9C405136, ped)
            Citizen.InvokeNative(0xCC8CA3E88256E58F, ped, false, true, true, true, false)
            if NakedBodyState then NakedBodyState.legsHiddenForSkirtBoots = true end
        end
        if hasUpper then
            local bh = GetBodyHash("BODIES_UPPER") or GetBodyHashNative(ped, "BODIES_UPPER") or GetBodyHashFromClothesList(ped, "BODIES_UPPER")
            if (not bh or bh == 0) then bh = GetBodyHashFromClothesList(ped, "BODIES_UPPER") end
            if bh and bh ~= 0 then
                Citizen.InvokeNative(0x59BD177A1A48600A, ped, GetHashKey("bodies_upper"))
                Citizen.InvokeNative(0xD3A7B003ED343FD9, ped, bh, true, true, true)
                Citizen.InvokeNative(0x704C908E9C405136, ped)
                Citizen.InvokeNative(0xCC8CA3E88256E58F, ped, false, true, true, true, false)
            end
        end
        if NakedBodyState then NakedBodyState.lastPedId = ped end
        -- ★ FIX LoadCharacter: штаны+сапоги — переприменяем сапоги поверх штанов (штаны заправляются в сапоги)
        if hasLower then
            local reapplyOverPants = {'boots', 'boot_accessories', 'spurs', 'chaps', 'spats', 'gunbelts', 'belts', 'satchels'}
            for _, cat in ipairs(reapplyOverPants) do
                if ClothesCache[cat] and ClothesCache[cat].hash and ClothesCache[cat].hash ~= 0 then
                    Citizen.InvokeNative(0x59BD177A1A48600A, ped, ClothesCache[cat].hash)
                    NativeSetPedComponentEnabledClothes(ped, ClothesCache[cat].hash, false, true, true)
                end
            end
            Citizen.InvokeNative(0x704C908E9C405136, ped)
            Citizen.InvokeNative(0xCC8CA3E88256E58F, ped, false, true, true, true, false)
            Wait(100)
            -- ★ Женские + обувь в кэше: снимаем naked lower после переприменения сапог (юбка+ботинки — ноги не просвечивают)
            if not IsPedMale(ped) and ClothesCache['boots'] and ClothesCache['boots'].hash and ClothesCache['boots'].hash ~= 0 and RemoveNakedLowerBody then
                RemoveNakedLowerBody(ped, true)
                if NakedBodyState then NakedBodyState.lowerApplied = false end
            end
        end
        -- ★ Проверка naked/ноги выполняется в rsg-appearance:client:ApplyClothesComplete в конце загрузки
        
        -- ★ FIX: Шляпа часто не прогружается после reload — переприменяем отдельно с задержкой.
        -- ПЕРЕД переприменением удаляем шляпу по категории, иначе получается две шляпы (stack).
        if ClothesCache['hats'] and ClothesCache['hats'].hash and ClothesCache['hats'].hash ~= 0 then
            Wait(250)
            ped = PlayerPedId()
            if DoesEntityExist(ped) then
                Citizen.InvokeNative(0xDF631E4BCE1B1FC4, ped, 0x9925C067)
                Wait(50)
                NativeSetPedComponentEnabledClothes(ped, ClothesCache['hats'].hash, true, true, true)
                Wait(150)
                NativeUpdatePedVariation(ped, true)
                if ApplyClothingColor and ClothesCache['hats'].palette and ClothesCache['hats'].tints then
                    ApplyClothingColor(ped, 'hats', ClothesCache['hats'].palette, ClothesCache['hats'].tints)
                end
            end
        end
        
        -- ★ Триггерим событие что одежда загружена
        TriggerEvent('rsg-clothing:client:clothingLoaded', ClothesCache)
        -- ★ Единая точка перезагрузки внешности (naked/ноги): тот же контракт, что после ApplyClothes
        TriggerEvent('rsg-appearance:client:ApplyClothesComplete', ped)
        
        if callback then callback(true, count) end
    end)
end

exports('LoadClothingFromInventory', LoadClothingFromInventory)

-- ==========================================
-- МОДИФИКАЦИЯ ОДЕЖДЫ (РУКАВА/ВОРОТНИК)
-- ==========================================

function GetCurrentShirtHash()
    local ped = PlayerPedId()
    if not ClothesCache['shirts_full'] then return nil end
    return ClothesCache['shirts_full'].hash
end

function ToggleSleeves()
    local ped = PlayerPedId()
    local isMale = IsPedMale(ped)
    local gender = isMale and "male" or "female"
    
    -- Проверяем надета ли рубашка
    if not ClothesCache['shirts_full'] or not ClothesCache['shirts_full'].model or ClothesCache['shirts_full'].model == 0 then
        TriggerEvent('ox_lib:notify', {
            title = 'Одежда',
            description = 'Сначала наденьте рубашку с длинными рукавами',
            type = 'error'
        })
        return
    end
    
    local currentModel = ClothesCache['shirts_full'].model
    local currentTexture = ClothesCache['shirts_full'].texture or 1
    
    -- Ищем вариацию с закатанными рукавами
    local clothingData = clothing[gender]['shirts_full']
    if not clothingData or not clothingData[currentModel] then
        TriggerEvent('ox_lib:notify', {
            title = 'Одежда',
            description = 'Эта рубашка не поддерживает закатывание рукавов',
            type = 'error'
        })
        return
    end
    
    -- Простая логика: четные модели - обычные, нечетные - закатанные
    local targetModel = currentModel
    if ClothingModifications.sleeves then
        -- Возвращаем обычные рукава
        if currentModel % 2 == 1 then
            targetModel = currentModel - 1
        end
        ClothingModifications.sleeves = false
    else
        -- Закатываем рукава
        if currentModel % 2 == 0 and clothingData[currentModel + 1] then
            targetModel = currentModel + 1
        else
            TriggerEvent('ox_lib:notify', {
                title = 'Одежда',
                description = 'Эта рубашка не поддерживает закатывание рукавов',
                type = 'error'
            })
            return
        end
        ClothingModifications.sleeves = true
    end
    
    -- Применяем изменения
    if clothingData[targetModel] and clothingData[targetModel][currentTexture] then
        local newHash = clothingData[targetModel][currentTexture].hash
        
        -- Сохраняем цвет перед сменой модели
        local savedPalette = ClothesCache['shirts_full'].palette
        local savedTints = ClothesCache['shirts_full'].tints
        
        -- Играем анимацию
        PlayClothingAnimation('sleeves')
        
        Wait(1000)
        
        -- Применяем новую модель
        NativeSetPedComponentEnabledClothes(ped, newHash, false, true, true)
        NativeUpdatePedVariation(ped, true)
        
        -- Обновляем кэш (сохраняем цвет!)
        ClothesCache['shirts_full'].model = targetModel
        ClothesCache['shirts_full'].hash = newHash
        ClothesCache['shirts_full'].palette = savedPalette
        ClothesCache['shirts_full'].tints = savedTints
        
        -- ПРИМЕНЯЕМ ЦВЕТ ЗАНОВО!
        if savedPalette and savedTints then
            Wait(100)
            ApplyClothingColor(ped, 'shirts_full', savedPalette, savedTints)
        end
        TriggerEvent('rsg-appearance:client:clothingVariationChanged')
        SetTimeout(650, function()
            TriggerEvent('rsg-appearance:client:clothingVariationSettled')
        end)
        
        TriggerEvent('ox_lib:notify', {
            title = 'Рукава',
            description = ClothingModifications.sleeves and 'Рукава закатаны' or 'Рукава опущены',
            type = 'success'
        })
    end
end

function ToggleCollar()
    local ped = PlayerPedId()
    local isMale = IsPedMale(ped)
    local gender = isMale and "male" or "female"
    
    -- Проверяем надета ли рубашка
    if not ClothesCache['shirts_full'] or not ClothesCache['shirts_full'].model or ClothesCache['shirts_full'].model == 0 then
        TriggerEvent('ox_lib:notify', {
            title = 'Одежда',
            description = 'Сначала наденьте рубашку',
            type = 'error'
        })
        return
    end
    
    local currentModel = ClothesCache['shirts_full'].model
    local currentTexture = ClothesCache['shirts_full'].texture or 1
    
    -- Ищем вариацию с расстегнутым воротником
    local clothingData = clothing[gender]['shirts_full']
    if not clothingData or not clothingData[currentModel] then
        TriggerEvent('ox_lib:notify', {
            title = 'Одежда',
            description = 'Эта рубашка не поддерживает расстегивание воротника',
            type = 'error'
        })
        return
    end
    
    -- Логика для воротника (настройте под ваши модели)
    -- Например: модели 1-10 застегнутые, 11-20 расстегнутые
    local targetModel = currentModel
    if ClothingModifications.collar then
        -- Застегиваем воротник
        if currentModel > 10 and currentModel <= 20 then
            targetModel = currentModel - 10
        end
        ClothingModifications.collar = false
    else
        -- Расстегиваем воротник
        if currentModel <= 10 and clothingData[currentModel + 10] then
            targetModel = currentModel + 10
        else
            TriggerEvent('ox_lib:notify', {
                title = 'Одежда',
                description = 'Эта рубашка не поддерживает расстегивание воротника',
                type = 'error'
            })
            return
        end
        ClothingModifications.collar = true
    end
    
    -- Применяем изменения
    if clothingData[targetModel] and clothingData[targetModel][currentTexture] then
        local newHash = clothingData[targetModel][currentTexture].hash
        
        -- Сохраняем цвет перед сменой модели
        local savedPalette = ClothesCache['shirts_full'].palette
        local savedTints = ClothesCache['shirts_full'].tints
        
        -- Играем анимацию
        PlayClothingAnimation('collar')
        
        Wait(800)
        
        -- Применяем новую модель
        NativeSetPedComponentEnabledClothes(ped, newHash, false, true, true)
        NativeUpdatePedVariation(ped, true)
        
        -- Обновляем кэш (сохраняем цвет!)
        ClothesCache['shirts_full'].model = targetModel
        ClothesCache['shirts_full'].hash = newHash
        ClothesCache['shirts_full'].palette = savedPalette
        ClothesCache['shirts_full'].tints = savedTints
        
        -- ПРИМЕНЯЕМ ЦВЕТ ЗАНОВО!
        if savedPalette and savedTints then
            Wait(100)
            ApplyClothingColor(ped, 'shirts_full', savedPalette, savedTints)
        end
        
        TriggerEvent('ox_lib:notify', {
            title = 'Воротник',
            description = ClothingModifications.collar and 'Воротник расстегнут' or 'Воротник застегнут',
            type = 'success'
        })
        SetTimeout(80, function()
            pcall(function() exports['shiw-tattoos']:ReapplyTattoo() end)
        end)
    end
end

function PlayClothingAnimation(type)
    local ped = PlayerPedId()
    local dict, anim
    
    if type == 'sleeves' then
        dict = 'script_common@mech@clothing@gloves'
        anim = 'put_on_gloves'
    elseif type == 'collar' then
        dict = 'mech_inventory@clothing@shirt'
        anim = 'collar_check'
    else
        return
    end
    
    RequestAnimDict(dict)
    local timeout = 0
    while not HasAnimDictLoaded(dict) and timeout < 100 do
        Wait(50)
        timeout = timeout + 1
    end
    
    if HasAnimDictLoaded(dict) then
        -- On mount/vehicle these anims can break rider pose; skip visual anim and keep clothing logic.
        if not IsPedOnMount(ped) and not IsPedInAnyVehicle(ped, false) then
            TaskPlayAnim(ped, dict, anim, 8.0, -8.0, -1, 51, 0, false, false, false)
        end
    end
end


-- ==========================================
-- ★ ИСПРАВЛЕННЫЙ ЭКИПИРОВКА/СНЯТИЕ v2.0
-- ★ NAKED BODY FIX: Исправлено мигание и появление/исчезновение
-- ==========================================

-- ★ Флаги для отслеживания naked body (синхронизация с naked_body.lua)
local NakedLowerApplied = false
local NakedUpperApplied = false

-- Функция сброса флагов naked body
local function ResetNakedFlags(category)
    if category == 'pants' or category == 'skirts' or category == 'dresses' then
        NakedLowerApplied = false
        print('[RSG-Clothing] Reset NakedLowerApplied flag')
    end
    if category == 'shirts_full' or category == 'dresses' or category == 'coats' or category == 'coats_closed' or category == 'vests' or category == 'corsets' then
        NakedUpperApplied = false
        print('[RSG-Clothing] Reset NakedUpperApplied flag')
    end
end

RegisterNetEvent('rsg-clothing:client:equipClothing', function(data, options)
    CreateThread(function()
        options = options or {}
        local ped = PlayerPedId()

        -- Проверка пола на СЕРВЕРЕ (sv_clothing.lua ToggleClothingItem) уже пройдена,
        -- клиентская проверка убрана — IsPedMale() и data.isMale имели несовместимые типы
        -- (0/1 vs true/false в Lua 5.4), вызывая ложные блокировки

        print('[RSG-Clothing] equipClothing: cat=' .. tostring(data.category) .. ' hash=' .. tostring(data.hash) .. ' kaf=' .. tostring(data.kaf))

        local kafEarly = data.kaf or data._kaf or "Classic"
        if kafEarly == "BodyComponent" then
            local bh = data.hash
            if type(bh) == "string" then bh = tonumber(bh, 16) end
            if bh and bh ~= 0 then
                Citizen.InvokeNative(0x1902C4CFCC5BE57C, ped, bh)
                Citizen.InvokeNative(0x704C908E9C405136, ped)
                Citizen.InvokeNative(0xCC8CA3E88256E58F, ped, false, true, true, true, false)
                if ReapplyBodyMorph then ReapplyBodyMorph(ped) end
                ClothesCache[data.category] = {
                    hash = bh, model = data.model or 0, texture = data.texture or 0,
                    palette = data.palette or 'tint_generic_clean', tints = data.tints or {0, 0, 0},
                    kaf = "BodyComponent", _kaf = "BodyComponent",
                }
                TriggerEvent('rsg-clothing:client:clothingLoaded', ClothesCache)
            end
            return
        end

        -- Сброс модификаций при смене рубашки
        if data.category == 'shirts_full' then
            ClothingModifications.sleeves = false
            ClothingModifications.collar = false
            if ResetClothingModState then ResetClothingModState('shirts_full') end
        end

        local hash = data.hash
        local isPedClothing = data.kaf == "Ped" and data.draw and data.draw ~= ""

        -- ★ Верхняя одежда: слоты, bodies_upper, ReapplyItem
        if data.category == 'shirts_full' or data.category == 'vests' or data.category == 'corsets' or 
           data.category == 'coats' or data.category == 'coats_closed' or data.category == 'dresses' then
            -- ★ Пальто: минимальный путь — только снять старое, без bodies_upper/ReapplyItem (вызывали просветы на спине)
            local isCoatOnly = (data.category == 'coats' or data.category == 'coats_closed')
            if isCoatOnly then
                if RemoveNakedUpperBody then RemoveNakedUpperBody(ped, true) end
                Wait(50)
                if data.category == 'coats' then
                    Citizen.InvokeNative(0xD710A5007C2AC539, ped, 0xE06D30CE, 0)
                    Citizen.InvokeNative(0xD710A5007C2AC539, ped, 0x0662AC34, 0)
                else
                    Citizen.InvokeNative(0xD710A5007C2AC539, ped, 0x0662AC34, 0)
                    Citizen.InvokeNative(0xD710A5007C2AC539, ped, 0xE06D30CE, 0)
                end
                Citizen.InvokeNative(0x704C908E9C405136, ped)
                Citizen.InvokeNative(0xCC8CA3E88256E58F, ped, false, true, true, true, false)
                Wait(50)
                -- ★ Переприменяем рубашку→жилет в правильном порядке ДО пальто — фикс просвечивания крашенного жилета
                if ClothesCache and ClothesCache['shirts_full'] and ClothesCache['shirts_full'].hash and ClothesCache['shirts_full'].hash ~= 0 then
                    NativeSetPedComponentEnabledClothes(ped, ClothesCache['shirts_full'].hash, false, true, true)
                    local shirtVar = 'BASE'
                    if ClothingModState and ClothingModState.sleeves_rolled_open then
                        shirtVar = (ClothingVariations and ClothingVariations.shirts and ClothingVariations.shirts.rolled_open) or 'open_collar_rolled_sleeve'
                    elseif ClothingModState and ClothingModState.sleeves_rolled then
                        shirtVar = (ClothingVariations and ClothingVariations.shirts and ClothingVariations.shirts.rolled_closed) or 'Closed_Collar_Rolled_Sleeve'
                    end
                    if SetPedComponentVariation then
                        SetPedComponentVariation(ped, ClothesCache['shirts_full'].hash, shirtVar)
                    end
                    Wait(80)
                end
                local vestItem = (ClothesCache and ClothesCache['vests'] and ClothesCache['vests'].hash and ClothesCache['vests'].hash ~= 0) and ClothesCache['vests']
                    or (ClothesCache and ClothesCache['corsets'] and ClothesCache['corsets'].hash and ClothesCache['corsets'].hash ~= 0) and ClothesCache['corsets']
                if vestItem then
                    NativeSetPedComponentEnabledClothes(ped, vestItem.hash, false, true, true)
                    Wait(80)
                end
            else
                -- Рубашка, жилет, корсет, платье — полный путь
                if (data.category == 'shirts_full' or data.category == 'coats' or data.category == 'coats_closed' or data.category == 'dresses')
                   and RemoveNakedUpperBody then
                    RemoveNakedUpperBody(ped, true)
                end
                Wait(50)
                if data.category == 'shirts_full' then
                    Citizen.InvokeNative(0xD710A5007C2AC539, ped, 0x2026C46D, 0)
                elseif data.category == 'vests' or data.category == 'corsets' then
                    Citizen.InvokeNative(0xD710A5007C2AC539, ped, 0x485EE834, 0)
                elseif data.category == 'coats' then
                    Citizen.InvokeNative(0xD710A5007C2AC539, ped, 0xE06D30CE, 0)
                elseif data.category == 'coats_closed' or data.category == 'dresses' then
                    Citizen.InvokeNative(0xD710A5007C2AC539, ped, 0x0662AC34, 0)
                    if data.category == 'dresses' then
                        Citizen.InvokeNative(0xD710A5007C2AC539, ped, 0x2026C46D, 0)
                        Citizen.InvokeNative(0xD710A5007C2AC539, ped, 0x485EE834, 0)
                    end
                end
                local bodyHash = GetBodyHash("BODIES_UPPER") or GetBodyHashNative(ped, "BODIES_UPPER") or GetBodyHashFromClothesList(ped, "BODIES_UPPER")
                if (not bodyHash or bodyHash == 0) then bodyHash = GetBodyHashFromClothesList(ped, "BODIES_UPPER") end
                if bodyHash and bodyHash ~= 0 then
                    Citizen.InvokeNative(0x59BD177A1A48600A, ped, GetHashKey("bodies_upper"))
                    Citizen.InvokeNative(0xD3A7B003ED343FD9, ped, bodyHash, true, true, true)
                end
                Citizen.InvokeNative(0x704C908E9C405136, ped)
                Citizen.InvokeNative(0xCC8CA3E88256E58F, ped, false, true, true, true, false)
                -- ★ ОТКЛЮЧЕНО: ReapplyItem('shirts_full') для vest/corset сбрасывал цвета
                Wait(100)
            end
        end

        -- ★ Убираем naked overlay (ноги) ДО применения штанов/юбки/платья
        if data.category == 'pants' or data.category == 'skirts' or data.category == 'dresses' then
            if RemoveNakedLowerBody then RemoveNakedLowerBody(ped, true) end
            Wait(50)
            Citizen.InvokeNative(0xD710A5007C2AC539, ped, 0x1D4C528A, 0)
            Citizen.InvokeNative(0xD710A5007C2AC539, ped, 0xA0E3AB7F, 0)
            Citizen.InvokeNative(0xD710A5007C2AC539, ped, 0x0662AC34, 0)
            Citizen.InvokeNative(0xD710A5007C2AC539, ped, 0x3107499B, 0)
            -- Снимаем сапоги и аксессуары ног — затем применим поверх штанов (штаны заправляются в сапоги)
            for _, compHash in ipairs({0x777EC6EF, 0x3107499B, 0x18729F39}) do -- boots, chaps, spurs
                Citizen.InvokeNative(0xD710A5007C2AC539, ped, compHash, 0)
            end
            Citizen.InvokeNative(0x704C908E9C405136, ped)
            Citizen.InvokeNative(0xCC8CA3E88256E58F, ped, false, true, true, true, false)
            Wait(80)
            -- ★ FIX LoadCharacter: GetBodyHashFromClothesList ПЕРВЫЙ — после naked native/export могут вернуть 0
            local bodyHash = GetBodyHashFromClothesList(ped, "BODIES_LOWER") or GetBodyHash("BODIES_LOWER") or GetBodyHashNative(ped, "BODIES_LOWER")
            if (not bodyHash or bodyHash == 0) then Wait(80) bodyHash = GetBodyHashFromClothesList(ped, "BODIES_LOWER") end
            if bodyHash and bodyHash ~= 0 then
                Citizen.InvokeNative(0xD710A5007C2AC539, ped, 0x823687F5, 0)
                Citizen.InvokeNative(0x59BD177A1A48600A, ped, GetHashKey("bodies_lower"))
                Citizen.InvokeNative(0xD3A7B003ED343FD9, ped, bodyHash, true, true, true)
            end
            Citizen.InvokeNative(0x704C908E9C405136, ped)
            Citizen.InvokeNative(0xCC8CA3E88256E58F, ped, false, true, true, true, false)
            Wait(100)
        end

        -- Сбрасываем флаги naked body (только флаги, без модификации педа!)
        if ResetNakedFlags then ResetNakedFlags(data.category) end

        -- ==========================================
        -- PED одежда (Draw/Albedo/Normal/Material)
        -- ==========================================
        if isPedClothing then
            -- Применяем Draw
            if data.draw and data.draw ~= "" and data.draw ~= "_" then
                local drawHash = GetHashKey(data.draw)
                Citizen.InvokeNative(0x59BD177A1A48600A, ped, drawHash)
                Citizen.InvokeNative(0xD3A7B003ED343FD9, ped, drawHash, true, true, true)
            end
            -- Применяем Albedo
            if data.albedo and data.albedo ~= "" then
                local albHash = GetHashKey(data.albedo)
                Citizen.InvokeNative(0x59BD177A1A48600A, ped, albHash)
                Citizen.InvokeNative(0xD3A7B003ED343FD9, ped, albHash, true, true, true)
            end
            -- Применяем Normal
            if data.normal and data.normal ~= "" then
                local normHash = GetHashKey(data.normal)
                Citizen.InvokeNative(0x59BD177A1A48600A, ped, normHash)
                Citizen.InvokeNative(0xD3A7B003ED343FD9, ped, normHash, true, true, true)
            end
            -- Применяем Material
            if data.material and data.material ~= 0 then
                local matHash = data.material
                if type(matHash) == "string" then matHash = GetHashKey(matHash) end
                Citizen.InvokeNative(0x59BD177A1A48600A, ped, matHash)
                Citizen.InvokeNative(0xD3A7B003ED343FD9, ped, matHash, true, true, true)
            end

            -- Финализация + обновление (один раз после всех компонентов)
            Citizen.InvokeNative(0x704C908E9C405136, ped)
            Citizen.InvokeNative(0xCC8CA3E88256E58F, ped, false, true, true, true, false)
            if ReapplyBodyMorph then ReapplyBodyMorph(ped) end
            Wait(100)

            -- Цвет
            if data.palette and data.palette ~= "" and data.palette ~= " " then
                local paletteHash = GetHashKey(data.palette)
                if not string.find(data.palette:lower(), 'metaped_') then
                    paletteHash = GetHashKey('metaped_' .. data.palette:lower())
                end
                local tintHash = GetTintCategoryHash(data.category)
                Citizen.InvokeNative(0x4EFC1F8FF1AD94DE, ped, tintHash, paletteHash,
                    data.tints and data.tints[1] or 0,
                    data.tints and data.tints[2] or 0,
                    data.tints and data.tints[3] or 0)
                Citizen.InvokeNative(0xAAB86462966168CE, ped, true)
                Citizen.InvokeNative(0x704C908E9C405136, ped)
                Citizen.InvokeNative(0xCC8CA3E88256E58F, ped, false, true, true, true, false)
            end

            -- Кэш
            ClothesCache[data.category] = {
                hash = hash, model = data.model or 0, texture = data.texture or 0,
                palette = data.palette or 'tint_generic_clean', tints = data.tints or {0, 0, 0},
                kaf = data.kaf, draw = data.draw, albedo = data.albedo,
                normal = data.normal, material = data.material,
            }
            if ReapplyBodyMorph then ReapplyBodyMorph(ped) end
            -- ★ PED пальто: UpdatePedVariation сбрасывает тинты рубашки — восстанавливаем
            if (data.category == 'coats' or data.category == 'coats_closed') and ApplyClothingColor then
                Wait(50)
                for _, cat in ipairs({'shirts_full', 'vests', 'corsets'}) do
                    if ClothesCache and ClothesCache[cat] and ClothesCache[cat].hash and ClothesCache[cat].hash ~= 0 then
                        local d = ClothesCache[cat]
                        if d.palette then
                            ApplyClothingColor(ped, cat, d.palette or 'tint_generic_clean', d.tints or {0, 0, 0})
                        end
                    end
                end
            end
            -- ★ PED штаны: отложенное переприменение + сапоги поверх
            if (data.category == 'pants' or data.category == 'skirts' or data.category == 'dresses') and data.draw and data.draw ~= "" then
                SetTimeout(350, function()
                    local p = PlayerPedId()
                    if DoesEntityExist(p) then
                        local drawHash = GetHashKey(data.draw)
                        Citizen.InvokeNative(0x59BD177A1A48600A, p, drawHash)
                        Citizen.InvokeNative(0xD3A7B003ED343FD9, p, drawHash, true, true, true)
                        Citizen.InvokeNative(0x704C908E9C405136, p)
                        if NativeUpdatePedVariation then NativeUpdatePedVariation(p, true) else Citizen.InvokeNative(0xCC8CA3E88256E58F, p, false, true, true, true, false) end
                        pcall(function() exports['rsg-appearance']:ReapplyBootsFromCache(p) end)
                    end
                end)
            end
            print('[RSG-Clothing] PED equipClothing completed')
            TriggerEvent('rsg-clothing:client:clothingLoaded', ClothesCache)
            if CheckAndApplyNakedBodyIfNeeded then
                SetTimeout(150, function()
                    CheckAndApplyNakedBodyIfNeeded(PlayerPedId(), ClothesCache)
                end)
            end
            return
        end

        -- ==========================================
        -- CLASSIC одежда (hash)
        -- ==========================================
        if (not hash or hash == 0) and data.model and data.model > 0 then
            hash = GetHashFromModel(data.category, data.model, data.texture or 1, data.isMale)
        end

        if hash and hash ~= 0 then
            -- ★ Шляпа: убираем старые висящие пропы перед надеванием (иначе модель может не отобразиться)
            if data.category == 'hats' then
                if ClearFloatingHatProp then ClearFloatingHatProp(ped, nil) end
                Citizen.InvokeNative(0x59BD177A1A48600A, ped, hash)
            end
            -- Конфликтующие категории (coats vs coats_closed и т.п.)
            if ConflictingCategories and ConflictingCategories[data.category] then
                local conflictCategory = ConflictingCategories[data.category]
                Citizen.InvokeNative(0xD710A5007C2AC539, ped, GetHashKey(conflictCategory), 0)
                ClothesCache[conflictCategory] = nil
            end

            -- ★ Украшения: перед применением очищаем слот, ждём, затем применяем
            local jewelryCompHash = {
                ['jewelry_rings_right'] = 0x7A6BBD0B, ['jewelry_rings_left'] = 0xF16A1D23,
                ['jewelry_bracelets'] = 0x7BC10759,
                ['rings_rh'] = 0x7A6BBD0B, ['rings_lh'] = 0xF16A1D23, ['bracelets'] = 0x7BC10759,
            }
            local compHash = jewelryCompHash[data.category]
            if compHash then
                Citizen.InvokeNative(0xD710A5007C2AC539, ped, GetHashKey(data.category), 0)
                Citizen.InvokeNative(0xD710A5007C2AC539, ped, compHash, 0)
                Citizen.InvokeNative(0x704C908E9C405136, ped)
                Citizen.InvokeNative(0xCC8CA3E88256E58F, ped, false, true, true, true, false)
                if NativeUpdatePedVariationClothes then NativeUpdatePedVariationClothes(ped) end
                Wait(150)
            end

            -- ★ Request для стриминга (штаны после bodies_lower могут не успеть прогрузиться)
            if data.category == 'pants' or data.category == 'skirts' or data.category == 'dresses' then
                Citizen.InvokeNative(0x59BD177A1A48600A, ped, hash)
                local t = 0
                while not Citizen.InvokeNative(0xA0BC8FAED8CFEB3C, ped) and t < 30 do Wait(20) t = t + 1 end
            end
            -- Применяем одежду: Request → Apply → Update (без ReapplyBodyMorph — как hate_framework)
            NativeSetPedComponentEnabledClothes(ped, hash, false, true, true)

            -- Цвет
            local palette = data.palette or 'tint_generic_clean'
            local tints = data.tints or {0, 0, 0}
            local isClassic = (data.kaf == "Classic" or data._kaf == "Classic")
            local hasZeroTints = (tints[1] == 0 and tints[2] == 0 and tints[3] == 0)
            local isPedCoatCategory = IsPedCoatItem(data.category, data)
            if isPedCoatCategory or not (isClassic and hasZeroTints) then
                Wait(100)
                ApplyClothingColor(ped, data.category, palette, tints)
            end

            -- Кэш (сохраняем ВСЕ поля включая kaf/draw для корректного снятия)
            ClothesCache[data.category] = {
                hash = hash, model = data.model or 0, texture = data.texture or 0,
                palette = data.palette or 'tint_generic_clean', tints = data.tints or {0, 0, 0},
                kaf = data.kaf or data._kaf or "Classic", _kaf = data._kaf or data.kaf or "Classic", draw = data.draw or "",
                albedo = data.albedo or "", normal = data.normal or "",
                material = data.material or 0,
            }

            -- После штанов: переприменяем сапоги поверх (штаны заправляются в сапоги)
            if data.category == "pants" or data.category == "skirts" or data.category == "dresses" then
                Wait(100)
                NativeSetPedComponentEnabledClothes(ped, hash, false, true, true)
                local reapplyAfterLower = {
                    'boots', 'boot_accessories', 'spurs', 'chaps', 'spats',
                    'gunbelts', 'belts', 'satchels'
                }
                for _, cat in ipairs(reapplyAfterLower) do
                    if ClothesCache[cat] and ClothesCache[cat].hash and ClothesCache[cat].hash ~= 0 then
                        NativeSetPedComponentEnabledClothes(ped, ClothesCache[cat].hash, false, true, true)
                    end
                end
            end

            -- ★ Женские + обувь: снимаем naked lower сразу после применения ботинок (ноги не просвечивают)
            if data.category == 'boots' and not IsPedMale(ped) and RemoveNakedLowerBody then
                Wait(80)
                RemoveNakedLowerBody(ped, true)
                if NakedBodyState then NakedBodyState.lowerApplied = false end
            end

            if data.category == 'coats' or data.category == 'coats_closed' then
                ApplyCoatAntiClipFix(ped, data.category)
                _G._CoatJustChanged = GetGameTimer()
                -- ★ ApplyCoatAntiClipFix/UpdatePedVariation сбрасывают тинты — восстанавливаем рубашку/жилет/корсет
                Wait(50)
                for _, cat in ipairs({'shirts_full', 'vests', 'corsets'}) do
                    if ClothesCache and ClothesCache[cat] and ClothesCache[cat].hash and ClothesCache[cat].hash ~= 0 then
                        local d = ClothesCache[cat]
                        if d.palette and ApplyClothingColor then
                            ApplyClothingColor(ped, cat, d.palette or 'tint_generic_clean', d.tints or {0, 0, 0})
                        end
                    end
                end
            end

            print('[RSG-Clothing] CLASSIC equipClothing completed: hash=' .. tostring(hash))
            TriggerEvent('rsg-clothing:client:clothingLoaded', ClothesCache)
            -- ★ Пальто: CheckAndApplyNakedBodyIfNeeded вызывал naked body через корсет
            if CheckAndApplyNakedBodyIfNeeded and data.category ~= 'coats' and data.category ~= 'coats_closed' then
                SetTimeout(150, function()
                    CheckAndApplyNakedBodyIfNeeded(PlayerPedId(), ClothesCache)
                end)
            end
        else
            print('[RSG-Clothing] ERROR: No hash for ' .. tostring(data.category))
        end

        -- Подстраховка от локального десинка:
        -- после события экипировки сверяемся с server equipped-состоянием.
        -- ★ skipResync: при loadcharacter одеваем через equip — не триггерим ресинк после каждого предмета
        -- ★ Пальто: ресинк вызывал мигание корсета (полная перезагрузка одежды)
        if not options.skipResync and EnableToggleInventoryResync and ScheduleClothingResyncFromInventory then
            if data.category ~= 'coats' and data.category ~= 'coats_closed' then
                ScheduleClothingResyncFromInventory('equip:' .. tostring(data.category))
            end
        end

        -- ★ ОТКЛЮЧЕНО: ReapplyAppearanceAfterClothing сбрасывал цвета
        -- ★ ОТКЛЮЧЕНО: requestModifierReapply после equip вызывал ApplyAllSavedColors и ломал одежду (naked body)
        -- Цвета уже применяются в equipClothing через ApplyClothingColor
        -- SetTimeout(500, function()
        --     TriggerEvent('rsg-appearance:client:requestModifierReapply')
        -- end)
    end)
end)

-- Функция получения hash из model
function GetHashFromModel(category, model, texture, isMale)
    if isMale == nil then
        isMale = IsPedMale(PlayerPedId())
    end
    
    local gender = isMale and 'male' or 'female'
    
    if clothing[gender] and clothing[gender][category] then
        local categoryData = clothing[gender][category]
        if categoryData[model] then
            local tex = texture or 1
            if categoryData[model][tex] and categoryData[model][tex].hash then
                return categoryData[model][tex].hash
            elseif categoryData[model][1] and categoryData[model][1].hash then
                return categoryData[model][1].hash
            end
        end
    end
    
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
        local idx = ((model - 1) * 10) + (texture or 1)
        if idx < 1 then idx = 1 end
        if idx > #items then idx = model end
        if idx > #items then idx = #items end
        return items[idx]
    end
    
    return 0
end

-- ★ Удаление "висящей" шляпы над головой (слетела/подлетела при снятии или от удара — игра создаёт проп)
local HAT_HEAD_RADIUS = 4.0   -- шляпа может подлететь на 3-4м при анимации
local HAT_HEAD_RADIUS_DAMAGE = 8.0  -- при ударе шляпа может улететь дальше
local HAT_Z_MAX = 5.0
local HAT_Z_MAX_DAMAGE = 10.0
local HAT_Z_MIN = 0.2 -- не трогаем шляпу в руке; 0.2м+ над головой — подлетевшая при первом снятии после релоада
-- ★ Не удаляем зонтики (shiw-parasol) — они прикреплены над головой
local PARASOL_MODEL_HASHES = {
    [joaat('p_parasol02x')] = true,
    [joaat('k_p_parasol02x_custom_01')] = true, [joaat('k_p_parasol02x_custom_02')] = true,
    [joaat('k_p_parasol02x_custom_03')] = true, [joaat('k_p_parasol02x_custom_04')] = true,
    [joaat('k_p_parasol02x_custom_05')] = true, [joaat('k_p_parasol02x_custom_06')] = true,
    [joaat('k_p_parasol02x_custom_07')] = true,
}

local HAT_ANIM_DICT = 'mech_loco_m@character@arthur@fidgets@hat@normal@unarmed@normal@left_hand'
local HAT_ANIM_NAME = 'hat_lhand_b'

local function IsInHatInteraction(ped)
    if not ped or not DoesEntityExist(ped) then return false end
    if IsEntityPlayingAnim(ped, HAT_ANIM_DICT, HAT_ANIM_NAME, 3) then
        return true
    end
    if IsPedUsingAnyScenario and IsPedUsingAnyScenario(ped) then
        return true
    end
    return false
end
-- ★ Удаляем ТОЛЬКО объекты с точным совпадением модели шляпы — не трогаем мировые пропы (tk_placeable и т.д.)
local function ClearFloatingHatProp(ped, hatModelHash, fromDamage)
    if not ped or not DoesEntityExist(ped) then return end
    if not hatModelHash or hatModelHash == 0 then return end
    if IsInHatInteraction(ped) then return end
    local headPos = GetEntityCoords(ped)
    local headPosHigh = vector3(headPos.x, headPos.y, headPos.z + 0.5)
    local radius = fromDamage and HAT_HEAD_RADIUS_DAMAGE or HAT_HEAD_RADIUS
    local zMax = fromDamage and HAT_Z_MAX_DAMAGE or HAT_Z_MAX
    local pool = GetGamePool and GetGamePool('CObject') or {}

    local weaponEntity = nil
    local _, wepHash = GetCurrentPedWeapon(ped, true, 0, true)
    if wepHash and wepHash ~= 0 and wepHash ~= GetHashKey("WEAPON_UNARMED") and wepHash ~= -1569615261 then
        local ei = GetCurrentPedWeaponEntityIndex and GetCurrentPedWeaponEntityIndex(ped, 0)
        if ei and ei ~= 0 and GetObjectIndexFromEntityIndex then
            weaponEntity = GetObjectIndexFromEntityIndex(ei)
        end
    end

    for _, obj in ipairs(pool) do
        if DoesEntityExist(obj) and obj ~= ped then
            if IsEntityAttachedToEntity(obj, ped) then
                goto next_obj
            end
            if weaponEntity and DoesEntityExist(weaponEntity) and obj == weaponEntity then
                goto next_obj
            end
            if PARASOL_MODEL_HASHES[GetEntityModel(obj)] then
                goto next_obj
            end
            if GetEntityModel(obj) ~= hatModelHash then goto next_obj end
            local objPos = GetEntityCoords(obj)
            local dist = #(headPosHigh - objPos)
            if dist > radius then goto next_obj end
            local zDelta = objPos.z - headPos.z
            if not (zDelta > HAT_Z_MIN and zDelta < zMax) then goto next_obj end
            DeleteEntity(obj)
            return
        end
        ::next_obj::
    end
end

local metaPedComponents = {
    ['hats'] = 0x9925C067,
    ['shirts_full'] = 0x2026C46D,
    ['pants'] = 0x1D4C528A,
    ['boots'] = 0x777EC6EF,
    ['vests'] = 0x485EE834,
    ['corsets'] = 0x485EE834,  -- тот же слот что vests
    ['coats'] = 0xE06D30CE,
    ['coats_closed'] = 0x662AC34,
    ['gloves'] = 0xEABE0032,
    ['neckwear'] = 0x7A96FACA,
    ['masks'] = 0x7505EF42,
    ['eyewear'] = 0x5F1BE9EC,
    ['gunbelts'] = 0xF1542D11,
    ['satchels'] = 0x94504D26,
    ['suspenders'] = 0x877A2CF7,
    ['chaps'] = 0x3107499B,
    ['spurs'] = 0x18729F39,
    ['cloaks'] = 0x3C1A74CD,
    ['ponchos'] = 0xAF14310B,
    ['skirts'] = 0xA0E3AB7F,
    ['belts'] = 0xA6D134C6,
    ['dresses'] = 0x0662AC34,
    -- Украшения и аксессуары (для снятия)
    ['accessories'] = 0x79D7DF96,
    ['talisman_belt'] = 0x1AECF7DC,
    ['rings_rh'] = 0x7A6BBD0B,
    ['rings_lh'] = 0xF16A1D23,
    ['bracelets'] = 0x7BC10759,
    ['jewelry_rings_right'] = 0x7A6BBD0B,
    ['jewelry_rings_left'] = 0xF16A1D23,
    ['jewelry_bracelets'] = 0x7BC10759,
}

local clothingResyncToken = 0
local activeInventoryResyncPasses = 0
local EnableToggleInventoryResync = false

ScheduleClothingResyncFromInventory = function(reason)
    clothingResyncToken = clothingResyncToken + 1
    local token = clothingResyncToken

    local function runResync(label)
        if token ~= clothingResyncToken then return end
        if LocalPlayer and LocalPlayer.state and LocalPlayer.state.isLoadingCharacter then return end
        -- ★ Не перезаписывать одежду когда игрок в магазине rsg-clothingstore (предпросмотр аксессуаров)
        if LocalPlayer.state.inClothingStore or LocalPlayer.state.isInClothingStore then return end

        activeInventoryResyncPasses = activeInventoryResyncPasses + 1
        LoadClothingFromInventory(function(success)
            activeInventoryResyncPasses = math.max(0, (activeInventoryResyncPasses or 1) - 1)
            if token ~= clothingResyncToken then return end

            -- Если сервер вернул "ничего не надето", принудительно снимаем локальные хвосты,
            -- чтобы не оставалась "фантомная" одежда только у себя.
            if not success then
                local ped = PlayerPedId()
                if not ped or not DoesEntityExist(ped) then return end

                ClothesCache = {}
                for cat, compHash in pairs(metaPedComponents) do
                    Citizen.InvokeNative(0xD710A5007C2AC539, ped, GetHashKey(cat), 0)
                    Citizen.InvokeNative(0xD710A5007C2AC539, ped, compHash, 0)
                end
                Citizen.InvokeNative(0x704C908E9C405136, ped)
                Citizen.InvokeNative(0xCC8CA3E88256E58F, ped, false, true, true, true, false)

                if EnsureBodyIntegrity then EnsureBodyIntegrity(ped, false) end
                if CheckAndApplyNakedBodyIfNeeded then
                    CheckAndApplyNakedBodyIfNeeded(ped, {})
                end
                if ReapplyBodyMorph then ReapplyBodyMorph(ped) end
            end

            if Config and Config.Debug then
                print(('[RSG-Clothing] Inventory resync pass (%s): %s success=%s'):format(
                    tostring(reason or 'unknown'), tostring(label), tostring(success)))
            end
        end)
    end

    -- Два прохода: быстрый и поздний (на случай сетевой/стриминговой задержки).
    SetTimeout(350, function() runResync('fast') end)
    SetTimeout(1200, function() runResync('late') end)
end

RegisterNetEvent('rsg-clothing:client:removeClothing', function(category)
    CreateThread(function()
    local ped = PlayerPedId()
    print('[RSG-Clothing] Removing category: ' .. category)

    -- Сброс модификаций рубашки
    if category == 'shirts_full' then
        ClothingModifications.sleeves = false
        ClothingModifications.collar = false
    end
    if ResetNakedFlags then ResetNakedFlags(category) end

    -- ★ Проверяем, был ли предмет типа "Ped" (raw overlay), пока кэш ещё жив
    local wasPedType = false
    local pedDrawHash = nil
    if ClothesCache[category] and ClothesCache[category].kaf == "Ped" and ClothesCache[category].draw then
        wasPedType = true
        pedDrawHash = GetHashKey(ClothesCache[category].draw)
    end

    -- ★ Для шляпы сохраняем hash модели до очистки кэша (чтобы удалить только этот проп)
    local savedHatHash = (category == 'hats' and ClothesCache[category] and ClothesCache[category].hash) or nil

    -- Удаляем из кэша
    ClothesCache[category] = nil

    -- ★ МЕТОД: Точечное удаление с фоллбэком
    -- Шаг 1: Пробуем точечное удаление (быстро, без переодевания)
    -- Шаг 2: Проверяем, снялся ли компонент визуально
    -- Шаг 3: Если нет — мини-перестройка слоёв (только затронутая группа)

    -- Шаг 1: Если это был Ped-тип (raw overlay) — очищаем overlay нулями
    if wasPedType and pedDrawHash then
        Citizen.InvokeNative(0xBC6DF00D7A4A6819, ped, pedDrawHash, 0, 0, 0, 0, 0, 0, 0)
    end

    -- Удаляем MetaPed компонент
    -- ★ Шляпы: RemoveShopItemFromPedByCategory — убирает по категории БЕЗ создания летящего пропа (RemoveTag его создаёт)
    if category == 'hats' then
        local hatsHash = metaPedComponents['hats'] or 0x9925C067
        Citizen.InvokeNative(0xDF631E4BCE1B1FC4, ped, hatsHash)
    else
        Citizen.InvokeNative(0xD710A5007C2AC539, ped, GetHashKey(category), 0)
        if metaPedComponents[category] then
            Citizen.InvokeNative(0xD710A5007C2AC539, ped, metaPedComponents[category], 0)
        end
    end

    -- Обработка конфликтующих категорий (coats/coats_closed, cloaks/ponchos)
    if ConflictingCategories and ConflictingCategories[category] then
        local conflictCategory = ConflictingCategories[category]
        Citizen.InvokeNative(0xD710A5007C2AC539, ped, GetHashKey(conflictCategory), 0)
        if metaPedComponents[conflictCategory] then
            Citizen.InvokeNative(0xD710A5007C2AC539, ped, metaPedComponents[conflictCategory], 0)
        end
    end

    -- Finalize + Update
    Citizen.InvokeNative(0x704C908E9C405136, ped)
    Citizen.InvokeNative(0xCC8CA3E88256E58F, ped, false, true, true, true, false)
    local t = 0
    while not Citizen.InvokeNative(0xA0BC8FAED8CFEB3C, ped) and t < 50 do Wait(10) t = t + 1 end
    Wait(100)

    -- ★ Снятие пальто: UpdatePedVariation сбрасывает тинты рубашки/жилета/корсета — восстанавливаем
    if (category == 'coats' or category == 'coats_closed') and ApplyClothingColor then
        Wait(50)
        for _, cat in ipairs({'shirts_full', 'vests', 'corsets'}) do
            if ClothesCache[cat] and ClothesCache[cat].hash and ClothesCache[cat].hash ~= 0 then
                local d = ClothesCache[cat]
                if d.palette then
                    ApplyClothingColor(ped, cat, d.palette or 'tint_generic_clean', d.tints or {0, 0, 0})
                end
            end
        end
    end

    -- ★ Шаг 2: Проверяем, снялся ли компонент визуально (0xFB4891BD7578CDC1)
    -- Для слоистых категорий (coats, vests и т.д.) RemoveTag может не снять визуальный меш
    -- после начальной загрузки через LoadClothingFromInventory
    local removalFailed = false
    if metaPedComponents[category] then
        local stillEquipped = Citizen.InvokeNative(0xFB4891BD7578CDC1, ped, metaPedComponents[category])
        if stillEquipped and stillEquipped ~= 0 then
            removalFailed = true
            print('[RSG-Clothing] Targeted removal failed for ' .. category .. ' (hash still present), using layer rebuild')
        end
    end

    -- ★ Шаг 3: Фоллбэк — мини-перестройка только когда целевое снятие не сработало.
    -- forceLayerRebuild для пальто ОТКЛЮЧЕН: перестройка снимала всё под пальто и переприменяла —
    -- при надевании пальто обратно слои просвечивали (рубашка/корсет через пальто).
    local forceLayerRebuild = false
    if removalFailed or forceLayerRebuild then
        -- Определяем группу слоёв для перестройки
        local layerGroup
        local upperGroup = {'shirts_full', 'vests', 'corsets', 'coats', 'coats_closed', 'cloaks', 'ponchos', 'suspenders'}
        local lowerGroup = {'pants', 'skirts', 'dresses', 'chaps'}

        local function isInGroup(cat, group)
            for _, g in ipairs(group) do if g == cat then return true end end
            return false
        end

        if isInGroup(category, upperGroup) then
            layerGroup = upperGroup
        elseif isInGroup(category, lowerGroup) then
            layerGroup = lowerGroup
        else
            -- Для аксессуаров (шляпы, перчатки и т.д.) — только сам предмет
            layerGroup = {category}
        end

        -- Снимаем все компоненты в группе
        for _, cat in ipairs(layerGroup) do
            if cat == 'hats' then
                Citizen.InvokeNative(0xDF631E4BCE1B1FC4, ped, metaPedComponents['hats'] or 0x9925C067)
            else
                Citizen.InvokeNative(0xD710A5007C2AC539, ped, GetHashKey(cat), 0)
                if metaPedComponents[cat] then
                    Citizen.InvokeNative(0xD710A5007C2AC539, ped, metaPedComponents[cat], 0)
                end
            end
        end
        Citizen.InvokeNative(0x704C908E9C405136, ped)
        Citizen.InvokeNative(0xCC8CA3E88256E58F, ped, false, true, true, true, false)
        t = 0
        while not Citizen.InvokeNative(0xA0BC8FAED8CFEB3C, ped) and t < 50 do Wait(10) t = t + 1 end
        Wait(50)

        -- ★ Vest/corset без рубашки: naked overlay ДО переприменения (корсет на голом теле, порядок слоёв)
        if (category == 'coats' or category == 'coats_closed') and not IsPedMale(ped) then
            local hasShirt = ClothesCache['shirts_full'] and ClothesCache['shirts_full'].hash and ClothesCache['shirts_full'].hash ~= 0
            local hasVest = ClothesCache['vests'] and ClothesCache['vests'].hash and ClothesCache['vests'].hash ~= 0
            local hasCorset = ClothesCache['corsets'] and ClothesCache['corsets'].hash and ClothesCache['corsets'].hash ~= 0
            if (hasVest or hasCorset) and not hasShirt and ApplyNakedUpperBody then
                ApplyNakedUpperBody(ped, true)
                Wait(50)
            end
        end

        -- Переприменяем оставшиеся предметы из кэша (кроме удалённой категории)
        local reapplied = 0
        for _, cat in ipairs(layerGroup) do
            if cat ~= category and ClothesCache[cat] and ClothesCache[cat].hash and ClothesCache[cat].hash ~= 0 then
                local itemData = ClothesCache[cat]
                if itemData.kaf == "Ped" and itemData.draw and itemData.draw ~= "" then
                    -- Ped-тип
                    if itemData.draw ~= "_" then
                        local drawHash = GetHashKey(itemData.draw)
                        Citizen.InvokeNative(0x59BD177A1A48600A, ped, drawHash)
                        Citizen.InvokeNative(0xD3A7B003ED343FD9, ped, drawHash, true, true, true)
                    end
                    if itemData.albedo and itemData.albedo ~= "" then
                        Citizen.InvokeNative(0x59BD177A1A48600A, ped, GetHashKey(itemData.albedo))
                        Citizen.InvokeNative(0xD3A7B003ED343FD9, ped, GetHashKey(itemData.albedo), true, true, true)
                    end
                else
                    -- Classic-тип
                    NativeSetPedComponentEnabledClothes(ped, itemData.hash, false, true, true)
                end
                reapplied = reapplied + 1
            end
        end

        if reapplied > 0 then
            NativeUpdatePedVariation(ped, true)
            Wait(50)
            -- Переприменяем цвета
            for _, cat in ipairs(layerGroup) do
                if ClothesCache[cat] and ClothesCache[cat].palette and ClothesCache[cat].tints then
                    local d = ClothesCache[cat]
                    local hasTints = d.tints[1] ~= 0 or d.tints[2] ~= 0 or d.tints[3] ~= 0
                    local isPedCoat = IsPedCoatItem(cat, d)
                    if isPedCoat or hasTints or d.palette ~= 'tint_generic_clean' then
                        ApplyClothingColor(ped, cat, d.palette, d.tints)
                    end
                end
            end
        end

        print('[RSG-Clothing] Layer rebuild complete: reapplied ' .. reapplied .. ' items')
        if category == 'coats' or category == 'coats_closed' then
            _G._CoatJustChanged = GetGameTimer()
        end
    end

    -- ★ Шляпа: после loadcharacter RemoveShopItemFromPedByCategory иногда создаёт летящий проп — чистим
    if category == 'hats' and savedHatHash and savedHatHash ~= 0 then
        CreateThread(function()
            for _, delay in ipairs({100, 400, 1000}) do
                Wait(delay)
                local p = PlayerPedId()
                if p and DoesEntityExist(p) and ClearFloatingHatProp then
                    ClearFloatingHatProp(p, savedHatHash, false)
                end
            end
        end)
    end

    -- ★ Naked body: если снята одежда нижней/верхней части тела и ничего не осталось
    if category == "pants" or category == "skirts" or category == "dresses" then
        local hasLower = false
        for _, cat in ipairs({'pants', 'skirts', 'dresses'}) do
            if ClothesCache[cat] and type(ClothesCache[cat]) == 'table' then
                if (ClothesCache[cat].hash and ClothesCache[cat].hash ~= 0) then hasLower = true break end
            end
        end
        if not hasLower then
            if ApplyNakedLowerBody then ApplyNakedLowerBody(ped) end
            Wait(150)
            -- Переприменяем сапоги поверх naked overlay
            pcall(function()
                exports['rsg-appearance']:ReapplyBootsFromCache(ped)
            end)
        end
    end
    if category == "shirts_full" or category == "dresses" or category == "coats" or category == "coats_closed" or category == "vests" or category == "corsets" then
        local isMale = IsPedMale(ped)
        if not isMale or isMale == false or isMale == 0 then
            -- ★ Рубашка/пальто/платье = не применять naked. Vest/corset без рубашки — naked нужен (корсет на голом теле)
            -- ★ FIX: При vest/corset НЕ применять naked — overlay рисовался поверх корсета и просвечивал
            local hasUpper = false
            for _, cat in ipairs({'shirts_full', 'dresses', 'coats', 'coats_closed'}) do
                if ClothesCache[cat] and type(ClothesCache[cat]) == 'table' then
                    if (ClothesCache[cat].hash and ClothesCache[cat].hash ~= 0) then hasUpper = true break end
                end
            end
            local hasVestOnly = false
            for _, cat in ipairs({'vests', 'corsets'}) do
                if ClothesCache[cat] and type(ClothesCache[cat]) == 'table' and ClothesCache[cat].hash and ClothesCache[cat].hash ~= 0 then
                    hasVestOnly = true break
                end
            end
            if not hasUpper and not hasVestOnly then
                if ApplyNakedUpperBody then ApplyNakedUpperBody(ped) end
            end
        end
    end

    EnsureBodyIntegrity(ped, false)
    -- ★ ОТКЛЮЧЕНО: ReapplyAppearanceAfterClothing сбрасывал цвета
    -- ★ Пальто: ресинк вызывал мигание корсета
    if EnableToggleInventoryResync and ScheduleClothingResyncFromInventory and category ~= 'coats' and category ~= 'coats_closed' then
        ScheduleClothingResyncFromInventory('remove:' .. tostring(category))
    end
    print('[RSG-Clothing] Category removed: ' .. category)
    end) -- end CreateThread
end)

-- ==========================================
-- АНИМАЦИЯ НАДЕВАНИЯ/СНЯТИЯ ОДЕЖДЫ
-- ==========================================

RegisterNetEvent('rsg-clothing:client:playClothingAnim')
AddEventHandler('rsg-clothing:client:playClothingAnim', function(category)
    CreateThread(function()
        local ped = PlayerPedId()
        local dict, anim
        if category == 'hats' then
            dict = 'mech_loco_m@character@arthur@fidgets@hat@normal@unarmed@normal@left_hand'
            anim = 'hat_lhand_b'
        else
            dict = 'mech_inventory@clothing@bandana'
            anim = 'neck_2_satchel'
        end
        
        RequestAnimDict(dict)
        local timeout = 0
        while not HasAnimDictLoaded(dict) and timeout < 100 do
            Wait(50)
            timeout = timeout + 1
        end
        
        if HasAnimDictLoaded(dict) then
            if not IsPedOnMount(ped) and not IsPedInAnyVehicle(ped, false) then
                TaskPlayAnim(ped, dict, anim, 4.0, -4.0, 2000, 51, 0, false, false, false)
            end
        end
    end)
end)

print('[RSG-Clothing] Fixed equip/remove handlers loaded (v2.0)')

-- ★ Очистка зависшей/подлетевшей шляпы (сбита в драке или при снятии — проп летает или висит)
-- Вызываем ВСЕГДА при надетой шляпе: hasHat может оставаться true, когда игра уже создала летящий проп
CreateThread(function()
    while true do
        Wait(800)
        local ped = PlayerPedId()
        if not ped or not DoesEntityExist(ped) then goto continue end
        if IsInHatInteraction(ped) then goto continue end
        if not ClothesCache or not ClothesCache['hats'] or not ClothesCache['hats'].hash then goto continue end
        if LocalPlayer.state.isLoadingCharacter then goto continue end
        local hatModelHash = ClothesCache['hats'].hash
        ClearFloatingHatProp(ped, hatModelHash, false)
        ::continue::
    end
end)

-- ★ При уроне — сразу ищем сбитую шляпу (игра создаёт проп, он может улететь далеко)
AddEventHandler('gameEventTriggered', function(name, args)
    if name ~= 'CEventNetworkEntityDamage' then return end
    local victim = args[1]
    if victim ~= PlayerPedId() or not DoesEntityExist(victim) then return end
    if not ClothesCache or not ClothesCache['hats'] or not ClothesCache['hats'].hash then return end

    local ped = PlayerPedId()
    if IsInHatInteraction(ped) then return end
    local hatModelHash = ClothesCache['hats'].hash
    for _, delay in ipairs({0, 150, 400, 800}) do
        SetTimeout(delay, function()
            local p = PlayerPedId()
            if DoesEntityExist(p) and ClothesCache and ClothesCache['hats'] then
                ClearFloatingHatProp(p, hatModelHash, true)
            end
        end)
    end
end)

-- ==========================================
-- ОСТАЛЬНОЙ КОД МАГАЗИНА
-- ==========================================

exports('IsCothingActive', function()
    return LocalPlayer.state.inClothingStore
end)

exports('GetClothesCache', function()
    return ClothesCache
end)

--- Перед цельным ricx-аутфитом: пустой ClothesCache + снять всю одежду с педа (без головы/причёски).
function PreparePedForRicxFullOutfit(ped)
    if not ped or not DoesEntityExist(ped) then ped = PlayerPedId() end
    if not DoesEntityExist(ped) then return end
    ClothesCache = {}
    if type(StripClothesOnly) == 'function' then
        StripClothesOnly(ped)
    end
end
exports('PreparePedForRicxFullOutfit', PreparePedForRicxFullOutfit)

-- ★ Восстановить меш нижней части тела (BODIES_LOWER) — после скрытия ног (жен.: штаны/юбка/платье+обувь)
local BODIES_LOWER_CATEGORY = 0x823687F5
-- MP верх торса/руки (clothes_list BODIES_UPPER)
local BODIES_UPPER_CATEGORY = 0x0B3966C9

function RestoreBodiesLower(ped)
    if not ped or not DoesEntityExist(ped) then return end
    local bodyHash = GetBodyHashFromClothesList(ped, "BODIES_LOWER") or GetBodyHash("BODIES_LOWER") or GetBodyHashNative(ped, "BODIES_LOWER")
    if not bodyHash or bodyHash == 0 then return end
    Citizen.InvokeNative(0x59BD177A1A48600A, ped, GetHashKey("bodies_lower"))
    Citizen.InvokeNative(0xD3A7B003ED343FD9, ped, bodyHash, true, true, true)
    Citizen.InvokeNative(0x704C908E9C405136, ped)
    Citizen.InvokeNative(0xCC8CA3E88256E58F, ped, false, true, true, true, false)
end
exports('RestoreBodiesLower', RestoreBodiesLower)

function RestoreBodiesUpper(ped)
    if not ped or not DoesEntityExist(ped) then return end
    local bodyHash = GetBodyHashFromClothesList(ped, "BODIES_UPPER") or GetBodyHash("BODIES_UPPER") or GetBodyHashNative(ped, "BODIES_UPPER")
    if not bodyHash or bodyHash == 0 then return end
    Citizen.InvokeNative(0x59BD177A1A48600A, ped, GetHashKey("bodies_upper"))
    Citizen.InvokeNative(0xD3A7B003ED343FD9, ped, bodyHash, true, true, true)
    Citizen.InvokeNative(0x704C908E9C405136, ped)
    Citizen.InvokeNative(0xCC8CA3E88256E58F, ped, false, true, true, true, false)
end
exports('RestoreBodiesUpper', RestoreBodiesUpper)

local function _PedVariationRefresh(ped)
    Citizen.InvokeNative(0x704C908E9C405136, ped)
    Citizen.InvokeNative(0xCC8CA3E88256E58F, ped, false, true, true, true, false)
end

local GLOVES_CATEGORY_HASH = 0xEABE0032

-- MP «голые руки» после снятия BODIES_UPPER (tint 1–6 ≈ skin_tone из clothes_list)
local BARE_HAND_GLOVES_MALE = {
    0x2C6BA43B, 0x88265BAF, 0x082ADBB6, 0x1A4A7FF5, 0xE5181591, 0xF5C6B6EE,
}
local BARE_HAND_GLOVES_FEMALE = {
    0x232BB82B, 0xDB37A860, 0xE9D8C5A2, 0xBF9DF12D, 0xCE640EB9, 0xA4123A16,
}

local function _RicxSkinToneForBareHands()
    if type(GetSkinTone) == 'function' then
        local t = tonumber(GetSkinTone())
        if t then return math.max(1, math.min(t, 6)) end
    end
    if type(CurrentSkinData) == 'table' and CurrentSkinData.skin_tone then
        local t = tonumber(CurrentSkinData.skin_tone)
        if t then return math.max(1, math.min(t, 6)) end
    end
    if type(CreatorCache) == 'table' and CreatorCache.skin_tone then
        local t = tonumber(CreatorCache.skin_tone)
        if t then return math.max(1, math.min(t, 6)) end
    end
    if type(LoadedComponents) == 'table' and LoadedComponents.skin_tone then
        local t = tonumber(LoadedComponents.skin_tone)
        if t then return math.max(1, math.min(t, 6)) end
    end
    return 1
end

local function _BareHandGloveHashForPed(ped)
    local tone = _RicxSkinToneForBareHands()
    if IsPedMale(ped) then
        return BARE_HAND_GLOVES_MALE[tone] or BARE_HAND_GLOVES_MALE[1]
    end
    return BARE_HAND_GLOVES_FEMALE[tone] or BARE_HAND_GLOVES_FEMALE[1]
end

local function _OutfitHasGlovesInCache()
    local g = ClothesCache and ClothesCache['gloves']
    return g and g.hash and tonumber(g.hash) and tonumber(g.hash) ~= 0
end

local function ApplyBareHandsGloveOverlayAfterUpperHide(ped)
    if not ped or not DoesEntityExist(ped) then return end
    if _OutfitHasGlovesInCache() then return end
    Citizen.InvokeNative(0xD710A5007C2AC539, ped, GLOVES_CATEGORY_HASH, 0)
    Citizen.InvokeNative(0x704C908E9C405136, ped)
    Citizen.InvokeNative(0xCC8CA3E88256E58F, ped, false, true, true, true, false)
    Wait(20)
    local h = _BareHandGloveHashForPed(ped)
    NativeSetPedComponentEnabledClothes(ped, h, false, true, true)
    -- Подтянуть оттенок под skin_tone (иначе на HS часто «белые перчатки» при неверном тоне в LoadedComponents)
    local tone = _RicxSkinToneForBareHands()
    if ApplyClothingColor then
        ApplyClothingColor(ped, 'gloves', 'tint_generic_clean', { tone, 0, 0 })
    end
end

local function RestoreGlovesSlotFromCacheAfterRicx(ped)
    if not ped or not DoesEntityExist(ped) then return end
    Citizen.InvokeNative(0xD710A5007C2AC539, ped, GLOVES_CATEGORY_HASH, 0)
    _PedVariationRefresh(ped)
    local g = ClothesCache and ClothesCache['gloves']
    if g and g.hash and tonumber(g.hash) and tonumber(g.hash) ~= 0 then
        NativeSetPedComponentEnabledClothes(ped, g.hash, false, true, true)
        if g.palette and ApplyClothingColor then
            ApplyClothingColor(ped, 'gloves', g.palette or 'tint_generic_clean', g.tints or { 0, 0, 0 })
        end
    end
    _PedVariationRefresh(ped)
end

--- Снять MP-меш ног (аналог логики юбка+сапоги в naked_body) — кожа не просвечивает сквозь штаны/обувь
function HideBodiesLowerMesh(ped)
    if not ped or not DoesEntityExist(ped) then return end
    Citizen.InvokeNative(0xD710A5007C2AC539, ped, BODIES_LOWER_CATEGORY, 0)
    _PedVariationRefresh(ped)
end
exports('HideBodiesLowerMesh', HideBodiesLowerMesh)

--- Снять MP-меш верха/рук — кожа не просвечивает сквозь рукава (формы ricx и т.п.)
function HideBodiesUpperMesh(ped)
    if not ped or not DoesEntityExist(ped) then return end
    Citizen.InvokeNative(0xD710A5007C2AC539, ped, BODIES_UPPER_CATEGORY, 0)
    _PedVariationRefresh(ped)
end
exports('HideBodiesUpperMesh', HideBodiesUpperMesh)

local function RicxCustomIdInList(id, list)
    if type(id) ~= 'string' or id == '' or type(list) ~= 'table' then return false end
    id = (id:match('^%s*(.-)%s*$') or id):lower()
    for _, v in ipairs(list) do
        if type(v) == 'string' and v:lower() == id then return true end
    end
    return false
end

local function RicxActiveOutfitHidesUpperBody(cfg)
    return RicxCustomIdInList(_G._RicxActiveOutfitCustomId, cfg.ricxHideUpperBodyCustomIds)
end

local function RicxActiveOutfitUsesBareHandsOverlay(cfg)
    return RicxCustomIdInList(_G._RicxActiveOutfitCustomId, cfg.ricxBareHandsAfterUpperHideCustomIds)
end

function ApplyRicxOutfitBodyMeshHide(ped)
    if not ped or not DoesEntityExist(ped) then ped = PlayerPedId() end
    if not DoesEntityExist(ped) then return end
    local cfg = RSG.RicxOutfitHideBodyMesh
    if not cfg or cfg.enabled ~= true then return end
    _G._RicxDidApplyUpperBodyHide = false
    _G._RicxAppliedBareHandsRicxHide = false
    if cfg.hideLower then
        HideBodiesLowerMesh(ped)
    end
    if cfg.hideUpper and RicxActiveOutfitHidesUpperBody(cfg) then
        Wait(40)
        HideBodiesUpperMesh(ped)
        _G._RicxDidApplyUpperBodyHide = true
        if RicxActiveOutfitUsesBareHandsOverlay(cfg) then
            Wait(35)
            ApplyBareHandsGloveOverlayAfterUpperHide(ped)
            _G._RicxAppliedBareHandsRicxHide = true
            _PedVariationRefresh(ped)
        end
    end
end
exports('ApplyRicxOutfitBodyMeshHide', ApplyRicxOutfitBodyMeshHide)

function RestoreRicxOutfitBodyMesh(ped)
    if not ped or not DoesEntityExist(ped) then ped = PlayerPedId() end
    if not DoesEntityExist(ped) then return end
    local cfg = RSG.RicxOutfitHideBodyMesh
    if not cfg or cfg.enabled ~= true then return end
    if cfg.hideLower then RestoreBodiesLower(ped) end
    if cfg.hideUpper and _G._RicxDidApplyUpperBodyHide then
        if _G._RicxAppliedBareHandsRicxHide then
            Citizen.InvokeNative(0xD710A5007C2AC539, ped, GLOVES_CATEGORY_HASH, 0)
            _PedVariationRefresh(ped)
            Wait(20)
        end
        RestoreBodiesUpper(ped)
        if _G._RicxAppliedBareHandsRicxHide then
            Wait(25)
            RestoreGlovesSlotFromCacheAfterRicx(ped)
        end
        _G._RicxDidApplyUpperBodyHide = false
        _G._RicxAppliedBareHandsRicxHide = false
    end
end
exports('RestoreRicxOutfitBodyMesh', RestoreRicxOutfitBodyMesh)

RegisterNetEvent('rsg-appearance:client:applyRicxBodyMeshHide', function()
    local ped = PlayerPedId()
    if DoesEntityExist(ped) and _G._RicxOutfitActive then
        ApplyRicxOutfitBodyMeshHide(ped)
    end
end)

CreateThread(function()
    for _,v in pairs(RSG.SetDoorState) do
        Citizen.InvokeNative(0xD99229FE93B46286, v.door, 1, 1, 0, 0, 0, 0)
        DoorSystemSetDoorState(v.door, v.state)
    end
end)

function GetDescriptionLayout(value, price)
    local desc = image:format(value.img) .. "<br><br>" .. value.desc .. "<br><br>" .. Divider ..
        "<br><span style='font-family:crock; float:left; font-size: 22px;'>" ..
        RSG.Label.total .. " </span><span style='font-family:crock;float:right; font-size: 22px;'>$" ..
        (price or CurrentPrice) .. "</span><br>" .. Divider
    return desc
end

function deepcopy(orig)
    local orig_type = type(orig)
    local copy
    if orig_type == 'table' then
        copy = {}
        for orig_key, orig_value in next, orig, nil do
            copy[deepcopy(orig_key)] = deepcopy(orig_value)
        end
        setmetatable(copy, deepcopy(getmetatable(orig)))
    else
        copy = orig
    end
    return copy
end

function GetPurchasedItems(newCache, oldCache, isMale)
    local purchasedItems = {}
    local gender = isMale and "male" or "female"
    
    if not newCache then return purchasedItems end
    if not oldCache then oldCache = {} end
    
    for category, newData in pairs(newCache) do
        if type(newData) ~= "table" then goto continue end
        
        local newModel = newData.model
        local newTexture = newData.texture or 1
        
        if not newModel or newModel < 1 then goto continue end
        
        local oldData = oldCache[category]
        local isNew = false
        
        if not oldData or type(oldData) ~= "table" then
            isNew = true
        elseif not oldData.model or oldData.model < 1 then
            isNew = true
        elseif newModel ~= oldData.model then
            isNew = true
        elseif newTexture ~= (oldData.texture or 1) then
            isNew = true
        end
        
        if isNew then
            local hash = nil
            
            if newData.hash and newData.hash ~= 0 then
                hash = newData.hash
            elseif clothing[gender] and clothing[gender][category] then
                if clothing[gender][category][newModel] and clothing[gender][category][newModel][newTexture] then
                    hash = clothing[gender][category][newModel][newTexture].hash
                end
            end
            
            if hash and hash ~= 0 then
                table.insert(purchasedItems, {
                    category = category,
                    hash = hash,
                    model = newModel,
                    texture = newTexture,
                    isMale = isMale
                })
            end
        end
        
        ::continue::
    end
    
    return purchasedItems
end

-- ==========================================
-- МЕНЮ МАГАЗИНА (ИСПРАВЛЕННОЕ)
-- ==========================================

function OpenClothingMenu()
    MenuData.CloseAll()
    local elements = {}

    for categoryKey, categoryData in pairsByKeys(RSG.MenuElements) do
        local iconName = GetCategoryIcon(categoryKey)
        elements[#elements + 1] = {
            label = categoryData.label or categoryKey,
            value = categoryKey,
            category = categoryKey,
            desc = image:format(iconName) .. "<br><br>" .. Divider .. "<br> " .. locale('clothing_menu.category_desc'),
        }
    end
    
    if not (IsInCharCreation or Skinkosong) then
        local descLayout = GetDescriptionLayout(
            { img = "menu_icon_tick", desc = locale('clothing_menu.confirm_purhcase') },
            CurrentPrice
        )
        elements[#elements + 1] = {
            label = RSG.Label.save or "Save",
            value = "save",
            desc = descLayout
        }
    end
    
    MenuData.Open('default', GetCurrentResourceName(), 'clothing_store_menu',
        {
            title = RSG.Label.clothes,
            subtext = RSG.Label.shop .. ' - $' .. CurrentPrice,
            align = 'top-left',
            elements = elements,
            itemHeight = "4vh"
        },
        function(data, menu)
            if data.current.value ~= "save" then
                OpenSubcategoryMenu(data.current.value)
            else
                if CurrentPrice > 0 then
                    RSGCore.Functions.TriggerCallback('rsg-clothing:server:purchaseClothing', function(success)
                        if success then
                            menu.close()
                            destory()
                            
                            local ClothesHash = ConvertCacheToHash(ClothesCache)
                            local isMale = IsPedMale(PlayerPedId())
                            local purchasedItems = GetPurchasedItems(ClothesCache, OldClothesCache, isMale)
                            
                            if purchasedItems and #purchasedItems > 0 then
                                for _, item in ipairs(purchasedItems) do
                                    TriggerServerEvent('rsg-clothing:server:saveToInventory', item)
                                    Wait(100)
                                end
                            end
                            
                            TriggerServerEvent("rsg-appearance:server:saveOutfit", ClothesHash, isMale)
                            Wait(500)
                            TriggerServerEvent('rsg-clothing:server:equipAfterPurchase')
                            
                            if next(CurentCoords) == nil then
                                CurentCoords = RSG.Zones1[1]
                            end
                            TeleportAndFade(CurentCoords.quitcoords, true)
                            Wait(1000)
                            ExecuteCommand('loadskin')
                            
                            TriggerEvent('ox_lib:notify', {
                                title = 'Магазин одежды',
                                description = 'Покупка завершена! Списано: $' .. CurrentPrice,
                                type = 'success'
                            })
                        else
                            TriggerEvent('ox_lib:notify', {
                                title = 'Магазин одежды',
                                description = 'Недостаточно денег! Нужно: $' .. CurrentPrice,
                                type = 'error'
                            })
                        end
                    end, CurrentPrice)
                else
                    menu.close()
                    destory()
                    if next(CurentCoords) == nil then
                        CurentCoords = RSG.Zones1[1]
                    end
                    TeleportAndFade(CurentCoords.quitcoords, true)
                    Wait(1000)
                    ExecuteCommand('loadskin')
                end
            end
        end,
        function(data, menu)
            if (IsInCharCreation or Skinkosong) then
                menu.close()
                FirstMenu()
            else
                menu.close()
                destory()
                if next(CurentCoords) == nil then
                    CurentCoords = RSG.Zones1[1]
                end
                TeleportAndFade(CurentCoords.quitcoords, true)
                Wait(1000)
                ExecuteCommand('loadskin')
            end
        end)
end

-- НОВАЯ ФУНКЦИЯ: Меню подкатегорий (hats, eyewear, masks и т.д.)
function OpenSubcategoryMenu(mainCategory)
    MenuData.CloseAll()
    local elements = {}
    
    local categoryData = RSG.MenuElements[mainCategory]
    if not categoryData or not categoryData.category then
        OpenClothingMenu()
        return
    end
    
    -- Создаем список подкатегорий
    for _, subcategory in ipairs(categoryData.category) do
        local isMale = IsPedMale(PlayerPedId())
        local gender = isMale and "male" or "female"
        
        -- Проверяем есть ли одежда этой категории
        if clothing[gender] and clothing[gender][subcategory] then
            local iconName = GetCategoryIcon(subcategory)
            elements[#elements + 1] = {
                label = RSG.Label[subcategory] or subcategory,
                value = subcategory,
                category = subcategory,
                desc = image:format(iconName) .. "<br><br>" .. Divider
            }
        end
    end
    
    if #elements == 0 then
        OpenClothingMenu()
        return
    end
    
    MenuData.Open('default', GetCurrentResourceName(), 'clothing_subcategory_menu',
        {
            title = categoryData.label or mainCategory,
            subtext = RSG.Label.options,
            align = 'top-left',
            elements = elements,
            itemHeight = "4vh"
        },
        function(data, menu)
            OpenItemMenu(data.current.category)
        end,
        function(data, menu)
            menu.close()
            OpenClothingMenu()
        end)
end

-- НОВАЯ ФУНКЦИЯ: Меню конкретного предмета (слайдеры модели и текстуры)
function OpenItemMenu(category)
    MenuData.CloseAll()
    local elements = {}
    local isMale = IsPedMale(PlayerPedId())
    local gender = isMale and "male" or "female"
    
    if not clothing[gender] or not clothing[gender][category] then
        OpenClothingMenu()
        return
    end
    
    local categoryClothing = clothing[gender][category]
    
    -- Инициализируем кэш если нужно
    if ClothesCache[category] == nil or type(ClothesCache[category]) ~= "table" then
        ClothesCache[category] = {}
        ClothesCache[category].model = 0
        ClothesCache[category].texture = 1
    end
    
    local price = RSG.Price[category] or 5
    local iconName = GetCategoryIcon(category)
    
    -- ✅ Проверяем изменились ли модель ИЛИ текстура
    local oldModel = OldClothesCache[category] and OldClothesCache[category].model or 0
    local oldTexture = OldClothesCache[category] and OldClothesCache[category].texture or 0
    local currentModel = ClothesCache[category].model or 0
    local currentTexture = ClothesCache[category].texture or 1
    
    local modelChanged = (currentModel > 0 and currentModel ~= oldModel)
    local textureChanged = (currentModel > 0 and currentModel == oldModel and currentTexture ~= oldTexture)
    local needsPurchase = modelChanged or textureChanged
    
    local displayPrice = needsPurchase and price or 0
    
    -- Слайдер модели
    local modelDesc = image:format(iconName) .. "<br><br>"
    if modelChanged then
        modelDesc = modelDesc .. "Новая модель: <span style='color:gold;'>$" .. price .. "</span>"
    elseif currentModel > 0 then
        modelDesc = modelDesc .. "Модель уже куплена"
    else
        modelDesc = modelDesc .. "Выберите модель"
    end
    modelDesc = modelDesc .. "<br>" .. Divider
    
    elements[#elements + 1] = {
        label = RSG.Label[category] or category,
        value = ClothesCache[category].model or 0,
        category = category,
        desc = modelDesc,
        type = "slider",
        min = 0,
        max = #categoryClothing,
        change_type = "model",
        id = 1
    }
    
    -- Слайдер текстуры
    local textureDesc = ""
    if textureChanged then
        textureDesc = "Новый цвет: <span style='color:gold;'>$" .. price .. "</span>"
    elseif currentModel > 0 and currentTexture == oldTexture then
        textureDesc = "<span style='color:lime;'>Этот цвет уже куплен</span>"
    else
        textureDesc = "Выберите цвет"
    end
    
    elements[#elements + 1] = {
        label = RSG.Label.color .. " " .. (RSG.Label[category] or category),
        value = ClothesCache[category].texture or 1,
        category = category,
        desc = textureDesc,
        type = "slider",
        min = 1,
        max = GetMaxTexturesForModel(category, ClothesCache[category].model or 1, true),
        change_type = "texture",
        id = 2
    }
    
    MenuData.Open('default', GetCurrentResourceName(), 'clothing_item_menu',
        {
            title = RSG.Label[category] or category,
            subtext = 'Цена за предмет: $' .. price .. ' | К оплате: $' .. CurrentPrice,
            align = 'top-left',
            elements = elements,
            itemHeight = "4vh"
        },
        function(data, menu)
            -- Клик не используется
        end,
        function(data, menu)
            menu.close()
            -- Возврат к подкатегориям
            local mainCategory = nil
            for catKey, catData in pairs(RSG.MenuElements) do
                for _, subcat in ipairs(catData.category) do
                    if subcat == category then
                        mainCategory = catKey
                        break
                    end
                end
                if mainCategory then break end
            end
            
            if mainCategory then
                OpenSubcategoryMenu(mainCategory)
            else
                OpenClothingMenu()
            end
        end,
        function(data, menu)
            MenuUpdateClothes(data, menu)
        end)
end
-- ==========================================
-- СИСТЕМА МОДИФИКАЦИИ ОДЕЖДЫ (SLEEVES/COLLAR/BANDANA)
-- ==========================================

local ClothingModState = {
    sleeves_rolled = false,      -- рукава закатаны (вариант 1)
    sleeves_rolled_open = false, -- рукава закатаны + открытый воротник (вариант 2)
    bandana_up = false,          -- бандана поднята
}

-- Вариации одежды
local ClothingVariations = {
    shirts = {
        base = 'BASE',
        rolled_closed = 'Closed_Collar_Rolled_Sleeve',  -- закатанные рукава, закрытый воротник
        rolled_open = 'open_collar_rolled_sleeve',       -- закатанные рукава, открытый воротник
    },
    bandana = {
        up = 'BANDANA_ON_RIGHT_HAND',
        down = 'BANDANA_OFF_RIGHT_HAND',
        base = 'base',
    }
}

-- Натив для смены вариации компонента
function SetPedComponentVariation(ped, componentHash, variationName)
    Citizen.InvokeNative(0x66B957AAC2EAAEAB, ped, componentHash, joaat(variationName), 0, true, 1)
end

-- Натив для анимации смены (для банданы)
function PlayComponentChangeAnimation(ped, componentHash, variationName)
    Citizen.InvokeNative(0xAE72E7DF013AAA61, ped, componentHash, joaat(variationName), 1, 0, -1082130432)
end

-- Обновить вариацию педа
-- options.skipBodyMorph = true — не вызывать ReapplyBodyMorph (фикс просвечивания на полных персонажах при закатке рукавов)
-- options.skipFinalize = true — не вызывать 0x704C908E9C405136 (как kaf_bulletproof, иначе вылезает одежда на полных)
function UpdatePedVariation(ped, options)
    options = options or {}
    if not options.skipFinalize then Citizen.InvokeNative(0x704C908E9C405136, ped) end
    -- ★ При skipFinalize (рукава/воротник) — (0,1,1,1,false) как kaf_bulletproof, иначе меш вылезает на полных
    Citizen.InvokeNative(0xCC8CA3E88256E58F, ped, options.skipFinalize and 0 or false, options.skipFinalize and 1 or true, true, true, false)
    -- ★ При смене рукавов/воротника — не переприменяем body morph. Смена вариации рубашки не трогает тело,
    -- а ReapplyBodyMorph меняет форму тела и на полных персонажах ломает меш (просвечивание).
    if ReapplyBodyMorph and not options.skipBodyMorph then
        if options.deferBodyMorph then
            SetTimeout(350, function()
                local p = ped and DoesEntityExist(ped) and ped or PlayerPedId()
                if p and DoesEntityExist(p) then ReapplyBodyMorph(p) end
            end)
        else
            ReapplyBodyMorph(ped)
        end
    end
    -- ★ Тату: /sleeves и /sleeves2 вызывают эту функцию (не NativeUpdatePedVariation) — даём shiw-tattoos переприменить оверлей
    -- ★ Макияж: переприменяем overlays после UpdatePedVariation
    if ped == PlayerPedId() then
        SetTimeout(120, function()
            TriggerEvent('shiw-tattoos:client:afterPedVariation')
            TriggerEvent('rsg-appearance:client:afterPedVariation')
        end)
    end
end

-- Переприменить жилет/корсет поверх рубашки (после смены рукавов/воротника)
local function ReapplyVestOverShirt(ped)
    if not ped or not DoesEntityExist(ped) then return end
    local item = (ClothesCache and ClothesCache['vests'] and ClothesCache['vests'].hash and ClothesCache['vests'].hash ~= 0) and ClothesCache['vests']
        or (ClothesCache and ClothesCache['corsets'] and ClothesCache['corsets'].hash and ClothesCache['corsets'].hash ~= 0) and ClothesCache['corsets']
    if not item then return end
    NativeSetPedComponentEnabledClothes(ped, item.hash, false, true, true)
    if NativeUpdatePedVariationClothes then NativeUpdatePedVariationClothes(ped) end
end

-- ★ ОТКЛЮЧЕНО: afterBodyMorph -> ReapplyVestIfEquipped вызывал каскад NativeUpdatePedVariation и ломал одежду
-- AddEventHandler('rsg-appearance:client:afterBodyMorph', ...)

-- ★ Корсет/жилет: переприменение (вызывается только из creator.lua после ApplySkin, не из каскада)
function ReapplyVestIfEquipped(ped)
    if not ped or not DoesEntityExist(ped) then ped = PlayerPedId() end
    local item = (ClothesCache and ClothesCache['vests'] and ClothesCache['vests'].hash and ClothesCache['vests'].hash ~= 0) and ClothesCache['vests']
        or (ClothesCache and ClothesCache['corsets'] and ClothesCache['corsets'].hash and ClothesCache['corsets'].hash ~= 0) and ClothesCache['corsets']
    if not item then return end
    -- Request перед Apply — фикс мешей/просвечивания (0x59BD177A1A48600A)
    Citizen.InvokeNative(0x59BD177A1A48600A, ped, item.hash)
    NativeSetPedComponentEnabledClothes(ped, item.hash, false, true, true)
    if NativeUpdatePedVariationClothes then NativeUpdatePedVariationClothes(ped) end
end

-- Получить текущий hash рубашки
function GetCurrentShirtHash()
    if not ClothesCache then return nil end
    if not ClothesCache['shirts_full'] then return nil end
    if type(ClothesCache['shirts_full']) ~= 'table' then return nil end
    return ClothesCache['shirts_full'].hash
end

-- Получить текущий hash шейного платка/банданы
function GetCurrentNeckwearHash()
    if not ClothesCache then return nil end
    if not ClothesCache['neckwear'] then return nil end
    if type(ClothesCache['neckwear']) ~= 'table' then return nil end
    return ClothesCache['neckwear'].hash
end

-- ==========================================
-- ЗАКАТАТЬ РУКАВА (Вариант 1 - закрытый воротник)
-- ==========================================
function ToggleSleeves()
    local ped = PlayerPedId()
    local shirtHash = GetCurrentShirtHash()
    
    if not shirtHash or shirtHash == 0 then
        TriggerEvent('ox_lib:notify', {
            title = 'Одежда',
            description = 'Сначала наденьте рубашку',
            type = 'error'
        })
        return
    end
    
    -- Сбрасываем другой вариант рукавов
    ClothingModState.sleeves_rolled_open = false
    
    -- Переключаем состояние
    ClothingModState.sleeves_rolled = not ClothingModState.sleeves_rolled
    
    -- Анимация
    PlayClothingModAnimation('sleeves')
    Wait(500)
    
    local variation = ClothingModState.sleeves_rolled 
        and ClothingVariations.shirts.rolled_closed 
        or ClothingVariations.shirts.base
    
    -- ★ Берём цвета из getEquippedClothing (тот же источник, что при загрузке)
    local fallbackPalette = ClothesCache and ClothesCache['shirts_full'] and ClothesCache['shirts_full'].palette
    local fallbackTints = ClothesCache and ClothesCache['shirts_full'] and ClothesCache['shirts_full'].tints
    RSGCore.Functions.TriggerCallback('rsg-clothing:server:getEquippedClothing', function(equipped)
        local pal, tnt = fallbackPalette, fallbackTints
        if equipped and equipped['shirts_full'] then
            local d = equipped['shirts_full']
            pal = d.palette or d._p or pal
            tnt = d.tints or d._tints or tnt
        end
        pal = pal or 'tint_generic_clean'
        tnt = tnt or {0, 0, 0}
        -- ★ Request перед сменой вариации — после loadcharacter меш рубашки может не быть загружен, без Request просвечивает
        Citizen.InvokeNative(0x59BD177A1A48600A, ped, shirtHash)
        Wait(80)
        SetPedComponentVariation(ped, shirtHash, variation)
        -- ★ Как kaf_bulletproof: 0xCC8CA3E88256E58F с параметрами (0,1,1,1,false) — иначе на полных меш вылезает
        Citizen.InvokeNative(0xCC8CA3E88256E58F, ped, 0, 1, 1, 1, false)
        if ApplyClothingColor then ApplyClothingColor(ped, 'shirts_full', pal, tnt) end
        -- ★ Жилет поверх рубашки — иначе просвечивает (порядок: рукава → жилет)
        ReapplyVestOverShirt(ped)
        if ApplyClothingColor then
            local v = ClothesCache and (ClothesCache['vests'] or ClothesCache['corsets'])
            if v and v.palette and v.tints then ApplyClothingColor(ped, v == ClothesCache['vests'] and 'vests' or 'corsets', v.palette, v.tints) end
        end
        if ped == PlayerPedId() then
            SetTimeout(120, function()
                TriggerEvent('shiw-tattoos:client:afterPedVariation')
                TriggerEvent('rsg-appearance:client:afterPedVariation')
            end)
        end
        TriggerEvent('rsg-appearance:client:clothingVariationChanged')
        SetTimeout(650, function()
            TriggerEvent('rsg-appearance:client:clothingVariationSettled')
        end)
    end)

    -- Уведомление
    local message = ClothingModState.sleeves_rolled and 'Рукава закатаны' or 'Рукава опущены'
    TriggerEvent('ox_lib:notify', {
        title = 'Рукава',
        description = message,
        type = 'success'
    })
    
    print('[Clothing] Sleeves toggled: ' .. variation .. ' for hash: 0x' .. string.format("%X", shirtHash))
    -- Тату: последний апплай в конце /sleeves, чтобы оверлей не перезаписался
    SetTimeout(80, function()
        pcall(function() exports['shiw-tattoos']:ReapplyTattoo() end)
    end)
end

-- ==========================================
-- ЗАКАТАТЬ РУКАВА (Вариант 2 - открытый воротник)
-- ==========================================
function ToggleSleevesOpen()
    local ped = PlayerPedId()
    local shirtHash = GetCurrentShirtHash()
    
    if not shirtHash or shirtHash == 0 then
        TriggerEvent('ox_lib:notify', {
            title = 'Одежда',
            description = 'Сначала наденьте рубашку',
            type = 'error'
        })
        return
    end
    
    -- Сбрасываем другой вариант рукавов
    ClothingModState.sleeves_rolled = false
    
    -- Переключаем состояние
    ClothingModState.sleeves_rolled_open = not ClothingModState.sleeves_rolled_open
    
    -- Анимация
    PlayClothingModAnimation('sleeves')
    Wait(500)
    
    local variation = ClothingModState.sleeves_rolled_open 
        and ClothingVariations.shirts.rolled_open 
        or ClothingVariations.shirts.base
    
    local fallbackPalette = ClothesCache and ClothesCache['shirts_full'] and ClothesCache['shirts_full'].palette
    local fallbackTints = ClothesCache and ClothesCache['shirts_full'] and ClothesCache['shirts_full'].tints
    RSGCore.Functions.TriggerCallback('rsg-clothing:server:getEquippedClothing', function(equipped)
        local pal, tnt = fallbackPalette, fallbackTints
        if equipped and equipped['shirts_full'] then
            local d = equipped['shirts_full']
            pal = d.palette or d._p or pal
            tnt = d.tints or d._tints or tnt
        end
        pal = pal or 'tint_generic_clean'
        tnt = tnt or {0, 0, 0}
        -- ★ Request перед сменой вариации — после loadcharacter меш рубашки может не быть загружен, без Request просвечивает
        Citizen.InvokeNative(0x59BD177A1A48600A, ped, shirtHash)
        Wait(80)
        SetPedComponentVariation(ped, shirtHash, variation)
        -- ★ Как kaf_bulletproof: 0xCC8CA3E88256E58F с параметрами (0,1,1,1,false) — иначе на полных меш вылезает
        Citizen.InvokeNative(0xCC8CA3E88256E58F, ped, 0, 1, 1, 1, false)
        if ApplyClothingColor then ApplyClothingColor(ped, 'shirts_full', pal, tnt) end
        -- ★ Жилет поверх рубашки — иначе просвечивает (порядок: рукава → жилет)
        ReapplyVestOverShirt(ped)
        if ApplyClothingColor then
            local v = ClothesCache and (ClothesCache['vests'] or ClothesCache['corsets'])
            if v and v.palette and v.tints then ApplyClothingColor(ped, v == ClothesCache['vests'] and 'vests' or 'corsets', v.palette, v.tints) end
        end
        if ped == PlayerPedId() then
            SetTimeout(120, function()
                TriggerEvent('shiw-tattoos:client:afterPedVariation')
                TriggerEvent('rsg-appearance:client:afterPedVariation')
            end)
        end
        TriggerEvent('rsg-appearance:client:clothingVariationChanged')
        SetTimeout(650, function()
            TriggerEvent('rsg-appearance:client:clothingVariationSettled')
        end)
    end)

    -- Уведомление
    local message = ClothingModState.sleeves_rolled_open and 'Рукава закатаны, воротник расстёгнут' or 'Рукава опущены, воротник застёгнут'
    TriggerEvent('ox_lib:notify', {
        title = 'Рукава',
        description = message,
        type = 'success'
    })
    SetTimeout(80, function()
        pcall(function() exports['shiw-tattoos']:ReapplyTattoo() end)
    end)
end

-- ==========================================
-- ВОРОТНИК (отдельно)
-- ==========================================
function ToggleCollar()
    local ped = PlayerPedId()
    local shirtHash = GetCurrentShirtHash()
    
    if not shirtHash or shirtHash == 0 then
        TriggerEvent('ox_lib:notify', {
            title = 'Одежда',
            description = 'Сначала наденьте рубашку',
            type = 'error'
        })
        return
    end
    
    -- Сохраняем цвет ДО изменения
    local savedPalette = nil
    local savedTints = nil
    if ClothesCache and ClothesCache['shirts_full'] then
        savedPalette = ClothesCache['shirts_full'].palette
        savedTints = ClothesCache['shirts_full'].tints
    end
    
    -- Если рукава уже закатаны - переключаем между вариантами воротника
    if ClothingModState.sleeves_rolled then
        -- Переключаем на открытый воротник с закатанными рукавами
        ClothingModState.sleeves_rolled = false
        ClothingModState.sleeves_rolled_open = true
        
        PlayClothingModAnimation('collar')
        Wait(500)
        
        SetPedComponentVariation(ped, shirtHash, ClothingVariations.shirts.rolled_open)
        UpdatePedVariation(ped, { skipBodyMorph = true, skipFinalize = true })
        
        -- ВОССТАНАВЛИВАЕМ ЦВЕТ!
        if savedPalette and savedTints then
            Wait(100)
            ApplyClothingColor(ped, 'shirts_full', savedPalette, savedTints)
        end
        TriggerEvent('rsg-appearance:client:clothingVariationChanged')
        SetTimeout(650, function()
            TriggerEvent('rsg-appearance:client:clothingVariationSettled')
        end)
        -- ★ НЕ вызываем requestModifierReapply — каскад UpdatePedVariation ломает меш на полных персонажах
        
        TriggerEvent('ox_lib:notify', {
            title = 'Воротник',
            description = 'Воротник расстёгнут',
            type = 'success'
        })
        SetTimeout(80, function()
            pcall(function() exports['shiw-tattoos']:ReapplyTattoo() end)
        end)
    elseif ClothingModState.sleeves_rolled_open then
        -- Переключаем на закрытый воротник с закатанными рукавами
        ClothingModState.sleeves_rolled_open = false
        ClothingModState.sleeves_rolled = true
        
        PlayClothingModAnimation('collar')
        Wait(500)
        
        SetPedComponentVariation(ped, shirtHash, ClothingVariations.shirts.rolled_closed)
        UpdatePedVariation(ped, { skipBodyMorph = true, skipFinalize = true })
        
        -- ВОССТАНАВЛИВАЕМ ЦВЕТ!
        if savedPalette and savedTints then
            Wait(100)
            ApplyClothingColor(ped, 'shirts_full', savedPalette, savedTints)
        end
        TriggerEvent('rsg-appearance:client:clothingVariationChanged')
        SetTimeout(650, function()
            TriggerEvent('rsg-appearance:client:clothingVariationSettled')
        end)
        -- ★ НЕ вызываем requestModifierReapply — каскад UpdatePedVariation ломает меш на полных персонажах
        
        TriggerEvent('ox_lib:notify', {
            title = 'Воротник',
            description = 'Воротник застёгнут',
            type = 'success'
        })
        SetTimeout(80, function()
            pcall(function() exports['shiw-tattoos']:ReapplyTattoo() end)
        end)
    else
        -- Рукава не закатаны - просто уведомляем
        TriggerEvent('ox_lib:notify', {
            title = 'Воротник',
            description = 'Сначала закатайте рукава (/sleeves или /sleeves2)',
            type = 'info'
        })
    end
end

-- ==========================================
-- БАНДАНА v4.0 (как в одиночке: вариации neckwear)
-- ==========================================

-- Константы для вариаций
local BANDANA_ON_VARIATION = GetHashKey("BANDANA_ON_RIGHT_HAND")
local BANDANA_OFF_VARIATION = GetHashKey("BANDANA_OFF_RIGHT_HAND")
local BANDANA_ON_COMPONENT = -1829635046  -- Вариация компонента: бандана на лице
local BANDANA_BASE_COMPONENT = GetHashKey("base") -- Вариация компонента: базовое положение

local NECKWEAR_META_CATEGORY_FP = 0x5FC29285
local BANDANA_DRAWABLE_SLOT_FP = 0x7505EF42
local appearanceFpBandanaStripSession = false

local function RsgHideBandanaFpEnabled()
    return RSG and RSG.HideBandanaMeshInFirstPerson == true
end

local N_RSG_FP_FULL = 0xD1BA66940E94C547 -- _IS_IN_FULL_FIRST_PERSON_MODE
local N_RSG_GET_FOLLOW_MODE = 0x8D4D46230B2C353A -- GET_FOLLOW_PED_CAM_VIEW_MODE
local N_RSG_GET_FOLLOW_MODE_LEGACY = 0x8D4D46230B92C8A7

local function RsgFollowModeIsFp(mode)
    if mode == nil then return false end
    local list = RSG and RSG.FirstPersonCamViewModes
    if type(list) == 'table' and #list > 0 then
        for _, m in ipairs(list) do
            if tonumber(mode) == tonumber(m) then return true end
        end
        return false
    end
    return tonumber(mode) == 4
end

local function RsgIsFollowCamFirstPerson()
    local ok, v = pcall(function()
        return Citizen.InvokeNative(N_RSG_FP_FULL)
    end)
    if ok and v and v ~= 0 then
        return true
    end

    local mode
    ok = pcall(function()
        if type(GetFollowPedCamViewMode) == 'function' then
            mode = tonumber(GetFollowPedCamViewMode())
        end
    end)
    if ok and RsgFollowModeIsFp(mode) then
        return true
    end

    for _, hash in ipairs({ N_RSG_GET_FOLLOW_MODE, N_RSG_GET_FOLLOW_MODE_LEGACY }) do
        ok, mode = pcall(function()
            return tonumber(Citizen.InvokeNative(hash))
        end)
        if ok and RsgFollowModeIsFp(mode) then
            return true
        end
    end

    if type(GetCamViewModeForContext) == 'function' then
        for ctx = 0, 8 do
            ok, mode = pcall(function()
                return tonumber(GetCamViewModeForContext(ctx))
            end)
            if ok and RsgFollowModeIsFp(mode) then
                return true
            end
        end
    end

    return false
end

local function RsgStripNeckwearForFp(ped)
    if not ped or ped == 0 then return end
    Citizen.InvokeNative(0xD710A5007C2AC539, ped, NECKWEAR_META_CATEGORY_FP, 0)
    Citizen.InvokeNative(0xD710A5007C2AC539, ped, BANDANA_DRAWABLE_SLOT_FP, 0)
    pcall(function()
        Citizen.InvokeNative(0xD710A5007C2AC539, ped, GetHashKey('masks'), 0)
        Citizen.InvokeNative(0xD710A5007C2AC539, ped, GetHashKey('neckwear'), 0)
    end)
    pcall(function()
        Citizen.InvokeNative(0x704C908E9C405136, ped)
    end)
    Citizen.InvokeNative(0xCC8CA3E88256E58F, ped, false, true, true, true, false)
end

local function RsgRestoreBandanaUpVisual(ped)
    if not ped or ped == 0 then return end
    if not ClothingModState.bandana_up then return end
    local nh = ClothingModState.saved_neckwear_hash or GetCurrentNeckwearHash()
    if not nh or nh == 0 then return end
    Citizen.InvokeNative(0x66B957AAC2EAAEAB, ped, tonumber(nh), BANDANA_ON_COMPONENT, 0, true, 1)
    Citizen.InvokeNative(0x704C908E9C405136, ped)
    Citizen.InvokeNative(0xCC8CA3E88256E58F, ped, false, true, true, true, false)
end

function ToggleBandana()
    local ped = PlayerPedId()
    local neckwearHash = GetCurrentNeckwearHash()

    if not neckwearHash or neckwearHash == 0 then
        TriggerEvent('ox_lib:notify', {
            title = 'Одежда',
            description = 'Сначала наденьте бандану/платок',
            type = 'error'
        })
        return
    end

    -- Переключаем состояние
    ClothingModState.bandana_up = not ClothingModState.bandana_up

    if ClothingModState.bandana_up then
        -- ========== ПОДНИМАЕМ БАНДАНУ ==========
        ClothingModState.saved_neckwear_hash = neckwearHash

        -- Анимация поднятия (через хеш самого neckwear — как в одиночке)
        Citizen.InvokeNative(0xAE72E7DF013AAA61, ped, tonumber(neckwearHash), BANDANA_ON_VARIATION, 1, 0, -1082130432)
        Wait(700)

        -- Применяем вариацию "бандана на лице" к тому же neckwear
        Citizen.InvokeNative(0x66B957AAC2EAAEAB, ped, tonumber(neckwearHash), BANDANA_ON_COMPONENT, 0, true, 1)

        -- Обновляем визуал
        Citizen.InvokeNative(0x704C908E9C405136, ped)
        Citizen.InvokeNative(0xCC8CA3E88256E58F, ped, false, true, true, true, false)
        if RsgHideBandanaFpEnabled() and RsgIsFollowCamFirstPerson() then
            RsgStripNeckwearForFp(ped)
            appearanceFpBandanaStripSession = true
        else
            appearanceFpBandanaStripSession = false
        end
    else
        appearanceFpBandanaStripSession = false
        -- ========== ОПУСКАЕМ БАНДАНУ ==========
        local originalHash = ClothingModState.saved_neckwear_hash or neckwearHash

        -- Анимация снятия
        Citizen.InvokeNative(0xAE72E7DF013AAA61, ped, tonumber(originalHash), BANDANA_OFF_VARIATION, 1, 0, -1082130432)
        Wait(700)

        -- Возвращаем базовую вариацию neckwear
        Citizen.InvokeNative(0x66B957AAC2EAAEAB, ped, tonumber(originalHash), BANDANA_BASE_COMPONENT, 0, true, 1)

        -- Обновляем визуал
        Citizen.InvokeNative(0x704C908E9C405136, ped)
        Citizen.InvokeNative(0xCC8CA3E88256E58F, ped, false, true, true, true, false)

        -- Восстанавливаем цвет neckwear
        Wait(100)
        if ClothesCache and ClothesCache['neckwear'] then
            local savedPalette = ClothesCache['neckwear'].palette
            local savedTints = ClothesCache['neckwear'].tints
            if savedPalette and savedTints then
                ApplyClothingColor(ped, 'neckwear', savedPalette, savedTints)
            end
        end

        ClothingModState.saved_neckwear_hash = nil
    end

    SetTimeout(650, function()
        TriggerEvent('rsg-appearance:client:requestModifierReapply')
    end)

    -- Уведомление
    local message = ClothingModState.bandana_up and 'Бандана поднята' or 'Бандана опущена'
    TriggerEvent('ox_lib:notify', {
        title = 'Бандана',
        description = message,
        type = 'success'
    })
end

CreateThread(function()
    while true do
        local ped = PlayerPedId()
        if ClothingModState.bandana_up and RsgHideBandanaFpEnabled() and ped ~= 0 then
            local fp = RsgIsFollowCamFirstPerson()
            if fp then
                RsgStripNeckwearForFp(ped)
                appearanceFpBandanaStripSession = true
                Wait(0)
            else
                if appearanceFpBandanaStripSession then
                    RsgRestoreBandanaUpVisual(ped)
                    if ClothesCache and ClothesCache['neckwear'] then
                        local savedPalette = ClothesCache['neckwear'].palette
                        local savedTints = ClothesCache['neckwear'].tints
                        if savedPalette and savedTints then
                            ApplyClothingColor(ped, 'neckwear', savedPalette, savedTints)
                        end
                    end
                    appearanceFpBandanaStripSession = false
                end
                Wait(50)
            end
        else
            if appearanceFpBandanaStripSession and ped ~= 0 then
                RsgRestoreBandanaUpVisual(ped)
                appearanceFpBandanaStripSession = false
            end
            Wait(200)
        end
    end
end)

-- ==========================================
-- АНИМАЦИЯ
-- ==========================================
function PlayClothingModAnimation(animType)
    local ped = PlayerPedId()
    if not ped or ped == 0 then return end
    
    local dict, anim, duration
    
    if animType == 'sleeves' then
        dict = 'script_proc@town@tailor@shop_owner'
        anim = 'measure_arm_tailor'
        duration = 1500
    elseif animType == 'collar' then
        dict = 'amb_misc@world_human_lean_fence_inspect@leaningalt@male_a@idle_c'
        anim = 'idle_d'
        duration = 1000
    else
        return
    end
    
    RequestAnimDict(dict)
    local timeout = 0
    while not HasAnimDictLoaded(dict) and timeout < 100 do
        Wait(50)
        timeout = timeout + 1
    end
    
    if HasAnimDictLoaded(dict) then
        if not IsPedOnMount(ped) and not IsPedInAnyVehicle(ped, false) then
            TaskPlayAnim(ped, dict, anim, 4.0, -4.0, duration, 49, 0, false, false, false)
        end
    end
end

-- ==========================================
-- СБРОС СОСТОЯНИЯ ПРИ СМЕНЕ ОДЕЖДЫ
-- ==========================================
function ResetClothingModState(category)
    if category == 'shirts_full' then
        ClothingModState.sleeves_rolled = false
        ClothingModState.sleeves_rolled_open = false
    elseif category == 'neckwear' then
        ClothingModState.bandana_up = false
        appearanceFpBandanaStripSession = false
    end
end

local function RestorePlayerVisibilitySafe()
    local ped = PlayerPedId()
    if not ped or not DoesEntityExist(ped) then return end
    if IsInCharCreation then return end
    -- ★ FIX: Не мерцаем если уже видим
    if IsEntityVisible(ped) and GetEntityAlpha(ped) >= 255 then return end

    SetEntityVisible(ped, true, false)
    SetEntityAlpha(ped, 255, false)
    NetworkSetEntityInvisibleToNetwork(ped, false)
    SetEntityCollision(ped, true, true)
    FreezeEntityPosition(ped, false)
end

-- Хук на снятие одежды
RegisterNetEvent('rsg-clothing:client:removeClothing')
AddEventHandler('rsg-clothing:client:removeClothing', function(category)
    ResetClothingModState(category)
end)

-- После loadcharacter только сбрасываем состояние рукавов/воротника (чтобы не было рассинхрона с визуалом). Без лишних переприменений одежды.
local _lastLoadCoatEquipPass = 0
local function ReapplyCoatsAfterLoadViaEquipPath()
    local now = GetGameTimer()
    if (now - (_lastLoadCoatEquipPass or 0)) < 1200 then
        return
    end
    _lastLoadCoatEquipPass = now

    RSGCore.Functions.TriggerCallback('rsg-clothing:server:getEquippedClothing', function(equippedItems)
        if not equippedItems then return end
        local ped = PlayerPedId()
        if not ped or not DoesEntityExist(ped) then return end

        -- Важно: используем тот же путь, что и ручное надевание (equipClothing),
        -- чтобы пальто получало идентичный apply/tint flow после loadcharacter.
        for _, cat in ipairs({'coats', 'coats_closed'}) do
            local item = equippedItems[cat]
            if item and type(item) == 'table' then
                local payload = {}
                for k, v in pairs(item) do payload[k] = v end
                payload.category = cat
                TriggerEvent('rsg-clothing:client:equipClothing', payload)
                Wait(120)
            end
        end
    end)
end

AddEventHandler('rsg-appearance:client:ApplySkinComplete', function()
    ResetClothingModState('shirts_full')
    ResetClothingModState('neckwear')

    -- ★ Освежение рубашки+жилета перенесено в LoadClothingFromInventory — выполняется сразу после основной загрузки, без задержки

    -- Safety fix: после loadskin/захода некоторые внешние скрипты (покер/блекджек)
    -- клонируют текущего педа. Если пед остался невидимым, клон тоже будет невидим.
    -- ★ FIX: Убраны лишние проходы (300, 900, 2000, 4500) — вызывали мерцание. RestorePlayerVisibilitySafe сам проверяет видимость.
    RestorePlayerVisibilitySafe()
    SetTimeout(300, RestorePlayerVisibilitySafe)

    -- Coat color fix after loadcharacter:
    -- один и тот же путь, что при ручном надевании, с отложенными проходами
    -- после поздних ped variation/update от других ресурсов.
    SetTimeout(700, ReapplyCoatsAfterLoadViaEquipPath)
    SetTimeout(1700, ReapplyCoatsAfterLoadViaEquipPath)
    -- ★ FIX: Vest/corset без рубашки — переприменяем через 1.2 сек (просветы тела сквозь корсет после loadcharacter)
    SetTimeout(1200, function()
        local p = PlayerPedId()
        if not p or not DoesEntityExist(p) then return end
        if not IsPedMale(p) and ClothesCache then
            local vest = ClothesCache['vests'] or ClothesCache['corsets']
            if vest and vest.hash and vest.hash ~= 0 and not (ClothesCache['shirts_full'] and ClothesCache['shirts_full'].hash and ClothesCache['shirts_full'].hash ~= 0) then
                if EnsureBodyIntegrity then EnsureBodyIntegrity(p, true) end
                Wait(80)
                NativeSetPedComponentEnabledClothes(p, vest.hash, false, true, true)
                Citizen.InvokeNative(0x704C908E9C405136, p)
                if NativeUpdatePedVariation then NativeUpdatePedVariation(p, true) end
                -- ★ После UpdatePedVariation стандартное тело может перекрыть корсет — ещё раз переприменяем корсет поверх
                Wait(40)
                NativeSetPedComponentEnabledClothes(p, vest.hash, false, true, true)
                if NativeUpdatePedVariationClothes then NativeUpdatePedVariationClothes(p) end
            end
        end
    end)
    -- ★ ОТКЛЮЧЕНО: requestModifierReapply через 3.5с вызывал ApplyAllSavedColors и ломал одежду (naked body)
    -- ReapplyCoatsAfterLoadViaEquipPath уже триггерит equip для пальто → ApplyClothingColor
    -- SetTimeout(3500, function() TriggerEvent('rsg-appearance:client:requestModifierReapply') end)
end)

-- ==========================================
-- КОМАНДЫ
-- ==========================================
RegisterCommand('sleeves', function()
    ToggleSleeves()
end, false)

RegisterCommand('sleeves2', function()
    ToggleSleevesOpen()
end, false)

RegisterCommand('collar', function()
    ToggleCollar()
end, false)

RegisterCommand('bandana', function()
    ToggleBandana()
end, false)

-- ==========================================
-- DEBUG
-- ==========================================
RegisterCommand('clothstate', function()
    print('=== CLOTHING MOD STATE ===')
    print('Sleeves rolled (closed): ' .. tostring(ClothingModState.sleeves_rolled))
    print('Sleeves rolled (open): ' .. tostring(ClothingModState.sleeves_rolled_open))
    print('Bandana up: ' .. tostring(ClothingModState.bandana_up))
    print('')
    print('Shirt hash: ' .. tostring(GetCurrentShirtHash()))
    print('Neckwear hash: ' .. tostring(GetCurrentNeckwearHash()))
end, false)

print('[RSG-Clothing] Sleeves/Collar/Bandana system loaded')
RegisterCommand('debugcache', function()
    print('=== CLOTHES CACHE DEBUG ===')
    
    if not ClothesCache then
        print('ClothesCache is nil!')
        return
    end
    
    if next(ClothesCache) == nil then
        print('ClothesCache is EMPTY!')
        return
    end
    
    for category, data in pairs(ClothesCache) do
        if type(data) == 'table' then
            print(category .. ':')
            print('  hash: ' .. tostring(data.hash))
            print('  model: ' .. tostring(data.model))
            print('  texture: ' .. tostring(data.texture))
        else
            print(category .. ': ' .. tostring(data))
        end
    end
end, false)
-- ★ GetCurrentShirtHash / GetCurrentNeckwearHash — дубликаты удалены, используются определения выше (только ClothesCache)
-- callback rsg-clothing:server:getEquippedClothingSync не используется — ресурс rsg-clothing отсутствует
function PlayClothingModAnimation()
    local ped = PlayerPedId()
    if not ped or ped == 0 then return end
    
    -- Используем анимацию надевания одежды
    local dict = 'mech_loco_m@character@arthur@fidgets@hat@normal@unarmed@normal@left_hand'
    local anim = 'hat_lhand_b'
    
    RequestAnimDict(dict)
    local timeout = 0
    while not HasAnimDictLoaded(dict) and timeout < 100 do
        Wait(50)
        timeout = timeout + 1
    end
    
    if HasAnimDictLoaded(dict) then
        if not IsPedOnMount(ped) and not IsPedInAnyVehicle(ped, false) then
            TaskPlayAnim(ped, dict, anim, 4.0, -4.0, 1500, 51, 0, false, false, false)
        end
    end
end
-- ==========================================
-- МЕНЮ РЕМОНТА (КЛИЕНТ)
-- ==========================================

RegisterNetEvent('rsg-clothing:client:openRepairMenu', function()
    RSGCore.Functions.TriggerCallback('rsg-clothing:server:getClothingForRepair', function(clothingList)
        if not clothingList or #clothingList == 0 then
            lib.notify({
                title = 'Ремонт',
                description = 'У вас нет одежды, которая нуждается в ремонте',
                type = 'info'
            })
            return
        end
        
        local menuOptions = {}
        
        for _, item in ipairs(clothingList) do
            local color = 'green'
            local icon = '✅'
            
            if item.durability < 20 then
                color = 'red'
                icon = '❌'
            elseif item.durability < 40 then
                color = 'orange'
                icon = '⚠️'
            elseif item.durability < 60 then
                color = 'yellow'
                icon = '👍'
            end
            
            local statusText = item.equipped and ' (Надето)' or ''
            
            table.insert(menuOptions, {
                title = icon .. ' ' .. item.label,
                description = 'Качество: ' .. item.durability .. '%' .. statusText .. '\nПосле ремонта: 100% (1 швейный набор)',
                metadata = {
                    {label = 'Текущее качество', value = item.durability .. '%'},
                    {label = 'После ремонта', value = '100%'},
                    {label = 'Статус', value = item.equipped and 'Надето' or 'В инвентаре'}
                },
                onSelect = function()
                    -- Показываем прогрессбар
                    if lib.progressBar({
                        duration = 5000,
                        label = 'Ремонтируем ' .. item.label .. '...',
                        useWhileDead = false,
                        canCancel = true,
                        disable = {
                            car = true,
                            combat = true,
                            move = true
                        },
                        anim = {
                            dict = 'mini_games@story@mud4@repair',
                            clip = 'Mud4_Repair_Player',
                            flags = 1
                        }
                    }) then
                        -- Ремонт успешен
                        TriggerServerEvent('rsg-clothing:server:repairClothing', item.slot)
                    else
                        -- Отменено
                        lib.notify({
                            title = 'Ремонт',
                            description = 'Ремонт отменён',
                            type = 'error'
                        })
                    end
                end,
                serverEvent = false
            })
        end
        
        -- Добавляем кнопку отмены
        table.insert(menuOptions, {
            title = '❌ Отмена',
            description = 'Закрыть меню ремонта',
            onSelect = function()
                lib.hideContext()
            end
        })
        
        lib.registerContext({
            id = 'clothing_repair_menu',
            title = '🔧 Ремонт одежды',
            options = menuOptions
        })
        
        lib.showContext('clothing_repair_menu')
    end)
end)
-- ==========================================
-- КОМАНДЫ
-- ==========================================

RegisterCommand('sleeves', function()
    ToggleSleeves()
end, false)

RegisterCommand('collar', function()
    ToggleCollar()
end, false)

-- ==========================================
-- DEBUG КОМАНДЫ
-- ==========================================

RegisterCommand('shirtinfo', function()
    local model, texture = GetCurrentShirtData()
    local hash = 0
    
    if ClothesCache and ClothesCache['shirts_full'] and ClothesCache['shirts_full'].hash then
        hash = ClothesCache['shirts_full'].hash
    end
    
    if model and model > 0 then
        local isMale = IsPedMale(PlayerPedId())
        print('=== SHIRT INFO ===')
        print('Gender: ' .. (isMale and 'male' or 'female'))
        print('Model: ' .. tostring(model))
        print('Texture: ' .. tostring(texture or 1))
        print('Hash: 0x' .. string.format("%X", hash or 0))
        
        -- Проверяем есть ли пара для рукавов
        local gender = isMale and 'male' or 'female'
        local hasSleeves = ShirtSleevesMap[gender] and ShirtSleevesMap[gender][model]
        print('Sleeves pair: ' .. tostring(hasSleeves or 'none'))
        
        TriggerEvent('ox_lib:notify', {
            title = 'Рубашка',
            description = 'Модель: ' .. model .. ' | Рукава: ' .. (hasSleeves and 'да' or 'нет'),
            type = 'info'
        })
    else
        print('No shirt equipped')
        TriggerEvent('ox_lib:notify', {
            title = 'Рубашка',
            description = 'Рубашка не надета',
            type = 'error'
        })
    end
end, false)

RegisterCommand('testshirt', function(source, args)
    if not args[1] then
        print('Usage: /testshirt [model] [texture]')
        return
    end
    
    local ped = PlayerPedId()
    local isMale = IsPedMale(ped)
    local gender = isMale and "male" or "female"
    local model = tonumber(args[1])
    local texture = tonumber(args[2]) or 1
    
    if not model then
        print('Invalid model number')
        return
    end
    
    if not clothing or not clothing[gender] or not clothing[gender]['shirts_full'] then
        print('Clothing data not found')
        return
    end
    
    local clothingData = clothing[gender]['shirts_full']
    
    if not clothingData[model] then
        print('Model ' .. model .. ' not found for ' .. gender)
        
        -- Показываем ближайшие доступные модели
        local available = {}
        for m in pairs(clothingData) do
            table.insert(available, m)
        end
        table.sort(available)
        print('Available models (first 20):')
        for i = 1, math.min(20, #available) do
            print('  ' .. available[i])
        end
        return
    end
    
    if not clothingData[model][texture] then
        print('Texture ' .. texture .. ' not found, trying texture 1')
        texture = 1
        if not clothingData[model][texture] then
            -- Ищем первую доступную
            for t in pairs(clothingData[model]) do
                texture = t
                break
            end
        end
    end
    
    if not clothingData[model][texture] then
        print('No valid texture found')
        return
    end
    
    local hash = clothingData[model][texture].hash
    
    if not hash or hash == 0 then
        print('Invalid hash')
        return
    end
    
    Citizen.InvokeNative(0xD710A5007C2AC539, ped, GetHashKey("shirts_full"), 0)
    Wait(100)
    NativeSetPedComponentEnabledClothes(ped, hash, false, true, true)
    NativeUpdatePedVariation(ped, true)
    
    ClothesCache['shirts_full'] = {
        model = model,
        texture = texture,
        hash = hash
    }
    
    print('Applied shirt model: ' .. model .. ' texture: ' .. texture .. ' hash: 0x' .. string.format("%X", hash))
    TriggerEvent('ox_lib:notify', {
        title = 'Тест рубашки',
        description = 'Модель: ' .. model,
        type = 'success'
    })
end, false)

RegisterCommand('listshirts', function()
    local ped = PlayerPedId()
    local isMale = IsPedMale(ped)
    local gender = isMale and "male" or "female"
    
    if not clothing or not clothing[gender] or not clothing[gender]['shirts_full'] then
        print('No shirts found')
        return
    end
    
    local clothingData = clothing[gender]['shirts_full']
    
    print('=== AVAILABLE SHIRT MODELS (' .. gender .. ') ===')
    local models = {}
    for model in pairs(clothingData) do
        table.insert(models, model)
    end
    table.sort(models)
    
    for _, model in ipairs(models) do
        local textureCount = 0
        for _ in pairs(clothingData[model]) do textureCount = textureCount + 1 end
        local hasSleeves = ShirtSleevesMap[gender] and ShirtSleevesMap[gender][model] and 'YES' or 'no'
        print('Model ' .. model .. ': ' .. textureCount .. ' textures, sleeves: ' .. hasSleeves)
    end
    print('Total: ' .. #models .. ' models')
end, false)

print('[RSG-Clothing] Sleeves/Collar commands loaded')
-- ==========================================
-- КЛИЕНТСКИЙ ОБРАБОТЧИК ИНВЕНТАРЯ
-- ==========================================

-- Проверка на clothing_item
function IsClothingItem(itemName)
    local clothingItems = {
        'clothing_item',
        'clothing_hats',
        'clothing_shirts_full',
        'clothing_pants',
        'clothing_boots',
        'clothing_vests',
        'clothing_coats',
        'clothing_coats_closed',
        'clothing_gloves',
        'clothing_neckwear',
        'clothing_masks',
        'clothing_eyewear',
        'clothing_gunbelts',
        'clothing_satchels',
        'clothing_skirts',
        'clothing_chaps',
        'clothing_spurs',
        'clothing_rings_rh',
        'clothing_rings_lh',
        'clothing_suspenders',
        'clothing_belts',
        'clothing_cloaks',
        'clothing_ponchos',
        'clothing_gauntlets',
        'clothing_neckties',
        'clothing_holsters_knife',
        'clothing_loadouts',
        'clothing_holsters_left',
        'clothing_holsters_right',
        'clothing_holsters_crossdraw',
        'clothing_aprons',
        'clothing_boot_accessories',
        'clothing_spats',
        'clothing_jewelry_rings_right',
        'clothing_jewelry_rings_left',
        'clothing_jewelry_bracelets',
        'clothing_talisman_holster',
        'clothing_talisman_wrist',
        'clothing_belt_buckles',
        'clothing_bows',
        'clothing_hair_accessories',
        'clothing_dresses',
        'clothing_earrings',
        'clothing_armor',
    }
    
    for _, item in ipairs(clothingItems) do
        if itemName == item then
            return true
        end
    end
    return false
end

-- Хук на изменение данных игрока (QBCore/RSGCore)
RegisterNetEvent('QBCore:Player:SetPlayerData', function(playerData)
    CreateThread(function()
        Wait(500) -- даем время серверу обработать
        TriggerServerEvent('rsg-clothing:server:checkInventorySync')
    end)
end)

RegisterNetEvent('RSGCore:Player:SetPlayerData', function(playerData)
    CreateThread(function()
        Wait(500)
        TriggerServerEvent('rsg-clothing:server:checkInventorySync')
    end)
end)

-- Хук на rsg-inventory (клиент) - когда предмет удаляется
RegisterNetEvent('rsg-inventory:client:ItemBox', function(itemData, type)
    if type == "remove" and itemData and itemData.name then
        if IsClothingItem(itemData.name) then
            print('[RSG-Clothing] Item removed: ' .. itemData.name)
            CreateThread(function()
                Wait(100)
                TriggerServerEvent('rsg-clothing:server:checkInventorySync')
            end)
        end
    end
end)

-- Хук на ox_inventory (если используется)
RegisterNetEvent('ox_inventory:updateInventory', function(changes)
    local needCheck = false
    
    if changes then
        for _, change in ipairs(changes) do
            if change and change.name and IsClothingItem(change.name) then
                needCheck = true
                break
            end
        end
    end
    
    if needCheck then
        CreateThread(function()
            Wait(100)
            TriggerServerEvent('rsg-clothing:server:checkInventorySync')
        end)
    end
end)

-- Хук на выброс предмета
RegisterNetEvent('inventory:client:ItemDropped', function(item)
    if item and item.name and IsClothingItem(item.name) then
        print('[RSG-Clothing] Item dropped: ' .. item.name)
        CreateThread(function()
            Wait(100)
            TriggerServerEvent('rsg-clothing:server:checkInventorySync')
        end)
    end
end)

-- Универсальный хук на обновление инвентаря
RegisterNetEvent('inventory:refresh', function()
    CreateThread(function()
        Wait(250)
        TriggerServerEvent('rsg-clothing:server:checkInventorySync')
    end)
end)

-- Debug команда для клиента
RegisterCommand('debugclothes', function()
    print('=== CLOTHES CACHE (CLIENT) ===')
    for category, data in pairs(ClothesCache) do
        print(category, json.encode(data))
    end
end, false)

-- Команда для принудительной проверки
RegisterCommand('checkclothes', function()
    TriggerServerEvent('rsg-clothing:server:checkInventorySync')
    TriggerEvent('ox_lib:notify', {
        title = 'Одежда',
        description = 'Проверка синхронизации...',
        type = 'info'
    })
end, false)

print('[RSG-Clothing] Inventory hooks registered')


function MenuUpdateClothes(data, menu)
    if data.current.change_type == "model" then
        if ClothesCache[data.current.category].model ~= data.current.value then
            ClothesCache[data.current.category].texture = 1
            ClothesCache[data.current.category].model = data.current.value
            if data.current.value > 0 then
                menu.setElement(data.current.id + 1, "max", GetMaxTexturesForModel(data.current.category, data.current.value, true))
                menu.setElement(data.current.id + 1, "min", 1)
                menu.setElement(data.current.id + 1, "value", 1)
                menu.refresh()
                Change(data.current.value, data.current.category, data.current.change_type)
            else
                if data.current.category == 'cloaks' then
                    data.current.category = 'ponchos'
                end
                Citizen.InvokeNative(0xD710A5007C2AC539, PlayerPedId(), GetHashKey(data.current.category), 0)
                NativeUpdatePedVariation(PlayerPedId(), true)
				SetTimeout(300, function()
					pcall(function()
					exports['rsg-appearance']:CheckAndApplyNakedBodyIfNeeded(PlayerPedId())
					end)
				end)
                menu.setElement(data.current.id + 1, "max", 0)
                menu.setElement(data.current.id + 1, "min", 0)
                menu.setElement(data.current.id + 1, "value", 0)
                menu.refresh()
            end
            -- ✅ ПЕРЕСЧЕТ ЦЕНЫ НАПРЯМУЮ
            if not (IsInCharCreation or Skinkosong) then
                CurrentPrice = CalculatePrice(ClothesCache, OldClothesCache, IsPedMale(PlayerPedId()))
            end
        end
    end
    if data.current.change_type == "texture" then
        if ClothesCache[data.current.category].texture ~= data.current.value then
            ClothesCache[data.current.category].texture = data.current.value
            Change(data.current.value, data.current.category, data.current.change_type)
            -- ✅ ПЕРЕСЧЕТ ЦЕНЫ НАПРЯМУЮ
            if not (IsInCharCreation or Skinkosong) then
                CurrentPrice = CalculatePrice(ClothesCache, OldClothesCache, IsPedMale(PlayerPedId()))
            end
        end
    end
end
-- ==========================================
-- РАСЧЕТ ЦЕНЫ (МОДЕЛЬ + ТЕКСТУРА)
-- ==========================================

function CalculatePrice(newClothes, oldClothes, isMale)
    local totalPrice = 0
    
    if not newClothes then return 0 end
    if not oldClothes then oldClothes = {} end
    if not RSG or not RSG.Price then return 0 end
    
    for category, newData in pairs(newClothes) do
        if type(newData) == "table" then
            local newModel = newData.model
            local newTexture = newData.texture or 1
            
            -- Пропускаем если модель 0 или nil
            if not newModel or newModel < 1 then
                goto continue
            end
            
            local oldData = oldClothes[category]
            local isNewItem = false
            
            if not oldData or type(oldData) ~= "table" then
                isNewItem = true
            elseif not oldData.model or oldData.model < 1 then
                isNewItem = true
            elseif newModel ~= oldData.model then
                isNewItem = true
            elseif newTexture ~= (oldData.texture or 1) then
                isNewItem = true
            end
            
            if isNewItem then
                local itemPrice = nil
                
                -- Пробуем найти цену для конкретной модели+текстуры
                if RSG.ItemPrices and RSG.ItemPrices[category] and RSG.ItemPrices[category][newModel] then
                    itemPrice = RSG.ItemPrices[category][newModel][newTexture]
                end
                
                -- Если не найдено - берем цену категории
                if not itemPrice then
                    itemPrice = RSG.Price[category] or 5
                end
                
                totalPrice = totalPrice + itemPrice
            end
            
            ::continue::
        end
    end
    
    return totalPrice
end

function ConvertCacheToHash(cache)
    if not cache then 
        return {} 
    end
    
    local result = {}
    for category, data in pairs(cache) do
        if type(data) == "table" then
            -- Создаем копию данных
            result[category] = {
                hash = data.hash or 0,
                model = data.model or 0,
                texture = data.texture or 1
            }
        end
    end
    return result
end


function Change(id, category, change_type)
    local ped = PlayerPedId()
    local isMale = IsPedMale(ped)
    local gender = isMale and "male" or "female"
    
    -- Проверяем конфликтующие категории
    if ConflictingCategories[category] then
        local conflictCategory = ConflictingCategories[category]
        Citizen.InvokeNative(0xD710A5007C2AC539, ped, GetHashKey(conflictCategory), 0)
        
        if ClothesCache[conflictCategory] then
            ClothesCache[conflictCategory].model = 0
            ClothesCache[conflictCategory].texture = 1
            ClothesCache[conflictCategory].hash = 0
        end
    end
    
    local hashToApply = nil
    
    if change_type == "model" then
        if clothing[gender][category] and clothing[gender][category][id] then
            hashToApply = clothing[gender][category][id][1].hash
            -- Обновляем кэш
            ClothesCache[category] = {
                model = id,
                texture = 1,
                hash = hashToApply
            }
        end
    else
        if clothing[gender][category] and 
           ClothesCache[category] and 
           clothing[gender][category][ClothesCache[category].model] and
           clothing[gender][category][ClothesCache[category].model][id] then
            hashToApply = clothing[gender][category][ClothesCache[category].model][id].hash
            ClothesCache[category].texture = id
            ClothesCache[category].hash = hashToApply
        end
    end
    
    if hashToApply then
        -- ВАЖНО: Сначала проверяем тело
        EnsureBodyIntegrity(ped, false)
        
        Wait(50)
        
        -- Затем применяем одежду
        NativeSetPedComponentEnabledClothes(ped, hashToApply, false, true, true)
        NativeUpdatePedVariation(ped, true)
        
        -- Проверяем ещё раз
        Wait(100)
        EnsureBodyIntegrity(ped, false)
    end
end

function ClothingLight()
    while ClothingCamera do
        Wait(0)
        TogglePrompts({ "TURN_LR", "CAM_UD", "ZOOM_IO" }, true)
        if IsControlPressed(2, RSGCore.Shared.Keybinds['D']) then
            SetEntityHeading(PlayerPedId(), GetEntityHeading(PlayerPedId()) + 2)
        end
        if IsControlPressed(2, RSGCore.Shared.Keybinds['A']) then
            SetEntityHeading(PlayerPedId(), GetEntityHeading(PlayerPedId()) - 2)
        end
        if IsControlPressed(2, 0x8BDE7443) then
            if c_zoom + 0.25 < 2.5 and c_zoom + 0.25 > 0.7 then
                c_zoom = c_zoom + 0.25
                camera(c_zoom, c_offset)
            end
        end
        if IsControlPressed(2, 0x62800C92) then
            if c_zoom - 0.25 < 2.5 and c_zoom - 0.25 > 0.7 then
                c_zoom = c_zoom - 0.25
                camera(c_zoom, c_offset)
            end
        end
        if IsControlPressed(2, RSGCore.Shared.Keybinds['W']) then
            if c_offset + 0.5 / 7 < 1.2 and c_offset + 0.5 / 7 > -1.0 then
                c_offset = c_offset + 0.5 / 7
                camera(c_zoom, c_offset)
            end
        end
        if IsControlPressed(2, RSGCore.Shared.Keybinds['S']) then
            if c_offset - 0.5 / 7 < 1.2 and c_offset - 0.5 / 7 > -1.0 then
                c_offset = c_offset - 0.5 / 7
                camera(c_zoom, c_offset)
            end
        end
    end
end

-- ★ FIX: Переприменение аксессуаров на голову при смене причёски (женщины) — цветы и т.д. зависят от причёски
AddEventHandler('rsg-appearance:client:ReapplyHairAccessories', function(ped)
    CreateThread(function()
        ped = ped or PlayerPedId()
        if not ped or not DoesEntityExist(ped) then return end
        if IsPedMale(ped) then return end
        if not ClothesCache or not ClothesCache['hair_accessories'] or not ClothesCache['hair_accessories'].hash or ClothesCache['hair_accessories'].hash == 0 then return end
        Wait(150) -- даём причёске обновиться
        ped = ped or PlayerPedId()
        if not DoesEntityExist(ped) then return end
        local h = ClothesCache['hair_accessories'].hash
        Citizen.InvokeNative(0xD710A5007C2AC539, ped, 0x79D7DF96, 0) -- снимаем слот accessories
        Wait(80)
        Citizen.InvokeNative(0x59BD177A1A48600A, ped, h)
        NativeSetPedComponentEnabledClothes(ped, h, true, true, true)
        Citizen.InvokeNative(0x704C908E9C405136, ped)
        Citizen.InvokeNative(0xCC8CA3E88256E58F, ped, false, true, true, true, false)
    end)
end)

RegisterNetEvent('rsg-appearance:client:ApplyClothes')
AddEventHandler('rsg-appearance:client:ApplyClothes', function(ClothesComponents, Target, SkinData)
    CreateThread(function()
        local _Target = Target or PlayerPedId()
        -- ★ FIX: ClothesCache — только для своего педа! При синке других игроков НЕ перезаписываем,
        -- иначе при анимациях/релоаде на игроке появляется одежда от ближайшего синкнутого игрока
        local isOwnPed = (_Target == PlayerPedId())
        
        print('[RSG-Clothing] ApplyClothes called' .. (isOwnPed and ' (own ped)' or ' (other player sync)'))
        print('[RSG-Clothing] ClothesComponents type: ' .. type(ClothesComponents))
        
        if type(ClothesComponents) ~= "table" or next(ClothesComponents) == nil then 
            print('[RSG-Clothing] ApplyClothes: No clothes data!')
            return 
        end
        
        -- Логируем что пришло
        for k, v in pairs(ClothesComponents) do
            if type(v) == 'table' then
                print('[RSG-Clothing] Category ' .. k .. ': hash=' .. tostring(v.hash) .. ' model=' .. tostring(v.model) .. ' texture=' .. tostring(v.texture) .. ' palette=' .. tostring(v.palette))
            else
                print('[RSG-Clothing] Category ' .. k .. ': ' .. tostring(v))
            end
        end
        
        SetEntityAlpha(_Target, 0)
        
        local isMale = IsPedMale(_Target)
        local genderKey = isMale and 'male' or 'female'
        
        -- ★ ФИКС: Сначала резолвим все хеши, потом применяем В ПРАВИЛЬНОМ ПОРЯДКЕ
        local resolvedComponents = {}
        
        for k, v in pairs(ClothesComponents) do
            if v ~= nil and v ~= 0 then
                if type(v) ~= "table" then 
                    v = { hash = v }
                end
                
                local hashToApply = nil
                
                -- ПРИОРИТЕТ 1: Если есть hash и он не 0, используем его напрямую
                if v.hash and v.hash ~= 0 then
                    hashToApply = v.hash
                    print('[RSG-Clothing] Using direct hash for ' .. k .. ': ' .. tostring(hashToApply))
                    
                -- ПРИОРИТЕТ 2: Получаем hash из clothing.lua по model/texture
                elseif v.model and tonumber(v.model) and tonumber(v.model) >= 1 then
                    local model = tonumber(v.model)
                    local texture = tonumber(v.texture) or 1
                    -- ★ FIX: Для женских hair_accessories — модель = текущая причёска (аксессуары зависят от причёски)
                    if k == 'hair_accessories' and not isMale and SkinData and SkinData.hair and type(SkinData.hair) == 'table' then
                        local hairModel = tonumber(SkinData.hair.model) or 1
                        if hairModel >= 1 and clothing[genderKey] and clothing[genderKey][k] and clothing[genderKey][k][hairModel] then
                            model = hairModel
                        end
                    end
                    -- Сначала пробуем из clothing таблицы
                    if clothing[genderKey] and clothing[genderKey][k] then
                        if clothing[genderKey][k][model] then
                            if clothing[genderKey][k][model][texture] then
                                hashToApply = clothing[genderKey][k][model][texture].hash
                                print('[RSG-Clothing] Got hash from clothing[' .. genderKey .. '][' .. k .. '][' .. model .. '][' .. texture .. '] = ' .. tostring(hashToApply))
                            elseif clothing[genderKey][k][model][1] then
                                -- Если текстура не найдена, берём первую
                                hashToApply = clothing[genderKey][k][model][1].hash
                                print('[RSG-Clothing] Got hash from clothing[' .. genderKey .. '][' .. k .. '][' .. model .. '][1] (fallback) = ' .. tostring(hashToApply))
                            end
                        elseif k == 'hair_accessories' and clothing[genderKey][k][1] then
                            -- Fallback: hair_accessories может иметь только model 1 — используем texture как стиль
                            if clothing[genderKey][k][1][texture] then
                                hashToApply = clothing[genderKey][k][1][texture].hash
                            elseif clothing[genderKey][k][1][1] then
                                hashToApply = clothing[genderKey][k][1][1].hash
                            end
                        end
                    end
                    
                    -- Fallback на GetHashFromModel (который теперь тоже использует clothing.lua)
                    if not hashToApply then
                        hashToApply = GetHashFromModel(k, model, texture, isMale)
                        print('[RSG-Clothing] Got hash from GetHashFromModel for ' .. k .. ': ' .. tostring(hashToApply))
                    end
                end
                
                if hashToApply and hashToApply ~= 0 then
                    resolvedComponents[k] = {
                        hash = hashToApply,
                        model = v.model or 0,
                        texture = v.texture or 0,
                        palette = v.palette or 'tint_generic_clean',
                        tints = v.tints or {0, 0, 0}
                    }
                else
                    print('[RSG-Clothing] WARNING: No hash found for ' .. k)
                end
            end
        end
        
        -- ★ Применяем В ПРАВИЛЬНОМ ПОРЯДКЕ с промежуточными Finalize+Update
        local lowerOrder = {'pants', 'skirts', 'dresses'}
        local upperOrder = {'shirts_full', 'vests', 'coats', 'coats_closed'}
        local lateOrder = {'boots', 'boot_accessories', 'spurs', 'chaps', 'spats'}
        local applied = {}
        local phaseCount = 0
        
        -- Фаза 1: Нижнее тело
        phaseCount = 0
        for _, cat in ipairs(lowerOrder) do
            if resolvedComponents[cat] then
                NativeSetPedComponentEnabledClothes(_Target, resolvedComponents[cat].hash, false, true, true)
                if isOwnPed then ClothesCache[cat] = resolvedComponents[cat] end
                applied[cat] = true
                phaseCount = phaseCount + 1
            end
        end
        if phaseCount > 0 then
            NativeUpdatePedVariation(_Target, true)
            Wait(100)
        end
        
        -- Фаза 2: Верхнее тело
        phaseCount = 0
        for _, cat in ipairs(upperOrder) do
            if resolvedComponents[cat] then
                NativeSetPedComponentEnabledClothes(_Target, resolvedComponents[cat].hash, false, true, true)
                if isOwnPed then ClothesCache[cat] = resolvedComponents[cat] end
                applied[cat] = true
                phaseCount = phaseCount + 1
            end
        end
        if phaseCount > 0 then
            NativeUpdatePedVariation(_Target, true)
            Wait(100)
        end
        
        -- Фаза 3: Всё остальное (кроме обуви)
        phaseCount = 0
        for k, data in pairs(resolvedComponents) do
            if not applied[k] then
                local isLate = false
                for _, lc in ipairs(lateOrder) do
                    if k == lc then isLate = true break end
                end
                if not isLate then
                    NativeSetPedComponentEnabledClothes(_Target, data.hash, false, true, true)
                    if isOwnPed then ClothesCache[k] = data end
                    applied[k] = true
                    phaseCount = phaseCount + 1
                end
            end
        end
        if phaseCount > 0 then
            NativeUpdatePedVariation(_Target, true)
            Wait(100)
        end
        
        -- Фаза 4: Обувь ПОСЛЕДНЕЙ (поверх штанов)
        phaseCount = 0
        for _, cat in ipairs(lateOrder) do
            if resolvedComponents[cat] and not applied[cat] then
                NativeSetPedComponentEnabledClothes(_Target, resolvedComponents[cat].hash, false, true, true)
                if isOwnPed then ClothesCache[cat] = resolvedComponents[cat] end
                applied[cat] = true
                phaseCount = phaseCount + 1
            end
        end
        if phaseCount > 0 then
            NativeUpdatePedVariation(_Target, true)
            Wait(100)
        end
        
        -- ПРИМЕНЯЕМ ЦВЕТА ПОСЛЕ ВСЕХ ХЕШЕЙ!
        for k, v in pairs(ClothesComponents) do
            if type(v) == 'table' and v.palette and v.tints then
                -- ★ ФИКС: Для Classic одежды НЕ применяем tint - цвет уже в hash!
                -- Если kaf="Classic" или kaf=nil (старые данные) с нулевыми tints - пропускаем
                local isClassic = (v.kaf == "Classic") or (v.kaf == nil and (not v.tints[1] or v.tints[1] == 0) and (not v.tints[2] or v.tints[2] == 0) and (not v.tints[3] or v.tints[3] == 0))
                local isPedCoatCategory = IsPedCoatItem(k, v)
                
                if isClassic and not isPedCoatCategory then
                    print('[RSG-Clothing] Skipping tint for ' .. k .. ' (Classic - color is in hash)')
                elseif isPedCoatCategory or
                   v.palette ~= 'tint_generic_clean' or 
                   (v.tints[1] and v.tints[1] > 0) or 
                   (v.tints[2] and v.tints[2] > 0) or 
                   (v.tints[3] and v.tints[3] > 0) then
                    ApplyClothingColor(_Target, k, v.palette, v.tints)
                    print('[RSG-Clothing] Applied color for ' .. k .. ': palette=' .. v.palette)
                    Wait(50)
                end
            end
        end
        
        SetEntityAlpha(_Target, 255)
        
        -- ★ FIX: Переприменяем hair_accessories для женщин (цветы и т.д. зависят от причёски)
        -- Только для своего педа — ReapplyHairAccessories использует ClothesCache
        if isOwnPed and not isMale and resolvedComponents['hair_accessories'] and resolvedComponents['hair_accessories'].hash and resolvedComponents['hair_accessories'].hash ~= 0 then
            SetTimeout(200, function()
                TriggerEvent('rsg-appearance:client:ReapplyHairAccessories', _Target)
            end)
        end
        
        -- ★ Сигнал creator.lua, что одежда полностью применена (до применения BodyMorph)
        if isOwnPed then
            _G._ApplyClothesComplete = true
            TriggerEvent('rsg-appearance:client:ApplyClothesComplete', _Target, SkinData)
        end
        
        -- ★ После одежды и цветов морф тела сбрасывается — переприменяем body morph в самом конце
        if ReapplyBodyMorph then ReapplyBodyMorph(_Target) end
        NativeUpdatePedVariation(_Target, true)
        
        print('[RSG-Clothing] ApplyClothes completed with colors')
    end)
end)

function destory()
    OldClothesCache = {}
    SetCamActive(ClothingCamera, false)
    RenderScriptCams(false, true, 500, true, true)
    DisplayHud(true)
    DisplayRadar(true)
    DestroyAllCams(true)
    ClothingCamera = nil
    playerHeading = nil
    Citizen.InvokeNative(0x4D51E59243281D80, PlayerId(), true, 0, false)
end

function TeleportAndFade(coords4, resetCoords)
    DoScreenFadeOut(500)
    Wait(1000)
    Citizen.InvokeNative(0x203BEFFDBE12E96A, PlayerPedId(), coords4)
    SetEntityCoordsNoOffset(PlayerPedId(), coords4, true, true, true)
    LocalPlayer.state.inClothingStore = true
    Wait(1500)
    DoScreenFadeIn(1800)
    if resetCoords then
        CurentCoords = {}
        TogglePrompts({ "TURN_LR", "CAM_UD", "ZOOM_IO" }, false)
        LocalPlayer.state.inClothingStore = false
        TriggerServerEvent('rsg-appearance:server:SetPlayerBucket', 0)
    end
end

function camera(zoom, offset)
    local playerPed = PlayerPedId()
    local coords = GetEntityCoords(playerPed)
    local angle
    if playerHeading == nil then
        playerHeading = GetEntityHeading(playerPed)
    end
    angle = playerHeading * math.pi / 180.0
    local pos = {
        x = coords.x - (zoom * math.sin(angle)),
        y = coords.y + (zoom * math.cos(angle)),
        z = coords.z + offset
    }
    if not ClothingCamera then
        DestroyAllCams(true)
        ClothingCamera = CreateCamWithParams("DEFAULT_SCRIPTED_CAMERA", pos.x, pos.y, pos.z, 300.00, 0.00, 0.00, 50.00, false, 0)
        PointCamAtCoord(ClothingCamera, coords.x, coords.y, coords.z + offset)
        SetCamActive(ClothingCamera, true)
        RenderScriptCams(true, true, 1000, true, true)
        DisplayRadar(false)
    else
        local ClothingCamera2 = CreateCamWithParams("DEFAULT_SCRIPTED_CAMERA", pos.x, pos.y, pos.z, 300.00, 0.00, 0.00, 50.00, false, 0)
        SetCamActive(ClothingCamera2, true)
        SetCamActiveWithInterp(ClothingCamera2, ClothingCamera, 750)
        PointCamAtCoord(ClothingCamera2, coords.x, coords.y, coords.z + offset)
        Wait(150)
        SetCamActive(ClothingCamera, false)
        DestroyCam(ClothingCamera)
        ClothingCamera = ClothingCamera2
    end
end

function Outfits()
    MenuData.CloseAll()
    local Result = lib.callback.await('rsg-appearance:server:getOutfits', false)
    local elements_outfits = {}
    for k, v in pairs(Result) do
        elements_outfits[#elements_outfits + 1] = {
            name = v.name,
            label = '#' .. k .. '. ' .. v.name,
            value = v.clothes,
            desc = RSG.Label.choose
        }
    end
    MenuData.Open('default', GetCurrentResourceName(), 'outfits_menu',
        {title = RSG.Label.clothes, subtext = RSG.Label.choose, align = 'top-left', elements = elements_outfits, itemHeight = "4vh"},
        function(data, menu)
            OutfitsManage(data.current.value, data.current.name)
        end, function(data, menu)
            menu.close()
        end)
end

function OutfitsManage(outfit, id)
    MenuData.CloseAll()
    local elements_outfits_manage = {
        {label = RSG.Label.wear, value = "SetOutfits", desc = RSG.Label.wear_desc},
        {label = RSG.Label.delete, value = "DeleteOutfit", desc = RSG.Label.delete_desc}
    }
    MenuData.Open('default', GetCurrentResourceName(), 'outfits_menu_manage',
        {title = RSG.Label.clothes, subtext = RSG.Label.options, align = 'top-left', elements = elements_outfits_manage, itemHeight = "4vh"}, function(data, menu)
            menu.close()
        if data.current.value == 'SetOutfits' then
            TriggerEvent('rsg-appearance:client:ApplyClothes', outfit, PlayerPedId())
            TriggerServerEvent('rsg-appearance:server:saveUseOutfit', ConvertCacheToHash(outfit))
        end
        if data.current.value == 'DeleteOutfit' then
            TriggerServerEvent('rsg-appearance:server:DeleteOutfit', id)
        end
    end, function(data, menu)
        Outfits()
    end)
end

RegisterNetEvent('rsg-appearance:client:outfits', function() Outfits() end)

local Cloakroom = GetRandomIntInRange(0, 0xffffff)

function OpenCloakroom()
    local str = locale('cloack_room_prompt_button')
    CloakPrompt = PromptRegisterBegin()
    PromptSetControlAction(CloakPrompt, RSG.OpenKey)
    PromptSetText(CloakPrompt, CreateVarString(10, 'LITERAL_STRING', str))
    PromptSetEnabled(CloakPrompt, true)
    PromptSetVisible(CloakPrompt, true)
    PromptSetHoldMode(CloakPrompt, true)
    PromptSetGroup(CloakPrompt, Cloakroom)
    PromptRegisterEnd(CloakPrompt)
end

CreateThread(function()
    OpenCloakroom()
    while true do
        Wait(5)
        local sleep = true
        local coords = GetEntityCoords(PlayerPedId())
        for _, v in pairs(RSG.Cloakroom) do
            if #(coords - v) < 2.0 then
                sleep = false
                PromptSetActiveGroupThisFrame(Cloakroom, CreateVarString(10, 'LITERAL_STRING', RSG.Cloakroomtext))
                if PromptHasHoldModeCompleted(CloakPrompt) then
                    Outfits()
                    break
                end
            end
        end
        if sleep then Wait(1500) end
    end
end)

function GenerateMenu()
    TriggerEvent('rsg-horses:client:FleeHorse')
    TeleportAndFade(CurentCoords.fittingcoords, false)
    TriggerServerEvent('rsg-appearance:server:SetPlayerBucket', 0, true)
    
    local ClothesComponents = lib.callback.await('rsg-appearance:server:LoadClothes', false)
    ClothesCache = hashToCache.PopulateClothingCache(ClothesComponents, IsPedMale(PlayerPedId()))
    
    -- Загружаем одежду из инвентаря
    RSGCore.Functions.TriggerCallback('rsg-clothing:server:getInventoryClothing', function(inventoryClothes)
        OldClothesCache = inventoryClothes or {}
        CurrentPrice = 0
        
        camera(2.4, -0.15)
        CreateThread(ClothingLight)
        OpenClothingMenu()
    end)
end

CreateThread(function()
    LocalPlayer.state.inClothingStore = false
    CreateBlips()
    if RegisterPrompts() then
        while true do
            local room = GetClosestConsumer()
            if room then
                if not PromptsEnabled then TogglePrompts({ "OPEN_CLOTHING_MENU" }, true) end
                if PromptsEnabled and IsPromptCompleted("OPEN_CLOTHING_MENU") then
                    Citizen.InvokeNative(0x4D51E59243281D80, PlayerId(), false, 0, true)
                    GenerateMenu()
                end
            else
                if PromptsEnabled then TogglePrompts({ "OPEN_CLOTHING_MENU" }, false) end
                Wait(250)
            end
            Wait(100)
        end
    end
end)

function GetClosestConsumer()
    local coords = GetEntityCoords(PlayerPedId())
    for _,data in pairs(RSG.Zones1) do
        if (data.promtcoords and #(coords - data.promtcoords) < 1.0) or (data.epromtcoords and #(coords - data.epromtcoords) < 1.0) then
            CurentCoords = data
            return true
        end
    end
    return false
end

function RegisterPrompts()
    local newTable = {}
    for i=1, #RSG.Prompts do
        local prompt = Citizen.InvokeNative(0x04F97DE45A519419, Citizen.ResultAsInteger())
        Citizen.InvokeNative(0x5DD02A8318420DD7, prompt, CreateVarString(10, "LITERAL_STRING", RSG.Prompts[i].label))
        Citizen.InvokeNative(0xB5352B7494A08258, prompt, RSG.Prompts[i].control or RSGCore.Shared.Keybinds[RSG.Keybind])
        if RSG.Prompts[i].control2 then
            Citizen.InvokeNative(0xB5352B7494A08258, prompt, RSG.Prompts[i].control2)
        end
        Citizen.InvokeNative(0x94073D5CA3F16B7B, prompt, RSG.Prompts[i].time or 1000)
        if RSG.Prompts[i].control then
            Citizen.InvokeNative(0x2F11D3A254169EA4, prompt, RoomPrompts)
        end
        Citizen.InvokeNative(0xF7AA2696A22AD8B9, prompt)
        Citizen.InvokeNative(0x8A0FB4D03A630D21, prompt, false)
        Citizen.InvokeNative(0x71215ACCFDE075EE, prompt, false)
        table.insert(RSG.CreatedEntries, { type = "PROMPT", handle = prompt })
        newTable[RSG.Prompts[i].id] = prompt
    end
    RSG.Prompts = newTable
    return true
end

function TogglePrompts(data, state)
    for index,prompt in pairs((data ~= "ALL" and data) or RSG.Prompts) do
        if RSG.Prompts[(data ~= "ALL" and prompt) or index] then
            Citizen.InvokeNative(0x8A0FB4D03A630D21, (data ~= "ALL" and RSG.Prompts[prompt]) or prompt, state)
            Citizen.InvokeNative(0x71215ACCFDE075EE, (data ~= "ALL" and RSG.Prompts[prompt]) or prompt, state)
        end
    end
    PromptSetActiveGroupThisFrame(RoomPrompts, CreateVarString(10, 'LITERAL_STRING', RSG.Label.shop.. ' - ~t6~'..CurrentPrice..'$'))
    PromptsEnabled = state
end

function IsPromptCompleted(name)
    return RSG.Prompts[name] and Citizen.InvokeNative(0xE0F65F0640EF0617, RSG.Prompts[name])
end

function CreateBlips()
    for _, coordsList in pairs(RSG.Zones1) do
        if #coordsList.blipcoords > 0 and coordsList.showblip then
            local blip = Citizen.InvokeNative(0x554D9D53F696D002, 1664425300, coordsList.blipcoords)
            SetBlipSprite(blip, RSG.BlipSprite, 1)
            SetBlipScale(blip, RSG.BlipScale)
            Citizen.InvokeNative(0x9CB1A1623062F402, blip, RSG.BlipName)
            table.insert(RSG.CreatedEntries, { type = "BLIP", handle = blip })
        end
    end
    for _, v in pairs(RSG.Cloakroom) do
        local blip = Citizen.InvokeNative(0x554D9D53F696D002, 1664425300, v)
        SetBlipSprite(blip, RSG.BlipSpriteCloakRoom, 1)
        SetBlipScale(blip, RSG.BlipScale)
        Citizen.InvokeNative(0x9CB1A1623062F402, blip, RSG.BlipNameCloakRoom)
        table.insert(RSG.CreatedEntries, { type = "BLIP", handle = blip })
    end
end
-- ==========================================
-- ФОНОВЫЙ МОНИТОРИНГ ЦЕЛОСТНОСТИ ТЕЛА
-- ==========================================

local bodyIntegrityMonitorEnabled = true

CreateThread(function()
    Wait(5000) -- Ждём загрузки
    
    while bodyIntegrityMonitorEnabled do
        Wait(3000) -- Проверяем каждые 3 секунды
        
        -- ★ FIX: Пропускаем проверку 6 сек после загрузки одежды — Avoid flicker
        if lastClothingLoadTime > 0 and (GetGameTimer() - lastClothingLoadTime) < 6000 then
            goto continue_body_monitor
        end
        
        local ped = PlayerPedId()
        if DoesEntityExist(ped) and not IsEntityDead(ped) then
            -- Тихая проверка без принудительного обновления
            local hadChanges = EnsureBodyIntegrity(ped, false)
            if hadChanges then
            end
        end
        ::continue_body_monitor::
    end
end)

-- Команда для отключения мониторинга (для отладки)
RegisterCommand('togglebodymonitor', function()
    bodyIntegrityMonitorEnabled = not bodyIntegrityMonitorEnabled
    print('[BodyMonitor] ' .. (bodyIntegrityMonitorEnabled and 'Enabled' or 'Disabled'))
end, false)

RegisterCommand('fixbody', function()
    local ped = PlayerPedId()
    
    print('=== FIXING BODY ===')
    print('Current ClothesCache:')
    for cat, data in pairs(ClothesCache or {}) do
        if type(data) == 'table' then
            print('  ' .. cat .. ': model=' .. tostring(data.model) .. ', hash=0x' .. string.format("%X", data.hash or 0))
        end
    end
    
    -- Принудительно восстанавливаем обе части тела
    local upperHash = GetBodyHash("BODIES_UPPER") or 0
    local lowerHash = GetBodyHash("BODIES_LOWER") or 0
    
    print('Upper body hash: 0x' .. string.format("%X", upperHash))
    print('Lower body hash: 0x' .. string.format("%X", lowerHash))
    
    -- Применяем
    if upperHash ~= 0 then
        Citizen.InvokeNative(0x59BD177A1A48600A, ped, GetHashKey("bodies_upper"))
        Citizen.InvokeNative(0xD3A7B003ED343FD9, ped, upperHash, true, true, true)
    end
    
    if lowerHash ~= 0 then
        Citizen.InvokeNative(0x59BD177A1A48600A, ped, GetHashKey("bodies_lower"))
        Citizen.InvokeNative(0xD3A7B003ED343FD9, ped, lowerHash, true, true, true)
    end
    
    Wait(100)
    NativeUpdatePedVariation(ped, true)
    
    -- Теперь переодеваем всю одежду из кэша
    Wait(100)
    for cat, data in pairs(ClothesCache or {}) do
        if type(data) == 'table' and data.hash and data.hash ~= 0 then
            NativeSetPedComponentEnabledClothes(ped, data.hash, false, true, true)
            Wait(50)
        end
    end
    
    NativeUpdatePedVariation(ped, true)
    
    TriggerEvent('ox_lib:notify', {
        title = 'Body Fix',
        description = 'Части тела восстановлены',
        type = 'success'
    })
end, false)
AddEventHandler('onResourceStop', function(resourceName)
    if GetCurrentResourceName() ~= resourceName then return end
    LocalPlayer.state.inClothingStore = false
    destory()
    for i=1, #RSG.CreatedEntries do
        if RSG.CreatedEntries[i].type == "BLIP" then
            RemoveBlip(RSG.CreatedEntries[i].handle)
        elseif RSG.CreatedEntries[i].type == "PROMPT" then
            Citizen.InvokeNative(0x00EDE88D4D13CF59, RSG.CreatedEntries[i].handle)
            PromptsEnabled = false
        end
    end
end)

RegisterNetEvent('rsg-appearance:client:LoadClothesAfterSkin', function()
    Wait(500)
    LoadClothingFromInventory()
end)

RegisterNetEvent('rsg-appearance:client:ApplyClothesAfterRespawn', function()
    Wait(1000)
    LoadClothingFromInventory()
end)

-- ★ loadcharacter: ExecuteCommand с клиента не триггерит серверные команды — используем TriggerServerEvent
RegisterCommand('loadcharacter', function()
    TriggerServerEvent('rsg-appearance:server:LoadCharacter')
end, false)

-- fixcharacter — алиас для loadcharacter (радиальный меню и т.п.)
RegisterCommand('fixcharacter', function()
    TriggerServerEvent('rsg-appearance:server:LoadCharacter')
end, false)

RegisterCommand('checkstructure', function()
    print('=== CHECKING CLOTHESCACHE STRUCTURE ===')
    
    if not ClothesCache then
        print('ClothesCache is nil!')
        return
    end
    
    for category, data in pairs(ClothesCache) do
        print('\nCategory: ' .. category)
        print('  Type: ' .. type(data))
        
        if type(data) == 'table' then
            print('  Keys in table:')
            for key, value in pairs(data) do
                print('    [' .. tostring(key) .. '] = ' .. tostring(value) .. ' (type: ' .. type(value) .. ')')
            end
        else
            print('  Value: ' .. tostring(data))
        end
    end
    
    print('\n=== TESTING CONVERT ===')
    local first = next(ClothesCache)
    if first then
        local v = ClothesCache[first]
        print('Testing ' .. first .. ':')
        print('  v = ' .. tostring(v))
        print('  v.model = ' .. tostring(v.model))
        print('  v["model"] = ' .. tostring(v["model"]))
        print('  rawget(v, "model") = ' .. tostring(rawget(v, "model")))
    end
end, false)
RegisterCommand('shopdebug', function()
    print('=== SHOP DEBUG ===')
    print('CurrentPrice: $' .. tostring(CurrentPrice))
    
    print('\nClothesCache (текущий выбор):')
    if not ClothesCache or next(ClothesCache) == nil then
        print('  ПУСТО!')
    else
        for cat, data in pairs(ClothesCache) do
            if type(data) == 'table' and data.model and data.model > 0 then
                print('  ' .. cat .. ': model=' .. tostring(data.model) .. ', texture=' .. tostring(data.texture or 1))
            end
        end
    end
    
    print('\nOldClothesCache (что есть в инвентаре):')
    if not OldClothesCache or next(OldClothesCache) == nil then
        print('  ПУСТО!')
    else
        for cat, data in pairs(OldClothesCache) do
            if type(data) == 'table' and data.model and data.model > 0 then
                print('  ' .. cat .. ': model=' .. tostring(data.model) .. ', texture=' .. tostring(data.texture or 1))
            end
        end
    end
    
    -- Пересчитываем цену
    local calcPrice = CalculatePrice(ClothesCache, OldClothesCache, IsPedMale(PlayerPedId()))
    print('\nПересчитанная цена: $' .. tostring(calcPrice))
end, false)
-- ==========================================
-- RSG-APPEARANCE PATCH: Сохранение цвета одежды
-- Добавьте этот код В КОНЕЦ файла clothes.lua
-- ==========================================

-- ★ ЭКСПОРТ: Переприменить сапоги и аксессуары ног из ClothesCache (штаны заправляются в сапоги)
exports('ReapplyBootsFromCache', function(ped)
    if not ped or not DoesEntityExist(ped) then ped = PlayerPedId() end
    if not ClothesCache then return end
    for _, cat in ipairs({'boots', 'boot_accessories', 'spurs', 'chaps', 'spats'}) do
        if ClothesCache[cat] and ClothesCache[cat].hash and ClothesCache[cat].hash ~= 0 then
            Citizen.InvokeNative(0x59BD177A1A48600A, ped, ClothesCache[cat].hash)
            NativeSetPedComponentEnabledClothes(ped, ClothesCache[cat].hash, false, true, true)
        end
    end
    Citizen.InvokeNative(0x704C908E9C405136, ped)
    Citizen.InvokeNative(0xCC8CA3E88256E58F, ped, false, true, true, true, false)
end)

-- ★ ЭКСПОРТ: Получить текущий hash категории одежды
exports('GetClothingCategoryHash', function(category)
    if ClothesCache and ClothesCache[category] then
        return ClothesCache[category].hash or 0
    end
    return 0
end)

-- ★ ЭКСПОРТ: Получить palette/tints для категории
exports('GetClothingColorData', function(category)
    if ClothesCache and ClothesCache[category] then
        return {
            palette = ClothesCache[category].palette or 'tint_generic_clean',
            tints = ClothesCache[category].tints or {0, 0, 0}
        }
    end
    return nil
end)

-- ★ ЭКСПОРТ: Установить palette/tints для категории (и применить)
exports('SetClothingColorData', function(category, palette, tints)
    if ClothesCache and ClothesCache[category] then
        ClothesCache[category].palette = palette
        ClothesCache[category].tints = tints
        
        -- Применяем цвет
        ApplyClothingColor(PlayerPedId(), category, palette, tints)
        return true
    end
    return false
end)

-- ★ Восстановить цвета всей одежды из ClothesCache (после loadcharacter, UpdatePedVariation сбрасывает тинты)
function ApplyAllClothingColorsFromCache(ped)
    if not ped or not DoesEntityExist(ped) then ped = PlayerPedId() end
    if not ClothesCache then return end
    for category, data in pairs(ClothesCache) do
        if data and data.hash and data.hash ~= 0 and data.palette and ApplyClothingColor then
            ApplyClothingColor(ped, category, data.palette or 'tint_generic_clean', data.tints or {0, 0, 0})
        end
    end
end
exports('ApplyAllClothingColorsFromCache', ApplyAllClothingColorsFromCache)

-- ★ Переопределяем LoadClothingFromInventory чтобы читать цвет из инвентаря
-- (Если ваша функция называется иначе, замените имя)

local OriginalLoadClothingFromInventory = LoadClothingFromInventory

LoadClothingFromInventory = function(callback, options)
    -- ★ Не перезаписывать одежду когда игрок в магазине rsg-clothingstore (предпросмотр)
    if LocalPlayer.state.inClothingStore or LocalPlayer.state.isInClothingStore then
        if callback then callback(false) end
        return
    end
    options = options or {}
    -- ★ По умолчанию одеваем через equipClothing (как "снять/надеть из инвентаря") — юбка+обувь без просвечивания ног
    local useEquipPath = (options.useEquipPath == nil) and true or options.useEquipPath
    local isLightResyncPass = (activeInventoryResyncPasses or 0) > 0
    RSGCore.Functions.TriggerCallback('rsg-clothing:server:getEquippedClothing', function(equippedItems)
        local ped = PlayerPedId()
        
        -- ★ FIX: Снимаем дефолтную шляпу (кепка конфедерата) если в инвентаре нет надетой шляпы
        if not equippedItems or not equippedItems['hats'] then
            Citizen.InvokeNative(0xDF631E4BCE1B1FC4, ped, 0x9925C067)
            Citizen.InvokeNative(0x704C908E9C405136, ped)
            Citizen.InvokeNative(0xCC8CA3E88256E58F, ped, false, true, true, true, false)
            if ClothesCache then ClothesCache['hats'] = nil end
        end
        
        if not equippedItems or not next(equippedItems) then
            if callback then callback(false) end
            return
        end
        
        local count = 0
        local isMale = IsPedMale(ped)
        local genderKey = isMale and 'male' or 'female'
        
        -- Очищаем кэш
        ClothesCache = {}
        
        for category, data in pairs(equippedItems) do
            local hashToUse = nil
            
            -- Получаем hash
            if data.hash and data.hash ~= 0 then
                hashToUse = data.hash
            elseif data.model and data.model > 0 then
                local model = data.model
                local texture = data.texture or 1
                -- ★ FIX: Для женских hair_accessories — модель = текущая причёска (аксессуары зависят от причёски)
                if category == 'hair_accessories' and not isMale then
                    local hairInfo = exports['rsg-appearance']:GetComponentId('hair')
                    if hairInfo and type(hairInfo) == 'table' and hairInfo.model and hairInfo.model >= 1 and clothing[genderKey] and clothing[genderKey][category] and clothing[genderKey][category][hairInfo.model] then
                        model = hairInfo.model
                    end
                end
                if clothing[genderKey] and clothing[genderKey][category] then
                    if clothing[genderKey][category][model] then
                        if clothing[genderKey][category][model][texture] then
                            hashToUse = clothing[genderKey][category][model][texture].hash
                        elseif clothing[genderKey][category][model][1] then
                            hashToUse = clothing[genderKey][category][model][1].hash
                        end
                    elseif category == 'hair_accessories' and clothing[genderKey][category][1] then
                        if clothing[genderKey][category][1][texture] then
                            hashToUse = clothing[genderKey][category][1][texture].hash
                        elseif clothing[genderKey][category][1][1] then
                            hashToUse = clothing[genderKey][category][1][1].hash
                        end
                    end
                end
            end
            
            if hashToUse and hashToUse ~= 0 then
                -- ★ ВАЖНО: Сохраняем ВСЕ данные из инвентаря, включая kaf/draw/albedo/normal/material
                ClothesCache[category] = {
                    hash = hashToUse,
                    model = data.model or 0,
                    texture = data.texture or 0,
                    palette = data.palette or data._p or 'tint_generic_clean',
                    tints = data.tints or data._tints or {0, 0, 0},
                    kaf = data.kaf or data._kaf or "Classic",
                    _kaf = data._kaf or data.kaf or "Classic",
                    draw = data.draw or "",
                    albedo = data.albedo or "",
                    normal = data.normal or "",
                    material = data.material or 0,
                }
                
                print('[RSG-Clothing] Loaded: ' .. category .. ' kaf=' .. tostring(ClothesCache[category].kaf) .. ' palette=' .. tostring(ClothesCache[category].palette))
            end
        end
        
        -- Проверяем целостность тела
        EnsureBodyIntegrity(ped, true)
        Wait(100)
        
        -- ★ FIX naked_body после /pee /poo: Убираем naked overlay ДО применения штанов (как в equipClothing)
        local lowerBodyCats = {'pants', 'skirts', 'dresses'}
        local hasLowerToApply = false
        for _, cat in ipairs(lowerBodyCats) do
            if ClothesCache[cat] and ClothesCache[cat].hash and ClothesCache[cat].hash ~= 0 then
                hasLowerToApply = true
                break
            end
        end
        if hasLowerToApply and RemoveNakedLowerBody then
            RemoveNakedLowerBody(ped, true)
            Wait(50)
        end
        
        if useEquipPath then
            -- ★ loadcharacter: одеваем как игрок — каждый предмет через equipClothing (корсет на голом теле работает)
            -- ★ Vest/corset без рубашки: применяем naked overlay ДО vest (закрывает грудь)
            local hasVest = (ClothesCache['vests'] or ClothesCache['corsets']) and ((ClothesCache['vests'] and ClothesCache['vests'].hash and ClothesCache['vests'].hash ~= 0) or (ClothesCache['corsets'] and ClothesCache['corsets'].hash and ClothesCache['corsets'].hash ~= 0))
            local hasShirt = ClothesCache['shirts_full'] and ClothesCache['shirts_full'].hash and ClothesCache['shirts_full'].hash ~= 0
            local hasDress = ClothesCache['dresses'] and ClothesCache['dresses'].hash and ClothesCache['dresses'].hash ~= 0
            local hasCoat = (ClothesCache['coats'] and ClothesCache['coats'].hash and ClothesCache['coats'].hash ~= 0) or (ClothesCache['coats_closed'] and ClothesCache['coats_closed'].hash and ClothesCache['coats_closed'].hash ~= 0)
            if hasVest and not hasShirt and not hasDress and not hasCoat and not IsPedMale(ped) and ApplyNakedUpperBody then
                ApplyNakedUpperBody(ped, true)
                Wait(80)
            end
            -- ★ Детерминированный порядок (hats, neckties в основном списке) — pairs() ломал загрузку (шляпа/галстук раз через раз)
            local equipOrder = {'pants', 'skirts', 'dresses', 'shirts_full', 'neckwear', 'neckties', 'vests', 'corsets', 'coats', 'coats_closed', 'hats', 'gunbelts', 'belts', 'satchels', 'suspenders', 'gloves', 'eyewear', 'masks'}
            local lateOrder = {'boots', 'boot_accessories', 'spurs', 'chaps', 'spats'}
            -- ★ Увеличены паузы 350мс — equipClothing асинхронный, 180мс не хватало на завершение (перекрытие → пропажа шляпы/рубашки/галстука)
            for _, cat in ipairs(equipOrder) do
                if ClothesCache[cat] and ClothesCache[cat].hash and ClothesCache[cat].hash ~= 0 then
                    local itemData = { category = cat, isMale = isMale }
                    for k, v in pairs(ClothesCache[cat]) do itemData[k] = v end
                    TriggerEvent('rsg-clothing:client:equipClothing', itemData, { skipResync = true })
                    Wait(350)
                end
            end
            for _, cat in ipairs(lateOrder) do
                if ClothesCache[cat] and ClothesCache[cat].hash and ClothesCache[cat].hash ~= 0 then
                    local itemData = { category = cat, isMale = isMale }
                    for k, v in pairs(ClothesCache[cat]) do itemData[k] = v end
                    TriggerEvent('rsg-clothing:client:equipClothing', itemData, { skipResync = true })
                    Wait(300)
                end
            end
            for category, data in pairs(ClothesCache) do
                if data.hash and data.hash ~= 0 then
                    local alreadyDone = false
                    for _, c in ipairs(equipOrder) do if category == c then alreadyDone = true break end end
                    for _, c in ipairs(lateOrder) do if category == c then alreadyDone = true break end end
                    if not alreadyDone then
                        local itemData = { category = category, isMale = isMale }
                        for k, v in pairs(data) do itemData[k] = v end
                        TriggerEvent('rsg-clothing:client:equipClothing', itemData, { skipResync = true })
                        Wait(300)
                    end
                end
            end
            count = 0
            for _ in pairs(ClothesCache) do count = count + 1 end
            -- ★ Один раз UpdatePedVariation в конце. skipBodyMorph=true — не ломаем меш на полных
            if NativeUpdatePedVariation then NativeUpdatePedVariation(ped, true) end
        else
        -- ★ ФИКС: Надеваем одежду В ПРАВИЛЬНОМ ПОРЯДКЕ (штаны -> обувь)
        -- ★ С ПОДДЕРЖКОЙ PED-ТИПА: Ped-одежда применяется через draw/albedo/normal/material
        local priorityOrder2 = {'pants', 'skirts', 'dresses', 'shirts_full', 'vests', 'coats', 'coats_closed'}
        local lateOrder2 = {'boots', 'boot_accessories', 'spurs', 'chaps', 'spats'}
        local applied2 = {}
        -- ★ Сохраняем данные для re-equip нижняя одежда+обувь (жен.), чтобы к моменту SetTimeout(600) не опереться на перезаписанный ClothesCache
        local reequipSkirtBootsPayload = nil

        -- ★ Функция применения одного предмета (Classic или Ped)
        local function ApplyItem(cat, itemData)
            if itemData.kaf == "Ped" and itemData.draw and itemData.draw ~= "" then
                -- Ped-тип: применяем через draw/albedo/normal/material
                if itemData.draw ~= "" and itemData.draw ~= "_" then
                    local drawHash = GetHashKey(itemData.draw)
                    Citizen.InvokeNative(0x59BD177A1A48600A, ped, drawHash)
                    Citizen.InvokeNative(0xD3A7B003ED343FD9, ped, drawHash, true, true, true)
                end
                if itemData.albedo and itemData.albedo ~= "" then
                    local albHash = GetHashKey(itemData.albedo)
                    Citizen.InvokeNative(0x59BD177A1A48600A, ped, albHash)
                    Citizen.InvokeNative(0xD3A7B003ED343FD9, ped, albHash, true, true, true)
                end
                if itemData.normal and itemData.normal ~= "" then
                    local normHash = GetHashKey(itemData.normal)
                    Citizen.InvokeNative(0x59BD177A1A48600A, ped, normHash)
                    Citizen.InvokeNative(0xD3A7B003ED343FD9, ped, normHash, true, true, true)
                end
                if itemData.material and itemData.material ~= 0 then
                    local matHash = itemData.material
                    if type(matHash) == "string" then matHash = GetHashKey(matHash) end
                    Citizen.InvokeNative(0x59BD177A1A48600A, ped, matHash)
                    Citizen.InvokeNative(0xD3A7B003ED343FD9, ped, matHash, true, true, true)
                end
            else
                -- Classic-тип: применяем через hash
                NativeSetPedComponentEnabledClothes(ped, itemData.hash, false, true, true)
            end
        end
        
        -- ★ FIX: Увеличены паузы между фазами для высокого пинга
        -- ★ Фаза 1: Нижняя часть тела (pants, skirts, dresses)
        local lowerBody = {'pants', 'skirts', 'dresses'}
        local lowerApplied = false
        for _, cat in ipairs(lowerBody) do
            if ClothesCache[cat] and ClothesCache[cat].hash and ClothesCache[cat].hash ~= 0 then
                ApplyItem(cat, ClothesCache[cat])
                applied2[cat] = true
                count = count + 1
                lowerApplied = true
                Wait(50)
            end
        end
        if lowerApplied then
            Wait(80)
        end

        -- ★ Фаза 2: Рубашки (базовый верхний слой)
        if ClothesCache['shirts_full'] and ClothesCache['shirts_full'].hash and ClothesCache['shirts_full'].hash ~= 0 then
            ApplyItem('shirts_full', ClothesCache['shirts_full'])
            applied2['shirts_full'] = true
            count = count + 1
            Wait(80)
        end

        -- ★ Фаза 3: Шейные слои (под жилеткой/пальто)
        for _, cat in ipairs({'neckwear', 'neckties'}) do
            if ClothesCache[cat] and ClothesCache[cat].hash and ClothesCache[cat].hash ~= 0 then
                ApplyItem(cat, ClothesCache[cat])
                applied2[cat] = true
                count = count + 1
                Wait(50)
            end
        end

        -- ★ Фаза 3.5: Корсет на голом теле — при vest/corset без рубашки применяем naked overlay ДО vest (закрывает грудь)
        local vestOrCorset = ClothesCache['vests'] or ClothesCache['corsets']
        local hasVest = vestOrCorset and vestOrCorset.hash and vestOrCorset.hash ~= 0
        local hasShirt = ClothesCache['shirts_full'] and ClothesCache['shirts_full'].hash and ClothesCache['shirts_full'].hash ~= 0
        local hasDress = ClothesCache['dresses'] and ClothesCache['dresses'].hash and ClothesCache['dresses'].hash ~= 0
        local hasCoat = (ClothesCache['coats'] and ClothesCache['coats'].hash and ClothesCache['coats'].hash ~= 0)
            or (ClothesCache['coats_closed'] and ClothesCache['coats_closed'].hash and ClothesCache['coats_closed'].hash ~= 0)
        if hasVest and not hasShirt and not hasDress and not hasCoat and not IsPedMale(ped) and ApplyNakedUpperBody then
            ApplyNakedUpperBody(ped, true)
            Wait(50)
        end

        -- ★ Фаза 4: Жилетки/корсеты (средний слой — поверх рубашки/шеи)
        if ClothesCache['vests'] and ClothesCache['vests'].hash and ClothesCache['vests'].hash ~= 0 then
            ApplyItem('vests', ClothesCache['vests'])
            applied2['vests'] = true
            count = count + 1
            Wait(80)
        end
        if ClothesCache['corsets'] and ClothesCache['corsets'].hash and ClothesCache['corsets'].hash ~= 0 then
            ApplyItem('corsets', ClothesCache['corsets'])
            applied2['corsets'] = true
            count = count + 1
            Wait(80)
        end

        -- ★ Фаза 5: Пальто (внешний слой — поверх жилетки)
        for _, cat in ipairs({'coats', 'coats_closed'}) do
            if ClothesCache[cat] and ClothesCache[cat].hash and ClothesCache[cat].hash ~= 0 then
                ApplyItem(cat, ClothesCache[cat])
                applied2[cat] = true
                count = count + 1
                Wait(50)
            end
        end

        -- ★ Фаза 6: Остальные аксессуары (кроме обуви)
        for category, data in pairs(ClothesCache) do
            if not applied2[category] and data.hash and data.hash ~= 0 then
                local isLate = false
                for _, lc in ipairs(lateOrder2) do
                    if category == lc then isLate = true break end
                end
                if not isLate then
                    -- ★ FIX: Шляпа — перед применением снимаем по категории, иначе две шляпы (stack)
                    if category == 'hats' then
                        Citizen.InvokeNative(0xDF631E4BCE1B1FC4, ped, 0x9925C067)
                        Wait(50)
                    end
                    ApplyItem(category, data)
                    applied2[category] = true
                    count = count + 1
                    Wait(50)
                end
            end
        end

        -- ★ Фаза 7: Обувь ПОСЛЕДНЕЙ
        for _, category in ipairs(lateOrder2) do
            if ClothesCache[category] and ClothesCache[category].hash and ClothesCache[category].hash ~= 0 and not applied2[category] then
                ApplyItem(category, ClothesCache[category])
                applied2[category] = true
                count = count + 1
                Wait(50)
            end
        end

        -- ★ Сохраняем копию данных штаны/юбка/платье+обувь для отложенного re-equip (не зависим от ClothesCache в SetTimeout)
        if (not IsPedMale(ped)) and (applied2['pants'] or applied2['skirts'] or applied2['dresses']) and (ClothesCache['boots'] and ClothesCache['boots'].hash and ClothesCache['boots'].hash ~= 0) then
            local lc = applied2['skirts'] and 'skirts' or (applied2['dresses'] and 'dresses' or 'pants')
            reequipSkirtBootsPayload = {
                lowerData = { category = lc, isMale = isMale },
                bootData = { category = 'boots', isMale = isMale }
            }
            for k, v in pairs(ClothesCache[lc]) do reequipSkirtBootsPayload.lowerData[k] = v end
            for k, v in pairs(ClothesCache['boots']) do reequipSkirtBootsPayload.bootData[k] = v end
        end

        -- ★ Один раз применяем вариацию после надевания ВСЕХ слоёв — skipBodyMorph чтобы окрашенная рубашка не просвечивала
        NativeUpdatePedVariation(ped, true)
        Wait(100)
        end  -- конец else (bulk apply)
        
        -- ★ ПРИМЕНЯЕМ ЦВЕТА!
        for category, data in pairs(ClothesCache) do
            if data.palette and data.tints then
                local hasTints = data.tints[1] ~= 0 or data.tints[2] ~= 0 or data.tints[3] ~= 0
                local hasCustomPalette = data.palette ~= 'tint_generic_clean'
                local isPedCoat = IsPedCoatItem(category, data)
                
                if isPedCoat or hasTints or hasCustomPalette then
                    print('[RSG-Clothing] Applying color to ' .. category .. ': ' .. table.concat(data.tints, ','))
                    ApplyClothingColor(ped, category, data.palette, data.tints)
                    Wait(50)
                end
            end
        end

        -- ★ Ped-тип: применяем цвета отдельно (через palette/tints)
        for category, data in pairs(ClothesCache) do
            if data.kaf == "Ped" and data.palette and data.palette ~= "" and data.palette ~= " " then
                local paletteHash = GetHashKey(data.palette)
                if not string.find(data.palette:lower(), 'metaped_') then
                    paletteHash = GetHashKey('metaped_' .. data.palette:lower())
                end
                local tintHash = GetTintCategoryHash and GetTintCategoryHash(category) or nil
                if tintHash then
                    Citizen.InvokeNative(0x4EFC1F8FF1AD94DE, ped, tintHash, paletteHash,
                        data.tints and data.tints[1] or 0,
                        data.tints and data.tints[2] or 0,
                        data.tints and data.tints[3] or 0)
                    Citizen.InvokeNative(0xAAB86462966168CE, ped, true)
                end
            end
        end
        
        -- Финальная проверка
        Wait(100)
        EnsureBodyIntegrity(ped, false)
        
        -- ★ После EnsureBodyIntegrity морф тела может сброситься — переприменяем морф + раскраска (nativepaint)
        ReapplyAppearanceAfterClothing(ped)
        NativeUpdatePedVariation(ped, true)

        -- ★ При полной загрузке (ApplySkin) лишние переприменения убраны — один проход одежды и два UpdatePedVariation (после слоёв и после морфа).
        -- При лёгком ресинке (equip/remove) можно дожимовать обувь/аксессуары после EnsureBodyIntegrity.
        if isLightResyncPass then
            Wait(150)
            ped = PlayerPedId()
            if DoesEntityExist(ped) then
                for _, cat in ipairs({'boots', 'boot_accessories', 'spurs', 'chaps', 'spats'}) do
                    local item = ClothesCache and ClothesCache[cat]
                    if item and item.hash and item.hash ~= 0 then
                        Citizen.InvokeNative(0x59BD177A1A48600A, ped, item.hash)
                        NativeSetPedComponentEnabledClothes(ped, item.hash, true, true, true)
                        Wait(50)
                    end
                end
                if not isMale and ClothesCache and ClothesCache['hair_accessories'] and ClothesCache['hair_accessories'].hash and ClothesCache['hair_accessories'].hash ~= 0 then
                    local h = ClothesCache['hair_accessories'].hash
                    Citizen.InvokeNative(0xD710A5007C2AC539, ped, 0x79D7DF96, 0)
                    Wait(80)
                    Citizen.InvokeNative(0x59BD177A1A48600A, ped, h)
                    NativeSetPedComponentEnabledClothes(ped, h, true, true, true)
                    Wait(80)
                end
                NativeUpdatePedVariation(ped, true)
            end
        else
            lastClothingLoadTime = GetGameTimer()
            -- ★ Реальное переодевание после загрузки: снять один слой и надеть обратно. Помогает скриптам с прозрачностью модели.
            -- ★ useEquipPath: уже одели через equip — не нужен refresh, только цвета
            if useEquipPath then
                SetTimeout(400, function()
                    TriggerEvent('rsg-appearance:client:clothingVariationChanged')
                    SetTimeout(250, function()
                        TriggerEvent('rsg-appearance:client:clothingVariationSettled')
                        TriggerEvent('rsg-appearance:client:requestModifierReapply')
                    end)
                end)
            else
            SetTimeout(600, function()
                local p = PlayerPedId()
                if not p or not DoesEntityExist(p) then return end
                -- ★ Жен.+штаны/юбка/платье+обувь: тот же путь, что "снять/надеть через инвентарь". Данные взяты из сохранённого payload (не ClothesCache — он мог перезаписаться при повторной загрузке)
                if reequipSkirtBootsPayload then
                    TriggerEvent('rsg-clothing:client:equipClothing', reequipSkirtBootsPayload.lowerData, { skipResync = true })
                    Wait(350)
                    TriggerEvent('rsg-clothing:client:equipClothing', reequipSkirtBootsPayload.bootData, { skipResync = true })
                    Wait(350)
                end
                local shirt = ClothesCache and ClothesCache['shirts_full']
                local shirtHash = shirt and shirt.hash and shirt.hash ~= 0 and shirt.hash or nil
                if shirtHash then
                    local catHash = GetHashKey('shirts_full')
                    Citizen.InvokeNative(0xD710A5007C2AC539, p, catHash, 0)
                    Citizen.InvokeNative(0x704C908E9C405136, p)
                    Citizen.InvokeNative(0xCC8CA3E88256E58F, p, false, true, true, true, false)
                    Wait(120)
                    Citizen.InvokeNative(0x59BD177A1A48600A, p, shirtHash)
                    NativeSetPedComponentEnabledClothes(p, shirtHash, false, true, true)
                    Citizen.InvokeNative(0x704C908E9C405136, p)
                    Citizen.InvokeNative(0xCC8CA3E88256E58F, p, false, true, true, true, false)
                    Wait(80)
                    -- ★ FIX: Используем вариацию из ClothingModState, а не BASE — иначе слетают рукава/воротник
                    local shirtVar = ClothingVariations.shirts.base
                    if ClothingModState and ClothingModState.sleeves_rolled_open then
                        shirtVar = ClothingVariations.shirts.rolled_open
                    elseif ClothingModState and ClothingModState.sleeves_rolled then
                        shirtVar = ClothingVariations.shirts.rolled_closed
                    end
                    SetPedComponentVariation(p, shirtHash, shirtVar)
                    NativeUpdatePedVariation(p, true)
                    if shirt.palette and shirt.tints and ApplyClothingColor then
                        Wait(80)
                        ApplyClothingColor(p, 'shirts_full', shirt.palette, shirt.tints)
                    end
                else
                    -- ★ FIX: Vest/corset без рубашки — переприменяем жилет через ~1.1 сек (просветы тела сквозь корсет)
                    -- RDR2 иногда требует "refresh" слоя для корректного рендера (по данным RDR2 modding)
                    local vest = ClothesCache and (ClothesCache['vests'] or ClothesCache['corsets'])
                    local vestHash = vest and vest.hash and vest.hash ~= 0 and vest.hash or nil
                    local vestCat = vest and (ClothesCache['vests'] and ClothesCache['vests'].hash == vest.hash and 'vests' or 'corsets') or nil
                    if vestHash and vestCat and not isMale then
                        SetTimeout(1100, function()
                            local ped = PlayerPedId()
                            if not ped or not DoesEntityExist(ped) then return end
                            if EnsureBodyIntegrity then EnsureBodyIntegrity(ped, true) end
                            Wait(80)
                            NativeSetPedComponentEnabledClothes(ped, vestHash, false, true, true)
                            Citizen.InvokeNative(0x704C908E9C405136, ped)
                            NativeUpdatePedVariation(ped, true)
                            if vest.palette and vest.tints and ApplyClothingColor then
                                Wait(50)
                                ApplyClothingColor(ped, vestCat, vest.palette, vest.tints)
                            end
                        end)
                    end
                    NativeUpdatePedVariation(p, true)
                end
                -- ReapplyAppearanceAfterClothing(p) -- ОТКЛЮЧЕНО: сбрасывал цвета
                TriggerEvent('rsg-appearance:client:clothingVariationChanged')
                SetTimeout(650, function()
                    TriggerEvent('rsg-appearance:client:clothingVariationSettled')
                    -- ★ FIX: Просим clothing-modifier переприменить цвета — иначе палитра/тинты слетают после reload
                    TriggerEvent('rsg-appearance:client:requestModifierReapply')
                end)
            end)
            end  -- else (bulk apply)
        end

        -- ★ ОТЛОЖЕННАЯ РЕСИНХРОНИЗАЦИЯ (5 сек) отключена при полной загрузке — один проход одежды без лишних переприменений.
        
        print('[RSG-Clothing] Loaded ' .. count .. ' items (single apply, no extra re-applies)')
        if callback then callback(true, count) end
    end)
end

-- ★ ОТКЛЮЧЕНО: ReapplyVestOverShirt в beforeModifierReapply вызывал лишний NativeUpdatePedVariation и ломал одежду
-- AddEventHandler('rsg-appearance:client:beforeModifierReapply', ...)

-- Отключено: переприменение vest/coat в afterModifierReapply сбрасывало цвет пальто и ломало жилетку
AddEventHandler('rsg-appearance:client:afterModifierReapply', function() end)

-- ★ Событие от clothing-modifier для обновления цвета в кэше
RegisterNetEvent('rsg-appearance:updateClothingColor', function(category, palette, tints)
    if ClothesCache and ClothesCache[category] then
        ClothesCache[category].palette = palette
        ClothesCache[category].tints = tints
        print('[RSG-Clothing] Updated cache color for ' .. category)
    end
end)

print('[RSG-Appearance] Color preservation patch loaded')