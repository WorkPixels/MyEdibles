-- Config.lua -- tabbed configuration panel for MyEdibles, MyPotions, and MyBandAids.
local ADDON, NS = ...
local C = NS.C
local GetItemInfo = C.GetItemInfo

local win
local function deepCopy(orig)
    if type(orig) ~= "table" then return orig end
    local copy = {}
    for k, v in pairs(orig) do
        copy[k] = type(v) == "table" and deepCopy(v) or v
    end
    return copy
end
local tabs, tabButtons = {}, {}
local checks = {}
local wlRows, blRows, bagsRows = {}, {}, {}
local wlOffset, blOffset, bagsOffset = 0, 0, 0
local wlCount, blCount, bagsCount = 0, 0, 0
local wlEmpty, blEmpty, bagsEmpty

-- Filter checkbuttons per bar key
local filterCBs = {} -- filterCBs[barKey] = { cb1, cb2, ... }

-- Whitelist/Blacklist bar selector state & buttons
local activeWlBar = "edibles"
local activeBlBar = "edibles"
local wlBarButtons = {} -- wlBarButtons[barKey] = button
local blBarButtons = {} -- blBarButtons[barKey] = button

-- Slider references per bar key
local barSliders = {} -- barSliders[barKey] = { max, size, spacing, scale }

-- ---------------------------------------------------------------------------
-- Widget Builders
-- ---------------------------------------------------------------------------
local function makeSlider(parent, key, label, min, max, step, x, y, setter, fmt)
    local s = CreateFrame("Slider", "MyEdiblesCfg"..key, parent, "OptionsSliderTemplate")
    s:SetWidth(200); s:SetHeight(16)
    s:SetPoint("TOPLEFT", x, y)
    s:SetMinMaxValues(min, max)
    s:SetValueStep(step)
    if s.SetObeyStepOnDrag then s:SetObeyStepOnDrag(true) end
    _G[s:GetName().."Low"]:SetText(tostring(min))
    _G[s:GetName().."High"]:SetText(tostring(max))
    s.titleFS = _G[s:GetName().."Text"]
    s.label, s.fmt = label, fmt
    s:SetScript("OnValueChanged", function(self, val)
        val = math.floor(val/step + 0.5) * step
        val = math.floor(val*100 + 0.5)/100
        setter(val)
        self.titleFS:SetText(self.label..": "..(self.fmt and self.fmt(val) or val))
        if NS.UpdateBar then NS.UpdateBar() end
    end)
    return s
end

