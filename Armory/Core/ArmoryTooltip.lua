--[[
    Armory Addon for World of Warcraft(tm).
    Revision: 204 2023-07-15T14:27:11Z
    URL: http://www.wow-neighbours.com

    License:
        This program is free software; you can redistribute it and/or
        modify it under the terms of the GNU General Public License
        as published by the Free Software Foundation; either version 2
        of the License, or (at your option) any later version.

        This program is distributed in the hope that it will be useful,
        but WITHOUT ANY WARRANTY; without even the implied warranty of
        MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
        GNU General Public License for more details.

        You should have received a copy of the GNU General Public License
        along with this program(see GPL.txt); if not, write to the Free Software
        Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston, MA  02110-1301, USA.

    Note:
        This AddOn's source code is specifically designed to work with
        World of Warcraft's interpreted AddOn system.
        You have an implicit licence to use this AddOn with these facilities
        since that is it's designated purpose as per:
        http://www.fsf.org/licensing/licenses/gpl-faq.html#InterpreterIncompat
--]]

local Armory, _ = Armory, nil;

local tooltipHooks = {};
local tooltipLines = {};

local MAX_ACHIEVEMENT_PLAYERS = 10;

local strtrim = strtrim;
local strlower = strlower;
local strsplit = strsplit;
local select = select;
local tonumber = tonumber;
local table = table;
local ipairs = ipairs;
local format = format;
local unpack = unpack;
local bit = bit;
local floor = floor;
local min = min;
local pcall = pcall;
local assert = assert;
local error = error;

----------------------------------------------------------
-- Tooltip Enhancement
----------------------------------------------------------

local function AddSpacer(tooltip)
    local lastLine = _G[tooltip:GetName().."TextLeft"..tooltip:NumLines()];
    if ( lastLine ) then
        if ( strtrim(lastLine:GetText() or "") ~= "" ) then
            tooltip:AddLine(" ");
        elseif ( tooltip.hasMoney ) then
            for i = 1, (tooltip.shownMoneyFrames or 0) do
                local moneyFrame = _G[tooltip:GetName().."MoneyFrame"..i];
                if ( moneyFrame and moneyFrame:IsShown() and select(2, moneyFrame:GetPoint()) == lastLine ) then
                    tooltip:AddLine(" ");
                    break;
                end
            end
        end
    end
    return 1;
end

