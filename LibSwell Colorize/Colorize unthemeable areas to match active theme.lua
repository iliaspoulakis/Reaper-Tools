--[[
  @author Ilias-Timon Poulakis (FeedTheCat)
  @license MIT
  @version 1.1.0
  @about Generates a libSwell.colortheme file that matches your active theme
  @changelog
    - Support overriding button color (separate script)
 ]]

local root_theme_path = reaper.GetExePath() .. '/libSwell.colortheme'
local user_theme_path = reaper.GetResourcePath() .. '/libSwell-user.colortheme'

local extname = 'FTC.LibSwell_Colorizer'
local theme_content = {}

-- Load custom colors
local custom_colors_str = reaper.GetExtState(extname, 'custom_colors')
local custom_colors = {}
for color in (custom_colors_str .. ','):gmatch('[^,]*') do
    custom_colors[#custom_colors + 1] = color ~= '' and color
end

-----------------------------------  FUNCTIONS  -------------------------------

function GetFileHash(file_path)
    local hash = 0
    local file = io.open(file_path, 'r')
    if not file then return end
    for line in file:lines() do
        for i = 1, line:len() do hash = hash + line:byte(i) end
    end
    io.close(file)
    return hash
end

function LoadLibSwellTheme(file_path)
    theme_content = {}
    local file = io.open(file_path, 'r')
    if not file then return end
    for line in file:lines() do theme_content[#theme_content + 1] = line end
    io.close(file)
end

function WriteLibSwellTheme(file_path)
    local file = io.open(file_path, 'w')
    if not file then return end
    for _, line in ipairs(theme_content) do file:write(line, '\n') end
    io.close(file)
end

function CreateBackupFile(file_path)
    local ext = '.bak'
    local i = 1
    -- Create numbered backups (filename.1.bak filename.2.bak etc.)
    while reaper.file_exists(file_path .. ext) do
        ext = '.' .. i .. '.bak'
        i = i + 1
    end
    local backup_path = file_path .. ext
    LoadLibSwellTheme(file_path)
    WriteLibSwellTheme(backup_path)

    local backup_file_name = backup_path:match('([^/\\]+)$')
    local msg = 'Your current libSwell colortheme was renamed to:\n\n '
    reaper.MB(msg .. backup_file_name, 'Warning', 0)
end

function ReplaceLibSwellColor(key, color)
    for i, line in ipairs(theme_content) do
        if line:match('^;*%s*' .. key .. ' #') then
            -- Remove comment
            line = line:gsub('^;*%s*', '')
            -- Replace color
            line = line:sub(1, #line - 1)
            theme_content[i] = line:gsub('#[^%s]+', color)
        end
    end
end

function RestartReaper()
    -- File: Close all projects
    reaper.Main_OnCommand(40886, 0)
    -- Check if user cancelled closing projects
    if reaper.IsProjectDirty(0) ~= 0 then
        local msg = 'In order for the changes to take effect, please \z
            restart REAPER.'
        reaper.MB(msg, 'Restart required', 0)
    else
        -- File: Quit REAPER
        reaper.Main_OnCommand(40004, 0)
        -- File: Spawn new instance of REAPER
        reaper.Main_OnCommand(40063, 0)
    end
end

function GetThemeColor(key)
    local color = reaper.GetThemeColor(key, 0)
    local r, g, b = reaper.ColorFromNative(color)
    return RGBToHex(r, g, b)
end

function HexToRGB(hex_color)
    hex_color = hex_color:gsub('#', '')
    local r = tonumber(hex_color:sub(1, 2), 16)
    local g = tonumber(hex_color:sub(3, 4), 16)
    local b = tonumber(hex_color:sub(5, 6), 16)
    return r, g, b
end

function RGBToHex(r, g, b)
    local int_color = r * 65536 + g * 256 + b
    return ('#%06x'):format(int_color)
end

-- Offsets the color by a given value (statically)
function OffsetColor(hex_color, offs)
    local r, g, b = HexToRGB(hex_color)
    r = r + offs
    g = g + offs
    b = b + offs
    r = r < 0 and 0 or r > 255 and 255 or r
    g = g < 0 and 0 or g > 255 and 255 or g
    b = b < 0 and 0 or b > 255 and 255 or b
    return RGBToHex(r, g, b)
end

-- Offsets the color by a percentage (relatively)
function ShadeColor(color, percent)
    local r, g, b = HexToRGB(color)
    r = math.floor(r * (100 + percent) / 100)
    g = math.floor(g * (100 + percent) / 100)
    b = math.floor(b * (100 + percent) / 100)
    r = r < 0 and 0 or r > 255 and 255 or r
    g = g < 0 and 0 or g > 255 and 255 or g
    b = b < 0 and 0 or b > 255 and 255 or b
    return RGBToHex(r, g, b)
end

function TintColor(hex_color, factor)
    local r, g, b = HexToRGB(hex_color)
    r = r + math.floor(factor * (255 - r))
    g = g + math.floor(factor * (255 - g))
    b = b + math.floor(factor * (255 - b))
    r = r < 0 and 0 or r > 255 and 255 or r
    g = g < 0 and 0 or g > 255 and 255 or g
    b = b < 0 and 0 or b > 255 and 255 or b
    return RGBToHex(r, g, b)
end

function IsDarkColor(hex_color)
    local r, g, b = HexToRGB(hex_color)
    return (r + g + b) / (3 * 256) < 0.5
end

function BlendColors(hex_color1, hex_color2, weight)
    -- The weight param can be used to balance the blend (Values between 0 and 1)
    weight = weight or 0.5
    local r1, g1, b1 = HexToRGB(hex_color1)
    local r2, g2, b2 = HexToRGB(hex_color2)
    local r = r1 + math.floor((r2 - r1) * weight)
    local b = b1 + math.floor((b2 - b1) * weight)
    local g = g1 + math.floor((g2 - g1) * weight)
    return RGBToHex(r, g, b)
end

--------------------------------------  COLORS  --------------------------------

-- Get colors from active user theme
local color_menubar = GetThemeColor('col_tl_bg')
local color_menubar_text = GetThemeColor('col_tl_fg')
local color_main_bg = GetThemeColor('col_main_bg')
local color_main_text = GetThemeColor('col_main_text')
local color_menu_bg = GetThemeColor('genlist_bg')
local color_menu_text = GetThemeColor('genlist_fg')
local color_menu_sel_bg = GetThemeColor('genlist_selbg')
local color_menu_sel_text = GetThemeColor('genlist_selfg')

-- Map each color to libSwell keys
local map = {}

--------------------------------------  MENUBAR  ------------------------------

map.menubar = {keys = {'menubar_bg'}, color = color_menubar}
map.menubar_text = {keys = {'menubar_text'}, color = color_menubar_text}

--------------------------------------  WINDOW  -------------------------------

map.main_bg = {keys = {'_3dface', 'edit_bg_disabled'}, color = color_main_bg}

map.main_text = {
    keys = {
        'checkbox_text', 'edit_text', 'label_text', 'tab_text', 'group_text',
    },
    color = color_main_text,
}

map.main_text_disabled = {
    keys = {
        'checkbox_text_disabled', 'edit_text_disabled', 'label_text_disabled',
    },
    color = BlendColors(color_main_text, color_main_bg, 0.55),
}
map.main_sh = {keys = {'group_shadow'}, color = color_main_bg, shade = 4}
map.main_hl = {keys = {'group_hilight'}, color = color_main_bg, shade = -12}

--------------------------------------  MENU  ---------------------------------

map.menu_bg = {
    keys = {
        'menu_bg', 'treeview_bg', 'listview_bg', 'info_bk', 'trackbar_track',
        'trackbar_mark', 'scrollbar_bg', '_3dshadow', '_3dhilight',
        '_3ddkshadow', 'tab_shadow', 'tab_hilight',
    },
    color = color_menu_bg,
}

map.menu_text = {
    keys = {
        'menu_text', 'treeview_text', 'listview_text', 'listview_hdr_text',
        'info_text', 'focusrect', 'edit_cursor', 'combo_text',
    },
    color = color_menu_text,
}

map.menu_text_disabled = {
    keys = {
        'menu_text_disabled', 'menubar_text_disabled', 'combo_text_disabled',
    },
    color = BlendColors(color_menu_text, color_menu_bg, 0.55),
}

map.menu_hl = {keys = {'menu_hilight'}, color = color_menu_bg, shade = 4}
map.menu_sh = {keys = {'menu_shadow'}, color = color_menu_bg, shade = -12}

-------------------------------  MENU SELECT  ---------------------------------

map.menu_sel_bg = {
    keys = {
        'menubar_bg_sel', 'menu_bg_sel', 'combo_arrow_press', 'checkbox_inter',
        'edit_bg_sel', 'trackbar_knob', 'progress', 'listview_bg_sel',
        'treeview_bg_sel', 'focus_hilight',
    },
    color = color_menu_sel_bg,
}

map.menu_sel_text = {
    keys = {
        'menubar_text_sel', 'menu_text_sel', 'edit_text_sel',
        'listview_text_sel', 'treeview_text_sel',
    },
    color = color_menu_sel_text,
}

-------------------------------  MENU EXTRAS  --------------------------------

map.menu_header = {
    keys = {'listview_hdr_bg', 'menu_scroll', 'scrollbar'},
    color = color_menu_bg,
    shade = 13,
}

map.menu_header_sh = {
    keys = {'listview_hdr_shadow', 'listview_hdr_hilight', 'listview_grid'},
    color = color_menu_bg,
    shade = -20,
}

map.menu_arrow = {
    keys = {
        'checkbox_fg', 'combo_arrow', 'treeview_arrow', 'menu_scroll_arrow',
        'listview_hdr_arrow', 'menu_submenu_arrow',
    },
    color = color_menu_text,
    offs = -14,
}

map.menu_scroll = {keys = {'scrollbar_fg'}, color = color_menu_bg, offs = 42}

------------------------ EDIT / COMBO / CHECKBOX  -------------------------

local is_dark_theme = IsDarkColor(color_main_bg)

map.edit = {
    keys = {'edit_bg'},
    color = color_main_bg,
    shade = is_dark_theme and -4 or 6,
}

map.edit_border = {
    keys = {'edit_shadow', 'edit_hilight', 'button_shadow', 'button_hilight'},
    color = color_main_bg,
    shade = -37,
}

map.combo = {
    keys = {'combo_bg', 'combo_bg2', 'combo_shadow', 'combo_hilight'},
    color = color_menu_bg,
    shade = -9,
}

map.checkbox = {
    keys = {'checkbox_bg'},
    color = BlendColors(color_main_bg, color_menu_bg),
    shade = is_dark_theme and -12 or 12,
}

-------------------------------  BUTTON  -----------------------------------

local weight = IsDarkColor(color_main_text) and 0.33 or 0.66
local color_button = custom_colors[1] or
    BlendColors(color_main_bg, color_menu_sel_bg, weight)

map.buttons = {keys = {'button_bg'}, color = color_button}

map.button_text = {keys = {'button_text'}, color = color_main_text}

map.button_text_disabled = {
    keys = {'button_text_disabled'},
    color = BlendColors(color_main_text, color_button, 0.55),
}

map.button_border = {
    keys = {'button_shadow', 'button_hilight'},
    color = color_main_bg,
    offs = -11,
    shade = -37,
}
-------------------------------  MAIN CODE  -----------------------------------

reaper.Undo_OnStateChange('Colorize unthemeable areas')

if reaper.GetOS() ~= 'Other' then
    reaper.MB('This script only works on Linux', 'Unsupported platform', 0)
    return
end

if not reaper.file_exists(root_theme_path) then
    reaper.MB('Could not find file: ' .. root_theme_path, 'Error', 0)
    return
end

if reaper.file_exists(user_theme_path) then
    local saved_hash = tonumber(reaper.GetExtState(extname, 'hash'))
    if saved_hash ~= GetFileHash(user_theme_path) then
        CreateBackupFile(user_theme_path)
    end
end

LoadLibSwellTheme(root_theme_path)

-- Replace libSwell colors according to map
for k, v in pairs(map) do
    if not v.keys then
        reaper.MB('No libSwell keys defined for map: ' .. k, 'Error', 0)
        return
    end
    if not v.color then
        reaper.MB('Invalid color! Check map: ' .. k, 'Error', 0)
        return
    end
    -- Adjust colors
    if tonumber(v.offs) then v.color = OffsetColor(v.color, v.offs) end
    if tonumber(v.shade) then v.color = ShadeColor(v.color, v.shade) end
    if tonumber(v.tint) then v.color = TintColor(v.color, v.tint) end
    for _, key in ipairs(v.keys) do
        if v.color then ReplaceLibSwellColor(key, v.color) end
    end
end

WriteLibSwellTheme(user_theme_path)
reaper.SetExtState(extname, 'hash', GetFileHash(user_theme_path), true)
RestartReaper()
