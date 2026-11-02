-- Seamless Party HUD Enhancements for Final Fantasy Resonance
-- Integrates Level, Max HP/MP, Percentage, Danger Alerts, and LB Ready Status directly into the native party frames!
-- Smooth, flicker-free, 100% game-thread safe.

local M = {}

local function fmtNum(n)
    if not n then return "0" end
    local s = tostring(math.floor(math.abs(n)))
    local formatted = s:reverse():gsub("(%d%d%d)", "%1,"):reverse():gsub("^,", "")
    if n < 0 then return "-" .. formatted end
    return formatted
end

local function cleanName(raw)
    if not raw or raw == "" then return "" end
    local s = raw:gsub("%s*Lv%..*$", ""):gsub("%s*%[.*$", ""):gsub("%s*%(.*$", "")
    return s:gsub("^%s+", ""):gsub("%s+$", "")
end

local function findTextBlocksIn(widget, depth)
    local results = {}
    if not (widget and widget:IsValid()) then return results end
    local okClass, cName = pcall(function() return widget:GetClass():GetFName():ToString() end)
    if okClass and cName == "TextBlock" then
        results[#results + 1] = widget
        return results
    end
    if (depth or 0) >= 4 then return results end
    local count = 0
    pcall(function() count = widget:GetChildrenCount() end)
    if count > 0 then
        for i = 0, count - 1 do
            local child = nil
            pcall(function() child = widget:GetChildAt(i) end)
            if child and child:IsValid() then
                local sub = findTextBlocksIn(child, (depth or 0) + 1)
                for _, s in ipairs(sub) do results[#results + 1] = s end
            end
        end
    end
    return results
end

local dumpLogged = false

function M.tick(allies, statFn, paramOfFn, unitNameFn, brokenFn)
    if not allies or #allies == 0 then return end

    pcall(function()
        -- Build current snapshot of party stats
        local statsByChar = {}
        for _, uid in ipairs(allies) do
            local name = unitNameFn(uid)
            if name and name ~= "" then
                local curHp = statFn(uid, 1, false) or 0  -- PARAM.HP = 1
                local maxHp = statFn(uid, 1, true) or 1
                local curMp = statFn(uid, 2, false) or 0  -- PARAM.MP = 2
                local maxMp = statFn(uid, 2, true) or 1
                local curLb = statFn(uid, 3, false) or 0  -- PARAM.LB = 3
                local maxLb = statFn(uid, 3, true) or 100
                if maxLb <= 0 then maxLb = 100 end

                local hpPct = math.floor((curHp / maxHp) * 100 + 0.5)
                local mpPct = math.floor((curMp / maxMp) * 100 + 0.5)
                local lbPct = math.min(100, math.floor((curLb / maxLb) * 100 + 0.5))

                local p = paramOfFn(uid)
                local lvl = nil
                if p then
                    local okL, l = pcall(function() return p:GetLevel() end)
                    if okL and type(l) == "number" and l > 0 then lvl = l end
                end

                statsByChar[name:lower()] = {
                    uid = uid,
                    name = name,
                    lvl = lvl,
                    curHp = curHp,
                    maxHp = maxHp,
                    hpPct = hpPct,
                    curMp = curMp,
                    maxMp = maxMp,
                    mpPct = mpPct,
                    curLb = curLb,
                    maxLb = maxLb,
                    lbPct = lbPct,
                }
            end
        end

        local allTBs = FindAllOf("TextBlock")
        if not allTBs or #allTBs == 0 then return end

        for _, tb in ipairs(allTBs) do
            if tb and tb:IsValid() then
                local okTxt, rawText = pcall(function() return tb:GetText():ToString() end)
                if okTxt and rawText and #rawText > 0 and #rawText < 40 then
                    local cName = cleanName(rawText):lower()
                    local charData = statsByChar[cName]

                    if charData then
                        -- Found the Name TextBlock for this character!
                        -- Format the header row: Name [Lv.XX] + Alert Tags
                        local alertTag = ""
                        if charData.hpPct <= 0 then
                            alertTag = " [FALLEN]"
                        elseif charData.hpPct <= 25 then
                            alertTag = " [DANGER!]"
                        elseif charData.lbPct >= 100 then
                            alertTag = " [LB READY!]"
                        end

                        local wantName = charData.lvl and string.format("%s (Lv.%d)%s", charData.name, charData.lvl, alertTag)
                                                      or string.format("%s%s", charData.name, alertTag)

                        if rawText ~= wantName then
                            pcall(function() tb:SetText(FText(wantName)) end)
                        end

                        -- Inspect Parent / Grandparent container to find all child TextBlocks
                        local topContainer = nil
                        local okPar, par = pcall(function() return tb:GetParent() end)
                        if okPar and par and par:IsValid() then
                            topContainer = par
                            local okGp, gp = pcall(function() return par:GetParent() end)
                            if okGp and gp and gp:IsValid() then
                                topContainer = gp
                                local okGgp, ggp = pcall(function() return gp:GetParent() end)
                                if okGgp and ggp and ggp:IsValid() then
                                    topContainer = ggp
                                end
                            end
                        end

                        if topContainer then
                            local siblings = findTextBlocksIn(topContainer, 0)
                            for _, child in ipairs(siblings) do
                                if child ~= tb and child:IsValid() then
                                    local okCTxt, cText = pcall(function() return child:GetText():ToString() end)
                                    if okCTxt and cText and #cText > 0 then
                                        local cleanDigits = cText:gsub(",", "")
                                        local numVal = tonumber(cleanDigits:match("^%d+"))

                                        -- Detect if this text block displays HP
                                        local isCurrentHp = (numVal == charData.curHp) or (cleanDigits == tostring(charData.curHp))
                                        -- Detect if this text block displays MP
                                        local isCurrentMp = (numVal == charData.curMp) or (cleanDigits == tostring(charData.curMp))

                                        -- Seamless HP format:
                                        -- If at full HP: "2,018 / 2,018"
                                        -- If damaged: "1,069 / 1,399 (76%)"
                                        if isCurrentHp and not cText:find("/") then
                                            local wantHp = (charData.hpPct < 100)
                                                and string.format("%s / %s (%d%%)", fmtNum(charData.curHp), fmtNum(charData.maxHp), charData.hpPct)
                                                or  string.format("%s / %s", fmtNum(charData.curHp), fmtNum(charData.maxHp))

                                            if cText ~= wantHp then
                                                pcall(function() child:SetText(FText(wantHp)) end)
                                            end

                                        -- Seamless MP format: "206 / 206"
                                        elseif isCurrentMp and not cText:find("/") then
                                            local wantMp = string.format("%s / %s", fmtNum(charData.curMp), fmtNum(charData.maxMp))
                                            if cText ~= wantMp then
                                                pcall(function() child:SetText(FText(wantMp)) end)
                                            end
                                        end
                                    end
                                end
                            end
                        end
                    end
                end
            end
        end
    end)
end

return M