local function AddAltsText(tooltip, spaceAdded, list, text, r, g, b)
    if ( list and #list > 0 ) then
        spaceAdded = spaceAdded or AddSpacer(tooltip);
        for i = 1, #list do
            if ( i == 1 ) then
                tooltip:AddDoubleLine(text, list[i], r, g, b, r, g, b);
            else
                tooltip:AddDoubleLine(" ", list[i], r, g, b, r, g, b);
            end
        end
    end
    return spaceAdded;
end

local knownBy;
local fetched;

local accountBoundPattern = "^"..ITEM_BIND_TO_BNETACCOUNT.."$";
local minLevelPattern = "^"..ITEM_MIN_LEVEL:gsub("(%%d)", "(.+)").."$";
local rankPattern = "^"..ITEM_MIN_SKILL:gsub("%d%$", ""):gsub("%%s", "(.+)"):gsub("%(%%d%)", "%%((%%d+)%%)").."$";
local repPattern = "^"..ITEM_REQ_REPUTATION:gsub("%-", "%%-"):gsub("%%s", "(.+)").."$";
local skillPattern = "^"..ITEM_REQ_SKILL:gsub("%d%$", ""):gsub("%%s", "(.+)").."$";
local racesPattern = "^"..ITEM_RACES_ALLOWED:gsub("%%s", "(.+)").."$";
local classesPattern = "^"..ITEM_CLASSES_ALLOWED:gsub("%%s", "(.+)").."$";
local reagentPattern = "\n"..ITEM_REQ_SKILL:gsub("%d%$", ""):gsub("%%s", "(.+)");

local function GetRequirements(tooltip)
    local text, standing, reagents;
    local reqLevel, reqProfession, reqRank, reqReputation, reqStanding, reqSkill, reqRaces, reqClasses, accountBound;

    for i = 2, tooltip:NumLines() do
        text = Armory:GetTooltipText(tooltip, i);
        if ( (text or "") ~= "" ) then
            if ( text:find(accountBoundPattern) ) then
                accountBound = true;

            elseif ( text:find(minLevelPattern) ) then
                reqLevel = text:match(minLevelPattern);

            elseif ( text:find(rankPattern) ) then
                reqProfession, reqRank = text:match(rankPattern);

            elseif ( text:find(repPattern) ) then
                reqReputation, standing = text:match(repPattern);
                reqStanding = 9;
                for j = 1, 8 do
                    if ( standing == _G["FACTION_STANDING_LABEL"..j] or standing == _G["FACTION_STANDING_LABEL"..j.."_FEMALE"] ) then
                        reqStanding = j;
                        break;
                    end
                end

            elseif ( text:find(skillPattern) ) then
                text:gsub(skillPattern, function(a, b) reqSkill = a; end);

            elseif ( text:find(racesPattern) ) then
                reqRaces = text:match(racesPattern);

            elseif ( text:find(classesPattern) ) then
                reqClasses = text:match(classesPattern);

            elseif ( text:find(reagentPattern) ) then
                reagents = text:match(reagentPattern);

            end
        end
    end

    return tonumber(reqLevel), reqProfession, tonumber(reqRank), reqReputation, reqStanding, reqSkill, reqRaces, reqClasses, reagents, accountBound;
end

local itemCandidates = {};
local function GetItemCandidates(minLevel, classes, itemLevel, slotID1, slotID2)
    local currentProfile = Armory:CurrentProfile();

    table.wipe(itemCandidates);

    local level, class;
    for _, profile in ipairs(Armory:SelectableProfiles()) do
        Armory:SelectProfile(profile);

        if ( Armory:UnitLevel("player") >= minLevel and (not classes or classes:find((Armory:UnitClass("player")))) ) then
            local link1, link2;
            if ( slotID1 ) then
                link1 = Armory:GetInventoryItemLink("player", slotID1);
            end
            if ( slotID2 ) then
                link2 = Armory:GetInventoryItemLink("player", slotID2);
            end
            if ( not link1 ) then
                link1 = link2;
                link2 = nil;
            end
            if ( link1 ) then
                local character = Armory:GetQualifiedCharacterName();
                table.insert(itemCandidates, {name=character, itemLevel=itemLevel, link1=link1, link2=link2});
            end
        end
    end
    Armory:SelectProfile(currentProfile);

    return itemCandidates;
end

local function UpdateItemCandidates(candidates)
    local result = candidates and #candidates > 0;
    if ( result ) then
        for i = #candidates, 1, -1 do
            local itemLevel = candidates[i].itemLevel;
            if ( not candidates[i].itemLevel1 ) then
                candidates[i].itemLevel1 = select(4, GetItemInfo(candidates[i].link1));
            end
            if ( not candidates[i].link2 ) then
                candidates[i].itemLevel2 = itemLevel + 1;
            elseif ( not candidates[i].itemLevel2 ) then
                candidates[i].itemLevel2 = select(4, GetItemInfo(candidates[i].link2));
            end
            if ( candidates[i].itemLevel1 == nil or candidates[i].itemLevel2 == nil ) then
                result = false;
            elseif ( candidates[i].itemLevel1 >= itemLevel and candidates[i].itemLevel2 >= itemLevel ) then
                table.remove(candidates, i);
            end
        end
    end
    return result;
end

local gemInfo, crafters, itemCount, hasSkill, canLearn, candidates;
local reagents = {};
local function EnhanceItemTooltip(tooltip, id)
    local spaceAdded, name;

    if ( not (id and Armory:IsValidTooltip(tooltip)) ) then
        return;

    elseif ( id ~= fetched ) then
        gemInfo = nil;
        knownBy = nil;
        canLearn = nil;
        hasSkill = nil;
        crafters = nil;
        candidates = nil;

        -- Need the fully qualified link
        local name, link, _, itemLevel, minLevel, _, subType, _, equipLoc, _, _, itemType, itemSubType = GetItemInfo(id);

        if ( not itemType ) then
            return;

        elseif ( itemType == Enum.ItemClass.Recipe ) then
            local _, reqProfession, reqRank, reqReputation, reqStanding, reqSkill, _, _, reagents = GetRequirements(tooltip);
            -- Recipe tooltips are built in stages (last stage shows rank)
            if ( not reqRank ) then
                return;
            end
            local recipeType, recipeName = name:match("^(.-): (.+)$");

            knownBy, hasSkill, canLearn = Armory:GetRecipeAltInfo(recipeName, link, subType or recipeType, reqProfession, reqRank, reqReputation, reqStanding, reqSkill);

        elseif ( itemType == Enum.ItemClass.Glyph ) then
            crafters = Armory:GetInscribers(name, subType);

        elseif ( itemType ~= Enum.ItemClass.Miscellaneous ) then
            if ( Armory:GetConfigShowGems() ) then
                local numGems;
                gemInfo, numGems = Armory:GetSocketInfo(link);
                if ( numGems == 0 ) then
                    gemInfo = nil;
                end
            end

            -- Note: can't do this for weapons or without class restriction
            if ( itemType == Enum.ItemClass.Armor ) then
                local _, _, _, _, _, _, _, reqClasses, _, accountBound = GetRequirements(tooltip);
                if ( reqClasses and accountBound ) then
                    local slot = ARMORY_SLOTINFO[equipLoc];
                    if ( slot ) then
                        if ( slot == ARMORY_SLOTID.Finger0Slot ) then
                            candidates = GetItemCandidates(minLevel, reqClasses, itemLevel, slot, ARMORY_SLOTID.Finger1Slot);
                        elseif ( slot == ARMORY_SLOTID.Trinket0Slot ) then
                            candidates = GetItemCandidates(minLevel, reqClasses, itemLevel, slot, ARMORY_SLOTID.Trinket1Slot);
                        else
                            candidates = GetItemCandidates(minLevel, reqClasses, itemLevel, slot);
                        end
                    end
                end
            end

            crafters = Armory:GetCrafters(id);
        end

        table.wipe(reagents);

        local parent = tooltip:GetOwner();
        if ( not parent.reagentSlotSchematic ) then
            parent = parent:GetParent();
        end
        if ( parent and parent.reagentSlotSchematic and #parent.reagentSlotSchematic.reagents > 1 ) then
            for _, reagent in ipairs(parent.reagentSlotSchematic.reagents) do
                local _, reagentLink = GetItemInfo(reagent.itemID);
                table.insert(reagents, reagentLink);
            end
            itemCount = Armory:GetMultipleItemCount(reagents)
        else
            itemCount = Armory:GetItemCount(link);
        end

        fetched = id;
    end

    if ( gemInfo ) then
        AddSpacer(tooltip);
        for _, socket in ipairs(gemInfo) do
            if ( socket.link ) then
                tooltip:AddLine(Armory:GetColorFromLink(socket.link)..socket.gem..FONT_COLOR_CODE_CLOSE.." : "..(socket.gemColor or UNKNOWN));
                tooltip:AddTexture(socket.texture);
            end
        end
        spaceAdded = spaceAdded or AddSpacer(tooltip);
    end

    if ( itemCount and #itemCount > 0 ) then
        spaceAdded = spaceAdded or AddSpacer(tooltip);
        local count, bagCount, bankCount, reagentBankCount, mailCount, auctionCount, equipCount, voidCount = 0, 0, 0, 0, 0, 0, 0, 0;
        local details;
        local numColor = Armory:HexColor(Armory:GetConfigItemCountNumberColor());

        local function AddItemCount(itemCount)
            for k, v in ipairs(itemCount) do
                if ( not v.currency ) then
                    count = count + v.count;
                end
                bagCount = bagCount + (v.bags or 0);
                bankCount = bankCount + (v.bank or 0);
                reagentBankCount = reagentBankCount + (v.reagentBank or 0);
                mailCount = mailCount + (v.mail or 0);
                auctionCount = auctionCount + (v.auction or 0);
                equipCount = equipCount + (v.equipped or 0);
                voidCount = voidCount + (v.void or 0);
                details = v.details or Armory:GetCountDetails(v.bags, v.bank, v.reagentBank, v.mail, v.auction, nil, nil, v.equipped, v.void, v.perSlot, numColor);

                local r, g, b = GetTableColor(v);
                if ( not r ) then
                    r, g, b = Armory:GetConfigItemCountColor();
                end
                local label = format(Armory:FormatCount("%s [%d]", v.numColor or numColor), v.name, v.count);
                if ( v.tier ) then
                    local atlasSize = 16;
                    local atlasMarkup = CreateAtlasMarkup(Professions.GetIconForQuality(v.tier, true), atlasSize, atlasSize);
                    label = atlasMarkup .. label;
                end
                tooltip:AddDoubleLine(label, details, r, g, b, r, g, b);
            end
        end

        if ( #reagents > 0 ) then
            for _, reagentCount in ipairs(itemCount) do
                AddItemCount(reagentCount);
            end
        else
            AddItemCount(itemCount);
        end

        if ( Armory:HasInventory() and count > 0 and Armory:GetConfigShowItemCountTotals() ) then
            local r, g, b = Armory:GetConfigItemCountTotalsColor();
            numColor = Armory:HexColor(Armory:GetConfigItemCountTotalsNumberColor());
            local guildCount = count - bagCount - bankCount - reagentBankCount - mailCount - auctionCount - equipCount - voidCount;
            details = Armory:GetCountDetails(bagCount, bankCount, reagentBankCount, mailCount, auctionCount, nil, guildCount, equipCount, voidCount, nil, numColor);
            tooltip:AddDoubleLine(format(Armory:FormatCount(ARMORY_TOTAL, numColor), count), details, r, g, b, r, g, b);
        end
    end

    spaceAdded = AddAltsText(tooltip, spaceAdded, crafters, ARMORY_CRAFTABLE_BY, Armory:GetConfigCraftersColor());
    spaceAdded = AddAltsText(tooltip, spaceAdded, knownBy, USED, Armory:GetConfigKnownColor());
    spaceAdded = AddAltsText(tooltip, spaceAdded, hasSkill, ARMORY_WILL_LEARN, Armory:GetConfigHasSkillColor());
    spaceAdded = AddAltsText(tooltip, spaceAdded, canLearn, ARMORY_CAN_LEARN, Armory:GetConfigCanLearnColor());

    if ( UpdateItemCandidates(candidates) and #candidates > 0 ) then
        AddSpacer(tooltip);
        tooltip:AddLine(ITEM_UPGRADE);
        local r, g, b = Armory:GetConfigCanLearnColor();
        for _, candidate in ipairs(candidates) do
            local link1, level1 = candidate.link1, candidate.itemLevel1;
            local link2, level2 = candidate.link2, candidate.itemLevel2;
            if ( level1 >= candidate.itemLevel ) then
                link1, level1 = link2, level2;
                link2, level2 = nil, nil;
            end
            local color, _, _, name = Armory:GetLinkInfo(link1);
            tooltip:AddDoubleLine(candidate.name, color..name.." ("..ITEM_LEVEL_ABBR.." "..level1..")", r, g, b, r, g, b);
            if ( level2 and level2 < candidate.itemLevel ) then
                color, _, _, name = Armory:GetLinkInfo(link2);
                tooltip:AddDoubleLine(candidate.name, color..name.." ("..ITEM_LEVEL_ABBR.." "..level2..")", r, g, b, r, g, b);
            end
        end
    end

    tooltip:Show();

    return 1;
end

local reagents, reagentCount;
local function EnhanceRecipeTooltip(tooltip, id, link)
    local spaceAdded;

    if ( not id ) then
        return;

    elseif ( id ~= fetched ) then
        fetched = id;

        knownBy = nil;
        reagentCount = nil;

        if ( tooltip ~= GameTooltip ) then
            knownBy = Armory:GetRecipeOwners(id);
        end

        if ( Armory:HasInventory() and Armory:GetConfigShowItemCount() ) then
            reagents = Armory:GetReagentsFromTooltip(tooltip);
            if ( reagents ) then
                reagentCount = Armory:GetMultipleItemCount(reagents);
            end
        end
    end

    spaceAdded = AddAltsText(tooltip, spaceAdded, knownBy, USED, Armory:GetConfigKnownColor());

    if ( reagentCount and #reagentCount > 0 ) then
        local count, bags, bank, mail, auction, alts, reagentBank;
        local name, quantity, details;

        spaceAdded = spaceAdded or AddSpacer(tooltip);
        local r, g, b = Armory:GetConfigItemCountColor();
        for i = 1, #reagents do
            name, quantity = unpack(reagents[i]);
            count, bags, bank, mail, auction, alts, reagentBank = 0, 0, 0, 0, 0, 0, 0;
            for _, v in ipairs(reagentCount[i]) do
                if ( v.mine ) then
                    bags = bags + (v.bags or 0);
                    bank = bank + (v.bank or 0);
                    reagentBank = reagentBank + (v.reagentBank or 0);
                    mail = mail + (v.mail or 0);
                    auction = auction + (v.auction or 0);
                else
                    alts = alts + (v.bags or 0) + (v.bank or 0) + (v.mail or 0) + (v.auction or 0) + (v.reagentBank or 0);
                end
                count = count + v.count;
            end
            details = Armory:GetCountDetails(bags, bank, reagentBank, mail, auction, alts, count - bags - bank - reagentBank - mail - auction - alts);
            tooltip:AddDoubleLine(name..format(" [%d/%d]", count, quantity), details, r, g, b, r, g, b);
        end
    end

    tooltip:Show();

    return 1;
end

local function EnhanceQuestTooltip(tooltip, id, link)
    if ( not (id and Armory:HasQuestLog() and Armory:GetConfigShowQuestAlts()) ) then
        return;
    end

    local currentProfile = Armory:CurrentProfile();

    table.wipe(tooltipLines);

    for _, character in ipairs(Armory:CharacterList(Armory.playerRealm)) do
        Armory:LoadProfile(Armory.playerRealm, character);

        if ( Armory:IsOnQuest(id) ) then
            table.insert(tooltipLines, character);
        end
    end
    Armory:SelectProfile(currentProfile);

    if ( #tooltipLines > 0 ) then
        AddSpacer(tooltip);
        local r, g, b = Armory:GetConfigQuestAltsColor();
        tooltip:AddLine(ARMORY_QUEST_TOOLTIP_LABEL);
        tooltip:AddLine(table.concat(tooltipLines, ", "), r, g, b, true);
        tooltip:Show();
    end

    return 1;
end

local achievements = {};
local function EnhanceAchievementTooltip(tooltip, id, link)
    if ( not (id and Armory:HasAchievements() and Armory:GetConfigShowAchievements()) ) then
        return;
    end

    local tooltipText = Armory:GetTextFromLink(link);
    local inProgressColor = Armory:HexColor(Armory:GetConfigAchievementInProgressColor());
    local addProgress = function(progress, inProgress)
        if ( not (inProgress and tooltipText:find(inProgress)) ) then
            table.insert(tooltipLines, progress);
            return true;
        end
        return false;
    end;

    table.wipe(tooltipLines);

    local id, _, _, completed, month, day, year, _, flags, _, _, isGuild, _, earnedBy = GetAchievementInfo(id);
    flags = flags or 0;
    if ( isGuild ) then
        return;
    elseif ( completed ) then
        addProgress(format(ACHIEVEMENT_TOOLTIP_COMPLETE, earnedBy ~= "" and earnedBy or strlower(YOU), month, day, year));
    else
        table.wipe(achievements);

        local multiRealm;
        local parent = "";
        while ( id and #achievements == 0 ) do
            if ( bit.band(flags, ACHIEVEMENT_FLAGS_ACCOUNT) ~= ACHIEVEMENT_FLAGS_ACCOUNT ) then
                local currentProfile = Armory:CurrentProfile();
                for _, profile in ipairs(Armory:Profiles()) do
                    Armory:SelectProfile(profile);
                    local quantity, reqQuantity = Armory:GetAchievement(id);
                    if ( quantity ) then
                        table.insert(achievements, {profile.character, profile.realm, quantity, reqQuantity, parent});
                        if ( profile.realm ~= Armory.playerRealm ) then
                            multiRealm = true;
                        end
                    end
                end
                Armory:SelectProfile(currentProfile);
            end

            if ( #achievements == 0 ) then
                local quantity = 0;
                local totalQuantity = 0;
                local started;
                for i = 1, GetAchievementNumCriteria(id) do
                    local _, criteriaType, completed, quantityNumber, reqQuantity, _, flags, assetId, quantityString = GetAchievementCriteriaInfo(id, i);
                    flags = flags or 0;
                    if ( criteriaType == CRITERIA_TYPE_ACHIEVEMENT and assetId ) then
                        _, _, _, completed = _G.GetAchievementInfo(assetId);
                        totalQuantity = totalQuantity + 1;
                        if ( completed ) then
                            quantity = quantity + 1;
                            started = true;
                        end
                    elseif ( bit.band(flags, EVALUATION_TREE_FLAG_PROGRESS_BAR) == EVALUATION_TREE_FLAG_PROGRESS_BAR ) then
                        if ( quantityString and quantityString:find("Gold") ) then
                            quantityNumber = floor(quantityNumber / 10000);
                            reqQuantity = floor(reqQuantity / 10000);
                        end
                        totalQuantity = totalQuantity + reqQuantity;
                        quantity = quantity + quantityNumber;
                        if ( quantityNumber > 0 ) then
                            started = true;
                        end
                    elseif ( completed ) then
                        totalQuantity = totalQuantity + 1;
                        quantity = quantity + 1;
                        started = true;
                    else
                        totalQuantity = totalQuantity + 1;
                    end
                end

                if ( started ) then
                    table.insert(achievements, {strlower(YOU), Armory.realm, quantity, totalQuantity, parent});
                end
            end

            id = GetPreviousAchievement(id);
            if ( id ) then
                _, parent = GetAchievementInfo(id);
            end
        end

        if ( #achievements > 0 ) then
            table.sort(achievements, function(a, b) return a[3] > b[3] end);
            local count = 0;
            local currentProfile = Armory:CurrentProfile();
            for i, v in ipairs(achievements) do
                local character, realm, quantity, reqQuantity, parent = unpack(v);
                local inProgress, progress;
                Armory:LoadProfile(realm, character);
                if ( i == 1 and parent ~= "" ) then
                    addProgress(parent..":");
                end
                if ( count < MAX_ACHIEVEMENT_PLAYERS ) then
                    inProgress = format(ACHIEVEMENT_TOOLTIP_IN_PROGRESS, character);
                    progress = format(ACHIEVEMENT_TOOLTIP_IN_PROGRESS, Armory:GetQualifiedCharacterName(multiRealm));
                    if ( quantity ) then
                        if ( Armory:GetConfigUseInProgressColor() ) then
                            progress = progress..inProgressColor;
                        end
                        progress = progress..format(" (%d%% [%d/%d])", floor((quantity * 100) / reqQuantity), quantity, reqQuantity);
                    end
                else
                    progress = ". . .";
                end
                if ( Armory:GetConfigUseInProgressColor() ) then
                    progress = inProgressColor..progress..FONT_COLOR_CODE_CLOSE;
                end
                if ( addProgress(progress, inProgress) ) then
                    count = count + 1;
                    if ( count > MAX_ACHIEVEMENT_PLAYERS ) then
                        break;
                    end
                end
            end
            Armory:SelectProfile(currentProfile);
        end
    end

    if ( #tooltipLines > 0 ) then
        AddSpacer(tooltip);
        local r, g, b = Armory:GetConfigAchievementsColor();
        for i = 1, #tooltipLines do
            tooltip:AddLine(tooltipLines[i], r, g, b);
        end
        tooltip:Show();
    end
end

local function EnhanceGlyphTooltip(tooltip, id, link)
    local name = Armory:GetNameFromLink(link);
    if ( name ) then
        if ( tooltip ~= GameTooltip ) then
            local reqLevel, _, _, _, _, _, _, reqClass = GetRequirements(tooltip);
            crafters = Armory:GetInscribers(name, reqClass);

            AddAltsText(tooltip, nil, crafters, ARMORY_CRAFTABLE_BY, Armory:GetConfigCraftersColor());
        else
            crafters = Armory:GetInscribers(name, _G.UnitClass("player"));

            AddAltsText(tooltip, nil, crafters, ARMORY_CRAFTABLE_BY, Armory:GetConfigCraftersColor());
        end
        tooltip:Show();
    end

    return 1;
end

local function EnhanceCurrencyTooltip(tooltip, id, link)
    if ( not (link and Armory:HasCurrency() and Armory:GetConfigShowItemCount()) ) then
        return;
    end

    local currentProfile = Armory:CurrentProfile();
    local count, character;
    table.wipe(tooltipLines);

    for _, profile in ipairs(Armory:GetConnectedProfiles()) do
        Armory:SelectProfile(profile);

        count = Armory:CountCurrency(link);
        if ( count > 0 ) then
            character = Armory:GetQualifiedCharacterName();
            table.insert(tooltipLines, {name=character, count=count});
        end
    end
    Armory:SelectProfile(currentProfile);

    if ( #tooltipLines > 0 ) then
        AddSpacer(tooltip);
        local r, g, b = Armory:GetConfigItemCountColor();
        for _, v in ipairs(tooltipLines) do
            tooltip:AddLine(format("%s [%d]", v.name, v.count), r, g, b);
        end
        tooltip:Show();
    end

    return 1;
end

local function EnhanceSpellTooltip(tooltip, id, link)
    local name = Armory:GetNameFromLink(link);
    if ( name ) then
        if ( not (id and Armory:HasTradeSkills() and Armory:GetConfigShowTradeSkillRanks()) ) then
            return;
        end

        -- Smelting
        if ( id == 2656 ) then
            name = ARMORY_TRADE_MINING;
        end

        local currentProfile = Armory:CurrentProfile();

        table.wipe(tooltipLines);

        for _, profile in ipairs(Armory:GetConnectedProfiles()) do
            Armory:SelectProfile(profile);

            local rank, maxRank;
            local tradeSkillLink = select(2, _G.GetSpellLink(id));

            if ( Armory:GetConfigShowSecondaryTradeSkillRanks() ) then
                rank, maxRank = Armory:GetTradeSkillRank(name);
            else
                for _, v in ipairs(Armory:GetPrimaryTradeSkills()) do
                    if ( v[1] == name ) then
                        rank = v[2];
                        maxRank = v[3];
                        break;
                    end
                end
            end

            if ( rank and maxRank ) then
                   local character = Armory:GetQualifiedCharacterName();
                table.insert(tooltipLines, {name=character, rank=rank, maxRank=maxRank});
            end
        end
        Armory:SelectProfile(currentProfile);

        if ( #tooltipLines > 0 ) then
            table.sort(tooltipLines, function(a, b) return a.rank > b.rank; end);
            AddSpacer(tooltip);
            local r, g, b = Armory:GetConfigTradeSkillRankColor();
            for _, v in ipairs(tooltipLines) do
                tooltip:AddDoubleLine(v.name, v.rank.."/"..v.maxRank, r, g, b, r, g, b);
            end
            tooltip:Show();
        end
    end

    return 1;
end

----------------------------------------------------------
-- Tooltip Internals
----------------------------------------------------------

local function ExecuteHook(tooltip, hook)
    local link = tooltip.alink;
    if ( link ) then
        local idType, id = Armory:GetLinkId(link);
        if ( hook.idType == idType and hook.id == id ) then
            return;
        end

        hook.idType = idType;
        hook.id = id;

        if ( hook.hooks[idType] and id ) then
            for _, v in ipairs(hook.hooks[idType]) do
                if ( not v[1](tooltip, id, link) ) then
                    hook.idType = nil;
                    hook.id = nil;
                end
            end
        end
    end
end

local function GetDummyCurrencyLink(currencyName)
    if ( currencyName ) then
        return "|cffffffff|Hcurrency:0|h["..currencyName.."]|h|r";
    end
end

local function SetTooltipHook(tooltip, name, func)
    assert(func, "Hook execution undefined for "..name);

    if ( name == "OnTooltipCleared" ) then
        tooltip:HookScript(name, func);
    elseif ( tooltip[name] ) then
        hooksecurefunc(tooltip, name, function(self, ...)
            if ( select("#", ...) > 0 ) then
                local hook = tooltipHooks[self];
                if ( name:find("Currency") ) then
                    self.alink = GetDummyCurrencyLink(func(...));
                else
                    self.alink = func(...);
                end
                Armory:PrintDebug(name, self.alink, ...);
                ExecuteHook(self, hook);
            end
        end);
    else
        error("Hook "..name.." is undefined");
    end
end

local function RegisterTooltipHook(tooltip, idType, hook, reset)
    if ( not tooltip ) then
        return;
    elseif ( idType == "item" or idType == "spell" ) then
        return;
    elseif ( not tooltipHooks[tooltip] ) then
        tooltipHooks[tooltip] = {};
        tooltipHooks[tooltip].hooks = {};

        SetTooltipHook(tooltip, "SetCurrencyToken", function(index)
            return C_CurrencyInfo.GetCurrencyListInfo(index).name;
        end);
        SetTooltipHook(tooltip, "SetQuestCurrency", _G.GetQuestCurrencyInfo);
        SetTooltipHook(tooltip, "SetQuestLogCurrency", function(type, index, questID)
            if ( questID ) then
                return _G.GetQuestLogRewardCurrencyInfo(index, questID);
            end
        end);

        SetTooltipHook(tooltip, "SetMerchantCostItem", function(index, itemIndex)
            local _, _, link, currencyName = _G.GetMerchantItemCostItem(index, itemIndex);
            return link or GetDummyCurrencyLink(currencyName);
        end);

        SetTooltipHook(tooltip, "SetHyperlink", function(link)
            return link;
        end);

        SetTooltipHook(tooltip, "OnTooltipCleared", function(self)
            local hook = tooltipHooks[self];
            local idType = hook.idType;

            if ( idType and hook.hooks[idType] ) then
                for _, v in ipairs(hook.hooks[idType]) do
                    if ( v[2] ) then
                        v[2](self);
                    end
                end
            end

            hook.idType = nil;
            hook.id = nil;
        end);
    end
    if ( not tooltipHooks[tooltip].hooks[idType] ) then
        tooltipHooks[tooltip].hooks[idType] = {};
    end
    table.insert(tooltipHooks[tooltip].hooks[idType], {hook, reset});
end

local function GetFontStringTextString(fontString)
    if ( fontString ) then
        local text = fontString:GetText();
        if ( text and strtrim(text) ~= "" ) then
            return Armory:Text2String(text, fontString:GetTextColor());
        end
    end
    return "";
end

----------------------------------------------------------
-- Tooltip Functions
----------------------------------------------------------

TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Item, function(tooltip, data)
    if ( tooltip == GameTooltip or tooltip == ItemRefTooltip ) then
        local _, _, id = tooltip:GetItem();
        EnhanceItemTooltip(tooltip, id);
    end
end);

TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Spell, function(tooltip, data)
    if ( tooltip == GameTooltip or tooltip == EmbeddedItemTooltip ) then
        local _, id = tooltip:GetSpell();
        EnhanceSpellTooltip(tooltip, id, id and _G.GetSpellLink(id) or nil);
    end
end);

function Armory:RegisterTooltipHooks(tooltip)
    RegisterTooltipHook(tooltip, "enchant", EnhanceRecipeTooltip);
    RegisterTooltipHook(tooltip, "quest", EnhanceQuestTooltip);
    RegisterTooltipHook(tooltip, "achievement", EnhanceAchievementTooltip);
    RegisterTooltipHook(tooltip, "glyph", EnhanceGlyphTooltip);
    RegisterTooltipHook(tooltip, "currency", EnhanceCurrencyTooltip);
end

function Armory:ResetTooltipHook()
    fetched = nil;
end

function Armory:RefreshTooltip(tooltip)
   if ( tooltip and tooltip.alink and tooltip:IsShown() ) then
        tooltip:ClearLines();
        tooltip:SetHyperlink(tooltip.alink);
        tooltip:Show();
    end
end

function Armory:GetTooltipText(tooltip, index, side)
    local fontString = _G[tooltip:GetName().."Text"..(side or "Left")..(index or 1)];
    if ( fontString and fontString:IsShown() ) then
        return fontString:GetText();
    end
end

function Armory:IsValidTooltip(tooltip)
    local numLines = tooltip:NumLines();
    local text;

    if ( numLines == 0 ) then
        return false;
    end

    for i = 1, numLines  do
        text = self:GetTooltipText(tooltip, i);
        if ( text == RETRIEVING_ITEM_INFO ) then
            return false;
        end
    end

    return true;
end

local sides = {"Left", "Right"};
function Armory:Tooltip2String(tooltip, all)
    local result = "";
    local text;

    for i = 1, tooltip:NumLines() do
        for _, side in ipairs(sides) do
            text = self:GetTooltipText(tooltip, i, side);
            if ( text ) then
                result = result..text.."\n";
            end
            if ( not all ) then
                break;
            end
        end
    end

    return result;
end

function Armory:Tooltip2Table(tooltip, all)
    local name = tooltip:GetName();
    local lines = {};
    local textLeft, textRight, icon, relativeTo, line;

    for i = 1, tooltip:NumLines() do
        textLeft = _G[name.."TextLeft"..i];
        if ( textLeft and textLeft:IsShown() ) then
            lines[i] = GetFontStringTextString(textLeft);
        else
            lines[i] = "";
        end
        textRight = _G[name.."TextRight"..i];
        if ( textRight and textRight:IsShown() ) then
            lines[i] = lines[i]..ARMORY_TOOLTIP_COLUMN_SEPARATOR..GetFontStringTextString(textRight);
        end

        if ( not all and lines[i] == "" ) then
            table.remove(lines, i);
            break;
        end
    end

    for i = 1, 10 do
        icon = _G[name.."Texture"..i];
        if ( icon and icon:IsShown() and icon:GetTexture() ) then
            _, relativeTo = icon:GetPoint();
            line = tonumber(relativeTo:GetName():match("(%d+)$"));
            if ( line > 0 and line <= #lines ) then
                lines[line] = lines[line]..ARMORY_TOOLTIP_TEXTURE_SEPARATOR..icon:GetTexture();
            end
        else
            break;
        end
    end

    return lines;
end

function Armory:Table2Tooltip(tooltip, t, firstWrap)
    local line, texture, left, right, textLeft, textRight;
    local leftR, leftG, leftB, rightR, rightG, rightB;

    tooltip:ClearLines();
    for i = 1, #t do
        line, texture = strsplit(ARMORY_TOOLTIP_TEXTURE_SEPARATOR, t[i]);
        if ( line ) then
            left, right = strsplit(ARMORY_TOOLTIP_COLUMN_SEPARATOR, line);
            if ( left ) then
                leftR, leftG, leftB, textLeft = self:String2Text(left);
                if ( right ) then
                    rightR, rightG, rightB, textRight = self:String2Text(right);
                    tooltip:AddDoubleLine(textLeft, textRight, leftR, leftG, leftB, rightR, rightG, rightB);
                elseif ( (textLeft or "") == "" ) then
                    tooltip:AddLine(" ");
                else
                    tooltip:AddLine(textLeft, leftR, leftG, leftB, not texture and i >= (firstWrap or 3));
                end
            end
            if ( texture ) then
                tooltip:AddTexture(texture);
            end
        end
    end
end

function Armory:AllocateTooltip()
    local tooltip;
    if ( not self.dummyTips ) then
        self.dummyTips = {};
    end
    for i = 1, #self.dummyTips do
        tooltip = self.dummyTips[i];
        if ( not tooltip.allocated ) then
            tooltip.allocated = true;
            tooltip:ClearLines();
            for i = 1, 4 do
                _G[tooltip:GetName().."Texture"..i]:SetTexture("");
            end
            -- In case the owner has been removed
            if ( not tooltip:GetOwner() ) then
                tooltip:SetOwner(UIParent, "ANCHOR_NONE");
            end
            return tooltip;
        end
    end
    tooltip = CreateFrame("GameTooltip", "ArmoryTooltip"..(#self.dummyTips + 1), nil, "GameTooltipTemplate")
    tooltip:SetOwner(UIParent, "ANCHOR_NONE");
    tooltip.allocated = true;
    table.insert(self.dummyTips, tooltip);

    return tooltip;
end

function Armory:ReleaseTooltip(tooltip)
    tooltip.allocated = false;
end

function Armory:TooltipAddHints(tooltip, ...)
    for i = 1, select("#", ...) do
        tooltip:AddLine(select(i, ...), GREEN_FONT_COLOR.r, GREEN_FONT_COLOR.g, GREEN_FONT_COLOR.b, 1);
    end
end

function Armory:GetItemFromTooltip(tooltip)
    local name, link = tooltip:GetItem();
    if ( (name or "") ~= "" ) then
        return name, link;
    end
end

local setPattern = EQUIPMENT_SETS:gsub("%%s", ".+");
local madeByPattern = ITEM_CREATED_BY:gsub("%%s", ".+");
local cdPattern = ITEM_COOLDOWN_TIME:gsub("%%s", ".+");

function Armory:GetTinkerFromTooltip(tooltip1, tooltip2)
    if ( (self:GetItemFromTooltip(tooltip1)) ~= (self:GetItemFromTooltip(tooltip2)) ) then
        return;
    end

    local tinker, anchor;

    local tooltip1Index = tooltip1:NumLines();
    local tooltip2Index = tooltip2:NumLines();
    local tooltip1Line = self:GetTooltipText(tooltip1, tooltip1Index);
    local tooltip2Line = self:GetTooltipText(tooltip2, tooltip2Index);

    while ( tooltip1Index > 1 ) do
        if ( tooltip1Line == RETRIEVING_ITEM_INFO or tooltip2Line == RETRIEVING_ITEM_INFO ) then
            return;
        elseif ( tooltip1Line:find(setPattern) or tooltip1Line:find(madeByPattern) or tooltip1Line:find(cdPattern) or tooltip1Line == ITEM_SOCKETABLE ) then
            tooltip1Index = tooltip1Index - 1;
        elseif ( tooltip1Line:find(ITEM_LEVEL) or tooltip1Line:find(ITEM_MIN_LEVEL) ) then
            break;
        elseif ( tooltip1Line == tooltip2Line ) then
            tooltip1Index = tooltip1Index - 1;
            tooltip2Index = tooltip2Index - 1;
        else
            tinker = tooltip1Line;
            anchor = tooltip2Index;
            break;
        end
        tooltip1Line = self:GetTooltipText(tooltip1, tooltip1Index);
        tooltip2Line = self:GetTooltipText(tooltip2, tooltip2Index);
    end

    return tinker, anchor;
end

function Armory:GetRequirementsFromLink(link)
    local tooltip = self:AllocateTooltip();
    tooltip:SetHyperlink(link);
    local reqLevel, reqProfession, reqRank, reqReputation, reqStanding, reqSkill, reqRaces, reqClasses = GetRequirements(tooltip);
    self:ReleaseTooltip(tooltip);
    return reqLevel, reqProfession, reqRank, reqReputation, reqStanding, reqSkill, reqRaces, reqClasses;
end

function Armory:SetHyperlink(tooltip, link, tinker, anchor)
    if ( not (link and tooltip) ) then
        return;
    end

    local color, kind, _, name = self:GetLinkInfo(link);
    if ( kind == "battlepet" ) then
        if ( tooltip == GameTooltip ) then
            local _, speciesID, level, breedQuality, maxHealth, power, speed, battlePetID = strsplit(":", link);
            if ( speciesID and tonumber(speciesID) > 0 ) then
                BattlePetToolTip_Show(tonumber(speciesID), tonumber(level), tonumber(breedQuality), tonumber(maxHealth), tonumber(power), tonumber(speed), name);
            end
        end
    elseif ( not pcall(tooltip.SetHyperlink, tooltip, link) ) then
        tooltip:AddLine(color..name);
        tooltip:AddLine(ARMORY_INVALID_ITEM, RED_FONT_COLOR.r, RED_FONT_COLOR.g, RED_FONT_COLOR.b);
        tooltip:Show();
    elseif ( tinker ) then
        local tooltipLines = self:Tooltip2Table(tooltip, true);
        table.insert(tooltipLines, min(anchor, #tooltipLines) + 1, self:Text2String(tinker, GetTableColor(GREEN_FONT_COLOR)));
        self:Table2Tooltip(tooltip, tooltipLines);
        tooltip:Show();
    end
end

function Armory:AddEnhancedTip(frame, normalText, r, g, b, enhancedText, noNormalText)
    if ( self:GetConfigShowEnhancedTips() ) then
        GameTooltip_SetDefaultAnchor(GameTooltip, frame);
        if ( normalText ) then
            GameTooltip:SetText(normalText, r, g, b);
            GameTooltip:AddLine(enhancedText, NORMAL_FONT_COLOR.r, NORMAL_FONT_COLOR.g, NORMAL_FONT_COLOR.b, 1);
        else
            GameTooltip:SetText(enhancedText, r, g, b, 1, true);
        end
        GameTooltip:Show();
    elseif ( not noNormalText ) then
        GameTooltip:SetOwner(frame, "ANCHOR_RIGHT");
        GameTooltip:SetText(normalText, r, g, b);
    end
end

function Armory:FilterTooltip(tooltip, ...)
    local function Hide(fontString)
        if ( fontString ) then
            fontString:SetText(nil);
            fontString:Hide();
        end
    end

    local name = tooltip:GetName();
    local textLeft, textRight;
    local text, pattern;
    for i = 1, tooltip:NumLines() do
        textLeft = _G[name.."TextLeft"..i];
        textRight = _G[name.."TextRight"..i];
        if ( textLeft and textLeft:IsShown() ) then
            text = GetFontStringTextString(textLeft);
            for j = 1, select("#", ...) do
                local pattern = select(j, ...);
                if ( text:find(pattern) ) then
                    Hide(textLeft);
                    Hide(textRight);
                    break;
                end
            end
            if ( text == "" and i > 1 and (GetFontStringTextString( _G[name.."TextLeft"..i-1]) or "") == "" ) then
                Hide(textLeft);
                Hide(textRight);
            end
        end
    end
    tooltip:Show();
end

function Armory:FindTooltipText(tooltip, pattern)
    local function FindPattern(fontString)
        if ( fontString ) then
            local text = fontString:GetText();
            if ( text and text:find(pattern) ) then
                return text;
            end
        end
    end

    local name = tooltip:GetName();
    for i = 1, tooltip:NumLines() do
        local text = FindPattern(_G[name.."TextLeft"..i]) or FindPattern(_G[name.."TextRight"..i]);
        if ( text ) then
            return text;
        end
    end
end