-- ==========================================
-- RSG-APPEARANCE HTML UI v3.0
-- Полная замена rsg-menubase на HTML
-- ==========================================

local RSGCore = exports['rsg-core']:GetCoreObject()
local clothing = require 'data.clothing'
local Data = require 'data.features'

local isUIOpen = false
local currentMode = nil -- 'creator' или 'shop'
local currentClothingCategory = nil
local isMouseDraggingPed = false
local lastMouseX = nil

local function IsCursorOverPedArea(cursorX, cursorY)
    -- Character is centered in creator scene; this avoids rotating while clicking edge UI.
    return cursorX > 0.25 and cursorX < 0.75 and cursorY > 0.10 and cursorY < 0.92
end

-- ★ Локальная функция для обновления вариации педа
-- (NativeUpdatePedVariation в creator.lua объявлена как local и не видна здесь)
local function NativeUpdatePedVariation(ped)
    Citizen.InvokeNative(0x704C908E9C405136, ped)
    Citizen.InvokeNative(0xCC8CA3E88256E58F, ped, false, true, true, true, false)
end

-- Получить педа для кастомизации (CreatorPed или PlayerPed)
local function GetTargetPed()
    if CreatorPed and DoesEntityExist(CreatorPed) then
        return CreatorPed
    end
    return PlayerPedId()
end

-- ==========================================
-- ФУНКЦИИ ОТКРЫТИЯ UI
-- ==========================================

function OpenCreatorHTML(step)
    if isUIOpen then return end
    
    isUIOpen = true
    currentMode = 'creator'
    
    local ped = GetTargetPed()
    
    SendNUIMessage({
        action = 'openCreator',
        step = step or 'gender',
        isMale = IsPedMale(ped),
        cache = CreatorCache or {}
    })
    
    SetNuiFocus(true, true)
end

function OpenShopHTML()
    if isUIOpen then return end
    
    isUIOpen = true
    currentMode = 'shop'
    
    SendNUIMessage({
        action = 'openShop',
        clothesCache = ClothesCache or {},
        oldClothesCache = OldClothesCache or {}
    })
    
    SetNuiFocus(true, true)
end

function CloseHTML()
    if not isUIOpen then return end
    
    isUIOpen = false
    currentMode = nil
    currentClothingCategory = nil
    
    SendNUIMessage({ action = 'close' })
    SetNuiFocus(false, false)
end

-- ==========================================
-- ПЕРЕХВАТ ФУНКЦИЙ rsg-menubase
-- ==========================================

-- Заменяем FirstMenu
local _originalFirstMenu = FirstMenu
function FirstMenu()
    OpenCreatorHTML('gender')
end

-- Заменяем MainMenu
local _originalMainMenu = MainMenu
function MainMenu()
    if isUIOpen then
        -- UI уже открыт - обновляем
        SendNUIMessage({
            action = 'setCache',
            cache = CreatorCache or {}
        })
    else
        OpenCreatorHTML('customize')
    end
end

-- Заменяем все остальные меню - они теперь в HTML
function OpenBodyMenu() MainMenu() end
function OpenFaceMenu() MainMenu() end
function OpenHairMenu() MainMenu() end
function OpenMakeupMenu() MainMenu() end
function OpenEyesMenu() MainMenu() end
function OpenNoseMenu() MainMenu() end
function OpenMouthMenu() MainMenu() end
function OpenJawMenu() MainMenu() end
function OpenChinMenu() MainMenu() end
function OpenEarsMenu() MainMenu() end
function OpenCheekbonesMenu() MainMenu() end
function OpenEyelidsMenu() MainMenu() end
function OpenEyebrowsMenu() MainMenu() end
function OpenDefectsMenu() MainMenu() end

-- ==========================================
-- NUI CALLBACKS - СОЗДАНИЕ ПЕРСОНАЖА
-- ==========================================

