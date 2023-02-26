--[[
  @author Ilias-Timon Poulakis (FeedTheCat)
  @license MIT
  @version 1.4.0
  @provides [main=main] .
  @about Toggle show dockers attached to one side of the main window
  @changelog
    - Regress behavior of reopening window
]]
local extname = 'FTC_dockers'
local _, file, sec, cmd = reaper.get_action_context()

-- Get docker position (left, right, etc.) from file name
local pos_str = file:match('show (.-) docker%.lua$')
local pos_ids = {bottom = 0, left = 1, top = 2, right = 3}
local pos = pos_ids[pos_str] or 0

reaper.Undo_OnStateChange(('Toggle %s docker'):format(pos_str))

-- Check if js_ReaScriptAPI extension is installed
if not reaper.JS_Window_ListAllChild then
    reaper.MB('Please install js_ReaScriptAPI extension', 'Error', 0)
    return
end

function print(msg) reaper.ShowConsoleMsg(tostring(msg) .. '\n') end

function GetChildren(parent_hwnd, filter)
    local children = {}
    local ret, list = reaper.JS_Window_ListAllChild(parent_hwnd)
    if ret ~= 0 then
        for addr in (list .. ','):gmatch('(.-),') do
            local hwnd = reaper.JS_Window_HandleFromAddress(addr)
            local class = reaper.JS_Window_GetClassName(hwnd)
            if class ~= 'WDLTabCtrl' then
                if reaper.JS_Window_GetParent(hwnd) == parent_hwnd then
                    local GetTitle = reaper.JS_Window_GetTitle
                    if not filter or GetTitle(hwnd):match(filter) then
                        table.insert(children, hwnd)
                    end
                end
            end
        end
    end
    return children
end

function GetActiveDockerIndex(docker)
    -- Get top window using Window_FromPoint
    local _, l, t, r, b = reaper.JS_Window_GetClientRect(docker.hwnd)
    -- Calculate margins (windows might be smaller than docker)
    local m_x = (l - t) // 10
    local m_y = (b - t) // 10
    -- Try different points (e.g. center, corners etc)
    local points = {}
    -- Center
    points[1] = {x = l + (r - l) // 2, y = t + (b - t) // 2}
    -- Top left corner
    points[2] = {x = l + m_x, y = t + m_y}
    -- Bottom left corner
    points[3] = {x = l + m_x, y = t + (b - t) - m_y}
    -- Top right corner
    points[4] = {x = l + r - m_x, y = t + m_y}
    -- Bottom right corner
    points[5] = {x = l + r - m_x, y = t + (b - t) - m_y}

    for p, point in ipairs(points) do
        local top_hwnd = reaper.JS_Window_FromPoint(point.x, point.y)
        -- Go through all docker children and match top window
        for c, child in ipairs(docker.children) do
            if child == top_hwnd or reaper.JS_Window_IsChild(child, top_hwnd) then
                return c
            end
        end
    end
end

local title_children_map = {}

-- Recursively find a window title that is not already used, e.g. title (3)
function FindAvailableWindowTitle(title)
    if not title_children_map[title] then
        title_children_map[title] = {title}
        return title
    end
    -- Increment current title appendix number
    local num = tonumber(title:match(' %((%d+)%)$')) or 1
    num = num + 1
    title = title:gsub(' %(%d+%)$', '') .. (' (%d)'):format(num)
    return FindAvailableWindowTitle(title)
end

local main_hwnd = reaper.GetMainHwnd()
local docker_hwnds = GetChildren(main_hwnd, 'REAPER_dock')

local dockers = {}
local is_visible = false
local child_cnt = 0

-- Get all dockers at position
for _, docker_hwnd in ipairs(docker_hwnds) do
    local id = reaper.DockIsChildOfDock(docker_hwnd)
    -- Note: Avoid children with empty names for MacOS
    local children = GetChildren(docker_hwnd, '.')
    if reaper.DockGetPosition(id) == pos then
        local docker = {}
        docker.id = id
        docker.hwnd = docker_hwnd
        docker.is_visible = reaper.JS_Window_IsVisible(docker_hwnd)
        docker.children = children
        table.insert(dockers, docker)
        -- Check if any docker at position is currently visible
        is_visible = is_visible or docker.is_visible
        -- Count total children of all docks at position
        child_cnt = child_cnt + #docker.children
    end
    -- Save all docker children in a table by title
    for _, child in ipairs(children) do
        local title = reaper.JS_Window_GetTitle(child)
        title_children_map[title] = title_children_map[title] or {}
        table.insert(title_children_map[title], child)
    end
end

-- Rename children with duplicate titles (for Dock_UpdateDockID function)
for title, children in pairs(title_children_map) do
    for i = 2, #children do
        local new_title = FindAvailableWindowTitle(title)
        reaper.JS_Window_SetTitle(children[i], new_title)
        reaper.DockWindowRefreshForHWND(children[i])
    end
end

-- Exit when no dock (with children) is found at position
if child_cnt == 0 then
    reaper.SetToggleCommandState(sec, cmd, 0)
    return
end

-- Set toolbar toggle state
reaper.SetToggleCommandState(sec, cmd, is_visible and 0 or 1)

for _, docker in ipairs(dockers) do
    -- Toggle docker visibility (only dockers that need change)
    if docker.is_visible == is_visible then
        if docker.is_visible then
            -- Save active docker child index for next script run
            if #docker.children > 1 then
                local index = GetActiveDockerIndex(docker)
                if index then
                    -- Save active index in extstate
                    reaper.SetExtState(extname, docker.id, index, true)
                end
            end
            -- Remove docker children from dock (hide dock)
            for _, child in ipairs(docker.children) do
                local title = reaper.JS_Window_GetTitle(child)
                reaper.Dock_UpdateDockID(title, docker.id)
                reaper.DockWindowRemove(child)
            end
        else
            -- Add docker children to dock (show dock)
            for _, child in ipairs(docker.children) do
                local title = reaper.JS_Window_GetTitle(child)
                reaper.DockWindowRemove(child)
                reaper.DockWindowAddEx(child, title, title, true)
            end
            -- Restore active docker child index
            local n = tonumber(reaper.GetExtState(extname, docker.id))
            if n and docker.children[n] and #docker.children > 1 then
                reaper.DockWindowActivate(docker.children[n])
            end
        end
    end
end
