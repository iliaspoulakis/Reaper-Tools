--[[
  @author Ilias-Timon Poulakis (FeedTheCat)
  @license MIT
  @noindex
  @about Set adaptive grid to narrowest size
]]
local extname = 'FTC.AdaptiveGrid'
local _, file, sec, cmd = reaper.get_action_context()
local path = file:match('^(.+)[\\/]')

local mult = 0

function print(msg) reaper.ShowConsoleMsg(tostring(msg) .. '\n') end

function ConcatPath(...) return table.concat({...}, package.config:sub(1, 1)) end

function GetGridMultiplier()
    return tonumber(reaper.GetExtState(extname, 'main_mult')) or 0
end

function SetGridMultiplier(multiplier)
    reaper.SetExtState(extname, 'main_mult', multiplier, true)
end

function GetMIDIGridMultiplier()
    return tonumber(reaper.GetExtState(extname, 'midi_mult')) or 0
end

function SetMIDIGridMultiplier(multiplier)
    reaper.SetExtState(extname, 'midi_mult', multiplier, true)
end

function RegisterToolbarToggleState(section, command, multiplier)
    local command_name = reaper.ReverseNamedCommandLookup(command)
    local entry = ('%s %s %s'):format(section, command_name, multiplier)
    local entries = reaper.GetExtState(extname, 'toolbar_entries')
    if not entries:find(entry, 0, true) then
        entries = entries .. entry .. ';'
        reaper.SetExtState(extname, 'toolbar_entries', entries, true)
    end
end

function UpdateToolbarToggleStates(section, multiplier)
    local entries = reaper.GetExtState(extname, 'toolbar_entries')
    local updated_entries = ''
    for entry in entries:gmatch('(.-);') do
        local pattern = '(%d+) (.-) (%-?%d+)'
        local entry_sec, entry_cmd_name, entry_mult = entry:match(pattern)
        entry_sec = tonumber(entry_sec)
        entry_mult = tonumber(entry_mult)
        local entry_cmd = reaper.NamedCommandLookup('_' .. entry_cmd_name)
        if section == entry_sec and entry_cmd > 0 then
            local state = entry_mult == multiplier and 1 or 0
            if entry_mult == 1000 and multiplier ~= 0 then state = 1 end
            reaper.SetToggleCommandState(entry_sec, entry_cmd, state)
            reaper.RefreshToolbar2(entry_sec, entry_cmd)
            updated_entries = updated_entries .. entry .. ';'
        elseif section ~= entry_sec then
            updated_entries = updated_entries .. entry .. ';'
        end
    end
    if updated_entries ~= entries then
        reaper.SetExtState(extname, 'toolbar_entries', updated_entries, true)
    end
end

reaper.Undo_BeginBlock()

RegisterToolbarToggleState(sec, cmd, mult)

if sec == 32060 then
    SetMIDIGridMultiplier(mult)
else
    SetGridMultiplier(mult)
end

UpdateToolbarToggleStates(sec, mult)

reaper.Undo_EndBlock('Set grid to fixed (adaptive)', -1)
