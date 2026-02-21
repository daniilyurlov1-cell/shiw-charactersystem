local RSGCore = exports['rsg-core']:GetCoreObject()

-- ==========================================
-- ROUTING BUCKETS
-- ==========================================
RegisterNetEvent('rsg-clothingstore:server:setPrivateBucket', function(playerId)
    local src = source
    local bucket = 1000 + src
    SetPlayerRoutingBucket(src, bucket)
    print('[RSG-ClothingStore] Player ' .. src .. ' moved to bucket ' .. bucket)
end)

RegisterNetEvent('rsg-clothingstore:server:setNormalBucket', function()
    local src = source
    SetPlayerRoutingBucket(src, 0)
    print('[RSG-ClothingStore] Player ' .. src .. ' returned to bucket 0')
end)

-- ==========================================
-- НАЗВАНИЯ КАТЕГОРИЙ
-- ==========================================
local categoryLabels = {
    ['hats'] = 'Шляпа',
    ['shirts_full'] = 'Рубашка',
    ['pants'] = 'Штаны',
    ['boots'] = 'Сапоги',
    ['vests'] = 'Жилет',
    ['coats'] = 'Пальто',
    ['coats_closed'] = 'Пальто',
    ['gloves'] = 'Перчатки',
    ['neckwear'] = 'Шейный платок',
    ['masks'] = 'Маска',
    ['eyewear'] = 'Очки',
    ['gunbelts'] = 'Патронташ',
    ['satchels'] = 'Сумка',
    ['skirts'] = 'Юбка',
    ['chaps'] = 'Чапсы',
    ['spurs'] = 'Шпоры',
    ['suspenders'] = 'Подтяжки',
    ['belts'] = 'Ремень',
    ['cloaks'] = 'Плащ',
    ['ponchos'] = 'Пончо',
    ['gauntlets'] = 'Наручи',
    ['neckties'] = 'Галстук',
    ['dresses'] = 'Платье',
    ['loadouts'] = 'Снаряжение',
    ['holsters_left'] = 'Кобура',
    ['holsters_right'] = 'Кобура',
    ['belt_buckles'] = 'Пряжка',
    ['accessories'] = 'Аксессуар',
    ['badges'] = 'Значок',
    ['corsets'] = 'Корсет',
    ['rings_rh'] = 'Кольцо (правая рука)',
    ['rings_lh'] = 'Кольцо (левая рука)',
    ['bracelets'] = 'Браслет',
    ['necklaces'] = 'Ожерелье',
    ['jewelry_rings_right'] = 'Кольцо (правая рука)',
    ['jewelry_rings_left'] = 'Кольцо (левая рука)',
    ['jewelry_bracelets'] = 'Браслет',
    ['boot_accessories'] = 'Аксессуары для обуви',
    ['earrings'] = 'Серьги',
}

