-- 叙事门静物的触发辅助脚本。
-- JSON / Inspector 只声明 triggerable 和 Trigger ID；
-- 是否开火由这里判断：角色进入门体积，并且 open >= 0.95。

local Door = {}

Door.OPEN_THRESHOLD = 0.95
-- 门板打开后包围盒会变；只略微外扩到门槛，不要把体积撑成整段楼梯。
Door.BOUNDS_INFLATE = 0.08

---@class DoorTriggerContext
---@field playerPosition Vector3|nil
---@field worldBox BoundingBox|nil

---@param box BoundingBox
---@param inflate number
---@return BoundingBox
function Door.InflateBox(box, inflate)
    local extra = inflate or Door.BOUNDS_INFLATE
    return BoundingBox(
        Vector3(box.min.x - extra, box.min.y - extra, box.min.z - extra),
        Vector3(box.max.x + extra, box.max.y + extra, box.max.z + extra)
    )
end

---@param context DoorTriggerContext
---@return boolean
function Door.IsEntered(context)
    if not context or not context.playerPosition or not context.worldBox then
        return false
    end
    local result = context.worldBox:IsInside(context.playerPosition)
    return result == INSIDE or result == INTERSECTS
end

---@param object table
---@param context DoorTriggerContext
---@return boolean
function Door.ShouldFire(object, context)
    if not object then
        return false
    end
    local open = object:GetDriver("open")
    if open < Door.OPEN_THRESHOLD then
        return false
    end
    if not context or not context.playerPosition or not context.worldBox then
        return false
    end
    return Door.IsEntered({
        playerPosition = context.playerPosition,
        worldBox = Door.InflateBox(context.worldBox, Door.BOUNDS_INFLATE),
    })
end

return Door
