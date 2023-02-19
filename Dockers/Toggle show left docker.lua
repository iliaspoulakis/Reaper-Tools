--[[
  @author Ilias-Timon Poulakis (FeedTheCat)
  @license MIT
  @version 1.1.0
  @provides [main=main] .
  @about Toggle show dockers attached to one side of the main window
  @changelog
    - Fix issue where windows would appear in random dockers
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

local main_hwnd = reaper.GetMainHwnd()
local docker_hwnds = GetChildren(main_hwnd, 'REAPER_dock')

local dockers = {}
local is_visible = false
local child_cnt = 0

-- Get all dockers at position
for _, docker_hwnd in ipairs(docker_hwnds) do
    local id = reaper.DockIsChildOfDock(docker_hwnd)
    if reaper.DockGetPosition(id) == pos then
        local docker = {}
        docker.id = id
        docker.hwnd = docker_hwnd
        docker.is_visible = reaper.JS_Window_IsVisible(docker_hwnd)
        -- Note: Avoid children with empty names
        docker.children = GetChildren(docker_hwnd, '.')
        table.insert(dockers, docker)
        -- Check if any docker at position is currently visible
        is_visible = is_visible or docker.is_visible
        -- Count total children of all docks at position
        child_cnt = child_cnt + #docker.children
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
                local IsChild = reaper.JS_Window_IsChild
                local GetClientRect = reaper.JS_Window_GetClientRect
                -- Get top window at center of docker using Window_FromPoint
                local _, l, t, r, b = GetClientRect(docker.hwnd)
                local x, y = l + (r - l) // 2, t + (b - t) // 2
                local top_hwnd = reaper.JS_Window_FromPoint(x, y)
                -- Go through all docker children and match top window
                for c, child in ipairs(docker.children) do
                    if child == top_hwnd or IsChild(child, top_hwnd) then
                        -- Save active index in extstate
                        reaper.SetExtState(extname, docker.id, c, true)
                    end
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
