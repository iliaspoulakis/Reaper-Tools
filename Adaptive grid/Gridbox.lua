--[[
  @author Ilias-Timon Poulakis (FeedTheCat)
  @license MIT
  @version 2.1.2
  @about Adds a little box to transport that displays project grid information
  @changelog
    - Fix MIDI editor options not applying new grid size immediately
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
local user_font_yoffs
local user_font_family

local user_snap_size
local user_snap_on_color
local user_snap_off_color
local user_snap_sep_color

local window_hwnd
local window_w
local window_h

local prev_time
local prev_window_w
local prev_window_h
local prev_color_theme
local prev_main_mult
local prev_swing_amt
local prev_grid_div
local prev_top_window_cnt
local top_window_array = reaper.new_array(4096)

local prev_hzoom_lvl
local prev_vis_grid_div

local grid_text
local is_adaptive

local drag_x
local drag_y
local swing_drag_x
local is_swing_drag

local is_left_click = false
local is_right_click = false

local left_w = 0
local prev_is_snap
local prev_is_rel_snap
local prev_is_snap_hovered

local menu_time
local menu_env

local bitmap
local lice_font
local font_size

local snap_bitmap
local bg_bitmap

local prev_bg_color
local prev_bg_corner_r
local prev_snap_color

local is_redraw = false
local is_resize = false
local resize_flags = 0

local prev_attach_hwnd
local prev_bm_w
local prev_bm_h
local prev_bm_x
local prev_bm_y

local GetSetGrid = reaper.GetSetProjectGrid

local has_reapack = reaper.ReaPack_BrowsePackages ~= nil
local missing_dependencies = {}

function print(...)
    local values = {...}
    for i = 1, #values do values[i] = tostring(values[i]) end
    if #values == 0 then values[1] = 'nil' end
    reaper.ShowConsoleMsg(table.concat(values, ' ') .. '\n')
end

-- Check if js_ReaScriptAPI extension is installed
if not reaper.JS_Composite_Delay then
    if has_reapack then
        table.insert(missing_dependencies, 'js_ReaScriptAPI')
    else
        reaper.MB('Please install js_ReaScriptAPI extension', 'GridBox', 0)
        return
    end
end

-- Load scripts from Adaptive Grid
local _, file, sec, cmd = reaper.get_action_context()
local file_dir = file:match('^(.+)[\\/]')

function ConcatPath(...) return table.concat({...}, package.config:sub(1, 1)) end

local menu_script = ConcatPath(file_dir, 'Adaptive grid menu.lua')

if not reaper.file_exists(menu_script) then
    if has_reapack then
        table.insert(missing_dependencies, 'Adaptive Grid')
    else
        reaper.MB('Please install Adaptive Grid', 'GridBox', 0)
        return
    end
end

if #missing_dependencies > 0 then
    local msg = ('Missing dependencies:\n\n'):format(#missing_dependencies)
    for _, dependency in ipairs(missing_dependencies) do
        msg = msg .. ' • ' .. dependency .. '\n'
    end
    reaper.MB(msg, 'GridBox', 0)

    for i = 1, #missing_dependencies do
        if missing_dependencies[i]:match(' ') then
            missing_dependencies[i] = '"' .. missing_dependencies[i] .. '"'
        end
    end
    reaper.ReaPack_BrowsePackages(table.concat(missing_dependencies, ' OR '))
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

local scroll_dir = is_macos and -1 or 1
scroll_dir = tonumber(reaper.GetExtState(extname, 'scroll_dir')) or scroll_dir

local use_vis_grid = reaper.GetExtState(extname, 'use_vis_grid') == '1'
local hide_snap = reaper.GetExtState(extname, 'hide_snap') == '1'

local comp_fps = reaper.GetExtState(extname, 'comp_fps')
comp_fps = tonumber(comp_fps) or 30
local comp_delay = comp_fps == 0 and 0 or 1 / comp_fps

local attach_window_title = reaper.GetExtState(extname, 'attach_title')
if attach_window_title == '' then attach_window_title = nil end

local attach_window_wait = reaper.GetExtState(extname, 'attach_wait')
if attach_window_wait == '' then attach_window_wait = nil end

local attach_window_child_id = reaper.GetExtState(extname, 'attach_child_id')
attach_window_child_id = tonumber(attach_window_child_id)

local transport_title = reaper.JS_Localize('Transport', 'common')
local menu_cmd = reaper.AddRemoveReaScript(true, 0, menu_script, true)

local function GetTransportScale()
    if is_macos then return 1 end
    local _, new_dpi = reaper.ThemeLayout_GetLayout('trans', -3)
    return tonumber(new_dpi) / 256
end

local scale = GetTransportScale()

local function ScaleValue(value, scale_factor)
    if not tonumber(value) then return value end
    scale_factor = scale_factor or scale
    return math.floor(value * scale_factor + 0.5)
end

-- Smallest size the bitmap is allowed to have (width and height in pixels)
local min_area_size = ScaleValue(12)

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

function IsStartupHookEnabled(opt_cmd_id)
    local res_path = reaper.GetResourcePath()
    local startup_path = ConcatPath(res_path, 'Scripts', '__startup.lua')
    local cmd_id = opt_cmd_id or GetStartupHookCommandID()
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
    if rel_theme_path then
        settings = ExtLoad(rel_theme_path)
        -- Check for saved settings from other OS
        if not settings and rel_theme_path:match('[/\\]') then
            if is_windows then
                rel_theme_path = rel_theme_path:gsub('/', '\\')
            else
                rel_theme_path = rel_theme_path:gsub('\\', '/')
            end
            settings = ExtLoad(rel_theme_path)
        end
    end
    -- Note: Theme path can be empty in new REAPER installations?
    if theme_path == '' then theme_path = 'default' end
    -- Fallback to full path
    if not settings then
        settings = ExtLoad(theme_path)
    end

    -- When attached to another window, try to load position saved for
    -- previously used theme
    if not settings and attach_window_title then
        local prev_theme_path = ExtLoad('prev_theme_path')
        local prev_settings = prev_theme_path and ExtLoad(prev_theme_path)
        if prev_settings then
            settings = {}
            settings.attach_x = prev_settings.attach_x
            settings.attach_mode = prev_settings.attach_mode

            settings.bm_x = prev_settings.bm_x
            settings.bm_y = prev_settings.bm_y
            settings.bm_w = prev_settings.bm_w
            settings.bm_h = prev_settings.bm_h
            settings.scale = prev_settings.scale
        end
    end

    local has_settings = settings ~= nil
    settings = settings or {}

    user_bg_color = settings.bg_color
    user_text_color = settings.text_color
    user_border_color = settings.border_color
    user_swing_color = settings.swing_color
    user_adaptive_color = settings.adaptive_color
    user_font_size = settings.font_size
    user_font_family = settings.font_family
    user_font_yoffs = settings.font_yoffs
    user_corner_radius = settings.corner_radius
    user_snap_size = settings.snap_size
    user_snap_on_color = settings.snap_on_color
    user_snap_off_color = settings.snap_off_color
    user_snap_sep_color = settings.snap_sep_color

    attach_x = settings.attach_x
    attach_mode = settings.attach_mode

    local new_bm_x = settings.bm_x
    local new_bm_y = settings.bm_y
    local new_bm_w = settings.bm_w
    local new_bm_h = settings.bm_h

    if not is_macos and settings.scale and settings.scale ~= scale then
        local scale_factor = scale / settings.scale
        new_bm_x = ScaleValue(new_bm_x, scale_factor)
        new_bm_y = ScaleValue(new_bm_y, scale_factor)
        new_bm_w = ScaleValue(new_bm_w, scale_factor)
        new_bm_h = ScaleValue(new_bm_h, scale_factor)

        attach_x = ScaleValue(attach_x, scale_factor)
        user_snap_size = ScaleValue(user_snap_size, scale_factor)
        user_font_size = ScaleValue(user_font_size, scale_factor)
        user_font_yoffs = ScaleValue(user_font_yoffs, scale_factor)
        user_corner_radius = ScaleValue(user_corner_radius, scale_factor)
    end

    if attach_x then new_bm_x = GetAttachPosition() end
    if attach_window_title == settings.attach_title
        and attach_window_child_id == settings.attach_child_id
        or not bm_x then
        SetBitmapCoords(new_bm_x, new_bm_y, new_bm_w, new_bm_h)
    end
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
        attach_title = attach_window_title,
        attach_child_id = attach_window_child_id,
        bg_color = user_bg_color,
        text_color = user_text_color,
        border_color = user_border_color,
        swing_color = user_swing_color,
        adaptive_color = user_adaptive_color,
        font_size = user_font_size,
        font_family = user_font_family,
        font_yoffs = user_font_yoffs,
        corner_radius = user_corner_radius,
        snap_size = user_snap_size,
        snap_on_color = user_snap_on_color,
        snap_off_color = user_snap_off_color,
        snap_sep_color = user_snap_sep_color,
        scale = scale,
    }

    -- If theme inside resource folder, save as relative path
    theme_path = GetRelativeThemePath(theme_path) or theme_path
    if theme_path == '' then theme_path = 'default' end
    ExtSave(theme_path, settings)
    ExtSave('prev_theme_path', theme_path)
end

function GetThemeColor(key, flag)
    local color = reaper.GetThemeColor(key, flag or 0)
    if is_windows then
        local r, g, b = reaper.ColorFromNative(color)
        color = r * 65536 + g * 256 + b
    end
    return color
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

function TintIntColor(color, factor)
    local a = color & 0xFF000000
    local r = (color & 0xFF0000) >> 16
    local g = (color & 0x00FF00) >> 8
    local b = (color & 0x0000FF)

    r = (r * factor) // 1
    g = (g * factor) // 1
    b = (b * factor) // 1

    r = r < 0 and 0 or r > 255 and 255 or r
    g = g < 0 and 0 or g > 255 and 255 or g
    b = b < 0 and 0 or b > 255 and 255 or b

    return (r * 65536 + g * 256 + b) | a
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
    user_corner_radius = user_corner_radius and math.floor(user_corner_radius)
    is_redraw = true

    SaveThemeSettings(prev_color_theme)
end

function SetCustomFont()
    local title = 'Font'
    local captions = 'Size: (e.g.42),Family (e.g. Comic Sans),\z
        Y offset:,extrawidth=50'

    local curr_vals_str = ('%s,%s,%s'):format(
        user_font_size or '',
        user_font_family or '',
        user_font_yoffs or ''
    )

    local ret, inputs = reaper.GetUserInputs(title, 3, captions, curr_vals_str)
    if not ret or inputs == curr_vals_str then return end

    local input_vals = {}
    for input in (inputs .. ','):gmatch('[^,]*') do
        input_vals[#input_vals + 1] = input
    end

    user_font_size = tonumber(input_vals[1])
    user_font_family = input_vals[2]
    if user_font_family == '' then user_font_family = nil end
    user_font_yoffs = tonumber(input_vals[3])
    is_resize = true

    SaveThemeSettings(prev_color_theme)
end

function SetCustomSnapSize()
    local title = 'Snap'
    local captions = 'Icon size: (e.g.24),extrawidth=50'

    local curr_vals_str = ('%s'):format(
        user_snap_size or '')

    local ret, inputs = reaper.GetUserInputs(title, 1, captions, curr_vals_str)
    if not ret or inputs == curr_vals_str then return end

    local input_vals = {}
    for input in (inputs .. ','):gmatch('[^,]*') do
        input_vals[#input_vals + 1] = input
    end

    user_snap_size = tonumber(input_vals[1])
    is_resize = true

    SaveThemeSettings(prev_color_theme)

    if user_snap_size and user_snap_size // 0.4 > bm_w / 1.3 then
        local msg = 'You entered a large size. Snap icon will not be \z
        visible.\n\nReduce the size or expand Gridbox to make it show.'
        reaper.MB(msg, 'Warning', 0)
    end
end

function SetCustomColors()
    local title = 'Custom Colors'
    local captions = 'Background: (e.g. #525252),Text:,Border:,Swing:,\z
        Adaptive:,Snap on:,Snap off:,Snap separator:'

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
    AddCurrentValue(user_snap_on_color)
    AddCurrentValue(user_snap_off_color)
    AddCurrentValue(user_snap_sep_color)

    local curr_vals_str = table.concat(curr_vals, ',')

    local ret, inputs = reaper.GetUserInputs(title, 8, captions, curr_vals_str)
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
    user_snap_on_color = colors[6]
    user_snap_off_color = colors[7]
    user_snap_sep_color = colors[8]

    SaveThemeSettings(prev_color_theme)
    is_redraw = true

    if has_invalid_color then
        local msg = 'Please specify colors in hexadecimal format! (#RRGGBB)'
        reaper.MB(msg, 'Invalid input', 0)
    end
end

function ClearBitmap(bm, color)
    -- Note: Clear to transparent avoids artifacts on aliased rect corners
    if is_windows then
        reaper.JS_LICE_Clear(bm, 0x00000000)
    else
        reaper.JS_LICE_Clear(bm, color & 0x00FFFFFF)
    end
end

function DrawLICERect(bm, color, x, y, w, h, fill, r, a)
    if a == 0 then return end
    fill = fill or 0
    r = r or 0
    a = a or 1

    if not fill or fill == 0 then
        local LICE_RoundRect = reaper.JS_LICE_RoundRect
        for _ = 1, math.max(1, math.max(1, scale)) do
            LICE_RoundRect(bm, x, y, w - 1, h - 1, r, color, a, 0, true)
            x, y, w, h = x + 1, y + 1, w - 2, h - 2
        end
        return
    end

    if not r or r == 0 then
        -- Body
        reaper.JS_LICE_FillRect(bm, x, y, w, h, color, a, 0)
        return
    end

    if h <= 2 * r then r = math.floor(h / 2 - 1) end
    if w <= 2 * r then r = math.floor(w / 2 - 1) end

    -- Top left corner
    local LICE_FillCircle = reaper.JS_LICE_FillCircle
    LICE_FillCircle(bm, x + r, y + r, r, color, a, 0, 1)
    -- Top right corner
    LICE_FillCircle(bm, x + w - r - 1, y + r, r, color, a, 0, 1)
    -- Bottom right corner
    LICE_FillCircle(bm, x + w - r - 1, y + h - r - 1, r, color, a, 0, 1)
    -- Bottom left corner
    LICE_FillCircle(bm, x + r, y + h - r - 1, r, color, a, 0, 1)
    -- Ends
    reaper.JS_LICE_FillRect(bm, x, y + r, r, h - r * 2, color, a, 0)
    reaper.JS_LICE_FillRect(bm, x + w - r, y + r, r, h - r * 2, color, a, 0)
    -- Body and sides
    reaper.JS_LICE_FillRect(bm, x + r, y, w - r * 2, h, color, a, 0)
end

function DrawBackground(bg_color, corner_r, a)
    if a == 0 then return end
    if not bg_bitmap then
        bg_bitmap = reaper.JS_LICE_CreateBitmap(true, bm_w, bm_h)
        prev_bg_color = nil
    end

    if bg_color ~= prev_bg_color or corner_r ~= prev_bg_corner_r then
        prev_bg_color = bg_color
        prev_bg_corner_r = corner_r
        ClearBitmap(bg_bitmap, bg_color)
        DrawLICERect(bg_bitmap, bg_color, 0, 0, bm_w, bm_h, true, corner_r)
    end
    reaper.JS_LICE_Blit(bitmap, 0, 0, bg_bitmap, 0, 0, bm_w, bm_h, a, 'COPY')
end

function DrawSnapIcon(snap_color, x, y, h, a)
    if a == 0 then return end
    h = h + 1
    if not snap_bitmap then
        snap_bitmap = reaper.JS_LICE_CreateBitmap(true, h, h)
        prev_snap_color = nil
    end

    if snap_color ~= prev_snap_color then
        prev_snap_color = snap_color

        local r = (h - 1) // 2
        local d = 2 * r + 1

        local FillRect = reaper.JS_LICE_FillRect
        local LICE_FillCircle = reaper.JS_LICE_FillCircle

        -- Clear bitmap by substracting color
        FillRect(snap_bitmap, 0, 0, h, h, snap_color, -1, 'ADD')

        -- Draw circle for right side of snap icon
        LICE_FillCircle(snap_bitmap, r, r, r, snap_color, 1, 0, 1)
        LICE_FillCircle(snap_bitmap, r, r, r - 0.5, snap_color, 1, 0, 1)

        -- Draw rectangle for left side of snap icon
        FillRect(snap_bitmap, 0, 0, r, d, snap_color, 1, 0)

        -- Draw inner circle (subtractive)
        local inner_r = r // 1.6
        LICE_FillCircle(snap_bitmap, r, r, inner_r, snap_color, -1, 'ADD', 1)

        -- Draw inner rectangle (subtractive)
        local diff = r - inner_r
        FillRect(snap_bitmap, 0, diff, r, d - 2 * diff, snap_color, -1, 'ADD')
        -- Draw snap icon cutoff (subtractive)
        local snap_cut = r // 3
        FillRect(snap_bitmap, snap_cut, 0, snap_cut, d, snap_color, -1, 'ADD')

        -- Change icon when relative snap is enabled
        if prev_is_rel_snap then
            FillRect(snap_bitmap, 0, 0, snap_cut, d, snap_color, 1, 0)
        end
    end
    reaper.JS_LICE_Blit(bitmap, x, y, snap_bitmap, 0, 0, h, h, a, 'ADD')
end

function DrawLiceBitmap()
    local alpha = 0xFF000000

    -- Determine background color
    local bg_color = tonumber(user_bg_color or '242424', 16)
    local bg_alpha = 1
    if user_bg_color and #user_bg_color > 6 then
        bg_alpha = (bg_color >> 24) / 255
    end
    bg_color = bg_color | alpha

    ClearBitmap(bitmap, bg_color)

    -- Draw background
    local corner_radius
    if user_corner_radius then
        corner_radius = math.floor(user_corner_radius)
    else
        corner_radius = ScaleValue(6)
    end
    DrawBackground(bg_color, corner_radius, bg_alpha)

    -- Determine border color
    local border_color
    local border_alpha = 1
    if user_border_color then
        border_color = tonumber(user_border_color or '242424', 16)
        if #user_border_color > 6 then
            border_alpha = (border_color >> 24) / 255
        end
        border_color = border_color | alpha
    end
    -- Draw border
    if border_color then
        DrawLICERect(bitmap, border_color, 0, 0, bm_w, bm_h, false,
            corner_radius, border_alpha)
    end

    local snap_h = user_snap_size
    snap_h = snap_h or bm_h - 2 * math.max(ScaleValue(4), bm_h // 4)

    left_w = snap_h // 0.4
    local right_w = bm_w - left_w
    -- Check if snap icon will be visible
    local is_snap_hidden = hide_snap or left_w == 0
    if not is_snap_hidden then
        local hide_factor = user_snap_size and 1.3 or 2.3
        is_snap_hidden = left_w > bm_w / hide_factor
    end
    if is_snap_hidden then
        left_w = 0
        right_w = bm_w
    else
        local snap_on_color, snap_off_color, snap_sep_color
        local snap_on_alpha, snap_off_alpha, snap_sep_alpha = 1, 1, 1
        -- Determine snap on color
        if user_snap_on_color then
            snap_on_color = tonumber(user_snap_on_color, 16)
            if #user_snap_on_color > 6 then
                snap_on_alpha = (snap_on_color >> 24) / 255
            end
            snap_on_color = snap_on_color | alpha
        else
            snap_on_color = GetThemeColor('areasel_outline') | alpha
        end
        -- Determine snap off color
        snap_off_color = tonumber(user_snap_off_color or '787878', 16)
        if user_snap_off_color and #user_snap_off_color > 6 then
            snap_off_alpha = (snap_off_color >> 24) / 255
        end
        snap_off_color = snap_off_color | alpha
        -- Determine snap separator color
        snap_sep_color = tonumber(user_snap_sep_color or '3a3a3b', 16)
        if user_snap_sep_color and #user_snap_sep_color > 6 then
            snap_sep_alpha = (snap_sep_color >> 24) / 255
        end
        snap_sep_color = snap_sep_color | alpha

        -- Choose snap color based on snap state
        local snap_alpha = prev_is_snap and snap_on_alpha or snap_off_alpha
        local snap_color = prev_is_snap and snap_on_color or snap_off_color
        if prev_is_snap_hovered then
            -- Slightly brighten snap color when hovered
            snap_color = TintIntColor(snap_color, 1.145)
        end
        -- Draw snap icon
        local snap_x = (left_w - snap_h) // 1.78
        local snap_y = (bm_h - snap_h) // 2
        DrawSnapIcon(snap_color, snap_x, snap_y, snap_h, snap_alpha)
        -- Draw snap separator
        local m = math.max(ScaleValue(3), bm_h // 14)
        local sep_w = math.max(1, ScaleValue(1))
        local sep_x = left_w - sep_w
        local sep_h = bm_h - 2 * m
        DrawLICERect(bitmap, snap_sep_color, sep_x, m, sep_w, sep_h, true, 0,
            snap_sep_alpha)
    end

    -- Draw swing slider
    if prev_swing_amt ~= 0 then
        --Determine swing color
        local swing_color
        local swing_alpha = 1
        if user_swing_color then
            swing_color = tonumber(user_swing_color, 16)
            if #user_swing_color > 6 then
                swing_alpha = (swing_color >> 24) / 255
            end
            swing_color = swing_color | alpha
        else
            swing_color = GetThemeColor('areasel_outline') | alpha
        end
        -- Draw swing slider
        local m = ScaleValue(4)
        local h = ScaleValue(3)
        local y_offs = border_color and ScaleValue(1) or 0
        local value = prev_swing_amt

        local swing_len = math.ceil(math.abs(value) * (right_w - 2 * m) / 2)

        local x_offs = left_w
        if value > 0 then
            x_offs = x_offs + right_w // 2
        else
            x_offs = x_offs + math.ceil(right_w / 2) - swing_len
        end
        DrawLICERect(bitmap, swing_color, x_offs, bm_h - h - y_offs, swing_len, h,
            true, 0, swing_alpha)
    end

    -- Measure Text
    local icon_w = 0
    if is_adaptive then icon_w = gfx.measurestr('A') * 4 // 3 end

    -- If text with "Swing:" prefix doesn't fit, remove prefix
    if grid_text:match('^Swing:') then
        local text_w, text_h = gfx.measurestr('Swing: -100%')
        if text_w > right_w then
            grid_text = grid_text:gsub('^Swing:', '')
        end
    end
    local text_w, text_h = gfx.measurestr(grid_text)

    local text_x = (right_w - text_w + icon_w) // 2
    local text_y = (bm_h - text_h) // 2
    if is_macos then text_y = text_y + 1 end
    text_y = text_y + (user_font_yoffs or 0)

    local m = ScaleValue(2)
    if text_x - icon_w < m then
        text_x = icon_w + m
    end
    text_x = text_x + left_w

    -- Determine text color
    local text_color = tonumber(user_text_color or 'a9a9a9', 16) | alpha

    -- Draw Text
    reaper.JS_LICE_SetFontColor(lice_font, text_color)
    local len = tostring(grid_text):len()
    local LICE_DrawText = reaper.JS_LICE_DrawText
    LICE_DrawText(bitmap, lice_font, grid_text, len, text_x, text_y, bm_w, bm_h)

    -- Draw adaptive icon (A)
    if icon_w > 0 then
        -- Determine adaptive color
        local adaptive_color
        if user_adaptive_color then
            adaptive_color = tonumber(user_adaptive_color, 16) | alpha
        else
            adaptive_color = text_color
        end
        reaper.JS_LICE_SetFontColor(lice_font, adaptive_color)
        LICE_DrawText(bitmap, lice_font, 'A', 1, text_x - icon_w, text_y,
            bm_w, bm_h)
    end

    -- Refresh window
    reaper.JS_Window_InvalidateRect(window_hwnd, bm_x, bm_y, bm_x + bm_w,
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

local LoadCursor = reaper.JS_Mouse_LoadCursor
local normal_cursor = LoadCursor(is_windows and 32512 or 0)
local diag1_resize_cursor = LoadCursor(is_linux and 32642 or 32643)
local diag2_resize_cursor = LoadCursor(is_linux and 32643 or 32642)
local horz_resize_cursor = LoadCursor(32644)
local vert_resize_cursor = LoadCursor(32645)
local move_cursor = LoadCursor(32646)

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
        Intercept(window_hwnd, intercept.message, intercept.passthrough)
    end
end

function EndIntercepts()
    if not is_intercept then return end
    is_intercept = false
    for _, intercept in ipairs(intercepts) do
        Release(window_hwnd, intercept.message)
        intercept.timestamp = 0
    end

    if prev_cursor ~= normal_cursor then
        reaper.JS_Mouse_SetCursor(normal_cursor)
    end
    prev_cursor = -1
end

function LoadMenuScript()
    local env = setmetatable({menu = true, cmd = menu_cmd}, {__index = _G})
    env._G = env
    local menu_chunk, err = loadfile(menu_script, 'bt', env)
    if menu_chunk then
        menu_chunk()
        if type(env._G.menu) ~= 'table' then
            local err_msg = 'Please update Adaptive Grid to latest version'
            reaper.MB(err_msg:format(menu_script, err), 'GridBox', 0)
            return
        end
        return env
    end
    local err_msg = 'Could not load script: %s:\n%s'
    reaper.MB(err_msg:format(menu_script, err), 'GridBox', 0)
end

function PeekIntercepts(m_x, m_y)
    for _, intercept in ipairs(intercepts) do
        local msg = intercept.message
        local ret, _, time, _, wph = Peek(window_hwnd, msg)

        if ret and time ~= intercept.timestamp then
            intercept.timestamp = time

            if msg == 'WM_LBUTTONDOWN' then
                -- Avoid new clicks after showing menu
                if menu_time and reaper.time_precise() < menu_time + 0.05 then
                    return
                end
                is_left_click = true
                if reaper.JS_Mouse_GetState(16) == 16 then
                    if left_w == 0 or m_x - bm_x > left_w then
                        swing_drag_x = m_x
                    end
                elseif is_edit_mode then
                    drag_x = m_x
                    drag_y = m_y
                end
            end

            if msg == 'WM_LBUTTONUP' then
                if not is_left_click then return end
                if is_swing_drag then return end
                -- Check if left section is pressed
                if left_w > 0 and m_x - bm_x < left_w then
                    -- Check if alt is pressed
                    if reaper.JS_Mouse_GetState(16) == 16 then
                        -- Item edit: Toggle relative grid snap
                        reaper.Main_OnCommand(41054, 0)
                    else
                        -- Options: Toggle snapping
                        reaper.Main_OnCommand(1157, 0)
                    end
                    return
                end

                -- Make sure menu is loaded
                menu_env = menu_env or LoadMenuScript()
                if not menu_env then return end

                -- Check if alt is pressed
                if reaper.JS_Mouse_GetState(16) == 16 then
                    menu_env.SetStraightGrid()
                    local _, grid_div, swing, swing_amt = GetSetGrid(0, 0)
                    local new_swing = swing ~= 1 and 1 or 0
                    GetSetGrid(0, 1, nil, new_swing, swing_amt)
                    menu_env.SaveProjectGrid(grid_div, new_swing, swing_amt)
                    return
                end
                if resize_flags == 0 or math.min(bm_w, bm_h) < min_area_size * 1.5 then
                    -- Show adaptive grid menu
                    local new_menu_env = LoadMenuScript()
                    if new_menu_env then ShowMenu(new_menu_env._G.menu) end
                    local main_mult = menu_env.GetGridMultiplier()
                    local midi_mult = menu_env.GetMIDIGridMultiplier()
                    menu_env.UpdateToolbarToggleStates(0, main_mult)
                    menu_env.UpdateToolbarToggleStates(32060, midi_mult)
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
                -- Check if left section is pressed
                if left_w > 0 and m_x - bm_x < left_w then
                    -- Options: Show snap/grid settings
                    reaper.Main_OnCommand(40071, 0)
                    return
                end
                ShowRightClickMenu()
            end

            if msg == 'WM_MOUSEWHEEL' then
                -- Check if left section is hovered
                if left_w > 0 and m_x - bm_x < left_w then return end

                -- Make sure menu is loaded
                menu_env = menu_env or LoadMenuScript()
                if not menu_env then return end

                wph = wph * scroll_dir
                local mouse_state = reaper.JS_Mouse_GetState(20)
                -- Check if alt is pressed
                if mouse_state & 16 == 16 then
                    wph = wph / math.abs(wph)
                    local _, grid_div, swing, swing_amt = GetSetGrid(0, 0)
                    if swing == 0 then
                        menu_env.SetStraightGrid()
                        -- Note: Enable for "Adjust items when changing swing"
                        GetSetGrid(0, 1, nil, 1, swing_amt)
                    end
                    -- Scroll slower when Ctrl is pressed
                    local amt = wph * (mouse_state == 20 and 0.01 or 0.03)
                    GetSetGrid(0, 1, nil, 1, swing_amt + amt)
                    menu_env.SaveProjectGrid(grid_div, swing, swing_amt)
                else
                    local ext = 'FTC.AdaptiveGrid'
                    -- Calculate new grid division
                    local _, grid_div, swing, swing_amt = GetSetGrid(0, 0)
                    local factor = reaper.GetExtState(ext, 'zoom_div')
                    factor = tonumber(factor) or 2
                    grid_div = wph < 0 and grid_div * factor or grid_div / factor
                    -- Respect user limits
                    local min_grid_div = reaper.GetExtState(ext, 'min_limit')
                    min_grid_div = tonumber(min_grid_div) or 0
                    if min_grid_div == 0 then min_grid_div = 1 / 4096 * 2 / 3 end
                    if grid_div < min_grid_div then
                        if wph > 0 then return end
                    end
                    local max_grid_div = reaper.GetExtState(ext, 'max_limit')
                    max_grid_div = tonumber(max_grid_div) or 0
                    if max_grid_div == 0 then max_grid_div = 4096 * 3 / 2 end
                    if grid_div > max_grid_div then
                        if wph < 0 then return end
                    end
                    if not menu_env.LoadProjectGrid(grid_div) then
                        GetSetGrid(0, 1, grid_div, swing, swing_amt)
                    end
                end
            end
        end
    end
end

function ShowRightClickMenu()
    local curr_attach_mode = GetAttachMode()

    local comp_fps_entry
    if is_windows then
        comp_fps_entry = {
            title = 'Anti-flickering',
            is_checked = comp_fps ~= 30,
            OnReturn = function()
                local title = 'Limit underlying window frame rate (FPS)'
                local caption = 'FPS: (lower FPS -> less flicker)'

                local GetUserInputs = reaper.GetUserInputs
                local ret, input = GetUserInputs(title, 1, caption, comp_fps)
                if not ret then return end
                comp_fps = tonumber(input) or 30
                comp_fps = math.max(0, comp_fps)
                comp_delay = comp_fps == 0 and 0 or 1 / comp_fps
                reaper.SetExtState(extname, 'comp_fps', comp_fps, 1)
                is_resize = true
            end,
        }
    end

    local menu = {
        {
            title = 'Customize',
            {title = 'Size', OnReturn = SetCustomSize},
            {title = 'Font', OnReturn = SetCustomFont},
            {title = 'Snap', OnReturn = SetCustomSnapSize},
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
                    end,
                },
                {
                    title = 'Text',
                    OnReturn = function()
                        user_text_color = GetUserColor()
                        SaveThemeSettings(prev_color_theme)
                        is_redraw = true
                    end,
                },
                {
                    title = 'Border',
                    OnReturn = function()
                        user_border_color = GetUserColor()
                        SaveThemeSettings(prev_color_theme)
                        is_redraw = true
                    end,
                },
                {
                    title = 'Swing',
                    OnReturn = function()
                        user_swing_color = GetUserColor()
                        SaveThemeSettings(prev_color_theme)
                        is_redraw = true
                    end,
                },
                {
                    title = 'Adaptive',
                    OnReturn = function()
                        user_adaptive_color = GetUserColor()
                        SaveThemeSettings(prev_color_theme)
                        is_redraw = true
                    end,
                },
                {
                    title = 'Snap on',
                    OnReturn = function()
                        user_snap_on_color = GetUserColor()
                        SaveThemeSettings(prev_color_theme)
                        is_redraw = true
                    end,
                },
                {
                    title = 'Snap off',
                    OnReturn = function()
                        user_snap_off_color = GetUserColor()
                        SaveThemeSettings(prev_color_theme)
                        is_redraw = true
                    end,
                },
                {
                    title = 'Snap separator',
                    OnReturn = function()
                        user_snap_sep_color = GetUserColor()
                        SaveThemeSettings(prev_color_theme)
                        is_redraw = true
                    end,
                },
            },
            {separator = true},
            {
                title = 'Attach to',
                {
                    title = 'Left status edge',
                    is_checked = curr_attach_mode == 3,
                    is_grayed = attach_window_title ~= nil,
                    OnReturn = function()
                        attach_mode = 3
                        UpdateAttachPosition()
                        SaveThemeSettings(prev_color_theme)
                    end,
                },
                {
                    title = 'Right status edge',
                    is_checked = curr_attach_mode == 4,
                    is_grayed = attach_window_title ~= nil,
                    OnReturn = function()
                        attach_mode = 4
                        UpdateAttachPosition()
                        SaveThemeSettings(prev_color_theme)
                    end,
                },
                {
                    title = 'Left window edge',
                    is_checked = curr_attach_mode == 1,
                    OnReturn = function()
                        attach_mode = 1
                        UpdateAttachPosition()
                        SaveThemeSettings(prev_color_theme)
                    end,
                },
                {
                    title = 'Right window edge',
                    is_checked = curr_attach_mode == 2,
                    OnReturn = function()
                        attach_mode = 2
                        UpdateAttachPosition()
                        SaveThemeSettings(prev_color_theme)
                    end,
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

                    if attach_window_title then
                        msg = 'Move Gridbox back to transport?'
                        ret = reaper.MB(msg, 'Gridbox', 4)
                        if ret == 6 then
                            SaveAttachedWindow(nil)
                            window_hwnd = nil
                        end
                    end
                end,
            },
        },
        {
            title = 'Preferences',
            {
                title = 'Reverse scroll',
                is_checked = scroll_dir < 0,
                OnReturn = function()
                    scroll_dir = scroll_dir > 0 and -1 or 1
                    reaper.SetExtState(extname, 'scroll_dir', scroll_dir, true)
                end,
            },
            {
                title = 'Show snap button',
                is_checked = not hide_snap,
                OnReturn = function()
                    hide_snap = not hide_snap
                    local val = hide_snap and 1 or 0
                    reaper.SetExtState(extname, 'hide_snap', val, true)
                    is_redraw = true
                end,
            },
            {
                title = 'Display visible grid',
                is_checked = use_vis_grid,
                OnReturn = function()
                    use_vis_grid = not use_vis_grid
                    local val = use_vis_grid and 1 or 0
                    reaper.SetExtState(extname, 'use_vis_grid', val, true)
                    if use_vis_grid then
                        local msg = 'Visible grid can only be displayed for \z
                            straight grid divisions!'
                        reaper.MB(msg, 'Notice', 0)
                    end
                    prev_hzoom_lvl = nil
                    prev_grid_div = nil
                    prev_vis_grid_div = nil
                end,
            },
            comp_fps_entry,
        },
        {
            title = 'Lock position',
            is_checked = not is_edit_mode,
            OnReturn = function()
                is_edit_mode = not is_edit_mode
                ExtSave('is_edit_mode', is_edit_mode)
            end,
        },
        {
            title = 'Run script on startup',
            IsChecked = IsStartupHookEnabled,
            OnReturn = function()
                local is_enabled = IsStartupHookEnabled()
                local comment = 'Start script: Gridbox'
                local var_name = 'grid_box_cmd_name'
                SetStartupHookEnabled(not is_enabled, comment, var_name)

                menu_env = menu_env or LoadMenuScript()
                if not menu_env then return end

                comment = 'Start script: Adaptive grid (background process)'
                var_name = 'adaptive_grid_cmd'
                local is_adapt_enabled = menu_env.IsStartupHookEnabled()
                if is_enabled and is_adapt_enabled then
                    menu_env.SetStartupHookEnabled(false, comment, var_name)
                end
                if not is_enabled and not is_adapt_enabled then
                    menu_env.SetStartupHookEnabled(true, comment, var_name)
                end
            end,
        },
    }
    ShowMenu(menu)
end

function ShowMenu(menu)
    SetCursor(normal_cursor)

    local focus_hwnd = reaper.JS_Window_GetFocus()
    -- Open gfx window
    gfx.clear = GetThemeColor('col_main_bg2')
    local ClientToScreen = reaper.JS_Window_ClientToScreen
    local window_x, window_y = ClientToScreen(window_hwnd, 0, 0)
    window_x, window_y = window_x + 4, window_y + 4
    gfx.init('FTC.GB', ScaleValue(24), 0, 0, window_x, window_y)

    -- Open menu at bottom left corner
    local menu_x, menu_y = ClientToScreen(window_hwnd, bm_x, bm_y + bm_h)
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
    local status_hwnd = reaper.JS_Window_FindChildByID(window_hwnd, 1010)
    local _, st_l, st_t, st_r, st_b = reaper.JS_Window_GetRect(status_hwnd)
    st_l, st_t = reaper.JS_Window_ScreenToClient(window_hwnd, st_l, st_t)
    st_r, st_b = reaper.JS_Window_ScreenToClient(window_hwnd, st_r, st_b)

    -- Note: Window can be out of transport bounds
    st_l = math.max(st_l, 0)
    st_t = math.max(st_t, 0)
    st_r = math.min(st_r, window_w)
    st_b = math.min(st_b, window_h)

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
        reaper.JS_Window_InvalidateRect(window_hwnd, bm_x, bm_y,
            bm_x + bm_w, bm_y + bm_h, false)
    end

    bm_x, bm_y, bm_w, bm_h = x or bm_x, y or bm_y, w or bm_w, h or bm_h

    -- Redraw new area
    reaper.JS_Window_InvalidateRect(window_hwnd, bm_x, bm_y,
        bm_x + bm_w, bm_y + bm_h, false)

    if not is_resize then
        -- Change bitmap draw coordinates
        reaper.JS_Composite_Delay(window_hwnd, comp_delay, comp_delay * 1.5, 2)
        reaper.JS_Composite(window_hwnd, bm_x, bm_y, bm_w, bm_h, bitmap, 0, 0,
            bm_w, bm_h)
    end
end

function UpdateAttachPosition()
    local mode = GetAttachMode()
    if mode == 1 then
        attach_x = bm_x
    end
    if mode == 2 then
        attach_x = bm_x - window_w
    end
    if mode == 3 then
        local st_l = GetStatusWindowClientRect()
        attach_x = bm_x - st_l
    end
    if mode == 4 then
        local _, _, st_r = GetStatusWindowClientRect()
        attach_x = bm_x - st_r
    end
end

function GetAttachMode()
    local mode = attach_mode
    -- Note: Status window options are only valid when attached to transport
    if mode and mode > 2 and attach_window_title then
        mode = mode - 2
    end
    return mode
end

function GetAttachPosition()
    if not attach_x then return end
    local mode = GetAttachMode()
    local new_bm_x
    if mode == 1 then
        new_bm_x = attach_x
    end
    if mode == 2 then
        new_bm_x = attach_x + window_w
    end
    if mode == 3 or mode == 4 then
        local st_l = GetStatusWindowClientRect()
        new_bm_x = attach_x + st_l
    end
    if mode == 4 then
        local _, _, st_r = GetStatusWindowClientRect()
        new_bm_x = attach_x + st_r
    end
    return new_bm_x
end

function EnsureBitmapVisible()
    -- Ensure position/size is within bounds
    local w = math.max(min_area_size, math.min(bm_w, window_w))
    local h = math.max(min_area_size, math.min(bm_h, window_h))

    local x = math.max(0, math.min(window_w - w, bm_x))
    local y = math.max(0, math.min(window_h - h, bm_y))

    if attach_window_title then
        SetBitmapCoords(x, y, w, h)
        return
    end

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
        local space_r = window_w - st_r
        local space_t = st_t
        local space_b = window_h - st_b

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
        w = math.max(min_area_size, math.min(w, window_w))
        h = math.max(min_area_size, math.min(h, window_h))

        x = math.max(0, math.min(window_w - w, x))
        y = math.max(0, math.min(window_h - h, y))
    end

    SetBitmapCoords(x, y, w, h)
end

function FindInitialPosition()
    -- Get status window coordinates
    local st_l, st_t, st_r, st_b = GetStatusWindowClientRect()
    local st_y = st_t
    local st_h = math.abs(st_b - st_t)

    -- Set initial position that matches status window
    bm_x = 0
    bm_y = st_y
    bm_w = st_h * 5 // 2
    bm_h = st_h

    -- Add small vertical margin if status window takes up full transport height
    if st_h >= window_h - 4 then
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

    local ClientToScreen = reaper.JS_Window_ClientToScreen
    local x_start, y = ClientToScreen(window_hwnd, 0, st_mid_y)
    local x_end = ClientToScreen(window_hwnd, st_l, st_mid_y)

    for x = x_start, x_end do
        AddEmptyArea(x, y, 1)
    end
    AddEmptyArea(x_end, -1, 1)

    x_start = ClientToScreen(window_hwnd, st_r, st_mid_y)
    x_end = ClientToScreen(window_hwnd, window_w, st_mid_y)

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
        r = reaper.JS_Window_ScreenToClient(window_hwnd, r, st_mid_y)

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

function WaitForAttachedWindow()
    if attach_window_title == 'REAPER Main Window' then return true end
    if attach_window_title == 'Active MIDI editor' then return true end
    return attach_window_wait == attach_window_title
end

function FindAttachedWindow()
    local hwnd
    local window_cnt = 0
    if attach_window_title == 'REAPER Main Window' then
        hwnd = reaper.GetMainHwnd()
    elseif attach_window_title == 'Active MIDI editor' then
        hwnd = reaper.MIDIEditor_GetActive()
    else
        local cnt, list = reaper.JS_Window_ListFind(attach_window_title, 1)
        window_cnt = cnt
        if window_cnt > 0 then
            local first_addr = (list .. ','):match('(.-),')
            hwnd = reaper.JS_Window_HandleFromAddress(first_addr)
        end
        if hwnd then
            reaper.SetExtState(extname, 'attach_wait', attach_window_title, 1)
        end
    end
    if attach_window_child_id then
        hwnd = reaper.JS_Window_FindChildByID(hwnd, attach_window_child_id)
    end
    return hwnd, window_cnt
end

function SaveAttachedWindow(title, child_id)
    if not title or title == transport_title and not child_id then
        attach_window_title = nil
        attach_window_child_id = nil
        reaper.SetExtState(extname, 'attach_title', '', 1)
        reaper.SetExtState(extname, 'attach_child_id', '', 1)
        reaper.SetExtState(extname, 'attach_wait', '', 1)
    else
        attach_window_title = title
        attach_window_child_id = child_id
        reaper.SetExtState(extname, 'attach_title', title, 1)
        reaper.SetExtState(extname, 'attach_child_id', child_id or '', 1)
        reaper.SetExtState(extname, 'attach_wait', '', 1)
    end
end

function Main()
    -- Find window
    if not window_hwnd or not reaper.ValidatePtr(window_hwnd, 'HWND*') then
        local time = reaper.time_precise()
        if not prev_time or time > prev_time + 0.5 then
            prev_time = time
            local top_window_cnt = reaper.JS_Window_ArrayAllTop(top_window_array)
            if top_window_cnt ~= prev_top_window_cnt then
                prev_top_window_cnt = top_window_cnt
                if attach_window_title then
                    window_hwnd = FindAttachedWindow()
                else
                    window_hwnd = reaper.JS_Window_Find(transport_title, true)
                end
                is_resize = true
            end
        end
    end

    -- Go idle if window is not found/visible
    if not window_hwnd or not reaper.JS_Window_IsVisible(window_hwnd) then
        if attach_window_title then window_hwnd = nil end
        reaper.defer(Main)
        return
    end

    local x, y = reaper.GetMousePosition()
    local hover_hwnd = reaper.JS_Window_FromPoint(x, y)

    do
        local _, w, h = reaper.JS_Window_GetClientSize(window_hwnd)
        window_w, window_h = w, h
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

    -- Detect changes to window size
    if window_w ~= prev_window_w or window_h ~= prev_window_h then
        local prev_scale = scale
        scale = GetTransportScale()

        if scale ~= prev_scale then
            min_area_size = ScaleValue(12)

            local scale_factor = scale / prev_scale
            local new_bm_x = ScaleValue(bm_x, scale_factor)
            local new_bm_y = ScaleValue(bm_y, scale_factor)
            local new_bm_w = ScaleValue(bm_w, scale_factor)
            local new_bm_h = ScaleValue(bm_h, scale_factor)

            attach_x = ScaleValue(attach_x, scale_factor)
            user_snap_size = ScaleValue(user_snap_size, scale_factor)
            user_font_size = ScaleValue(user_font_size, scale_factor)
            user_font_yoffs = ScaleValue(user_font_yoffs, scale_factor)
            user_corner_radius = ScaleValue(user_corner_radius, scale_factor)

            if attach_x then new_bm_x = GetAttachPosition() end
            SetBitmapCoords(new_bm_x, new_bm_y, new_bm_w, new_bm_h)
            EnsureBitmapVisible()
            is_resize = true
        elseif prev_window_w then
            -- Move bitmap based on attached position
            local new_bm_x = GetAttachPosition()
            if new_bm_x then SetBitmapCoords(new_bm_x) end
            EnsureBitmapVisible()
        end
        prev_window_w = window_w
        prev_window_h = window_h
    end

    local is_snap_hovered = false
    local is_hovered = false

    if hover_hwnd == window_hwnd or drag_x then
        local ScreenToClient = reaper.JS_Window_ScreenToClient
        local m_x, m_y = ScreenToClient(window_hwnd, x, y)
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
                prev_bm_w = prev_bm_w or bm_w
                prev_bm_h = prev_bm_h or bm_h
                prev_bm_x = prev_bm_x or bm_x
                prev_bm_y = prev_bm_y or bm_y

                -- Move Gridbox to hovered window
                if hover_hwnd ~= window_hwnd then
                    prev_attach_hwnd = prev_attach_hwnd or window_hwnd
                    EndIntercepts()
                    reaper.JS_Composite_Delay(window_hwnd, 0, 0, 0)
                    -- Redraw previous area
                    reaper.JS_Window_InvalidateRect(window_hwnd, bm_x, bm_y,
                        bm_x + bm_w, bm_y + bm_h, false)
                    window_hwnd = hover_hwnd
                    reaper.JS_Window_SetFocus(hover_hwnd)

                    -- Get relative position to bitmap top left corner
                    local drag_x_diff = drag_x - bm_x
                    local drag_y_diff = drag_y - bm_y

                    -- Get new mouse window position
                    m_x, m_y = ScreenToClient(window_hwnd, x, y)

                    -- Set bitmap coordinates with relative position
                    -- Note: Avoid SetBitmapCoords as it doesn't allow going out
                    -- of bounds
                    bm_x = m_x - drag_x_diff
                    bm_y = m_y - drag_y_diff
                    drag_x = bm_x + drag_x_diff
                    drag_y = bm_y + drag_y_diff

                    StartIntercepts()

                    -- Remeasure window size
                    local _, w, h = reaper.JS_Window_GetClientSize(window_hwnd)
                    window_w, window_h = w, h

                    -- Avoid edge attachment
                    prev_window_w = nil
                    is_resize = true
                else
                    -- Move Gridbox inside window
                    local new_bm_x = bm_x + m_x - drag_x
                    local new_bm_y = bm_y + m_y - drag_y
                    SetBitmapCoords(new_bm_x, new_bm_y)
                end
                if m_x > 0 and m_y > 0 and m_x < window_w and m_y < window_h then
                    SetCursor(move_cursor)
                end
            end
            drag_x = m_x
            drag_y = m_y
            is_left_click = false
        end

        local m = ScaleValue(4)
        is_hovered = m_x > bm_x - m and m_y > bm_y - m and
            m_x < bm_x + bm_w + m and m_y < bm_y + bm_h + m

        if is_hovered then
            if is_edit_mode and not drag_x and not swing_drag_x then
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
            if not swing_drag_x and left_w > 0 and m_x - bm_x < left_w then
                is_snap_hovered = true
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
            -- Check if new attached window is valid
            if drag_x and prev_attach_hwnd and window_hwnd ~= prev_attach_hwnd then
                local is_reset = false
                local target_hwnd = window_hwnd
                local title = reaper.JS_Window_GetTitle(target_hwnd)

                local child_id = nil
                -- If window has no title, check if window has ID and parent has title
                if title == '' then
                    local parent_hwnd = reaper.JS_Window_GetParent(target_hwnd)
                    if reaper.ValidatePtr(parent_hwnd, 'HWND*') then
                        local id = reaper.JS_Window_GetLong(target_hwnd, 'ID')
                        id = tonumber(id)
                        if id and id > 0 then
                            child_id = id
                            title = reaper.JS_Window_GetTitle(parent_hwnd)
                            target_hwnd = parent_hwnd
                        end
                    end
                end

                -- Do not allow windows with empty titles
                if title == '' then
                    local msg = 'Can not attach Gridbox to this window.\n\n\z
                        Window does not have a title.'
                    reaper.MB(msg, 'Notice', 0)
                    is_reset = true
                end

                -- Do not allow titles with newline characters
                if not is_reset and title:match('\n') then
                    local msg = 'Can not attach Gridbox to this window.\n\n\z
                        Invalid window title:\n\nTITLE: %s'
                    reaper.MB(msg:format(title), 'Notice', 0)
                end

                local found_hwnd
                if not is_reset then
                    -- Check if new attached window can be found via Window_Find
                    local window_cnt, list = reaper.JS_Window_ListFind(title, 1)
                    if window_cnt > 1 then
                        local msg = 'Can not attach Gridbox to this window. \z
                            %d windows have the same title!\n\n\z
                            TITLE: %s\n\nIf this window is a toolbar, make sure \z
                            that it is only open once (not in toolbar docker) and \z
                            consider giving it a unique title.'
                        reaper.MB(msg:format(window_cnt, title), 'Notice', 0)
                        is_reset = true
                    elseif window_cnt == 0 then
                        local msg = 'Can not attach Gridbox to this window.\n\n\z
                            Could not find window by title.\n\nTITLE: %s'
                        reaper.MB(msg:format(title), 'Notice', 0)
                        is_reset = true
                    else
                        found_hwnd = reaper.JS_Window_HandleFromAddress(list)
                        if found_hwnd ~= target_hwnd then
                            local msg = 'Can not attach Gridbox to this window.\z
                                \n\nHandle missmatch'
                            reaper.MB(msg, 'Notice', 0)
                            is_reset = true
                        end
                    end
                end

                if not is_reset then
                    is_reset = true
                    -- Save accessible windows by custom ID instead of title
                    if target_hwnd == reaper.GetMainHwnd() then
                        title = 'REAPER Main Window'
                    end
                    if target_hwnd == reaper.MIDIEditor_GetActive() then
                        title = 'Active MIDI editor'
                    end

                    -- Prompt user to confirm new attachment
                    local msg = 'Gridbox will be attached to this window:\z
                            \n\nTITLE: %s%s\n\nProceed?'
                    local id_text = ''
                    if child_id then id_text = ('\nID: %d'):format(child_id) end
                    msg = msg:format(title, id_text)

                    local ret = reaper.MB(msg, 'Notice', 4)
                    if ret == 6 then
                        -- Save info on new attachment for next script startup
                        SaveAttachedWindow(title, child_id)
                        is_reset = false
                    end
                end

                if is_reset then
                    -- Move Gridbox back to previous window (pre-drag)
                    EndIntercepts()
                    reaper.JS_Composite_Delay(window_hwnd, 0, 0, 0)
                    -- Redraw previous area
                    reaper.JS_Window_InvalidateRect(window_hwnd, bm_x, bm_y,
                        bm_x + bm_w, bm_y + bm_h, false)

                    window_hwnd = prev_attach_hwnd
                    reaper.JS_Window_SetFocus(prev_attach_hwnd)

                    bm_w = prev_bm_w
                    bm_h = prev_bm_h
                    bm_x = prev_bm_x
                    bm_y = prev_bm_y

                    StartIntercepts()

                    -- Remeasure window size
                    local _, w, h = reaper.JS_Window_GetClientSize(window_hwnd)
                    window_w, window_h = w, h

                    -- Avoid edge attachment
                    prev_window_w = nil
                    is_resize = true
                end
            end
            EnsureBitmapVisible()
            UpdateAttachPosition()
            SaveThemeSettings(color_theme)
            drag_x = nil
            drag_y = nil
            is_redraw = true
            prev_attach_hwnd = nil
            prev_bm_w = nil
            prev_bm_h = nil
            prev_bm_x = nil
            prev_bm_y = nil
        end
    end

    if swing_drag_x then
        local m_x = reaper.JS_Window_ScreenToClient(window_hwnd, x, y)
        if reaper.JS_Mouse_GetState(3) == 0 then
            swing_drag_x = nil
            is_swing_drag = false
            is_redraw = true
        elseif math.abs(m_x - swing_drag_x) > 2 then
            is_swing_drag = true
            local swing_x = m_x - (bm_x + left_w)
            local swing_w = bm_w - left_w
            local swing_amt = 2 * swing_x / swing_w - 1
            swing_amt = swing_amt < -1 and -1 or swing_amt
            swing_amt = swing_amt > 1 and 1 or swing_amt
            -- Round swing to 2 digits
            swing_amt = math.floor(swing_amt * 100 + 0.5) / 100

            -- Make sure menu is loaded
            menu_env = menu_env or LoadMenuScript()

            local _, grid_div, swing = GetSetGrid(0, 0)
            if swing == 0 then
                if menu_env then menu_env.SetStraightGrid() end
                -- Note: Enable for "Adjust items when changing swing"
                GetSetGrid(0, 1, nil, 1, swing_amt)
            end
            GetSetGrid(0, 1, nil, 1, swing_amt)
            if menu_env then menu_env.SaveProjectGrid(grid_div, 1, swing_amt) end
        end
    end

    -- Monitor adaptive grid setting
    local main_mult = reaper.GetExtState('FTC.AdaptiveGrid', 'main_mult')
    if main_mult ~= prev_main_mult then
        prev_main_mult = main_mult
        is_adaptive = (tonumber(main_mult) or 0) ~= 0
        is_redraw = true
    end

    -- Monitor grid division
    local _, grid_div, swing, swing_amt = GetSetGrid(0, 0)
    -- Handle undefined grid (-inf)
    if grid_div ~= grid_div then grid_div = 1 end

    if swing_drag_x or is_hovered and not is_snap_hovered and
        reaper.JS_Mouse_GetState(16) == 16 then
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
    else
        local vis_grid_div
        local hzoom_lvl = use_vis_grid and reaper.GetHZoomLevel() or nil
        local hzoom_lvl_changed = prev_hzoom_lvl ~= hzoom_lvl
        if hzoom_lvl_changed and not is_adaptive and math.log(grid_div, 2) % 1 == 0 then
            prev_hzoom_lvl = hzoom_lvl

            local start_time, end_time = reaper.GetSet_ArrangeView2(0, 0, 0, 0)
            local _, _, _, start_beat = reaper.TimeMap2_timeToBeats(0, start_time)
            local _, _, _, end_beat = reaper.TimeMap2_timeToBeats(0, end_time)

            -- Current view width in pixels
            local arrange_pixels = (end_time - start_time) * hzoom_lvl
            -- Number of measures that fit into current view
            local arrange_measures = (end_beat - start_beat) / 4

            local measure_length_in_pixels = arrange_pixels / arrange_measures

            local spacing
            local ret, projgridmin = reaper.get_config_var_string('projgridmin')
            if ret then
                spacing = tonumber(projgridmin) or 8
            elseif reaper.SNM_GetIntConfigVar then
                spacing = reaper.SNM_GetIntConfigVar('projgridmin', 8)
            else
                spacing = reaper.GetExtState('FTC.AdaptiveGrid', 'projgridmin')
                spacing = tonumber(spacing) or 8
            end

            -- The maximum grid (divisions) that would be allowed with spacing
            local max_grid_div = spacing / measure_length_in_pixels

            vis_grid_div = grid_div
            -- Calculate smaller visible grid
            if grid_div < max_grid_div then
                local exp = math.ceil(math.log(max_grid_div / grid_div, 2))
                vis_grid_div = grid_div * 2 ^ exp
            end
            if vis_grid_div == prev_vis_grid_div then
                vis_grid_div = nil
            end
            prev_vis_grid_div = vis_grid_div
        end

        if grid_div ~= prev_grid_div or vis_grid_div then
            prev_grid_div = grid_div
            -- Grid division changed
            grid_div = vis_grid_div or grid_div

            is_adaptive = (tonumber(main_mult) or 0) ~= 0

            local num, denom = DecimalToFraction(grid_div)

            local is_triplet, is_dotted = false, false
            local is_quintuplet, is_septuplet = false, false

            if grid_div > 1 then
                is_triplet = 2 * grid_div % (2 / 3) == 0
                is_quintuplet = 4 * grid_div % (4 / 5) == 0
                is_septuplet = 4 * grid_div % (4 / 7) == 0
                is_dotted = 2 * grid_div % 3 == 0
            else
                is_triplet = 2 / grid_div % 3 == 0
                is_quintuplet = 4 / grid_div % 5 == 0
                is_septuplet = 4 / grid_div % 7 == 0
                is_dotted = 2 / grid_div % (2 / 3) == 0
            end

            local suffix = ''
            if is_triplet then
                suffix = 'T'
                denom = denom * 2 / 3
            elseif is_quintuplet then
                suffix = 'Q'
                denom = denom * 4 / 5
            elseif is_septuplet then
                suffix = 'S'
                denom = denom * 4 / 7
            elseif is_dotted then
                suffix = 'D'
                denom = denom / 2
                num = num / 3
            end

            -- Simplify fractions, e.g. 2/4 to 1/2
            if num > 1 then
                local rest = denom % num
                if rest == 0 then
                    denom = denom / num
                    num = 1
                end
            end

            if num >= denom and num % denom == 0 then
                grid_text = ('%.0f%s'):format(num / denom, suffix)
            else
                grid_text = ('%.0f/%.0f%s'):format(num, denom, suffix)
            end
            is_redraw = true
        end
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
        if snap_bitmap then reaper.JS_LICE_DestroyBitmap(snap_bitmap) end
        if bg_bitmap then reaper.JS_LICE_DestroyBitmap(bg_bitmap) end
        bitmap = reaper.JS_LICE_CreateBitmap(true, bm_w, bm_h)
        snap_bitmap = nil
        bg_bitmap = nil

        -- Determine font size
        font_size = user_font_size
        local font_family = user_font_family or 'Arial'
        if not font_size then
            font_size = 1
            -- Find optimal font size by incrementing until it doesn't target height
            local target_h = math.max(math.min(ScaleValue(14), bm_h), bm_h // 2.5)
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

        font_size = math.floor(font_size)
        local GDI_CreateFont = reaper.JS_GDI_CreateFont
        local gdi = GDI_CreateFont(font_size, 0, 0, 0, 0, 0, font_family)
        reaper.JS_LICE_SetFontFromGDI(lice_font, gdi, '')
        reaper.JS_GDI_DeleteObject(gdi)

        -- Set bitmap draw coordinates
        reaper.JS_Composite_Delay(window_hwnd, comp_delay, comp_delay * 1.5, 2)
        reaper.JS_Composite(window_hwnd, bm_x, bm_y, bm_w, bm_h, bitmap,
            0, 0, bm_w, bm_h)
        is_resize = false
        is_redraw = true
    end

    if left_w > 0 then
        local is_snap = reaper.GetToggleCommandState(1157) == 1
        if is_snap ~= prev_is_snap then
            prev_is_snap = is_snap
            is_redraw = true
        end

        local is_rel_snap = reaper.GetToggleCommandState(41054) == 1
        if is_rel_snap ~= prev_is_rel_snap then
            prev_is_rel_snap = is_rel_snap
            prev_snap_color = nil
            is_redraw = true
        end

        if is_snap_hovered ~= prev_is_snap_hovered then
            prev_is_snap_hovered = is_snap_hovered
            is_redraw = true
        end
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
    if snap_bitmap then reaper.JS_LICE_DestroyBitmap(snap_bitmap) end
    if bg_bitmap then reaper.JS_LICE_DestroyBitmap(bg_bitmap) end
    if lice_font then reaper.JS_LICE_DestroyFont(lice_font) end
    if window_hwnd then
        reaper.JS_Composite_Delay(window_hwnd, 0, 0, 0)
        if bm_x then
            reaper.JS_Window_InvalidateRect(window_hwnd, bm_x, bm_y,
                bm_x + bm_w, bm_y + bm_h, false)
        end
    end

    EndIntercepts()
end

local has_run = reaper.GetExtState(extname, 'has_run') == 'yes'
reaper.SetExtState(extname, 'has_run', 'yes', false)

-- Switch to fixed grid on startup if adaptive service is not enabled
if not has_run then
    local ext = 'FTC.AdaptiveGrid'
    local main_mult = tonumber(reaper.GetExtState(ext, 'main_mult')) or 0
    local midi_mult = tonumber(reaper.GetExtState(ext, 'midi_mult')) or 0
    if main_mult > 0 or midi_mult > 0 then
        local is_service_enabled = IsStartupHookEnabled(menu_cmd)
        if not is_service_enabled then
            reaper.SetExtState(ext, 'main_mult', 0, true)
            reaper.SetExtState(ext, 'midi_mult', 0, true)
        end
    end
end

if attach_window_title then
    local is_reset = false
    -- Give option to move Gridbox back to transport when attached window
    -- is not found upon script startup (or when multiple windows are found)
    local window_cnt = 0
    window_hwnd, window_cnt = FindAttachedWindow()

    if window_cnt > 1 then
        local msg = 'Found %d windows with the same title.\n\n\z
            Move Gridbox back to transport?'
        local ret = reaper.MB(msg:format(window_cnt), 'Gridbox', 4)
        is_reset = ret == 6
        ExtSave('start_cnt', nil)
    end

    if not window_hwnd and not WaitForAttachedWindow() then
        local msg = 'Could not find window.\n\nTITLE: %s\n\nWait for \z
            window to open?'
        local ret = reaper.MB(msg:format(attach_window_title), 'Gridbox', 4)
        is_reset = ret ~= 6
        if is_reset then
            reaper.MB('Moved Gridbox back to transport', 'Gridbox', 4)
        end
        ExtSave('start_cnt', nil)
    end

    -- Give option to move Gridbox back to transport when user quickly toggles
    -- the script 3 times in a row (in 3 seconds)
    local curr_time = reaper.time_precise()
    local start_cnt = ExtLoad('start_cnt', 1)
    local start_time = ExtLoad('start_time', curr_time)

    -- Check if more than 3 seconds have passed
    if math.abs(start_time - curr_time) > 3 then
        start_cnt = 1
        ExtSave('start_cnt', nil)
        ExtSave('start_time', nil)
    else
        start_cnt = start_cnt + 1
        -- Check if script has started 3 times
        if start_cnt > 3 then
            start_cnt = nil
            curr_time = nil
            local msg = 'Move Gridbox back to transport?'
            local ret = reaper.MB(msg, 'Gridbox', 4)
            is_reset = ret == 6
        end
        ExtSave('start_cnt', start_cnt)
        ExtSave('start_time', curr_time)
    end

    -- Move Gridbox window back to transport
    if is_reset then
        SaveAttachedWindow(nil)
        window_hwnd = nil
    end
end

reaper.atexit(Exit)
reaper.defer(Main)
