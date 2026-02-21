local RSGCore = exports['rsg-core']:GetCoreObject()

local isStoreOpen = false
local currentStore = nil
local previewedItem = nil
local originalClothes = {}
local storeCam = nil
local camOffsetZ = 0.0
local savedPosition = nil
local savedHeading = nil
local currentCloakroom = nil

-- ★ ХЕШИ ДЛЯ ПРИМЕНЕНИЯ КОМПОНЕНТОВ ОДЕЖДЫ (mp_male)
local CategoryComponentHash = {
    ['hats'] = 0x9925C067,
    ['coats'] = 0xE06D47B7,
    ['coats_closed'] = 0xE06D47B7,
    ['vests'] = 0x485EE834,
    ['shirts_full'] = 0x0662AC34,
    ['shirts'] = 0x0662AC34,
    ['pants'] = 0xB6B6122D,
    ['boots'] = 0x777EC6EF,
    ['chaps'] = 0x3107499B,
    ['gloves'] = 0xEABE0032,
    ['neckwear'] = 0x5FC29285,
    ['suspenders'] = 0x877A2CF7,
    ['belts'] = 0x9B2C8B89,
    ['belt_buckles'] = 0xDA0E2C55,
    ['beltbuckle'] = 0xDA0E2C55,
    ['satchels'] = 0x94504D26,
    ['gunbelts'] = 0x9B2C8B89,
    ['holsters_left'] = 0x7A6BBD0B,
    ['holsters_right'] = 0x0B3966C9,
    ['accessories'] = 0x79D7DF96,
    ['masks'] = 0x7505EF42,
    ['eyewear'] = 0x5E47CA6F,
    ['cloaks'] = 0x3C1A74CD,
    ['ponchos'] = 0xAF14310B,
    ['skirts'] = 0x1D4C528A,
    ['loadouts'] = 0x83887E88,
    ['spurs'] = 0x18729F39,
    ['gauntlets'] = 0x91CE9B20,
    ['neckties'] = 0x7A96FACA,
    ['dresses'] = 0x0662AC34,
    ['corsets'] = 0x485EE834,
    ['badges'] = 0x79D7DF96,
    ['hair_accessories'] = 0x79D7DF96,
    ['boot_accessories'] = 0x18729F39,
    ['necklaces'] = 0x79D7DF96,
    ['rings_rh'] = 0x79D7DF96,
    ['rings_lh'] = 0x79D7DF96,
    ['bracelets'] = 0x79D7DF96,
    ['earrings'] = 0x72E6EF74,  -- серьги (accessories ear slot)
    -- Украшения — отдельные слоты (rdr2mods/jo_libs)
    ['jewelry_rings_right'] = 0x7A6BBD0B,
    ['jewelry_rings_left'] = 0xF16A1D23,
    ['jewelry_bracelets'] = 0x7BC10759,
    ['talisman_belt'] = 0x1AECF7DC,
}

-- ★ Категории аксессуаров (для женских персонажей иногда нужно очищать оба слота)
local AccessoryCategories = {
    ['accessories'] = true, ['badges'] = true, ['hair_accessories'] = true,
    ['necklaces'] = true, ['rings_rh'] = true, ['rings_lh'] = true, ['bracelets'] = true,
    ['earrings'] = true,
    ['jewelry_rings_right'] = true, ['jewelry_rings_left'] = true, ['jewelry_bracelets'] = true,
    ['talisman_belt'] = true,
}

local function GetComponentHashForPed(ped, category)
    return CategoryComponentHash[category]
end

-- ★ ХЕШИ ДЛЯ ПРИМЕНЕНИЯ ЦВЕТА/TINT (ОТЛИЧАЮТСЯ!)
local CategoryTintHash = {
    ['hats'] = 0x9925C067,
    ['shirts_full'] = 0x2026C46D,
    ['shirts'] = 0x2026C46D,
    ['pants'] = 0x1D4C528A,
    ['boots'] = 0x777EC6EF,
    ['vests'] = 0x485EE834,
    ['coats'] = 0xE06D30CE,
    ['coats_closed'] = 0x662AC34,
    ['gloves'] = 0xEABE0032,
    ['neckwear'] = 0x7A96FACA,
    ['neckties'] = 0x7A96FACA,
    ['masks'] = 0x7505EF42,
    ['eyewear'] = 0x5F1BE9EC,
    ['gunbelts'] = 0xF1542D11,
    ['satchels'] = 0x94504D26,
    ['suspenders'] = 0x877A2CF7,
    ['chaps'] = 0x3107499B,
    ['spurs'] = 0x18729F39,
    ['cloaks'] = 0x3C1A74CD,
    ['ponchos'] = 0xAF14310B,
    ['skirts'] = 0x1D4C528A,
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
    ['boot_accessories'] = 0x18729F39,
    ['earrings'] = 0x72E6EF74,
    ['talisman_belt'] = 0x1AECF7DC,
}

