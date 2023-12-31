--[[
    Armory Addon for World of Warcraft(tm).
    Revision: 204 2022-10-30T09:57:47Z
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
local container = "WorldBosses";

----------------------------------------------------------
-- Raid Info World Bosses Internals
----------------------------------------------------------

local instanceLines = {};
local dirty = true;
local owner = "";

local function GetWorldBossLines()
    local dbEntry = Armory.selectedDbBaseEntry;

    table.wipe(instanceLines);

    if ( dbEntry ) then
        local count = dbEntry:GetNumValues(container);

        for i = 1, count do
            _, _, instanceReset = Armory:GetSavedWorldBossInfo(i);
            if ( instanceReset > 0 ) then
                table.insert(instanceLines, i);
            end
        end
    end

    dirty = false;
    owner = Armory:SelectedCharacter();

    return instanceLines;
end

--[[
local WOD_WORLD_BOSSES = {
    ["Drov the Ruiner"]    = {id=1291, quest=37460},
    ["Tarlna the Ageless"] = {id=1211, quest=37462},
    ["Rukhmar"]            = {id=1262, quest=37464}
};

local wodBosses = {};
local function GetWoDSavedWorldBossInfo()
    table.wipe(wodBosses);
    for _, info in pairs(WOD_WORLD_BOSSES) do
        if ( C_QuestLog.IsQuestFlaggedCompleted(info.quest) ) then
            local id, name = EJ_GetCreatureInfo(1, info.id);
            local reset = Armory:GetWeeklyQuestResetTime() - time();
            table.insert(wodBosses, {name, id, reset});
        end
    end
    return wodBosses;
end
--]]

----------------------------------------------------------
-- Raid Info World Bosses Storage
----------------------------------------------------------

function Armory:ClearWorldBosses()
    self:ClearModuleData(container);
    dirty = true;
end

function Armory:UpdateWorldBosses()
    local dbEntry = self.playerDbBaseEntry;
    if ( not dbEntry ) then
        return;
    elseif ( not self:RaidEnabled() ) then
        dbEntry:SetValue(container, nil);
        return;
    end

    if ( not self:IsLocked(container) ) then
        self:Lock(container);

        self:PrintDebug("UPDATE", container);

        --local wodBosses = GetWoDSavedWorldBossInfo();
        local numSaved = _G.GetNumSavedWorldBosses();

        local oldNum = dbEntry:GetNumValues(container);
        local newNum = numSaved;-- + #wodBosses;

        if ( newNum == 0 ) then
            dbEntry:SetValue(container, nil);
        else
            dbEntry:SelectContainer(container);
            dbEntry:SetValue(2, container, "TimeStamp", time());
            for i = 1, max(oldNum, newNum) do
                if ( i > newNum ) then
                    dbEntry:SetValue(2, container, i, nil);
                else--if ( i <= numSaved ) then
                    dbEntry:SetValue(2, container, i, _G.GetSavedWorldBossInfo(i));
                --else
                    --dbEntry:SetValue(2, container, i, unpack(wodBosses[i - numSaved]));
                end
            end
        end

        dirty = dirty or self:IsPlayerSelected();

        self:Unlock(container);
    else
        self:PrintDebug("LOCKED", container);
    end
end

function Armory:UpdateWorldBossesInProgress()
    return self:IsLocked(container);
end

----------------------------------------------------------
-- Raid Info World Bosses Interface
----------------------------------------------------------

function Armory:GetNumSavedWorldBosses()
    if ( dirty or not self:IsSelectedCharacter(owner) ) then
        GetWorldBossLines();
    end
    return #instanceLines;
end

function Armory:GetSavedWorldBossInfo(id)
    local dbEntry = self.selectedDbBaseEntry;
    if ( dbEntry ) then
        local timestamp = dbEntry:GetValue(container, "TimeStamp");
        local instanceName, instanceID, instanceReset = dbEntry:GetValue(container, id);

        if ( instanceReset ) then
            instanceReset = instanceReset - (time() - timestamp);
            if ( instanceReset <= 0 ) then
                instanceReset = 0;
            end
        end

        return instanceName, instanceID, instanceReset;
    end
end

function Armory:GetWorldBossLineId(index)
    if ( dirty or not self:IsSelectedCharacter(owner) ) then
        GetInstanceLines();
    end
    return instanceLines[index];
end
