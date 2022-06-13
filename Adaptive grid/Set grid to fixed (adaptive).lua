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
    local reg_str = ('%s %s %s'):format(section, command, multiplier)
    local registered_cmds = reaper.GetExtState(extname, 'registered_cmds')
    if not registered_cmds:match(reg_str) then
        registered_cmds = registered_cmds .. reg_str .. ';'
        reaper.SetExtState(extname, 'registered_cmds', registered_cmds, true)
    end
end

function UpdateToolbarToggleStates(section, multiplier)
    local registered_cmds = reaper.GetExtState(extname, 'registered_cmds')
    for reg_str in registered_cmds:gmatch('(.-);') do
        local reg_sec, reg_cmd, reg_mult = reg_str:match('(%d+) (%d+) (%-?%d+)')
        reg_sec = tonumber(reg_sec)
        reg_cmd = tonumber(reg_cmd)
        reg_mult = tonumber(reg_mult)
        if section == reg_sec then
            local state = reg_mult == multiplier and 1 or 0
            reaper.SetToggleCommandState(reg_sec, reg_cmd, state)
            reaper.RefreshToolbar2(reg_sec, reg_cmd)
        end
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

