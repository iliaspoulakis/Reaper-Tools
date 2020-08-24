--[[
  @author Ilias-Timon Poulakis (FeedTheCat)
  @license MIT
  @version 1.1.2
  @noindex
  @about Settings dialog for all FolderMagic scripts
]]
reaper.Undo_BeginBlock()

local extname = 'FTC.FolderMagic'
local mb_title = 'FolderMagic: Settings'

local settings = {
    {
        caption = 'Mode: Single click',
        key = 'mode_sc',
        type = 'int',
        default = 1
    },
    {
        caption = 'Mode: Double click',
        key = 'mode_dc',
        type = 'int',
        default = 2
    },
    {
        caption = 'Item emphasis factor',
        key = 'emphasis_factor',
        type = 'float',
        default = 3.5
    },
    {
        caption = 'Treat root tracks like folders',
        key = 'use_tracks',
        type = 'boolean',
        default = 'no'
    },
    {
        caption = 'Minimum folder depth (root level)',
        key = 'min_depth',
        type = 'int',
        default = 0
    },
    {
        caption = 'Maximum folder depth',
        key = 'max_depth',
        type = 'int',
        default = 0
    },
    {
        caption = 'Pinned track name',
        key = 'pinned_name',
        type = 'string',
        default = ''
    }
}

function checkType(values, settings)
    local log = ''
    for i, setting in ipairs(settings) do
        if setting.type == 'boolean' then
            local bool = values[i]:lower()
            if bool == 'yes' or bool == 'y' or bool == 'true' then
                bool = true
            end
            if bool == 'no' or bool == 'n' or bool == 'false' then
                bool = false
            end
            if type(bool) ~= 'boolean' then
                local msg =
                    '\n%s:\n--> has to be either yes (y, true) or no (n, false)!\n'
                log = log .. msg:format(setting.caption)
            end
            values[i] = bool and 'yes' or 'no'
        end

        if setting.type == 'int' then
            values[i] = values[i] == '' and 0 or tonumber(values[i])
            if not values[i] or values[i] < 0 or values[i] % 1 ~= 0 then
                local msg = '\n%s:\n--> has to be a positive round number!\n'
                log = log .. msg:format(setting.caption)
            end
        end
        if setting.type == 'float' then
            values[i] = values[i] == '' and 0 or tonumber(values[i])
            if not values[i] or values[i] < 0 then
                local msg = '\n%s:\n--> has to be a positive number!\n'
                log = log .. msg:format(setting.caption)
            end
        end
    end
    return log
end

local captions = ''
local values = ''
-- Build strings for user input dialog
for i, setting in ipairs(settings) do
    local value = reaper.GetExtState(extname, setting.key)
    if value == '' then
        value = setting.default
    end
    values = values .. value .. ','
    captions = captions .. setting.caption .. ','
end

-- Repeat user input dialog until entries are valid or dialog is cancelled
repeat
    local log = ''
    local ret, user_input = reaper.GetUserInputs(mb_title, #settings, captions, values)
    if ret then
        -- Ensure that empty entries will be matched by inserting whitespaces
        local user_input, cnt = user_input:gsub(',', ' , ')

        local user_values = {}
        for value in user_input:gmatch('[^,]*') do
            -- Remove trailing and leading whitespaces
            value = value:gsub('^%s*(.-)%s*$', '%1')
            user_values[#user_values + 1] = value
        end

        log = checkType(user_values, settings)
        if cnt >= #settings then
            log = '\nCommas ( , ) are not allowed!\n'
        end
        if log ~= '' then
            reaper.MB(log .. '\n ', 'Incorrect input', 0)
        else
            for i, value in ipairs(user_values) do
                reaper.SetExtState(extname, settings[i].key, value, true)
            end
        end
    end
until log == ''

reaper.Undo_EndBlock('FolderMagic: Settings', 0)
