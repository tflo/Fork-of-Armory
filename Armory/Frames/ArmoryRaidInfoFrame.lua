--[[
    Armory Addon for World of Warcraft(tm).
    Revision: 229 2022-10-30T09:57:47Z
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

local MAX_RAID_INFOS = 20;
local MAX_RAID_INFOS_DISPLAYED = 9;

local VALOR_TIER1_LFG_ID = 301;
local welcomed;

function ArmoryRaidInfoFrame_OnLoad(self)
    self:RegisterEvent("PLAYER_ENTERING_WORLD");
    self:RegisterEvent("UPDATE_INSTANCE_INFO");
    self:RegisterEvent("RAID_INSTANCE_WELCOME");
end

function ArmoryRaidInfoFrame_OnEvent(self, event, ...)
    local arg1, arg2, arg3, arg4 = ...;

    if ( not Armory:CanHandleEvents() ) then
        return;

    elseif ( event == "PLAYER_ENTERING_WORLD" ) then
        --self:UnregisterEvent("PLAYER_ENTERING_WORLD");
        RequestRaidInfo();
        Armory:Execute(
            function()
                Armory:UpdateRaidFinderInfo();
            end
        );

        -- because the RAID_INSTANCE_WELCOME is no longer fired for LFG...
        Armory:ExecuteDelayed(5,
            function()
                if ( welcomed ) then
                    self:UnregisterEvent("PLAYER_ENTERING_WORLD");
                    return
                end
                if ( IsInLFGDungeon() and GetPartyLFGID() ) then
                    local dungeonID = GetPartyLFGID();
                    local instanceName, _, difficultyIndex, difficultyName, maxPlayers = GetInstanceInfo();
                    local dungeonName = GetLFGDungeonInfo(dungeonID);
                    local lockExpireTime = Armory:GetRaidReset(instanceName);
                    if ( lockExpireTime ) then
                        Armory:SaveRaidFinderInfo(dungeonName, dungeonID, lockExpireTime - time(), difficultyIndex, maxPlayers, difficultyName);
                    end
                end
            end
        );

    elseif ( event == "UPDATE_INSTANCE_INFO" ) then
        Armory:Execute(ArmoryRaidInfoFrame_UpdateInfo);

    elseif ( event == "RAID_INSTANCE_WELCOME" ) then
        -- seems event is no longer fired for LFG
        local lockExpireTime = arg2;
        Armory:ExecuteDelayed(1,
            function()
                if ( IsInLFGDungeon() and GetPartyLFGID() ) then
                    welcomed = true;
                    for index = 1, GetNumRFDungeons() do
                        local dungeonID = GetRFDungeonInfo(index);
                        if ( dungeonID == GetPartyLFGID() ) then
                            local _, _, difficultyIndex, difficultyName, maxPlayers = GetInstanceInfo();
                            local dungeonName = GetLFGDungeonInfo(dungeonID);
                            Armory:SaveRaidFinderInfo(dungeonName, dungeonID, lockExpireTime, difficultyIndex, maxPlayers, difficultyName);
                            break;
                        end
                    end
                end
                self:RegisterEvent("PLAYER_ENTERING_WORLD");
            end
        );
    end
end

function ArmoryRaidInfoScrollFrame_OnLoad(self)
    ArmoryHybridScrollFrame_OnLoad(self);
    self.update = ArmoryRaidInfoFrame_Update;
    ArmoryHybridScrollFrame_CreateButtons(self, "ArmoryRaidInfoInstanceTemplate");
end

function ArmoryRaidInfoFrame_OnShow(self)
    ArmoryRaidInfoFrame_Update();
end

function ArmoryRaidInfoFrame_Update(scrollToSelected)
    if ( Armory:UpdateInstancesInProgress() or Armory:UpdateRaidFinderInProgress() or Armory:UpdateWorldBossesInProgress() ) then
        return;
    end
    ArmoryRaidInfoFrame_UpdateSelectedIndex();

    local scrollFrame = ArmoryRaidInfoScrollFrame;
    local savedDungeons = Armory:GetNumRaidFinderDungeons();
    local savedInstances = Armory:GetNumSavedInstances();
    local savedWorldBosses = Armory:GetNumSavedWorldBosses();
    local instanceName, instanceID, instanceReset, instanceDifficulty, locked, extended, instanceIDMostSig, isRaid, maxPlayers, difficultyName, killed;
    local frameName, frameNameText, frameID, frameReset, width;
    local offset = ArmoryHybridScrollFrame_GetOffset(scrollFrame);
    local buttons = scrollFrame.buttons;
    local numButtons = #buttons;
    local buttonHeight = buttons[1]:GetHeight();

    if ( scrollToSelected == true and ArmoryRaidInfoFrame.selectedIndex ) then --Using == true in case the ArmoryHybridScrollFrame .update is changed to pass in the parent.
        local button = buttons[ArmoryRaidInfoFrame.selectedIndex - offset]
        if ( not button or (button:GetTop() > scrollFrame:GetTop()) or (button:GetBottom() < scrollFrame:GetBottom()) ) then
            local buttonHeight = scrollFrame.buttons[1]:GetHeight();
            local scrollValue = min(((ArmoryRaidInfoFrame.selectedIndex - 1) * buttonHeight), scrollFrame.range)
            if ( scrollValue ~= scrollFrame.scrollBar:GetValue() ) then
                scrollFrame.scrollBar:SetValue(scrollValue);
            end
        end
    end

    offset = ArmoryHybridScrollFrame_GetOffset(scrollFrame);    --May have changed in the previous section to move selected parts into view.

    local mouseIsOverScrollFrame = scrollFrame:IsVisible() and scrollFrame:IsMouseOver();
    local frame, index, id;
    for i = 1, numButtons do
        frame = buttons[i];
        index = i + offset;

        if ( index <= savedDungeons ) then
            id = Armory:GetRaidFinderLineId(index);
            instanceName, instanceID, instanceReset, instanceDifficulty, locked, maxPlayers, difficultyName, killed = Armory:GetRaidFinderInfo(id);
            extended = nil;

            frame.instanceID = instanceID;
            frame.longInstanceID = nil;
            frame.killed = killed;

        elseif ( index <= savedDungeons + savedInstances ) then
            index = index - savedDungeons;
            id = Armory:GetInstanceLineId(index);
            instanceName, instanceID, instanceReset, instanceDifficulty, locked, extended, instanceIDMostSig, isRaid, maxPlayers, difficultyName = Armory:GetSavedInstanceInfo(id);

            frame:SetID(index);
            -- prevent integer overflow
            --frame.longInstanceID = string.format("%x%x", instanceIDMostSig, instanceID);
            frame.longInstanceID = instanceIDMostSig..instanceID;
            frame.killed = nil;

        elseif ( index <= savedDungeons + savedInstances + savedWorldBosses ) then
            index = index - savedDungeons - savedInstances;
            id = Armory:GetWorldBossLineId(index);
            instanceName, instanceID, instanceReset = Armory:GetSavedWorldBossInfo(id);
            locked = true;
            extended = false;
            difficultyName = RAID_INFO_WORLD_BOSS;

            frame.longInstanceID = nil;
            frame.killed = nil;

        else
            instanceID = nil;

        end

        frame:SetID(index);

        if ( instanceID ) then
            frame.instanceID = instanceID;

            if ( ArmoryRaidInfoFrame.selectedIndex == index ) then
                frame:LockHighlight();
            else
                frame:UnlockHighlight();
            end

            frame.difficulty:SetText(difficultyName);

            if ( extended or locked ) then
                frame.reset:SetText(SecondsToTime(instanceReset, true, nil, 3));
                frame.name:SetText(instanceName);
            else
                frame.reset:SetFormattedText("|cff808080%s|r", RAID_INSTANCE_EXPIRES_EXPIRED);
                frame.name:SetFormattedText("|cff808080%s|r", instanceName);
            end

            if ( extended ) then
                frame.extended:Show();
            else
                frame.extended:Hide();
            end

            frame:Show();

            if ( mouseIsOverScrollFrame and frame:IsMouseOver() ) then
                ArmoryRaidInfoInstance_OnEnter(frame);
            end
        else
            frame:Hide();
        end
    end
    ArmoryHybridScrollFrame_Update(scrollFrame, (savedInstances + savedDungeons + savedWorldBosses) * buttonHeight, scrollFrame:GetHeight());
end

function ArmoryRaidInfoFrame_UpdateInfo()
    Armory:UpdateInstances();
    Armory:UpdateWorldBosses();
    ArmoryRaidInfoFrame_Update(true);
end

function ArmoryRaidInfoInstance_OnEnter(self)
    if ( self.killed ) then
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT");
        GameTooltip:SetText(ERR_LOOT_GONE);
        for i = 1, table.getn(self.killed) do
            GameTooltip:AddLine(self.killed[i], RED_FONT_COLOR.r, RED_FONT_COLOR.g, RED_FONT_COLOR.b);
        end
        GameTooltip:Show();
    elseif ( self.longInstanceID ) then
        local tooltipLines = Armory:GetInstanceTooltip(self:GetID());
        if ( tooltipLines ) then
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT");
            Armory:Table2Tooltip(GameTooltip, tooltipLines);
            GameTooltip:Show();
        end
    end
end

function ArmoryRaidInfoFrame_UpdateSelectedIndex()
    local savedDungeons = Armory:GetNumRaidFinderDungeons();
    for index = 1, savedDungeons do
        local id = Armory:GetRaidFinderLineId(index);
        local _, instanceID = Armory:GetRaidFinderInfo(id);
        if ( instanceID == ArmoryRaidInfoFrame.instanceID ) then
            ArmoryRaidInfoFrame.selectedIndex = index;
            return;
        end
    end

    local savedInstances = Armory:GetNumSavedInstances();
    for index = 1, savedInstances do
        local id = Armory:GetInstanceLineId(index);
        local _, instanceID, _, _, _, _, instanceIDMostSig = Armory:GetSavedInstanceInfo(id);
        --if ( format("%x%x", instanceIDMostSig, instanceID) == ArmoryRaidInfoFrame.longInstanceID ) then
        if ( instanceIDMostSig..instanceID == ArmoryRaidInfoFrame.longInstanceID ) then
            ArmoryRaidInfoFrame.selectedIndex = index + savedDungeons;
            return;
        end
    end

    local savedWorldBosses = Armory:GetNumSavedWorldBosses();
    for index = 1, savedWorldBosses do
        local id = Armory:GetWorldBossLineId(index);
        local _, instanceID = Armory:GetSavedWorldBossInfo(id);
        if ( instanceID == ArmoryRaidInfoFrame.instanceID ) then
            ArmoryRaidInfoFrame.selectedIndex = index + savedDungeons + savedInstances;
            return;
        end
    end

    ArmoryRaidInfoFrame.selectedIndex = nil;
end
