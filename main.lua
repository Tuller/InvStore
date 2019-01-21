local AddonName = ...
local Addon = LibStub("AceAddon-3.0"):NewAddon(AddonName, "AceEvent-3.0", "AceConsole-3.0")
local DB_NAME = AddonName .. "DB"
local DB_VERSION = 1

-- local bindings
local After = C_Timer.After
local tinsert = table.insert

-- constants
local BACKPACK_CONTAINER = _G.BACKPACK_CONTAINER
local BANK_CONTAINER = _G.BANK_CONTAINER
local INVSLOT_LAST_EQUIPPED = _G.INVSLOT_LAST_EQUIPPED
local MAX_GUILDBANK_SLOTS_PER_TAB = 98
local REAGENTBANK_CONTAINER = _G.REAGENTBANK_CONTAINER
local VOID_STORAGE_MAX = 80
local VOID_STORAGE_PAGES = 2

local PLAYER_BAGS = {}
do
    for bag = BACKPACK_CONTAINER, NUM_BAG_FRAMES do
        tinsert(PLAYER_BAGS, bag)
    end
end

local BANK_BAGS = {}
do
    tinsert(BANK_BAGS, BANK_CONTAINER)

    for bag = NUM_BAG_SLOTS + 1, NUM_BANKBAGSLOTS do
        tinsert(BANK_BAGS, bag)
    end

    tinsert(BANK_BAGS, REAGENTBANK_CONTAINER)
end

-- helpers
local function debounce(delay, func)
    local calls = 0
    local arg

    local callback = function()
        calls = calls - 1
        if calls == 0 then
            func(arg)
        end
    end

    return function(...)
        calls = calls + 1
        arg = ...
        After(delay, callback)
    end
end

local function isEquippableBag(bagID)
    return bagID > BACKPACK_CONTAINER and bagID <= NUM_BANKBAGSLOTS
end

local function getCompressedInfo(link)
    local result = tonumber(link)

    if not result then
        local linkData = link:match("|H(.-)|h")

        -- grab an itemID from an itemID there's nothing special about this item
        -- that is, all non itemID fields are set to default values
        local itemID = linkData:match("^item:(%d+):::::::([%d%-]*):(%d+):(%d+)(:+)$")
        if itemID then
            result = tonumber(itemID)
        else
            result = linkData
        end
    end

    return result
end

local function saveItemInfo(t, index, itemIDOrLink, itemCount)
    if not itemIDOrLink then
        t[index] = nil
        return
    end

    local item = getCompressedInfo(itemIDOrLink)
    itemCount = tonumber(itemCount) or 0

    if itemCount > 1 then
        t[index] = ("%s;%d"):format(item, itemCount)
    else
        t[index] = item
    end
end

local function getPlayerGuildID(player)
    local name = player and player.name

    if name then
        return ("%s;%s"):format(name, player.realmID)
    end
end

-- events
function Addon:OnInitialize()
    -- setup initial state information
    self.dirtyBags = {}

    for _, bag in pairs(PLAYER_BAGS) do
        self.dirtyBags[bag] = true
    end

    self:LoadDatabase()
end

function Addon:OnEnable()
    self.playerID = UnitGUID("player")
    self.player = self:CreateOrUpdatePlayerInfo()

    self.realmID = (select(2, UnitFullName("player")))
    self.realm = self:CreateOrUpdateRealmInfo()

    self:SaveEquippedItems()
    self:SaveUpdatedBags()

    -- bank
    self:RegisterEvent("BANKFRAME_CLOSED")
    self:RegisterEvent("BANKFRAME_OPENED")
    self:RegisterEvent("PLAYERBANKSLOTS_CHANGED")
    self:RegisterEvent("PLAYERREAGENTBANKSLOTS_CHANGED")

    -- bag
    self:RegisterEvent("BAG_UPDATE")
    self:RegisterEvent("BAG_CLOSED")
    self:RegisterEvent("BAG_UPDATE_DELAYED")

    -- equipment
    self:RegisterEvent("PLAYER_EQUIPMENT_CHANGED")

    -- player
    self:RegisterEvent("GUILD_ROSTER_UPDATE")
    self:RegisterEvent("PLAYER_GUILD_UPDATE")
    self:RegisterEvent("PLAYER_MONEY")

    -- guild bank
    self:RegisterEvent("GUILDBANK_UPDATE_MONEY")
    self:RegisterEvent("GUILDBANK_UPDATE_TABS")
    self:RegisterEvent("GUILDBANKBAGSLOTS_CHANGED")
    self:RegisterEvent("GUILDBANKFRAME_CLOSED")
    self:RegisterEvent("GUILDBANKFRAME_OPENED")

    -- voidstorage
    self:RegisterEvent("VOID_STORAGE_CONTENTS_UPDATE")
    self:RegisterEvent("VOID_STORAGE_OPEN")
    self:RegisterEvent("VOID_STORAGE_CLOSE")
    self:RegisterEvent("VOID_STORAGE_UPDATE")
    self:RegisterEvent("VOID_TRANSFER_DONE")
