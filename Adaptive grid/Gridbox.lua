--[[
  @author Ilias-Timon Poulakis (FeedTheCat)
  @license MIT
  @version 1.1.3
  @about Adds a little box to transport that displays project grid information
  @changelog
    - Fix font family setting not being saved
]]

local extname = 'FTC.GridBox'

local bm_w
local bm_h
local bm_x
local bm_y

local attach_mode
local attach_x

local user_bg_color
local user_border_color
local user_text_color
local user_swing_color
local user_corner_radius
local user_adaptive_color
local user_font_size
local user_font_family

local transport_hwnd
local transport_w
local transport_h

local prev_time
local prev_transport_w
local prev_transport_h
local prev_color_theme
local prev_main_mult
local prev_swing_amt
local prev_grid_div

local grid_text
local is_adaptive

local drag_x
local drag_y

local is_left_click = false
local is_right_click = false

local menu_time

local bitmap
local lice_font
local font_size

local is_redraw = false
local is_resize = false
local resize_flags = 0

local adaptive_names = {}
adaptive_names[-1] = 'Custom'
adaptive_names[1] = 'Narrowest'
adaptive_names[2] = 'Narrow'
adaptive_names[3] = 'Medium'
adaptive_names[4] = 'Wide'
adaptive_names[6] = 'Widest'

local has_reapack = reaper.ReaPack_BrowsePackages ~= nil
local missing_dependencies = {}

function print(...)
    local values = {...}
    for i = 1, #values do values[i] = tostring(values[i]) end
    if #values == 0 then values[1] = 'nil' end
    reaper.ShowConsoleMsg(table.concat(values, ' ') .. '\n')
end

-- Check if js_ReaScriptAPI extension is installed
if not reaper.JS_Window_SetPosition then
    if has_reapack then
        table.insert(missing_dependencies, 'js_ReaScriptAPI')
    else
        reaper.MB('Please install js_ReaScriptAPI extension', 'Error', 0)
        return
    end
end

-- Load scripts from Adaptive Grid
local _, file, sec, cmd = reaper.get_action_context()
local file_dir = file:match('^(.+)[\\/]')

function ConcatPath(...) return table.concat({...}, package.config:sub(1, 1)) end

local adjust_script = ConcatPath(file_dir, 'Adjust adaptive grid (mousewheel).lua')
local menu_script = ConcatPath(file_dir, 'Adaptive grid menu.lua')

if not reaper.file_exists(adjust_script) or not reaper.file_exists(menu_script) then
    if has_reapack then
        table.insert(missing_dependencies, 'Adaptive Grid')
    else
        reaper.MB('Please install Adaptive Grid', 'Error', 0)
        return
    end
end

