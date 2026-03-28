
-- this is the file to put all your custom logic functions into.
-- if you dont want to use the json based logic you can switch to a graph-based logic method.
-- the needed functions for that are in `/scripts/logic/graph_logic/logic_main.lua`.



-- function <name> (<parameters if needed>)
--     <actual code>
--     <indentations are just for readability>
-- end
--

-- Globals
local scoop_sanity_enabled = nil
local restricted_item_enabled = nil
local scoop_order_list = {}
local goal_is_ending_s = true

-- Clear handler
Archipelago:AddClearHandler("dead_rising_slot_data_init", function(slot_data)
    print("ClearHandler fired! Slot data received.")

    -- Scoop Sanity
    local ss_val = slot_data.scoop_sanity
    if ss_val == nil and slot_data.options then ss_val = slot_data.options.scoop_sanity end
    scoop_sanity_enabled = (ss_val == true or ss_val == 1)
    print("ScoopSanity: " .. (scoop_sanity_enabled and "ENABLED" or "DISABLED"))

    -- Restricted Item Mode
    local ri_val = slot_data.restricted_item_mode
    if ri_val == nil and slot_data.options then ri_val = slot_data.options.restricted_item_mode end
    restricted_item_enabled = (ri_val == true or ri_val == 1)
    print("Restricted Item Mode: " .. (restricted_item_enabled and "ENABLED" or "DISABLED"))

    -- Scoop Order
    if slot_data.scoop_order and type(slot_data.scoop_order) == "table" then
        scoop_order_list = slot_data.scoop_order
        print("Scoop order received with " .. #scoop_order_list .. " entries:")
        print("   " .. table.concat(scoop_order_list, " then "))
    else
        scoop_order_list = {}
        print("No scoop order received (or ScoopSanity off)")
    end

    -- ==================== GOAL LOGIC ====================
    local goal_val = slot_data.goal
    if goal_val == nil and slot_data.options then
        goal_val = slot_data.options.goal
    end

    if goal_val == 1 then
        goal_is_ending_s = false
        print(">>> GOAL IS ENDING A so Hiding Ending S content")
    else
        goal_is_ending_s = true
        print(">>> GOAL IS ENDING S (or unknown) so Showing Ending S content")
    end

    Tracker:Update()
end)

-- Functions
function hasScoopSanity()    return scoop_sanity_enabled and 1 or 0 end
function hasRegularMode()    return (not scoop_sanity_enabled) and 1 or 0 end
function hasRestrictedItems() return restricted_item_enabled and 1 or 0 end
function hasNormalItems()    return (not restricted_item_enabled) and 1 or 0 end
function getScoopOrder()     return scoop_order_list end

function hasGoalEndingS()
    local result = goal_is_ending_s and 1 or 0
    return result
end

function hasGoalEndingA()
    return (not goal_is_ending_s) and 1 or 0
end

-- ==================== MAIN SCOOP CHAIN LOGIC ====================

-- Table that maps scoop name → its completion location path
-- You MUST fill this in with your exact @paths from location_mapping.lua or JSON
local SCOOP_TO_PATH = {
    ["Hideout"]                     = "@Main Scoops/Hideout/Escort Isabela to the Hideout and have a chat",
    ["Image in the Monitor"]        = "@Main Scoops/Image in the Monitor/Complete Image in the Monitor",
    ["Santa Cabeza"]                = "@Main Scoops/Santa Cabeza/Complete Santa Cabeza",
    ["Girl Hunting"]                = "@Main Scoops/Girl Hunting/Beat up Isabela",
    ["The Butcher"]                 = "@Main Scoops/The Butcher/Complete The Butcher",
    ["A Promise to Isabela"]        = "@Main Scoops/A Promise to Isabela/Carry Isabela back to the Safe Room",
    ["Backup for Brad"]             = "@Main Scoops/Backup for Brad/Escort Brad to see Dr Barnaby",
    ["A Temporary Agreement"]       = "@Main Scoops/Temporary Agreement/Complete Temporary Agreement",
    ["Rescue the Professor"]        = "@Main Scoops/Rescue the Professor/Complete Rescue the Professor",
    ["The Last Resort"]             = "@Main Scoops/Last Resort/Complete Bomb Collector",
    ["Professor's Past"]            = "@Main Scoops/Professor's Past/Complete Professors Past",
    ["Medicine Run"]                = "@Main Scoops/Medicine Run/Complete Medicine Run",
    ["Jessie's Discovery"]          = "@Main Scoops/Jessie's Discovery/Complete Jessie's Discovery"
}

-- Returns the 1-based index of the NEXT scoop that should be available
function getCurrentScoopPosition()
    if hasScoopSanity() == 0 then return 0 end

    local order = scoop_order_list
    if #order == 0 then return 0 end

    local progressed = 0
    for i, scoop_name in ipairs(order) do
        local path = SCOOP_TO_PATH[scoop_name]
        if path == nil then break end

        local obj = Tracker:FindObjectForCode(path)
        if obj == nil or obj.AvailableChestCount ~= 0 then
            break  -- this is the next one
        end
        progressed = i
    end

    return progressed + 1
end

-- Returns 1 if this scoop is the current next one in the chain
function isNextScoop(scoop_name)
    if hasScoopSanity() == 0 then
        return 1   -- not in Scoopsanity → all main scoops available normally
    end

    local next_pos = getCurrentScoopPosition()
    if next_pos == 0 then return 0 end

    return (scoop_order_list[next_pos] == scoop_name) and 1 or 0
end

-- PP Sticker Logic

local pp_areas = {
    -- Base area
    { keys = {"$hasParadiseAccess"}, value = 16 },

    -- Straight-line areas
    { keys = {"$hasLeisureAccess"},                                             value = 4 },
    { keys = {"$hasColbyAccess"},                                      value = 10 },
    { keys = {"$hasFoodAccess"},                                               value = 11 },
    { keys = {"$hasFrescaAccess"},                           value = 11 },
    { keys = {"$hasEntranceAccess"},       value = 10 },
    { keys = {"$hasNorthAccess"},                                              value = 9 },
    { keys = {"$hasCrislipsAccess"},                  value = 2 },
    { keys = {"$hasGroceryAccess"},                           value = 3 },
    { keys = {"$hasTunnelAccess"},                                       value = 7 },
    { keys = {"$hasWonderlandAccess"}, value = 15 },

    -- Mode-specific stickers
    { keys = { {"$hasScoopSanity", "leisureparkkey", "astrangegroup"}, {"$hasScoopSanity", "leisureparkkey", "thecult"} },             value = 2 },
    { keys = {"$hasRegularMode", "leisureparkkey", "day2_06_am", "day2_11_am"},                value = 2 },
}

function hasEnoughPPStickers(target)
    target = tonumber(target) or 0
    local total = 0

    for _, area in ipairs(pp_areas) do
        local can_access = false

        -- If keys is a table of tables → it's an OR group
        if type(area.keys[1]) == "table" then
            -- OR logic: any one of the sub-groups is enough
            for _, subgroup in ipairs(area.keys) do
                local subgroup_ok = true
                for _, key in ipairs(subgroup) do
                    if key:sub(1,1) == "$" then
                        local func = _G[key:sub(2)]
                        if not (func and func() == 1) then
                            subgroup_ok = false
                            break
                        end
                    else
                        if Tracker:ProviderCountForCode(key) == 0 then
                            subgroup_ok = false
                            break
                        end
                    end
                end
                if subgroup_ok then
                    can_access = true
                    break
                end
            end
        else
            -- Normal AND logic
            local all_ok = true
            for _, key in ipairs(area.keys) do
                if key:sub(1,1) == "$" then
                    local func = _G[key:sub(2)]
                    if not (func and func() == 1) then
                        all_ok = false
                        break
                    end
                else
                    if Tracker:ProviderCountForCode(key) == 0 then
                        all_ok = false
                        break
                    end
                end
            end
            can_access = all_ok
        end

        if can_access then
            total = total + area.value
        end
    end

    return (total >= target) and 1 or 0
end


-- ==================== AREA ACCESS FUNCTIONS ====================

function hasParadiseAccess()
    return Tracker:ProviderCountForCode("rooftopkey") > 0 and
           Tracker:ProviderCountForCode("servicehallwaykey") > 0 and
           Tracker:ProviderCountForCode("paradiseplazakey") > 0 and 1 or 0
end

function hasLeisureAccess()
    return Tracker:ProviderCountForCode("rooftopkey") > 0 and
           Tracker:ProviderCountForCode("servicehallwaykey") > 0 and
           Tracker:ProviderCountForCode("paradiseplazakey") > 0 and
           Tracker:ProviderCountForCode("leisureparkkey") > 0 and 1 or 0
end

function hasColbyAccess()
    return Tracker:ProviderCountForCode("rooftopkey") > 0 and
           Tracker:ProviderCountForCode("servicehallwaykey") > 0 and
           Tracker:ProviderCountForCode("paradiseplazakey") > 0 and
           Tracker:ProviderCountForCode("colbysmovietheaterkey") > 0 and 1 or 0
end

function hasTunnelAccess()
    -- Path 1: Normal way
    if Tracker:ProviderCountForCode("rooftopkey") > 0 and
       Tracker:ProviderCountForCode("servicehallwaykey") > 0 and
       Tracker:ProviderCountForCode("paradiseplazakey") > 0 and
       Tracker:ProviderCountForCode("leisureparkkey") > 0 and
       Tracker:ProviderCountForCode("maintenancetunnelkey") > 0 then
        return 1
    end
    -- Path 2: Alternative tunnel access
    if Tracker:ProviderCountForCode("rooftopkey") > 0 and
       Tracker:ProviderCountForCode("servicehallwaykey") > 0 and
       Tracker:ProviderCountForCode("paradiseplazakey") > 0 and
       Tracker:ProviderCountForCode("maintenancetunnelkey") > 0 and
       Tracker:ProviderCountForCode("maintenancetunnelaccesskey") > 0 then
        return 1
    end
    return 0
end

function hasFoodAccess()
    -- Path 1: Normal Leisure to Food Court
    if Tracker:ProviderCountForCode("rooftopkey") > 0 and
       Tracker:ProviderCountForCode("servicehallwaykey") > 0 and
       Tracker:ProviderCountForCode("paradiseplazakey") > 0 and
       Tracker:ProviderCountForCode("leisureparkkey") > 0 and
       Tracker:ProviderCountForCode("foodcourtkey") > 0 then
        return 1
    end
    -- Path 2: Tunnel alternative
    if Tracker:ProviderCountForCode("rooftopkey") > 0 and
       Tracker:ProviderCountForCode("servicehallwaykey") > 0 and
       Tracker:ProviderCountForCode("paradiseplazakey") > 0 and
       Tracker:ProviderCountForCode("maintenancetunnelkey") > 0 and
       Tracker:ProviderCountForCode("maintenancetunnelaccesskey") > 0 and
       Tracker:ProviderCountForCode("foodcourtkey") > 0 then
        return 1
    end
    -- Path 3: ScoopSanity alternative
    if hasScoopSanity() == 1 and
       Tracker:ProviderCountForCode("rooftopkey") > 0 and
       Tracker:ProviderCountForCode("servicehallwaykey") > 0 and
       Tracker:ProviderCountForCode("paradiseplazakey") > 0 and
       Tracker:ProviderCountForCode("entranceplazakey") > 0 and
       Tracker:ProviderCountForCode("alfrescaplazakey") > 0 and
       Tracker:ProviderCountForCode("foodcourtkey") > 0 then
        return 1
    end
    return 0
end

function hasNorthAccess()
    -- Path 1: Normal Leisure to North Plaza
    if Tracker:ProviderCountForCode("rooftopkey") > 0 and
       Tracker:ProviderCountForCode("servicehallwaykey") > 0 and
       Tracker:ProviderCountForCode("paradiseplazakey") > 0 and
       Tracker:ProviderCountForCode("leisureparkkey") > 0 and
       Tracker:ProviderCountForCode("northplazakey") > 0 then
        return 1
    end
    -- Path 2: Tunnel to Grocery to North
    if Tracker:ProviderCountForCode("rooftopkey") > 0 and
       Tracker:ProviderCountForCode("servicehallwaykey") > 0 and
       Tracker:ProviderCountForCode("paradiseplazakey") > 0 and
       Tracker:ProviderCountForCode("maintenancetunnelkey") > 0 and
       Tracker:ProviderCountForCode("maintenancetunnelaccesskey") > 0 and
       Tracker:ProviderCountForCode("grocerystorekey") > 0 and
       Tracker:ProviderCountForCode("northplazakey") > 0 then
        return 1
    end
    -- Path 3: Tunnel to Wonderland to North
    if Tracker:ProviderCountForCode("rooftopkey") > 0 and
       Tracker:ProviderCountForCode("servicehallwaykey") > 0 and
       Tracker:ProviderCountForCode("paradiseplazakey") > 0 and
       Tracker:ProviderCountForCode("maintenancetunnelkey") > 0 and
       Tracker:ProviderCountForCode("maintenancetunnelaccesskey") > 0 and
       Tracker:ProviderCountForCode("wonderlandplazakey") > 0 and
       Tracker:ProviderCountForCode("northplazakey") > 0 then
        return 1
    end
    -- Path 4: ScoopSanity alternative
    if hasScoopSanity() == 1 and
       Tracker:ProviderCountForCode("rooftopkey") > 0 and
       Tracker:ProviderCountForCode("servicehallwaykey") > 0 and
       Tracker:ProviderCountForCode("paradiseplazakey") > 0 and
       Tracker:ProviderCountForCode("entranceplazakey") > 0 and
       Tracker:ProviderCountForCode("alfrescaplazakey") > 0 and
       Tracker:ProviderCountForCode("foodcourtkey") > 0 and
       Tracker:ProviderCountForCode("wonderlandplazakey") > 0 and
       Tracker:ProviderCountForCode("northplazakey") > 0 then
        return 1
    end
    return 0
end

function hasFrescaAccess()
    -- Path 1: Normal Leisure to Food Court to Al Fresca
    if Tracker:ProviderCountForCode("rooftopkey") > 0 and
       Tracker:ProviderCountForCode("servicehallwaykey") > 0 and
       Tracker:ProviderCountForCode("paradiseplazakey") > 0 and
       Tracker:ProviderCountForCode("leisureparkkey") > 0 and
       Tracker:ProviderCountForCode("foodcourtkey") > 0 and
       Tracker:ProviderCountForCode("alfrescaplazakey") > 0 then
        return 1
    end
    -- Path 2: ScoopSanity direct
    if hasScoopSanity() == 1 and
       Tracker:ProviderCountForCode("rooftopkey") > 0 and
       Tracker:ProviderCountForCode("servicehallwaykey") > 0 and
       Tracker:ProviderCountForCode("paradiseplazakey") > 0 and
       Tracker:ProviderCountForCode("entranceplazakey") > 0 and
       Tracker:ProviderCountForCode("alfrescaplazakey") > 0 then
        return 1
    end
    -- Path 3: Tunnel alternatives
    if Tracker:ProviderCountForCode("rooftopkey") > 0 and
       Tracker:ProviderCountForCode("servicehallwaykey") > 0 and
       Tracker:ProviderCountForCode("paradiseplazakey") > 0 and
       Tracker:ProviderCountForCode("leisureparkkey") > 0 and
       Tracker:ProviderCountForCode("maintenancetunnelkey") > 0 and
       Tracker:ProviderCountForCode("alfrescaplazakey") > 0 then
        return 1
    end

    if Tracker:ProviderCountForCode("rooftopkey") > 0 and
       Tracker:ProviderCountForCode("servicehallwaykey") > 0 and
       Tracker:ProviderCountForCode("paradiseplazakey") > 0 and
       Tracker:ProviderCountForCode("maintenancetunnelkey") > 0 and
       Tracker:ProviderCountForCode("maintenancetunnelaccesskey") > 0 and
       Tracker:ProviderCountForCode("alfrescaplazakey") > 0 then
        return 1
    end
    return 0
end

function hasEntranceAccess()
    -- Path 1: Normal Leisure to Food Court to Alfresca to Entrance
    if Tracker:ProviderCountForCode("rooftopkey") > 0 and
       Tracker:ProviderCountForCode("servicehallwaykey") > 0 and
       Tracker:ProviderCountForCode("paradiseplazakey") > 0 and
       Tracker:ProviderCountForCode("leisureparkkey") > 0 and
       Tracker:ProviderCountForCode("foodcourtkey") > 0 and
       Tracker:ProviderCountForCode("alfrescaplazakey") > 0 and
       Tracker:ProviderCountForCode("entranceplazakey") > 0 then
        return 1
    end
    -- Path 2: Tunnel direct
    if Tracker:ProviderCountForCode("rooftopkey") > 0 and
       Tracker:ProviderCountForCode("servicehallwaykey") > 0 and
       Tracker:ProviderCountForCode("paradiseplazakey") > 0 and
       Tracker:ProviderCountForCode("leisureparkkey") > 0 and
       Tracker:ProviderCountForCode("maintenancetunnelkey") > 0 and
       Tracker:ProviderCountForCode("entranceplazakey") > 0 then
        return 1
    end
    -- Path 3: Tunnel + access key
    if Tracker:ProviderCountForCode("rooftopkey") > 0 and
       Tracker:ProviderCountForCode("servicehallwaykey") > 0 and
       Tracker:ProviderCountForCode("paradiseplazakey") > 0 and
       Tracker:ProviderCountForCode("maintenancetunnelkey") > 0 and
       Tracker:ProviderCountForCode("maintenancetunnelaccesskey") > 0 and
       Tracker:ProviderCountForCode("entranceplazakey") > 0 then
        return 1
    end
    -- Path 4: ScoopSanity direct
    if hasScoopSanity() == 1 and
       Tracker:ProviderCountForCode("rooftopkey") > 0 and
       Tracker:ProviderCountForCode("servicehallwaykey") > 0 and
       Tracker:ProviderCountForCode("paradiseplazakey") > 0 and
       Tracker:ProviderCountForCode("entranceplazakey") > 0 then
        return 1
    end
    return 0
end

function hasCrislipsAccess()
    -- Path 1: Normal Leisure to North to Crislips
    if Tracker:ProviderCountForCode("rooftopkey") > 0 and
       Tracker:ProviderCountForCode("servicehallwaykey") > 0 and
       Tracker:ProviderCountForCode("paradiseplazakey") > 0 and
       Tracker:ProviderCountForCode("leisureparkkey") > 0 and
       Tracker:ProviderCountForCode("northplazakey") > 0 and
       Tracker:ProviderCountForCode("crislipshardwarestorekey") > 0 then
        return 1
    end
    -- Path 2: Tunnel to Grocery to North to Crislips
    if Tracker:ProviderCountForCode("rooftopkey") > 0 and
       Tracker:ProviderCountForCode("servicehallwaykey") > 0 and
       Tracker:ProviderCountForCode("paradiseplazakey") > 0 and
       Tracker:ProviderCountForCode("maintenancetunnelkey") > 0 and
       Tracker:ProviderCountForCode("maintenancetunnelaccesskey") > 0 and
       Tracker:ProviderCountForCode("grocerystorekey") > 0 and
       Tracker:ProviderCountForCode("northplazakey") > 0 and
       Tracker:ProviderCountForCode("crislipshardwarestorekey") > 0 then
        return 1
    end
    -- Path 3: Tunnel to Wonderland to North to Crislips
    if Tracker:ProviderCountForCode("rooftopkey") > 0 and
       Tracker:ProviderCountForCode("servicehallwaykey") > 0 and
       Tracker:ProviderCountForCode("paradiseplazakey") > 0 and
       Tracker:ProviderCountForCode("maintenancetunnelkey") > 0 and
       Tracker:ProviderCountForCode("maintenancetunnelaccesskey") > 0 and
       Tracker:ProviderCountForCode("wonderlandplazakey") > 0 and
       Tracker:ProviderCountForCode("northplazakey") > 0 and
       Tracker:ProviderCountForCode("crislipshardwarestorekey") > 0 then
        return 1
    end
    -- Path 4: ScoopSanity alternative
    if hasScoopSanity() == 1 and
       Tracker:ProviderCountForCode("rooftopkey") > 0 and
       Tracker:ProviderCountForCode("servicehallwaykey") > 0 and
       Tracker:ProviderCountForCode("paradiseplazakey") > 0 and
       Tracker:ProviderCountForCode("entranceplazakey") > 0 and
       Tracker:ProviderCountForCode("alfrescaplazakey") > 0 and
       Tracker:ProviderCountForCode("foodcourtkey") > 0 and
       Tracker:ProviderCountForCode("wonderlandplazakey") > 0 and
       Tracker:ProviderCountForCode("northplazakey") > 0 and
       Tracker:ProviderCountForCode("crislipshardwarestorekey") > 0 then
        return 1
    end
    return 0
end

function hasGroceryAccess()
    -- Path 1: Normal Leisure to North to Grocery
    if Tracker:ProviderCountForCode("rooftopkey") > 0 and
       Tracker:ProviderCountForCode("servicehallwaykey") > 0 and
       Tracker:ProviderCountForCode("paradiseplazakey") > 0 and
       Tracker:ProviderCountForCode("leisureparkkey") > 0 and
       Tracker:ProviderCountForCode("northplazakey") > 0 and
       Tracker:ProviderCountForCode("grocerystorekey") > 0 then
        return 1
    end
    -- Path 2: Tunnel direct to Grocery
    if Tracker:ProviderCountForCode("rooftopkey") > 0 and
       Tracker:ProviderCountForCode("servicehallwaykey") > 0 and
       Tracker:ProviderCountForCode("paradiseplazakey") > 0 and
       Tracker:ProviderCountForCode("leisureparkkey") > 0 and
       Tracker:ProviderCountForCode("maintenancetunnelkey") > 0 and
       Tracker:ProviderCountForCode("grocerystorekey") > 0 then
        return 1
    end
    -- Path 3: Tunnel + access key to Grocery
    if Tracker:ProviderCountForCode("rooftopkey") > 0 and
       Tracker:ProviderCountForCode("servicehallwaykey") > 0 and
       Tracker:ProviderCountForCode("paradiseplazakey") > 0 and
       Tracker:ProviderCountForCode("maintenancetunnelkey") > 0 and
       Tracker:ProviderCountForCode("maintenancetunnelaccesskey") > 0 and
       Tracker:ProviderCountForCode("grocerystorekey") > 0 then
        return 1
    end
    -- Path 4: ScoopSanity alternative
    if hasScoopSanity() == 1 and
       Tracker:ProviderCountForCode("rooftopkey") > 0 and
       Tracker:ProviderCountForCode("servicehallwaykey") > 0 and
       Tracker:ProviderCountForCode("paradiseplazakey") > 0 and
       Tracker:ProviderCountForCode("entranceplazakey") > 0 and
       Tracker:ProviderCountForCode("alfrescaplazakey") > 0 and
       Tracker:ProviderCountForCode("foodcourtkey") > 0 and
       Tracker:ProviderCountForCode("wonderlandplazakey") > 0 and
       Tracker:ProviderCountForCode("northplazakey") > 0 and
       Tracker:ProviderCountForCode("grocerystorekey") > 0 then
        return 1
    end
    return 0
end

function hasWonderlandAccess()
    -- Path 1: Food Court to Wonderland
    if Tracker:ProviderCountForCode("rooftopkey") > 0 and
       Tracker:ProviderCountForCode("servicehallwaykey") > 0 and
       Tracker:ProviderCountForCode("paradiseplazakey") > 0 and
       Tracker:ProviderCountForCode("leisureparkkey") > 0 and
       Tracker:ProviderCountForCode("foodcourtkey") > 0 and
       Tracker:ProviderCountForCode("wonderlandplazakey") > 0 then
        return 1
    end
    -- Path 2: North Plaza to Wonderland
    if Tracker:ProviderCountForCode("rooftopkey") > 0 and
       Tracker:ProviderCountForCode("servicehallwaykey") > 0 and
       Tracker:ProviderCountForCode("paradiseplazakey") > 0 and
       Tracker:ProviderCountForCode("leisureparkkey") > 0 and
       Tracker:ProviderCountForCode("northplazakey") > 0 and
       Tracker:ProviderCountForCode("wonderlandplazakey") > 0 then
        return 1
    end
    -- Path 3: Tunnel direct
    if Tracker:ProviderCountForCode("rooftopkey") > 0 and
       Tracker:ProviderCountForCode("servicehallwaykey") > 0 and
       Tracker:ProviderCountForCode("paradiseplazakey") > 0 and
       Tracker:ProviderCountForCode("leisureparkkey") > 0 and
       Tracker:ProviderCountForCode("maintenancetunnelkey") > 0 and
       Tracker:ProviderCountForCode("wonderlandplazakey") > 0 then
        return 1
    end
    -- Path 4: Tunnel + access key
    if Tracker:ProviderCountForCode("rooftopkey") > 0 and
       Tracker:ProviderCountForCode("servicehallwaykey") > 0 and
       Tracker:ProviderCountForCode("paradiseplazakey") > 0 and
       Tracker:ProviderCountForCode("maintenancetunnelkey") > 0 and
       Tracker:ProviderCountForCode("maintenancetunnelaccesskey") > 0 and
       Tracker:ProviderCountForCode("wonderlandplazakey") > 0 then
        return 1
    end
    -- Path 5: ScoopSanity alternative
    if hasScoopSanity() == 1 and
       Tracker:ProviderCountForCode("rooftopkey") > 0 and
       Tracker:ProviderCountForCode("servicehallwaykey") > 0 and
       Tracker:ProviderCountForCode("paradiseplazakey") > 0 and
       Tracker:ProviderCountForCode("entranceplazakey") > 0 and
       Tracker:ProviderCountForCode("alfrescaplazakey") > 0 and
       Tracker:ProviderCountForCode("foodcourtkey") > 0 and
       Tracker:ProviderCountForCode("wonderlandplazakey") > 0 then
        return 1
    end
    return 0
end


-- ==================== SCOOP ACCESS FUNCTIONS ====================

-- Barricade Pair Scoop Access
function hasBarricadeScoop()
    -- Path 1: ScoopSanity
    if hasFrescaAccess() == 1 and
       hasScoopSanity() == 1 and
       Tracker:ProviderCountForCode("barricadepair") > 0 then
        return 1
    end
    
    -- Path 2: Regular mode
    if hasFrescaAccess() == 1 and
       hasRegularMode() == 1 then
        return 1
    end
    return 0
end

-- Mother's Lament Scoop Access
function hasMothersScoop()
    -- Path 1: ScoopSanity
    if hasFrescaAccess() == 1 and
       hasScoopSanity() == 1 and
       Tracker:ProviderCountForCode("amotherslament") > 0 then
        return 1
    end
    
    -- Path 2: Regular mode
    if hasFrescaAccess() == 1 and
       hasRegularMode() == 1 then
        return 1
    end
    return 0
end

-- The Coward Scoop Access
function hasCowardScoop()
    -- Path 1: ScoopSanity
    if hasFrescaAccess() == 1 and
       hasScoopSanity() == 1 and
       Tracker:ProviderCountForCode("thecoward") > 0 then
        return 1
    end
    
    -- Path 2: Regular mode
    if hasFrescaAccess() == 1 and
       hasRegularMode() == 1 and
       Tracker:ProviderCountForCode("day2_06_am") > 0 then
        return 1
    end
    return 0
end

-- Antique Lover Scoop Access
function hasAntiqueScoop()
    -- Path 1: ScoopSanity
    if hasEntranceAccess() == 1 and
       hasScoopSanity() == 1 and
       Tracker:ProviderCountForCode("antiquelover") > 0 then
        return 1
    end
    
    -- Path 2: Regular mode
    if hasEntranceAccess() == 1 and
       hasRegularMode() == 1 and
       Tracker:ProviderCountForCode("day2_06_am") > 0 and
       Tracker:ProviderCountForCode("day2_11_am") > 0 then
        return 1
    end
    return 0
end

-- The Woman Who Didn't Make It Scoop Access
function hasWomanScoop()
    -- Path 1: ScoopSanity
    if hasEntranceAccess() == 1 and
       hasScoopSanity() == 1 and
       Tracker:ProviderCountForCode("thewomanwhodidntmakeit") > 0 then
        return 1
    end
    
    -- Path 2: Regular mode
    if hasEntranceAccess() == 1 and
       hasRegularMode() == 1 and
       Tracker:ProviderCountForCode("day2_06_am") > 0 and
       Tracker:ProviderCountForCode("day2_11_am") > 0 then
        return 1
    end
    return 0
end

-- Man in a Bind Scoop Access
function hasBindScoop()
    return hasEntranceAccess()
end

-- Mark of the Sniper Scoop Access
function hasSniperScoop()
    -- Path 1: ScoopSanity
    if hasEntranceAccess() == 1 and
       hasScoopSanity() == 1 and
       Tracker:ProviderCountForCode("markofthesniper") > 0 then
        return 1
    end
    
    -- Path 2: Regular mode
    if hasEntranceAccess() == 1 and
       hasRegularMode() == 1 and
       Tracker:ProviderCountForCode("day2_06_am") > 0 and
       Tracker:ProviderCountForCode("day2_11_am") > 0 then
        return 1
    end
    return 0
end

-- Out of Control Scoop Access
function hasControlScoop()
    -- Path 1: ScoopSanity
    if hasWonderlandAccess() == 1 and
       hasScoopSanity() == 1 and
       Tracker:ProviderCountForCode("outofcontrol") > 0 then
        return 1
    end
    
    -- Path 2: Regular mode
    if hasWonderlandAccess() == 1 and
       hasRegularMode() == 1 then
        return 1
    end
    return 0
end

-- Long Haired Punk Scoop Access
function hasPunkScoop()
    -- Path 1: ScoopSanity
    if hasWonderlandAccess() == 1 and
       hasScoopSanity() == 1 and
       Tracker:ProviderCountForCode("longhairedpunk") > 0 then
        return 1
    end
    
    -- Path 2: Regular mode
    if hasWonderlandAccess() == 1 and
       hasRegularMode() == 1 and
       Tracker:ProviderCountForCode("day2_06_am") > 0 and
       Tracker:ProviderCountForCode("day2_11_am") > 0 and
       Tracker:ProviderCountForCode("day3_00_am") > 0 then
        return 1
    end
    return 0
end

-- Paul Carson Scoop Access
function hasCarsonScoop()
    -- Path 1: ScoopSanity and normal items
    if hasWonderlandAccess() == 1 and
       hasScoopSanity() == 1 and
       hasNormalItems() == 1 and
       Tracker:ProviderCountForCode("longhairedpunk") > 0 then
        return 1
    end
    
    -- Path 2: Regular mode and normal items
    if hasWonderlandAccess() == 1 and
       hasRegularMode() == 1 and
       hasNormalItems() == 1 and
       Tracker:ProviderCountForCode("day2_06_am") > 0 and
       Tracker:ProviderCountForCode("day2_11_am") > 0 and
       Tracker:ProviderCountForCode("day3_00_am") > 0 then
        return 1
    end
    
    -- Path 3: ScoopSanity and restricted items
    if hasWonderlandAccess() == 1 and
       hasScoopSanity() == 1 and
       hasRestrictedItems() == 1 and
       Tracker:ProviderCountForCode("fireextinguisher") > 0 and
       Tracker:ProviderCountForCode("longhairedpunk") > 0 then
        return 1
    end
    
    -- Path 4: Regular mode and restricted items
    if hasWonderlandAccess() == 1 and
       hasRegularMode() == 1 and
       hasRestrictedItems() == 1 and
       Tracker:ProviderCountForCode("fireextinguisher") > 0 and
       Tracker:ProviderCountForCode("day2_06_am") > 0 and
       Tracker:ProviderCountForCode("day2_11_am") > 0 and
       Tracker:ProviderCountForCode("day3_00_am") > 0 then
        return 1
    end
    return 0
end

-- Japanese Tourists Scoop Access
function hasTouristScoop()
    -- Path 1: ScoopSanity and normal items
    if hasWonderlandAccess() == 1 and
       hasScoopSanity() == 1 and
       hasNormalItems() == 1 and
       Tracker:ProviderCountForCode("japanesetourists") > 0 then
        return 1
    end
    
    -- Path 2: Regular mode and normal items
    if hasWonderlandAccess() == 1 and
       hasRegularMode() == 1 and
       hasNormalItems() == 1 then
        return 1
    end

    -- Path 3: ScoopSanity and restricted items
    if hasWonderlandAccess() == 1 and
       hasScoopSanity() == 1 and
       hasRestrictedItems() == 1 and
       Tracker:ProviderCountForCode("bookjapaneseconversation") > 0 and
       Tracker:ProviderCountForCode("japanesetourists") > 0 then
        return 1
    end
    
    -- Path 4: Regular mode and restricted items
    if hasWonderlandAccess() == 1 and
       hasRegularMode() == 1 and
       hasRestrictedItems() == 1 and
       Tracker:ProviderCountForCode("bookjapaneseconversation") > 0 then
        return 1
    end
    return 0
end

-- The Woman Left Behind Scoop Access
function hasBehindScoop()
    -- Path 1: ScoopSanity
    if hasWonderlandAccess() == 1 and
       hasScoopSanity() == 1 and
       Tracker:ProviderCountForCode("thewomanleftbehind") > 0 then
        return 1
    end
    
    -- Path 2: Regular mode
    if hasWonderlandAccess() == 1 and
       hasRegularMode() == 1 and
       Tracker:ProviderCountForCode("day2_06_am") > 0 and
       Tracker:ProviderCountForCode("day2_11_am") > 0 and
       Tracker:ProviderCountForCode("day3_00_am") > 0 then
        return 1
    end
    return 0
end

-- A Sick Man Scoop Access
function hasSickScoop()
    -- Path 1: ScoopSanity
    if hasWonderlandAccess() == 1 and
       hasScoopSanity() == 1 and
       Tracker:ProviderCountForCode("asickman") > 0 then
        return 1
    end
    
    -- Path 2: Regular mode
    if hasWonderlandAccess() == 1 and
       hasRegularMode() == 1 and
       Tracker:ProviderCountForCode("day2_06_am") > 0 and
       Tracker:ProviderCountForCode("day2_11_am") > 0 and
       Tracker:ProviderCountForCode("day3_00_am") > 0 then
        return 1
    end
    return 0
end

-- Above the Law Scoop Access
function hasLawScoop()
    -- Path 1: ScoopSanity
    if hasWonderlandAccess() == 1 and
       hasScoopSanity() == 1 and
       Tracker:ProviderCountForCode("abovethelaw") > 0 then
        return 1
    end
    
    -- Path 2: Regular mode
    if hasWonderlandAccess() == 1 and
       hasRegularMode() == 1 and
       Tracker:ProviderCountForCode("day2_06_am") > 0 and
       Tracker:ProviderCountForCode("day2_11_am") > 0 then
        return 1
    end
    return 0
end

-- Hanging by a Thread Scoop Access
function hasHangingScoop()
    -- Path 1: ScoopSanity
    if hasWonderlandAccess() == 1 and
       hasScoopSanity() == 1 and
       Tracker:ProviderCountForCode("hangingbyathread") > 0 then
        return 1
    end
    
    -- Path 2: Regular mode
    if hasWonderlandAccess() == 1 and
       hasRegularMode() == 1 and
       Tracker:ProviderCountForCode("day2_06_am") > 0 and
       Tracker:ProviderCountForCode("day2_11_am") > 0 then
        return 1
    end
    return 0
end

-- Lovers Scoop Access
function hasLoversScoop()
    -- Path 1: ScoopSanity
    if hasWonderlandAccess() == 1 and
       hasScoopSanity() == 1 and
       Tracker:ProviderCountForCode("lovers") > 0 then
        return 1
    end
    
    -- Path 2: Regular mode
    if hasWonderlandAccess() == 1 and
       hasRegularMode() == 1 and
       Tracker:ProviderCountForCode("day2_06_am") > 0 then
        return 1
    end
    return 0
end

-- The Cult Scoop Access
function hasCultScoop()
    -- Path 1: ScoopSanity
    if hasParadiseAccess() == 1 and
       hasScoopSanity() == 1 and
       Tracker:ProviderCountForCode("thecult") > 0 then
        return 1
    end
    
    -- Path 2: Regular mode
    if hasParadiseAccess() == 1 and
       hasRegularMode() == 1 and
       Tracker:ProviderCountForCode("day2_06_am") > 0 and
       Tracker:ProviderCountForCode("day2_11_am") > 0 then
        return 1
    end
    return 0
end

-- A Woman in Despair Scoop Access
function hasDespairScoop()
    -- Path 1: ScoopSanity
    if hasParadiseAccess() == 1 and
       hasScoopSanity() == 1 and
       Tracker:ProviderCountForCode("awomanindespair") > 0 then
        return 1
    end
    
    -- Path 2: Regular mode
    if hasParadiseAccess() == 1 and
       hasRegularMode() == 1 and
       Tracker:ProviderCountForCode("day2_06_am") > 0 and
       Tracker:ProviderCountForCode("day2_11_am") > 0 and
       Tracker:ProviderCountForCode("day3_00_am") > 0 and
       Tracker:ProviderCountForCode("day3_11_am") > 0 then
        return 1
    end
    return 0
end

-- Twin Sisters Scoop Access
function hasSistersScoop()
    -- Path 1: ScoopSanity
    if hasParadiseAccess() == 1 and
       hasScoopSanity() == 1 and
       Tracker:ProviderCountForCode("twinsisters") > 0 then
        return 1
    end
    
    -- Path 2: Regular mode
    if hasParadiseAccess() == 1 and
       hasRegularMode() == 1 and
       Tracker:ProviderCountForCode("day2_06_am") > 0 and
       Tracker:ProviderCountForCode("day2_11_am") > 0 then
        return 1
    end
    return 0
end

-- Restaurant Man Scoop Access
function hasRestaurantScoop()
    -- Path 1: ScoopSanity and normal items
    if hasParadiseAccess() == 1 and
       hasScoopSanity() == 1 and
       hasNormalItems() == 1 and
       Tracker:ProviderCountForCode("restaurantman") > 0 then
        return 1
    end
    
    -- Path 2: Regular mode and normal items
    if hasParadiseAccess() == 1 and
       hasRegularMode() == 1 and
       hasNormalItems() == 1 and
       Tracker:ProviderCountForCode("day2_06_am") > 0 and
       Tracker:ProviderCountForCode("day2_11_am") > 0 then
        return 1
    end
    
    -- Path 3: ScoopSanity and restricted items
    if hasParadiseAccess() == 1 and
       hasScoopSanity() == 1 and
       hasRestrictedItems() == 1 and
       Tracker:ProviderCountForCode("orangejuice") > 0 and
       Tracker:ProviderCountForCode("restaurantman") > 0 then
        return 1
    end
    
    -- Path 4: Regular mode and restricted items
    if hasParadiseAccess() == 1 and
       hasRegularMode() == 1 and
       hasRestrictedItems() == 1 and
       Tracker:ProviderCountForCode("orangejuice") > 0 and
       Tracker:ProviderCountForCode("day2_06_am") > 0 and
       Tracker:ProviderCountForCode("day2_11_am") > 0 then
        return 1
    end
    return 0
end

-- Photographer's Pride Scoop Access
function hasPrideScoop()
    -- Path 1: ScoopSanity
    if hasParadiseAccess() == 1 and
       hasScoopSanity() == 1 and
       Tracker:ProviderCountForCode("cutfromthesamecloth") > 0 and
       Tracker:ProviderCountForCode("photochallenge") > 0 and
       Tracker:ProviderCountForCode("photographerspride") > 0 then
        return 1
    end
    
    -- Path 2: Regular mode
    if hasParadiseAccess() == 1 and
       hasRegularMode() == 1 and
       Tracker:ProviderCountForCode("day2_06_am") > 0 and
       Tracker:ProviderCountForCode("day2_11_am") > 0 and
       Tracker:ProviderCountForCode("day3_00_am") > 0 and
       Tracker:ProviderCountForCode("day3_11_am") > 0 then
        return 1
    end
    return 0
end

-- A Strange Group Scoop Access
function hasStrangeScoop()
    -- Path 1: ScoopSanity
    if hasColbyAccess() == 1 and
       hasScoopSanity() == 1 and
       Tracker:ProviderCountForCode("astrangegroup") > 0 then
        return 1
    end
    
    -- Path 2: Regular mode
    if hasColbyAccess() == 1 and
       hasRegularMode() == 1 and
       Tracker:ProviderCountForCode("day2_06_am") > 0 and
       Tracker:ProviderCountForCode("day2_11_am") > 0 and
       Tracker:ProviderCountForCode("day3_00_am") > 0 then
        return 1
    end
    return 0
end

-- The Convicts Scoop Access
function hasConvictsScoop()
    -- Path 1: ScoopSanity
    if hasLeisureAccess() == 1 and
       hasScoopSanity() == 1 and
       Tracker:ProviderCountForCode("theconvicts") > 0 then
        return 1
    end
    
    -- Path 2: Regular mode
    if hasLeisureAccess() == 1 and
       hasRegularMode() == 1 then
        return 1
    end
    return 0
end

-- The Hatchet Man Scoop Access
function hasHatchetScoop()
    -- Path 1: ScoopSanity
    if hasCrislipsAccess() == 1 and
       hasScoopSanity() == 1 and
       Tracker:ProviderCountForCode("thehatchetman") > 0 then
        return 1
    end
    
    -- Path 2: Regular mode
    if hasCrislipsAccess() == 1 and
       hasRegularMode() == 1 and
       Tracker:ProviderCountForCode("day2_06_am") > 0 then
        return 1
    end
    return 0
end

-- Dressed for Action Scoop Access
function hasDressedScoop()
    -- Path 1: ScoopSanity
    if hasNorthAccess() == 1 and
       hasScoopSanity() == 1 and
       Tracker:ProviderCountForCode("dressedforaction") > 0 then
        return 1
    end
    
    -- Path 2: Regular mode
    if hasNorthAccess() == 1 and
       hasRegularMode() == 1 and
       Tracker:ProviderCountForCode("day2_06_am") > 0 and
       Tracker:ProviderCountForCode("day2_11_am") > 0 and
       Tracker:ProviderCountForCode("day3_00_am") > 0 then
        return 1
    end
    return 0
end

-- Shadow of the North Plaza Scoop Access
function hasShadowScoop()
    -- Path 1: ScoopSanity
    if hasNorthAccess() == 1 and
       hasScoopSanity() == 1 and
       Tracker:ProviderCountForCode("shadowofthenorthplaza") > 0 then
        return 1
    end
    
    -- Path 2: Regular mode
    if hasNorthAccess() == 1 and
       hasRegularMode() == 1 then
        return 1
    end
    return 0
end

-- Gun Shop Standoff Scoop Access
function hasStandoffScoop()
    -- Path 1: ScoopSanity
    if hasNorthAccess() == 1 and
       hasScoopSanity() == 1 and
       Tracker:ProviderCountForCode("gunshopstandoff") > 0 then
        return 1
    end
    
    -- Path 2: Regular mode
    if hasNorthAccess() == 1 and
       hasRegularMode() == 1 and
       Tracker:ProviderCountForCode("day2_06_am") > 0 and
       Tracker:ProviderCountForCode("day2_11_am") > 0 and
       Tracker:ProviderCountForCode("day3_00_am") > 0 then
        return 1
    end
    return 0
end

-- Cletus Scoop Access
function hasCletusScoop()
    -- Path 1: ScoopSanity
    if hasNorthAccess() == 1 and
       hasScoopSanity() == 1 and
       Tracker:ProviderCountForCode("cletus") > 0 then
        return 1
    end
    
    -- Path 2: Regular mode
    if hasNorthAccess() == 1 and
       hasRegularMode() == 1 then
        return 1
    end
    return 0
end

-- The Drunkard Scoop Access
function hasDrunkardScoop()
    -- Path 1: ScoopSanity
    if hasFoodAccess() == 1 and
       hasScoopSanity() == 1 and
       Tracker:ProviderCountForCode("thedrunkard") > 0 then
        return 1
    end
    
    -- Path 2: Regular mode
    if hasFoodAccess() == 1 and
       hasRegularMode() == 1 and
       Tracker:ProviderCountForCode("day2_06_am") > 0 and
       Tracker:ProviderCountForCode("day2_11_am") > 0 and
       Tracker:ProviderCountForCode("day3_00_am") > 0 then
        return 1
    end
    return 0
end

-- Love Lasts a Lifetime Scoop Access
function hasLifetimeScoop()
    -- Always available
    return Tracker:ProviderCountForCode("rooftopkey") > 0 and 1 or 0
end


function hasTotalSurvivors(target)
    target = tonumber(target) or 0
    local count = 0

    if hasLifetimeScoop() == 1 then count = count + 2 end
    if hasBarricadeScoop() == 1 then count = count + 2 end
    if hasMothersScoop() == 1 then count = count + 1 end
    if hasCowardScoop() == 1 then count = count + 1 end
    if hasAntiqueScoop() == 1 then count = count + 1 end
    if hasWomanScoop() == 1 then count = count + 2 end
    if hasBindScoop() == 1 then count = count + 1 end
    if hasSniperScoop() == 1 then count = count + 1 end
    if hasControlScoop() == 1 then count = count + 1 end
    if hasPunkScoop() == 1 then count = count + 2 end
    if hasCarsonScoop() == 1 then count = count + 1 end
    if hasTouristScoop() == 1 then count = count + 2 end
    if hasBehindScoop() == 1 then count = count + 1 end
    if hasSickScoop() == 1 then count = count + 1 end
    if hasLawScoop() == 1 then count = count + 4 end
    if hasHangingScoop() == 1 then count = count + 2 end
    if hasLoversScoop() == 1 then count = count + 2 end
    if hasCultScoop() == 1 then count = count + 1 end
    if hasDespairScoop() == 1 then count = count + 1 end
    if hasSistersScoop() == 1 then count = count + 2 end
    if hasRestaurantScoop() == 1 then count = count + 1 end
    if hasPrideScoop() == 1 then count = count + 1 end
    if hasStrangeScoop() == 1 then count = count + 5 end
    if hasConvictsScoop() == 1 then count = count + 1 end
    if hasHatchetScoop() == 1 then count = count + 3 end
    if hasDressedScoop() == 1 then count = count + 1 end
    if hasShadowScoop() == 1 then count = count + 1 end
    if hasStandoffScoop() == 1 then count = count + 3 end
    if hasDrunkardScoop() == 1 then count = count + 1 end

    return (count >= target) and 1 or 0
end

function hasEscortSurvivors(target)
    target = tonumber(target) or 0
    local count = 0

    if hasBarricadeScoop() == 1 then count = count + 2 end
    if hasMothersScoop() == 1 then count = count + 1 end
    if hasCowardScoop() == 1 then count = count + 1 end
    if hasAntiqueScoop() == 1 then count = count + 1 end
    if hasWomanScoop() == 1 then count = count + 2 end
    if hasBindScoop() == 1 then count = count + 1 end
    if hasSniperScoop() == 1 then count = count + 1 end
    if hasControlScoop() == 1 then count = count + 1 end
    if hasPunkScoop() == 1 then count = count + 2 end
    if hasCarsonScoop() == 1 then count = count + 1 end
    if hasTouristScoop() == 1 then count = count + 2 end
    if hasBehindScoop() == 1 then count = count + 1 end
    if hasSickScoop() == 1 then count = count + 1 end
    if hasLawScoop() == 1 then count = count + 4 end
    if hasHangingScoop() == 1 then count = count + 2 end
    if hasLoversScoop() == 1 then count = count + 2 end
    if hasCultScoop() == 1 then count = count + 1 end
    if hasDespairScoop() == 1 then count = count + 1 end
    if hasSistersScoop() == 1 then count = count + 2 end
    if hasRestaurantScoop() == 1 then count = count + 1 end
    if hasPrideScoop() == 1 then count = count + 1 end
    if hasStrangeScoop() == 1 then count = count + 5 end
    if hasConvictsScoop() == 1 then count = count + 1 end
    if hasHatchetScoop() == 1 then count = count + 3 end
    if hasDressedScoop() == 1 then count = count + 1 end
    if hasShadowScoop() == 1 then count = count + 1 end
    if hasStandoffScoop() == 1 then count = count + 3 end
    if hasDrunkardScoop() == 1 then count = count + 1 end

    return (count >= target) and 1 or 0
end

function hasFemaleSurvivors(target)
    target = tonumber(target) or 0
    local count = 0

    if hasMothersScoop() == 1 then count = count + 1 end
    if hasWomanScoop() == 1 then count = count + 2 end
    if hasPunkScoop() == 1 then count = count + 2 end
    if hasBehindScoop() == 1 then count = count + 1 end
    if hasLawScoop() == 1 then count = count + 4 end
    if hasHangingScoop() == 1 then count = count + 1 end
    if hasLoversScoop() == 1 then count = count + 1 end
    if hasCultScoop() == 1 then count = count + 1 end
    if hasDespairScoop() == 1 then count = count + 1 end
    if hasSistersScoop() == 1 then count = count + 2 end
    if hasStrangeScoop() == 1 then count = count + 3 end
    if hasConvictsScoop() == 1 then count = count + 1 end
    if hasHatchetScoop() == 1 then count = count + 1 end
    if hasStandoffScoop() == 1 then count = count + 1 end

    return (count >= target) and 1 or 0
end

function hasPsychoCount(target)
    target = tonumber(target) or 0
    local count = 0

    if hasSniperScoop() == 1 then count = count + 3 end
    if hasControlScoop() == 1 then count = count + 1 end
    if hasPunkScoop() == 1 then count = count + 1 end
    if hasLawScoop() == 1 then count = count + 1 end
    if hasPrideScoop() == 1 then count = count + 1 end
    if hasStrangeScoop() == 1 then count = count + 1 end
    if hasHatchetScoop() == 1 then count = count + 1 end
    if hasCletusScoop() == 1 then count = count + 1 end

    return (count >= target) and 1 or 0
end


-- Returns 1 if the player has completed ANY main scoop OR has started Hideout / The Last Resort
function hasAnyMainScoopCompleted()
    if hasScoopSanity() == 0 then
        return 1
    end

    local order = scoop_order_list
    if #order == 0 then return 0 end

    local first_scoop = order[1]
    if first_scoop == nil then return 0 end

    -- Special case: If Hideout or The Last Resort is first in the order,
    -- check if the player has received the scoop item itself
    if first_scoop == "Hideout" then
        if Tracker:ProviderCountForCode("hideout") > 0 then
            return 1
        end
    elseif first_scoop == "The Last Resort" then
        if Tracker:ProviderCountForCode("thelastresort") > 0 then
            return 1
        end
    end

    -- Normal case: Check if the first scoop has been completed
    local path = SCOOP_TO_PATH[first_scoop]
    if path then
        local obj = Tracker:FindObjectForCode(path)
        if obj and obj.AvailableChestCount == 0 then
            return 1
        end
    end

    return 0
end