RegisterNUICallback('selectGender', function(data, cb)
    local isMale = data.isMale
    local newSex = isMale and 1 or 2
    
    print('[RSG-Appearance] selectGender: isMale=' .. tostring(isMale) .. ' current=' .. tostring(Selectedsex))
    
    -- Если пол не изменился - ничего не делаем
    if Selectedsex == newSex then
        cb('ok')
        return
    end
    
    Selectedsex = newSex
    
    -- Пересоздаём педа в фоне
    CreateThread(function()
        DoScreenFadeOut(200)
        Wait(200)
        
        -- Удаляем старого педа
        if CreatorPed and DoesEntityExist(CreatorPed) then
            DeleteEntity(CreatorPed)
            CreatorPed = nil
        end
        
        local modelName = isMale and 'mp_male' or 'mp_female'
        local gender = isMale and 'male' or 'female'
        local coords = {x = -559.6, y = -3781.0, z = 237.55, h = 110.0}
        
        -- Загружаем модель
        local modelHash = GetHashKey(modelName)
        RequestModel(modelHash, false)
        while not HasModelLoaded(modelHash) do
            Wait(10)
        end
        
        -- Создаём нового педа
        CreatorPed = CreatePed(modelHash, coords.x, coords.y, coords.z, coords.h, true, false, false, false)
        
        Wait(100)
        
        -- Инициализация MP педа
        Citizen.InvokeNative(0x283978A15512B2FE, CreatorPed, true)
        Citizen.InvokeNative(0x58A850EAEE20FAA3, CreatorPed)
        
        NetworkSetEntityInvisibleToNetwork(CreatorPed, true)
        FreezeEntityPosition(CreatorPed, true)
        
        Wait(200)
        
        -- Сбрасываем кэш с правильными значениями
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
        
        -- Очищаем ВСЕ компоненты включая гильзы
        FixIssues(CreatorPed)
        
        -- Дополнительно убираем гильзы разными способами
        Citizen.InvokeNative(0xD710A5007C2AC539, CreatorPed, GetHashKey("gunbelts"), 0)
        Citizen.InvokeNative(0xD710A5007C2AC539, CreatorPed, GetHashKey("loadouts"), 0)
        Citizen.InvokeNative(0xD710A5007C2AC539, CreatorPed, GetHashKey("holsters_left"), 0)
        Citizen.InvokeNative(0xD710A5007C2AC539, CreatorPed, GetHashKey("holsters_right"), 0)
        Citizen.InvokeNative(0xD710A5007C2AC539, CreatorPed, GetHashKey("belt_buckles"), 0)
        Citizen.InvokeNative(0xD710A5007C2AC539, CreatorPed, 0xF1542D11, 0)  -- gunbelts hash
        Citizen.InvokeNative(0xD710A5007C2AC539, CreatorPed, 0x9B2C8B89, 0)  -- loadouts hash
        Citizen.InvokeNative(0xD710A5007C2AC539, CreatorPed, 0x877A2CF7, 0)  -- ammo belts
        Citizen.InvokeNative(0xD710A5007C2AC539, CreatorPed, 0x72E6EF74, 0)  -- accessories
        
        Wait(100)
        
        -- ВАЖНО: Сначала тело, потом голова - это гарантирует одинаковый тон!
        LoadBoody(CreatorPed, CreatorCache)
        Wait(150)
        LoadHead(CreatorPed, CreatorCache)
        Wait(100)
        LoadEyes(CreatorPed, CreatorCache)
        Wait(50)
        
        -- Размеры тела
        LoadBodyFeature(CreatorPed, CreatorCache.body_size, Data.Appearance.body_size)
        LoadBodyFeature(CreatorPed, CreatorCache.body_waist, Data.Appearance.body_waist)
        LoadBodyFeature(CreatorPed, CreatorCache.chest_size, Data.Appearance.chest_size)
        
        -- Убираем штаны
        Citizen.InvokeNative(0xD710A5007C2AC539, CreatorPed, GetHashKey("pants"), 0)
        
        Citizen.InvokeNative(0x704C908E9C405136, CreatorPed)
        Citizen.InvokeNative(0xCC8CA3E88256E58F, CreatorPed, false, true, true, true, false)
        if ReapplyBodyMorph then ReapplyBodyMorph(CreatorPed) end
        
        Wait(100)
        DoScreenFadeIn(200)
        
        print('[RSG-Appearance] Gender changed to: ' .. gender)
    end)
    
    cb('ok')
end)

RegisterNUICallback('confirmGender', function(data, cb)
    local isMale = data.isMale
    Selectedsex = isMale and 1 or 2
    
    print('[RSG-Appearance] confirmGender: isMale=' .. tostring(isMale))
    
    -- Устанавливаем начальные значения
    CreatorCache = {
        sex = isMale and 1 or 2,
        head = 1,
        skin_tone = 1,
        body_size = 3,
        body_waist = 11,
        chest_size = 6,
        height = 100,
    }
    
    local ped = GetTargetPed()
    print('[RSG-Appearance] confirmGender applying to ped: ' .. tostring(ped))
    
    LoadHead(ped, CreatorCache)
    LoadBoody(ped, CreatorCache)
    NativeUpdatePedVariation(ped)
    
    cb('ok')
end)

RegisterNUICallback('selectCategory', function(data, cb)
    currentClothingCategory = data.category or data.subcategory
    
    if currentMode == 'shop' and currentClothingCategory then
        -- Получаем максимум моделей
        local ped = GetTargetPed()
        local isMale = IsPedMale(ped)
        local gender = isMale and 'male' or 'female'
        local maxModels = 0
        
        if clothing[gender] and clothing[gender][currentClothingCategory] then
            for model, _ in pairs(clothing[gender][currentClothingCategory]) do
                if type(model) == 'number' and model > maxModels then
                    maxModels = model
                end
            end
        end
        
        SendNUIMessage({ action = 'updateMax', id = 'model', max = maxModels })
    end
    
    cb('ok')
end)

