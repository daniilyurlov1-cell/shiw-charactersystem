-- ==========================================
-- СТАРТОВАЯ ОДЕЖДА ДЛЯ СОЗДАНИЯ ПЕРСОНАЖА
-- Хеши взяты из clothing.lua - первые модели каждой категории
-- ==========================================

StarterClothingOptions = {
    male = {
        -- Рубашки (модели 1-5)
        shirts_full = {
            { model = 1, texture = 1, hash = 2795762245 },  -- FRONTIER_SHIRT_000
            { model = 2, texture = 1, hash = 4004347424 },  -- OUTLAW_SHIRT_000
            { model = 3, texture = 1, hash = 0 },           -- placeholder
            { model = 4, texture = 1, hash = 0 },
            { model = 5, texture = 1, hash = 0 },
        },
        
        -- Штаны (модели 1-5)
        pants = {
            { model = 1, texture = 1, hash = 1094172669 },  -- FRONTIER_PANTS_000
            { model = 2, texture = 1, hash = 2807053654 },  -- OUTLAW_PANTS_000
            { model = 3, texture = 1, hash = 0 },
            { model = 4, texture = 1, hash = 0 },
            { model = 5, texture = 1, hash = 0 },
        },
        
        -- Сапоги (модели 1-5)
        boots = {
            { model = 1, texture = 1, hash = 4076107613 },  -- BOOTS_000_TINT_001
            { model = 1, texture = 2, hash = 93297815 },    -- BOOTS_000_TINT_002
            { model = 2, texture = 1, hash = 0 },
            { model = 3, texture = 1, hash = 0 },
            { model = 4, texture = 1, hash = 0 },
        },
        
        -- Пальто (модели 1-5)
        coats = {
            { model = 1, texture = 1, hash = 3349172660 },  -- COAT_000_TINT_001
            { model = 1, texture = 2, hash = 543785797 },   -- COAT_000_TINT_002
            { model = 1, texture = 3, hash = 1429728481 },  -- COAT_000_TINT_003
            { model = 2, texture = 1, hash = 0 },
            { model = 3, texture = 1, hash = 0 },
        },
        
        -- Шляпы (модели 1-2)
        hats = {
            { model = 1, texture = 1, hash = 1820410246 },  -- FRONTIER_HAT_000
            { model = 2, texture = 1, hash = 2754281087 },  -- HAT_000_TINT_001
        },
    },
    
    female = {
        -- Рубашки
        shirts_full = {
            { model = 1, texture = 1, hash = 3726847883 },  -- CHEMISE_000_TINT_001
            { model = 1, texture = 2, hash = 610548752 },   -- CHEMISE_000_TINT_002
            { model = 1, texture = 3, hash = 4010332502 },  -- CHEMISE_000_TINT_003
            { model = 2, texture = 1, hash = 0 },
            { model = 3, texture = 1, hash = 0 },
        },
        
        -- Штаны/Юбки
        pants = {
            { model = 1, texture = 1, hash = 3545812420 },  -- FRONTIER_PANTS_000
            { model = 2, texture = 1, hash = 1680224254 },  -- OUTLAW_PANTS_000
            { model = 3, texture = 1, hash = 1570272012 },  -- OVERALLS_001_TINT_001
            { model = 4, texture = 1, hash = 0 },
            { model = 5, texture = 1, hash = 0 },
        },
        
        -- Сапоги
        boots = {
            { model = 1, texture = 1, hash = 3723064563 },  -- BOOTS_000_TINT_001
            { model = 1, texture = 2, hash = 1881839991 },  -- BOOTS_000_TINT_002
            { model = 1, texture = 3, hash = 4045806460 },  -- BOOTS_000_TINT_003
            { model = 1, texture = 4, hash = 23641089 },    -- BOOTS_000_TINT_004
            { model = 2, texture = 1, hash = 0 },
        },
        
        -- Пальто
        coats = {
            { model = 1, texture = 1, hash = 1578729681 },  -- first coat
            { model = 1, texture = 2, hash = 1879581870 },
            { model = 1, texture = 3, hash = 948647349 },
            { model = 2, texture = 1, hash = 3555396598 },
            { model = 3, texture = 1, hash = 0 },
        },
        
        -- Шляпы
        hats = {
            { model = 1, texture = 1, hash = 1431102593 },  -- SEASON3_HAT_001
            { model = 3, texture = 1, hash = 3313189151 },  -- FRONTIER_HAT_000
        },
    },
}

-- ==========================================
-- ФУНКЦИИ
-- ==========================================

-- Получить опции стартовой одежды для пола
function GetStarterClothingOptions(isMale)
    return isMale and StarterClothingOptions.male or StarterClothingOptions.female
end

-- Проверка является ли это стартовой одеждой
function IsStarterClothing(category, hash, isMale)
    local options = GetStarterClothingOptions(isMale)
    if not options[category] then return false end
    
    for _, item in ipairs(options[category]) do
        if item.hash == hash then
            return true
        end
    end
    
    return false
end

-- Получить количество стартовых вариантов
function GetStarterClothingCount(category, isMale)
    local options = GetStarterClothingOptions(isMale)
    if not options[category] then return 0 end
    
    local count = 0
    for _, item in ipairs(options[category]) do
        if item.hash and item.hash > 0 then
            count = count + 1
        end
    end
    
    return count
end

-- Получить стартовую одежду по индексу
function GetStarterClothingByIndex(category, index, isMale)
    local options = GetStarterClothingOptions(isMale)
    if not options[category] then return nil end
    if not options[category][index] then return nil end
    
    return options[category][index]
end

return {
    StarterClothingOptions = StarterClothingOptions,
    GetStarterClothingOptions = GetStarterClothingOptions,
    IsStarterClothing = IsStarterClothing,
    GetStarterClothingCount = GetStarterClothingCount,
    GetStarterClothingByIndex = GetStarterClothingByIndex,
}