local function makeCheck(parent, key, label, x, y, get, set)
    local cb = CreateFrame("CheckButton", "MyEdiblesCfg"..key, parent, "UICheckButtonTemplate")
    cb:SetPoint("TOPLEFT", x, y)
    _G[cb:GetName().."Text"]:SetText(label)
    cb.get, cb.set = get, set
    cb:SetScript("OnClick", function(self)
        set(self:GetChecked() and true or false)
        if NS.UpdateBar then NS.UpdateBar() end
    end)
    checks[#checks+1] = cb
    return cb
end

local function header(parent, text, x, y, w)
    local h = parent:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    h:SetPoint("TOPLEFT", x, y); h:SetText(text); h:SetTextColor(1, 0.82, 0)
    local line = parent:CreateTexture(nil, "ARTWORK")
    line:SetColorTexture(1, 0.82, 0, 0.3)
    line:SetPoint("TOPLEFT", x, y - 16); line:SetSize(w or 480, 1)
    return h
end

-- ---------------------------------------------------------------------------
-- Tab framework
-- ---------------------------------------------------------------------------
local function selectTab(i)
    for j, fr in ipairs(tabs) do fr:SetShown(j == i) end
    for j, b in ipairs(tabButtons) do
        if j == i then 
            b:LockHighlight() 
            b:GetFontString():SetTextColor(1, 0.82, 0)
        else 
            b:UnlockHighlight() 
            b:GetFontString():SetTextColor(1, 1, 1) 
        end
    end
end

local function newTab(label, idx, x)
    local b = CreateFrame("Button", nil, win, "UIPanelButtonTemplate")
    b:SetSize(64, 22); b:SetPoint("TOPLEFT", x, -48)
    b:SetText(label)
    b:SetScript("OnClick", function() selectTab(idx) end)
    tabButtons[idx] = b
    local fr = CreateFrame("Frame", nil, win)
    fr:SetPoint("TOPLEFT", 16, -80)
    fr:SetPoint("BOTTOMRIGHT", -16, 20)
    fr:Hide()
    tabs[idx] = fr
    return fr
end

-- ---------------------------------------------------------------------------
-- Item resolution from string input or drag
-- ---------------------------------------------------------------------------
local function ResolveItem(text)
    if not text or text == "" then return nil end
    local itemID = tonumber(text) or tonumber(text:match("item:(%d+)"))
    if not itemID then
        local name, link = GetItemInfo(text)
        if link then
            itemID = tonumber(link:match("item:(%d+)"))
        end
    end
    return itemID
end

local function SetupDragNDrop(editBox)
    local function HandleEditBoxDrag(self)
        local infoType, itemID, itemLink = GetCursorInfo()
        if infoType == "item" and itemID then
            self:SetText(itemLink or tostring(itemID))
            ClearCursor()
        end
    end
    editBox:SetScript("OnReceiveDrag", HandleEditBoxDrag)
    editBox:SetScript("OnMouseUp", HandleEditBoxDrag)
end

-- ---------------------------------------------------------------------------
-- Filter UI Updates
-- ---------------------------------------------------------------------------
local function UpdateFilterChecks()
    for _, def in ipairs(NS.barDefs) do
        local cbs = filterCBs[def.key]
        if cbs then
            local filter = NS.db[def.key].filterType or "All"
            for _, entry in ipairs(cbs) do
                entry.cb:SetChecked(entry.filterKey == filter)
            end
        end
    end
end

local function UpdateWlBarToggles()
    for barKey, btn in pairs(wlBarButtons) do
        if barKey == activeWlBar then btn:LockHighlight() else btn:UnlockHighlight() end
    end
end

local function UpdateBlBarToggles()
    for barKey, btn in pairs(blBarButtons) do
        if barKey == activeBlBar then btn:LockHighlight() else btn:UnlockHighlight() end
    end
end

-- ---------------------------------------------------------------------------
-- List Management & Refreshing
-- ---------------------------------------------------------------------------
local function GetWhitelistIDs(barType)
    local ids = {}
    local db = NS.db[barType]
    for id in pairs(db.whitelist or {}) do
        if db.whitelist[id] then table.insert(ids, id) end
    end
    table.sort(ids)
    return ids
end

local function GetBlacklistIDs(barType)
    local ids = {}
    local db = NS.db[barType]
    for id in pairs(db.blacklist or {}) do
        if db.blacklist[id] then table.insert(ids, id) end
    end
    table.sort(ids)
    return ids
end

local function GetBagsConsumables()
    local counts = {}
    local items = {}
    local seen = {}
    
    for _, bag in ipairs(C.BACKPACK_BAGS) do
        local slots = C.NumSlots(bag)
        for slot = 1, slots do
            local info = C.ItemInfo(bag, slot)
            if info and info.itemID then
                local id = info.itemID
                counts[id] = (counts[id] or 0) + info.count
                if not seen[id] then
                    seen[id] = true
                    local name, link, quality, _, reqLevel, class, subclass, _, _, texture, _, classID, subclassID = GetItemInfo(id)
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
                           string.find(lowerName, "pietra della salute") then
                            isHealthstone = true
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

                        -- Check if listed on any bar
                        local isListed = false
                        for _, def in ipairs(NS.barDefs) do
                            if NS.db[def.key].whitelist[id] or NS.db[def.key].blacklist[id] then
                                isListed = true
                                break
                            end
                        end
                        
                        if isFoodAndDrink or isPotion or isElixir or isFlask or isBandage or isHealthstone or isBomb or isStone or isCamping or isListed then
                            table.insert(items, {
                                id = id,
                                name = name,
                                link = info.link or link,
                                icon = texture or info.icon,
                                count = 0
                            })
                        end
                    end
                end
            end
        end
    end
    
    for _, item in ipairs(items) do
        item.count = counts[item.id] or 0
    end
    
    table.sort(items, function(a, b) return a.name < b.name end)
    return items
end

local function RefreshWhitelistList()
    if not win or not wlRows then return end
    local ids = GetWhitelistIDs(activeWlBar)
    wlCount = #ids
    local maxOff = math.max(0, wlCount - 8)
    wlOffset = math.min(wlOffset, maxOff)

    for i = 1, 8 do
        local row = wlRows[i]
        local idx = i + wlOffset
        local id = ids[idx]
        if id then
            row.itemID = id
            local name, link, _, _, _, _, _, _, _, texture = GetItemInfo(id)
            if not name then
                name = "item:" .. id
                if C_Item and C_Item.RequestLoadItemDataByID then C_Item.RequestLoadItemDataByID(id) end
            end
            local iconStr = texture and ("|T"..texture..":16:16:0:0|t ") or ""
            row.text:SetText(iconStr .. (link or name))
            row:Show()
        else
            row.itemID = nil
            row:Hide()
        end
    end
    wlEmpty:SetShown(wlCount == 0)
end

local function RefreshBlacklistList()
    if not win or not blRows then return end
    local ids = GetBlacklistIDs(activeBlBar)
    blCount = #ids
    local maxOff = math.max(0, blCount - 8)
    blOffset = math.min(blOffset, maxOff)

    for i = 1, 8 do
        local row = blRows[i]
        local idx = i + blOffset
        local id = ids[idx]
        if id then
            row.itemID = id
            local name, link, _, _, _, _, _, _, _, texture = GetItemInfo(id)
            if not name then
                name = "item:" .. id
                if C_Item and C_Item.RequestLoadItemDataByID then C_Item.RequestLoadItemDataByID(id) end
            end
            local iconStr = texture and ("|T"..texture..":16:16:0:0|t ") or ""
            row.text:SetText(iconStr .. (link or name))
            row:Show()
        else
            row.itemID = nil
            row:Hide()
        end
    end
    blEmpty:SetShown(blCount == 0)
end

local function RefreshBagsList()
    if not win or not bagsRows then return end
    local items = GetBagsConsumables()
    bagsCount = #items
    local maxOff = math.max(0, bagsCount - 8)
    bagsOffset = math.min(bagsOffset, maxOff)

    for i = 1, 8 do
        local row = bagsRows[i]
        local idx = i + bagsOffset
        local item = items[idx]
        if item then
            row.itemID = item.id
            local iconStr = item.icon and ("|T"..item.icon..":16:16:0:0|t ") or ""
            local countStr = " (" .. item.count .. ")"
            row.text:SetText(iconStr .. item.name .. countStr)

            -- Status text
            local statusList = {}
            for _, def in ipairs(NS.barDefs) do
                local short = def.key:sub(1, 3):upper() -- EDI, POT, BAN
                if NS.db[def.key].whitelist[item.id] then
                    table.insert(statusList, "|cff00ff00WL " .. short .. "|r")
                end
                if NS.db[def.key].blacklist[item.id] then
                    table.insert(statusList, "|cffff2222BL " .. short .. "|r")
                end
            end
            row.status:SetText(table.concat(statusList, " "))

            -- Update button highlights
            for _, def in ipairs(NS.barDefs) do
                local wlBtn = row.barWlBtns[def.key]
                local blBtn = row.barBlBtns[def.key]
                if wlBtn then
                    if NS.db[def.key].whitelist[item.id] then wlBtn:LockHighlight() else wlBtn:UnlockHighlight() end
                end
                if blBtn then
                    if NS.db[def.key].blacklist[item.id] then blBtn:LockHighlight() else blBtn:UnlockHighlight() end
                end
            end

            row:Show()
        else
            row.itemID = nil
            row:Hide()
        end
    end
    bagsEmpty:SetShown(bagsCount == 0)
end

local function RefreshAllLists()
    RefreshWhitelistList()
    RefreshBlacklistList()
    RefreshBagsList()
end

-- ---------------------------------------------------------------------------
-- Build a settings tab for a given bar definition
-- ---------------------------------------------------------------------------
local function BuildBarSettingsTab(def, tabFrame)
    local barKey = def.key

    makeCheck(tabFrame, "Enable_"..barKey, "Enable Bar", 10, -10,
        function() return NS.db[barKey].enabled end, 
        function(v) NS.db[barKey].enabled = v end)

    makeCheck(tabFrame, "Lock_"..barKey, "Lock Bar position and hide anchor", 10, -36,
        function() return NS.db[barKey].locked end, 
        function(v) NS.db[barKey].locked = v end)

    makeCheck(tabFrame, "Vertical_"..barKey, "Vertical Bar Layout", 10, -62,
        function() return NS.db[barKey].orientation == "Vertical" end, 
        function(v) NS.db[barKey].orientation = v and "Vertical" or "Horizontal" end)

    makeCheck(tabFrame, "HideEmpty_"..barKey, "Hide bar when inventory is empty", 10, -88,
        function() return NS.db[barKey].hideWhenEmpty end, 
        function(v) NS.db[barKey].hideWhenEmpty = v end)

    -- Filter section (only show if more than one filter option)
    local yOffset = -136
    if #def.filterOpts > 1 then
        header(tabFrame, def.label .. " Filter", 10, yOffset, 220)
        yOffset = yOffset - 18

        filterCBs[barKey] = {}
        for fi, fopt in ipairs(def.filterOpts) do
            local cbName = "MyEdiblesCfgFilter_" .. barKey .. "_" .. fopt.key
            local fcb = CreateFrame("CheckButton", cbName, tabFrame, "UICheckButtonTemplate")
            fcb:SetPoint("TOPLEFT", 10, yOffset)
            _G[fcb:GetName().."Text"]:SetText(fopt.label)
            fcb:SetScript("OnClick", function()
                NS.db[barKey].filterType = fopt.key
                UpdateFilterChecks()
                if NS.UpdateBar then NS.UpdateBar() end
            end)
            table.insert(filterCBs[barKey], { cb = fcb, filterKey = fopt.key })
            yOffset = yOffset - 26
        end
        yOffset = yOffset - 24
    end

    -- Sliders
    barSliders[barKey] = {}
    barSliders[barKey].max = makeSlider(tabFrame, barKey.."MaxItems", "Max Items to Show", 1, 20, 1, 12, yOffset,
        function(v) NS.db[barKey].maxItems = v end)
    yOffset = yOffset - 40

    barSliders[barKey].size = makeSlider(tabFrame, barKey.."ButtonSize", "Button Size", 20, 64, 1, 12, yOffset,
        function(v) NS.db[barKey].buttonSize = v end)
    yOffset = yOffset - 40

    barSliders[barKey].spacing = makeSlider(tabFrame, barKey.."Spacing", "Button Spacing", 0, 20, 1, 12, yOffset,
        function(v) NS.db[barKey].buttonSpacing = v end)
    yOffset = yOffset - 40

    barSliders[barKey].scale = makeSlider(tabFrame, barKey.."Scale", "Scale", 0.5, 2.0, 0.1, 12, yOffset,
        function(v) NS.db[barKey].scale = v end)
    yOffset = yOffset - 40

    -- Reset Position Button
    local resetBtn = CreateFrame("Button", nil, tabFrame, "UIPanelButtonTemplate")
    resetBtn:SetSize(160, 22); resetBtn:SetPoint("TOPLEFT", 12, yOffset)
    resetBtn:SetText("Reset Position")
    resetBtn:SetScript("OnClick", function()
        local defConf = def.defaults or {}
        local point = defConf.point or "BOTTOM"
        local relPt = defConf.relativePoint or "BOTTOM"
        local xOfs = defConf.xOfs or 100
        local yOfs = defConf.yOfs or 150
        NS.db[barKey].point = point
        NS.db[barKey].relativePoint = relPt
        NS.db[barKey].xOfs = xOfs
        NS.db[barKey].yOfs = yOfs
        local barState = NS.bars[barKey]
        if barState and barState.anchor then
            barState.anchor:ClearAllPoints()
            barState.anchor:SetPoint(point, UIParent, relPt, xOfs, yOfs)
        end
        if NS.UpdateBar then NS.UpdateBar() end
    end)
end

-- ---------------------------------------------------------------------------
-- Window Creation
-- ---------------------------------------------------------------------------
local function build()
    win = CreateFrame("Frame", "MyEdiblesConfigWindow", UIParent, "BackdropTemplate")
    win:SetSize(650, 560)
    win:SetFrameStrata("FULLSCREEN_DIALOG")
    win:SetToplevel(true)
    if NS.db and NS.db.configPos then
        local p = NS.db.configPos
        win:SetPoint(p.point or "CENTER", UIParent, p.relativePoint or "CENTER", p.x or 0, p.y or 0)
    else
        win:SetPoint("CENTER")
    end
    win:EnableMouse(true); win:SetMovable(true)
    win:RegisterForDrag("LeftButton")
    win:SetScript("OnDragStart", win.StartMoving)
    win:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        local pt, _, relPt, x, y = self:GetPoint(1)
        if pt and x and y and NS.db then
            NS.db.configPos = { point = pt, relativePoint = relPt or pt, x = x, y = y }
        end
    end)
    win:SetScript("OnShow", function()
        NS.configOpen = true
        if NS.UpdateBar then NS.UpdateBar() end
    end)
    win:SetScript("OnHide", function()
        NS.configOpen = false
        if NS.UpdateBar then NS.UpdateBar() end
    end)
    win:Hide()
    
    if win.SetBackdrop then
        win:SetBackdrop({
            bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background-Dark",
            edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
            tile = true, tileSize = 32, edgeSize = 32,
            insets = { left = 11, right = 11, top = 11, bottom = 11 },
        })
    end
    tinsert(UISpecialFrames, "MyEdiblesConfigWindow")

    -- Title
    local titleBg = win:CreateTexture(nil, "ARTWORK")
    titleBg:SetColorTexture(1, 0.82, 0, 0.08)
    titleBg:SetPoint("TOPLEFT", 12, -12); titleBg:SetPoint("TOPRIGHT", -12, -12); titleBg:SetHeight(28)
    local t = win:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    t:SetPoint("LEFT", titleBg, "LEFT", 14, 0); t:SetText("MyEdibles Config"); t:SetTextColor(1, 0.82, 0)

    -- Close Button
    local close = CreateFrame("Button", nil, win, "UIPanelCloseButton")
    close:SetPoint("TOPRIGHT", 2, 2)
    close:SetScript("OnClick", function() win:Hide() end)

    -- Tab layout: one settings tab per bar + whitelist + blacklist + bags
    local numBars = #NS.barDefs
    local tabX = 16
    local tabIdx = 0

    -- Build settings tabs for each bar
    for _, def in ipairs(NS.barDefs) do
        tabIdx = tabIdx + 1
        local tabFrame = newTab(def.label:gsub("^My", ""), tabIdx, tabX)
        tabX = tabX + 68
        BuildBarSettingsTab(def, tabFrame)
    end

    -- ===== Whitelist Tab =====
    tabIdx = tabIdx + 1
    local wl = newTab("WList", tabIdx, tabX)
    tabX = tabX + 68
    header(wl, "Item Whitelist (Always show these items)", 8, -6, 500)

    -- Bar Selector Toggles
    local wlBarText = wl:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    wlBarText:SetPoint("TOPLEFT", 8, -26)
    wlBarText:SetText("Bar:")
    
    local wlBtnX = wlBarText
    for _, def in ipairs(NS.barDefs) do
        local btn = CreateFrame("Button", nil, wl, "UIPanelButtonTemplate")
        btn:SetSize(76, 20)
        if wlBtnX == wlBarText then
            btn:SetPoint("LEFT", wlBarText, "RIGHT", 8, 0)
        else
            btn:SetPoint("LEFT", wlBtnX, "RIGHT", 4, 0)
        end
        btn:SetText(def.label:gsub("^My", ""))
        btn:SetScript("OnClick", function()
            activeWlBar = def.key; UpdateWlBarToggles(); wlOffset = 0; RefreshWhitelistList()
        end)
        wlBarButtons[def.key] = btn
        wlBtnX = btn
    end

    local wlAddBox = CreateFrame("EditBox", nil, wl, "InputBoxTemplate")
    wlAddBox:SetSize(280, 20); wlAddBox:SetPoint("TOPLEFT", 8, -50)
    wlAddBox:SetAutoFocus(false)
    SetupDragNDrop(wlAddBox)

    local wlAddBtn = CreateFrame("Button", nil, wl, "UIPanelButtonTemplate")
    wlAddBtn:SetSize(100, 20); wlAddBtn:SetPoint("LEFT", wlAddBox, "RIGHT", 6, 0)
    wlAddBtn:SetText("Add Whitelist")
    wlAddBtn:SetScript("OnClick", function()
        local txt = wlAddBox:GetText()
        local id = ResolveItem(txt)
        if id then
            NS.db[activeWlBar].whitelist[id] = true
            NS.db[activeWlBar].blacklist[id] = nil
            wlAddBox:SetText("")
            RefreshAllLists()
            if NS.UpdateBar then NS.UpdateBar() end
        else
            print("|cffff4444MyEdibles:|r Could not resolve item. Try dragging an item onto the editbox, or using its item ID.")
        end
    end)

    local ROW_H = 20
    local wlList = CreateFrame("Frame", nil, wl)
    wlList:SetPoint("TOPLEFT", 8, -80)
    wlList:SetSize(500, ROW_H * 8)
    wlList:EnableMouseWheel(true)
    wlList:SetScript("OnMouseWheel", function(_, delta)
        local maxOff = math.max(0, wlCount - 8)
        wlOffset = math.min(maxOff, math.max(0, wlOffset - delta))
        RefreshWhitelistList()
    end)

    wlRows = {}
    for i = 1, 8 do
        local row = CreateFrame("Frame", nil, wlList)
        row:SetSize(500, ROW_H)
        row:SetPoint("TOPLEFT", 0, -(i-1)*ROW_H)

        row.text = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        row.text:SetPoint("LEFT", 4, 0); row.text:SetWidth(400); row.text:SetJustifyH("LEFT")

        local del = CreateFrame("Button", nil, row, "UIPanelCloseButton")
        del:SetSize(16, 16); del:SetPoint("RIGHT", -4, 0)
        del:SetScript("OnClick", function()
            if row.itemID then
                NS.db[activeWlBar].whitelist[row.itemID] = nil
                RefreshAllLists()
                if NS.UpdateBar then NS.UpdateBar() end
            end
        end)

        wlRows[i] = row
    end
    wlEmpty = wlList:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    wlEmpty:SetPoint("TOPLEFT", 4, -4)
    wlEmpty:SetText("No whitelisted items. Select a bar above, then drag items or type item ID to add.")

    -- ===== Blacklist Tab =====
    tabIdx = tabIdx + 1
    local bl = newTab("BList", tabIdx, tabX)
    tabX = tabX + 68
    header(bl, "Item Blacklist (Never show these items)", 8, -6, 500)

    -- Bar Selector Toggles
    local blBarText = bl:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    blBarText:SetPoint("TOPLEFT", 8, -26)
    blBarText:SetText("Bar:")
    
    local blBtnX = blBarText
    for _, def in ipairs(NS.barDefs) do
        local btn = CreateFrame("Button", nil, bl, "UIPanelButtonTemplate")
        btn:SetSize(76, 20)
        if blBtnX == blBarText then
            btn:SetPoint("LEFT", blBarText, "RIGHT", 8, 0)
        else
            btn:SetPoint("LEFT", blBtnX, "RIGHT", 4, 0)
        end
        btn:SetText(def.label:gsub("^My", ""))
        btn:SetScript("OnClick", function()
            activeBlBar = def.key; UpdateBlBarToggles(); blOffset = 0; RefreshBlacklistList()
        end)
        blBarButtons[def.key] = btn
        blBtnX = btn
    end

    local blAddBox = CreateFrame("EditBox", nil, bl, "InputBoxTemplate")
    blAddBox:SetSize(280, 20); blAddBox:SetPoint("TOPLEFT", 8, -50)
    blAddBox:SetAutoFocus(false)
    SetupDragNDrop(blAddBox)

    local blAddBtn = CreateFrame("Button", nil, bl, "UIPanelButtonTemplate")
    blAddBtn:SetSize(100, 20); blAddBtn:SetPoint("LEFT", blAddBox, "RIGHT", 6, 0)
    blAddBtn:SetText("Add Blacklist")
    blAddBtn:SetScript("OnClick", function()
        local txt = blAddBox:GetText()
        local id = ResolveItem(txt)
        if id then
            NS.db[activeBlBar].blacklist[id] = true
            NS.db[activeBlBar].whitelist[id] = nil
            blAddBox:SetText("")
            RefreshAllLists()
            if NS.UpdateBar then NS.UpdateBar() end
        else
            print("|cffff4444MyEdibles:|r Could not resolve item. Try dragging an item onto the editbox, or using its item ID.")
        end
    end)

    local blList = CreateFrame("Frame", nil, bl)
    blList:SetPoint("TOPLEFT", 8, -80)
    blList:SetSize(500, ROW_H * 8)
    blList:EnableMouseWheel(true)
    blList:SetScript("OnMouseWheel", function(_, delta)
        local maxOff = math.max(0, blCount - 8)
        blOffset = math.min(maxOff, math.max(0, blOffset - delta))
        RefreshBlacklistList()
    end)

    blRows = {}
    for i = 1, 8 do
        local row = CreateFrame("Frame", nil, blList)
        row:SetSize(500, ROW_H)
        row:SetPoint("TOPLEFT", 0, -(i-1)*ROW_H)

        row.text = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        row.text:SetPoint("LEFT", 4, 0); row.text:SetWidth(400); row.text:SetJustifyH("LEFT")

        local del = CreateFrame("Button", nil, row, "UIPanelCloseButton")
        del:SetSize(16, 16); del:SetPoint("RIGHT", -4, 0)
        del:SetScript("OnClick", function()
            if row.itemID then
                NS.db[activeBlBar].blacklist[row.itemID] = nil
                RefreshAllLists()
                if NS.UpdateBar then NS.UpdateBar() end
            end
        end)

        blRows[i] = row
    end
    blEmpty = blList:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    blEmpty:SetPoint("TOPLEFT", 4, -4)
    blEmpty:SetText("No blacklisted items. Select a bar above, then drag items or type item ID to add.")

    -- ===== Bags Scanner Tab =====
    tabIdx = tabIdx + 1
    local bgTab = newTab("Bags", tabIdx, tabX)
    header(bgTab, "Inventory Scanner", 8, -6, 500)

    local bagsList = CreateFrame("Frame", nil, bgTab)
    bagsList:SetPoint("TOPLEFT", 8, -26)
    bagsList:SetSize(610, ROW_H * 8 + 20)
    bagsList:EnableMouseWheel(true)
    bagsList:SetScript("OnMouseWheel", function(_, delta)
        local maxOff = math.max(0, bagsCount - 8)
        bagsOffset = math.min(maxOff, math.max(0, bagsOffset - delta))
        RefreshBagsList()
    end)

    bagsRows = {}
    for i = 1, 8 do
        local row = CreateFrame("Frame", nil, bagsList)
        row:SetSize(610, ROW_H + 4)
        row:SetPoint("TOPLEFT", 0, -(i-1)*(ROW_H + 4))

        row.text = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        row.text:SetPoint("LEFT", 4, 0); row.text:SetWidth(70); row.text:SetJustifyH("LEFT")

        row.status = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        row.status:SetPoint("LEFT", row.text, "RIGHT", 2, 0); row.status:SetWidth(40); row.status:SetJustifyH("LEFT")

        -- Create WL/BL toggle buttons for each bar
        row.barWlBtns = {}
        row.barBlBtns = {}
        local prevBtn = row.status
        for _, def in ipairs(NS.barDefs) do
            local short = def.key:sub(1, 3):upper()
            
            local wlBtn = CreateFrame("Button", nil, row, "UIPanelButtonTemplate")
            wlBtn:SetSize(38, 18); wlBtn:SetPoint("LEFT", prevBtn, "RIGHT", 3, 0)
            wlBtn:SetText("+" .. short:sub(1,3))
            wlBtn:SetScript("OnClick", function()
                if row.itemID then
                    if NS.db[def.key].whitelist[row.itemID] then
                        NS.db[def.key].whitelist[row.itemID] = nil
                    else
                        NS.db[def.key].whitelist[row.itemID] = true
                        NS.db[def.key].blacklist[row.itemID] = nil
                    end
                    RefreshAllLists()
                    if NS.UpdateBar then NS.UpdateBar() end
                end
            end)

            local blBtn = CreateFrame("Button", nil, row, "UIPanelButtonTemplate")
            blBtn:SetSize(38, 18); blBtn:SetPoint("LEFT", wlBtn, "RIGHT", 1, 0)
            blBtn:SetText("x" .. short:sub(1,3))
            blBtn:SetScript("OnClick", function()
                if row.itemID then
                    if NS.db[def.key].blacklist[row.itemID] then
                        NS.db[def.key].blacklist[row.itemID] = nil
                    else
                        NS.db[def.key].blacklist[row.itemID] = true
                        NS.db[def.key].whitelist[row.itemID] = nil
                    end
                    RefreshAllLists()
                    if NS.UpdateBar then NS.UpdateBar() end
                end
            end)

            row.barWlBtns[def.key] = wlBtn
            row.barBlBtns[def.key] = blBtn
            prevBtn = blBtn
        end

        bagsRows[i] = row
    end
    bagsEmpty = bagsList:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    bagsEmpty:SetPoint("TOPLEFT", 4, -4)
    bagsEmpty:SetText("No consumable items currently in bags.")

    selectTab(1)