end

-- bank
function Addon:BANKFRAME_OPENED()
    self.atBank = true

    for _, bag in pairs(BANK_BAGS) do
        self.dirtyBags[bag] = true
    end

    self:SaveUpdatedBags()
end

function Addon:BANKFRAME_CLOSED()
    self.atBank = nil
end

function Addon:PLAYERBANKSLOTS_CHANGED(msg, slot)
    if not self.atBank then
        return
    end

    if slot then
        self:SaveBagItem(BANK_CONTAINER, slot)
    else
        self.dirtyBags[BANK_CONTAINER] = true
        self:SaveUpdatedBags()
    end
end

function Addon:PLAYERREAGENTBANKSLOTS_CHANGED(msg, slot)
    if not self.atBank then
        return
    end

    if slot then
        self:SaveBagItem(REAGENTBANK_CONTAINER, slot)
    else
        self.dirtyBags[REAGENTBANK_CONTAINER] = true
        self:SaveUpdatedBags()
    end
end

-- bags
function Addon:BAG_UPDATE(msg, bag)
    self.dirtyBags[bag] = true
end

function Addon:BAG_CLOSED(msg, bag)
    self:ClearBag(bag)
end

function Addon:BAG_UPDATE_DELAYED()
    self:SaveUpdatedBags()
end

-- player
function Addon:PLAYER_MONEY()
    self:SavePlayerMoney()
end

function Addon:PLAYER_EQUIPMENT_CHANGED(msg, slot)
    self:SaveEquippedItem(slot)
end

function Addon:PLAYER_GUILD_UPDATE()
    self:SavePlayerGuild()

    if self:UpdateGuildID() then
        self.guild = self:CreateOrUpdateGuildInfo()
    end
end

function Addon:GUILD_ROSTER_UPDATE()
    self:SavePlayerGuild()

    if self:UpdateGuildID() then
        self.guild = self:CreateOrUpdateGuildInfo()
    end
end

-- void storage
function Addon:VOID_STORAGE_OPEN()
    self.atVoidStorage = true
    self:SaveVoidStorageItems()
end

function Addon:VOID_STORAGE_CLOSE()
    self.atVoidStorage = nil
end

function Addon:VOID_STORAGE_UPDATE()
    if not self.atVoidStorage then
        return
    end

    self:SaveVoidStorageItems()
end

function Addon:VOID_STORAGE_CONTENTS_UPDATE()
    if not self.atVoidStorage then
        return
    end

    self:SaveVoidStorageItems()
end

function Addon:VOID_TRANSFER_DONE()
    if not self.atVoidStorage then
        return
    end

    self:SaveVoidStorageItems()
end

-- guild bank
function Addon:GUILDBANK_UPDATE_TABS()
    if not self.atGuildBank then
        return
    end

    self:SaveGuildBank()
end

function Addon:GUILDBANKBAGSLOTS_CHANGED()
    if not self.atGuildBank then
        return
    end

    self:SaveGuildBank()
end

function Addon:GUILDBANKFRAME_CLOSED()
    self.atGuildBank = nil
end

function Addon:GUILDBANKFRAME_OPENED()
    self.atGuildBank = true
    self:SaveGuildBank()
end

function Addon:GUILDBANK_UPDATE_MONEY()
    self:SaveGuildBankMoney()
