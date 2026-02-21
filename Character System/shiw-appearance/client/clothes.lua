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
    'vests',  -- ★ FIX: корсет/жилетка ПОКРЫВАЕТ верхнюю часть тела, не надо применять bodies_upper поверх
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
        
        if hasUpperCutoff and not hasUpperCover then
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
        end
    end
    
    -- Обновляем вариацию если были изменения
    if needsUpdate or forceUpdate then
        Wait(50)
        NativeUpdatePedVariation(ped)
    end
    
    return needsUpdate
end

-- Экспорт функции
exports('EnsureBodyIntegrity', EnsureBodyIntegrity)
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
-- normalize shirt variation and hide the most problematic under-layers.
local function ApplyCoatAntiClipFix(ped, equippedCategory)
    if not ped or not DoesEntityExist(ped) then return end
    if equippedCategory ~= 'coats' and equippedCategory ~= 'coats_closed' then return end

    if equippedCategory == 'coats_closed' then
        -- Анти-клип для закрытых пальто: скрываем проблемные слои и задаём рубашке BASE-вариацию.
        -- Рубашка видна только на открытых точках (воротник, манжеты), не просвечивает сквозь ткань.
        local hideCats = { 'vests', 'suspenders', 'neckwear', 'neckties' }
        for i = 1, #hideCats do
            local cat = hideCats[i]
            if ClothesCache and ClothesCache[cat] and ClothesCache[cat].hash and ClothesCache[cat].hash ~= 0 then
                Citizen.InvokeNative(0xD710A5007C2AC539, ped, GetHashKey(cat), 0)
                if metaPedComponents and metaPedComponents[cat] then
                    Citizen.InvokeNative(0xD710A5007C2AC539, ped, metaPedComponents[cat], 0)
                end
            end
        end
        if ClothesCache and ClothesCache['shirts_full'] and ClothesCache['shirts_full'].hash and ClothesCache['shirts_full'].hash ~= 0 then
            Citizen.InvokeNative(0x66B957AAC2EAAEAB, ped, ClothesCache['shirts_full'].hash, joaat('BASE'), 0, true, 1)
        end
    else
        -- Open coats: softer fix, keep shirt but normalize variation.
        if ClothesCache and ClothesCache['shirts_full'] and ClothesCache['shirts_full'].hash and ClothesCache['shirts_full'].hash ~= 0 then
            Citizen.InvokeNative(0x66B957AAC2EAAEAB, ped, ClothesCache['shirts_full'].hash, joaat('BASE'), 0, true, 1)
        end
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
    -- shirts_full НЕ скрываем — рубашка должна быть видна под пальто
    if category == 'vests' then return true end
    if category == 'suspenders' then return true end
    if category == 'neckwear' then return true end
    if category == 'neckties' then return true end
    return false
end
-- ==========================================
-- НАТИВНЫЕ ФУНКЦИИ
-- ==========================================

function NativeSetPedComponentEnabledClothes(ped, hash, immediately, isMp01, isPlayer)
    Citizen.InvokeNative(0x59BD177A1A48600A, ped, hash)
    -- ★ ИСПРАВЛЕНО: Всегда immediately=true, isMp=true, isMultiplayer=true
    -- Все рабочие вызовы в load_functions.lua используют (ped, hash, true, true, true)
    -- С immediately=false компонент ставится в очередь но не применяется на существующем педе
    Citizen.InvokeNative(0xD3A7B003ED343FD9, ped, hash, true, true, true)

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
end

function NativeUpdatePedVariation(ped)
    -- ★ ИСПРАВЛЕНО: Добавлен 0x704C908E9C405136 (_FINAL_PED_META_CHANGE_APPLY)
    -- Без этого вызова MetaPed компоненты одежды НЕ отображаются визуально!
    -- ★ ИСПРАВЛЕНО: Параметры 0xCC8CA3E88256E58F теперь boolean (не integer)
    Citizen.InvokeNative(0x704C908E9C405136, ped)
    Citizen.InvokeNative(0xCC8CA3E88256E58F, ped, false, true, true, true, false)
    if ReapplyBodyMorph then ReapplyBodyMorph(ped) end
end

-- ==========================================
-- НАТИВЫ ДЛЯ ЦВЕТА ОДЕЖДЫ v3.0
-- ==========================================

function SetTextureOutfitTints(ped, categoryHash, paletteHash, tint0, tint1, tint2)
    Citizen.InvokeNative(0x4EFC1F8FF1AD94DE, ped, categoryHash, paletteHash, tint0, tint1, tint2)
end