-- ★ ВЗАИМОЗАМЕНЯЕМЫЕ КАТЕГОРИИ (как в rsg-appearance)
local ConflictingCategories = {
    ['coats'] = 'coats_closed',
    ['coats_closed'] = 'coats',
}

-- ==========================================
-- КОМНАТА И BUCKET
-- ==========================================
local function GetNearestCloakroom()
    local ped = PlayerPedId()
    local playerCoords = GetEntityCoords(ped)
    local nearestDist = 9999
    local nearestRoom = Config.Cloakrooms[1]
    
    for _, room in ipairs(Config.Cloakrooms) do
        local dist = #(playerCoords - vector3(room.coords.x, room.coords.y, room.coords.z))
        if dist < nearestDist then
            nearestDist = dist
            nearestRoom = room
        end
    end
    
    return nearestRoom
end

local function TeleportToRoom()
    local ped = PlayerPedId()
    local room = GetNearestCloakroom()
    currentCloakroom = room
    
    savedPosition = GetEntityCoords(ped)
    savedHeading = GetEntityHeading(ped)
    
    -- Убрать лошадь до телепорта (иначе «умирает» и остаётся призрак)
    TriggerEvent('rsg-horses:client:DespawnForClothingStore')
    
    local playerId = GetPlayerServerId(PlayerId())
    TriggerServerEvent('rsg-clothingstore:server:setPrivateBucket', playerId)
    
    -- ★ ОТКЛЮЧАЕМ ТЕМПЕРАТУРУ
    LocalPlayer.state:set('isInClothingStore', true, true)
    
    DoScreenFadeOut(500)
    while not IsScreenFadedOut() do Wait(10) end
    Wait(200)
    
    RequestCollisionAtCoord(room.coords.x, room.coords.y, room.coords.z)
    
    SetEntityCoords(ped, room.coords.x, room.coords.y, room.coords.z, false, false, false, false)
    SetEntityHeading(ped, room.coords.w)
    
    local timeout = 0
    while not HasCollisionLoadedAroundEntity(ped) and timeout < 200 do 
        Wait(10) 
        timeout = timeout + 1
    end
    
    Wait(500)
    
    DoScreenFadeIn(500)
    while not IsScreenFadedIn() do Wait(10) end
end

local function TeleportBack()
    if not savedPosition then return end
    
    local ped = PlayerPedId()
    
    DoScreenFadeOut(500)
    while not IsScreenFadedOut() do Wait(10) end
    Wait(200)
    
    TriggerServerEvent('rsg-clothingstore:server:setNormalBucket')
    
    -- ★ ВКЛЮЧАЕМ ТЕМПЕРАТУРУ ОБРАТНО
    LocalPlayer.state:set('isInClothingStore', false, true)
    
    FreezeEntityPosition(ped, true)
    RequestCollisionAtCoord(savedPosition.x, savedPosition.y, savedPosition.z)
    
    SetEntityCoordsNoOffset(ped, savedPosition.x, savedPosition.y, savedPosition.z, false, false, false)
    SetEntityHeading(ped, savedHeading)
    
    local timeout = 0
    while not HasCollisionLoadedAroundEntity(ped) and timeout < 100 do 
        Wait(10)
        timeout = timeout + 1
    end
    
    Wait(300)
    
    DoScreenFadeIn(500)
    while not IsScreenFadedIn() do Wait(10) end
    
    Wait(100)
    FreezeEntityPosition(ped, false)
    ClearPedTasks(ped)
    
    -- ★ ВЫЗЫВАЕМ LOADCHARACTER ПОСЛЕ ВЫХОДА ИЗ МАГАЗИНА
    Wait(500)
    ExecuteCommand('loadcharacter')
    
    savedPosition = nil
    savedHeading = nil
    currentCloakroom = nil