end

-- db
function Addon:LoadDatabase()
    local db = _G[DB_NAME]
    if not db then
        db = {
            settings = {},
            guilds = {},
            players = {},
            realms = {},
            version = DB_VERSION
        }

        _G[DB_NAME] = db
    end

    self:UpgradeDatabase(db)

    self.db = db
end

function Addon:UpgradeDatabase(db)
    if db.version >= DB_VERSION then
        return
    end

    db.version = DB_VERSION
end

-- player data
function Addon:CreateOrUpdatePlayerInfo()
    local playerID = self.playerID
    local _, classId, _, raceId, gender = GetPlayerInfoByGUID(playerID)
    local _, faction = UnitFactionGroup("player")
    local name, realmID = UnitFullName("player")

    local player = self.db.players[playerID]
    if not player then
        player = {
            inventory = {}
        }

        self.db.players[playerID] = player
    end

    player.class = classId
    player.faction = faction
    player.gender = gender
    player.name = name
    player.race = raceId
    player.realmID = realmID
    player.money = GetMoney()

    return player
end

function Addon:SavePlayerMoney()
    self.player.money = GetMoney()
end

function Addon:SavePlayerGuild()
    local player = self.player
    local newGuildName = GetGuildInfo("player")

    if player.guild ~= newGuildName then
        player.guild = newGuildName
        return true
    end

    return false
end

-- guild data
function Addon:UpdateGuildID()
    local guildID = getPlayerGuildID(self.player)

    if self.guildID ~= guildID then
        self.guildID = guildID
    end

    return guildID
end

function Addon:CreateOrUpdateGuildInfo()
    local guildID = self.guildID
    if not guildID then
        self.guild = nil
        return
    end

    local guild = self.db.guilds[guildID]
    if not guild then
        guild = {
            name = self.player.guild,
            realmID = self.player.realmID,
            money = GetGuildBankMoney() or 0,
            inventory = {}
        }

        self.db.guilds[guildID] = guild
    end

    return guild
end

-- equipment
local GetInventoryItemLink = _G.GetInventoryItemLink
local GetInventoryItemCount = _G.GetInventoryItemCount

function Addon:SaveEquippedItems()
    for slot = 1, INVSLOT_LAST_EQUIPPED do
        self:SaveEquippedItem(slot)
    end
end

function Addon:SaveEquippedItem(slot)
    local equipped = self.player.inventory.equipped
    if not equipped then
        equipped = {}
        self.player.inventory.equipped = equipped
    end

    local itemLink = GetInventoryItemLink("player", slot)
    local itemCount = GetInventoryItemCount("player", slot)

    saveItemInfo(equipped, slot, itemLink, itemCount)
end

-- bags
Addon.SaveUpdatedBags = debounce(0.25, function(self)
    for bag in pairs(self.dirtyBags) do
        self:SaveBag(bag)
        self.dirtyBags[bag] = nil
    end
end)

function Addon:SaveBag(bagID)
    local bag = self:GetOrCreateBagInfo(bagID)
    local oldSize = bag.size or 0
    local newSize = GetContainerNumSlots(bagID) or 0

    if isEquippableBag(bagID) then
        self:SaveEquippedItem(ContainerIDToInventoryID(bagID))
    end

    bag.size = newSize

    for slotID = 1, newSize do
        self:SaveBagItem(bagID, slotID)
    end

    for slotID = newSize + 1, oldSize do
        bag[slotID] = nil
    end
end

function Addon:ClearBag(bagID)
    self.db.player.inventory[bagID] = nil
end

function Addon:SaveBagItem(bagID, slot)
    local bag = self:GetOrCreateBagInfo(bagID)
    local _, itemCount, _, _, _, _, itemLink, _, _, itemID = GetContainerItemInfo(bagID, slot)

    saveItemInfo(bag, slot, itemLink or itemID, itemCount)
end

function Addon:GetOrCreateBagInfo(bagID)
    local bag = self.player.inventory[bagID]

    if not bag then
        bag = {}
        self.player.inventory[bagID] = bag
    end

    return bag
end

-- void storage
local GetVoidItemInfo = _G.GetVoidItemInfo