end

-- ---------------------------------------------------------------------------
-- Config API Interface
-- ---------------------------------------------------------------------------
function NS.RefreshConfig()
    if not win then return end
    
    local function setSlider(sl, val)
        sl:SetValue(val)
        sl.titleFS:SetText(sl.label..": "..(sl.fmt and sl.fmt(val) or val))
    end
    
    for _, def in ipairs(NS.barDefs) do
        local sl = barSliders[def.key]
        if sl then
            setSlider(sl.max, NS.db[def.key].maxItems)
            setSlider(sl.size, NS.db[def.key].buttonSize)
            setSlider(sl.spacing, NS.db[def.key].buttonSpacing)
            setSlider(sl.scale, NS.db[def.key].scale)
        end
    end
    
    for _, cb in ipairs(checks) do
        cb:SetChecked(cb.get())
    end
    
    UpdateFilterChecks()
    UpdateWlBarToggles()
    UpdateBlBarToggles()
    RefreshAllLists()
end

function NS.ToggleConfig()
    if not win then
        local ok, err = pcall(build)
        if not ok then
            print("|cffff4444MyEdibles:|r Could not build config UI: "..tostring(err))
            return
        end
    end
    
    if win:IsShown() then
        win:Hide()
    else
        NS.RefreshConfig()
        win:Show()
    end
