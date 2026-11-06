-- MyEdibles.lua -- Core addon logic, secure action buttons, bag scanning, and events.
local ADDON, NS = ...
local C = NS.C -- Compat layer
local GetItemInfo = C.GetItemInfo

local frame = CreateFrame("Frame", "MyEdiblesFrame")
frame:RegisterEvent("ADDON_LOADED")
frame:RegisterEvent("PLAYER_LOGIN")
frame:RegisterEvent("PLAYER_LOGOUT")
frame:RegisterEvent("BAG_UPDATE_DELAYED")
frame:RegisterEvent("PLAYER_REGEN_ENABLED")
frame:RegisterEvent("GET_ITEM_INFO_RECEIVED")

NS.frame = frame
NS.updateNeeded = false
NS.ediblesDrinkButtons = {}

-- ---------------------------------------------------------------------------
-- Bar Registry
-- ---------------------------------------------------------------------------
-- Each bar has: key, label, anchorName, buttonPrefix, defaults, matchFn, filterOpts
-- matchFn(detail) -> true if the item naturally belongs on this bar
-- filterOpts = { {key, label}, ... } for the bar-specific filter radio buttons

NS.barDefs = {
    {
        key = "edibles",
        label = "MyEdibles",
        anchorName = "MyEdiblesAnchor",
        buttonPrefix = "MyEdiblesButton",
        defaults = {
            enabled = true,
            maxItems = 5,
            buttonSize = 32,
            buttonSpacing = 4,
            orientation = "Horizontal",
            locked = false,
            scale = 1.0,
            whitelist = {},
            blacklist = {},
            point = "BOTTOM",
            relativePoint = "BOTTOM",
            xOfs = 100,
            yOfs = 150,
            filterType = "All",
            hideWhenEmpty = true,
        },
        filterOpts = {
            { key = "All",    label = "Show All Food & Drink" },
            { key = "Health", label = "Health Food Only" },
            { key = "Mana",   label = "Mana Drinks Only" },
        },
    },
    {
        key = "potions",
        label = "MyPotions",
        anchorName = "MyPotionsAnchor",
        buttonPrefix = "MyPotionsButton",
        defaults = {
            enabled = true,
            maxItems = 5,
            buttonSize = 32,
            buttonSpacing = 4,
            orientation = "Horizontal",
            locked = false,
            scale = 1.0,
            whitelist = {},
            blacklist = {},
            point = "BOTTOM",
            relativePoint = "BOTTOM",
            xOfs = 100,
            yOfs = 150,
            filterType = "All",
            hideWhenEmpty = true,
        },
        filterOpts = {
            { key = "All",     label = "Show All Consumables" },
            { key = "Potions", label = "Potions Only" },
            { key = "Elixirs", label = "Elixirs & Flasks Only" },
        },
    },
    {
        key = "bandaids",
        label = "MyBandAids",
        anchorName = "MyBandAidsAnchor",
        buttonPrefix = "MyBandAidsButton",
        defaults = {
            enabled = true,
            maxItems = 5,
            buttonSize = 32,
            buttonSpacing = 4,
            orientation = "Horizontal",
            locked = false,
            scale = 1.0,
            whitelist = {},
            blacklist = {},
            point = "BOTTOM",
            relativePoint = "BOTTOM",
            xOfs = 100,
            yOfs = 150,
            filterType = "All",
            hideWhenEmpty = true,
        },
        filterOpts = {
            { key = "All", label = "Show All Bandages" },
        },
    },
    {
        key = "bombs",
        label = "MyBombs",
        anchorName = "MyBombsAnchor",
        buttonPrefix = "MyBombsButton",
        defaults = {
            enabled = true,
            maxItems = 5,
            buttonSize = 32,
            buttonSpacing = 4,
            orientation = "Horizontal",
            locked = false,
            scale = 1.0,
            whitelist = {},
            blacklist = {},
            point = "BOTTOM",
            relativePoint = "BOTTOM",
            xOfs = 100,
            yOfs = 150,
            filterType = "All",
            hideWhenEmpty = true,
        },
        filterOpts = {
            { key = "All", label = "Show All Bombs" },
        },
    },
    {
        key = "stones",
        label = "MyStones",
        anchorName = "MyStonesAnchor",
        buttonPrefix = "MyStonesButton",
        defaults = {
            enabled = true,
            maxItems = 5,
            buttonSize = 32,
            buttonSpacing = 4,
            orientation = "Horizontal",
            locked = false,
            scale = 1.0,
            whitelist = {},
            blacklist = {},
            point = "BOTTOM",
            relativePoint = "BOTTOM",
            xOfs = 100,
            yOfs = 150,
            filterType = "All",
            hideWhenEmpty = true,
        },
        filterOpts = {
            { key = "All", label = "Show All Stones" },
        },
    },
    {
        key = "camping",
        label = "MyCamping",
        anchorName = "MyCampingAnchor",
        buttonPrefix = "MyCampingButton",
        defaults = {
            enabled = true,
            maxItems = 5,
            buttonSize = 32,
            buttonSpacing = 4,
            orientation = "Horizontal",
            locked = false,
            scale = 1.0,
            whitelist = {},
            blacklist = {},
            point = "BOTTOM",
            relativePoint = "BOTTOM",
            xOfs = 100,
            yOfs = 150,
            filterType = "All",
            hideWhenEmpty = true,
        },
        filterOpts = {
            { key = "All",     label = "Show All Camp Items" },
            { key = "Fires",   label = "Campfire Kits Only" },
            { key = "Objects", label = "Camp Objects Only" },
        },
    },
}