-- ==========================================
-- СОЗДАНИЕ МЕТАДАННЫХ (ПОЛНЫЕ ДАННЫЕ ДЛЯ ПРИМЕНЕНИЯ)
-- ==========================================
local function CreateClothingItemInfo(category, item, isMale, durability)
    durability = durability or 100
    local label = categoryLabels[category] or category
    
    -- Для Classic - hash напрямую
    -- Для Ped - нужны все компоненты (Draw, alb, norm, mat)
    local hash = 0
    local isClassic = item.Kaf == "Classic"
    
    if isClassic then
        if type(item.Hash) == "string" then
            hash = tonumber(item.Hash, 16) or 0
        else
            hash = item.Hash or 0
        end
    else
        -- Для Ped вычисляем hash из Draw
        if item.Draw and item.Draw ~= "" and item.Draw ~= "_" then
            hash = GetHashKey(item.Draw)
        end
    end
    
    -- Palette и tints
    local palette = item.pal or 'tint_generic_clean'
    if palette == " " or palette == "" then
        palette = 'tint_generic_clean'
    end
    
    local tints = {
        tonumber(item.palette1) or 0,
        tonumber(item.palette2) or 0,
        tonumber(item.palette3) or 0
    }
    
    -- ВАЖНО: Сохраняем ВСЕ данные для корректного применения
    return {
        -- Короткие ключи
        _c = category,
        _h = hash,
        _m = 0,
        _t = 1,
        _g = isMale,
        _e = true,
        _d = durability,
        _q = math.floor(durability),
        _p = palette,
        _tints = tints,
        
        -- Длинные ключи
        category = category,
        hash = hash,
        model = 0,
        texture = 1,
        isMale = isMale,
        equipped = true,
        durability = durability,
        quality = math.floor(durability),
        palette = palette,
        tints = tints,
        
        -- Название
        label = item.name,
        description = item.name,
        
        -- ★ ПОЛНЫЕ ДАННЫЕ ДЛЯ ПРИМЕНЕНИЯ (используются в rsg-appearance)
        _kaf = isClassic and "Classic" or "Ped",
        _draw = item.Draw or "",
        _alb = item.alb or "",
        _norm = item.norm or "",
        _mat = item.mat or 0,
        
        -- Дубли для совместимости
        kaf = isClassic and "Classic" or "Ped",
        draw = item.Draw or "",
        albedo = item.alb or "",
        normal = item.norm or "",
        material = item.mat or 0,
    }
end

-- ==========================================
-- ПОКУПКА ТОВАРА
-- ==========================================
RegisterNetEvent('rsg-clothingstore:server:buyItem', function(item, storeId, isMale)
    local src = source
    local Player = RSGCore.Functions.GetPlayer(src)
    
    if not Player then return end
    if not item then return end
    
    local price = item.price or 0
    local playerMoney = Player.PlayerData.money.cash or 0
    
    if playerMoney < price then
        TriggerClientEvent('rsg-clothingstore:client:purchaseFailed', src, 'Недостаточно денег')
        return
    end

    local category = item.category or 'accessories'
    local itemName = Config.CategoryToItem[category] or 'clothing_accessories'
    -- ★ Убрана проверка CanAddItem — часто даёт false при наличии места; полагаемся на AddItem
    local success = Player.Functions.RemoveMoney('cash', price, 'clothing-purchase')
    
    if not success then
        TriggerClientEvent('rsg-clothingstore:client:purchaseFailed', src, 'Ошибка оплаты')
        return
    end
    
    -- Создаём info с ПОЛНЫМИ данными
    local info = CreateClothingItemInfo(category, item, isMale, 100)
    
    print('[RSG-ClothingStore] Creating item with:')
    print('  category: ' .. tostring(category))
    print('  kaf: ' .. tostring(info._kaf))
    print('  hash: ' .. tostring(info._h))
    print('  draw: ' .. tostring(info._draw))
    print('  alb: ' .. tostring(info._alb))
    
    -- Выдаём предмет
    local added = Player.Functions.AddItem(itemName, 1, nil, info)
    
    if not added then
        Player.Functions.AddMoney('cash', price, 'clothing-refund')
        TriggerClientEvent('rsg-clothingstore:client:purchaseFailed', src, 'Нет места в инвентаре')
        return
    end
    
    -- Обновляем UI инвентаря
    TriggerClientEvent('rsg-core:client:inventory:client:ItemBox', src, RSGCore.Shared.Items[itemName], 'add', 1)
    
    local newMoney = Player.PlayerData.money.cash
    TriggerClientEvent('rsg-clothingstore:client:purchaseSuccess', src, item, newMoney)
    
    print(string.format('[RSG-ClothingStore] %s bought %s (%s) for $%.2f', 
        Player.PlayerData.charinfo.firstname .. ' ' .. Player.PlayerData.charinfo.lastname,
        item.name,
        itemName,
        price
    ))
end)

-- ==========================================
-- CALLBACK
-- ==========================================
RSGCore.Functions.CreateCallback('rsg-clothingstore:server:getPlayerMoney', function(source, cb)
    local Player = RSGCore.Functions.GetPlayer(source)
    if Player then
        cb(Player.PlayerData.money.cash or 0)
    else
        cb(0)
    end
end)
