RSGCore = exports['rsg-core']:GetCoreObject()

-- ★ Таблица одежды для разрешения model→hash на сервере (ленивая загрузка)
local _clothingTable = nil
local function GetClothingTable()
    if _clothingTable then return _clothingTable end
    local ok, tbl = pcall(function() return require('data.clothing') end)
    _clothingTable = ok and tbl or nil
    return _clothingTable
end

-- ★ Разрешение model/texture → hash на сервере (меньше логики на клиенте)
local function ResolveClothesHashes(skin, clothes)
    if not clothes or next(clothes) == nil then return clothes end
    local clothing = GetClothingTable()
    if not clothing then return clothes end

    local isMale = (skin and tonumber(skin.sex) or 1) == 1
    local gender = isMale and 'male' or 'female'

    local function resolveHash(category, model, texture, hairModelForAccessories)
        if not model or tonumber(model) <= 0 then return 0 end
        model = tonumber(model)
        texture = tonumber(texture) or 1
        if category == 'hair_accessories' and not isMale and hairModelForAccessories and hairModelForAccessories >= 1 then
            model = hairModelForAccessories
        end
        if clothing[gender] and clothing[gender][category] then
            if clothing[gender][category][model] then
                if clothing[gender][category][model][texture] then
                    return clothing[gender][category][model][texture].hash
                elseif clothing[gender][category][model][1] then
                    return clothing[gender][category][model][1].hash
                end
            elseif category == 'hair_accessories' and clothing[gender][category][1] then
                if clothing[gender][category][1][texture] then
                    return clothing[gender][category][1][texture].hash
                elseif clothing[gender][category][1][1] then
                    return clothing[gender][category][1][1].hash
                end
            end
        end
        return 0
    end

    local hairModel = skin and skin.hair and type(skin.hair) == 'table' and tonumber(skin.hair.model) or nil
    for cat, data in pairs(clothes) do
        if type(data) == 'table' then
            local hash = data.hash or data._h or 0
            local model = data.model or data._m or 0
            local texture = data.texture or data._t or 1
            if (not hash or hash == 0) and model and tonumber(model) > 0 then
                local resolvedHash = resolveHash(cat, model, texture, hairModel)
                if resolvedHash and resolvedHash ~= 0 then
                    data.hash = resolvedHash
                    data._h = resolvedHash
                end
            end
        end
    end
    return clothes
end

-- ★ УТИЛИТЫ (определяем ДО обработчиков событий)
function TableLength(t)
    if not t then return 0 end
    local count = 0
    for _ in pairs(t) do count = count + 1 end
    return count
end

-- ★ Кулдаун /loadcharacter (сек), чтобы нельзя было восстанавливать HP спамом
local LoadCharacterCooldownSec = 3
local LoadCharacterLastTime = {}

-- ★ Глубокий мерж таблиц (сохраняет head, face features и т.д. при частичном обновлении)
local function DeepMergeSkin(target, source)
    if not target then target = {} end
    if not source then return target end
    for k, v in pairs(source) do
        if v ~= nil then
            if type(v) == "table" and not (k == "components" or k == "stateBag") then
                if type(target[k]) ~= "table" then target[k] = {} end
                DeepMergeSkin(target[k], v)
            else
                target[k] = v
            end
        end
    end
    return target
end