end

-- ==========================================
-- КАМЕРА
-- ==========================================
local function CreateStoreCam()
    if not currentCloakroom then return end
    
    local ped = PlayerPedId()
    local pedCoords = GetEntityCoords(ped)
    local cam = currentCloakroom.cam
    
    storeCam = CreateCam("DEFAULT_SCRIPTED_CAMERA", true)
    SetCamCoord(storeCam, cam.x, cam.y, cam.z)
    SetCamRot(storeCam, -4.0, 0.0, cam.w or 0.0, 2)
    SetCamFov(storeCam, 35.0)
    SetCamActive(storeCam, true)
    RenderScriptCams(true, false, 500, true, true)
    
    SetFocusPosAndVel(pedCoords.x, pedCoords.y, pedCoords.z, 0.0, 0.0, 0.0)
    camOffsetZ = 0.0
end

local function DestroyStoreCam()
    if storeCam then
        DestroyAllCams(true)
        RenderScriptCams(false, true, 500, true, true)
        storeCam = nil
        SetFocusEntity(PlayerPedId())
    end
end

local function MoveStoreCam(direction)
    if not storeCam or not currentCloakroom then return end
    
    local ped = PlayerPedId()
    local pedCoords = GetEntityCoords(ped)
    local cam = currentCloakroom.cam
    
    if direction == 'up' then
        camOffsetZ = math.min(camOffsetZ + 0.3, 1.5)
    elseif direction == 'down' then
        camOffsetZ = math.max(camOffsetZ - 0.3, -0.8)
    elseif direction == 'left' then
        SetEntityHeading(ped, GetEntityHeading(ped) + 15.0)
    elseif direction == 'right' then
        SetEntityHeading(ped, GetEntityHeading(ped) - 15.0)
    elseif direction == 'reset' then
        camOffsetZ = 0.0
        if currentCloakroom then
            SetEntityHeading(ped, currentCloakroom.coords.w)
        end
    end
    
    SetCamCoord(storeCam, cam.x, cam.y, cam.z + camOffsetZ)
    SetFocusPosAndVel(pedCoords.x, pedCoords.y, pedCoords.z + camOffsetZ, 0.0, 0.0, 0.0)
end

-- ==========================================
-- СОХРАНЕНИЕ/ВОССТАНОВЛЕНИЕ ОДЕЖДЫ
-- ==========================================
local function SaveCurrentClothes()
    originalClothes = {}
    local ped = PlayerPedId()
    
    for category, hash in pairs(CategoryComponentHash) do
        local compHash = GetComponentHashForPed(ped, category) or hash
        local drawable = Citizen.InvokeNative(0x77BA37622E22023B, ped, compHash)
        if drawable then
            originalClothes[category] = { hash = hash, drawable = drawable }
        end
    end
end

-- Восстановить слот категории к состоянию при входе
local function RestoreSlotToOriginal(category)
    local ped = PlayerPedId()
    local compHash = GetComponentHashForPed(ped, category) or CategoryComponentHash[category]
    if not compHash then return end
    
    Citizen.InvokeNative(0xD710A5007C2AC539, ped, compHash, 0)
    if ConflictingCategories and ConflictingCategories[category] then
        local conflictCat = ConflictingCategories[category]
        local conflictHash = CategoryComponentHash[conflictCat]
        if conflictHash then
            Citizen.InvokeNative(0xD710A5007C2AC539, ped, conflictHash, 0)
        end
        Citizen.InvokeNative(0xD710A5007C2AC539, ped, GetHashKey(conflictCat), 0)
    end
    Citizen.InvokeNative(0xD710A5007C2AC539, ped, GetHashKey(category), 0)
    
    if originalClothes[category] and originalClothes[category].drawable and originalClothes[category].drawable ~= 0 then
        local orig = originalClothes[category]
        Citizen.InvokeNative(0xD3A7B003ED343FD9, ped, compHash, orig.drawable, true, true, false)
    end
    
    Citizen.InvokeNative(0x704C908E9C405136, ped)
    Citizen.InvokeNative(0xCC8CA3E88256E58F, ped, false, true, true, true, false)
end

