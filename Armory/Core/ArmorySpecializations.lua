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
local container = "Specializations";

----------------------------------------------------------
-- Specializations Storage
----------------------------------------------------------

function Armory:SetSpecializations(unit)
    local isPet = (strlower(unit) == "pet");

    if ( not self:IsLocked(container) ) then
        self:Lock(container);

        self:PrintDebug("UPDATE", container);

        local oldNum = self:GetClassNumValues(unit, container);
        local newNum = _G.GetNumSpecializations(false, isPet);
        for i = 1, max(oldNum, newNum) do
            if ( i > newNum ) then
                self:SetClassValue(unit, 2, container, i, nil);
            else
                self:SetClassValue(unit, 2, container, i, _G.GetSpecializationInfo(i, false, isPet, nil, isPet and _G.UnitSex("pet") or _G.UnitSex("player")));
            end
        end

        self:Unlock(container);
    else
        self:PrintDebug("LOCKED", container);
    end
end

----------------------------------------------------------
-- Specializations Interface
----------------------------------------------------------

function Armory:GetNumSpecializations(inspect, pet)
    local unit = ((pet and "pet") or "player");
    local numSpecs = self:GetClassNumValues(unit, container);
    -- Provide backwards compatibility
    if ( not pet and not numSpecs ) then
        local _, _, classID = self:UnitClass(unit);
        numSpecs = _G.GetNumSpecializationsForClassID(classID);
    end
    return numSpecs or 0;
end

function Armory:GetSpecializationInfo(index, inspect, pet, dummy, sex)
    local unit = ((pet and "pet") or "player");
    -- Provide backwards compatibility
    if ( not pet and not self:GetClassValue(unit, container, index) ) then
        local _, _, classID = self:UnitClass(unit);
        -- As 7th (now 6th?) value this will return a boolean while GetSpecializationInfo() will return a stat index
        return _G.GetSpecializationInfoForClassID(classID, index, sex);
    end
    return self:GetClassValue(unit, container, index);
end

function Armory:GetSpecializationRole(index, inspect, pet)
    local _, _, _, _, role = self:GetSpecializationInfo(index, inspect, pet, nil, Armory:UnitSex((pet and "pet") or "player"));
    return role;
end
