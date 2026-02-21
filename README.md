# Shiw Character System
This is 2 script what u can use free to make cloth like item and get character creation. Only For RSG Framework
IF U WANT IT MAY BE COMPTABILYTI WITH OTHERS RSG BASED SCRIPT RENAME RESOURCES TO rsg-appearance and rsg-clothingstore
*Need to add this items in rsg-core
```
-- ============================================================
-- ПРЕДМЕТЫ ОДЕЖДЫ ДЛЯ RSG-CORE
-- Добавьте эти строки в файл rsg-core/shared/items.lua
-- ============================================================

-- ==========================================
-- ГОЛОВНЫЕ УБОРЫ
-- ==========================================
['clothing_hats']               = {['name'] = 'clothing_hats',              ['label'] = 'Головной убор',          ['weight'] = 200,  ['type'] = 'item', ['image'] = 'clothing_hats.png',             ['unique'] = true, ['useable'] = true, ['shouldClose'] = true, ['description'] = 'Головной убор'},

-- ==========================================
-- ОДЕЖДА - ВЕРХНЯЯ ЧАСТЬ ТЕЛА
-- ==========================================
['clothing_shirts_full']        = {['name'] = 'clothing_shirts_full',       ['label'] = 'Рубашка',                ['weight'] = 300,  ['type'] = 'item', ['image'] = 'clothing_shirts_full.png',      ['unique'] = true, ['useable'] = true, ['shouldClose'] = true, ['description'] = 'Рубашка'},
['clothing_vests']              = {['name'] = 'clothing_vests',             ['label'] = 'Жилет',                  ['weight'] = 300,  ['type'] = 'item', ['image'] = 'clothing_vests.png',            ['unique'] = true, ['useable'] = true, ['shouldClose'] = true, ['description'] = 'Жилет'},
['clothing_coats']              = {['name'] = 'clothing_coats',             ['label'] = 'Пальто',                 ['weight'] = 800,  ['type'] = 'item', ['image'] = 'clothing_coats.png',            ['unique'] = true, ['useable'] = true, ['shouldClose'] = true, ['description'] = 'Пальто или куртка'},
['clothing_coats_closed']       = {['name'] = 'clothing_coats_closed',      ['label'] = 'Закрытое пальто',        ['weight'] = 800,  ['type'] = 'item', ['image'] = 'clothing_coats.png',            ['unique'] = true, ['useable'] = true, ['shouldClose'] = true, ['description'] = 'Застёгнутое пальто'},
['clothing_cloaks']             = {['name'] = 'clothing_cloaks',            ['label'] = 'Плащ',                   ['weight'] = 600,  ['type'] = 'item', ['image'] = 'clothing_cloaks.png',           ['unique'] = true, ['useable'] = true, ['shouldClose'] = true, ['description'] = 'Плащ или накидка'},
['clothing_ponchos']            = {['name'] = 'clothing_ponchos',           ['label'] = 'Пончо',                  ['weight'] = 500,  ['type'] = 'item', ['image'] = 'clothing_ponchos.png',          ['unique'] = true, ['useable'] = true, ['shouldClose'] = true, ['description'] = 'Пончо'},

-- ==========================================
-- ОДЕЖДА - НИЖНЯЯ ЧАСТЬ ТЕЛА
-- ==========================================
['clothing_pants']              = {['name'] = 'clothing_pants',             ['label'] = 'Штаны',                  ['weight'] = 400,  ['type'] = 'item', ['image'] = 'clothing_pants.png',            ['unique'] = true, ['useable'] = true, ['shouldClose'] = true, ['description'] = 'Штаны'},
['clothing_skirts']             = {['name'] = 'clothing_skirts',            ['label'] = 'Юбка',                   ['weight'] = 350,  ['type'] = 'item', ['image'] = 'clothing_skirts.png',           ['unique'] = true, ['useable'] = true, ['shouldClose'] = true, ['description'] = 'Юбка'},
['clothing_chaps']              = {['name'] = 'clothing_chaps',             ['label'] = 'Чапсы',                  ['weight'] = 400,  ['type'] = 'item', ['image'] = 'clothing_chaps.png',            ['unique'] = true, ['useable'] = true, ['shouldClose'] = true, ['description'] = 'Кожаные накладки на ноги'},

-- ==========================================
-- ОДЕЖДА - ОБУВЬ
-- ==========================================
['clothing_boots']              = {['name'] = 'clothing_boots',             ['label'] = 'Сапоги',                 ['weight'] = 500,  ['type'] = 'item', ['image'] = 'clothing_boots.png',            ['unique'] = true, ['useable'] = true, ['shouldClose'] = true, ['description'] = 'Сапоги или ботинки'},
['clothing_spurs']              = {['name'] = 'clothing_spurs',             ['label'] = 'Шпоры',                  ['weight'] = 100,  ['type'] = 'item', ['image'] = 'clothing_spurs.png',            ['unique'] = true, ['useable'] = true, ['shouldClose'] = true, ['description'] = 'Шпоры для верховой езды'},

-- ==========================================
-- ОДЕЖДА - РУКИ
-- ==========================================
['clothing_gloves']             = {['name'] = 'clothing_gloves',            ['label'] = 'Перчатки',               ['weight'] = 100,  ['type'] = 'item', ['image'] = 'clothing_gloves.png',           ['unique'] = true, ['useable'] = true, ['shouldClose'] = true, ['description'] = 'Перчатки'},
['clothing_gauntlets']          = {['name'] = 'clothing_gauntlets',         ['label'] = 'Наручи',                 ['weight'] = 200,  ['type'] = 'item', ['image'] = 'clothing_gauntlets.png',        ['unique'] = true, ['useable'] = true, ['shouldClose'] = true, ['description'] = 'Защитные наручи'},
['clothing_rings_rh']           = {['name'] = 'clothing_rings_rh',          ['label'] = 'Кольцо (правая)',        ['weight'] = 20,   ['type'] = 'item', ['image'] = 'clothing_rings_rh.png',         ['unique'] = true, ['useable'] = true, ['shouldClose'] = true, ['description'] = 'Кольцо на правую руку'},
['clothing_rings_lh']           = {['name'] = 'clothing_rings_lh',          ['label'] = 'Кольцо (левая)',         ['weight'] = 20,   ['type'] = 'item', ['image'] = 'clothing_rings_lh.png',         ['unique'] = true, ['useable'] = true, ['shouldClose'] = true, ['description'] = 'Кольцо на левую руку'},
['clothing_bracelets']          = {['name'] = 'clothing_bracelets',         ['label'] = 'Браслет',                ['weight'] = 30,   ['type'] = 'item', ['image'] = 'clothing_bracelets.png',        ['unique'] = true, ['useable'] = true, ['shouldClose'] = true, ['description'] = 'Браслет'},

-- ==========================================
-- ОДЕЖДА - ШЕЯ И ЛИЦО
-- ==========================================
['clothing_neckwear']           = {['name'] = 'clothing_neckwear',          ['label'] = 'Шейный платок',          ['weight'] = 100,  ['type'] = 'item', ['image'] = 'clothing_neckwear.png',         ['unique'] = true, ['useable'] = true, ['shouldClose'] = true, ['description'] = 'Платок или галстук'},
['clothing_neckties']           = {['name'] = 'clothing_neckties',          ['label'] = 'Галстук',                ['weight'] = 50,   ['type'] = 'item', ['image'] = 'clothing_neckties.png',         ['unique'] = true, ['useable'] = true, ['shouldClose'] = true, ['description'] = 'Галстук'},
['clothing_necklaces']          = {['name'] = 'clothing_necklaces',         ['label'] = 'Ожерелье',               ['weight'] = 50,   ['type'] = 'item', ['image'] = 'clothing_necklaces.png',        ['unique'] = true, ['useable'] = true, ['shouldClose'] = true, ['description'] = 'Ожерелье'},
['clothing_masks']              = {['name'] = 'clothing_masks',             ['label'] = 'Маска',                  ['weight'] = 100,  ['type'] = 'item', ['image'] = 'clothing_masks.png',            ['unique'] = true, ['useable'] = true, ['shouldClose'] = true, ['description'] = 'Маска на лицо'},
['clothing_eyewear']            = {['name'] = 'clothing_eyewear',           ['label'] = 'Очки',                   ['weight'] = 50,   ['type'] = 'item', ['image'] = 'clothing_eyewear.png',          ['unique'] = true, ['useable'] = true, ['shouldClose'] = true, ['description'] = 'Очки'},

-- ==========================================
-- ОДЕЖДА - АКСЕССУАРЫ И РЕМНИ
-- ==========================================
['clothing_suspenders']         = {['name'] = 'clothing_suspenders',        ['label'] = 'Подтяжки',               ['weight'] = 150,  ['type'] = 'item', ['image'] = 'clothing_suspenders.png',       ['unique'] = true, ['useable'] = true, ['shouldClose'] = true, ['description'] = 'Подтяжки'},
['clothing_belts']              = {['name'] = 'clothing_belts',             ['label'] = 'Ремень',                 ['weight'] = 200,  ['type'] = 'item', ['image'] = 'clothing_belts.png',            ['unique'] = true, ['useable'] = true, ['shouldClose'] = true, ['description'] = 'Поясной ремень'},
['clothing_belt_buckles']       = {['name'] = 'clothing_belt_buckles',      ['label'] = 'Пряжка ремня',           ['weight'] = 100,  ['type'] = 'item', ['image'] = 'clothing_belt_buckles.png',     ['unique'] = true, ['useable'] = true, ['shouldClose'] = true, ['description'] = 'Пряжка для ремня'},
['clothing_gunbelts']           = {['name'] = 'clothing_gunbelts',          ['label'] = 'Патронташ',              ['weight'] = 400,  ['type'] = 'item', ['image'] = 'clothing_gunbelts.png',         ['unique'] = true, ['useable'] = true, ['shouldClose'] = true, ['description'] = 'Пояс с патронами'},
['clothing_holsters_left']      = {['name'] = 'clothing_holsters_left',     ['label'] = 'Кобура (левая)',         ['weight'] = 200,  ['type'] = 'item', ['image'] = 'clothing_holsters_left.png',    ['unique'] = true, ['useable'] = true, ['shouldClose'] = true, ['description'] = 'Левая кобура'},
['clothing_holsters_right']     = {['name'] = 'clothing_holsters_right',    ['label'] = 'Кобура (правая)',        ['weight'] = 200,  ['type'] = 'item', ['image'] = 'clothing_holsters_right.png',   ['unique'] = true, ['useable'] = true, ['shouldClose'] = true, ['description'] = 'Правая кобура'},

-- ==========================================
-- ОДЕЖДА - СУМКИ И СНАРЯЖЕНИЕ
-- ==========================================
['clothing_satchels']           = {['name'] = 'clothing_satchels',          ['label'] = 'Сумка',                  ['weight'] = 300,  ['type'] = 'item', ['image'] = 'clothing_satchels.png',         ['unique'] = true, ['useable'] = true, ['shouldClose'] = true, ['description'] = 'Наплечная сумка'},
['clothing_loadouts']           = {['name'] = 'clothing_loadouts',          ['label'] = 'Снаряжение',             ['weight'] = 500,  ['type'] = 'item', ['image'] = 'clothing_loadouts.png',         ['unique'] = true, ['useable'] = true, ['shouldClose'] = true, ['description'] = 'Комплект снаряжения'},

-- ==========================================
-- ОДЕЖДА - ЗНАЧКИ И УКРАШЕНИЯ
-- ==========================================
['clothing_badges']             = {['name'] = 'clothing_badges',            ['label'] = 'Значок',                 ['weight'] = 50,   ['type'] = 'item', ['image'] = 'clothing_badges.png',           ['unique'] = true, ['useable'] = true, ['shouldClose'] = true, ['description'] = 'Значок шерифа или маршала'},
['clothing_earrings']           = {['name'] = 'clothing_earrings',          ['label'] = 'Серьги',                 ['weight'] = 20,   ['type'] = 'item', ['image'] = 'clothing_earrings.png',         ['unique'] = true, ['useable'] = true, ['shouldClose'] = true, ['description'] = 'Серьги'},
['clothing_accessories']        = {['name'] = 'clothing_accessories',       ['label'] = 'Аксессуар',              ['weight'] = 100,  ['type'] = 'item', ['image'] = 'clothing_accessories.png',      ['unique'] = true, ['useable'] = true, ['shouldClose'] = true, ['description'] = 'Декоративный аксессуар'},

-- ==========================================
-- ОДЕЖДА - СПЕЦИАЛЬНЫЕ (ЖЕНСКИЕ)
-- ==========================================
['clothing_corsets']            = {['name'] = 'clothing_corsets',           ['label'] = 'Корсет',                 ['weight'] = 300,  ['type'] = 'item', ['image'] = 'clothing_corsets.png',          ['unique'] = true, ['useable'] = true, ['shouldClose'] = true, ['description'] = 'Корсет'},
['clothing_dresses']            = {['name'] = 'clothing_dresses',           ['label'] = 'Платье',                 ['weight'] = 500,  ['type'] = 'item', ['image'] = 'clothing_dresses.png',          ['unique'] = true, ['useable'] = true, ['shouldClose'] = true, ['description'] = 'Платье'},
```
And create SQL Tables for this

--
-- Структура таблицы `players`
--
```
CREATE TABLE `players` (
  `id` int(11) NOT NULL,
  `citizenid` varchar(255) NOT NULL,
  `cid` int(11) DEFAULT NULL,
  `license` varchar(255) NOT NULL,
  `name` varchar(255) NOT NULL,
  `outlawstatus` int(11) NOT NULL DEFAULT 0,
  `money` text NOT NULL,
  `charinfo` longtext CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci DEFAULT NULL,
  `job` text NOT NULL,
  `gang` text DEFAULT NULL,
  `position` text NOT NULL,
  `metadata` text NOT NULL,
  `inventory` longtext DEFAULT NULL,
  `weight` int(11) NOT NULL DEFAULT 0,
  `slots` int(11) NOT NULL DEFAULT 0,
  `last_updated` timestamp NOT NULL DEFAULT current_timestamp() ON UPDATE current_timestamp(),
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci;
```
https://upload.fixitfy.com.tr/images/FIXITFY-JRcDtCRDai.png
https://upload.fixitfy.com.tr/images/FIXITFY-lpaQOMqbUY.png
https://upload.fixitfy.com.tr/images/FIXITFY-XhLqnHdUJA.png
