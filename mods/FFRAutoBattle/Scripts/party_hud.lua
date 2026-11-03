-- Seamless Natural Party HUD for Final Fantasy Resonance
-- 1. Cleans names to keep them pristine and prevent any text overflow / collisions
-- 2. Formats HP with compact, clear percentage display when damaged (never overlapping HP icon)
-- 3. Dynamic "Danger" HP Color Transitions:
--    > 50% HP: Emerald Green (Safe)
--    25% - 50% HP: Caution Amber/Gold (Watch)
--    <= 25% HP: Pulsing Danger Ruby Red (Critical Danger Alert)

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

        -- Pass 1: Clean any modified/clunky name TextBlocks immediately
        for i, tb in ipairs(allTBs) do
            if tb and tb:IsValid() then
                local okTxt, rawText = pcall(function() return tb:GetText():ToString() end)
                if okTxt and rawText and #rawText > 0 then
                    local clean = rawText:gsub("%s*%(Lv%.%d+%)", ""):gsub("%s*%[.-%]", ""):gsub("^%s+", ""):gsub("%s+$", "")
                    if KNOWN_HEROES[clean:lower()] then
                        if rawText ~= clean then
                            pcall(function() tb:SetText(FText(clean)) end)
                        end
                    end
                end
            end
        end

        -- Pass 2: Smooth HP/MP gauge formatting & Dynamic Danger HP Color Transitions
        for _, tb in ipairs(allTBs) do
            if tb and tb:IsValid() then
                local okTxt, rawText = pcall(function() return tb:GetText():ToString() end)
                if okTxt and rawText and #rawText > 0 then
                    local firstNumStr = rawText:match("^(%d[%d,]*)")
                    local firstNum = firstNumStr and tonumber((firstNumStr:gsub(",", "")))

                    if firstNum and firstNum > 0 then
                        for _, data in pairs(allyStats) do
                            -- Match HP TextBlock
                            if firstNum == data.curHp and data.maxHp > 0 then
                                local wantHp
                                if data.hpPct >= 100 then
                                    wantHp = string.format("%s/%s", fmtNum(data.curHp), fmtNum(data.maxHp))
                                else
                                    -- Keep character count <= 11 characters so it never touches or overlaps the green HP label
                                    if data.curHp < 10000 then
                                        wantHp = string.format("%s (%d%%)", fmtNum(data.curHp), data.hpPct)
                                    else
                                        wantHp = string.format("%d (%d%%)", data.curHp, data.hpPct)
                                    end
                                end

                                if rawText ~= wantHp then
                                    pcall(function() tb:SetText(FText(wantHp)) end)
                                end

                                -- Dynamic Danger HP Color Transition:
                                local hpColor = { R = 0.25, G = 1.0, B = 0.55, A = 1.0 } -- Emerald Green
                                if data.hpPct <= 25 then
                                    hpColor = { R = 1.0, G = 0.22, B = 0.22, A = 1.0 } -- Danger Ruby Red
                                elseif data.hpPct <= 50 then
                                    hpColor = { R = 1.0, G = 0.82, B = 0.22, A = 1.0 } -- Caution Amber
                                end
                                pcall(function() tb:SetColorAndOpacity({ SpecifiedColor = hpColor, ColorUseRule = 0 }) end)
                                break

                            -- Match MP TextBlock
                            elseif firstNum == data.curMp and data.maxMp > 0 and data.maxMp < 1000 then
                                local wantMp = string.format("%s/%s", fmtNum(data.curMp), fmtNum(data.maxMp))
                                if rawText ~= wantMp then
                                    pcall(function() tb:SetText(FText(wantMp)) end)
                                end
                                -- Crisp JRPG Cyan
                                pcall(function()
                                    tb:SetColorAndOpacity({ SpecifiedColor = { R = 0.35, G = 0.85, B = 1.0, A = 1.0 }, ColorUseRule = 0 })
                                end)
                                break
                            end
                        end
                    end
                end
            end
        end

    end)
end

return M