RegisterNUICallback('updateValue', function(data, cb)
    local id = data.id
    local value = data.value
    local ped = GetTargetPed()
    
    print('[RSG-Appearance] updateValue: id=' .. tostring(id) .. ' value=' .. tostring(value) .. ' ped=' .. tostring(ped))
    
    -- Сохраняем
    if id == 'hair_model' or id == 'hair_color' then
        if not CreatorCache['hair'] then
            CreatorCache['hair'] = { model = 0, color = 1 }
        end
        if id == 'hair_model' then
            CreatorCache['hair'].model = value
        else
            CreatorCache['hair'].color = value
        end
        CreatorCache['hair_color'] = CreatorCache['hair'].color
        LoadHair(ped, CreatorCache)
        
    elseif id == 'beard_model' or id == 'beard_color' then
        if not CreatorCache['beard'] then
            CreatorCache['beard'] = { model = 0, color = 1 }
        end
        if id == 'beard_model' then
            CreatorCache['beard'].model = value
        else
            CreatorCache['beard'].color = value
        end
        CreatorCache['beard_color'] = CreatorCache['beard'].color
        LoadBeard(ped, CreatorCache)
        
    else
        CreatorCache[id] = value
        
        -- Применяем
        if id == 'head' then
            LoadHead(ped, CreatorCache)
        elseif id == 'skin_tone' then
            LoadHead(ped, CreatorCache)
            LoadBoody(ped, CreatorCache)
        elseif id == 'body_size' or id == 'body_waist' or id == 'chest_size' then
            -- ★ Полный body morph: хеши + face features
            -- ApplyAllBodyMorph применяет ВСЕ компоненты тела (хеши + face features)
            -- и сохраняет в _G._BodyMorphData для guard/reapply
            ApplyAllBodyMorph(ped, CreatorCache)
            -- UpdatePedVariation нужен чтобы хеш-компоненты отрисовались
            NativeUpdatePedVariation(ped)
            -- Но UpdatePedVariation сбрасывает face features — переприменяем
            Wait(50)
            ReapplyBodyMorph(ped)
        elseif id == 'height' then
            LoadHeight(ped, CreatorCache)
        elseif id == 'eyes_color' then
            LoadEyes(ped, CreatorCache)
        -- Стартовая одежда
        elseif id == 'shirt_model' then
            LoadStarterClothing(ped, 'shirts_full', value, 1)
        elseif id == 'pants_model' then
            LoadStarterClothing(ped, 'pants', value, 1)
        elseif id == 'boots_model' then
            LoadStarterClothing(ped, 'boots', value, 1)
        elseif string.find(id, '_t') or string.find(id, '_op') then
            LoadOverlays(ped, CreatorCache)
        else
            -- Черты лица (включая eyes_depth, eyes_angle и т.д.)
            LoadFeatures(ped, CreatorCache)
            
            -- ВАЖНО: После изменения черт лица переприменяем размеры тела!
            -- Иначе тело сбрасывается на дефолт
            Wait(50)
            if CreatorCache.body_size or CreatorCache.body_waist or CreatorCache.chest_size then
                ApplyAllBodyMorph(ped, CreatorCache)
                NativeUpdatePedVariation(ped)
                Wait(50)
                ReapplyBodyMorph(ped)
            end
        end
    end
    
    -- ★ УБРАНО: NativeUpdatePedVariation больше НЕ вызывается безусловно в конце.
    -- Каждый обработчик (LoadHead, LoadBoody, LoadEyes, LoadOverlays, LoadStarterClothing)
    -- уже вызывает UpdatePedVariation внутри себя.
    -- Body слайдеры обработаны выше с правильной последовательностью.
    -- Height использует SetPedScale, который не требует UpdatePedVariation.
    cb('ok')
end)

-- Проверка: строка содержит только кириллицу, пробелы и дефисы (без латиницы, цифр, спецсимволов)
local function isCyrillicOnly(str)
    if not str or str == '' then return false end
    -- Убираем допустимые символы (пробелы и дефисы)
    local cleaned = str:gsub('[%s%-]', '')
    if cleaned == '' then return false end
    -- Проверяем на наличие запрещённых символов: латиница, цифры, спецсимволы
    if cleaned:match('[a-zA-Z]') then return false end
    if cleaned:match('[%d]') then return false end
    if cleaned:match('[!@#$%%%^&*%(%)_+=~`%[%]{}<>|/\\%.,%?;:\"\']') then return false end
    return true
end

