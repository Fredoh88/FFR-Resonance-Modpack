-- mathematical advisor for FFRS: evaluates party loadout, stagger, elements, and AP economy.
local M = {}

local ELEMENTS = { "fire", "ice", "thunder", "wind", "water", "light", "dark" }

local LOW_TIER_SPELLS = {
    ["fire"] = "Firaga",
    ["blizzard"] = "Blizzaga",
    ["thunder"] = "Thundaga",
    ["aero"] = "Aeroga",
    ["water"] = "Waterga",
    ["cure"] = "Curaja",
    ["cura"] = "Curaja",
}

function M.analyzeParty(allies, equippedIdsFn, skillOfFn, knownOfFn, outputFilePath)
    local report = {}
    local append = function(s) report[#report + 1] = s end

    append("================================================================================")
    append("        FINAL FANTASY RESONANCE - MATHEMATICAL GEAR & TALENT ADVISOR           ")
    append("================================================================================")
    append("")

    local coveredElements = {}
    local memberSummaries = {}
    local hudLines = {}
    hudLines[#hudLines + 1] = "== MATHEMATICAL ADVISOR =="

    for _, a in ipairs(allies or {}) do
        local uid = a.id
        local name = a.name or ("Unit " .. tostring(uid))
        local ids = {}
        if equippedIdsFn then
            local ok, res = pcall(equippedIdsFn, uid)
            if ok and type(res) == "table" then ids = res end
        end

        local physCount, magCount, healCount = 0, 0, 0
        local unitElements = {}
        local bestStaggerSkill, bestStaggerVal = nil, 0
        local bestDamageSkill, bestDamageVal = nil, 0
        local upgradeSuggestions = {}

        for _, id in ipairs(ids) do
            local s = skillOfFn and skillOfFn(id)
            if s then
                local info = knownOfFn and knownOfFn(s)
                local sName = (s.name or ""):lower()
                local power = s.power or 0
                local stagger = (info and info.stagger) or s.breakPower or 0
                local el = (info and info.element) or s.element

                if el then
                    coveredElements[el] = true
                    unitElements[el] = true
                end

                if (info and info.phys) or s.phys then
                    physCount = physCount + 1
                elseif (info and info.magic) or s.magic then
                    magCount = magCount + 1
                end

                if (info and (info.use == "heal" or info.use == "cure" or info.use == "revive")) or s.kind == "heal" or s.kind == "revive" then
                    healCount = healCount + 1
                end

                if stagger > bestStaggerVal then
                    bestStaggerVal = stagger
                    bestStaggerSkill = s.name
                end

                if power > bestDamageVal then
                    bestDamageVal = power
                    bestDamageSkill = s.name
                end

                if LOW_TIER_SPELLS[sName] then
                    upgradeSuggestions[#upgradeSuggestions + 1] = string.format("%s -> %s (0 AP)", s.name, LOW_TIER_SPELLS[sName])
                end
            end
        end

        local role = "Hybrid"
        if healCount >= 2 and healCount >= physCount and healCount >= magCount then
            role = "Healer"
        elseif physCount > magCount then
            role = "Phys Breaker"
        elseif magCount > physCount then
            role = "Mage Nuker"
        end

        local elsList = {}
        for el in pairs(unitElements) do elsList[#elsList + 1] = el end
        table.sort(elsList)

        append(string.format("[%s] Role: %s", name, role))
        append(string.format("  - Total Equipped Skills: %d (Phys: %d, Mag: %d, Support: %d)", #ids, physCount, magCount, healCount))
        append(string.format("  - Elements Covered: %s", #elsList > 0 and table.concat(elsList, ", ") or "Neutral"))
        append(string.format("  - Best Stagger Skill: %s (Stagger Power: %d)", bestStaggerSkill or "None", bestStaggerVal))
        append(string.format("  - Best Burst Skill: %s (Raw Power: %d)", bestDamageSkill or "None", bestDamageVal))

        if #upgradeSuggestions > 0 then
            append("  - OPTIMIZATION OPPORTUNITY (Free AP Mod):")
            for _, u in ipairs(upgradeSuggestions) do
                append("      * Replace " .. u)
            end
        end
        append("")

        hudLines[#hudLines + 1] = string.format("[%s] %s | Top Stagger: %s (%d)",
            name, role, bestStaggerSkill or "Attack", bestStaggerVal)
    end

    -- Global Party Assessment
    append("--------------------------------------------------------------------------------")
    append("                      PARTY ELEMENTAL & BREAK EFFICIENCY                        ")
    append("--------------------------------------------------------------------------------")
    local coveredList, missingList = {}, {}
    for _, el in ipairs(ELEMENTS) do
        if coveredElements[el] then
            coveredList[#coveredList + 1] = el
        else
            missingList[#missingList + 1] = el
        end
    end

    local coveragePct = math.floor((#coveredList / #ELEMENTS) * 100)
    append(string.format("Elemental Coverage: %d/%d (%d%%)", #coveredList, #ELEMENTS, coveragePct))
    append("  Covered: " .. (#coveredList > 0 and table.concat(coveredList, ", ") or "None"))
    append("  Missing: " .. (#missingList > 0 and table.concat(missingList, ", ") or "None (Full Spectrum)"))
    append("")
    append("MATHEMATICAL PRINCIPLE:")
    append("  Hitting an elemental weakness gives +200% Break (3.0x multiplier) and bypasses armor.")
    if #missingList > 0 then
        append("  Recommendation: Slot abilities covering " .. table.concat(missingList, ", ") .. " across your party")
        append("  to ensure guaranteed 3.0x Stagger against all mob types (Beasts, Mechs, Undead).")
    else
        append("  PERFECT COVERAGE: Your party can exploit any enemy elemental weakness in the game!")
    end
    append("================================================================================")

    hudLines[#hudLines + 1] = string.format("Coverage: %d/%d Elements (%d%%)", #coveredList, #ELEMENTS, coveragePct)
    if #missingList > 0 then
        hudLines[#hudLines + 1] = "Missing: " .. table.concat(missingList, ", ") .. " (Rec: slot for 3.0x Break)"
    else
        hudLines[#hudLines + 1] = "Spectrum: 100% Full Weakness Exploitation!"
    end
    hudLines[#hudLines + 1] = "[F8: Toggle HUD Display]"

    local fullText = table.concat(report, "\n")
    if outputFilePath then
        pcall(function()
            local f = io.open(outputFilePath, "w")
            if f then
                f:write(fullText)
                f:close()
            end
        end)
    end

    local summary = string.format("Coverage: %d/%d elements (%d%%) | Missing: %s",
        #coveredList, #ELEMENTS, coveragePct, #missingList > 0 and table.concat(missingList, ", ") or "None")

    return summary, table.concat(hudLines, "\n")
end

return M