function ApplyClothingColor(ped, category, palette, tints)
    if tints and tints[1] == 0 and tints[2] == 0 and tints[3] == 0 then
        local isDefaultPalette = (not palette or palette == 'tint_generic_clean' or palette == 'metaped_tint_generic_clean')
        if isDefaultPalette then
            return
        end
    end
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
    
    if isDefaultPalette and not hasNonZeroTints then
        -- Для дефолтной палитры - очищаем тинты полностью (сбрасываем на оригинальный цвет)
        -- Не вызываем SetTextureOutfitTints - оставляем оригинальный цвет одежды
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
    NativeUpdatePedVariation(ped)
    
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
        -- mp_male/mp_female приходят с дефолтным головным убором — без явного снятия он остаётся
        if not equippedItems or not equippedItems['hats'] then
            Citizen.InvokeNative(0xD710A5007C2AC539, ped, GetHashKey('hats'), 0)
            Citizen.InvokeNative(0xD710A5007C2AC539, ped, 0x9925C067, 0)
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
                    kaf = data.kaf or "Classic",
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
        -- ★ FIX: Увеличены паузы между фазами для высокого пинга
        if phaseCount > 0 then
            NativeUpdatePedVariation(ped)
            Wait(200)
            print('[RSG-Clothing] Phase 1 (lower body): ' .. phaseCount .. ' items applied')
        end
        
        -- Фаза 2a: Рубашки (базовый верхний слой)
        -- ★ Каждый слой верхней одежды обновляется отдельно для корректной регистрации в MetaPed
        if ClothesCache['shirts_full'] and ClothesCache['shirts_full'].hash and ClothesCache['shirts_full'].hash ~= 0 then
            ApplyItemOriginal('shirts_full', ClothesCache['shirts_full'])
            applied['shirts_full'] = true
            count = count + 1
            NativeUpdatePedVariation(ped)
            Wait(150)
            print('[RSG-Clothing] Phase 2a (shirts): applied')
        end

        -- Фаза 2b: Жилетки (средний слой)
        if ClothesCache['vests'] and ClothesCache['vests'].hash and ClothesCache['vests'].hash ~= 0 then
            ApplyItemOriginal('vests', ClothesCache['vests'])
            applied['vests'] = true
            count = count + 1
            NativeUpdatePedVariation(ped)
            Wait(150)
            print('[RSG-Clothing] Phase 2b (vests): applied')
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
            NativeUpdatePedVariation(ped)
            Wait(150)
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
            NativeUpdatePedVariation(ped)
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
            NativeUpdatePedVariation(ped)
            Wait(200)
            print('[RSG-Clothing] Phase 4 (boots): ' .. phaseCount .. ' items applied')
        end
        
        -- ПРИМЕНЯЕМ ЦВЕТА!
        for category, data in pairs(ClothesCache) do
            if data.palette and data.tints then
                if data.palette ~= 'tint_generic_clean' or 
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
        
        -- ★ После EnsureBodyIntegrity морф тела может сброситься — переприменяем (пузо/талия/телосложение)
        if ReapplyBodyMorph then ReapplyBodyMorph(ped) end
        NativeUpdatePedVariation(ped)
        
        -- ★ NAKED BODY: Проверяем нужно ли голое тело
        Wait(100)
        -- ★ FIX LoadCharacter: явно применяем bodies при наличии одежды — стабилизация для первого снятия/надевания
        local hasLower = applied['pants'] or applied['skirts'] or applied['dresses']
        local hasUpper = applied['shirts_full'] or applied['vests'] or applied['coats'] or applied['coats_closed'] or applied['dresses']
        if hasLower then
            local bh = GetBodyHash("BODIES_LOWER") or GetBodyHashNative(ped, "BODIES_LOWER") or GetBodyHashFromClothesList(ped, "BODIES_LOWER")
            if (not bh or bh == 0) then bh = GetBodyHashFromClothesList(ped, "BODIES_LOWER") end
            if bh and bh ~= 0 then
                Citizen.InvokeNative(0x59BD177A1A48600A, ped, GetHashKey("bodies_lower"))
                Citizen.InvokeNative(0xD3A7B003ED343FD9, ped, bh, true, true, true)
                Citizen.InvokeNative(0x704C908E9C405136, ped)
                Citizen.InvokeNative(0xCC8CA3E88256E58F, ped, false, true, true, true, false)
            end
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
        end
        if CheckAndApplyNakedBodyIfNeeded then
            CheckAndApplyNakedBodyIfNeeded(ped, ClothesCache)
        end
        
        -- ★ FIX: Шляпа часто не прогружается после reload — переприменяем отдельно с задержкой
        if ClothesCache['hats'] and ClothesCache['hats'].hash and ClothesCache['hats'].hash ~= 0 then
            Wait(250)
            ped = PlayerPedId()
            if DoesEntityExist(ped) then
                NativeSetPedComponentEnabledClothes(ped, ClothesCache['hats'].hash, true, true, true)
                Wait(150)
                NativeUpdatePedVariation(ped)
                if ApplyClothingColor and ClothesCache['hats'].palette and ClothesCache['hats'].tints then
                    ApplyClothingColor(ped, 'hats', ClothesCache['hats'].palette, ClothesCache['hats'].tints)
                end
            end
        end
        
        -- ★ Триггерим событие что одежда загружена
        TriggerEvent('rsg-clothing:client:clothingLoaded', ClothesCache)
        
        -- ★ FIX LoadCharacter: штаны сквозь сапоги — несколько проходов переприменения сапог поверх штанов
        if hasLower then
            local function ReapplyBootsOverPants()
                local p = PlayerPedId()
                if not DoesEntityExist(p) or not ClothesCache then return end
                for _, cat in ipairs({'boots', 'boot_accessories', 'spurs', 'chaps', 'spats'}) do
                    if ClothesCache[cat] and ClothesCache[cat].hash and ClothesCache[cat].hash ~= 0 then
                        Citizen.InvokeNative(0x59BD177A1A48600A, p, ClothesCache[cat].hash)
                        NativeSetPedComponentEnabledClothes(p, ClothesCache[cat].hash, false, true, true)
                    end
                end
                NativeUpdatePedVariation(p)
            end
            for _, delay in ipairs({600, 1200, 2500}) do
                SetTimeout(delay, ReapplyBootsOverPants)
            end
        end
        -- ★ FIX: Отложенное переприменение шляпы (после unfreeze/морфа игра может сбросить)
        for _, delay in ipairs({1500, 3500}) do
            SetTimeout(delay, function()
                local p = PlayerPedId()
                if not DoesEntityExist(p) or not ClothesCache or not ClothesCache['hats'] then return end
                local h = ClothesCache['hats'].hash
                if not h or h == 0 then return end
                local hasHat = Citizen.InvokeNative(0xFB4891BD7578CDC1, p, 0x9925C067)
                if not hasHat or hasHat == 0 then
                    Citizen.InvokeNative(0x59BD177A1A48600A, p, h) -- Request
                    NativeSetPedComponentEnabledClothes(p, h, true, true, true)
                    Wait(100)
                    NativeUpdatePedVariation(p)
                end
            end)
        end
        
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
        NativeUpdatePedVariation(ped)
        
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
        ReapplyVestOverShirt(ped)
        
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
        NativeUpdatePedVariation(ped)
        
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
        ReapplyVestOverShirt(ped)
        
        TriggerEvent('ox_lib:notify', {
            title = 'Воротник',
            description = ClothingModifications.collar and 'Воротник расстегнут' or 'Воротник застегнут',
            type = 'success'
        })
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
        TaskPlayAnim(ped, dict, anim, 8.0, -8.0, -1, 51, 0, false, false, false)
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
    if category == 'shirts_full' or category == 'dresses' or category == 'coats' or category == 'coats_closed' or category == 'vests' then
        NakedUpperApplied = false
        print('[RSG-Clothing] Reset NakedUpperApplied flag')
    end
end