-- Runtime state per bar: anchors, buttons, activeItems
NS.bars = {} -- keyed by barDef.key

-- ---------------------------------------------------------------------------
-- ---------------------------------------------------------------------------
-- DB Initialization & Migration
-- ---------------------------------------------------------------------------
local function deepCopy(orig)
    if type(orig) ~= "table" then return orig end
    local copy = {}
    for k, v in pairs(orig) do
        copy[k] = type(v) == "table" and deepCopy(v) or v
    end
    return copy
end
NS.deepCopy = deepCopy

local function InitializeDB()
    MyEdiblesDB = MyEdiblesDB or {}
    
    -- Migration: if old flat structure exists, move it to MyEdiblesDB.edibles
    if MyEdiblesDB.maxItems ~= nil then
        local oldConfig = {}
        local ediDef = NS.barDefs[1]
        for k, v in pairs(ediDef.defaults) do
            if MyEdiblesDB[k] ~= nil then
                oldConfig[k] = MyEdiblesDB[k]
                MyEdiblesDB[k] = nil
            else
                oldConfig[k] = v
            end
        end
        MyEdiblesDB.edibles = oldConfig
    end

    -- Initialize all bar configs from defaults in account-wide MyEdiblesDB
    for _, def in ipairs(NS.barDefs) do
        if not MyEdiblesDB[def.key] then MyEdiblesDB[def.key] = {} end
        for k, v in pairs(def.defaults) do
            if MyEdiblesDB[def.key][k] == nil then
                MyEdiblesDB[def.key][k] = type(v) == "table" and deepCopy(v) or v
            end
        end

        -- Safety for tables
        if not MyEdiblesDB[def.key].whitelist then MyEdiblesDB[def.key].whitelist = {} end
        if not MyEdiblesDB[def.key].blacklist then MyEdiblesDB[def.key].blacklist = {} end
    end

    NS.db = MyEdiblesDB
end

-- ---------------------------------------------------------------------------
-- Save Positioning
-- ---------------------------------------------------------------------------
local function SavePosition(barKey)
    if InCombatLockdown() then return end
    local barState = NS.bars[barKey]
    if not barState or not barState.anchor then return end
    local anchor = barState.anchor
    local point, relativeTo, relativePoint, xOfs, yOfs = anchor:GetPoint(1)
    if point and xOfs and yOfs then
        local db = NS.db[barKey]
        db.point = point
        db.relativePoint = relativePoint or point
        db.xOfs = xOfs
        db.yOfs = yOfs
        
        anchor:ClearAllPoints()
        anchor:SetPoint(db.point, UIParent, db.relativePoint, db.xOfs, db.yOfs)
    end
end

