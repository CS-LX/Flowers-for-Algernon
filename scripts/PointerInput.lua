-- 玩法指针：鼠标和第一根手指合成一份每帧状态。
-- 手机上 GetMouseButtonPress 不会跟着触摸走，路径点击和机关拖拽必须读这里。

local UI = require("urhox-libs/UI")

local PointerInput = {}

---@class PointerState
---@field position Vector2
---@field down boolean
---@field pressed boolean
---@field fromTouch boolean
---@field pointerId number

local lastTouchCount = 0
local lastPosition = Vector2(0, 0)
local suppressMousePress = 0

---@type PointerState
local state = {
    position = Vector2(0, 0),
    down = false,
    pressed = false,
    fromTouch = false,
    pointerId = 0,
}

local function CopyPosition(source)
    return Vector2(source.x, source.y)
end

function PointerInput.BeginFrame()
    local touchCount = input:GetNumTouches()
    if touchCount > 0 then
        local touch = input:GetTouch(0)
        local position = CopyPosition(touch.position)
        state.position = position
        state.down = true
        state.pressed = lastTouchCount == 0
        state.fromTouch = true
        state.pointerId = touch.touchID or 1
        lastPosition = position
        suppressMousePress = 12
        if state.pressed then
            print(string.format(
                "PointerInput: touch press x=%.0f y=%.0f id=%s",
                position.x,
                position.y,
                tostring(state.pointerId)
            ))
        end
    elseif lastTouchCount > 0 then
        state.position = lastPosition
        state.down = false
        state.pressed = false
        state.fromTouch = true
        state.pointerId = 1
        suppressMousePress = 12
    else
        local mouse = input:GetMousePosition()
        state.position = Vector2(mouse.x, mouse.y)
        state.down = input:GetMouseButtonDown(MOUSEB_LEFT)
        state.pressed = input:GetMouseButtonPress(MOUSEB_LEFT)
        state.fromTouch = false
        state.pointerId = 0
        if suppressMousePress > 0 then
            suppressMousePress = suppressMousePress - 1
            state.pressed = false
        end
        lastPosition = state.position
    end
    lastTouchCount = touchCount
end

---@return PointerState
function PointerInput.Get()
    return state
end

---@param camera Camera
---@return Ray
function PointerInput.GetScreenRay(camera)
    local width = math.max(1, graphics:GetWidth())
    local height = math.max(1, graphics:GetHeight())
    return camera:GetScreenRay(state.position.x / width, state.position.y / height)
end

---@return boolean
function PointerInput.IsOverUI()
    if UI.IsPointerOverUI() or UI.GetPressedWidget() then
        return true
    end
    for pointerId = 0, 32 do
        if UI.GetHoveredWidgetForPointer(pointerId) or UI.GetPressedWidgetForPointer(pointerId) then
            return true
        end
    end
    return false
end

return PointerInput