end

-- Register to Blizzard settings panel
local function RegisterAddonCategory()
    local panel = CreateFrame("Frame", "MyEdiblesOptionsShortcut")
    panel.name = "MyEdibles"
    
    local t = panel:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    t:SetPoint("TOPLEFT", 16, -16)
    t:SetText("MyEdibles")

    local d = panel:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    d:SetPoint("TOPLEFT", 16, -42)
    d:SetText("Config menu for MyEdibles. Manages food, potions, and bandage bars.")

    local b = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
    b:SetSize(160, 26); b:SetPoint("TOPLEFT", 16, -66)
    b:SetText("Open Config Menu")
    b:SetScript("OnClick", function() 
        if _G.InterfaceOptionsFrame_Show then
            pcall(_G.InterfaceOptionsFrame_Show)
        end
        if _G.SettingsPanel and _G.SettingsPanel.Close then
            pcall(function() _G.SettingsPanel:Close() end)
        end
        if _G.InterfaceOptionsFrame and _G.InterfaceOptionsFrame.Hide then
            pcall(function() _G.InterfaceOptionsFrame:Hide() end)
        end
        NS.ToggleConfig() 
    end)
    
    if Settings and Settings.RegisterCanvasLayoutCategory and Settings.RegisterAddOnCategory then
        local cat = Settings.RegisterCanvasLayoutCategory(panel, "MyEdibles")
        Settings.RegisterAddOnCategory(cat)
    elseif InterfaceOptions_AddCategory then
        InterfaceOptions_AddCategory(panel)
    end