-- ---------------------------------------------------------------------------
-- Bag Scanning
-- ---------------------------------------------------------------------------
local function ScanBags()
    local counts = {}
    local itemDetails = {}
    local neededItemInfos = false

    for _, bag in ipairs(C.BACKPACK_BAGS) do
        local slots = C.NumSlots(bag)
        for slot = 1, slots do
            local info = C.ItemInfo(bag, slot)
            if info and info.itemID then
                local id = info.itemID
                counts[id] = (counts[id] or 0) + info.count

                if not itemDetails[id] then
                    local name, link, quality, iLevel, reqLevel, class, subclass, maxStack, slotName, texture, vendorPrice, classID, subclassID = GetItemInfo(id)
                    if name then
                        local isFoodAndDrink = false
                        local isPotion = false
                        local isElixir = false
                        local isFlask = false
                        local isBandage = false
                        
                        if classID and subclassID then
                            isFoodAndDrink = (classID == 0 and subclassID == 5)
                            isPotion = (classID == 0 and subclassID == 1)
                            isElixir = (classID == 0 and subclassID == 2)
                            isFlask = (classID == 0 and subclassID == 3)
                            isBandage = (classID == 0 and subclassID == 7)
                        else
                            isFoodAndDrink = (class == "Consumable" and subclass == "Food & Drink")
                            isPotion = (class == "Consumable" and subclass == "Potion")
                            isElixir = (class == "Consumable" and subclass == "Elixir")
                            isFlask = (class == "Consumable" and subclass == "Flask")
                            isBandage = (class == "Consumable" and subclass == "Bandage")
                        end

                        local isHealthstone = false
                        local lowerName = string.lower(name)
                        if string.find(lowerName, "healthstone") or 
                           string.find(lowerName, "gesundheitsstein") or 
                           string.find(lowerName, "pierre de soin") or 
                           string.find(lowerName, "piedra de salud") or 
                           string.find(lowerName, "pietra della salute") or
                           string.find(lowerName, "pedra de saude") or
                           string.find(lowerName, "pedra de saúde") then
                            isHealthstone = true
                        end

                        -- Name-based fallback checks (robust for localization & API quirks)
                        if not isPotion and (string.find(lowerName, "potion") or string.find(lowerName, "trank") or string.find(lowerName, "poción") or string.find(lowerName, "pozione") or string.find(lowerName, "potion")) then
                            isPotion = true
                        end
                        if not isElixir and (string.find(lowerName, "elixir") or string.find(lowerName, "elixier") or string.find(lowerName, "élixir") or string.find(lowerName, "elíxir")) then
                            isElixir = true
                        end
                        if not isFlask and (string.find(lowerName, "flask") or string.find(lowerName, "fläschchen") or string.find(lowerName, "flacon") or string.find(lowerName, "frasco")) then
                            isFlask = true
                        end
                        if not isBandage and (string.find(lowerName, "bandage") or string.find(lowerName, "verband") or string.find(lowerName, "venda") or string.find(lowerName, "benda")) then
                            isBandage = true
                        end

                        local isBomb = false
                        if name then
                            local lowerName = string.lower(name)
                            if string.find(lowerName, "bomb") or 
                               string.find(lowerName, "bombe") or
                               string.find(lowerName, "bomba") or
                               string.find(lowerName, "grenade") or 
                               string.find(lowerName, "granate") or 
                               string.find(lowerName, "granada") or
                               string.find(lowerName, "granata") or
                               string.find(lowerName, "dynamite") or 
                               string.find(lowerName, "dynamit") or 
                               string.find(lowerName, "dinamita") or
                               string.find(lowerName, "dinamite") or
                               string.find(lowerName, "sapper charge") or 
                               string.find(lowerName, "sapeur") or 
                               string.find(lowerName, "zapador") or
                               string.find(lowerName, "sapador") or
                               string.find(lowerName, "explosive sheep") or
                               string.find(lowerName, "explosivschaf") or
                               string.find(lowerName, "mouton explosif") or
                               string.find(lowerName, "oveja explosiva") then
                                isBomb = true
                            end
                        end

                        local isStone = false
                        if name then
                            local lowerName = string.lower(name)
                            if string.find(lowerName, "sharpening stone") or 
                               string.find(lowerName, "wetzstein") or 
                               string.find(lowerName, "schleifstein") or 
                               string.find(lowerName, "pierre à aiguiser") or 
                               string.find(lowerName, "pierre de lest") or 
                               string.find(lowerName, "piedra de afilar") or 
                               string.find(lowerName, "pietra per affilare") or 
                               string.find(lowerName, "pedra de afiar") or 
                               string.find(lowerName, "weight stone") or 
                               string.find(lowerName, "weightstone") or 
                               string.find(lowerName, "gewichtstein") or 
                               string.find(lowerName, "piedra de peso") or 
                               string.find(lowerName, "pietra da peso") or 
                               string.find(lowerName, "pedra de peso") then
                                isStone = true
                            end
                        end

                        local isCampfire = false
                        local isCampItem = false
                        if name then
                            local lowerName = string.lower(name)
                            if string.find(lowerName, "campfire") or 
                               string.find(lowerName, "camp fire") or 
                               string.find(lowerName, "feuerstelle") or 
                               string.find(lowerName, "feu de camp") or 
                               string.find(lowerName, "hoguera") then
                                isCampfire = true
                            end

                            if string.find(lowerName, "camp chair") or 
                               string.find(lowerName, "camp tent") or 
                               string.find(lowerName, "camping") or 
                               string.find(lowerName, "campsite") or 
                               string.find(lowerName, "sharpening wheel") or 
                               string.find(lowerName, "mana well") or 
                               string.find(lowerName, "enchanted lute") or 
                               string.find(lowerName, "enchanter's crystal") or 
                               string.find(lowerName, "leyline conduit") or 
                               string.find(lowerName, "field first aid kit") or 
                               string.find(lowerName, "triage station") or 
                               string.find(lowerName, "emergency cot") or 
                               string.find(lowerName, "trauma center") or 
                               string.find(lowerName, "fish bowl") or 
                               string.find(lowerName, "tackle box bench") or 
                               string.find(lowerName, "fisherman's wharf") or 
                               string.find(lowerName, "incense candle") or 
                               string.find(lowerName, "sprout box") or 
                               string.find(lowerName, "seed hybridizer") or 
                               string.find(lowerName, "arborist's conservatory") or 
                               string.find(lowerName, "tannin basin") or 
                               string.find(lowerName, "curing rack") or 
                               string.find(lowerName, "master tanner") or 
                               string.find(lowerName, "mining lodestone") or 
                               string.find(lowerName, "lodestone") or 
                               string.find(lowerName, "smelter's hearth") or 
                               string.find(lowerName, "core drill") or 
                               string.find(lowerName, "skinning post") or 
                               string.find(lowerName, "drying frame") or 
                               string.find(lowerName, "trophies of the hunt") or 
                               string.find(lowerName, "faction banner") or 
                               string.find(lowerName, "camp banner") or 
                               string.find(lowerName, "scarlet banner") or 
                               string.find(lowerName, "reagent bot") or 
                               string.find(lowerName, "tinker's workbench") or 
                               string.find(lowerName, "repair station") or 
                               string.find(lowerName, "demolition platform") or 
                               string.find(lowerName, "fermenter") or 
                               string.find(lowerName, "campfire anvil") or 
                               string.find(lowerName, "master forge") then
                                isCampItem = true
                            end
                        end
                        local isCamping = isCampfire or isCampItem

                        itemDetails[id] = {
                            id = id,
                            name = name,
                            link = info.link or link,
                            quality = quality,
                            minLevel = reqLevel or 0,
                            isFoodAndDrink = isFoodAndDrink,
                            isPotion = isPotion,
                            isElixir = isElixir,
                            isFlask = isFlask,
                            isBandage = isBandage,
                            isHealthstone = isHealthstone,
                            isBomb = isBomb,
                            isStone = isStone,
                            isCamping = isCamping,
                            isCampfire = isCampfire,
                            isCampItem = isCampItem,
                            icon = texture or info.icon,
                        }
                    else
                        neededItemInfos = true
                        if C_Item and C_Item.RequestLoadItemDataByID then
                            C_Item.RequestLoadItemDataByID(id)
                        end
                    end
                end
            end
        end
    end
    return counts, itemDetails, neededItemInfos
