--[[
  @author Ilias-Timon Poulakis (FeedTheCat)
  @license MIT
  @version 1.0.0
  @noindex
  @about Generates non-contextual configurations of MeMagic
]]
local _, file_name = reaper.get_action_context()
local seperator = reaper.GetOS():match('win') and '\\' or '/'
local file_path = file_name:match('(.*' .. seperator .. ')')
local file = io.open(file_path .. 'FTC_MeMagic.lua', 'r')

-- Load MeMagic script content
local content = {}
if file then
    for line in file:lines() do
        if line:match('@about') then
            line = '  @noindex\n  @about Automatically generated configuration of MeMagic'
        end
        content[#content + 1] = line
    end
    file:close()
end

-- Create path for generated files
local gen_folder_name = 'Generated'
local dir_path = file_path .. gen_folder_name .. seperator
reaper.RecursiveCreateDirectory(dir_path, 0)

-- Remove old files
local i = 0
repeat
    local file = reaper.EnumerateFiles(dir_path, i)
    if file then
        local file_path = dir_path .. file
        reaper.AddRemoveReaScript(false, 0, file_path, false)
        reaper.AddRemoveReaScript(false, 32060, file_path, false)
    end
    i = i + 1
until not file

for n = i, 0, -1 do
    local file = reaper.EnumerateFiles(dir_path, n)
    if file then
        local file_path = dir_path .. file
        os.remove(file_path)
    end
end

local hmodes = {
    '',
    'zoom to item',
    'zoom to 4 measures at mouse or edit cursor',
    'zoom to 4 measures at at mouse or edit cursor, restrict to item',
    'smart zoom to 10 notes at mouse or edit cursor',
    'smart zoom to 10 notes at mouse or edit cursor, restrict to item',
    'scroll to mouse or edit cursor'
}

local vmodes = {
    '',
    'zoom to notes in visible area',
    'zoom to all notes in item',
    'scroll to note row under mouse cursor',
    'scroll to note row under mouse cursor, restrict to notes in visible area',
    'scroll to note row under mouse cursor, restrict to notes in item',
    'scroll to lowest note in visible area',
    'scroll to lowest note in item',
    'scroll to highest note in visible area',
    'scroll to highest note in item',
    'scroll to center of notes in visible area',
    'scroll to center of notes in item'
}

local hmode_cnt, vmode_cnt = 7, 12

local config = ''
local provides = '    [main=midi_editor] '
local name_pattern = 'FTC_MeMagic (%d-%d) %s%s%s.lua'
-- Generate MeMagic configurations
for h = 1, hmode_cnt do
    for v = 1, vmode_cnt do
        if not (v == 1 and h == 1) then
            local hmode = hmodes[h]
            local vmode = vmodes[v]
            hmode = hmode ~= '' and 'Horizontally ' .. hmode or hmode
            vmode = vmode ~= '' and 'Vertically ' .. vmode or vmode
            local space = hmode ~= '' and vmode ~= '' and ' | ' or ''
            local new_file_name = name_pattern:format(h, v, hmode, space, vmode)
            local new_file_path = dir_path .. new_file_name
            local new_file = io.open(new_file_path, 'w')

            for _, line in ipairs(content) do
                if line:match('local TBB_horizontal_zoom_mode = ') then
                    line = 'local TBB_horizontal_zoom_mode = ' .. h
                end
                if line:match('local TBB_vertical_zoom_mode = ') then
                    line = 'local TBB_vertical_zoom_mode = ' .. v
                end
                if line:match('local use_toolbar_context_only = ') then
                    line = 'local use_toolbar_context_only = true'
                end
                if line:match('local set_edit_cursor = ') then
                    line = 'local set_edit_cursor = false'
                end
                if line:match('local debug = ') then
                    line = 'local debug = false'
                end
                new_file:write(line, '\n')
            end
            new_file:close()
            reaper.AddRemoveReaScript(true, 0, new_file_path, false)
            reaper.AddRemoveReaScript(
                true,
                32060,
                new_file_path,
                v + h == vmode_cnt + hmode_cnt
            )
            config = config .. provides .. gen_folder_name .. '/' .. new_file_name .. '\n'
        end
    end
end

local file = io.open(file_path .. 'FTC_MeMagic bundle.lua', 'w')

if file then
    -- Create package with configurations
    for _, line in ipairs(content) do
        if line:match('@about') then
            local about = '  @about Bundle with all possible configurations of MeMagic\n'
            local meta_pkg = '  @metapackage\n'
            line = about .. meta_pkg .. '  @provides\n' .. config .. ']]'
            content[#content + 1] = line
            file:write(line, '\n')
            break
        end
        content[#content + 1] = line
        file:write(line, '\n')
    end
    file:close()
end
