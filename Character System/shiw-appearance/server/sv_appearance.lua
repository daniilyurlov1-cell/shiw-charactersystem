RSGCore = exports['rsg-core']:GetCoreObject()

-- ★ УТИЛИТЫ (определяем ДО обработчиков событий)
function TableLength(t)
    if not t then return 0 end
    local count = 0
    for _ in pairs(t) do count = count + 1 end
    return count
end

RegisterNetEvent('rsg-appearance:server:SaveSkin')
AddEventHandler('rsg-appearance:server:SaveSkin', function(skin, clothes, oldplayer)
    local encode = json.encode(skin)
    local encode2 = json.encode(clothes)
    local Player = RSGCore.Functions.GetPlayer(source)
    local citizenid = Player.PlayerData.citizenid

    if oldplayer then
        local result = MySQL.Sync.fetchAll('SELECT * FROM playerskins WHERE citizenid = ?', {citizenid})

        if result and #result > 0 then
            local existingSkin = json.decode(result[1].skin)
            local existingClothes = json.decode(result[1].clothes)

            for k, v in pairs(skin) do
                existingSkin[k] = v
            end

            for k, v in pairs(clothes) do
                existingClothes[k] = v
            end

            local encodedSkin = json.encode(existingSkin)
            local encodedclothes = json.encode(existingClothes)
            MySQL.Async.execute('UPDATE playerskins SET skin = @skin, clothes = @clothes WHERE citizenid = @citizenid',
            {
                ['citizenid'] = citizenid,
                ['skin'] = encodedSkin,
                ['clothes'] = encodedclothes,
            }, function(rowsChanged)
            end)
        end
    else
        MySQL.Async.insert('INSERT INTO playerskins (citizenid, skin, clothes) VALUES (?, ?, ?);', { citizenid, encode, encode2 })
        TriggerClientEvent('rsg-spawn:client:setupSpawnUI', source, encode, true)
    end
end)

RegisterNetEvent('rsg-appearance:server:SetPlayerBucket')
AddEventHandler('rsg-appearance:server:SetPlayerBucket', function(b, random)
    if random then
        local BucketID = RSGCore.Shared.RandomInt(1000, 9999)
        SetRoutingBucketPopulationEnabled(BucketID, false)
        SetPlayerRoutingBucket(source, BucketID)
    else
        SetPlayerRoutingBucket(source, b)
    end
end)

-- ==========================================
-- ФУНКЦИЯ ДЛЯ ПОЛУЧЕНИЯ ОДЕЖДЫ ИЗ ИНВЕНТАРЯ
-- ★ Определена ДО LoadSkin чтобы быть доступной
-- ==========================================

local function GetEquippedClothesFromInventory(Player)
    local clothes = {}
    
    if not Player or not Player.PlayerData or not Player.PlayerData.items then
        return clothes
    end
    
    for slot, item in pairs(Player.PlayerData.items) do
        if item and item.name and item.info then
            local isClothing = string.find(item.name, 'clothing_') ~= nil
            
            if isClothing then
                local info = item.info
                local isEquipped = info._e == true or info.equipped == true or info._equipped == true
                
                if isEquipped then
                    local category = info._c or info.category or info._category
                    
                    if category then
                        clothes[category] = {
                            hash = info._h or info.hash or 0,
                            model = info._m or info.model or 0,
                            texture = info._t or info.texture or 1,
                            palette = info._p or info.palette or 'tint_generic_clean',
                            tints = info._tints or info.tints or {0, 0, 0}
                        }
                        print('[RSG-Appearance] Found equipped: ' .. category .. ' hash=' .. tostring(clothes[category].hash))
                    end
                end
            end
        end
    end
    
    return clothes
end

RegisterNetEvent('rsg-appearance:server:LoadSkin')
AddEventHandler('rsg-appearance:server:LoadSkin', function()
    local _source = source
    local User = RSGCore.Functions.GetPlayer(_source)
    if not User then return end
    local citizenid = User.PlayerData.citizenid
    local skins = MySQL.Sync.fetchAll('SELECT * FROM playerskins WHERE citizenid = ?', {citizenid})
    if skins[1] then
        local skin = json.decode(skins[1].skin or '{}')
        -- ★ ИСПРАВЛЕНО: Берём одежду из инвентаря (актуальные данные), а не из БД
        local clothes = GetEquippedClothesFromInventory(User)
        print('[RSG-Appearance] LoadSkin: Found ' .. TableLength(clothes) .. ' equipped clothes for ' .. citizenid)
        TriggerClientEvent('rsg-appearance:client:ApplySkin', _source, skin, clothes)
    else
        TriggerClientEvent('rsg-appearance:client:OpenCreator', _source)
    end
end)


