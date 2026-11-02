local function InspectSpeed()
    print("=== [SPEED INSPECTOR START] ===")
    local managers = {
        "CPP_BtlGameSpeedManager",
        "BtlGameSpeedManager",
        "CPP_BtlManager",
        "CPP_BattleManager",
        "CPP_MuchaGameInstance",
        "MuchaGameInstance"
    }

    for _, name in ipairs(managers) do
        local obj = FindFirstOf(name)
        if obj and obj:IsValid() then
            print("[SPEED INSPECTOR] Found: " .. obj:GetFullName())
            pcall(function()
                -- Dump properties if possible or check known speed fields
                for _, prop in ipairs({"Speed", "GameSpeed", "BtlSpeed", "BattleSpeed", "SpeedRate", "TimeDilation", "CurrentSpeed", "PlayRate"}) do
                    if obj[prop] ~= nil then
                        print(string.format("   %s = %s", prop, tostring(obj[prop])))
                    end
                end
            end)
        else
            print("[SPEED INSPECTOR] Not found: " .. name)
        end
    end
    print("=== [SPEED INSPECTOR END] ===")
end

InspectSpeed()