-- Восстановить все просмотренные категории при выходе
local function RestoreOriginalClothes()
    local ped = PlayerPedId()
    
    -- Восстановить текущий preview
    if previewedItem then
        RestoreSlotToOriginal(previewedItem.category)
        if ConflictingCategories and ConflictingCategories[previewedItem.category] then
            RestoreSlotToOriginal(ConflictingCategories[previewedItem.category])
        end
    end
    
    previewedItem = nil
end

-- ==========================================
-- ★ ПРИМЕНЕНИЕ ОДЕЖДЫ ДЛЯ ПРЕВЬЮ
-- ==========================================
local function ApplyClothingItem(item)
    if not item then return end
    
    local ped = PlayerPedId()
    local category = item.category
    local compHash = GetComponentHashForPed(ped, category) or CategoryComponentHash[category]
    
    if not compHash then
        print('[RSG-ClothingStore] Unknown category: ' .. tostring(category))
        return
    end
    
    -- ★ При смене категории — восстанавливаем предыдущую
    if previewedItem and previewedItem.category ~= category then
        RestoreSlotToOriginal(previewedItem.category)
        if ConflictingCategories and ConflictingCategories[previewedItem.category] then
            RestoreSlotToOriginal(ConflictingCategories[previewedItem.category])
        end
        Wait(50)
    end
    
    -- ★ Очищаем конфликтующую категорию (coats/coats_closed)
    if ConflictingCategories and ConflictingCategories[category] then
        local conflictCat = ConflictingCategories[category]
        local conflictHash = CategoryComponentHash[conflictCat]
        if conflictHash then
            Citizen.InvokeNative(0xD710A5007C2AC539, ped, conflictHash, 0)
        end
        Citizen.InvokeNative(0xD710A5007C2AC539, ped, GetHashKey(conflictCat), 0)
        Wait(30)
    end
    
    -- Удаляем текущий компонент (для женских аксессуаров — очищаем оба слотовых хеша)
    Citizen.InvokeNative(0xD710A5007C2AC539, ped, compHash, 0)
    Citizen.InvokeNative(0xD710A5007C2AC539, ped, GetHashKey(category), 0)
    if not IsPedMale(ped) and AccessoryCategories[category] then
        Citizen.InvokeNative(0xD710A5007C2AC539, ped, 0x79D7DF96, 0)
        Citizen.InvokeNative(0xD710A5007C2AC539, ped, 0x72E6EF74, 0)
        Wait(80)
    end
    Citizen.InvokeNative(0xCC8CA3E88256E58F, ped, 0, 1, 1, 1, 0)
    Wait(50)
    
    if item.Kaf == "Classic" then
        -- ★ CLASSIC ОДЕЖДА - цвет уже в хеше, НЕ применяем tint!
        local hash = item.Hash
        if type(hash) == "string" then
            hash = tonumber(hash, 16)
        end
        
        if hash and hash ~= 0 then
            print('[RSG-ClothingStore] Classic hash: ' .. string.format("0x%X", hash))
            
            Citizen.InvokeNative(0x59BD177A1A48600A, ped, hash)
            Citizen.InvokeNative(0xD3A7B003ED343FD9, ped, hash, true, true, true)
            local t = 0
            while not Citizen.InvokeNative(0xA0BC8FAED8CFEB3C, ped) and t < 100 do Wait(20) t = t + 1 end
            Citizen.InvokeNative(0x704C908E9C405136, ped)
            Citizen.InvokeNative(0xCC8CA3E88256E58F, ped, false, true, true, true, false)
            
            -- ★ НЕ ПРИМЕНЯЕМ TINT ДЛЯ CLASSIC!
            -- Цвет уже запечён в хеш
        end
    else
        -- ★ PED ОДЕЖДА - применяем компоненты и tint
        -- Сначала запрашиваем все хеши для стриминга (решает проблему COMBOCOAT и др.)
        local hashesToRequest = {}
        if item.Draw and item.Draw ~= "" and item.Draw ~= "_" then table.insert(hashesToRequest, GetHashKey(item.Draw)) end
        if item.alb and item.alb ~= "" then table.insert(hashesToRequest, GetHashKey(item.alb)) end
        if item.norm and item.norm ~= "" then table.insert(hashesToRequest, GetHashKey(item.norm)) end
        if item.mat and item.mat ~= 0 and item.mat ~= "" then
            local m = item.mat
            if type(m) == "string" then m = m:sub(1,2) == "0x" and tonumber(m,16) or GetHashKey(m) else m = m end
            if m and m ~= 0 then table.insert(hashesToRequest, m) end
        end
        for _, h in ipairs(hashesToRequest) do Citizen.InvokeNative(0x59BD177A1A48600A, ped, h) end
        Wait(350)
        
        local function ApplyPedComponent(hash)
            if not hash or hash == 0 then return end
            Citizen.InvokeNative(0x59BD177A1A48600A, ped, hash)
            Citizen.InvokeNative(0xD3A7B003ED343FD9, ped, hash, true, true, true)
            local t = 0
            while not Citizen.InvokeNative(0xA0BC8FAED8CFEB3C, ped) and t < 150 do Wait(20) t = t + 1 end
        end
        
        -- Draw
        if item.Draw and item.Draw ~= "" and item.Draw ~= "_" then
            ApplyPedComponent(GetHashKey(item.Draw))
        end
        
        -- Albedo
        if item.alb and item.alb ~= "" then
            ApplyPedComponent(GetHashKey(item.alb))
        end
        
        -- Normal
        if item.norm and item.norm ~= "" then
            ApplyPedComponent(GetHashKey(item.norm))
        end
        
        -- Material
        if item.mat and item.mat ~= 0 and item.mat ~= "" then
            local matHash = item.mat
            if type(matHash) == "string" then 
                if matHash:sub(1, 2) == "0x" then
                    matHash = tonumber(matHash, 16)
                else
                    matHash = GetHashKey(matHash)
                end
            end
            ApplyPedComponent(matHash)
        end
        
        -- ★ Критично: без _FINAL_PED_META_CHANGE_APPLY компоненты MetaPed не отображаются
        Citizen.InvokeNative(0x704C908E9C405136, ped)
        Citizen.InvokeNative(0xCC8CA3E88256E58F, ped, false, true, true, true, false)
        Wait(100)
        
        -- ★ ПРИМЕНЯЕМ ЦВЕТ ТОЛЬКО ДЛЯ PED ОДЕЖДЫ
        if item.pal and item.pal ~= " " and item.pal ~= "" then
            local palette = item.pal
            local paletteHash = GetHashKey(palette)
            
            if not string.find(palette:lower(), 'metaped_') then
                paletteHash = GetHashKey('metaped_' .. palette:lower())
            end
            
            local t0 = tonumber(item.palette1) or 0
            local t1 = tonumber(item.palette2) or 0
            local t2 = tonumber(item.palette3) or 0
            
            local tintHash = CategoryTintHash[category] or compHash
            
            print('[RSG-ClothingStore] Tint: ' .. palette .. ' Values: ' .. t0 .. ',' .. t1 .. ',' .. t2)
            
            Citizen.InvokeNative(0x4EFC1F8FF1AD94DE, ped, tintHash, paletteHash, t0, t1, t2)
            Citizen.InvokeNative(0xAAB86462966168CE, ped, true)
            Citizen.InvokeNative(0xCC8CA3E88256E58F, ped, 0, 1, 1, 1, 0)
        end
    end
    
    -- ★ Анти-клип: для пальто убираем просвечивание рубашки (видна только на воротнике/манжетах)
    if (category == 'coats' or category == 'coats_closed') and GetResourceState('rsg-appearance') == 'started' then
        pcall(function() exports['rsg-appearance']:ApplyCoatAntiClipFix(ped, category) end)
    end
    
    Citizen.InvokeNative(0xCC8CA3E88256E58F, ped, 0, 1, 1, 1, 0)
    previewedItem = item
