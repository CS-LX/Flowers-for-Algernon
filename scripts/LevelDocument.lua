-- 关卡级 JSON 文档。
-- 管理 Part、StillObject、固定相机和保存路径；不持有局部体素、Scene Node 或 Bake 缓存。

local PartDefinition = require "PartDefinition"
local StillObject = require "StillObject"
local PathConnectionCandidate = require "PathConnectionCandidate"
local PartEditSession = require "PartEditSession"
local LookApplier = require "LookApplier"

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
        pitch = camera.pitch or 30,
        orthoSize = camera.orthoSize or 10.0,
        nearClip = camera.nearClip or 0.1,
        farClip = camera.farClip or 100.0,
        target = CopyVector(camera.target),
    }
end

local function GetParentLookup(self)
    local lookup = {}
    for _, part in pairs(self.parts) do
        lookup[part.id] = part
    end
    for _, object in pairs(self.stillObjects) do
        lookup[object.id] = object
    end
    return lookup
end

local function IsDescendant(self, candidateId, ancestorId)
    local lookup = GetParentLookup(self)
    local current = lookup[candidateId]
    local vis = {}
    while current and current.parentId do
        if vis[current.id] then
            return true
        end
        vis[current.id] = true
        if current.parentId == ancestorId then
            return true
        end
        current = lookup[current.parentId]
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
    self.stillObjects = {}
    self.stillObjectOrder = {}
    self.pathCandidates = {}
    self.pathCandidateOrder = {}
    self.spawnNodeKey = nil
    self.atmosphere = LookApplier.CopyAtmosphere()
    self.dirty = false
    return self
end

function LevelDocument:AddPart(part)
    if getmetatable(part) ~= PartDefinition then
        part = PartDefinition.New(part)
    end
    if self:HasId(part.id) then
        return false, "duplicate object id: " .. part.id
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

function LevelDocument:HasId(id)
    return self.parts[id] ~= nil or self.stillObjects[id] ~= nil
end

