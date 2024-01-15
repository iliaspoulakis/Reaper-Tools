--[[
  @author Ilias-Timon Poulakis (FeedTheCat)
  @license MIT
  @version 1.0.0
  @noindex
  @about Settings dialog for smart-freeze script
]]
local extname = 'FTC.SmartFreeze'
local title = 'Settings: Smart-freeze'

local settings = {
    {
        caption = 'Unlock items',
        key = 'unlock_items',
        type = 'boolean',
        default = 'yes',
    },
    {
        caption = 'Render tail: (in ms)',
        key = 'render_tail',
        type = 'positive_number',
        default = 2000,
    },
    {
        caption = 'Realtime FX (separated by ;)',
        key = 'realtime_fx',
        type = 'string',
        default = 'ReaInsert;',
    },
}

function BuildCaptions()
    local captions = ''
    local values = ''

    -- Build strings for user input dialog
    for _, setting in ipairs(settings) do
        local value = reaper.GetExtState(extname, setting.key)
        if value == '' then value = setting.default end
        values = values .. value .. ','
        captions = captions .. setting.caption .. ','
    end

    captions = captions .. 'extrawidth=150'
    return captions, values
end

function CheckReturnValues(values)
    local log = ''
    for i, setting in ipairs(settings) do
        if setting.type == 'boolean' then
            if values[i] == '' then values[i] = setting.default end

            local bool = values[i]:lower()
            if bool == 'yes' or bool == 'y' or bool == 'true' or bool == '1' then
                bool = true
            end
            if bool == 'no' or bool == 'n' or bool == 'false' or bool == '0' then
                bool = false
            end
            if type(bool) == 'boolean' then
                values[i] = bool and 'yes' or 'no'
                reaper.SetExtState(extname, setting.key, values[i], true)
            else
                local msg = '\n%s:\n  - has to be either yes or no\n'
                log = log .. msg:format(setting.caption)
            end
        end

        if setting.type == 'number' then
            if values[i] == '' then values[i] = setting.default end
            local num = tonumber(values[i])

            if num and num % 1 == 0 then
                reaper.SetExtState(extname, setting.key, values[i], true)
            else
                local msg = '\n%s:\n  - has to be a number\n'
                log = log .. msg:format(setting.caption)
            end
        end

        if setting.type == 'positive_number' then
            if values[i] == '' then values[i] = setting.default end
            local num = tonumber(values[i])

            if num and num >= 0 and num % 1 == 0 then
                reaper.SetExtState(extname, setting.key, values[i], true)
            else
                local msg = '\n%s:\n  - has to be a number\n'
                log = log .. msg:format(setting.caption)
            end
        end

        if setting.type == 'float' then
            if values[i] == '' then values[i] = setting.default end

            local num = tonumber(values[i])
            if num then
                reaper.SetExtState(extname, setting.key, values[i], true)
            else
                local msg = '\n%s:\n  - has to be a number\n'
                log = log .. msg:format(setting.caption)
            end
        end

        if setting.type == 'positive_float' then
            if values[i] == '' then values[i] = setting.default end

            local num = tonumber(values[i])
            if num and num % 1 == 0 then
                reaper.SetExtState(extname, setting.key, values[i], true)
            else
                local msg = '\n%s:\n  - has to be a number\n'
                log = log .. msg:format(setting.caption)
            end
        end

        if setting.type == 'string' then
            reaper.SetExtState(extname, setting.key, values[i], true)
        end
    end
    return log
end

-- Repeat user input dialog until entries are valid or dialog is canceled
repeat
    local log = ''
    local captions, retvals = BuildCaptions()
    local ret, input = reaper.GetUserInputs(title, #settings, captions, retvals)
    if ret then
        local user_values = {}
        for value in (input .. ','):gmatch('(.-),') do
            user_values[#user_values + 1] = value
        end
        log = CheckReturnValues(user_values)
        if log ~= '' then reaper.MB(log .. '\n ', 'Incorrect input', 0) end
    end
until log == ''

reaper.Undo_OnStateChange('Smart-freeze: Settings')