end

-- ==========================================
-- ОТКРЫТИЕ/ЗАКРЫТИЕ МАГАЗИНА
-- ==========================================
function OpenClothingStore(storeId)
    if isStoreOpen then return end
    
    local storeData = Config.Stores[storeId]
    if not storeData then return end
    
    local ped = PlayerPedId()
    local model = GetEntityModel(ped)
    local isMale = model == GetHashKey('mp_male')
    local sexKey = isMale and 'mp_male' or 'mp_female'
    
    local items = storeData.hashes[sexKey]
    if not items or #items == 0 then
        RSGCore.Functions.Notify('В этом магазине нет товаров для вас', 'error')
        return
    end
    
    currentStore = storeId
    isStoreOpen = true
    
    SaveCurrentClothes()
    TeleportToRoom()
    Wait(300)
    CreateStoreCam()
    FreezeEntityPosition(PlayerPedId(), true)
    
    local PlayerData = RSGCore.Functions.GetPlayerData()
    local money = PlayerData.money.cash or 0
    
    SetNuiFocus(true, true)
    SendNUIMessage({
        action = 'open',
        items = items,
        money = money,
        storeName = storeData.name or 'Магазин одежды',
        isMale = isMale
    })
end

function CloseClothingStore()
    if not isStoreOpen then return end
    
    isStoreOpen = false
    currentStore = nil
    
    SetNuiFocus(false, false)
    SendNUIMessage({ action = 'close' })
    
    DestroyStoreCam()
    RestoreOriginalClothes()
    FreezeEntityPosition(PlayerPedId(), false)
    TeleportBack()