end

-- ---------------------------------------------------------------------------
-- Tooltip Scanner for Food Subtype (Health vs Mana)
-- ---------------------------------------------------------------------------
local scanner
local function CreateScanner()
    if scanner then return end
    scanner = CreateFrame("GameTooltip", "MyEdiblesScannerTooltip", nil, "GameTooltipTemplate")
    scanner:SetOwner(WorldFrame, "ANCHOR_NONE")
end

local function GetEdibleType(itemLink)
    if not itemLink then return "Health" end
    CreateScanner()
    scanner:ClearLines()
    scanner:SetHyperlink(itemLink)

    local hasHealth = false
    local hasMana = false

    for i = 1, scanner:NumLines() do
        local line = _G["MyEdiblesScannerTooltipTextLeft" .. i]
        local text = line and line:GetText()
        if text then
            text = string.lower(text)
            if string.find(text, "health") or string.find(text, "gesundheit") or string.find(text, "points de vie") or string.find(text, "salud") or string.find(text, "vida") then
                hasHealth = true
            end
            if string.find(text, "mana") or string.find(text, "maná") then
                hasMana = true
            end
        end
    end

    if hasHealth and hasMana then
        return "Both"
    elseif hasHealth then
        return "Health"
    elseif hasMana then
        return "Mana"
    end
    return "Health"