RegisterNUICallback('confirmCreator', function(data, cb)
    local firstname = data.firstname
    local lastname = data.lastname
    local nationality = data.nationality
    local birthdate = data.birthdate
    
    -- Валидация
    if not firstname or #firstname < 2 then
        TriggerEvent('ox_lib:notify', { 
            title = 'Ошибка', 
            description = 'Введите имя (мин. 2 символа)', 
            type = 'error' 
        })
        cb({ success = false })
        return
    end
    
    if not isCyrillicOnly(firstname) then
        TriggerEvent('ox_lib:notify', { 
            title = 'Ошибка', 
            description = 'Имя должно содержать только кириллицу', 
            type = 'error' 
        })
        cb({ success = false })
        return
    end
    
    if not lastname or #lastname < 2 then
        TriggerEvent('ox_lib:notify', { 
            title = 'Ошибка', 
            description = 'Введите фамилию (мин. 2 символа)', 
            type = 'error' 
        })
        cb({ success = false })
        return
    end
    
    if not isCyrillicOnly(lastname) then
        TriggerEvent('ox_lib:notify', { 
            title = 'Ошибка', 
            description = 'Фамилия должна содержать только кириллицу', 
            type = 'error' 
        })
        cb({ success = false })
        return
    end
    
    -- Сохраняем данные
    Firstname = firstname
    Lastname = lastname
    Nationality = nationality or ''
    Birthdate = birthdate or '1870-01-01'
    
    -- Добавляем пол в кэш
    CreatorCache.sex = Selectedsex
    CreatorCache.model = Selectedsex == 1 and 'mp_male' or 'mp_female'
    
    -- Собираем одежду с хешами
    local isMale = Selectedsex == 1
    local gender = isMale and 'male' or 'female'
    
    -- Функция для получения хеша одежды
    local function GetClothingHash(category, model, texture)
        texture = texture or 1
        if model <= 0 then return 0 end
        
        if clothing[gender] and clothing[gender][category] then
            if clothing[gender][category][model] and clothing[gender][category][model][texture] then
                return clothing[gender][category][model][texture].hash
            elseif clothing[gender][category][model] and clothing[gender][category][model][1] then
                return clothing[gender][category][model][1].hash
            end
        end
        return 0
    end
    
    local shirtModel = CreatorCache.shirt_model or 0
    local pantsModel = CreatorCache.pants_model or 0
    local bootsModel = CreatorCache.boots_model or 0
    
    local clothesData = {
        shirts_full = {
            model = shirtModel,
            texture = 1,
            hash = GetClothingHash('shirts_full', shirtModel, 1)
        },
        pants = {
            model = pantsModel,
            texture = 1,
            hash = GetClothingHash('pants', pantsModel, 1)
        },
        boots = {
            model = bootsModel,
            texture = 1,
            hash = GetClothingHash('boots', bootsModel, 1)
        },
    }
    
    print('[RSG-Appearance] Starter clothes with hashes:')
    print('  shirts_full: model=' .. shirtModel .. ' hash=' .. tostring(clothesData.shirts_full.hash))
    print('  pants: model=' .. pantsModel .. ' hash=' .. tostring(clothesData.pants.hash))
    print('  boots: model=' .. bootsModel .. ' hash=' .. tostring(clothesData.boots.hash))
    
    -- Закрываем UI
    CloseHTML()
    
    -- Фейд
    DoScreenFadeOut(500)
    Wait(500)
    
    -- Закрываем камеру и удаляем педа создания
    DestroyCreatorCamera()
    
    -- Применяем модель к игроку
    local modelName = Selectedsex == 1 and 'mp_male' or 'mp_female'
    local modelHash = GetHashKey(modelName)
    
    RequestModel(modelHash, false)
    while not HasModelLoaded(modelHash) do
        Wait(10)
    end
    
    SetPlayerModel(PlayerId(), modelHash, true)
    
    local playerPed = PlayerPedId()
    
    -- Инициализация MP педа
    Citizen.InvokeNative(0x283978A15512B2FE, playerPed, true)
    Citizen.InvokeNative(0x58A850EAEE20FAA3, playerPed)
    
    Wait(200)
    
    -- Применяем внешность к игроку
    local isMale = Selectedsex == 1
    local gender = isMale and 'male' or 'female'
    
    ApplyCreatorComponents(playerPed, gender, CreatorCache)
    
    -- Применяем волосы и бороду
    if CreatorCache.hair then
        LoadHair(playerPed, CreatorCache)
    end
    if CreatorCache.beard and isMale then
        LoadBeard(playerPed, CreatorCache)
    end
    
    -- Применяем одежду - используем хеши напрямую
    if clothesData.shirts_full.hash and clothesData.shirts_full.hash ~= 0 then
        Citizen.InvokeNative(0xD3A7B003ED343FD9, playerPed, clothesData.shirts_full.hash, true, true, true)
        print('[RSG-Appearance] Applied shirt hash: ' .. tostring(clothesData.shirts_full.hash))
    elseif clothesData.shirts_full.model > 0 then
        LoadStarterClothing(playerPed, 'shirts_full', clothesData.shirts_full.model, 1)
    end
    
    if clothesData.pants.hash and clothesData.pants.hash ~= 0 then
        Citizen.InvokeNative(0xD3A7B003ED343FD9, playerPed, clothesData.pants.hash, true, true, true)
        print('[RSG-Appearance] Applied pants hash: ' .. tostring(clothesData.pants.hash))
    elseif clothesData.pants.model > 0 then
        LoadStarterClothing(playerPed, 'pants', clothesData.pants.model, 1)
    end
    
    if clothesData.boots.hash and clothesData.boots.hash ~= 0 then
        Citizen.InvokeNative(0xD3A7B003ED343FD9, playerPed, clothesData.boots.hash, true, true, true)
        print('[RSG-Appearance] Applied boots hash: ' .. tostring(clothesData.boots.hash))
    elseif clothesData.boots.model > 0 then
        LoadStarterClothing(playerPed, 'boots', clothesData.boots.model, 1)
    end
    
    -- Обновляем вариацию
    Citizen.InvokeNative(0x704C908E9C405136, playerPed)
    Citizen.InvokeNative(0xCC8CA3E88256E58F, playerPed, false, true, true, true, false)
    if ReapplyBodyMorph then ReapplyBodyMorph(playerPed) end
    
    Wait(500)
    
    if Skinkosong then
        -- Редактирование существующего персонажа
        Skinkosong = false
        TriggerServerEvent('rsg-appearance:server:SaveSkin', CreatorCache, clothesData, true)
    elseif Cid then
        -- Создание нового персонажа
        local newData = {
            firstname = Firstname,
            lastname = Lastname,
            nationality = Nationality,
            gender = Selectedsex == 1 and 0 or 1,
            birthdate = Birthdate,
            cid = Cid
        }
        
        TriggerServerEvent('rsg-multicharacter:server:createCharacter', newData)
        Wait(500)
        
        TriggerServerEvent('rsg-appearance:server:SaveSkin', CreatorCache, clothesData, false)
        
        -- Выдаём стартовую одежду как предметы
        TriggerServerEvent('rsg-appearance:server:GiveStarterClothing', clothesData, isMale)
    end
    
    -- Возвращаем в нормальный бакет
    TriggerServerEvent('rsg-appearance:server:SetPlayerBucket', 0)
    
    DoScreenFadeIn(500)
    
    cb({ success = true })
end)