end

-- ==========================================
-- NUI CALLBACKS
-- ==========================================
RegisterNUICallback('previewItem', function(data, cb)
    if data.item then
        ApplyClothingItem(data.item)
    end
    cb('ok')
end)

RegisterNUICallback('buyItem', function(data, cb)
    if not data.item then
        cb('error')
        return
    end
    
    local ped = PlayerPedId()
    local model = GetEntityModel(ped)
    local isMale = model == GetHashKey('mp_male')
    
    TriggerServerEvent('rsg-clothingstore:server:buyItem', data.item, currentStore, isMale)
    cb('ok')
end)

RegisterNUICallback('moveCamera', function(data, cb)
    MoveStoreCam(data.direction)
    cb('ok')
end)

RegisterNUICallback('closeStore', function(data, cb)
    CloseClothingStore()
    cb('ok')
end)

-- ==========================================
-- СЕРВЕРНЫЕ СОБЫТИЯ
-- ==========================================
RegisterNetEvent('rsg-clothingstore:client:purchaseSuccess', function(item, newMoney)
    -- ★ Купили = новая одежда уже на персонаже (превью), обновляем originalClothes
    if previewedItem and item then
        local ped = PlayerPedId()
        local category = previewedItem.category
        local compHash = GetComponentHashForPed(ped, category) or CategoryComponentHash[category]
        if compHash then
            local ped = PlayerPedId()
            local drawable = Citizen.InvokeNative(0x77BA37622E22023B, ped, compHash)
            local newState = { hash = compHash, drawable = drawable }
            originalClothes[category] = newState
            if ConflictingCategories and ConflictingCategories[category] then
                local conflictCat = ConflictingCategories[category]
                originalClothes[conflictCat] = newState
            end
        end
        previewedItem = nil
    end
    
    SendNUIMessage({
        action = 'purchaseSuccess',
        newMoney = newMoney
    })
end)

RegisterNetEvent('rsg-clothingstore:client:purchaseFailed', function(reason)
    lib.notify({
        title = 'Магазин одежды',
        description = reason or 'Ошибка покупки',
        type = 'error',
        position = 'top',
    })
    SendNUIMessage({
        action = 'purchaseFailed',
        reason = reason
    })
end)

-- ==========================================
-- ПРОМПТЫ И БЛИПЫ
-- ==========================================
CreateThread(function()
    for storeId, storeData in pairs(Config.Stores) do
        exports['rsg-core']:createPrompt(storeId .. '_clothing', storeData.coords, RSGCore.Shared.Keybinds['J'], 'Войти в ' .. storeData.name, {
            type = 'client',
            event = 'rsg-clothingstore:client:openStore',
            args = { storeId }
        })
        
        local blip = BlipAddForCoords(1664425300, storeData.coords.x, storeData.coords.y, storeData.coords.z)
        SetBlipSprite(blip, GetHashKey('blip_shop_tailor'), true)
        SetBlipScale(blip, 0.2)
        SetBlipName(blip, storeData.name)
    end
end)

RegisterNetEvent('rsg-clothingstore:client:openStore', function(storeId)
    OpenClothingStore(storeId)
end)

CreateThread(function()
    while true do
        Wait(0)
        if isStoreOpen then
            DisableAllControlActions(0)
            if IsControlJustPressed(0, 0x156F7119) then
                CloseClothingStore()
            end
        end
    end
end)

AddEventHandler('onResourceStop', function(resourceName)
    if GetCurrentResourceName() == resourceName then
        if isStoreOpen then
            CloseClothingStore()
        end
    end
end)