end

-- ---------------------------------------------------------------------------
-- Item matching helpers per bar type
-- ---------------------------------------------------------------------------
local function MatchesBar(barKey, detail)
    if barKey == "edibles" then
        return detail.isFoodAndDrink
    elseif barKey == "potions" then
        return detail.isPotion or detail.isElixir or detail.isFlask or detail.isHealthstone
    elseif barKey == "bandaids" then
        return detail.isBandage
    elseif barKey == "bombs" then
        return detail.isBomb
    elseif barKey == "stones" then
        return detail.isStone
    elseif barKey == "camping" then
        return detail.isCamping
    end
    return false
end

local function PassesFilter(barKey, filterType, detail)
    if filterType == "All" then return true end
    
    if barKey == "edibles" then
        local foodType = GetEdibleType(detail.link)
        if filterType == "Health" and foodType == "Mana" then return false end
        if filterType == "Mana" and foodType == "Health" then return false end
    elseif barKey == "potions" then
        if filterType == "Potions" and not (detail.isPotion or detail.isHealthstone) then return false end
        if filterType == "Elixirs" and not (detail.isElixir or detail.isFlask) then return false end
    elseif barKey == "camping" then
        if filterType == "Fires" and not detail.isCampfire then return false end
        if filterType == "Objects" and not detail.isCampItem then return false end
    end
    -- bandaids and stones only have "All" filter, always pass
    return true
end

-- ---------------------------------------------------------------------------
-- Bar Layout and Updates
-- ---------------------------------------------------------------------------
function NS.UpdateBarVisuals()
    local counts = {}
    for _, bag in ipairs(C.BACKPACK_BAGS) do
        local slots = C.NumSlots(bag)
        for slot = 1, slots do
            local info = C.ItemInfo(bag, slot)
            if info and info.itemID then
                counts[info.itemID] = (counts[info.itemID] or 0) + info.count
            end
        end
    end

    local function updateList(buttons)
        for i = 1, #buttons do
            local btn = buttons[i]
            if btn:IsShown() and btn.itemID then
                local count = counts[btn.itemID] or 0
                if count == 0 then
                    btn.icon:SetDesaturated(true)
                    btn.icon:SetVertexColor(0.4, 0.4, 0.4)
                    btn.count:SetText("0")
                    if btn.cooldown then btn.cooldown:Hide() end
                else
                    btn.icon:SetDesaturated(false)
                    btn.icon:SetVertexColor(1, 1, 1)
                    btn.count:SetText(count > 1 and tostring(count) or "")
                    
                    local start, duration, enable = C.GetItemCooldown(btn.itemID)
                    if start and duration and duration > 0 then
                        CooldownFrame_Set(btn.cooldown, start, duration, enable)
                    else
                        btn.cooldown:Hide()
                    end
                end
            end
        end
    end

    for _, def in ipairs(NS.barDefs) do
        local barState = NS.bars[def.key]
        if barState and barState.buttons then
            updateList(barState.buttons)
        end
    end
    updateList(NS.ediblesDrinkButtons)
end

local function CreateActionButton(btnName, parent)
    local btn = CreateFrame("Button", btnName, parent, "SecureActionButtonTemplate")
    btn:SetFrameStrata("HIGH")
    btn:RegisterForClicks("AnyUp", "AnyDown")
    btn:SetAttribute("useOnKeyDown", false)
    
    local icon = btn:CreateTexture(nil, "BACKGROUND")
    icon:SetAllPoints(btn)
    icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    btn.icon = icon

    local count = btn:CreateFontString(nil, "OVERLAY", "NumberFontNormal")
    count:SetPoint("BOTTOMRIGHT", btn, "BOTTOMRIGHT", -2, 2)
    btn.count = count

    local cd = CreateFrame("Cooldown", btnName.."CD", btn, "CooldownFrameTemplate")
    cd:SetAllPoints(btn)
    btn.cooldown = cd

    local highlight = btn:CreateTexture(nil, "HIGHLIGHT")
    highlight:SetTexture("Interface\\Buttons\\ButtonHilight-Square")
    highlight:SetAllPoints(btn)
    btn:SetHighlightTexture(highlight)

    local pushed = btn:CreateTexture(nil, "ARTWORK")
    pushed:SetTexture("Interface\\Buttons\\UI-Quickslot-Depress")
    pushed:SetAllPoints(btn)
    btn:SetPushedTexture(pushed)

    local normal = btn:CreateTexture(nil, "BORDER")
    normal:SetTexture("Interface\\Buttons\\UI-Quickslot2")
    normal:SetAllPoints(btn)
    btn.normal = normal

    btn:SetScript("OnEnter", function(self)
        if self.itemLink then
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:SetHyperlink(self.itemLink)
            GameTooltip:Show()
        end
    end)
    btn:SetScript("OnLeave", function(self)
        GameTooltip:Hide()
    end)

    return btn