-- ==========================================
-- NUI CALLBACKS - МАГАЗИН
-- ==========================================

RegisterNUICallback('updateClothes', function(data, cb)
    local category = currentClothingCategory
    local valueType = data.type
    local value = data.value
    
    if not category then
        cb('ok')
        return
    end
    
    -- Обновляем кэш
    if not ClothesCache[category] then
        ClothesCache[category] = { model = 0, texture = 1 }
    end
    
    local ped = PlayerPedId()
    local isMale = IsPedMale(ped)
    local gender = isMale and 'male' or 'female'
    
    if valueType == 'model' then
        ClothesCache[category].model = value
        ClothesCache[category].texture = 1
        
        -- Обновляем макс текстур
        local maxTex = GetMaxTexturesForModel(category, value, false)
        SendNUIMessage({ action = 'updateMax', id = 'texture', max = math.max(1, maxTex) })
    else
        ClothesCache[category].texture = value
    end
    
    -- Применяем превью
    local model = ClothesCache[category].model
    local texture = ClothesCache[category].texture
    
    if model > 0 then
        if clothing[gender] and clothing[gender][category] and 
           clothing[gender][category][model] and clothing[gender][category][model][texture] then
            local hash = clothing[gender][category][model][texture].hash
            ClothesCache[category].hash = hash
            
            NativeSetPedComponentEnabledClothes(ped, hash, false, true, true)
            NativeUpdatePedVariation(ped)
        end
    else
        -- Снимаем одежду этой категории
        Citizen.InvokeNative(0xD710A5007C2AC539, ped, GetHashKey(category), 0)
        ClothesCache[category].hash = nil
        NativeUpdatePedVariation(ped)
    end
    
    -- Пересчитываем цену
    local price = CalculatePrice(ClothesCache, OldClothesCache, isMale)
    CurrentPrice = price
    SendNUIMessage({ action = 'updatePrice', price = price })
    
    cb('ok')
end)

RegisterNUICallback('confirmShop', function(data, cb)
    local totalPrice = CurrentPrice or 0
    
    if totalPrice <= 0 then
        TriggerEvent('ox_lib:notify', { 
            title = 'Магазин', 
            description = 'Вы ничего не выбрали', 
            type = 'info' 
        })
        cb({ success = false })
        return
    end
    
    -- Покупаем
    local purchasedItems = GetPurchasedItems(ClothesCache, OldClothesCache, IsPedMale(PlayerPedId()))
    
    TriggerServerEvent('rsg-appearance:server:buyClothes', purchasedItems, totalPrice)
    
    -- Обновляем OldClothesCache
    for category, data in pairs(ClothesCache) do
        if data.model and data.model > 0 then
            OldClothesCache[category] = {
                model = data.model,
                texture = data.texture,
                hash = data.hash
            }
        end
    end
    
    CurrentPrice = 0
    
    cb({ success = true })
end)