RegisterNetEvent('rsg-appearance:server:SaveSkin')
AddEventHandler('rsg-appearance:server:SaveSkin', function(skin, clothes, oldplayer)
    if not skin or type(skin) ~= "table" then return end
    local clothesData = clothes
    if not clothesData or type(clothesData) ~= "table" then clothesData = {} end

    local Player = RSGCore.Functions.GetPlayer(source)
    if not Player then return end
    local citizenid = Player.PlayerData.citizenid

    if oldplayer then
        local result = MySQL.Sync.fetchAll('SELECT * FROM playerskins WHERE citizenid = ?', {citizenid})

        if result and #result > 0 then
            local existingSkin = json.decode(result[1].skin or '{}')
            local existingClothes = json.decode(result[1].clothes or '{}')
            if not existingSkin then existingSkin = {} end
            if not existingClothes then existingClothes = {} end

            -- ★ Глубокий мерж: сохраняем head, face features, overlays и т.д.
            DeepMergeSkin(existingSkin, skin)
            DeepMergeSkin(existingClothes, clothesData)

            MySQL.Async.execute('UPDATE playerskins SET skin = @skin, clothes = @clothes WHERE citizenid = @citizenid', {
                ['citizenid'] = citizenid,
                ['skin'] = json.encode(existingSkin),
                ['clothes'] = json.encode(existingClothes),
            }, function()
                SetPlayerAppearanceState(source, existingSkin, existingClothes)
            end)
        else
            -- Нет записи — вставляем полный скин из редактора
            MySQL.Async.insert('INSERT INTO playerskins (citizenid, skin, clothes) VALUES (?, ?, ?)', {
                citizenid,
                json.encode(skin),
                json.encode(clothesData)
            }, function()
                SetPlayerAppearanceState(source, skin, clothesData)
            end)
        end
    else
        MySQL.Async.insert('INSERT INTO playerskins (citizenid, skin, clothes) VALUES (?, ?, ?)', {
            citizenid,
            json.encode(skin),
            json.encode(clothesData)
        }, function() end)
        TriggerClientEvent('rco-spawnselector:client:openSpawnSelector', source, true)
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

-- ★ Одежда: только из БД (playerskins.clothes). SyncClothesToDatabase пишет при equip/unequip.
-- ★ State Bag + дублирующий broadcast: на части сборок RedM вложенный `skin` в state у других клиентов
--    приходит урезанным (лицо «дефолт»). JSON по сети от сервера сохраняет все face features.
-- ★ loadAt: принудительно меняет значение state, иначе повторный loadcharacter с теми же данными не триггерит handler
local _loadCharacterNonce = 0
local function SetPlayerAppearanceState(src, skin, clothes)
    if not src or not skin then return end
    clothes = ResolveClothesHashes(skin, clothes or {})
    _loadCharacterNonce = _loadCharacterNonce + 1
    local okS, sJson = pcall(json.encode, skin)
    local okC, cJson = pcall(json.encode, clothes or {})
    local state = Player(src).state
    if state then
        -- skin_json / clothes_json: строка реплицируется целиком; вложенный skin у других клиентов часто обрезается
        -- и EnsureFaceFeaturesForSync подставляет 0 → лицо «шире», чем у владельца (отрицательные морфы теряются).
        local payload = {
            skin = skin,
            clothes = clothes,
            loadAt = _loadCharacterNonce,
        }
        if okS and sJson then payload.skin_json = sJson end
        if okC and cJson then payload.clothes_json = cJson end
        state:set('appearance', payload, true)
    end
    if okS and okC and sJson and cJson and (#sJson + #cJson) < 400000 then
        TriggerClientEvent('rsg-appearance:client:PeerAppearancePayload', -1, src, sJson, cJson, _loadCharacterNonce)
    end
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
        local clothes = json.decode(skins[1].clothes or '{}')
        SetPlayerAppearanceState(_source, skin, clothes)
    else
        TriggerClientEvent('rsg-appearance:client:OpenCreator', _source)
    end
end)

-- ★ Скин для открытия редактора (без сброса) — только данные из БД
RSGCore.Functions.CreateCallback('rsg-appearance:server:GetSkinForEditor', function(source, cb)
    local Player = RSGCore.Functions.GetPlayer(source)
    if not Player then cb(nil) return end
    local citizenid = Player.PlayerData.citizenid
    local skins = MySQL.Sync.fetchAll('SELECT skin FROM playerskins WHERE citizenid = ?', {citizenid})
    if skins and skins[1] and skins[1].skin then
        cb(json.decode(skins[1].skin or '{}'))
    else
        cb(nil)
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
-- ★ Событие для вызова с клиента (ExecuteCommand с клиента не триггерит серверные команды)
-- ==========================================

local function DoLoadCharacter(source)
    local Player = RSGCore.Functions.GetPlayer(source)
    if not Player then return end

    -- ★ Кулдаун: нельзя спамить команду (иначе можно восстанавливать HP)
    local now = os.time()
    local last = LoadCharacterLastTime[source] or 0
    if now - last < LoadCharacterCooldownSec then
        TriggerClientEvent('ox_lib:notify', source, {
            title = 'Подождите',
            description = 'Повторно через ' .. (LoadCharacterCooldownSec - (now - last)) .. ' сек',
            type = 'error'
        })
        return
    end
    LoadCharacterLastTime[source] = now

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

    -- ★ Синхронизируем инвентарь одежды в БД перед загрузкой (как fixcharacter)
    if SyncClothesToDatabase then
        SyncClothesToDatabase(source)
    end

    local citizenid = Player.PlayerData.citizenid
    local skins = MySQL.Sync.fetchAll('SELECT * FROM playerskins WHERE citizenid = ?', {citizenid})

    if skins and skins[1] then
        local skin = json.decode(skins[1].skin or '{}')
        local clothes = json.decode(skins[1].clothes or '{}')
        SetPlayerAppearanceState(source, skin, clothes)

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
end

-- ★ Только чтение skin для hate-style ClonePedToTarget (без полного loadcharacter)
RegisterNetEvent('rsg-appearance:server:HateCloneGetSkin', function()
    local src = source
    local skin = {}
    local Player = RSGCore.Functions.GetPlayer(src)
    if Player and Player.PlayerData and Player.PlayerData.citizenid then
        local citizenid = Player.PlayerData.citizenid
        local rows = MySQL.Sync.fetchAll('SELECT skin FROM playerskins WHERE citizenid = ? LIMIT 1', { citizenid })
        if rows and rows[1] and rows[1].skin and rows[1].skin ~= '' then
            local ok, dec = pcall(json.decode, rows[1].skin)
            if ok and type(dec) == 'table' then
                skin = dec
            end
        end
    end
    -- Всегда отвечаем клиенту: иначе _RicxHateCloneQueue зависает и предмет «надевается» снова и снова.
    TriggerClientEvent('rsg-appearance:client:HateCloneSkinResult', src, skin)
end)

RegisterNetEvent('rsg-appearance:server:LoadCharacter')
AddEventHandler('rsg-appearance:server:LoadCharacter', function()
    DoLoadCharacter(source)
end)

RSGCore.Commands.Add('loadcharacter', 'Загрузить внешность персонажа', {}, false, function(source)
    DoLoadCharacter(source)
end)

-- ==========================================
-- ★ АВТОЗАГРУЗКА: loadcharacter при входе (синк инвентаря → БД → полная загрузка)
-- ==========================================

AddEventHandler('RSGCore:Server:PlayerLoaded', function(Player)
    local src = Player.PlayerData.source
    local citizenid = Player.PlayerData.citizenid
    -- ★ DoLoadCharacter: SyncClothesToDatabase → свежие данные из playerskins → ApplySkin (useEquipPath)
    SetTimeout(6500, function()
        if not GetPlayerName(src) then return end
        local P = RSGCore.Functions.GetPlayer(src)
        if not P then return end
        local isDead = P.PlayerData.metadata and P.PlayerData.metadata['isdead']
        if isDead then
            -- Мёртвые: только SetPlayerAppearanceState (DoLoadCharacter блокирует)
            local skins = MySQL.Sync.fetchAll('SELECT * FROM playerskins WHERE citizenid = ?', {citizenid})
            if skins and skins[1] then
                local skin = json.decode(skins[1].skin or '{}')
                local clothes = json.decode(skins[1].clothes or '{}')
                SetPlayerAppearanceState(src, skin, clothes)
            end
        else
            DoLoadCharacter(src)
        end
    end)
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

AddEventHandler('playerDropped', function()
    local src = source
    if src then LoadCharacterLastTime[src] = nil end
end)

-- ★ Экспорт для других ресурсов: установить внешность через State Bag (с разрешением хешей)
exports('SetPlayerAppearance', function(src, skin, clothes)
    if not src or not skin then return end
    SetPlayerAppearanceState(src, skin, clothes or {})
end)

print('[RSG-Appearance] Server loaded (State Bag sync, server-side hash resolution)')

-- ★ Команда для админов: вернуть персонажа в редактор внешности без сброса
-- /editappearance — открыть себе; /editappearance [id] — открыть указанному игроку
RSGCore.Commands.Add('editappearance', 'Открыть редактор внешности без сброса (админ). /editappearance [id]', 
    { { name = 'id', help = 'ID игрока (опционально)' } }, false, function(source, args)
    if not RSGCore.Functions.HasPermission(source, 'admin') then
        TriggerClientEvent('ox_lib:notify', source, { title = 'Нет прав', description = 'Только для администраторов', type = 'error' })
        return
    end
    local targetId = tonumber(args and args[1])
    local target = source
    if targetId then
        if not GetPlayerName(targetId) then
            TriggerClientEvent('ox_lib:notify', source, { title = 'Ошибка', description = 'Игрок с ID ' .. tostring(targetId) .. ' не найден', type = 'error' })
            return
        end
        target = targetId
    end
    TriggerClientEvent('rsg-appearance:client:OpenEditor', target)
    if target ~= source then
        TriggerClientEvent('ox_lib:notify', source, { title = 'Редактор', description = 'Открыт для игрока #' .. target, type = 'success' })
    end
end, 'admin')

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
        local skinTone = tonumber(skinData.skin_tone) or 1
        if skinTone < 1 then skinTone = 1 end
        if skinTone > 6 then skinTone = 6 end
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