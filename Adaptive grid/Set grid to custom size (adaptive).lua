--[[
  @author Ilias-Timon Poulakis (FeedTheCat)
  @license MIT
  @noindex
  @about Set adaptive grid to a custom user defined size
]]
local extname = 'FTC.AdaptiveGrid'
local _, file, sec, cmd = reaper.get_action_context()
local path = file:match('^(.+)[\\/]')

local mult = -1
local min_spacing

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

function IsServiceRunning()
    return reaper.GetExtState(extname, 'is_service_running') ~= ''
end

function SetServiceRunning(is_running)
    local value = is_running and 'yes' or ''
    reaper.SetExtState(extname, 'is_service_running', value, false)
end

function StartService()
    if GetGridMultiplier() == 0 and GetMIDIGridMultiplier() == 0 then return end

    local script_name = 'Adaptive grid (background service).lua'
    local script_path = ConcatPath(path, script_name)

    if not reaper.file_exists(script_path) then
        local msg = 'Could not start background service!\n\nFile not found:\n%s'
        reaper.MB(msg:format(script_path), 'Adaptive grid', 0)
        return
    end

    local service_cmd = reaper.AddRemoveReaScript(true, 0, script_path, true)
    reaper.Main_OnCommand(service_cmd, 0)
    reaper.AddRemoveReaScript(false, 0, script_path, true)
end

function RunAdaptScript(is_midi)
    local script_path = ConcatPath(path, 'Adapt grid to zoom level.lua')

    if is_midi then
        local hwnd = reaper.MIDIEditor_GetActive()
        if hwnd then
            _G.mode = 2
            dofile(script_path)
        end
    else
        _G.mode = 1
        dofile(script_path)
    end
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

function GetUserCustomGridSpacing(is_midi)
    local key = is_midi and 'midi_custom_spacing' or 'custom_spacing'
    local caption = 'Minimum grid spacing in pixels:'
    local custom_spacing = reaper.GetExtState(extname, key)
    local title = 'Adaptive Grid'
    local ret, spacing = reaper.GetUserInputs(title, 1, caption, custom_spacing)
    if not ret then return end
    spacing = tonumber(spacing) or 0
    if spacing <= 0 then
        reaper.MB('Value not permitted!', 'Error', 0)
        return false
    else
        if spacing < (is_midi and 15 or min_spacing) then
            local status = ' (Currently: %s pixels in grid settings)'
            status = is_midi and ' (15px)' or status:format(min_spacing)
            local msg = 'The value you set is smaller than the minimum \z
                 grid line spacing%s.\n\z
                 This might have unwanted side effects.'
            reaper.MB(msg:format(status), 'Warning', 0)
        end
        reaper.SetExtState(extname, key, spacing, true)
        return true
    end
end

function CheckUserCustomGridSpacing(is_midi)
    local key = is_midi and 'midi_custom_spacing' or 'custom_spacing'
    local curr_spacing = tonumber(reaper.GetExtState(extname, key))
    if curr_spacing then return curr_spacing end
    return GetUserCustomGridSpacing(is_midi)
end

reaper.Undo_BeginBlock()

local ret, projgridmin = reaper.get_config_var_string('projgridmin')
if ret then
    min_spacing = tonumber(projgridmin) or 8
elseif reaper.SNM_GetIntConfigVar then
    min_spacing = reaper.SNM_GetIntConfigVar('projgridmin', 8)
else
    min_spacing = tonumber(reaper.GetExtState(extname, 'projgridmin')) or 8
end

if not CheckUserCustomGridSpacing(sec == 32060) then
    reaper.Undo_EndBlock('Set grid to custom size (adaptive)', -1)
    return
end

RegisterToolbarToggleState(sec, cmd, mult)

local is_enabled = reaper.GetToggleCommandStateEx(sec, cmd) == 1
if is_enabled then mult = 0 end

if sec == 32060 then
    SetMIDIGridMultiplier(mult)
    RunAdaptScript(true)
else
    SetGridMultiplier(mult)
    RunAdaptScript(false)
end

UpdateToolbarToggleStates(sec, mult)

reaper.Undo_EndBlock('Set grid to custom size (adaptive)', -1)

-- Start defer background service
if not IsServiceRunning() then StartService() end