end

function NS.UpdateSingleBar(barKey)
    if InCombatLockdown() then
        NS.updateNeeded = true
        return
    end

    local barState = NS.bars[barKey]
    if not barState or not barState.anchor then return end

    local db = NS.db[barKey]
    local anchor = barState.anchor
    local buttons = barState.buttons
    local def = barState.def

    -- Handle Enabled/Disabled state
    if not db.enabled then
        anchor:Hide()
        return
    end

    -- Update Anchor Lock Visuals
    if db.locked then
        anchor:EnableMouse(false)
        anchor.bg:Hide()
        anchor.title:Hide()
    else
        anchor:EnableMouse(true)
        anchor.bg:Show()
        anchor.title:Show()
    end
    anchor:SetScale(db.scale or 1.0)

    -- Scan Bags
    local counts, itemDetails, neededItemInfos = ScanBags()
    
    -- Filter and collect matching items
    local list = {}
    local playerLevel = UnitLevel("player") or 1

    for id, count in pairs(counts) do
        local detail = itemDetails[id]
        if detail then
            local isWhitelisted = db.whitelist[id]
            local isBlacklisted = db.blacklist[id]

            if not isBlacklisted then
                local passFilter = true
                local filter = db.filterType or "All"
                
                if filter ~= "All" and not isWhitelisted then
                    passFilter = PassesFilter(barKey, filter, detail)
                end

                local naturalMatch = MatchesBar(barKey, detail)
                if passFilter and (isWhitelisted or (naturalMatch and detail.minLevel <= playerLevel)) then
                    table.insert(list, {
                        id = id,
                        name = detail.name,
                        link = detail.link,
                        minLevel = detail.minLevel,
                        count = count,
                        icon = detail.icon,
                    })
                end
            end
        end
    end

    -- Sort items
    table.sort(list, function(a, b)
        local a_wl = db.whitelist[a.id] and 1 or 0
        local b_wl = db.whitelist[b.id] and 1 or 0
        if a_wl ~= b_wl then return a_wl > b_wl end
        if a.minLevel ~= b.minLevel then return a.minLevel > b.minLevel end
        if a.count ~= b.count then return a.count > b.count end
        return a.name < b.name
    end)

    barState.activeItems = list

    local maxToShow = db.maxItems or 5
    local size = db.buttonSize or 36
    local spacing = db.buttonSpacing or 4
    local orientation = db.orientation or "Horizontal"
    local handleSize = db.locked and 0 or 16

    -- Determine split food & drink layouts
    local numActiveFood = 0
    local numActiveDrink = 0
    local hasTwoRows = false

    local foodList = {}
    local drinkList = {}

    if barKey == "edibles" and db.filterType == "All" then
        for _, item in ipairs(list) do
            local foodType = GetEdibleType(item.link)
            if foodType == "Health" then
                table.insert(foodList, item)
            elseif foodType == "Mana" then
                table.insert(drinkList, item)
            elseif foodType == "Both" then
                table.insert(foodList, item)
                table.insert(drinkList, item)
            end
        end
        numActiveFood = math.min(#foodList, maxToShow)
        numActiveDrink = math.min(#drinkList, maxToShow)
        if numActiveFood > 0 and numActiveDrink > 0 then
            hasTwoRows = true
        end
    end

    if not hasTwoRows then
        foodList = list
        numActiveFood = math.min(#list, maxToShow)
        drinkList = {}
        numActiveDrink = 0
    end

    -- 1. Setup Food (or Single List) buttons
    for i = 1, maxToShow do
        if not buttons[i] then
            buttons[i] = CreateActionButton(def.buttonPrefix .. i, anchor)
        end
    end

    for i = 1, #buttons do
        local btn = buttons[i]
        if i <= numActiveFood then
            local data = foodList[i]
            btn.itemID = data.id
            btn.itemLink = data.link

            btn:SetAttribute("type", "macro")
            btn:SetAttribute("macrotext", "/use item:" .. data.id)

            btn.icon:SetTexture(data.icon)
            btn.icon:SetDesaturated(false)
            btn.icon:SetVertexColor(1, 1, 1)
            btn.count:SetText(data.count > 1 and tostring(data.count) or "")

            btn:ClearAllPoints()
            local offset = (i - 1) * (size + spacing) + handleSize
            if orientation == "Horizontal" then
                btn:SetPoint("TOPLEFT", anchor, "TOPLEFT", offset + 2, -2)
            else
                btn:SetPoint("TOPLEFT", anchor, "TOPLEFT", 2, -offset - 2)
            end
            btn:SetSize(size, size)
            
            local pad = size * (14 / 36)
            btn.normal:ClearAllPoints()
            btn.normal:SetPoint("TOPLEFT", btn, "TOPLEFT", -pad, pad)
            btn.normal:SetPoint("BOTTOMRIGHT", btn, "BOTTOMRIGHT", pad, -pad)
            
            btn:Show()
        else
            btn.itemID = nil
            btn.itemLink = nil
            btn:SetAttribute("type", nil)
            btn:SetAttribute("macrotext", nil)
            btn:Hide()
        end
    end

    -- 2. Setup Drink buttons (only if barKey is edibles)
    local drinkButtons = NS.ediblesDrinkButtons
    if barKey == "edibles" then
        for i = 1, maxToShow do
            if not drinkButtons[i] then
                drinkButtons[i] = CreateActionButton("MyEdiblesDrinkButton" .. i, anchor)
            end
        end

        for i = 1, #drinkButtons do
            local btn = drinkButtons[i]
            if hasTwoRows and i <= numActiveDrink then
                local data = drinkList[i]
                btn.itemID = data.id
                btn.itemLink = data.link

                btn:SetAttribute("type", "macro")
                btn:SetAttribute("macrotext", "/use item:" .. data.id)

                btn.icon:SetTexture(data.icon)
                btn.icon:SetDesaturated(false)
                btn.icon:SetVertexColor(1, 1, 1)
                btn.count:SetText(data.count > 1 and tostring(data.count) or "")

                btn:ClearAllPoints()
                local offset = (i - 1) * (size + spacing) + handleSize
                if orientation == "Horizontal" then
                    btn:SetPoint("TOPLEFT", anchor, "TOPLEFT", offset + 2, -2 - size - spacing)
                else
                    btn:SetPoint("TOPLEFT", anchor, "TOPLEFT", 2 + size + spacing, -offset - 2)
                end
                btn:SetSize(size, size)
                
                local pad = size * (14 / 36)
                btn.normal:ClearAllPoints()
                btn.normal:SetPoint("TOPLEFT", btn, "TOPLEFT", -pad, pad)
                btn.normal:SetPoint("BOTTOMRIGHT", btn, "BOTTOMRIGHT", pad, -pad)
                
                btn:Show()
            else
                btn.itemID = nil
                btn.itemLink = nil
                btn:SetAttribute("type", nil)
                btn:SetAttribute("macrotext", nil)
                btn:Hide()
            end
        end
    end

    -- Resize Anchor Frame
    local displayNum = math.max(1, hasTwoRows and math.max(numActiveFood, numActiveDrink) or numActiveFood)
    local totalLength = displayNum * size + (displayNum - 1) * spacing + 4 + handleSize
    local totalBreadth = (hasTwoRows and 2 or 1) * size + (hasTwoRows and spacing or 0) + 4

    if orientation == "Horizontal" then
        anchor:SetSize(totalLength, totalBreadth)
    else
        anchor:SetSize(totalBreadth, totalLength)
    end

    -- Handle unlocked fallback display when empty
    local numActiveTotal = hasTwoRows and (numActiveFood + numActiveDrink) or numActiveFood
    if numActiveTotal == 0 and db.hideWhenEmpty and not NS.configOpen then
        anchor:Hide()
        return
    else
        anchor:Show()
    end

    if numActiveTotal == 0 and (not db.locked or NS.configOpen) then
        anchor.bg:SetColorTexture(0.2, 0.6, 0.2, 0.4)
        anchor.title:ClearAllPoints()
        anchor.title:SetPoint("CENTER", anchor, "CENTER", 0, 0)
        anchor.title:SetText(def.label .. " (Empty)")
        anchor:SetSize(120, size + 4)
        anchor.title:Show()
        anchor.bg:Show()
    else
        anchor.bg:SetColorTexture(0.1, 0.1, 0.1, 0.6)
        if not db.locked then
            anchor.title:ClearAllPoints()
            if orientation == "Horizontal" then
                anchor.title:SetPoint("CENTER", anchor, "LEFT", 8, 0)
            else
                anchor.title:SetPoint("CENTER", anchor, "TOP", 0, -8)
            end
            anchor.title:SetText("::")
            anchor.title:Show()
            anchor.bg:Show()
        else
            anchor.title:Hide()
            anchor.bg:Hide()
        end
    end
end

function NS.UpdateBar()
    for _, def in ipairs(NS.barDefs) do
        NS.UpdateSingleBar(def.key)
    end
end

-- ---------------------------------------------------------------------------
-- Bar Creation
-- ---------------------------------------------------------------------------
local function CreateBarUI()
    for _, def in ipairs(NS.barDefs) do
        local barKey = def.key
        local db = NS.db[barKey]
        
        NS.bars[barKey] = {
            def = def,
            buttons = {},
            activeItems = {},
        }

        local anchor = CreateFrame("Frame", def.anchorName, UIParent, "BackdropTemplate")
        anchor:SetFrameStrata("HIGH")
        anchor:SetFrameLevel(20)
        anchor:SetMovable(true)
        anchor:RegisterForDrag("LeftButton")
        anchor:SetClampedToScreen(true)
        anchor:ClearAllPoints()
        anchor:SetPoint(db.point or def.defaults.point or "BOTTOM", UIParent, db.relativePoint or def.defaults.relativePoint or "BOTTOM", db.xOfs or def.defaults.xOfs or 100, db.yOfs or def.defaults.yOfs or 150)

        local bg = anchor:CreateTexture(nil, "BACKGROUND")
        bg:SetAllPoints(anchor)
        bg:SetColorTexture(0.1, 0.1, 0.1, 0.6)
        anchor.bg = bg

        local title = anchor:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        title:SetPoint("CENTER", anchor, "CENTER", 0, 0)
        title:SetText(def.label)
        title:SetTextColor(1, 0.82, 0)
        anchor.title = title

        anchor:SetScript("OnDragStart", function(self)
            if not InCombatLockdown() and not NS.db[barKey].locked then
                self:StartMoving()
                self.isMoving = true
            end
        end)
        local function stopMoving(self)
            if self.isMoving then
                self.isMoving = false
                pcall(self.StopMovingOrSizing, self)
                SavePosition(barKey)
            end
        end
        anchor:SetScript("OnDragStop", stopMoving)
        anchor:SetScript("OnMouseUp", function(self, button)
            if button == "LeftButton" and self.isMoving then
                stopMoving(self)
            elseif button == "RightButton" and not NS.db[barKey].locked and not InCombatLockdown() then
                if NS.ToggleConfig then NS.ToggleConfig() end
            end
        end)

        NS.bars[barKey].anchor = anchor
    end

    -- Backwards compat references
    NS.anchor = NS.bars.edibles.anchor
    NS.potionAnchor = NS.bars.potions.anchor
    NS.buttons = NS.bars.edibles.buttons
    NS.potionButtons = NS.bars.potions.buttons
    NS.bandaidButtons = NS.bars.bandaids.buttons
    NS.bombButtons = NS.bars.bombs.buttons
    NS.stoneButtons = NS.bars.stones.buttons
    NS.campingButtons = NS.bars.camping and NS.bars.camping.buttons
    NS.campingAnchor = NS.bars.camping and NS.bars.camping.anchor
end

-- ---------------------------------------------------------------------------
-- Event Handler
-- ---------------------------------------------------------------------------
frame:SetScript("OnEvent", function(self, event, ...)
    if event == "ADDON_LOADED" then
        local name = ...
        if name and ADDON and string.lower(name) == string.lower(ADDON) then
            InitializeDB()
        end
    elseif event == "PLAYER_LOGIN" then
        if not NS.db then
            InitializeDB()
        end
        CreateBarUI()
        NS.UpdateBar()
    elseif event == "PLAYER_LOGOUT" then
        for _, def in ipairs(NS.barDefs) do
            SavePosition(def.key)
        end
    elseif event == "BAG_UPDATE_DELAYED" then
        if InCombatLockdown() then
            NS.updateNeeded = true
            NS.UpdateBarVisuals()
        else
            NS.UpdateBar()
        end
    elseif event == "PLAYER_REGEN_ENABLED" then
        if NS.updateNeeded then
            NS.updateNeeded = false
            NS.UpdateBar()
        end
    elseif event == "GET_ITEM_INFO_RECEIVED" then
        if not InCombatLockdown() then
            NS.UpdateBar()
        end
    end
end)