if #missing_dependencies > 0 then
    local msg = ('Missing dependencies:\n\n'):format(#missing_dependencies)
    for _, dependency in ipairs(missing_dependencies) do
        msg = msg .. ' • ' .. dependency .. '\n'
    end
    reaper.MB(msg, 'Error', 0)

    for i = 1, #missing_dependencies do
        if missing_dependencies[i]:match(' ') then
            missing_dependencies[i] = '"' .. missing_dependencies[i] .. '"'
        end
    end
    reaper.ReaPack_BrowsePackages(table.concat(missing_dependencies, " OR "))
    return
end

-- Check REAPER version
local version = tonumber(reaper.GetAppVersion():match('[%d.]+'))
if version >= 7.03 then reaper.set_action_options(1) end

-- Detect operating system
local os = reaper.GetOS()
local is_windows = os:match('Win')
local is_macos = os:match('OSX') or os:match('macOS')
local is_linux = os:match('Other')

-- Detect REAPER UI scale
function GetWindowScale()
    local main_hwnd = reaper.GetMainHwnd()
    local _, main_l, main_r = reaper.JS_Window_GetRect(main_hwnd)
    reaper.TrackCtl_SetToolTip(' ', main_l, main_r, false)
    local tt_hwnd = reaper.GetTooltipWindow()
    local _, _, tt_t, _, tt_b = reaper.JS_Window_GetRect(tt_hwnd)
    reaper.TrackCtl_SetToolTip('', main_l, main_r, false)
    reaper.JS_Window_Show(tt_hwnd, 'HIDE')
    local tt_h = math.abs(tt_b - tt_t)
    return tt_h / (is_windows and 20 or is_macos and 17 or 19)
end

local _, ini_scale = reaper.get_config_var_string('uiscale', '')
ini_scale = tonumber(ini_scale) or 1
local scale = ini_scale * GetWindowScale()

-- Smallest size the bitmap is allowed to have (width and height in pixels)
local min_area_size = math.floor(12 * scale)

-------------------------------- FUNCTIONS -----------------------------------

function EscapeString(str)
    local function EscapeChar(char)
        if char == ',' then return '\\,' end
        if char == ':' then return '\\:' end
        if char == '{' then return '\\[' end
        if char == '}' then return '\\]' end
        if char == '\\' then return '\\&' end
    end
    return str:gsub('[,:{}\\]', EscapeChar)
end

function UnEscapeString(str)
    local function UnEscapeChar(char)
        if char == ',' then return ',' end
        if char == ':' then return ':' end
        if char == '[' then return '{' end
        if char == ']' then return '}' end
        if char == '&' then return '\\' end
    end
    return str:gsub('\\([,:%[%]&])', UnEscapeChar)
end

function Serialize(value, add_newlines)
    local value_type = type(value)
    if value_type == 'string' then return 's:' .. EscapeString(value) end
    if value_type == 'number' then return 'n:' .. value end
    if value_type == 'boolean' then return 'b:' .. (value and 1 or 0) end
    if value_type == 'table' then
        local value_str = 't:{'
        local has_elems = false
        for key, elem in pairs(value) do
            if type(elem) ~= 'function' then
                -- Avoid adding protected elements that start with underscore
                local is_str_key = type(key) == 'string'
                if not is_str_key or key:sub(1, 1) ~= '_' then
                    if is_str_key then key = EscapeString(key) end
                    if not has_elems and add_newlines then
                        value_str = value_str .. '\n'
                    end
                    local entry = Serialize(elem, add_newlines)
                    value_str = value_str .. key .. ':' .. entry .. ','
                    if add_newlines then value_str = value_str .. '\n' end
                    has_elems = true
                end
            end
        end
        if has_elems then
            value_str = value_str:sub(1, -2)
            if add_newlines then value_str = value_str .. '\n' end
        end
        return value_str .. '}'
    end
    return ''
end

function Deserialize(value_str)
    local value_type, payload = value_str:sub(1, 1), value_str:sub(3)
    if value_type == 's' then return UnEscapeString(payload) end
    if value_type == 'n' then return tonumber(payload) end
    if value_type == 'b' then return payload == '1' end
    if value_type == 't' then
        local matches = {}
        local m = 0

        local function AddMatch(table_str)
            m = m + 1
            local match = {}
            local i = 1
            for value in (table_str .. ','):gmatch('(.-[^\\]),\r?\n?') do
                match[i] = value
                i = i + 1
            end
            matches[m] = match
            return m
        end

        local _, bracket_cnt = payload:gsub('{', '')
        for _ = 1, bracket_cnt do
            payload = payload:gsub('{\r?\n?([^{}]*)\r?\n?}', AddMatch, 1)
        end

        local function AssembleTable(match)
            local ret = {}
            for _, elem in ipairs(match) do
                local key, value = elem:match('^(.-[^\\]):(.-)$')
                key = tonumber(key) or UnEscapeString(key)
                if value:sub(1, 1) == 't' then
                    local n = tonumber(value:match('^t:(.-)$'))
                    ret[key] = AssembleTable(matches[n])
                else
                    ret[key] = Deserialize(value)
                end
            end
            return ret
        end
        return AssembleTable(matches[m])
    end
end

function ExtSave(key, value, is_temporary)
    local value_str = Serialize(value)
    if not value_str then return end
    reaper.SetExtState(extname, key, value_str, not is_temporary)
end

function ExtLoad(key, default)
    local value = default
    local value_str = reaper.GetExtState(extname, key)
    if value_str ~= '' then value = Deserialize(value_str) end
    return value
end

function GetStartupHookCommandID()
    -- Note: Startup hook commands have to be in the main section
    local _, script_file, section, cmd_id = reaper.get_action_context()
    if section == 0 then
        -- Save command name when main section script is run first
        local cmd_name = '_' .. reaper.ReverseNamedCommandLookup(cmd_id)
        reaper.SetExtState(extname, 'hook_cmd_name', cmd_name, true)
    else
        -- Look for saved command name by main section script
        local cmd_name = reaper.GetExtState(extname, 'hook_cmd_name')
        cmd_id = reaper.NamedCommandLookup(cmd_name)
        if cmd_id == 0 then
            -- Add the script to main section (to get cmd id)
            cmd_id = reaper.AddRemoveReaScript(true, 0, script_file, true)
            if cmd_id ~= 0 then
                -- Save command name to avoid adding script on next run
                cmd_name = '_' .. reaper.ReverseNamedCommandLookup(cmd_id)
                reaper.SetExtState(extname, 'hook_cmd_name', cmd_name, true)
            end
        end
    end
    return cmd_id
end

function IsStartupHookEnabled()
    local res_path = reaper.GetResourcePath()
    local startup_path = ConcatPath(res_path, 'Scripts', '__startup.lua')
    local cmd_id = GetStartupHookCommandID()
    local cmd_name = reaper.ReverseNamedCommandLookup(cmd_id)

    if reaper.file_exists(startup_path) then
        -- Read content of __startup.lua
        local startup_file = io.open(startup_path, 'r')
        if not startup_file then return false end
        local content = startup_file:read('*a')
        startup_file:close()

        -- Find line that contains command id (also next line if available)
        local pattern = '[^\n]+' .. cmd_name .. '\'?\n?[^\n]+'
        local s, e = content:find(pattern)

        -- Check if line exists and whether it is commented out
        if s and e then
            local hook = content:sub(s, e)
            local comment = hook:match('[^\n]*%-%-[^\n]*reaper%.Main_OnCommand')
            if not comment then return true end
        end
    end
    return false
end

function SetStartupHookEnabled(is_enabled, comment, var_name)
    local res_path = reaper.GetResourcePath()
    local startup_path = ConcatPath(res_path, 'Scripts', '__startup.lua')
    local cmd_id = GetStartupHookCommandID()
    local cmd_name = reaper.ReverseNamedCommandLookup(cmd_id)

    local content = ''
    local hook_exists = false

    -- Check startup script for existing hook
    if reaper.file_exists(startup_path) then
        local startup_file = io.open(startup_path, 'r')
        if not startup_file then return end
        content = startup_file:read('*a')
        startup_file:close()

        -- Find line that contains command id (also next line if available)
        local pattern = '[^\n]+' .. cmd_name .. '\'?\n?[^\n]+'
        local s, e = content:find(pattern)

        if s and e then
            -- Add/remove comment from existing startup hook
            local hook = content:sub(s, e)
            local repl = (is_enabled and '' or '-- ') .. 'reaper.Main_OnCommand'
            hook = hook:gsub('[^\n]*reaper%.Main_OnCommand', repl, 1)
            content = content:sub(1, s - 1) .. hook .. content:sub(e + 1)

            -- Write changes to file
            local new_startup_file = io.open(startup_path, 'w')
            if not new_startup_file then return end
            new_startup_file:write(content)
            new_startup_file:close()

            hook_exists = true
        end
    end

    -- Create startup hook
    if is_enabled and not hook_exists then
        comment = comment and '-- ' .. comment .. '\n' or ''
        var_name = var_name or 'cmd_name'
        local hook = '%slocal %s = \'_%s\'\nreaper.\z
            Main_OnCommand(reaper.NamedCommandLookup(%s), 0)\n\n'
        hook = hook:format(comment, var_name, cmd_name, var_name)
        local startup_file = io.open(startup_path, 'w')
        if not startup_file then return end
        startup_file:write(hook .. content)
        startup_file:close()
    end
end

function CreateMenuRecursive(menu)
    local str = ''
    if menu.title then str = str .. '>' .. menu.title .. '|' end

    for _, entry in ipairs(menu) do
        if entry then
            local arg = entry.arg
            if entry.IsGrayed and entry.IsGrayed(arg) or entry.is_grayed then
                str = str .. '#'
            end
            if entry.IsChecked and entry.IsChecked(arg) or entry.is_checked then
                str = str .. '!'
            end
            if #entry > 0 then
                str = str .. CreateMenuRecursive(entry) .. '|'
            else
                if entry.title or entry.separator then
                    local shortcut = entry.shortcut and '\t ' .. entry.shortcut or
                        ''
                    str = str .. (entry.title or '') .. shortcut .. '|'
                end
            end
        end
    end
    if menu.title then str = str .. '<' end
    return str
end

function ReturnMenuRecursive(menu, idx, i)
    i = i or 1
    for _, entry in ipairs(menu) do
        if entry then
            if #entry > 0 then
                i = ReturnMenuRecursive(entry, idx, i)
                if i < 0 then return i end
            elseif entry.title then
                if i == math.floor(idx) then
                    if entry.OnReturn then entry.OnReturn(entry.arg) end
                    return -1
                end
                i = i + 1
            end
        end
    end
    return i
end

function GetRelativeThemePath(theme_path)
    local resource_dir = reaper.GetResourcePath()
    -- Note: Using find to suppress matching special characters in path
    local _, end_idx = theme_path:find(resource_dir, 0, true)
    if end_idx then
        local rel_path = theme_path:sub(end_idx + 2)
        return rel_path
    end
end

function LoadThemeSettings(theme_path)
    local settings
    -- If theme inside resource folder, try and load from relative path
    local rel_theme_path = GetRelativeThemePath(theme_path)
    if rel_theme_path then settings = ExtLoad(rel_theme_path) end
    -- Note: Theme path can be empty in new REAPER installations?
    if theme_path == '' then theme_path = 'default' end
    -- Fallback to full path
    if not settings then
        settings = ExtLoad(theme_path)
    end

    local has_settings = settings ~= nil
    settings = settings or {}

    local x = settings.bm_x
    local y = settings.bm_y
    local w = settings.bm_w
    local h = settings.bm_h

    attach_x = settings.attach_x
    attach_mode = settings.attach_mode
    if attach_x then x = GetAttachPosition() end
    SetBitmapCoords(x, y, w, h)

    user_bg_color = settings.bg_color
    user_text_color = settings.text_color
    user_border_color = settings.border_color
    user_swing_color = settings.swing_color
    user_adaptive_color = settings.adaptive_color
    user_font_size = settings.font_size
    user_font_family = settings.font_family
    user_corner_radius = settings.corner_radius
    return has_settings
end

function SaveThemeSettings(theme_path)
    local settings = {
        bm_x = bm_x,
        bm_y = bm_y,
        bm_w = bm_w,
        bm_h = bm_h,
        attach_x = attach_x,
        attach_mode = attach_mode,
        bg_color = user_bg_color,
        text_color = user_text_color,
        border_color = user_border_color,
        swing_color = user_swing_color,
        adaptive_color = user_adaptive_color,
        font_size = user_font_size,
        font_family = user_font_family,
        corner_radius = user_corner_radius,
    }

    -- If theme inside resource folder, save as relative path
    theme_path = GetRelativeThemePath(theme_path) or theme_path
    if theme_path == '' then theme_path = 'default' end
    ExtSave(theme_path, settings)
end

function RGBAToHex(r, g, b, a)
    local int_color = r * 65536 + g * 256 + b
    if not a or a == 255 then return ('#%06x'):format(int_color) end
    return ('#%06x%02x'):format(int_color, a)
end

function IntToHex(int_color)
    local r, g, b = reaper.ColorFromNative(int_color)
    return RGBAToHex(r, g, b)
end

function GetUserColor()
    local ret, color = reaper.GR_SelectColor(reaper.GetMainHwnd())
    if ret ~= 0 then return IntToHex(color):gsub('#', '') end
end

function SetCustomSize()
    local title = 'Size/Position'
    local captions = 'Width:,Height:,X pos:,Y pos:'

    local floor = math.floor
    local curr_vals = {floor(bm_w), floor(bm_h), floor(bm_x), floor(bm_y)}
    local curr_vals_str = table.concat(curr_vals, ',')

    local ret, inputs = reaper.GetUserInputs(title, 4, captions, curr_vals_str)
    if not ret or inputs == curr_vals_str then return end

    local input_vals = {}
    for input in (inputs .. ','):gmatch('[^,]*') do
        input_vals[#input_vals + 1] = tonumber(input)
    end

    local x, y, w, h
    if input_vals[1] then w = floor(input_vals[1] + 0.5) end
    if input_vals[2] then h = floor(input_vals[2] + 0.5) end
    if input_vals[3] then x = floor(input_vals[3] + 0.5) end
    if input_vals[4] then y = floor(input_vals[4] + 0.5) end
    SetBitmapCoords(x, y, w, h)

    UpdateAttachPosition()
    EnsureBitmapVisible()

    SaveThemeSettings(prev_color_theme)
end

function SetCustomCornerRadius()
    local title = 'Corners'
    local captions = 'Corner radius: (e.g. 4)'

    local curr_vals_str = ('%s'):format(user_corner_radius or '')

    local ret, inputs = reaper.GetUserInputs(title, 1, captions, curr_vals_str)
    if not ret or inputs == curr_vals_str then return end

    local input_vals = {}
    for input in (inputs .. ','):gmatch('[^,]*') do
        input_vals[#input_vals + 1] = input
    end

    user_corner_radius = tonumber(input_vals[1])
    is_redraw = true

    SaveThemeSettings(prev_color_theme)
end

function SetCustomFont()
    local title = 'Font'
    local captions = 'Size: (e.g.42),Family (e.g. Comic Sans),extrawidth=50'

    local curr_vals_str = ('%s,%s'):format(user_font_size or '', user_font_family or '')

    local ret, inputs = reaper.GetUserInputs(title, 2, captions, curr_vals_str)
    if not ret or inputs == curr_vals_str then return end

    local input_vals = {}
    for input in (inputs .. ','):gmatch('[^,]*') do
        input_vals[#input_vals + 1] = input
    end

    user_font_size = tonumber(input_vals[1])
    user_font_family = input_vals[2]
    if user_font_family == '' then user_font_family = nil end
    is_resize = true

    SaveThemeSettings(prev_color_theme)
end

function SetCustomColors()
    local title = 'Custom Colors'
    local captions = 'Background: (e.g. #525252),Text:,Border:,Swing:,Adaptive:'

    local curr_vals = {}
    local function AddCurrentValue(color)
        local hex_num = color and tonumber(color, 16)
        curr_vals[#curr_vals + 1] = hex_num and ('#%.6X'):format(hex_num) or ''
    end

    AddCurrentValue(user_bg_color)
    AddCurrentValue(user_text_color)
    AddCurrentValue(user_border_color)
    AddCurrentValue(user_swing_color)
    AddCurrentValue(user_adaptive_color)

    local curr_vals_str = table.concat(curr_vals, ',')

    local ret, inputs = reaper.GetUserInputs(title, 5, captions, curr_vals_str)
    if not ret or inputs == curr_vals_str then return end

    local colors = {}
    local has_invalid_color = false

    local function ValidateColor(color)
        local is_valid = #color <= 8 and tonumber(color, 16)
        if not is_valid then has_invalid_color = true end
        return is_valid and color or nil
    end

    local i = 1
    for input in (inputs .. ','):gmatch('[^,]*') do
        input = input:gsub('^#', '')
        if input == '' then input = nil else input = ValidateColor(input) end
        colors[i] = input
        i = i + 1
    end

    user_bg_color = colors[1]
    user_text_color = colors[2]
    user_border_color = colors[3]
    user_swing_color = colors[4]
    user_adaptive_color = colors[5]

    SaveThemeSettings(prev_color_theme)
    is_redraw = true

    if has_invalid_color then
        local msg = 'Please specify colors in hexadecimal format! (#RRGGBB)'
        reaper.MB(msg, 'Invalid input', 0)
    end
end

function DrawLICERect(color, x, y, w, h, fill, r, a)
    fill = fill or 0
    r = r or 0
    a = a or 1

    if not fill or fill == 0 then
        for _ = 1, math.max(1, math.max(1, scale)) do
            reaper.JS_LICE_RoundRect(bitmap, x, y, w - 1, h - 1, r, color, a, 0, true)
            x, y, w, h = x + 1, y + 1, w - 2, h - 2
        end
        return
    end

    if not r or r == 0 then
        -- Body
        reaper.JS_LICE_FillRect(bitmap, x, y, w, h, color, a, 0)
        return
    end

    if h <= 2 * r then r = math.floor(h / 2 - 1) end
    if w <= 2 * r then r = math.floor(w / 2 - 1) end

    -- Top left corner
    reaper.JS_LICE_FillCircle(bitmap, x + r, y + r, r, color, a, 0, 1)
    -- Top right corner
    reaper.JS_LICE_FillCircle(bitmap, x + w - r - 1, y + r, r, color, a, 0, 1)
    -- Bottom right corner
    reaper.JS_LICE_FillCircle(bitmap, x + w - r - 1, y + h - r - 1, r, color, a, 0, 1)
    -- Bottom left corner
    reaper.JS_LICE_FillCircle(bitmap, x + r, y + h - r - 1, r, color, a, 0, 1)
    -- Ends
    reaper.JS_LICE_FillRect(bitmap, x, y + r, r, h - r * 2, color, a, 0)
    reaper.JS_LICE_FillRect(bitmap, x + w - r, y + r, r, h - r * 2, color, a, 0)
    -- Body and sides
    reaper.JS_LICE_FillRect(bitmap, x + r, y, w - r * 2, h, color, a, 0)
end

function DrawLiceBitmap()
    -- Determine colors
    local alpha = 0xFF000000
    local bg_color = tonumber(user_bg_color or '242424', 16) | alpha
    local text_color = tonumber(user_text_color or 'a9a9a9', 16) | alpha

    local border_color
    if user_border_color then
        border_color = tonumber(user_border_color, 16) | alpha
    end

    local swing_color
    if user_swing_color then
        swing_color = tonumber(user_swing_color, 16) | alpha
    else
        swing_color = reaper.GetThemeColor('toolbararmed_color', 0) | alpha
    end

    local adaptive_color
    if user_adaptive_color then
        adaptive_color = tonumber(user_adaptive_color, 16) | alpha
    else
        adaptive_color = reaper.GetThemeColor('toolbararmed_color', 0) | alpha
    end

    -- Note: Clear to transparent avoids artifacts on aliased rect corners
    if is_windows then
        reaper.JS_LICE_Clear(bitmap, 0x00000000)
    else
        reaper.JS_LICE_Clear(bitmap, bg_color & 0x00FFFFFF)
    end

    local corner_radius = user_corner_radius or math.floor(6 * scale)
    -- Draw background
    DrawLICERect(bg_color, 0, 0, bm_w, bm_h, true, corner_radius)

    -- Draw border
    if border_color then
        DrawLICERect(border_color, 0, 0, bm_w, bm_h, false, corner_radius)
    end

    -- Draw swing slider
    if prev_swing_amt ~= 0 then
        local m = math.floor(4 * scale)
        local h = math.floor(3 * scale)
        local y_offs = border_color and math.floor(scale + 0.5) or 0
        local value = prev_swing_amt

        local swing_len = math.ceil(math.abs(value) * (bm_w - 2 * m) / 2)

        local x_offs = value > 0 and bm_w // 2 or math.ceil(bm_w / 2) - swing_len
        DrawLICERect(swing_color, x_offs, bm_h - h - y_offs, swing_len, h, true)
    end

    -- Measure Text
    local icon_w = 0
    if is_adaptive then icon_w = gfx.measurestr('A') * 4 // 3 end

    local text_w, text_h = gfx.measurestr(grid_text)
    local text_x = (bm_w - text_w + icon_w) // 2
    local text_y = (bm_h - text_h) // 2
    if is_macos then text_y = text_y + 1 end

    local m = 2 * math.ceil(scale)
    if text_x - icon_w < m then
        text_x = icon_w + m
    end

    -- Draw Text
    reaper.JS_LICE_SetFontColor(lice_font, text_color)
    local len = tostring(grid_text):len()
    reaper.JS_LICE_DrawText(bitmap, lice_font, grid_text, len, text_x, text_y, bm_w,
        bm_h)

    -- Draw adaptive icon (A)
    if icon_w > 0 then
        local x = text_x - icon_w
        reaper.JS_LICE_SetFontColor(lice_font, adaptive_color)
        reaper.JS_LICE_DrawText(bitmap, lice_font, 'A', 1, text_x - icon_w,
            text_y, bm_w, bm_h)
    end

    -- Refresh window
    reaper.JS_Window_InvalidateRect(transport_hwnd, bm_x, bm_y, bm_x + bm_w,
        bm_y + bm_h, false)
end

function DecimalToFraction(x, error)
    error = error or 0.0000000001
    local n = math.floor(x)
    x = x - n
    if x < error then
        return n, 1
    elseif 1 - error < x then
        return n + 1, 1
    end

    local lower_n = 0
    local lower_d = 1

    local upper_n = 1
    local upper_d = 1

    while true do
        local middle_n = lower_n + upper_n
        local middle_d = lower_d + upper_d
        if middle_d * (x + error) < middle_n then
            upper_n = middle_n
            upper_d = middle_d
        elseif middle_n < (x - error) * middle_d then
            lower_n = middle_n
            lower_d = middle_d
        else
            return n * middle_d + middle_n, middle_d
        end
    end
end

local normal_cursor = reaper.JS_Mouse_LoadCursor(is_windows and 32512 or 0)
local diag1_resize_cursor = reaper.JS_Mouse_LoadCursor(is_linux and 32642 or 32643)
local diag2_resize_cursor = reaper.JS_Mouse_LoadCursor(is_linux and 32643 or 32642)
local horz_resize_cursor = reaper.JS_Mouse_LoadCursor(32644)
local vert_resize_cursor = reaper.JS_Mouse_LoadCursor(32645)
local move_cursor = reaper.JS_Mouse_LoadCursor(32646)

local is_edit_mode = ExtLoad('is_edit_mode', true)

local Intercept = reaper.JS_WindowMessage_Intercept
local Release = reaper.JS_WindowMessage_Release
local Peek = reaper.JS_WindowMessage_Peek

local prev_cursor = normal_cursor
local is_intercept = false

local intercepts = {
    {timestamp = 0, passthrough = false, message = 'WM_SETCURSOR'},
    {timestamp = 0, passthrough = false, message = 'WM_LBUTTONDOWN'},
    {timestamp = 0, passthrough = false, message = 'WM_LBUTTONUP'},
    {timestamp = 0, passthrough = false, message = 'WM_RBUTTONDOWN'},
    {timestamp = 0, passthrough = false, message = 'WM_RBUTTONUP'},
    {timestamp = 0, passthrough = false, message = 'WM_MOUSEWHEEL'},
}

function SetCursor(cursor)
    reaper.JS_Mouse_SetCursor(cursor)
    prev_cursor = cursor
end

function StartIntercepts()
    if is_intercept then return end
    is_intercept = true
    for _, intercept in ipairs(intercepts) do
        Intercept(transport_hwnd, intercept.message, intercept.passthrough)
    end
end

function EndIntercepts()
    if not is_intercept then return end
    is_intercept = false
    for _, intercept in ipairs(intercepts) do
        Release(transport_hwnd, intercept.message)
        intercept.timestamp = 0
    end

    if prev_cursor ~= normal_cursor then
        reaper.JS_Mouse_SetCursor(normal_cursor)
    end
    prev_cursor = -1
end

function LoadMenuScript()
    local menu_env = {}
    for key, val in pairs(_G) do menu_env[key] = val end
    menu_env._G = {menu = true}
    local menu_chunk, err = loadfile(menu_script, 'bt', menu_env)
    if menu_chunk then
        menu_chunk()
        if type(menu_env._G.menu) ~= 'table' then
            local err_msg = 'Please update Adaptive Grid to latest version'
            reaper.MB(err_msg:format(menu_script, err), 'Error', 0)
            return
        end
        return menu_env
    end
    local err_msg = 'Could not load script: %s:\n%s'
    reaper.MB(err_msg:format(menu_script, err), 'Error', 0)
end

function PeekIntercepts(m_x, m_y)
    for _, intercept in ipairs(intercepts) do
        local msg = intercept.message
        local ret, _, time, _, wph = Peek(transport_hwnd, msg)

        if ret and time ~= intercept.timestamp then
            intercept.timestamp = time

            if msg == 'WM_LBUTTONDOWN' then
                -- Avoid new clicks after showing menu
                if menu_time and reaper.time_precise() < menu_time + 0.05 then
                    return
                end
                is_left_click = true
                if is_edit_mode then
                    drag_x = m_x
                    drag_y = m_y
                end
            end

            if msg == 'WM_LBUTTONUP' then
                if not is_left_click then return end
                if reaper.JS_Mouse_GetState(16) == 16 then
                    local menu_env = LoadMenuScript()
                    if menu_env then menu_env.SetStraightGrid() end
                    local _, _, swing, swing_amt = reaper.GetSetProjectGrid(0, false)
                    local new_swing = swing ~= 1 and 1 or 0
                    reaper.GetSetProjectGrid(0, true, nil, new_swing, swing_amt)
                    return
                end
                if resize_flags == 0 or math.min(bm_w, bm_h) < min_area_size * 1.5 then
                    local menu_env = LoadMenuScript()
                    if menu_env then
                        ShowMenu(menu_env._G.menu)
                        local main_mult = menu_env.GetGridMultiplier()
                        local midi_mult = menu_env.GetMIDIGridMultiplier()
                        menu_env.UpdateToolbarToggleStates(0, main_mult)
                        menu_env.UpdateToolbarToggleStates(32060, midi_mult)
                        -- Avoid hover setting adaptive name before switching grid
                        reaper.defer(Main)
                    end
                end
            end

            if msg == 'WM_RBUTTONDOWN' then
                -- Avoid new clicks after showing menu
                if menu_time and reaper.time_precise() < menu_time + 0.05 then
                    return
                end
                is_right_click = true
            end

            if msg == 'WM_RBUTTONUP' then
                if not is_right_click then return end
                ShowRightClickMenu()
            end

            if msg == 'WM_MOUSEWHEEL' then
                local mouse_state = reaper.JS_Mouse_GetState(20)
                if mouse_state & 16 == 16 then
                    wph = wph / math.abs(wph)
                    local _, _, swing, swing_amt = reaper.GetSetProjectGrid(0, false)
                    if swing == 0 then
                        local menu_env = LoadMenuScript()
                        if menu_env then menu_env.SetStraightGrid() end
                    end
                    -- Scroll slower when Ctrl is pressed
                    local amt = wph * (mouse_state == 20 and 0.01 or 0.03)
                    reaper.GetSetProjectGrid(0, true, nil, 1, swing_amt + amt)
                else
                    local adjust_chunk, err = loadfile(adjust_script)
                    if adjust_chunk then
                        _G.scroll_dir = wph
                        adjust_chunk()
                    else
                        local err_msg = 'Could not load script: %s:\n%s'
                        reaper.MB(err_msg:format(adjust_script, err), 'Error', 0)
                    end
                end
            end
        end
    end
end

function ShowRightClickMenu()
    local menu = {
        {
            title = 'Customize',
            {title = 'Size', OnReturn = SetCustomSize},
            {title = 'Font', OnReturn = SetCustomFont},
            {title = 'Corners', OnReturn = SetCustomCornerRadius},
            {separator = true},
            {title = 'Colors', OnReturn = SetCustomColors},
            {
                title = 'Choose color...',

                {
                    title = 'Background',
                    OnReturn = function()
                        user_bg_color = GetUserColor()
                        SaveThemeSettings(prev_color_theme)
                        is_redraw = true
                    end
                },
                {
                    title = 'Text',
                    OnReturn = function()
                        user_text_color = GetUserColor()
                        SaveThemeSettings(prev_color_theme)
                        is_redraw = true
                    end
                },
                {
                    title = 'Border',
                    OnReturn = function()
                        user_border_color = GetUserColor()
                        SaveThemeSettings(prev_color_theme)
                        is_redraw = true
                    end
                },
                {
                    title = 'Swing',
                    OnReturn = function()
                        user_swing_color = GetUserColor()
                        SaveThemeSettings(prev_color_theme)
                        is_redraw = true
                    end
                },
                {
                    title = 'Adaptive',
                    OnReturn = function()
                        user_adaptive_color = GetUserColor()
                        SaveThemeSettings(prev_color_theme)
                        is_redraw = true
                    end
                },

            },
            {separator = true},
            {
                title = 'Attach to',

                {
                    title = 'Left status edge',
                    is_checked = attach_mode == 3,
                    OnReturn = function()
                        attach_mode = 3
                        UpdateAttachPosition()
                        SaveThemeSettings(prev_color_theme)
                    end
                },
                {
                    title = 'Right status edge',
                    is_checked = attach_mode == 4,
                    OnReturn = function()
                        attach_mode = 4
                        UpdateAttachPosition()
                        SaveThemeSettings(prev_color_theme)
                    end
                },
                {
                    title = 'Left transport edge',
                    is_checked = attach_mode == 1,
                    OnReturn = function()
                        attach_mode = 1
                        UpdateAttachPosition()
                        SaveThemeSettings(prev_color_theme)
                    end
                },
                {
                    title = 'Right transport edge',
                    is_checked = attach_mode == 2,
                    OnReturn = function()
                        attach_mode = 2
                        UpdateAttachPosition()
                        SaveThemeSettings(prev_color_theme)
                    end
                },
            },
            {separator = true},
            {
                title = 'Reset',
                OnReturn = function()
                    local msg = 'This will clear all customizations you made \z
                    for the active theme.\n\nProceed?'
                    local ret = reaper.MB(msg, 'Warning', 4)
                    if ret ~= 6 then return end
                    -- If theme inside resource folder, save as relative path
                    local theme_path = prev_color_theme
                    theme_path = GetRelativeThemePath(theme_path) or theme_path
                    if theme_path == '' then theme_path = 'default' end
                    ExtSave(theme_path, nil)
                    prev_color_theme = nil
                end
            }
        },
        {
            title = 'Lock position',
            is_checked = not is_edit_mode,
            OnReturn = function()
                is_edit_mode = not is_edit_mode
                ExtSave('is_edit_mode', is_edit_mode)
            end
        },
        {
            title = 'Run script on startup',
            IsChecked = IsStartupHookEnabled,
            OnReturn = function()
                local is_enabled = IsStartupHookEnabled()
                local comment = 'Start script: Gridbox'
                local var_name = 'grid_box_cmd_name'
                SetStartupHookEnabled(not is_enabled, comment, var_name)
            end,
        },
    }
    ShowMenu(menu)
end

function ShowMenu(menu)
    SetCursor(normal_cursor)

    local focus_hwnd = reaper.JS_Window_GetFocus()
    -- Open gfx window
    gfx.clear = reaper.GetThemeColor('col_main_bg2', 0)
    local ClientToScreen = reaper.JS_Window_ClientToScreen
    local transport_x, transport_y = ClientToScreen(transport_hwnd, 0, 0)
    transport_x, transport_y = transport_x + 4, transport_y + 4
    gfx.init('FTC.GB', math.floor(24 * scale), 0, 0, transport_x, transport_y)

    -- Open menu at bottom left corner
    local menu_x, menu_y = ClientToScreen(transport_hwnd, bm_x, bm_y + bm_h)
    gfx.x, gfx.y = gfx.screentoclient(menu_x, menu_y)

    -- Hide gfx window
    local gfx_hwnd = reaper.JS_Window_Find('FTC.GB', true)
    reaper.JS_Window_SetOpacity(gfx_hwnd, 'ALPHA', 0)

    if is_linux then
        reaper.JS_Window_SetStyle(gfx_hwnd, 'POPUP')
    else
        reaper.JS_Window_Show(gfx_hwnd, 'HIDE')
        if focus_hwnd then reaper.JS_Window_SetFocus(focus_hwnd) end
    end

    -- Show menu
    local menu_str = CreateMenuRecursive(menu)
    local ret = gfx.showmenu(menu_str)
    gfx.quit()

    if focus_hwnd then reaper.JS_Window_SetFocus(focus_hwnd) end
    if ret > 0 then ReturnMenuRecursive(menu, ret) end

    -- Make sure that user can click gridbox to close menu
    menu_time = reaper.time_precise()
    is_left_click = false
    is_right_click = false
    drag_x = nil
end

function GetStatusWindowClientRect()
    -- Get status window coordinates
    local status_hwnd = reaper.JS_Window_FindChildByID(transport_hwnd, 1010)
    local _, st_l, st_t, st_r, st_b = reaper.JS_Window_GetRect(status_hwnd)
    st_l, st_t = reaper.JS_Window_ScreenToClient(transport_hwnd, st_l, st_t)
    st_r, st_b = reaper.JS_Window_ScreenToClient(transport_hwnd, st_r, st_b)

    -- Note: Window can be out of transport bounds
    st_l = math.max(st_l, 0)
    st_t = math.max(st_t, 0)
    st_r = math.min(st_r, transport_w)
    st_b = math.min(st_b, transport_h)

    return st_l, st_t, st_r, st_b
end

function SetBitmapCoords(x, y, w, h)
    local has_pos_changed = x and x ~= bm_x or y and y ~= bm_y
    local has_size_changed = w and w ~= bm_w or h and h ~= bm_h
    if not has_pos_changed and not has_size_changed then return end

    if has_pos_changed then is_redraw = true end
    if has_size_changed then is_resize = true end

    if bm_x then
        -- Redraw previous area
        reaper.JS_Window_InvalidateRect(transport_hwnd, bm_x, bm_y,
            bm_x + bm_w, bm_y + bm_h, false)
    end

    bm_x, bm_y, bm_w, bm_h = x or bm_x, y or bm_y, w or bm_w, h or bm_h

    -- Redraw new area
    reaper.JS_Window_InvalidateRect(transport_hwnd, bm_x, bm_y,
        bm_x + bm_w, bm_y + bm_h, false)

    if not is_resize then
        -- Change bitmap draw coordinates
        reaper.JS_Composite_Delay(transport_hwnd, 0.03, 0.03, 2)
        reaper.JS_Composite(transport_hwnd, bm_x, bm_y, bm_w, bm_h, bitmap, 0, 0,
            bm_w, bm_h)
    end
end

function UpdateAttachPosition()
    if attach_mode == 1 then
        attach_x = bm_x
    end
    if attach_mode == 2 then
        attach_x = bm_x - transport_w
    end
    if attach_mode == 3 then
        local st_l = GetStatusWindowClientRect()
        attach_x = bm_x - st_l
    end
    if attach_mode == 4 then
        local _, _, st_r = GetStatusWindowClientRect()
        attach_x = bm_x - st_r
    end
end

function GetAttachPosition()
    if not attach_x then return end
    local new_bm_x
    if attach_mode == 1 then
        new_bm_x = attach_x
    end
    if attach_mode == 2 then
        new_bm_x = attach_x + transport_w
    end
    if attach_mode == 3 or attach_mode == 4 then
        local st_l = GetStatusWindowClientRect()
        new_bm_x = attach_x + st_l
    end
    if attach_mode == 4 then
        local _, _, st_r = GetStatusWindowClientRect()
        new_bm_x = attach_x + st_r
    end
    return new_bm_x
end

function EnsureBitmapVisible()
    -- Ensure position/size is within bounds
    local w = math.max(min_area_size, math.min(bm_w, transport_w))
    local h = math.max(min_area_size, math.min(bm_h, transport_h))

    local x = math.max(0, math.min(transport_w - w, bm_x))
    local y = math.max(0, math.min(transport_h - h, bm_y))

    -- Get status window coordinates
    local st_l, st_t, st_r, st_b = GetStatusWindowClientRect()

    local st_x = st_l
    local st_y = st_t
    local st_w = st_r - st_l
    local st_h = math.abs(st_b - st_t)

    -- Check if bitmap overlaps or contains status window
    local is_left = x + w < st_x
    local is_right = x > st_x + st_w
    local is_above = y + h < st_y
    local is_below = y > st_y + st_h

    local is_overlap = not (is_left or is_right or is_above or is_below)
    local is_contained = x > st_l and x < st_r and y > st_t and y < st_b

    if is_overlap or is_contained then
        -- Move bitmap to not overlap with status window
        local space_l = st_l
        local space_r = transport_w - st_r
        local space_t = st_t
        local space_b = transport_h - st_b

        local new_l_x = st_l - w
        local new_r_x = st_r
        local new_t_y = st_t - h
        local new_b_y = st_b

        local move_x = 0
        local move_y = 0

        if space_l >= w or space_r >= w then
            if space_l >= w and space_r >= w then
                -- Space on both sides, move to closest position
                move_x = x - new_l_x < new_r_x - x and -1 or 1
            else
                -- Space only on one side, move accordingly
                move_x = space_r > space_l and 1 or -1
            end
        elseif space_t >= h or space_b >= h then
            if space_t >= h and space_b >= h then
                -- Space on both sides, move to closest position
                move_y = y - new_t_y < new_b_y - y and -1 or 1
            else
                -- Space only on one side, move accordingly
                move_y = space_b > space_t and 1 or -1
            end
        else
            -- Check if more vertical or horizontal space, move accordingly
            if math.max(space_l, space_r) > math.max(space_t, space_b) then
                move_x = space_r > space_l and 1 or -1
            else
                move_y = space_b > space_t and 1 or -1
            end
        end

        if move_x == -1 then
            -- Move left
            x = new_l_x
            w = math.min(w, space_l)
        end
        if move_x == 1 then
            -- Move right
            x = new_r_x
            w = math.min(w, space_r)
        end
        if move_y == -1 then
            -- Move top
            y = new_t_y
            h = math.min(h, space_t)
        end
        if move_y == 1 then
            -- Move bottom
            y = new_b_y
            h = math.min(h, space_b)
        end

        -- Ensure position/size is within bounds after move
        w = math.max(min_area_size, math.min(w, transport_w))
        h = math.max(min_area_size, math.min(h, transport_h))

        x = math.max(0, math.min(transport_w - w, x))
        y = math.max(0, math.min(transport_h - h, y))
    end

    SetBitmapCoords(x, y, w, h)
end

function FindInitialPosition()
    -- Get status window coordinates
    local st_l, st_t, st_r, st_b = GetStatusWindowClientRect()
    local st_x = st_l
    local st_y = st_t
    local st_w = st_r - st_l
    local st_h = math.abs(st_b - st_t)

    -- Set initial position that matches status window
    bm_x = 0
    bm_y = st_y
    bm_w = st_h * 5 // 2
    bm_h = st_h

    -- Add small vertical margin if status window takes up full transport height
    if st_h >= transport_h - 4 then
        bm_y = bm_y + 2
        bm_h = bm_h - 4
    end

    -- Now we'll use GetThingFromPoint to get empty tranposrt areas on x axis
    local st_mid_y = st_y + bm_h // 2
    local empty_areas = {}

    local size = 0
    local sel_cnt = 0
    local bpm_x

    local function AddEmptyArea(x, y, align)
        local _, thing = reaper.GetThingFromPoint(x, y)

        if thing == 'trans' then
            -- Empty transport area, increase size
            size = size + 1
        else
            -- Remember x position of BPM button
            if not bpm_x and thing:sub(1, 9) == 'trans.bpm' then
                bpm_x = x
            end
            if size > 0 then
                -- Add previous area
                if sel_cnt == 0 and size > min_area_size then
                    local area = {size = size, r = x, align = align}
                    empty_areas[#empty_areas + 1] = area
                end
                size = 0
                sel_cnt = 0
            end

            -- Skip areas to the right of selection (selection textboxes)
            if thing == 'trans.sel' then sel_cnt = sel_cnt + 1 end
        end
    end

    local x_start, y = reaper.JS_Window_ClientToScreen(transport_hwnd, 0, st_mid_y)
    local x_end = reaper.JS_Window_ClientToScreen(transport_hwnd, st_l, st_mid_y)

    for x = x_start, x_end do
        AddEmptyArea(x, y, 1)
    end
    AddEmptyArea(x_end, -1, 1)

    x_start = reaper.JS_Window_ClientToScreen(transport_hwnd, st_r, st_mid_y)
    x_end = reaper.JS_Window_ClientToScreen(transport_hwnd, transport_w, st_mid_y)

    for x = x_start, x_end do
        AddEmptyArea(x, y, -1)
    end
    AddEmptyArea(x_end, -1, 1)

    local target_area

    if bpm_x then
        local min_bpm_distance
        for _, area in ipairs(empty_areas) do
            -- Check if area is large enough
            if area.size > bm_w * 0.7 then
                local area_x = area.r > bpm_x and area.r or area.r - area.size
                local diff = bpm_x - area_x
                local distance = math.abs(diff)
                -- Check distance to bpm window
                if not min_bpm_distance or distance < min_bpm_distance then
                    min_bpm_distance = distance
                    target_area = area
                    target_area.align = area.r > bpm_x and -1 or 1
                end
            end
        end
    end

    if not target_area then
        -- Find largest empty area
        local largest_area_size = 0
        for _, area in ipairs(empty_areas) do
            if area.size > largest_area_size then
                target_area = area
                largest_area_size = area.size
            end
        end
    end

    if target_area then
        -- Make bitmap a bit larger if it'll then fully fit empty space
        if target_area.size < bm_w * 1.5 then bm_w = target_area.size end

        -- Add margin
        local m = bm_h // 6
        bm_w = math.max(min_area_size, math.min(target_area.size - 2 * m, bm_w))

        -- Convert back to client coordinates
        local r = target_area.r
        r = reaper.JS_Window_ScreenToClient(transport_hwnd, r, st_mid_y)

        -- Place bitmap (x pos) in empty target area (based on alignment)
        if target_area.align > 0 then
            bm_x = math.max(0, r - bm_w - m)
        else
            bm_x = math.max(0, r - target_area.size + m)
        end
    end

    attach_mode = bm_x < st_r and 3 or 4
    UpdateAttachPosition()
end

function Main()
    -- Find transport window
    if not transport_hwnd or not reaper.ValidatePtr(transport_hwnd, 'HWND*') then
        local time = reaper.time_precise()
        if not prev_time or time > prev_time + 0.5 then
            local transport_title = reaper.JS_Localize('Transport', 'common')
            transport_hwnd = reaper.JS_Window_Find(transport_title, true)
        end
    end

    -- Go idle if transport window is not found/visible
    if not transport_hwnd or not reaper.JS_Window_IsVisible(transport_hwnd) then
        reaper.defer(Main)
        return
    end

    local x, y = reaper.GetMousePosition()
    local hover_hwnd = reaper.JS_Window_FromPoint(x, y)

    do
        local _, w, h = reaper.JS_Window_GetClientSize(transport_hwnd)
        transport_w, transport_h = w, h
    end

    -- Monitor color theme changes
    local color_theme = reaper.GetLastColorThemeFile()
    if color_theme ~= prev_color_theme then
        prev_color_theme = color_theme
        if not LoadThemeSettings(color_theme) then
            FindInitialPosition()
        end
        EnsureBitmapVisible()
        is_resize = true
    end

    local is_hovered = false
    if hover_hwnd == transport_hwnd or drag_x then
        local m_x, m_y = reaper.JS_Window_ScreenToClient(transport_hwnd, x, y)
        -- Handle drag move/resize
        if drag_x and (drag_x ~= m_x or drag_y ~= m_y) then
            if resize_flags > 0 then
                if resize_flags & 1 == 1 then
                    local bm_r = bm_x + bm_w
                    local new_bm_w = math.max(min_area_size, bm_r - m_x)
                    local new_bm_x = bm_r - new_bm_w
                    SetBitmapCoords(new_bm_x, nil, new_bm_w, nil)
                end
                if resize_flags & 2 == 2 then
                    local bm_b = bm_y + bm_h
                    local new_bm_h = math.max(min_area_size, bm_b - m_y)
                    local new_bm_y = bm_b - new_bm_h
                    SetBitmapCoords(nil, new_bm_y, nil, new_bm_h)
                end
                if resize_flags & 4 == 4 then
                    local new_bm_w = math.max(min_area_size, m_x - bm_x)
                    SetBitmapCoords(nil, nil, new_bm_w, nil)
                end
                if resize_flags & 8 == 8 then
                    local new_bm_h = math.max(min_area_size, m_y - bm_y)
                    SetBitmapCoords(nil, nil, nil, new_bm_h)
                end
                is_resize = true
            else
                -- Move window
                local new_bm_x = bm_x + m_x - drag_x
                local new_bm_y = bm_y + m_y - drag_y
                SetBitmapCoords(new_bm_x, new_bm_y)
                if m_x > 0 and m_y > 0 and m_x < transport_w and m_y < transport_h then
                    SetCursor(move_cursor)
                end
            end
            drag_x = m_x
            drag_y = m_y
            is_left_click = false
        end

        local m = math.floor(scale * 4)
        is_hovered = m_x > bm_x - m and m_y > bm_y - m and
            m_x < bm_x + bm_w + m and m_y < bm_y + bm_h + m

        if is_hovered then
            if is_edit_mode and not drag_x then
                local new_resize = 0
                local cursor = normal_cursor

                local diff_l = math.abs(bm_x - m_x)
                local diff_t = math.abs(bm_y - m_y)
                local diff_r = math.abs(bm_x + bm_w - m_x)
                local diff_b = math.abs(bm_y + bm_h - m_y)

                if diff_l < m then
                    new_resize = 1
                    cursor = horz_resize_cursor
                end

                if diff_t < m then
                    new_resize = 2
                    cursor = vert_resize_cursor
                end

                if diff_r < m then
                    new_resize = 4
                    cursor = horz_resize_cursor
                end

                if diff_b < m then
                    new_resize = 8
                    cursor = vert_resize_cursor
                end

                local d_m = 2 * m

                if diff_l < d_m and diff_t < d_m then
                    new_resize = 3
                    cursor = diag2_resize_cursor
                end

                if diff_t < d_m and diff_r < d_m then
                    new_resize = 6
                    cursor = diag1_resize_cursor
                end

                if diff_r < d_m and diff_b < d_m then
                    new_resize = 12
                    cursor = diag2_resize_cursor
                end

                if diff_b < d_m and diff_l < d_m then
                    new_resize = 9
                    cursor = diag1_resize_cursor
                end

                SetCursor(cursor)

                if resize_flags ~= new_resize then
                    resize_flags = new_resize
                    is_redraw = true
                end
            end
            StartIntercepts()
            PeekIntercepts(m_x, m_y)
        else
            EndIntercepts()
            is_left_click = false
            is_right_click = false
            if resize_flags > 0 and not drag_x then
                is_redraw = true
                resize_flags = 0
            end
        end

        -- Release drags / left clicks / right clicks
        if drag_x and reaper.JS_Mouse_GetState(3) == 0 then
            EnsureBitmapVisible()
            UpdateAttachPosition()
            SaveThemeSettings(color_theme)
            drag_x = nil
            drag_y = nil
            is_redraw = true
        end
    end

    -- Detect changes to transport window size
    if transport_w ~= prev_transport_w or transport_h ~= prev_transport_h then
        if prev_transport_w then
            -- Move bitmap based on attached position
            local a_x = GetAttachPosition()
            if a_x then SetBitmapCoords(a_x) end
            EnsureBitmapVisible()
        end
        prev_transport_w = transport_w
        prev_transport_h = transport_h
    end

    -- Monitor adaptive grid setting
    local main_mult = reaper.GetExtState('FTC.AdaptiveGrid', 'main_mult')
    if main_mult ~= prev_main_mult then
        prev_main_mult = main_mult
        is_adaptive = (tonumber(main_mult) or 0) ~= 0
        is_redraw = true
    end

    -- Monitor grid division
    local _, grid_div, swing, swing_amt = reaper.GetSetProjectGrid(0, false)

    if is_hovered and reaper.JS_Mouse_GetState(16) == 16 then
        -- Display swing state when hovered and alt is pressed
        local text = 'Swing: '
        if swing == 1 then
            text = text .. math.floor(swing_amt * 100) .. '%'
        else
            text = text .. 'off'
        end
        if text ~= grid_text then
            grid_text = text
            is_adaptive = false
            prev_grid_div = nil
            is_redraw = true
        end
    elseif is_hovered and (tonumber(main_mult) or 0) ~= 0 then
        -- Display adaptive mode name when hovered and adaptive grid is on
        local text = adaptive_names[tonumber(main_mult)]
        if text ~= grid_text then
            grid_text = text
            is_adaptive = false
            prev_grid_div = nil
            is_redraw = true
        end
    elseif reaper.GetToggleCommandState(40904) == 1 then
        -- Grid is set to Frame
        if grid_text ~= 'Frame' then
            grid_text = 'Frame'
            is_adaptive = false
            prev_grid_div = nil
            is_redraw = true
        end
    elseif swing == 3 then
        -- Grid is set to Measure
        if grid_text ~= 'Measure' then
            grid_text = 'Measure'
            is_adaptive = false
            prev_grid_div = nil
            is_redraw = true
        end
    elseif grid_div ~= prev_grid_div then
        prev_grid_div = grid_div
        -- Grid division changed

        is_adaptive = (tonumber(main_mult) or 0) ~= 0

        local num, denom = DecimalToFraction(grid_div)

        local is_triplet, is_dotted = false, false
        if grid_div > 1 then
            is_triplet = 2 * grid_div % (2 / 3) == 0
            is_dotted = 2 * grid_div % 3 == 0
        else
            is_triplet = 2 / grid_div % 3 == 0
            is_dotted = 2 / grid_div % (2 / 3) == 0
        end

        local suffix = ''
        if is_triplet then
            suffix = 'T'
            denom = denom * 2 / 3
        elseif is_dotted then
            suffix = 'D'
            denom = denom / 2
            num = num / 3
            --[[  elseif swing == 1 then
            suffix = 'S' ]]
        end

        if num >= denom and num % denom == 0 then
            grid_text = ("%.0f%s"):format(num / denom, suffix)
        else
            grid_text = ("%.0f/%.0f%s"):format(num, denom, suffix)
        end
        is_redraw = true
    end

    -- Monitor swing amount
    if swing ~= 1 then swing_amt = 0 end
    if swing_amt ~= prev_swing_amt then
        prev_swing_amt = swing_amt
        is_redraw = true
    end

    if is_resize then
        -- Prepare LICE bitmap for drawing
        if bitmap then reaper.JS_LICE_DestroyBitmap(bitmap) end
        bitmap = reaper.JS_LICE_CreateBitmap(true, bm_w, bm_h)

        -- Determine font size
        font_size = user_font_size
        local font_family = user_font_family or 'Arial'
        if not font_size then
            font_size = 1
            -- Find optimal font size by incrementing until it doesn't target height
            local target_h = math.max(math.min(14 * scale, bm_h), bm_h // 2.5)
            local curr_h
            repeat
                gfx.setfont(1, font_family, font_size)
                curr_h = select(2, gfx.measurechar(70))
                font_size = font_size + math.floor(target_h / curr_h + 0.5)
            until curr_h >= target_h
        else
            gfx.setfont(1, font_family, font_size)
        end

        -- Create LICE font
        if lice_font then reaper.JS_LICE_DestroyFont(lice_font) end
        lice_font = reaper.JS_LICE_CreateFont()

        local gdi = reaper.JS_GDI_CreateFont(font_size, 0, 0, 0, 0, 0, font_family)
        reaper.JS_LICE_SetFontFromGDI(lice_font, gdi, '')
        reaper.JS_GDI_DeleteObject(gdi)

        -- Set bitmap draw coordinates
        reaper.JS_Composite_Delay(transport_hwnd, 0.03, 0.03, 2)
        reaper.JS_Composite(transport_hwnd, bm_x, bm_y, bm_w, bm_h, bitmap, 0, 0,
            bm_w, bm_h)
        is_resize = false
        is_redraw = true
    end

    if is_redraw then
        DrawLiceBitmap()
        is_redraw = false
    end

    reaper.defer(Main)
end

reaper.SetToggleCommandState(sec, cmd, 1)
reaper.RefreshToolbar2(sec, cmd)

function Exit()
    reaper.SetToggleCommandState(sec, cmd, 0)
    reaper.RefreshToolbar2(sec, cmd)

    if bitmap then reaper.JS_LICE_DestroyBitmap(bitmap) end
    if lice_font then reaper.JS_LICE_DestroyFont(lice_font) end
    if transport_hwnd then
        reaper.JS_Composite_Delay(transport_hwnd, 0, 0, 0)
        if bm_x then
            reaper.JS_Window_InvalidateRect(transport_hwnd, bm_x, bm_y,
                bm_x + bm_w, bm_y + bm_h, false)
        end
    end

    EndIntercepts()
end

reaper.atexit(Exit)
reaper.defer(Main)