end

-- ---------------------------------------------------------------------------
-- Slash Commands
-- ---------------------------------------------------------------------------
SLASH_MYEDIBLES1 = "/myedibles"
SLASH_MYEDIBLES2 = "/edibles"
SlashCmdList["MYEDIBLES"] = function(msg)
    local cmd = string.lower(msg or "")
    if cmd == "lock" then
        for _, def in ipairs(NS.barDefs) do NS.db[def.key].locked = true end
        print("|cffffd100MyEdibles:|r All bars locked.")
        if NS.UpdateBar then NS.UpdateBar() end
    elseif cmd == "unlock" then
        for _, def in ipairs(NS.barDefs) do NS.db[def.key].locked = false end
        print("|cffffd100MyEdibles:|r All bars unlocked.")
        if NS.UpdateBar then NS.UpdateBar() end
    elseif cmd == "reset" then
        for _, def in ipairs(NS.barDefs) do
            local defConf = def.defaults or {}
            local point = defConf.point or "BOTTOM"
            local relPt = defConf.relativePoint or "BOTTOM"
            local xOfs = defConf.xOfs or 100
            local yOfs = defConf.yOfs or 150
            NS.db[def.key].point = point
            NS.db[def.key].relativePoint = relPt
            NS.db[def.key].xOfs = xOfs
            NS.db[def.key].yOfs = yOfs
            local barState = NS.bars[def.key]
            if barState and barState.anchor then
                barState.anchor:ClearAllPoints()
                barState.anchor:SetPoint(point, UIParent, relPt, xOfs, yOfs)
            end
        end
        if NS.UpdateBar then NS.UpdateBar() end
        print("|cffffd100MyEdibles:|r All positions reset to default above action bar.")
    else
        NS.ToggleConfig()
    end
end

-- ---------------------------------------------------------------------------
-- Initialization Event Handler
-- ---------------------------------------------------------------------------
local setup = CreateFrame("Frame")
setup:RegisterEvent("PLAYER_LOGIN")
setup:SetScript("OnEvent", function(self, event)
    RegisterAddonCategory()
end)
