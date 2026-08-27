-- 关卡装饰静物。
-- 无体素、无 PathNode、无机关；只保存父节点局部 Transform 和后续模型引用。

local StillObject = {}
StillObject.__index = StillObject

local KIND = "stillObject"
local MODE_TRIGGERABLE = "triggerable"

local ALLOWED_MODES = {
    triggerable = true,
}


local function CopyVector(value, fallback)
    value = value or {}
    fallback = fallback or {}
    return {
        x = value.x ~= nil and value.x or (fallback.x or 0),
        y = value.y ~= nil and value.y or (fallback.y or 0),
        z = value.z ~= nil and value.z or (fallback.z or 0),
    }
end

local function CopyBehaviorModes(source)
    local result = {}
    local known = {}
    for _, mode in ipairs(source or {}) do
        if ALLOWED_MODES[mode] and not known[mode] then
            known[mode] = true
            result[#result + 1] = mode
        end
    end
    return result
end

local function HasMode(modes, wanted)
    for _, mode in ipairs(modes) do
        if mode == wanted then
            return true
        end
    end
    return false
end

function StillObject.New(data)
    local self = setmetatable({}, StillObject)
    self:Init(data)
    return self
end

function StillObject:Init(data)
    data = data or {}
    self.kind = KIND
    self.id = data.id or "still"
    self.name = data.name or self.id
    self.parentId = data.parentId
    self.modelPath = type(data.modelPath) == "string" and data.modelPath or ""
    local transform = data.transform or {}
    self.transform = {
        position = CopyVector(transform.position),
        rotation = CopyVector(transform.rotation),
        scale = CopyVector(transform.scale, { x = 1, y = 1, z = 1 }),
    }
    self.behaviorModes = CopyBehaviorModes(data.behaviorModes)
    self.behaviors = {}
    if HasMode(self.behaviorModes, MODE_TRIGGERABLE) then
        local source = (data.behaviors or {}).triggerable or {}
        self.behaviors.triggerable = {
            triggerId = type(source.triggerId) == "string" and source.triggerId or "",
        }
    end
end

function StillObject:SetName(name)
    name = tostring(name or "")
    if name == "" then
        return false
    end
    self.name = name
    return true
end

function StillObject:SetParentId(parentId)
    if parentId == "" then
        parentId = nil
    end
    self.parentId = parentId
    return true
end

function StillObject:SetPosition(position)
    self.transform.position = CopyVector(position)
    return true
end

function StillObject:SetRotation(rotation)
    self.transform.rotation = CopyVector(rotation)
    return true
end

function StillObject:SetScale(scale)
    if type(scale) == "number" then
        scale = { x = scale, y = scale, z = scale }
    end
    local copied = CopyVector(scale, { x = 1, y = 1, z = 1 })
    if copied.x <= 0 or copied.y <= 0 or copied.z <= 0 then
        return false
    end
    self.transform.scale = copied
    return true
end

function StillObject:SetModelPath(path)
    self.modelPath = type(path) == "string" and path or ""
    return true
end

function StillObject:HasModel()
    return self.modelPath ~= ""
end

function StillObject:HasBehavior(mode)
    return HasMode(self.behaviorModes, mode)
end

function StillObject:SetInteraction(mode, enabled)
    if not ALLOWED_MODES[mode] then
        return false
    end
    local hasMode = self:HasBehavior(mode)
    if enabled and not hasMode then
        self.behaviorModes[#self.behaviorModes + 1] = mode
    elseif (not enabled) and hasMode then
        local nextModes = {}
        for _, current in ipairs(self.behaviorModes) do
            if current ~= mode then
                nextModes[#nextModes + 1] = current
            end
        end
        self.behaviorModes = nextModes
        self.behaviors[mode] = nil
    end
    if enabled and mode == MODE_TRIGGERABLE then
        self.behaviors.triggerable = self.behaviors.triggerable or { triggerId = "" }
    end
    return true
end

function StillObject:SetTriggerId(triggerId)
    if not self:HasBehavior(MODE_TRIGGERABLE) then
        return false
    end
    self.behaviors.triggerable.triggerId = tostring(triggerId or "")
    return true
end


function StillObject:ToTable()
    local data = {
        kind = KIND,
        id = self.id,
        name = self.name,
        parentId = self.parentId,
        modelPath = self.modelPath ~= "" and self.modelPath or nil,
        transform = {
            position = CopyVector(self.transform.position),
            rotation = CopyVector(self.transform.rotation),
            scale = CopyVector(self.transform.scale, { x = 1, y = 1, z = 1 }),
        },
    }
    if #self.behaviorModes > 0 then
        data.behaviorModes = {}
        for index, mode in ipairs(self.behaviorModes) do
            data.behaviorModes[index] = mode
        end
    end
    if self:HasBehavior(MODE_TRIGGERABLE) then
        data.behaviors = {
            triggerable = {
                triggerId = self.behaviors.triggerable.triggerId,
            },
        }
    end
    return data
end

function StillObject.FromTable(data)
    if type(data) ~= "table" or type(data.id) ~= "string" or data.id == "" then
        return nil, "invalid StillObject"
    end
    return StillObject.New(data)
end

return StillObject