-- ==========================================
-- NUI CALLBACKS - ОБЩИЕ
-- ==========================================

RegisterNUICallback('back', function(data, cb)
    -- При создании персонажа нельзя закрыть
    if currentMode == 'creator' and IsInCharCreation then
        cb('blocked')
        return
    end
    
    if currentMode == 'shop' then
        CloseHTML()
    end
    
    cb('ok')
end)

RegisterNUICallback('close', function(data, cb)
    -- При создании персонажа нельзя закрыть
    if currentMode == 'creator' and IsInCharCreation then
        cb('blocked')
        return
    end
    
    CloseHTML()
    cb('ok')
end)

-- Поворот педа
RegisterNUICallback('rotatePedLeft', function(data, cb)
    RotateCreatorPedLeft()
    cb('ok')
end)

RegisterNUICallback('rotatePedRight', function(data, cb)
    RotateCreatorPedRight()
    cb('ok')
end)

-- Управление камерой
RegisterNUICallback('moveCamera', function(data, cb)
    local position = data.position or 'reset'
    
    if position == 'up' then
        MoveCreatorCamera('up')
    elseif position == 'down' then
        MoveCreatorCamera('down')
    elseif position == 'in' then
        MoveCreatorCamera('in')
    elseif position == 'out' then
        MoveCreatorCamera('out')
    elseif position == 'reset' then
        -- Сбрасываем камеру на стандартное положение
        ResetCreatorCamera()
    end
    
    cb('ok')
end)

-- ==========================================
-- РАНДОМАЙЗЕР ВНЕШНОСТИ
-- ==========================================

RegisterNUICallback('randomize', function(data, cb)
    local ped = GetTargetPed()
    local isMale = IsPedMale(ped)
    
    print('[RSG-Appearance] Randomizing appearance')
    
    -- Выбираем ОДИН тон кожи для всего персонажа
    local skinTone = math.random(1, 6)
    
    -- Голова - используем тот же тон кожи
    CreatorCache.head = math.random(2, 45)
    CreatorCache.skin_tone = skinTone
    
    -- Тело
    CreatorCache.body_size = math.random(1, 5)
    CreatorCache.body_waist = math.random(1, 21)
    CreatorCache.chest_size = math.random(1, 11)
    CreatorCache.height = math.random(95, 105)
    
    -- Черты лица
    local faceFeatures = {
        'head_width', 'face_width', 'jaw_width', 'jaw_height', 
        'chin_width', 'chin_height', 'chin_depth',
        'eyes_depth', 'eyes_angle', 'eyes_distance', 'eyes_height',
        'eyelid_height', 'eyelid_width',
        'nose_width', 'nose_size', 'nose_height', 'nose_angle', 'nose_curvature', 'nostrils_distance',
        'mouth_width', 'mouth_depth', 'mouth_x_pos', 'mouth_y_pos',
        'upper_lip_height', 'upper_lip_width', 'lower_lip_height', 'lower_lip_width',
        'ears_width', 'ears_height', 'ears_size', 'ears_angle',
        'cheekbones_width', 'cheekbones_height', 'cheekbones_depth',
        'eyebrow_height', 'eyebrow_width', 'eyebrow_depth'
    }
    
    for _, feature in ipairs(faceFeatures) do
        CreatorCache[feature] = math.random(-50, 50)
    end
    
    -- Глаза
    CreatorCache.eyes_color = math.random(5, 18)
    
    -- Волосы
    local maxHair = isMale and 29 or 35
    local hairModel = math.random(0, maxHair)
    -- Пропускаем битые
    if isMale and hairModel == 19 then hairModel = 20 end
    if not isMale and (hairModel == 21 or hairModel == 32) then hairModel = hairModel + 1 end
    
    if not CreatorCache.hair then CreatorCache.hair = {} end
    CreatorCache.hair.model = hairModel
    CreatorCache.hair.color = math.random(1, 15)
    
    -- Борода для мужчин
    if isMale then
        if not CreatorCache.beard then CreatorCache.beard = {} end
        CreatorCache.beard.model = math.random(0, 20)
        CreatorCache.beard.color = math.random(1, 15)
    end
    
    -- Особенности
    CreatorCache.eyebrows_t = math.random(1, 15)
    CreatorCache.eyebrows_op = math.random(50, 100)
    
    -- ВАЖНО: Сначала применяем тело, потом голову с тем же тоном!
    -- Это гарантирует одинаковый цвет
    
    -- 1. Очищаем компоненты
    FixIssues(ped)
    Wait(100)
    
    -- 2. Сначала тело
    LoadBoody(ped, CreatorCache)
    Wait(150)
    
    -- 3. Потом голова с тем же skin_tone
    LoadHead(ped, CreatorCache)
    Wait(150)
    
    -- 4. Остальное
    LoadEyes(ped, CreatorCache)
    Wait(50)
    LoadFeatures(ped, CreatorCache)
    Wait(50)
    LoadHair(ped, CreatorCache)
    if isMale then
        LoadBeard(ped, CreatorCache)
    end
    Wait(50)
    LoadOverlays(ped, CreatorCache)
    Wait(50)
    LoadHeight(ped, CreatorCache)
    
    -- 5. Размеры тела
    LoadBodyFeature(ped, CreatorCache.body_size, Data.Appearance.body_size)
    LoadBodyFeature(ped, CreatorCache.body_waist, Data.Appearance.body_waist)
    LoadBodyFeature(ped, CreatorCache.chest_size, Data.Appearance.chest_size)
    
    Wait(100)
    
    -- 6. Финальное обновление
    NativeUpdatePedVariation(ped)
    
    -- 7. Переприменяем тело ещё раз для надёжности
    Wait(100)
    LoadBodyFeature(ped, CreatorCache.body_size, Data.Appearance.body_size)
    LoadBodyFeature(ped, CreatorCache.body_waist, Data.Appearance.body_waist)
    LoadBodyFeature(ped, CreatorCache.chest_size, Data.Appearance.chest_size)
    
    print('[RSG-Appearance] Randomize complete, skin_tone=' .. tostring(skinTone))
    
    -- Отправляем обновлённый кэш в UI
    SendNUIMessage({
        action = 'openCreator',
        isMale = isMale,
        cache = CreatorCache
    })
    
    cb('ok')
end)

