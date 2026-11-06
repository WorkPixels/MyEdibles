-- Compat.lua -- API compatibility layer so MyEdibles runs on Classic Era, TBC and Wrath clients.
local ADDON, NS = ...
local C = {}
NS.C = C

-- ---------------------------------------------------------------------------
-- Container API: newer clients expose C_Container.*; older expose globals.
-- ---------------------------------------------------------------------------
local CC = _G.C_Container

function C.NumSlots(bag)
    if CC and CC.GetContainerNumSlots then return CC.GetContainerNumSlots(bag) or 0 end
    return _G.GetContainerNumSlots(bag) or 0
end

-- Returns a normalized table or nil for an empty slot:
--   { icon, count, locked, quality, readable, lootable, link, filtered, noValue, itemID }
function C.ItemInfo(bag, slot)
    if CC and CC.GetContainerItemInfo then
        local t = CC.GetContainerItemInfo(bag, slot)
        if not t then return nil end
        return {
            icon     = t.iconFileID,
            count    = t.stackCount,
            locked   = t.isLocked,
            quality  = t.quality,
            readable = t.isReadable,
            lootable = t.hasLoot,
            link     = t.hyperlink,
            filtered = t.isFiltered,
            noValue  = t.hasNoValue,
            itemID   = t.itemID,
        }
    end
    local icon, count, locked, quality, readable, lootable, link, filtered, noValue, itemID = _G.GetContainerItemInfo(bag, slot)
    if not icon and not itemID then return nil end
    return {
        icon = icon, count = count, locked = locked, quality = quality,
        readable = readable, lootable = lootable, link = link,
        filtered = filtered, noValue = noValue, itemID = itemID,
    }
end

function C.ItemLink(bag, slot)
    if CC and CC.GetContainerItemLink then return CC.GetContainerItemLink(bag, slot) end
    return _G.GetContainerItemLink(bag, slot)
end

function C.ItemCooldown(bag, slot)
    if CC and CC.GetContainerItemCooldown then return CC.GetContainerItemCooldown(bag, slot) end
    return _G.GetContainerItemCooldown(bag, slot)
end

-- ---------------------------------------------------------------------------
-- Item API: newer clients expose C_Item.*; older expose globals.
-- ---------------------------------------------------------------------------
local CI = _G.C_Item

function C.GetItemInfo(item)
    if CI and CI.GetItemInfo then return CI.GetItemInfo(item) end
    if _G.GetItemInfo then return _G.GetItemInfo(item) end
    return nil
end

function C.GetItemCooldown(itemID)
    if CI and CI.GetItemCooldown then return CI.GetItemCooldown(itemID) end
    if CC and CC.GetItemCooldown then return CC.GetItemCooldown(itemID) end
    if _G.GetItemCooldown then return _G.GetItemCooldown(itemID) end
    return 0, 0, 0
end

if not _G.GetItemInfo and CI and CI.GetItemInfo then
    _G.GetItemInfo = CI.GetItemInfo
end

function C.UseItem(bag, slot)
    if CC and CC.UseContainerItem then return CC.UseContainerItem(bag, slot) end
    return _G.UseContainerItem(bag, slot)
end

C.BACKPACK_BAGS = { 0, 1, 2, 3, 4 }

return C
