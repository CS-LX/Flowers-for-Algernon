-- 运行时路径节点索引与候选解析。
-- PathNode 仍由各 Part 的 VoxelDocument 持有；本模块只保存运行时索引和诊断。
-- 本阶段不生成有效边，不执行视觉评估，也不执行寻路。

local PartEditSession = require "PartEditSession"

local PathRuntime = {}
PathRuntime.__index = PathRuntime

local function NodeKey(partId, nodeId)
    return tostring(partId) .. ":" .. tostring(nodeId)
end

local function AddDiagnostic(list, candidateId, status, reason)
    list[#list + 1] = {
        candidateId = candidateId,
        status = status,
        reason = reason,
    }
end

function PathRuntime.New(levelDocument, grid)
    local self = setmetatable({}, PathRuntime)
    self.levelDocument = levelDocument
    self.grid = grid
    self.partSessions = {}
    self.nodesByKey = {}
    self.nodesByPart = {}
    self.candidateRecords = {}
    self.diagnostics = {}
    self.topologyVersion = 0
    return self
end

function PathRuntime:Clear()
    self.partSessions = {}
    self.nodesByKey = {}
    self.nodesByPart = {}
    self.candidateRecords = {}
    self.diagnostics = {}
end

function PathRuntime:LoadPartNodes(part)
    local session, errorMessage = PartEditSession.Open(self.grid, part)
    if not session then
        AddDiagnostic(
            self.diagnostics,
            nil,
            "unresolved",
            "无法加载 Part " .. part.id .. " 的局部体素文档：" .. tostring(errorMessage)
        )
        return false
    end

    self.partSessions[part.id] = session
    self.nodesByPart[part.id] = {}
    for _, node in ipairs(session.document:GetPathNodes()) do
        local key = NodeKey(part.id, node.id)
        if self.nodesByKey[key] then
            AddDiagnostic(self.diagnostics, nil, "duplicate", "重复的运行时节点键：" .. key)
        else
            local record = {
                key = key,
                partId = part.id,
                localNodeId = node.id,
                node = node,
                part = part,
                document = session.document,
            }
            self.nodesByKey[key] = record
            self.nodesByPart[part.id][#self.nodesByPart[part.id] + 1] = record
        end
    end
    return true
end

function PathRuntime:ResolveCandidates()
    for _, candidate in ipairs(self.levelDocument:GetPathCandidates()) do
        local record = {
            id = candidate.id,
            candidate = candidate,
            fromKey = candidate:GetEndpointKey("from"),
            toKey = candidate:GetEndpointKey("to"),
            from = nil,
            to = nil,
            status = "pending",
            reason = "等待视觉评估",
        }
        if not candidate.enabled then
            record.status = "disabled"
            record.reason = "设计者已禁用候选"
        else
            record.from = self.nodesByKey[record.fromKey]
            record.to = self.nodesByKey[record.toKey]
            if not record.from then
                record.status = "unresolved"
                record.reason = "找不到 from 局部 PathNode：" .. record.fromKey
            elseif not record.to then
                record.status = "unresolved"
                record.reason = "找不到 to 局部 PathNode：" .. record.toKey
            end
        end
        self.candidateRecords[#self.candidateRecords + 1] = record
        if record.status ~= "pending" then
            AddDiagnostic(self.diagnostics, record.id, record.status, record.reason)
        end
    end
end

function PathRuntime:Rebuild()
    self:Clear()
    for _, part in ipairs(self.levelDocument:GetParts()) do
        self:LoadPartNodes(part)
    end
    self:ResolveCandidates()
    return true
end

function PathRuntime:GetNode(key)
    return self.nodesByKey[key]
end

function PathRuntime:GetNodes()
    local result = {}
    for _, part in ipairs(self.levelDocument:GetParts()) do
        for _, record in ipairs(self.nodesByPart[part.id] or {}) do
            result[#result + 1] = record
        end
    end
    return result
end

function PathRuntime:GetCandidateRecords()
    local result = {}
    for _, record in ipairs(self.candidateRecords) do
        result[#result + 1] = record
    end
    return result
end

function PathRuntime:GetDiagnostics()
    local result = {}
    for _, diagnostic in ipairs(self.diagnostics) do
        result[#result + 1] = diagnostic
    end
    return result
end

function PathRuntime:GetTopologyVersion()
    return self.topologyVersion
end

function PathRuntime:GetSummary()
    local pending = 0
    local disabled = 0
    local unresolved = 0
    for _, record in ipairs(self.candidateRecords) do
        if record.status == "pending" then
            pending = pending + 1
        elseif record.status == "disabled" then
            disabled = disabled + 1
        elseif record.status == "unresolved" then
            unresolved = unresolved + 1
        end
    end
    return {
        nodeCount = #self:GetNodes(),
        candidateCount = #self.candidateRecords,
        pendingCount = pending,
        disabledCount = disabled,
        unresolvedCount = unresolved,
        topologyVersion = self.topologyVersion,
    }
end

return PathRuntime