-- ==========================================
-- МАГАЗИН ОДЕЖДЫ - НОВЫЕ CALLBACKS
-- ==========================================

RegisterNUICallback('selectShopCategory', function(data, cb)
    local category = data.category
    currentClothingCategory = category
    
    print('[RSG-Appearance] Shop category: ' .. tostring(category))
    
    cb('ok')
end)

RegisterNUICallback('updateShopClothes', function(data, cb)
    local category = data.category
    local valueType = data.type
    local value = data.value
    local ped = PlayerPedId()
    
    if not category then
        cb('ok')
        return
    end
    
    -- Обновляем кэш
    if not ClothesCache[category] then
        ClothesCache[category] = { model = 0, texture = 1 }
    end
    
    ClothesCache[category][valueType] = value
    
    -- Применяем одежду
    local model = ClothesCache[category].model or 0
    local texture = ClothesCache[category].texture or 1
    
    if model > 0 then
        local isMale = IsPedMale(ped)
        local hash = GetHashFromModelTexture(category, model, texture, isMale)
        
        if hash and hash ~= 0 then
            Citizen.InvokeNative(0xD3A7B003ED343FD9, ped, hash, true, true, true)
            Citizen.InvokeNative(0x704C908E9C405136, ped)
            Citizen.InvokeNative(0xCC8CA3E88256E58F, ped, false, true, true, true, false)
            if ReapplyBodyMorph then ReapplyBodyMorph(ped) end
        end
    else
        -- Убираем одежду
        Citizen.InvokeNative(0xD710A5007C2AC539, ped, GetHashKey(category), 0)
        Citizen.InvokeNative(0x704C908E9C405136, ped)
    end
    
    cb('ok')
end)

RegisterNUICallback('purchaseClothes', function(data, cb)
    local clothesCache = data.cache or {}
    local total = data.total or 0
    
    -- Отправляем на сервер для покупки
    TriggerServerEvent('rsg-appearance:server:purchaseClothes', clothesCache, total)
    
    CloseHTML()
    cb('ok')
end)

RegisterNUICallback('exitShop', function(data, cb)
    -- Восстанавливаем старую одежду
    if OldClothesCache then
        local ped = PlayerPedId()
        TriggerEvent('rsg-appearance:client:ApplyClothes', OldClothesCache, ped)
    end
    
    CloseHTML()
    cb('ok')
end)

RegisterNUICallback('cancelCreator', function(data, cb)
    print('[RSG-Appearance] cancelCreator called')
    
    -- Закрываем UI
    CloseHTML()
    
    -- Удаляем педа создания
    if CreatorPed and DoesEntityExist(CreatorPed) then
        DeleteEntity(CreatorPed)
        CreatorPed = nil
    end
    
    -- Убираем камеру
    if CreatorCam and DoesCamExist(CreatorCam) then
        SetCamActive(CreatorCam, false)
        RenderScriptCams(false, false, 0, true, true)
        DestroyCam(CreatorCam, false)
        CreatorCam = nil
    end
    
    -- Сбрасываем флаги
    IsInCharCreation = false
    
    -- Показываем игрока
    local playerPed = PlayerPedId()
    SetEntityVisible(playerPed, true)
    SetEntityInvincible(playerPed, false)
    FreezeEntityPosition(playerPed, false)
    
    -- Возвращаем в стандартный бакет
    TriggerServerEvent('rsg-appearance:server:SetPlayerBucket', 0, false)
    
    -- Возвращаем в меню выбора персонажа
    TriggerEvent('rsg-multicharacter:client:chooseChar')
    
    cb('ok')
end)