function LevelDocument:AddStillObject(object)
    if getmetatable(object) ~= StillObject then
        object = StillObject.New(object)
    end
    if self:HasId(object.id) then
        return false, "duplicate object id: " .. object.id
    end
    self.stillObjects[object.id] = object
    self.stillObjectOrder[#self.stillObjectOrder + 1] = object.id
    self.dirty = true
    return true, object
end

function LevelDocument:GetStillObject(id)
    return self.stillObjects[id]
end

function LevelDocument:GetStillObjects()
    local result = {}
    for _, id in ipairs(self.stillObjectOrder) do
        local object = self.stillObjects[id]
        if object then
            result[#result + 1] = object
        end
    end
    return result
end

function LevelDocument:GetObject(id)
    return self.parts[id] or self.stillObjects[id]
end

function LevelDocument:GetObjectKind(id)
    if self.parts[id] then
        return "part"
    end
    if self.stillObjects[id] then
        return "stillObject"
    end
    return nil
end

function LevelDocument:GetPathCandidate(id)
    return self.pathCandidates[id]
end

function LevelDocument:GetPathCandidates()
    local result = {}
    for _, id in ipairs(self.pathCandidateOrder) do
        local candidate = self.pathCandidates[id]
        if candidate then
            result[#result + 1] = candidate
        end
    end
    return result
end

function LevelDocument:HasPathCandidate(id)
    return self.pathCandidates[id] ~= nil
end

function LevelDocument:AddPathCandidate(candidate)
    if getmetatable(candidate) ~= PathConnectionCandidate then
        local normalized, errorMessage = PathConnectionCandidate.New(candidate)
        if not normalized then
            return false, errorMessage
        end
        candidate = normalized
    end
    if type(candidate.id) ~= "string" or candidate.id == "" then
        return false, "path candidate id is required"
    end
    if not PathConnectionCandidate.IsValidReference(candidate.from)
        or not PathConnectionCandidate.IsValidReference(candidate.to) then
        return false, "path candidate has invalid endpoint"
    end
    if self.pathCandidates[candidate.id] then
        return false, "duplicate path candidate id: " .. candidate.id
    end
    if not self.parts[candidate.from.partId] then
        return false, "candidate from Part does not exist: " .. candidate.from.partId
    end
    if not self.parts[candidate.to.partId] then
        return false, "candidate to Part does not exist: " .. candidate.to.partId
    end
    self.pathCandidates[candidate.id] = candidate
    self.pathCandidateOrder[#self.pathCandidateOrder + 1] = candidate.id
    self.dirty = true
    return true, candidate
end

function LevelDocument:RemovePathCandidate(id)
    if not self.pathCandidates[id] then
        return false, "path candidate does not exist: " .. tostring(id)
    end
    self.pathCandidates[id] = nil
    for index, candidateId in ipairs(self.pathCandidateOrder) do
        if candidateId == id then
            table.remove(self.pathCandidateOrder, index)
            break
        end
    end
    self.dirty = true
    return true
end

function LevelDocument:RemovePathCandidatesForPart(partId)
    local removed = false
    for index = #self.pathCandidateOrder, 1, -1 do
        local candidateId = self.pathCandidateOrder[index]
        local candidate = self.pathCandidates[candidateId]
        if candidate
            and (candidate.from.partId == partId or candidate.to.partId == partId) then
            self.pathCandidates[candidateId] = nil
            table.remove(self.pathCandidateOrder, index)
            removed = true
        end
    end
    if removed then
        self.dirty = true
    end
    return removed
end

function LevelDocument:GetPathCandidatesByPart(partId)
    local result = {}
    for _, candidate in ipairs(self:GetPathCandidates()) do
        if candidate.from.partId == partId or candidate.to.partId == partId then
            result[#result + 1] = candidate
        end
    end
    return result
end

function LevelDocument:GetSpawnNodeKey()
    return self.spawnNodeKey
end

function LevelDocument:SetSpawnNodeKey(nodeKey)
    if nodeKey ~= nil and (type(nodeKey) ~= "string" or nodeKey == "") then
        return false, "出生点必须是有效的 PathNode key"
    end
    self.spawnNodeKey = nodeKey
    self.dirty = true
    return true
end

function LevelDocument:ClearSpawnNodeForPart(partId)
    if type(self.spawnNodeKey) ~= "string" then
        return false
    end
    local prefix = tostring(partId) .. ":"
    if self.spawnNodeKey:sub(1, #prefix) ~= prefix then
        return false
    end
    self.spawnNodeKey = nil
    self.dirty = true
    return true
end

function LevelDocument:ClearSpawnNodeIf(nodeKey)
    if self.spawnNodeKey ~= nodeKey then
        return false
    end
    self.spawnNodeKey = nil
    self.dirty = true
    return true
end

function LevelDocument:SetParent(childId, parentId)
    local child = self:GetObject(childId)
    if not child then
        return false, "child object does not exist: " .. tostring(childId)
    end
    if parentId == childId then
        return false, "an object cannot parent itself"
    end
    if parentId ~= nil and not self:GetObject(parentId) then
        return false, "parent object does not exist: " .. tostring(parentId)
    end
    if self.parts[childId] and parentId and self.stillObjects[parentId] then
        return false, "Part cannot parent under StillObject"
    end
    if parentId and IsDescendant(self, parentId, childId) then
        return false, "cannot create a parent cycle"
    end
    child:SetParentId(parentId)
    self.dirty = true
    return true
end

function LevelDocument:IsDescendant(candidateId, ancestorId)
    return IsDescendant(self, candidateId, ancestorId)
end

function LevelDocument:GetChildren(parentId)
    local result = {}
    for _, part in ipairs(self:GetParts()) do
        if part.parentId == parentId then
            result[#result + 1] = part
        end
    end
    for _, object in ipairs(self:GetStillObjects()) do
        if object.parentId == parentId then
            result[#result + 1] = object
        end
    end
    return result
end

function LevelDocument:GetTreeNodes()
    local function Build(parentId, visiting)
        local nodes = {}
        for _, object in ipairs(self:GetChildren(parentId)) do
            if not visiting[object.id] then
                local nextVisiting = {}
                for id, value in pairs(visiting) do
                    nextVisiting[id] = value
                end
                nextVisiting[object.id] = true
                local secondary = nil
                if self.parts[object.id] then
                    if #object.behaviorModes > 0 then
                        secondary = table.concat(object.behaviorModes, " + ")
                    end
                else
                    secondary = "StillObject"
                end
                nodes[#nodes + 1] = {
                    key = object.id,
                    id = object.id,
                    label = object.name,
                    secondary = secondary,
                    children = Build(object.id, nextVisiting),
                    data = object,
                }
            end
        end
        return nodes
    end
    return Build(nil, {})
end

function LevelDocument:DetachChildren(parentId)
    for _, part in pairs(self.parts) do
        if part.parentId == parentId then
            part.parentId = nil
        end
    end
    for _, object in pairs(self.stillObjects) do
        if object.parentId == parentId then
            object.parentId = nil
        end
    end
end

function LevelDocument:RemovePart(id)
    if not self.parts[id] then
        return false, "Part does not exist: " .. tostring(id)
    end
    self:RemovePathCandidatesForPart(id)
    self:ClearSpawnNodeForPart(id)
    self.parts[id] = nil
    for index, partId in ipairs(self.partOrder) do
        if partId == id then
            table.remove(self.partOrder, index)
            break
        end
    end
    self:DetachChildren(id)
    self.dirty = true
    return true
end

function LevelDocument:RemoveStillObject(id)
    if not self.stillObjects[id] then
        return false, "StillObject does not exist: " .. tostring(id)
    end
    self.stillObjects[id] = nil
    for index, objectId in ipairs(self.stillObjectOrder) do
        if objectId == id then
            table.remove(self.stillObjectOrder, index)
            break
        end
    end
    self:DetachChildren(id)
    self.dirty = true
    return true
end

function LevelDocument:ToTable()
    local parts = {}
    for _, part in ipairs(self:GetParts()) do
        parts[#parts + 1] = part:ToTable()
    end
    local stillObjects = {}
    for _, object in ipairs(self:GetStillObjects()) do
        stillObjects[#stillObjects + 1] = object:ToTable()
    end
    local result = {
        format = FORMAT,
        version = FORMAT_VERSION,
        name = self.name,
        fixedCamera = CopyCamera(self.fixedCamera),
        parts = parts,
        stillObjects = stillObjects,
        spawnNodeKey = self.spawnNodeKey,
        atmosphere = LookApplier.CopyAtmosphere(self.atmosphere),
    }
    if #self.pathCandidateOrder > 0 then
        local candidates = {}
        for _, id in ipairs(self.pathCandidateOrder) do
            local candidate = self.pathCandidates[id]
            if candidate then
                candidates[#candidates + 1] = candidate:ToTable()
            end
        end
        result.pathCandidates = candidates
    end
    return result
end

local function EncodeLevelJson(data)
    local json = cjson.encode(data)
    json = json:gsub('"behaviorModes":%{%}', '"behaviorModes":[]')
    return json
end

-- 工作区存档继续拆成 Level + parts/*.json。
-- 导出给用户时把每个 Part 的体素文档内联进同一份 JSON。
function LevelDocument:ExportInlineTable(grid)
    if not grid then
        return nil, "inline export requires TriPrismGrid"
    end
    local data = self:ToTable()
    data.inlineParts = true
    for _, partData in ipairs(data.parts) do
        local part = self:GetPart(partData.id)
        if not part then
            return nil, "inline export missing Part: " .. tostring(partData.id)
        end
        local session, errorMessage = PartEditSession.Open(grid, part)
        if not session then
            return nil, "无法内联 Part " .. part.id .. "：" .. tostring(errorMessage)
        end
        partData.localVoxelDocument = session.document:ToTable()
    end
    return data
end

function LevelDocument:ExportInlineJson(grid)
    local data, errorMessage = self:ExportInlineTable(grid)
    if not data then
        return nil, errorMessage
    end
    return EncodeLevelJson(data)
end

local function DecodeLevelJson(json)
    if type(json) ~= "string" or json == "" then
        return nil, "level JSON is empty"
    end
    json = json:gsub("^\239\187\191", "")
    json = json:match("^%s*(.-)%s*$") or json
    local first = nil
    local last = nil
    for index = 1, #json do
        local byte = string.byte(json, index)
        if byte == 123 and not first then
            first = index
        elseif byte == 125 then
            last = index
        end
    end
    if first and last and last >= first then
        json = json:sub(first, last)
    end
    local ok, data = pcall(cjson.decode, json)
    if not ok then
        return nil, "invalid level JSON: " .. tostring(data)
    end
    if type(data) ~= "table" then
        return nil, "invalid level JSON"
    end
    return data
end

-- 把导出的单文件关卡拆回 Runtime 存档：levels/*.json + parts/*.json。
-- 先在临时文档上校验，成功后再覆盖当前 LevelDocument。
function LevelDocument:ImportInlineJson(json, grid)
    if not grid then
        return false, "inline import requires TriPrismGrid"
    end
    local data, decodeError = DecodeLevelJson(json)
    if not data then
        return false, decodeError
    end
    if type(data.parts) ~= "table" or #data.parts == 0 then
        return false, "imported level has no Parts"
    end

    local voxelSessions = {}
    for _, item in ipairs(data.parts) do
        if type(item) ~= "table" or type(item.id) ~= "string" or item.id == "" then
            return false, "imported Part is missing id"
        end
        local voxelData = item.localVoxelDocument
        if type(voxelData) ~= "table" then
            return false, "imported Part is missing inlined voxel document: " .. item.id
        end
        local path = item.localVoxelPath or ("parts/" .. item.id .. ".json")
        local session = PartEditSession.New(grid, {
            id = item.id,
            name = item.name or item.id,
            path = path,
        })
        local loaded, errorMessage = session.document:LoadTable(voxelData)
        if not loaded then
            return false, "无法导入 Part " .. item.id .. " 的体素文档：" .. tostring(errorMessage)
        end
        voxelSessions[item.id] = session
    end

    local imported = LevelDocument.New(self.path)
    local loaded, loadError = imported:LoadTable(data)
    if not loaded then
        return false, loadError
    end

    for _, part in ipairs(imported:GetParts()) do
        local session = voxelSessions[part.id]
        if not session then
            return false, "imported Part is missing voxel session: " .. part.id
        end
        session.path = part.localVoxelPath
        session.document.path = part.localVoxelPath
        local saved, saveError = session:Save()
        if not saved then
            return false, "无法写入 Part 体素存档 " .. part.id .. "：" .. tostring(saveError)
        end
    end

    local applied, applyError = self:LoadTable(imported:ToTable())
    if not applied then
        return false, applyError
    end
    self.path = imported.path
    return self:Save()
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
    self.stillObjects = {}
    self.stillObjectOrder = {}
    self.pathCandidates = {}
    self.pathCandidateOrder = {}
    self.spawnNodeKey = type(data.spawnNodeKey) == "string" and data.spawnNodeKey
        or (type(data["出生点"]) == "string" and data["出生点"] or nil)
    self.atmosphere = LookApplier.CopyAtmosphere(data.atmosphere)

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
    for _, item in ipairs(data.stillObjects or {}) do
        local object, errorMessage = StillObject.FromTable(item)
        if not object then
            return false, errorMessage
        end
        local added, addError = self:AddStillObject(object)
        if not added then
            return false, addError
        end
    end
    for _, item in ipairs(data.pathCandidates or {}) do
        local candidate, errorMessage = PathConnectionCandidate.FromTable(item)
        if not candidate then
            return false, errorMessage
        end
        local added, addError = self:AddPathCandidate(candidate)
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
    file:WriteLine(EncodeLevelJson(self:ToTable()))
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
