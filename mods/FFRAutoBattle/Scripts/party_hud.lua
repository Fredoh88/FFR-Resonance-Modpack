-- Seamless Natural Party HUD for Final Fantasy Resonance
-- 1. Cleans names to keep them pristine and prevent any text overflow / collisions
-- 2. Discovers and formats HP & MP gauge readouts into smooth, visually pleasing stats (Current / Max)
-- 3. Dumps live widget tree to tb_dump.txt for exact telemetry mapping

local M = {}

local function fmtNum(n)
    if not n then return "0" end
    local s = tostring(math.floor(math.abs(n)))
    local formatted = s:reverse():gsub("(%d%d%d)", "%1,"):reverse():gsub("^,", "")
    if n < 0 then return "-" .. formatted end
    return formatted
end

local KNOWN_HEROES = {
    ["rain"] = true, ["lasswell"] = true, ["fina"] = true, ["lid"] = true,
    ["nichol"] = true, ["sakura"] = true, ["jake"] = true, ["dark fina"] = true,
    ["archwitch fina"] = true, ["raegen"] = true, ["sieghard"] = true, ["folka"] = true
}

local dumpDone = false

function M.tick(allies, statFn, paramOfFn, unitNameFn, brokenFn)
    pcall(function()
        local allTBs = FindAllOf("TextBlock")
        if not allTBs or #allTBs == 0 then return end

        -- Build live ally stats table
        local allyStats = {}
        if allies and #allies > 0 and statFn and unitNameFn then
            for _, uid in ipairs(allies) do
                local name = unitNameFn(uid)
                if name and name ~= "" then
                    local curHp = statFn(uid, 1, false) or 0
                    local maxHp = statFn(uid, 1, true) or 1
                    local curMp = statFn(uid, 2, false) or 0
                    local maxMp = statFn(uid, 2, true) or 1
                    local curLb = statFn(uid, 4, false) or 0
                    local maxLb = statFn(uid, 4, true) or 100
                    if maxLb <= 0 then maxLb = 100 end

                    local hpPct = math.floor((curHp / maxHp) * 100 + 0.5)
                    local mpPct = math.floor((curMp / maxMp) * 100 + 0.5)

                    allyStats[name:lower()] = {
                        uid = uid,
                        name = name,
                        curHp = curHp,
                        maxHp = maxHp,
                        hpPct = hpPct,
                        curMp = curMp,
                        maxMp = maxMp,
                        mpPct = mpPct,
                    }
                end
            end
        end

        local dumpLines = {}
        if not dumpDone then
            dumpLines[#dumpLines + 1] = string.format("=== TEXTBLOCK SCAN: %d WIDGETS ===", #allTBs)
        end

        -- Pass 1: Clean any modified/clunky name TextBlocks immediately
        for i, tb in ipairs(allTBs) do
            if tb and tb:IsValid() then
                local okTxt, rawText = pcall(function() return tb:GetText():ToString() end)
                if okTxt and rawText and #rawText > 0 then
                    -- Extract pure character name
                    local clean = rawText:gsub("%s*%(Lv%.%d+%)", ""):gsub("%s*%[.-%]", ""):gsub("^%s+", ""):gsub("%s+$", "")
                    if KNOWN_HEROES[clean:lower()] then
                        -- Restore pristine character name with ZERO overflow
                        if rawText ~= clean then
                            pcall(function() tb:SetText(FText(clean)) end)
                        end
                    end

                    if not dumpDone and #rawText < 100 then
                        local parClass, outerClass = "none", "none"
                        pcall(function() parClass = tb:GetParent():GetClass():GetFName():ToString() end)
                        pcall(function() outerClass = tb:GetOuter():GetClass():GetFName():ToString() end)
                        dumpLines[#dumpLines + 1] = string.format("  [%d] '%s' | Parent: %s | Outer: %s", i, rawText, parClass, outerClass)
                    end
                end
            end
        end

        -- Pass 2: Smooth HP/MP gauge formatting
        -- For each ally, find their HP and MP value TextBlocks and format them cleanly as "Current / Max"
        for _, tb in ipairs(allTBs) do
            if tb and tb:IsValid() then
                local okTxt, rawText = pcall(function() return tb:GetText():ToString() end)
                if okTxt and rawText and #rawText > 0 and not rawText:find("/") then
                    local cleanDigits = rawText:gsub(",", ""):gsub("%s+", "")
                    local numVal = tonumber(cleanDigits)

                    if numVal and numVal > 0 then
                        for _, data in pairs(allyStats) do
                            -- Match HP TextBlock
                            if numVal == data.curHp and data.maxHp > 0 then
                                local wantHp = (data.hpPct < 100)
                                    and string.format("%s/%s (%d%%)", fmtNum(data.curHp), fmtNum(data.maxHp), data.hpPct)
                                    or  string.format("%s/%s", fmtNum(data.curHp), fmtNum(data.maxHp))

                                if rawText ~= wantHp then
                                    pcall(function() tb:SetText(FText(wantHp)) end)
                                end
                                break
                            -- Match MP TextBlock
                            elseif numVal == data.curMp and data.maxMp > 0 and data.maxMp < 1000 then
                                local wantMp = string.format("%s/%s", fmtNum(data.curMp), fmtNum(data.maxMp))
                                if rawText ~= wantMp then
                                    pcall(function() tb:SetText(FText(wantMp)) end)
                                end
                                break
                            end
                        end
                    end
                end
            end
        end

        if not dumpDone and #dumpLines > 1 then
            dumpDone = true
            local f = io.open("D:\\SteamLibrary\\steamapps\\common\\FINAL FANTASY RESONANCE\\FFRS\\Binaries\\Win64\\ue4ss\\Mods\\tb_dump.txt", "w")
            if f then
                f:write(table.concat(dumpLines, "\n"))
                f:close()
            end
        end
    end)
end

return M
