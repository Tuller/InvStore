-- A LibItemCache-2.0 interface implementation

local AddonName = ...
local Addon = LibStub("AceAddon-3.0"):GetAddon(AddonName)
local ItemCache = LibStub:NewLibrary(AddonName .. "ItemCache", 0)

ItemCache.IsItemCache = true

-- helpers
local itemInfos = setmetatable({}, {
    __index = function(self, itemData)
        local result
        if type(itemData) == "number" then
            result = {
                id = itemData,
                cached = true,
                count = 1
            }
        else
            local itemStringOrID = strsplit(";", itemData)
            local itemID = tonumber(itemStringOrID)

            if itemID then
                result = {
                    id = itemID,
                    cached = true,
                    count = 1
                }
            else
                result = {
                    id = tonumber(itemStringOrID:match("^item:(%d+)")),
                    link = itemStringOrID,
                    cached = true,
                    count = 1
                }
            end
        end

        self[itemData] = result
        return result
    end,

    mode = "kv"
})

local function getItemInfo(itemData)
    if itemData then
        return itemInfos[itemData]
    end
end

local function getPlayer(realm, name)
    for _, player in pairs(Addon.db.players) do
        if player.realm == realm and player.name == name then
            return player
        end
    end
end

local function getGuild(realm, name)
    for _, guild in pairs(Addon.db.guilds) do
        if guild.realm == realm and guild.name == name then
            return guild
        end
    end
end

local function getInventoryIndex(bagID)
    if bagID == "equip" then
        return "equipped"
    end

    if bagID == "vault" then
        return "voidStorage"
    end

    return tonumber(bagID)
end

-- players
function ItemCache:GetPlayers(realm)
    local players = Addon.db.players
    local id, player
    return function()
        repeat
            id, player = next(players, id)
        until id == nil or player.realm == realm

        if player then
            return player.name
        end
    end
end

function ItemCache:GetPlayer(realm, name)
    local player = getPlayer(realm, name)

    if player then
        return {
            cached = true,
            money = player.money,
            faction = player.faction,
            guild = player.guild,
            class = player.class,
            gender = player.gender,
            race = player.race
        }
    end
end

function ItemCache:DeletePlayer(realm, name)
    for id, player in pairs(Addon.db.players) do
        if player.name == name and player.realm == realm then
            Addon.db.players[id] = nil
            break
        end
    end
end

-- guilds
function ItemCache:GetGuilds(realm)
    local guilds = Addon.db.guilds
    local id, guild

    return function()
        repeat
            id, guild = next(guilds, id)
        until id == nil or guild.realm == realm

        if guild then
            return guild.name
        end
    end
end

function ItemCache:GetGuild(realm, name)
    local guild = getGuild(realm, name)

    if guild then
        return {
            cached = true,
            isguild = true,
            money = guild.money,
            faction = guild.faction,
            guild = guild.guild
        }
    end
end

function ItemCache:DeleteGuild(realm, name)
    for id, guild in pairs(Addon.db.guilds) do
        if guild.name == name and guild.realm == realm then
            Addon.db.guilds[id] = nil
        end
    end
end

-- items
function ItemCache:GetBag(realm, owner, bag)
    local player = getPlayer(realm, owner)
    if not player then
        return
    end

    local items = player.inventory[bag]
    local size = items and items.size or 0

    if size > 0 then
        local slot = bag > 0 and ContainerIDToInventoryID(bag) or nil
        local itemInfo
        if slot then
            itemInfo = getItemInfo(player.inventory.equipped[slot]) or {}
        else
            itemInfo = {}
        end

        itemInfo.count = size
        return itemInfo
    end
end

function ItemCache:GetItem(realm, owner, bag, slot)
    local player = getPlayer(realm, owner)
    if not player then
        return
    end

    local index = getInventoryIndex(bag)
    if not index then
        return
    end

    local items = player.inventory[index]
    if not items then
        return
    end

    return getItemInfo(items[slot])
end

-- guild bank
function ItemCache:GetGuildItem(realm, name, tabID, slot)
    local guild = getGuild(realm, name)
    if not guild then
        return
    end

    local tab = guild.inventory[tabID]
    if tab then
        return getItemInfo(tab[slot])
    end
end

function ItemCache:GetGuildTab(realm, name, tabID)
    local guild = getGuild(realm, name)
    if not guild then
        return
    end

    local tab = guild.inventory[tabID]
    if tab then
        return {
            name = tab.name,
            icon = tab.icon,
            viewable = true
        }
    end
end