-- Вспомогательная функция получения hash
function GetHashFromModelTexture(category, model, texture, isMale)
    local gender = isMale and 'male' or 'female'
    
    if clothing[gender] and clothing[gender][category] then
        if clothing[gender][category][model] then
            if clothing[gender][category][model][texture] then
                return clothing[gender][category][model][texture].hash
            elseif clothing[gender][category][model][1] then
                return clothing[gender][category][model][1].hash
            end
        end
    end
    
    return 0
end

-- ==========================================
-- ЭКСПОРТЫ
-- ==========================================

exports('OpenCreatorHTML', OpenCreatorHTML)
exports('OpenShopHTML', OpenShopHTML)
exports('CloseHTML', CloseHTML)
exports('IsHTMLOpen', function() return isUIOpen end)

-- ==========================================
-- ЗАМЕНА ВЫЗОВОВ ДЛЯ МАГАЗИНА
-- ==========================================

-- Перехватываем открытие магазина одежды
RegisterNetEvent('rsg-appearance:client:openClothingShop', function()
    OpenShopHTML()
end)

-- Альтернативный вызов
AddEventHandler('rsg-clothing:client:openShop', function()
    OpenShopHTML()
end)

-- ==========================================
-- БЛОКИРОВКА УПРАВЛЕНИЯ
-- ==========================================

CreateThread(function()
    while true do
        Wait(0)
        
        if isUIOpen then
            DisableAllControlActions(0)
            DisableAllControlActions(1)
            DisableAllControlActions(2)
            
            -- Мышь
            EnableControlAction(0, 239, true) -- cursor x
            EnableControlAction(0, 240, true) -- cursor y
            EnableControlAction(0, 237, true) -- scroll up
            EnableControlAction(0, 238, true) -- scroll down
            EnableControlAction(0, 31, true)  -- mouse input

            -- Mouse wheel camera zoom in/out
            if currentMode == 'creator' then
                if IsDisabledControlJustPressed(0, 237) then
                    MoveCreatorCamera('in')
                elseif IsDisabledControlJustPressed(0, 238) then
                    MoveCreatorCamera('out')
                end
            end

            -- Hold LMB and drag to rotate ped around its axis
            if currentMode == 'creator' and CreatorPed and DoesEntityExist(CreatorPed) then
                local cursorX = GetDisabledControlNormal(0, 239)
                local cursorY = GetDisabledControlNormal(0, 240)
                local lmbPressed = IsDisabledControlPressed(0, GetHashKey("INPUT_ATTACK"))

                if lmbPressed then
                    if not isMouseDraggingPed then
                        if IsCursorOverPedArea(cursorX, cursorY) then
                            isMouseDraggingPed = true
                            lastMouseX = cursorX
                        end
                    else
                        if lastMouseX ~= nil then
                            local deltaX = cursorX - lastMouseX
                            if math.abs(deltaX) > 0.0005 then
                                local heading = GetEntityHeading(CreatorPed)
                                SetEntityHeading(CreatorPed, heading - (deltaX * 260.0))
                            end
                        end
                        lastMouseX = cursorX
                    end
                else
                    isMouseDraggingPed = false
                    lastMouseX = nil
                end
            else
                isMouseDraggingPed = false
                lastMouseX = nil
            end
            
            -- Клавиши управления
            -- A - поворот влево
            if IsControlJustPressed(0, 0x7065027D) then -- INPUT_MOVE_LEFT_ONLY (A)
                RotateCreatorPedLeft()
            end
            
            -- D - поворот вправо
            if IsControlJustPressed(0, 0xB4E465B4) then -- INPUT_MOVE_RIGHT_ONLY (D)
                RotateCreatorPedRight()
            end
            
            -- W - камера вверх
            if IsControlJustPressed(0, 0x8FD015D8) then -- INPUT_MOVE_UP_ONLY (W)
                MoveCreatorCamera('up')
            end
            
            -- S - камера вниз
            if IsControlJustPressed(0, 0xD27782E3) then -- INPUT_MOVE_DOWN_ONLY (S)
                MoveCreatorCamera('down')
            end
            
            -- ESC для закрытия - только в магазине, НЕ при создании персонажа
            if IsControlJustPressed(0, 0x156F7119) then -- INPUT_FRONTEND_CANCEL
                if currentMode == 'shop' then
                    CloseHTML()
                end
                -- При создании персонажа ESC не работает
            end
        end
    end
end)

print('[RSG-Appearance] HTML UI v3.0 loaded - rsg-menubase replaced')