RegisterNetEvent('rsg-clothing:client:equipClothing', function(data)
    CreateThread(function()
        local ped = PlayerPedId()

        -- Проверка пола на СЕРВЕРЕ (sv_clothing.lua ToggleClothingItem) уже пройдена,
        -- клиентская проверка убрана — IsPedMale() и data.isMale имели несовместимые типы
        -- (0/1 vs true/false в Lua 5.4), вызывая ложные блокировки

        print('[RSG-Clothing] equipClothing: cat=' .. tostring(data.category) .. ' hash=' .. tostring(data.hash) .. ' kaf=' .. tostring(data.kaf))

        -- Сброс модификаций при смене рубашки
        if data.category == 'shirts_full' then
            ClothingModifications.sleeves = false
            ClothingModifications.collar = false
        end

        local hash = data.hash
        local isPedClothing = data.kaf == "Ped" and data.draw and data.draw ~= ""

        -- ★ Убираем naked overlay ДО применения рубашки/корсета
        -- ★ FIX: Очищаем ТОЛЬКО слот экипируемой категории — рубашка и жилетка носятся вместе!
        if data.category == 'shirts_full' or data.category == 'vests' or data.category == 'corsets' or 
           data.category == 'coats' or data.category == 'coats_closed' or data.category == 'dresses' then
            if RemoveNakedUpperBody then RemoveNakedUpperBody(ped, true) end
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
            -- ★ Переприменяем нижние слои (рубашка под жилеткой, жилетка под пальто)
            local function ReapplyItem(cat)
                local d = ClothesCache[cat]
                if not d or (not d.hash or d.hash == 0) then return end
                if d.kaf == "Ped" and d.draw and d.draw ~= "" and d.draw ~= "_" then
                    local h = GetHashKey(d.draw)
                    Citizen.InvokeNative(0x59BD177A1A48600A, ped, h)
                    Citizen.InvokeNative(0xD3A7B003ED343FD9, ped, h, true, true, true)
                else
                    Citizen.InvokeNative(0x59BD177A1A48600A, ped, d.hash)
                    NativeSetPedComponentEnabledClothes(ped, d.hash, false, true, true)
                end
            end
            if data.category == 'vests' or data.category == 'corsets' then
                ReapplyItem('shirts_full')
                Citizen.InvokeNative(0x704C908E9C405136, ped)
                Citizen.InvokeNative(0xCC8CA3E88256E58F, ped, false, true, true, true, false)
            elseif data.category == 'coats' or data.category == 'coats_closed' then
                ReapplyItem('shirts_full')
                ReapplyItem('vests')
                Citizen.InvokeNative(0x704C908E9C405136, ped)
                Citizen.InvokeNative(0xCC8CA3E88256E58F, ped, false, true, true, true, false)
            end
            Wait(100)
        end

        -- ★ Убираем naked overlay (ноги) ДО применения штанов/юбки/платья
        if data.category == 'pants' or data.category == 'skirts' or data.category == 'dresses' then
            if RemoveNakedLowerBody then RemoveNakedLowerBody(ped, true) end
            Wait(50)
            Citizen.InvokeNative(0xD710A5007C2AC539, ped, 0x1D4C528A, 0)
            Citizen.InvokeNative(0xD710A5007C2AC539, ped, 0xA0E3AB7F, 0)
            Citizen.InvokeNative(0xD710A5007C2AC539, ped, 0x0662AC34, 0)
            Citizen.InvokeNative(0xD710A5007C2AC539, ped, 0x3107499B, 0)
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
            -- ★ PED штаны: отложенное переприменение (fix LoadCharacter)
            if (data.category == 'pants' or data.category == 'skirts' or data.category == 'dresses') and data.draw and data.draw ~= "" then
                SetTimeout(350, function()
                    local p = PlayerPedId()
                    if DoesEntityExist(p) then
                        local drawHash = GetHashKey(data.draw)
                        Citizen.InvokeNative(0x59BD177A1A48600A, p, drawHash)
                        Citizen.InvokeNative(0xD3A7B003ED343FD9, p, drawHash, true, true, true)
                        Citizen.InvokeNative(0x704C908E9C405136, p)
                        if NativeUpdatePedVariation then NativeUpdatePedVariation(p) else Citizen.InvokeNative(0xCC8CA3E88256E58F, p, false, true, true, true, false) end
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
                if ReapplyBodyMorph then ReapplyBodyMorph(ped) end
                Wait(150)
            end

            -- ★ Request для стриминга (штаны после bodies_lower могут не успеть прогрузиться)
            if data.category == 'pants' or data.category == 'skirts' or data.category == 'dresses' then
                Citizen.InvokeNative(0x59BD177A1A48600A, ped, hash)
                local t = 0
                while not Citizen.InvokeNative(0xA0BC8FAED8CFEB3C, ped) and t < 30 do Wait(20) t = t + 1 end
            end
            -- Применяем одежду: Request → Apply → Finalize → Update
            NativeSetPedComponentEnabledClothes(ped, hash, false, true, true)
            NativeUpdatePedVariation(ped)

            -- Цвет
            local palette = data.palette or 'tint_generic_clean'
            local tints = data.tints or {0, 0, 0}
            local isClassic = (data.kaf == "Classic" or data._kaf == "Classic")
            local hasZeroTints = (tints[1] == 0 and tints[2] == 0 and tints[3] == 0)
            if not (isClassic and hasZeroTints) then
                Wait(100)
                ApplyClothingColor(ped, data.category, palette, tints)
            end

            -- Кэш (сохраняем ВСЕ поля включая kaf/draw для корректного снятия)
            ClothesCache[data.category] = {
                hash = hash, model = data.model or 0, texture = data.texture or 0,
                palette = data.palette or 'tint_generic_clean', tints = data.tints or {0, 0, 0},
                kaf = data.kaf or "Classic", draw = data.draw or "",
                albedo = data.albedo or "", normal = data.normal or "",
                material = data.material or 0,
            }

            -- После штанов: переприменяем штаны (fix LoadCharacter — с 1 раза) + сапоги поверх
            if data.category == "pants" or data.category == "skirts" or data.category == "dresses" then
                Wait(100)
                NativeSetPedComponentEnabledClothes(ped, hash, false, true, true)
                NativeUpdatePedVariation(ped)
                local reapplyAfterLower = {
                    'boots', 'boot_accessories', 'spurs', 'chaps', 'spats',
                    'gunbelts', 'belts', 'satchels'
                }
                for _, cat in ipairs(reapplyAfterLower) do
                    if ClothesCache[cat] and ClothesCache[cat].hash and ClothesCache[cat].hash ~= 0 then
                        NativeSetPedComponentEnabledClothes(ped, ClothesCache[cat].hash, false, true, true)
                    end
                end
                NativeUpdatePedVariation(ped)
                -- ★ Отложенное переприменение штанов (после naked bodies_lower стриминг может задержаться)
                SetTimeout(350, function()
                    local p = PlayerPedId()
                    if DoesEntityExist(p) and hash and hash ~= 0 then
                        Citizen.InvokeNative(0x59BD177A1A48600A, p, hash)
                        NativeSetPedComponentEnabledClothes(p, hash, false, true, true)
                        NativeUpdatePedVariation(p)
                    end
                end)
            end

            if data.category == 'coats' or data.category == 'coats_closed' then
                ApplyCoatAntiClipFix(ped, data.category)
            end

            print('[RSG-Clothing] CLASSIC equipClothing completed: hash=' .. tostring(hash))
            TriggerEvent('rsg-clothing:client:clothingLoaded', ClothesCache)
            if CheckAndApplyNakedBodyIfNeeded then
                SetTimeout(150, function()
                    CheckAndApplyNakedBodyIfNeeded(PlayerPedId(), ClothesCache)
                end)
            end
        else
            print('[RSG-Clothing] ERROR: No hash for ' .. tostring(data.category))
        end

        -- Подстраховка от локального десинка:
        -- после события экипировки сверяемся с server equipped-состоянием.
        if EnableToggleInventoryResync and ScheduleClothingResyncFromInventory then
            ScheduleClothingResyncFromInventory('equip:' .. tostring(data.category))
        end

        -- ★ Отложенное переприменение body morph — UpdatePedVariation/цвета иногда сбрасывают пузо/талию
        SetTimeout(300, function()
            local p = PlayerPedId()
            if DoesEntityExist(p) and ReapplyBodyMorph then ReapplyBodyMorph(p) end
        end)
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

-- ★ Удаление "висящей" шляпы над головой (слетела/подлетела при снятии — игра создаёт проп)
local HAT_HEAD_RADIUS = 4.0  -- ★ Увеличен: шляпа может подлететь на 3-4м при анимации
local HAT_Z_MAX = 5.0        -- ★ Макс. высота над головой (шляпа "подлетает" вверх)
-- hatModelHash — хеш модели; если nil/0 — удаляем любой проп над головой (по позиции)
local function ClearFloatingHatProp(ped, hatModelHash)
    if not ped or not DoesEntityExist(ped) then return end
    local headPos = GetEntityCoords(ped)
    local headPosHigh = vector3(headPos.x, headPos.y, headPos.z + 0.5)
    local pool = GetGamePool and GetGamePool('CObject') or {}
    local removed = false
    local fallbackCandidate = nil
    local fallbackDist = 999.0

    for _, obj in ipairs(pool) do
        if DoesEntityExist(obj) and obj ~= ped then
            local objPos = GetEntityCoords(obj)
            local dist = #(headPosHigh - objPos)
            if dist <= HAT_HEAD_RADIUS then
                local modelMatches = (hatModelHash and hatModelHash ~= 0 and GetEntityModel(obj) == hatModelHash)
                local zDelta = objPos.z - headPos.z
                -- Шляпа над головой (0.15м - 5м) — "зависшая" или "подлетевшая" при снятии
                local isAboveHead = (zDelta > 0.15 and zDelta < HAT_Z_MAX)
                local isSlowOrAttached = (GetEntitySpeed(obj) < 0.5) or IsEntityAttached(obj)

                if modelMatches then
                    DeleteEntity(obj)
                    removed = true
                elseif isAboveHead and isSlowOrAttached and dist < fallbackDist then
                    -- Проп над головой, почти не двигается — вероятно сбитая шляпа
                    fallbackCandidate = obj
                    fallbackDist = dist
                end
            end
        end
    end

    if not removed and fallbackCandidate and DoesEntityExist(fallbackCandidate) then
        DeleteEntity(fallbackCandidate)
    end
end

local metaPedComponents = {
    ['hats'] = 0x9925C067,
    ['shirts_full'] = 0x2026C46D,
    ['pants'] = 0x1D4C528A,
    ['boots'] = 0x777EC6EF,
    ['vests'] = 0x485EE834,
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

    -- Удаляем MetaPed компонент по имени категории + по хешу
    Citizen.InvokeNative(0xD710A5007C2AC539, ped, GetHashKey(category), 0)
    if metaPedComponents[category] then
        Citizen.InvokeNative(0xD710A5007C2AC539, ped, metaPedComponents[category], 0)
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

    -- ★ Шаг 3: Фоллбэк — мини-перестройка только затронутой группы слоёв
    if removalFailed then
        -- Определяем группу слоёв для перестройки
        local layerGroup
        local upperGroup = {'shirts_full', 'vests', 'coats', 'coats_closed', 'cloaks', 'ponchos', 'suspenders'}
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
            Citizen.InvokeNative(0xD710A5007C2AC539, ped, GetHashKey(cat), 0)
            if metaPedComponents[cat] then
                Citizen.InvokeNative(0xD710A5007C2AC539, ped, metaPedComponents[cat], 0)
            end
        end
        Citizen.InvokeNative(0x704C908E9C405136, ped)
        Citizen.InvokeNative(0xCC8CA3E88256E58F, ped, false, true, true, true, false)
        t = 0
        while not Citizen.InvokeNative(0xA0BC8FAED8CFEB3C, ped) and t < 50 do Wait(10) t = t + 1 end
        Wait(50)

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
            NativeUpdatePedVariation(ped)
            Wait(50)
            -- Переприменяем цвета
            for _, cat in ipairs(layerGroup) do
                if ClothesCache[cat] and ClothesCache[cat].palette and ClothesCache[cat].tints then
                    local d = ClothesCache[cat]
                    local hasTints = d.tints[1] ~= 0 or d.tints[2] ~= 0 or d.tints[3] ~= 0
                    if hasTints or d.palette ~= 'tint_generic_clean' then
                        ApplyClothingColor(ped, cat, d.palette, d.tints)
                    end
                end
            end
        end

        print('[RSG-Clothing] Layer rebuild complete: reapplied ' .. reapplied .. ' items')
    end

    -- ★ Шляпа: удаляем проп (модель снятой шляпы) — он может подлететь при анимации или появиться с задержкой
    if category == 'hats' then
        ClearFloatingHatProp(ped, savedHatHash)
        for _, delay in ipairs({400, 1000, 2000}) do
            SetTimeout(delay, function()
                local p = PlayerPedId()
                if DoesEntityExist(p) then ClearFloatingHatProp(p, savedHatHash) end
            end)
        end
        SetTimeout(2500, function()
            local p = PlayerPedId()
            if DoesEntityExist(p) then ClearFloatingHatProp(p, nil) end
        end)
    end

    -- ★ Body morph (UpdatePedVariation может сбросить face features)
    if ReapplyBodyMorph then ReapplyBodyMorph(ped) end

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
        end
    end
    if category == "shirts_full" or category == "dresses" or category == "coats" or category == "coats_closed" or category == "vests" then
        local isMale = IsPedMale(ped)
        if not isMale or isMale == false or isMale == 0 then
            local hasUpper = false
            for _, cat in ipairs({'shirts_full', 'dresses', 'coats', 'coats_closed', 'vests'}) do
                if ClothesCache[cat] and type(ClothesCache[cat]) == 'table' then
                    if (ClothesCache[cat].hash and ClothesCache[cat].hash ~= 0) then hasUpper = true break end
                end
            end
            if not hasUpper then
                if ApplyNakedUpperBody then ApplyNakedUpperBody(ped) end
            end
        end
    end

    EnsureBodyIntegrity(ped, false)
    if EnableToggleInventoryResync and ScheduleClothingResyncFromInventory then
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
            TaskPlayAnim(ped, dict, anim, 4.0, -4.0, 2000, 51, 0, false, false, false)
        end
    end)
end)

print('[RSG-Clothing] Fixed equip/remove handlers loaded (v2.0)')

-- ★ Очистка зависшей шляпы над головой (сбита в драке — проп не падает, а висит)
CreateThread(function()
    local hatHash = 0x9925C067
    while true do
        Wait(800)
        local ped = PlayerPedId()
        if not ped or not DoesEntityExist(ped) then goto continue end
        if not ClothesCache then goto continue end
        if not ClothesCache['hats'] or not ClothesCache['hats'].hash then goto continue end
        if lastClothingLoadTime > 0 and (GetGameTimer() - lastClothingLoadTime) < 8000 then goto continue end
        local hasHat = Citizen.InvokeNative(0xFB4891BD7578CDC1, ped, hatHash)
        if not hasHat or hasHat == 0 then
            -- ★ FIX: Только удаляем висящий проп (визуальный баг), НЕ очищаем ClothesCache!
            -- Сохраняем шляпу в кэше — тогда при респавне/релоаде она снова применится.
            local hatModelHash = ClothesCache['hats'].hash
            ClearFloatingHatProp(ped, hatModelHash)
        end
        ::continue::
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
function UpdatePedVariation(ped)
    Citizen.InvokeNative(0x704C908E9C405136, ped)
    Citizen.InvokeNative(0xCC8CA3E88256E58F, ped, false, true, true, true, false)
    -- ★ AUTO-FIX: UpdatePedVariation сбрасывает body morph
    if ReapplyBodyMorph then ReapplyBodyMorph(ped) end
end

-- Переприменить жилет поверх рубашки (после смены рукавов/воротника рубашка не должна просвечивать сквозь жилет)
local function ReapplyVestOverShirt(ped)
    if not ped or not DoesEntityExist(ped) then return end
    if not ClothesCache or not ClothesCache['vests'] or not ClothesCache['vests'].hash or ClothesCache['vests'].hash == 0 then return end
    NativeSetPedComponentEnabledClothes(ped, ClothesCache['vests'].hash, false, true, true)
    NativeUpdatePedVariation(ped)
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
    
    -- Сохраняем цвет ДО изменения
    local savedPalette = nil
    local savedTints = nil
    if ClothesCache and ClothesCache['shirts_full'] then
        savedPalette = ClothesCache['shirts_full'].palette
        savedTints = ClothesCache['shirts_full'].tints
    end
    
    -- Сбрасываем другой вариант рукавов
    ClothingModState.sleeves_rolled_open = false
    
    -- Переключаем состояние
    ClothingModState.sleeves_rolled = not ClothingModState.sleeves_rolled
    
    -- Анимация
    PlayClothingModAnimation('sleeves')
    Wait(500)
    
    -- Применяем вариацию
    local variation = ClothingModState.sleeves_rolled 
        and ClothingVariations.shirts.rolled_closed 
        or ClothingVariations.shirts.base
    
    SetPedComponentVariation(ped, shirtHash, variation)
    UpdatePedVariation(ped)
    
    -- ВОССТАНАВЛИВАЕМ ЦВЕТ рубашки
    if savedPalette and savedTints then
        Wait(100)
        ApplyClothingColor(ped, 'shirts_full', savedPalette, savedTints)
        print('[Clothing] Restored color after sleeves toggle: ' .. savedPalette)
    end
    ReapplyVestOverShirt(ped)
    
    -- Уведомление
    local message = ClothingModState.sleeves_rolled and 'Рукава закатаны' or 'Рукава опущены'
    TriggerEvent('ox_lib:notify', {
        title = 'Рукава',
        description = message,
        type = 'success'
    })
    
    print('[Clothing] Sleeves toggled: ' .. variation .. ' for hash: 0x' .. string.format("%X", shirtHash))
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
    
    -- Сохраняем цвет ДО изменения
    local savedPalette = nil
    local savedTints = nil
    if ClothesCache and ClothesCache['shirts_full'] then
        savedPalette = ClothesCache['shirts_full'].palette
        savedTints = ClothesCache['shirts_full'].tints
    end
    
    -- Сбрасываем другой вариант рукавов
    ClothingModState.sleeves_rolled = false
    
    -- Переключаем состояние
    ClothingModState.sleeves_rolled_open = not ClothingModState.sleeves_rolled_open
    
    -- Анимация
    PlayClothingModAnimation('sleeves')
    Wait(500)
    
    -- Применяем вариацию
    local variation = ClothingModState.sleeves_rolled_open 
        and ClothingVariations.shirts.rolled_open 
        or ClothingVariations.shirts.base
    
    SetPedComponentVariation(ped, shirtHash, variation)
    UpdatePedVariation(ped)
    
    -- ВОССТАНАВЛИВАЕМ ЦВЕТ рубашки
    if savedPalette and savedTints then
        Wait(100)
        ApplyClothingColor(ped, 'shirts_full', savedPalette, savedTints)
        print('[Clothing] Restored color after sleeves2 toggle: ' .. savedPalette)
    end
    ReapplyVestOverShirt(ped)
    
    -- Уведомление
    local message = ClothingModState.sleeves_rolled_open and 'Рукава закатаны, воротник расстёгнут' or 'Рукава опущены, воротник застёгнут'
    TriggerEvent('ox_lib:notify', {
        title = 'Рукава',
        description = message,
        type = 'success'
    })
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
        UpdatePedVariation(ped)
        
        -- ВОССТАНАВЛИВАЕМ ЦВЕТ!
        if savedPalette and savedTints then
            Wait(100)
            ApplyClothingColor(ped, 'shirts_full', savedPalette, savedTints)
        end
        ReapplyVestOverShirt(ped)
        
        TriggerEvent('ox_lib:notify', {
            title = 'Воротник',
            description = 'Воротник расстёгнут',
            type = 'success'
        })
    elseif ClothingModState.sleeves_rolled_open then
        -- Переключаем на закрытый воротник с закатанными рукавами
        ClothingModState.sleeves_rolled_open = false
        ClothingModState.sleeves_rolled = true
        
        PlayClothingModAnimation('collar')
        Wait(500)
        
        SetPedComponentVariation(ped, shirtHash, ClothingVariations.shirts.rolled_closed)
        UpdatePedVariation(ped)
        
        -- ВОССТАНАВЛИВАЕМ ЦВЕТ!
        if savedPalette and savedTints then
            Wait(100)
            ApplyClothingColor(ped, 'shirts_full', savedPalette, savedTints)
        end
        ReapplyVestOverShirt(ped)
        
        TriggerEvent('ox_lib:notify', {
            title = 'Воротник',
            description = 'Воротник застёгнут',
            type = 'success'
        })
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
    else
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

    -- Уведомление
    local message = ClothingModState.bandana_up and 'Бандана поднята' or 'Бандана опущена'
    TriggerEvent('ox_lib:notify', {
        title = 'Бандана',
        description = message,
        type = 'success'
    })
end

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
        TaskPlayAnim(ped, dict, anim, 4.0, -4.0, duration, 49, 0, false, false, false)
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
    end
end

-- Хук на снятие одежды
RegisterNetEvent('rsg-clothing:client:removeClothing')
AddEventHandler('rsg-clothing:client:removeClothing', function(category)
    ResetClothingModState(category)
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
function GetCurrentShirtHash()
    -- Из кэша
    if ClothesCache and ClothesCache['shirts_full'] and type(ClothesCache['shirts_full']) == 'table' then
        local h = ClothesCache['shirts_full'].hash
        if h and h ~= 0 then
            return h
        end
    end
    
    -- Синхронный запрос через lib.callback
    local equippedItems = lib.callback.await('rsg-clothing:server:getEquippedClothingSync', false)
    
    if equippedItems and equippedItems['shirts_full'] then
        -- Обновляем весь кэш
        for category, data in pairs(equippedItems) do
            if not ClothesCache then ClothesCache = {} end
            ClothesCache[category] = data
        end
        return equippedItems['shirts_full'].hash
    end
    
    return nil
end

function GetCurrentNeckwearHash()
    if ClothesCache and ClothesCache['neckwear'] and type(ClothesCache['neckwear']) == 'table' then
        local h = ClothesCache['neckwear'].hash
        if h and h ~= 0 then
            return h
        end
    end
    
    local equippedItems = lib.callback.await('rsg-clothing:server:getEquippedClothingSync', false)
    
    if equippedItems and equippedItems['neckwear'] then
        for category, data in pairs(equippedItems) do
            if not ClothesCache then ClothesCache = {} end
            ClothesCache[category] = data
        end
        return equippedItems['neckwear'].hash
    end
    
    return nil
end
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
        TaskPlayAnim(ped, dict, anim, 4.0, -4.0, 1500, 51, 0, false, false, false)
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
                description = 'Качество: ' .. item.durability .. '%' .. statusText .. '\n+' .. tostring(20) .. '% после ремонта',
                metadata = {
                    {label = 'Текущее качество', value = item.durability .. '%'},
                    {label = 'После ремонта', value = math.min(100, item.durability + 20) .. '%'},
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
    NativeUpdatePedVariation(ped)
    
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
                NativeUpdatePedVariation(PlayerPedId())
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
        NativeUpdatePedVariation(ped)
        
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

RegisterNetEvent('rsg-appearance:client:ApplyClothes')
AddEventHandler('rsg-appearance:client:ApplyClothes', function(ClothesComponents, Target, SkinData)
    CreateThread(function()
        local _Target = Target or PlayerPedId()
        
        print('[RSG-Clothing] ApplyClothes called')
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
                ClothesCache[cat] = resolvedComponents[cat]
                applied[cat] = true
                phaseCount = phaseCount + 1
            end
        end
        if phaseCount > 0 then
            NativeUpdatePedVariation(_Target)
            Wait(100)
        end
        
        -- Фаза 2: Верхнее тело
        phaseCount = 0
        for _, cat in ipairs(upperOrder) do
            if resolvedComponents[cat] then
                NativeSetPedComponentEnabledClothes(_Target, resolvedComponents[cat].hash, false, true, true)
                ClothesCache[cat] = resolvedComponents[cat]
                applied[cat] = true
                phaseCount = phaseCount + 1
            end
        end
        if phaseCount > 0 then
            NativeUpdatePedVariation(_Target)
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
                    ClothesCache[k] = data
                    applied[k] = true
                    phaseCount = phaseCount + 1
                end
            end
        end
        if phaseCount > 0 then
            NativeUpdatePedVariation(_Target)
            Wait(100)
        end
        
        -- Фаза 4: Обувь ПОСЛЕДНЕЙ (поверх штанов)
        phaseCount = 0
        for _, cat in ipairs(lateOrder) do
            if resolvedComponents[cat] and not applied[cat] then
                NativeSetPedComponentEnabledClothes(_Target, resolvedComponents[cat].hash, false, true, true)
                ClothesCache[cat] = resolvedComponents[cat]
                applied[cat] = true
                phaseCount = phaseCount + 1
            end
        end
        if phaseCount > 0 then
            NativeUpdatePedVariation(_Target)
            Wait(100)
        end
        
        -- ПРИМЕНЯЕМ ЦВЕТА ПОСЛЕ ВСЕХ ХЕШЕЙ!
        for k, v in pairs(ClothesComponents) do
            if type(v) == 'table' and v.palette and v.tints then
                -- ★ ФИКС: Для Classic одежды НЕ применяем tint - цвет уже в hash!
                -- Если kaf="Classic" или kaf=nil (старые данные) с нулевыми tints - пропускаем
                local isClassic = (v.kaf == "Classic") or (v.kaf == nil and (not v.tints[1] or v.tints[1] == 0) and (not v.tints[2] or v.tints[2] == 0) and (not v.tints[3] or v.tints[3] == 0))
                
                if isClassic then
                    print('[RSG-Clothing] Skipping tint for ' .. k .. ' (Classic - color is in hash)')
                elseif v.palette ~= 'tint_generic_clean' or 
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
        
        -- ★ Сигнал creator.lua, что одежда полностью применена (до применения BodyMorph)
        _G._ApplyClothesComplete = true
        TriggerEvent('rsg-appearance:client:ApplyClothesComplete', _Target, SkinData)
        
        -- ★ После одежды и цветов морф тела сбрасывается — переприменяем body morph в самом конце
        if ReapplyBodyMorph then ReapplyBodyMorph(_Target) end
        NativeUpdatePedVariation(_Target)
        
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
    NativeUpdatePedVariation(ped)
    
    -- Теперь переодеваем всю одежду из кэша
    Wait(100)
    for cat, data in pairs(ClothesCache or {}) do
        if type(data) == 'table' and data.hash and data.hash ~= 0 then
            NativeSetPedComponentEnabledClothes(ped, data.hash, false, true, true)
            Wait(50)
        end
    end
    
    NativeUpdatePedVariation(ped)
    
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

RegisterCommand('fixcharacter', function()
    TriggerServerEvent('rsg-clothing:server:syncInventoryToDatabase')
    Wait(500)
    ExecuteCommand('loadskin')
    Wait(2500)
    LoadClothingFromInventory()
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

-- ★ Переопределяем LoadClothingFromInventory чтобы читать цвет из инвентаря
-- (Если ваша функция называется иначе, замените имя)

local OriginalLoadClothingFromInventory = LoadClothingFromInventory

LoadClothingFromInventory = function(callback)
    local isLightResyncPass = (activeInventoryResyncPasses or 0) > 0
    RSGCore.Functions.TriggerCallback('rsg-clothing:server:getEquippedClothing', function(equippedItems)
        local ped = PlayerPedId()
        
        -- ★ FIX: Снимаем дефолтную шляпу (кепка конфедерата) если в инвентаре нет надетой шляпы
        if not equippedItems or not equippedItems['hats'] then
            Citizen.InvokeNative(0xD710A5007C2AC539, ped, GetHashKey('hats'), 0)
            Citizen.InvokeNative(0xD710A5007C2AC539, ped, 0x9925C067, 0)
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
                
                if clothing[genderKey] and clothing[genderKey][category] then
                    if clothing[genderKey][category][model] then
                        if clothing[genderKey][category][model][texture] then
                            hashToUse = clothing[genderKey][category][model][texture].hash
                        elseif clothing[genderKey][category][model][1] then
                            hashToUse = clothing[genderKey][category][model][1].hash
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
                    kaf = data.kaf or "Classic",
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
        
        -- ★ ФИКС: Надеваем одежду В ПРАВИЛЬНОМ ПОРЯДКЕ (штаны -> обувь)
        -- ★ С ПОДДЕРЖКОЙ PED-ТИПА: Ped-одежда применяется через draw/albedo/normal/material
        local priorityOrder2 = {'pants', 'skirts', 'dresses', 'shirts_full', 'vests', 'coats', 'coats_closed'}
        local lateOrder2 = {'boots', 'boot_accessories', 'spurs', 'chaps', 'spats'}
        local applied2 = {}

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
            NativeUpdatePedVariation(ped)
            Wait(150)
        end

        -- ★ Фаза 2: Рубашки (базовый верхний слой)
        if ClothesCache['shirts_full'] and ClothesCache['shirts_full'].hash and ClothesCache['shirts_full'].hash ~= 0 then
            ApplyItem('shirts_full', ClothesCache['shirts_full'])
            applied2['shirts_full'] = true
            count = count + 1
            NativeUpdatePedVariation(ped)
            Wait(150)
        end

        -- ★ Фаза 3: Шейные слои (под жилеткой/пальто)
        local neckApplied = false
        for _, cat in ipairs({'neckwear', 'neckties'}) do
            if ClothesCache[cat] and ClothesCache[cat].hash and ClothesCache[cat].hash ~= 0 then
                ApplyItem(cat, ClothesCache[cat])
                applied2[cat] = true
                count = count + 1
                neckApplied = true
                Wait(50)
            end
        end
        if neckApplied then
            NativeUpdatePedVariation(ped)
            Wait(120)
        end

        -- ★ Фаза 4: Жилетки (средний слой — поверх рубашки/шеи)
        if ClothesCache['vests'] and ClothesCache['vests'].hash and ClothesCache['vests'].hash ~= 0 then
            ApplyItem('vests', ClothesCache['vests'])
            applied2['vests'] = true
            count = count + 1
            NativeUpdatePedVariation(ped)
            Wait(150)
        end

        -- ★ Фаза 5: Пальто (внешний слой — поверх жилетки)
        local coatApplied = false
        for _, cat in ipairs({'coats', 'coats_closed'}) do
            if ClothesCache[cat] and ClothesCache[cat].hash and ClothesCache[cat].hash ~= 0 then
                ApplyItem(cat, ClothesCache[cat])
                applied2[cat] = true
                count = count + 1
                coatApplied = true
                Wait(50)
            end
        end
        if coatApplied then
            NativeUpdatePedVariation(ped)
            Wait(150)
        end

        -- ★ Фаза 6: Остальные аксессуары (кроме обуви)
        local accessoryApplied = false
        for category, data in pairs(ClothesCache) do
            if not applied2[category] and data.hash and data.hash ~= 0 then
                local isLate = false
                for _, lc in ipairs(lateOrder2) do
                    if category == lc then isLate = true break end
                end
                if not isLate then
                    ApplyItem(category, data)
                    applied2[category] = true
                    count = count + 1
                    accessoryApplied = true
                    Wait(50)
                end
            end
        end
        if accessoryApplied then
            NativeUpdatePedVariation(ped)
            Wait(150)
        end
        
        -- ★ Фаза 7: Обувь ПОСЛЕДНЕЙ
        local bootsApplied = false
        for _, category in ipairs(lateOrder2) do
            if ClothesCache[category] and ClothesCache[category].hash and ClothesCache[category].hash ~= 0 and not applied2[category] then
                ApplyItem(category, ClothesCache[category])
                applied2[category] = true
                count = count + 1
                bootsApplied = true
                Wait(50)
            end
        end
        if bootsApplied then
            NativeUpdatePedVariation(ped)
            Wait(150)
        end
        
        -- ★ ПРИМЕНЯЕМ ЦВЕТА!
        for category, data in pairs(ClothesCache) do
            if data.palette and data.tints then
                local hasTints = data.tints[1] ~= 0 or data.tints[2] ~= 0 or data.tints[3] ~= 0
                local hasCustomPalette = data.palette ~= 'tint_generic_clean'
                
                if hasTints or hasCustomPalette then
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
        
        -- ★ После EnsureBodyIntegrity морф тела может сброситься — переприменяем (пузо/талия/телосложение)
        if ReapplyBodyMorph then ReapplyBodyMorph(ped) end
        NativeUpdatePedVariation(ped)
        
        -- ★ FIX: Обувь часто слетает после EnsureBodyIntegrity — переприменяем сразу
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
            NativeUpdatePedVariation(ped)
        end
        
        -- ★ ФИКС: Пальто, жилеты и шляпа часто не держатся после перезагрузки — переприменяем верхние слои и шляпу сразу
        -- В "лёгком" ресинке (после equip/remove) этот блок пропускаем, чтобы не вызывать мигание слоёв.
        local upperCats = {'shirts_full', 'vests', 'coats', 'coats_closed', 'hats'}
        if not isLightResyncPass then
            lastClothingLoadTime = GetGameTimer()
            local closedCoatActive = IsClosedCoatVisualOverrideActive()
            for _, cat in ipairs(upperCats) do
                if ClothesCache[cat] and ClothesCache[cat].hash and ClothesCache[cat].hash ~= 0 then
                    if not (closedCoatActive and IsHiddenUnderClosedCoat(cat)) then
                        ApplyItem(cat, ClothesCache[cat])
                        Wait(80)
                    end
                end
            end
            NativeUpdatePedVariation(ped)
            if ClothesCache['coats_closed'] and ClothesCache['coats_closed'].hash and ClothesCache['coats_closed'].hash ~= 0 then
                ApplyCoatAntiClipFix(ped, 'coats_closed')
            elseif ClothesCache['coats'] and ClothesCache['coats'].hash and ClothesCache['coats'].hash ~= 0 then
                ApplyCoatAntiClipFix(ped, 'coats')
            end
            Wait(100)
            for category, data in pairs(ClothesCache) do
                if data.palette and data.tints then
                    local skip = true
                    for _, c in ipairs(upperCats) do if category == c then skip = false break end end
                    if not skip and (data.tints[1] ~= 0 or data.tints[2] ~= 0 or data.tints[3] ~= 0 or data.palette ~= 'tint_generic_clean') then
                        ApplyClothingColor(ped, category, data.palette, data.tints)
                        Wait(30)
                    end
                end
            end
            NativeUpdatePedVariation(ped)
        end
        
        print('[RSG-Clothing] Loaded ' .. count .. ' items with colors')
        
        -- ★ Ранний ресинк верхней части (1.5 сек) — пальто/жилеты часто не успевают загрузиться с первого раза
        if not isLightResyncPass then
            local savedUpper = {}
            for _, c in ipairs(upperCats) do
                if ClothesCache[c] and ClothesCache[c].hash and ClothesCache[c].hash ~= 0 then
                    savedUpper[c] = ClothesCache[c]
                end
            end
            if next(savedUpper) then
                SetTimeout(1500, function()
                    local p = PlayerPedId()
                    if not p or not DoesEntityExist(p) then return end
                    local closedNow = IsClosedCoatVisualOverrideActive()
                    for _, cat in ipairs(upperCats) do
                        if savedUpper[cat] then
                            if not (closedNow and IsHiddenUnderClosedCoat(cat)) then
                                ApplyItem(cat, savedUpper[cat])
                                Wait(60)
                            end
                        end
                    end
                    NativeUpdatePedVariation(p)
                    if closedNow then
                        ApplyCoatAntiClipFix(p, 'coats_closed')
                    end
                end)
            end

            -- ★ FIX: Обувь часто не прогружается после reload — переприменяем как шляпу (1.5с и 3.5с)
            local bootCats = {'boots', 'boot_accessories', 'spurs', 'chaps', 'spats'}
            local savedBoots = {}
            for _, c in ipairs(bootCats) do
                if ClothesCache[c] and ClothesCache[c].hash and ClothesCache[c].hash ~= 0 then
                    savedBoots[c] = ClothesCache[c]
                end
            end
            if next(savedBoots) then
                for _, delay in ipairs({1500, 3500}) do
                    SetTimeout(delay, function()
                        local p = PlayerPedId()
                        if not p or not DoesEntityExist(p) then return end
                        for cat, item in pairs(savedBoots) do
                            Citizen.InvokeNative(0x59BD177A1A48600A, p, item.hash)
                            NativeSetPedComponentEnabledClothes(p, item.hash, true, true, true)
                            Wait(60)
                            if item.palette and item.tints and ApplyClothingColor then
                                ApplyClothingColor(p, cat, item.palette, item.tints)
                                Wait(30)
                            end
                        end
                        NativeUpdatePedVariation(p)
                    end)
                end
            end
        end
        
        -- ★ ОТЛОЖЕННАЯ РЕСИНХРОНИЗАЦИЯ (5 сек после начальной загрузки)
        -- При загрузке персонажа MetaPed система может быть ещё не полностью инициализирована,
        -- и компоненты одежды не регистрируются корректно (визуально видны, но не управляются).
        -- ★ FIX: Увеличено с 3с до 5с для высокого пинга
        if count > 0 and not isLightResyncPass then
            local savedCache = {}
            for cat, d in pairs(ClothesCache) do
                savedCache[cat] = d
            end
            
            SetTimeout(5000, function()
                local resyncPed = PlayerPedId()
                if not resyncPed or not DoesEntityExist(resyncPed) then return end
                local closedNow = IsClosedCoatVisualOverrideActive()
                
                print('[RSG-Clothing] ★ Resync: re-applying ' .. count .. ' items for proper MetaPed registration')
                
                -- Порядок переприменения: снизу вверх (как при equipClothing)
                local resyncOrder = {
                    'pants', 'skirts', 'dresses',
                    'shirts_full',
                    'neckwear', 'neckties',
                    'vests',
                    'coats', 'coats_closed',
                    'hats', 'eyewear', 'masks',
                    'gloves', 'gunbelts', 'satchels', 'suspenders',
                    'belts', 'cloaks', 'ponchos', 'chaps',
                    'boots', 'spurs',
                }
                
                -- Также переприменяем категории которых нет в списке
                local applied = {}
                
                for _, cat in ipairs(resyncOrder) do
                    if savedCache[cat] and savedCache[cat].hash and savedCache[cat].hash ~= 0 then
                        if closedNow and IsHiddenUnderClosedCoat(cat) then
                            applied[cat] = true
                            goto continue_resync_order
                        end
                        local itemData = savedCache[cat]
                        
                        if itemData.kaf == "Ped" and itemData.draw and itemData.draw ~= "" then
                            -- Ped-тип
                            if itemData.draw ~= "_" then
                                local drawHash = GetHashKey(itemData.draw)
                                Citizen.InvokeNative(0x59BD177A1A48600A, resyncPed, drawHash)
                                Citizen.InvokeNative(0xD3A7B003ED343FD9, resyncPed, drawHash, true, true, true)
                            end
                            if itemData.albedo and itemData.albedo ~= "" then
                                Citizen.InvokeNative(0x59BD177A1A48600A, resyncPed, GetHashKey(itemData.albedo))
                                Citizen.InvokeNative(0xD3A7B003ED343FD9, resyncPed, GetHashKey(itemData.albedo), true, true, true)
                            end
                        else
                            -- Classic-тип: Request + Apply + Wait for ready
                            NativeSetPedComponentEnabledClothes(resyncPed, itemData.hash, false, true, true)
                        end
                        
                        -- Индивидуальный Finalize + Update для каждого предмета
                        NativeUpdatePedVariation(resyncPed)
                        Wait(50)
                        
                        applied[cat] = true
                    end
                    ::continue_resync_order::
                end
                
                -- Категории не в списке
                for cat, itemData in pairs(savedCache) do
                    if not applied[cat] and itemData.hash and itemData.hash ~= 0 then
                        if closedNow and IsHiddenUnderClosedCoat(cat) then
                            goto continue_resync_rest
                        end
                        if itemData.kaf == "Ped" and itemData.draw and itemData.draw ~= "" then
                            if itemData.draw ~= "_" then
                                Citizen.InvokeNative(0x59BD177A1A48600A, resyncPed, GetHashKey(itemData.draw))
                                Citizen.InvokeNative(0xD3A7B003ED343FD9, resyncPed, GetHashKey(itemData.draw), true, true, true)
                            end
                        else
                            NativeSetPedComponentEnabledClothes(resyncPed, itemData.hash, false, true, true)
                        end
                        NativeUpdatePedVariation(resyncPed)
                        Wait(50)
                    end
                    ::continue_resync_rest::
                end
                
                -- Переприменяем цвета
                for cat, itemData in pairs(savedCache) do
                    if itemData.palette and itemData.tints then
                        if closedNow and IsHiddenUnderClosedCoat(cat) then
                            goto continue_resync_colors
                        end
                        local hasTints = itemData.tints[1] ~= 0 or itemData.tints[2] ~= 0 or itemData.tints[3] ~= 0
                        if hasTints or itemData.palette ~= 'tint_generic_clean' then
                            ApplyClothingColor(resyncPed, cat, itemData.palette, itemData.tints)
                            Wait(30)
                        end
                    end
                    ::continue_resync_colors::
                end
                
                -- Финальный морф тела
                if ReapplyBodyMorph then ReapplyBodyMorph(resyncPed) end
                if closedNow then
                    ApplyCoatAntiClipFix(resyncPed, 'coats_closed')
                end
                
                print('[RSG-Clothing] ★ Resync complete — all items re-registered in MetaPed')
            end)
        end
        
        if callback then callback(true, count) end
    end)
end

-- ★ Патч для ToggleSleeves - уже должен сохранять цвет, но на всякий случай
local OriginalToggleSleeves = ToggleSleeves

ToggleSleeves = function()
    local ped = PlayerPedId()
    
    -- Сохраняем цвет ПЕРЕД сменой
    local savedPalette = nil
    local savedTints = nil
    
    if ClothesCache['shirts_full'] then
        savedPalette = ClothesCache['shirts_full'].palette
        savedTints = ClothesCache['shirts_full'].tints
    end
    
    -- Вызываем оригинальную функцию
    OriginalToggleSleeves()
    
    -- Восстанавливаем цвет ПОСЛЕ смены (с задержкой)
    if savedPalette and savedTints then
        SetTimeout(1200, function()
            if ClothesCache['shirts_full'] then
                ClothesCache['shirts_full'].palette = savedPalette
                ClothesCache['shirts_full'].tints = savedTints
                ApplyClothingColor(ped, 'shirts_full', savedPalette, savedTints)
            end
        end)
    end
end

-- ★ Событие от clothing-modifier для обновления цвета в кэше
RegisterNetEvent('rsg-appearance:updateClothingColor', function(category, palette, tints)
    if ClothesCache and ClothesCache[category] then
        ClothesCache[category].palette = palette
        ClothesCache[category].tints = tints
        print('[RSG-Clothing] Updated cache color for ' .. category)
    end
end)

print('[RSG-Appearance] Color preservation patch loaded')