-- 关卡级 JSON 文档。
-- 只管理 Part 定义、关卡级固定相机和保存路径；不持有局部体素、Scene Node 或 Bake 缓存。

local PartDefinition = require "PartDefinition"

local LevelDocument = {}
LevelDocument.__index = LevelDocument

local FORMAT = "tri-prism-monument-level"
local FORMAT_VERSION = 1

local function CopyVector(value)
    value = value or {}
    return {
        x = value.x or 0,
        y = value.y or 0,
        z = value.z or 0,
    }
end

local function CopyCamera(camera)
    camera = camera or {}
    return {
        projection = "orthographic",
        pitch = 30,
        yaw = camera.yaw or 30,
        orthoSize = camera.orthoSize or 10.0,
        nearClip = camera.nearClip or 0.1,
        farClip = camera.farClip or 100.0,
        target = CopyVector(camera.target),
    }
end

local function IsDescendant(parts, candidateId, ancestorId)
    local current = parts[candidateId]
    local visited = {}
    while current and current.parentId do
        if visited[current.id] then
            return true
        end
        visited[current.id] = true
        if current.parentId == ancestorId then
            return true
        end
        current = parts[current.parentId]
    end
    return false
end

function LevelDocument.New(path)
    local self = setmetatable({}, LevelDocument)
    self.path = path or "levels/default-level.json"
    self.name = "默认关卡"
    self.fixedCamera = CopyCamera()
    self.parts = {}
    self.partOrder = {}
    self.dirty = false
    return self
end

function LevelDocument:AddPart(part)
    if getmetatable(part) ~= PartDefinition then
        part = PartDefinition.New(part)
    end
    if self.parts[part.id] then
        return false, "duplicate Part id: " .. part.id
    end
    self.parts[part.id] = part
    self.partOrder[#self.partOrder + 1] = part.id
    self.dirty = true
    return true, part
end

function LevelDocument:GetPart(id)
    return self.parts[id]
end

function LevelDocument:GetParts()
    local result = {}
    for _, id in ipairs(self.partOrder) do
        local part = self.parts[id]
        if part then
            result[#result + 1] = part
        end
    end
    return result
end

function LevelDocument:SetParent(childId, parentId)
    local child = self.parts[childId]
    if not child then
        return false, "child Part does not exist: " .. tostring(childId)
    end
    if parentId == childId then
        return false, "a Part cannot parent itself"
    end
    if parentId ~= nil and not self.parts[parentId] then
        return false, "parent Part does not exist: " .. tostring(parentId)
    end
    if parentId and IsDescendant(self.parts, parentId, childId) then
        return false, "cannot create a parent cycle"
    end
    child:SetParentId(parentId)
    self.dirty = true
    return true
end

function LevelDocument:IsDescendant(candidateId, ancestorId)
    return IsDescendant(self.parts, candidateId, ancestorId)
end

function LevelDocument:GetChildren(parentId)
    local result = {}
    for _, part in ipairs(self:GetParts()) do
        if part.parentId == parentId then
            result[#result + 1] = part
        end
    end
    return result
end

function LevelDocument:GetTreeNodes()
    local function Build(parentId, visiting)
        local nodes = {}
        for _, part in ipairs(self:GetChildren(parentId)) do
            if not visiting[part.id] then
                local nextVisiting = {}
                for id, value in pairs(visiting) do
                    nextVisiting[id] = value
                end
                nextVisiting[part.id] = true
                nodes[#nodes + 1] = {
                    key = part.id,
                    id = part.id,
                    label = part.name,
                    secondary = #part.behaviorModes > 0 and table.concat(part.behaviorModes, " + ") or nil,
                    children = Build(part.id, nextVisiting),
                    data = part,
                }
            end
        end
        return nodes
    end
    return Build(nil, {})
end

function LevelDocument:RemovePart(id)
    if not self.parts[id] then
        return false, "Part does not exist: " .. tostring(id)
    end
    self.parts[id] = nil
    for index, partId in ipairs(self.partOrder) do
        if partId == id then
            table.remove(self.partOrder, index)
            break
        end
    end
    for _, part in pairs(self.parts) do
        if part.parentId == id then
            part.parentId = nil
        end
    end
    self.dirty = true
    return true
end

function LevelDocument:ToTable()
    local parts = {}
    for _, part in ipairs(self:GetParts()) do
        parts[#parts + 1] = part:ToTable()
    end
    return {
        format = FORMAT,
        version = FORMAT_VERSION,
        name = self.name,
        fixedCamera = CopyCamera(self.fixedCamera),
        parts = parts,
    }
end

function LevelDocument:LoadTable(data)
    if type(data) ~= "table" or type(data.parts) ~= "table" then
        return false, "invalid level document"
    end
    if data.format and data.format ~= FORMAT then
        return false, "unsupported level format"
    end

    self.name = data.name or "未命名关卡"
    self.fixedCamera = CopyCamera(data.fixedCamera)
    self.parts = {}
    self.partOrder = {}

    for _, item in ipairs(data.parts) do
        local part, errorMessage = PartDefinition.FromTable(item)
        if not part then
            return false, errorMessage
        end
        local added, addError = self:AddPart(part)
        if not added then
            return false, addError
        end
    end
    self.dirty = false
    return true
end

function LevelDocument:Save(path)
    path = path or self.path
    local directory = path:match("^(.*)/[^/]+$")
    if directory and directory ~= "" then
        fileSystem:CreateDir(directory)
    end

    local file = File(path, FILE_WRITE)
    if not file:IsOpen() then
        return false, "cannot open level save file"
    end
    local json = cjson.encode(self:ToTable())
    json = json:gsub('"behaviorModes":%{%}', '"behaviorModes":[]')
    file:WriteLine(json)
    file:Close()
    self.path = path
    self.dirty = false
    return true
end

function LevelDocument:Load(path)
    path = path or self.path
    if not fileSystem:FileExists(path) then
        return false, "level file does not exist"
    end

    local file = File(path, FILE_READ)
    if not file:IsOpen() then
        return false, "cannot open level file"
    end
    local text = file:ReadString()
    file:Close()

    local ok, data = pcall(cjson.decode, text)
    if not ok then
        return false, "invalid level JSON"
    end
    local loaded, errorMessage = self:LoadTable(data)
    if loaded then
        self.path = path
    end
    return loaded, errorMessage
end

return LevelDocument