RegisterNetEvent('rsg-appearance:server:deleteSkin')
AddEventHandler('rsg-appearance:server:deleteSkin', function(license, Callback)
    local _source = source
    local id
    for k, v in ipairs(GetPlayerIdentifiers(_source)) do
        if string.sub(v, 1, string.len('steam:')) == 'steam:' then
            id = v
            break
        end
    end
    local Callback = callback
    MySQL.Async.fetchAll('DELETE FROM playerskins WHERE `citizenid`= ? AND`license`= ?;', {id, license})
end)

RegisterNetEvent('rsg-appearance:server:updategender', function(gender)
    local Player = RSGCore.Functions.GetPlayer(source)
    local citizenid = Player.PlayerData.citizenid
    local license = RSGCore.Functions.GetIdentifier(source, 'license')

    local result = MySQL.Sync.fetchAll('SELECT * FROM players WHERE citizenid = ? AND license = ?', {citizenid, license})
    local Charinfo = json.decode(result[1].charinfo)
    Charinfo.gender = gender
    MySQL.Async.execute('UPDATE players SET `charinfo` = ? WHERE `citizenid`= ? AND `license`= ?', {json.encode(Charinfo), citizenid, license})
    Player.Functions.Save()
end)

-- ==========================================
-- ★ КОМАНДА ЗАГРУЗКИ ПЕРСОНАЖА (БЕЗ ЛЕЧЕНИЯ)
-- ==========================================

RSGCore.Commands.Add('loadcharacter', 'Загрузить внешность персонажа', {}, false, function(source)
    local Player = RSGCore.Functions.GetPlayer(source)
    if not Player then return end
    
    -- ★ ПРОВЕРКА: НЕ ЗАГРУЖАЕМ ЕСЛИ ИГРОК МЁРТВ
    local isDead = Player.PlayerData.metadata and Player.PlayerData.metadata['isdead']
    if isDead then
        TriggerClientEvent('ox_lib:notify', source, {
            title = 'Ошибка',
            description = 'Нельзя загрузить персонажа пока вы мертвы',
            type = 'error'
        })
        return
    end
    
    local citizenid = Player.PlayerData.citizenid
    local skins = MySQL.Sync.fetchAll('SELECT * FROM playerskins WHERE citizenid = ?', {citizenid})
    
    if skins and skins[1] then
        local skin = json.decode(skins[1].skin or '{}')
        local clothes = GetEquippedClothesFromInventory(Player)
        
        print('[RSG-Appearance] loadcharacter: Found ' .. TableLength(clothes) .. ' equipped clothes')
        
        -- ★ ИСПОЛЬЗУЕМ ОБЫЧНОЕ СОБЫТИЕ (оно уже сохраняет HP в creator.lua:941)
        TriggerClientEvent('rsg-appearance:client:ApplySkin', source, skin, clothes)
        
        TriggerClientEvent('ox_lib:notify', source, {
            title = 'Персонаж',
            description = 'Внешность загружена',
            type = 'success'
        })
    else
        TriggerClientEvent('ox_lib:notify', source, {
            title = 'Ошибка',
            description = 'Данные персонажа не найдены',
            type = 'error'
        })
    end
end)

-- ==========================================
-- ★ АВТОЗАГРУЗКА ПРИ ВХОДЕ ИГРОКА (ИСПРАВЛЕНО)
-- ==========================================

AddEventHandler('RSGCore:Server:PlayerLoaded', function(Player)
    local src = Player.PlayerData.source
    local citizenid = Player.PlayerData.citizenid
    
    -- ★ ПРОВЕРЯЕМ ЧТО ИГРОК НЕ МЁРТВ
    local isDead = Player.PlayerData.metadata and Player.PlayerData.metadata['isdead']
    if isDead then
        print('[RSG-Appearance] Auto-load BLOCKED - Player ' .. citizenid .. ' is dead')
        return
    end
    
    local skins = MySQL.Sync.fetchAll('SELECT * FROM playerskins WHERE citizenid = ?', {citizenid})
    
    if skins and skins[1] then
        local skin = json.decode(skins[1].skin or '{}')
        
        -- ★ FIX: Увеличен таймаут с 3с до 5с для высокого пинга
        -- При большом пинге клиент может не успеть инициализировать пед за 3 сек
        SetTimeout(5000, function()
            local PlayerNow = RSGCore.Functions.GetPlayer(src)
            if PlayerNow then
                -- ★ ПОВТОРНАЯ ПРОВЕРКА СМЕРТИ
                local isStillDead = PlayerNow.PlayerData.metadata and PlayerNow.PlayerData.metadata['isdead']
                if isStillDead then
                    print('[RSG-Appearance] Auto-load BLOCKED (delayed) - Player is dead')
                    return
                end
                
                local clothes = GetEquippedClothesFromInventory(PlayerNow)
                print('[RSG-Appearance] Auto-load: Found ' .. TableLength(clothes) .. ' equipped clothes for ' .. citizenid)
                
                -- ★ ИСПОЛЬЗУЕМ ОБЫЧНОЕ ПРИМЕНЕНИЕ (без изменения HP)
                TriggerClientEvent('rsg-appearance:client:ApplySkin', src, skin, clothes)
            end
        end)
    end
end)