Addon.SaveVoidStorageItems = debounce(0.25,
    function(self)
        for page = 1, VOID_STORAGE_PAGES do
            for slot = 1, VOID_STORAGE_MAX do
                self:SaveVoidStorageItem(page, slot)
            end
        end
    end
)

function Addon:SaveVoidStorageItem(page, slot)
    local voidStorage = self.player.inventory.voidStorage
    if not voidStorage then
        voidStorage = {}
        self.player.inventory.voidStorage = voidStorage
    end

    local index = (page - 1) * VOID_STORAGE_PAGES + slot
    local itemID = (GetVoidItemInfo(page, slot))

    saveItemInfo(voidStorage, index, itemID)
end

-- guild bank
local GetCurrentGuildBankTab = _G.GetCurrentGuildBankTab
local GetGuildBankItemInfo = _G.GetGuildBankItemInfo
local GetGuildBankItemLink = _G.GetGuildBankItemLink
local GetGuildBankMoney = _G.GetGuildBankMoney
local GetGuildBankTabInfo = _G.GetGuildBankTabInfo
local GetNumGuildBankTabs = _G.GetNumGuildBankTabs

local function getGuildBankItemInfo(tab, slot)
    local itemLink = GetGuildBankItemLink(tab, slot)

    if itemLink then
        local _, count = GetGuildBankItemInfo(tab, slot)
        return itemLink, count
    end
end

Addon.SaveGuildBank = debounce(0.25,
    function(self)
        if not self.guild then
            return
        end

        for tab = 1, GetNumGuildBankTabs() do
            self:SaveGuildBankTab(tab)
        end
    end
)

function Addon:SaveCurrentGuildBankTab()
    local id = GetCurrentGuildBankTab()
    if id then
        self:SaveGuildBankTab(id)
    end
end

function Addon:SaveGuildBankTab(id)
    if not self.guild then
        return
    end

    local tab = self:CreateOrUpdateGuildTab(id)
    if not tab then
        return
    end

    for slot = 1, MAX_GUILDBANK_SLOTS_PER_TAB do
        saveItemInfo(tab, slot, getGuildBankItemInfo(id, slot))
    end
end

function Addon:CreateOrUpdateGuildTab(tabID)
    local name, icon, isViewable = GetGuildBankTabInfo(tabID)
    local tab = nil

    if isViewable then
        tab = self.guild.inventory[tabID]
        if not tab then
            tab = { }
            self.guild.inventory[tabID] = tab
        end

        tab.name = name
        tab.icon = icon
        tab.size = MAX_GUILDBANK_SLOTS_PER_TAB
    else
        self.guild.inventory[tabID] = nil
    end

    return tab
end

function Addon:SaveGuildBankTabItem(id, slot)
    if not self.guild then
        return
    end

    local tab = self.guild.inventory[id]
    if not tab then
        return
    end

    saveItemInfo(tab, slot, getGuildBankItemInfo(id, slot))
end

function Addon:SaveGuildBankMoney()
    if not self.guild then
        return
    end

    self.guild.money = GetGuildBankMoney() or 0
end

function Addon:GetOrCreateGuildInfo()
    local guildID = getPlayerGuildID(self.player)
    if not guildID then
        return
    end

    local guild = self.db.guilds[guildID]

    if not guild then
        guild = {
            name = self.player.guild,
            realmID = self.realmID,
            money = GetGuildBankMoney() or 0,
            inventory = {}
        }

        self.db.guilds[guildID] = guild
    end

    return guild
end

-- realms
function Addon:CreateOrUpdateRealmInfo()
    local realms = self.db.realms
    if not realms then
        realms = {}
        self.db.realms = realms
    end

    local realmID = self.realmID
    local realm = realms[realmID]
    if not realm then
        realm = { id = realmID }
        realms[realmID] = realm
    end

    realm.name = GetRealmName()

    local links
    local connectedRealms = GetAutoCompleteRealms()
    if connectedRealms then
        for _, connectedRealmID in pairs(connectedRealms) do
            if connectedRealmID ~= realmID then
                links = links or {}
                links[connectedRealmID] = true
            end
        end
    end

    realm.links = links

    self.realm = realm
    return realm
end