-- 关卡装饰静物。
-- 无体素、无 PathNode、无机关；只保存父节点局部 Transform 和后续模型引用。

local StillObject = {}
StillObject.__index = StillObject

local KIND = "stillObject"

local function CopyVector(value, fallback)
    value = value or {}
    fallback = fallback or {}
    return {
        x = value.x ~= nil and value.x or (fallback.x or 0),
        y = value.y ~= nil and value.y or (fallback.y or 0),
        z = value.z ~= nil and value.z or (fallback.z or 0),
    }
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

function StillObject:ToTable()
    return {
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
end

function StillObject.FromTable(data)
    if type(data) ~= "table" or type(data.id) ~= "string" or data.id == "" then
        return nil, "invalid StillObject"
    end
    return StillObject.New(data)
end

return StillObject