-- ==========================================
-- ПОКУПКА ОДЕЖДЫ В МАГАЗИНЕ
-- ==========================================

RegisterNetEvent('rsg-appearance:server:purchaseClothes')
AddEventHandler('rsg-appearance:server:purchaseClothes', function(clothesCache, totalPrice)
    local src = source
    local Player = RSGCore.Functions.GetPlayer(src)
    if not Player then return end
    
    local cash = Player.Functions.GetMoney('cash')
    if cash < totalPrice then
        TriggerClientEvent('ox_lib:notify', src, {
            title = 'Магазин',
            description = 'Недостаточно денег',
            type = 'error'
        })
        return
    end
    
    Player.Functions.RemoveMoney('cash', totalPrice, 'clothing-purchase')
    
    TriggerClientEvent('ox_lib:notify', src, {
        title = 'Магазин',
        description = 'Покупка совершена: $' .. totalPrice,
        type = 'success'
    })
end)

print('[RSG-Appearance] Server loaded with fixed loadcharacter (preserves health)')

-- ==========================================
-- NAKED BODY SYSTEM: Работа с skin_tone
-- ==========================================

-- Отправить skin_tone клиенту при запросе
RegisterNetEvent('rsg-appearance:server:RequestSkinTone')
AddEventHandler('rsg-appearance:server:RequestSkinTone', function()
    local _source = source
    local Player = RSGCore.Functions.GetPlayer(_source)
    
    if not Player then return end
    
    local citizenid = Player.PlayerData.citizenid
    local result = MySQL.Sync.fetchAll('SELECT skin FROM playerskins WHERE citizenid = ?', {citizenid})
    
    if result and result[1] and result[1].skin then
        local skinData = json.decode(result[1].skin)
        local skinTone = skinData.skin_tone or 1
        print('[RSG-Appearance] Sending skin_tone=' .. skinTone .. ' to ' .. citizenid)
        TriggerClientEvent('rsg-appearance:client:SetSkinTone', _source, skinTone)
    end
end)

-- Исправление skin_tone в базе данных

RegisterNetEvent('rsg-appearance:server:FixSkinTone')
AddEventHandler('rsg-appearance:server:FixSkinTone', function(newSkinTone)
    local _source = source
    local Player = RSGCore.Functions.GetPlayer(_source)
    
    if not Player then
        print('[RSG-Appearance] FixSkinTone: Player not found')
        return
    end
    
    local citizenid = Player.PlayerData.citizenid
    
    -- Проверяем валидность
    if not newSkinTone or newSkinTone < 1 or newSkinTone > 6 then
        print('[RSG-Appearance] FixSkinTone: Invalid skin_tone ' .. tostring(newSkinTone))
        return
    end
    
    -- Получаем текущий скин
    local result = MySQL.Sync.fetchAll('SELECT skin FROM playerskins WHERE citizenid = ?', {citizenid})
    
    if result and result[1] and result[1].skin then
        local skinData = json.decode(result[1].skin)
        local oldTone = skinData.skin_tone
        
        -- Обновляем skin_tone
        skinData.skin_tone = newSkinTone
        
        -- Сохраняем обратно
        local encodedSkin = json.encode(skinData)
        MySQL.Async.execute('UPDATE playerskins SET skin = @skin WHERE citizenid = @citizenid', {
            ['citizenid'] = citizenid,
            ['skin'] = encodedSkin
        }, function(rowsChanged)
            print('[RSG-Appearance] FixSkinTone: Updated skin_tone from ' .. tostring(oldTone) .. ' to ' .. newSkinTone .. ' for ' .. citizenid)
            
            TriggerClientEvent('ox_lib:notify', _source, {
                title = 'Цвет кожи',
                description = 'Сохранено: skin_tone = ' .. newSkinTone,
                type = 'success'
            })
        end)
    else
        print('[RSG-Appearance] FixSkinTone: No skin data found for ' .. citizenid)
    end
end)