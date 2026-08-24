-- 运行时路径节点索引与候选解析。
-- PathNode 仍由各 Part 的 VoxelDocument 持有；本模块只保存运行时索引和诊断。
-- 当前版本为不稳定原型：局部连接暂用锚点距离 + 法向启发式。
-- 下一版规则已记录在 docs/tri-prism-face-adjacency-spec.md，
-- 必须按面顶点、法线、共面和正长度边重合替换本函数。

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

local function GetWorldNodeData(record, grid, partRenderer)
    local localPoint, localNormal = record.node:GetLocalAnchor(grid, 0.035)
    if not localPoint or not localNormal then
        return nil, "missing-local-anchor"
    end
    local worldPoint = partRenderer:GetPartWorldPoint(record.partId, localPoint)
    local worldNormal = partRenderer:GetPartWorldNormal(record.partId, localNormal)
    if not worldPoint or not worldNormal then
        return nil, "missing-world-anchor"
    end
    local result = {
        worldPoint = worldPoint,
        worldNormal = worldNormal,
    }
    return result
end

local FACE_TOLERANCE = 0.0001

local function GetNodeFace(record, grid)
    local faces = grid:GetCellFaces(record.node.voxelCell)
    return faces[record.node:GetFaceIndex()]
end

local function IsSamePlane(faceA, faceB, tolerance)
    local normalA = faceA.normal:Normalized()
    local normalB = faceB.normal:Normalized()
    if normalA:DotProduct(normalB) < 1.0 - tolerance then
        return false
    end
    local origin = faceA.vertices[1]
    for _, vertex in ipairs(faceB.vertices) do
        if math.abs((vertex - origin):DotProduct(normalA)) > tolerance then
            return false
        end
    end
    return true
end

local function IsVerticalEdge(first, second, tolerance)
    return math.abs(first.x - second.x) <= tolerance
        and math.abs(first.z - second.z) <= tolerance
        and math.abs(first.y - second.y) > tolerance
end

local function GetFaceEdges(face, faceName, tolerance)
    local edges = {}
    for index = 1, #face.vertices do
        local nextIndex = index % #face.vertices + 1
        local first = face.vertices[index]
        local second = face.vertices[nextIndex]
        if faceName == "top" or faceName == "bottom"
            or IsVerticalEdge(first, second, tolerance) then
            edges[#edges + 1] = { first = first, second = second }
        end
    end
    return edges
end

local function HasPositiveEdgeOverlap(edgeA, edgeB, tolerance)
    local direction = edgeA.second - edgeA.first
    local length = direction:Length()
    if length <= tolerance then
        return false
    end
    local normalized = direction / length
    local otherDirection = edgeB.second - edgeB.first
    if normalized:CrossProduct(otherDirection):Length() > tolerance * length then
        return false
    end
    if (edgeB.first - edgeA.first):CrossProduct(normalized):Length() > tolerance then
        return false
    end
    local firstProjection = 0.0
    local secondProjection = length
    local otherFirst = (edgeB.first - edgeA.first):DotProduct(normalized)
    local otherSecond = (edgeB.second - edgeA.first):DotProduct(normalized)
    local overlap = math.min(secondProjection, math.max(otherFirst, otherSecond))
        - math.max(firstProjection, math.min(otherFirst, otherSecond))
    return overlap > tolerance
end

local function IsFaceAdjacent(source, target, grid)
    local sourceFace = GetNodeFace(source, grid)
    local targetFace = GetNodeFace(target, grid)
    if not sourceFace or not targetFace then
        return false
    end
    local sourceName = source.node.face
    local targetName = target.node.face
    if sourceName == "bottom" or targetName == "bottom" then
        return false
    end
    local sourceTopBottom = sourceName == "top"
    local targetTopBottom = targetName == "top"
    if sourceTopBottom ~= targetTopBottom then
        return false
    end
    if sourceTopBottom and sourceName ~= targetName then
        return false
    end
    if not IsSamePlane(sourceFace, targetFace, FACE_TOLERANCE) then
        return false
    end
    local sourceEdges = GetFaceEdges(sourceFace, sourceName, FACE_TOLERANCE)
    local targetEdges = GetFaceEdges(targetFace, targetName, FACE_TOLERANCE)
    for _, sourceEdge in ipairs(sourceEdges) do
        for _, targetEdge in ipairs(targetEdges) do
            if HasPositiveEdgeOverlap(sourceEdge, targetEdge, FACE_TOLERANCE) then
                return true
            end
        end
    end
    return false
end

local function HasCompatibleLocalDirection(source, target, grid)
    local sourcePoint = source.node:GetLocalAnchor(grid, 0.0)
    local targetPoint = target.node:GetLocalAnchor(grid, 0.0)
    local delta = targetPoint and sourcePoint and targetPoint - sourcePoint or nil
    return delta ~= nil and delta:Length() > FACE_TOLERANCE
end

local function GetLocalFixedNeighbors(partRecord, allRecords, grid)
    local neighbors = {}
    for _, target in ipairs(allRecords) do
        if target.key ~= partRecord.key and target.node.walkable
            and IsFaceAdjacent(partRecord, target, grid)
            and HasCompatibleLocalDirection(partRecord, target, grid) then
            neighbors[#neighbors + 1] = {
                key = target.key,
                kind = "local_fixed",
            }
        end
    end
    table.sort(neighbors, function(left, right)
        return left.key < right.key
    end)
    return neighbors
end

local function SortNeighbors(neighbors)
    table.sort(neighbors, function(left, right)
        if left.key ~= right.key then
            return left.key < right.key
        end
        return tostring(left.candidateId) < tostring(right.candidateId)
    end)
end

local function TransformEdge(partRenderer, partId, edge)
    return {
        first = partRenderer:GetPartWorldPoint(partId, edge.first),
        second = partRenderer:GetPartWorldPoint(partId, edge.second),
    }
end

local function ProjectEdge(camera, edge)
    return {
        first = camera:WorldToScreenPoint(edge.first),
        second = camera:WorldToScreenPoint(edge.second),
    }
end

local function ProjectedEdgesHavePositiveOverlap(edgeA, edgeB, tolerance)
    local vectorA = edgeA.second - edgeA.first
    local vectorB = edgeB.second - edgeB.first
    local lengthA = vectorA:Length()
    local lengthB = vectorB:Length()
    if lengthA <= tolerance or lengthB <= tolerance then return false, 0.0 end
    local directionA = vectorA / lengthA
    local directionB = vectorB / lengthB
    if math.abs(directionA.x * directionB.x + directionA.y * directionB.y) < 1.0 - tolerance then
        return false, 0.0
    end
    local offset = edgeB.first - edgeA.first
    if math.abs(offset.x * directionA.y - offset.y * directionA.x) > tolerance then return false, 0.0 end
    local first = offset.x * directionA.x + offset.y * directionA.y
    local secondOffset = edgeB.second - edgeA.first
    local second = secondOffset.x * directionA.x + secondOffset.y * directionA.y
    local overlap = math.min(lengthA, math.max(first, second)) - math.max(0.0, math.min(first, second))
    return overlap > tolerance, math.max(0.0, overlap)
end
local function TransformEdges(partRenderer, partId, edges)
    local result = {}
    for _, edge in ipairs(edges) do
        result[#result + 1] = TransformEdge(partRenderer, partId, edge)
    end
    return result
end

local function ProjectEdges(camera, edges)
    local result = {}
    for _, edge in ipairs(edges) do
        result[#result + 1] = ProjectEdge(camera, edge)
    end
    return result
end

local function FindPositiveOverlapPair(edgesA, edgesB, tolerance)
    for indexA, edgeA in ipairs(edgesA) do
        for indexB, edgeB in ipairs(edgesB) do
            local overlaps, length = ProjectedEdgesHavePositiveOverlap(edgeA, edgeB, tolerance)
            if overlaps then
                return true, length, indexA, indexB
            end
        end
    end
    return false, 0.0, nil, nil
end

local function EvaluateCandidate(record, grid, partRenderer, cameraNode, camera, options)
    if not record.from or not record.to then
        return false, "unresolved"
    end
    if not record.from.node.walkable or not record.to.node.walkable then
        return false, "endpoint-not-walkable"
    end

    local fromData, fromError = GetWorldNodeData(record.from, grid, partRenderer)
    if not fromData then
        return false, fromError
    end
    local toData, toError = GetWorldNodeData(record.to, grid, partRenderer)
    if not toData then
        return false, toError
    end

    local fromLocalEdges = record.from.node:GetLocalFaceEdges(grid)
    local toLocalEdges = record.to.node:GetLocalFaceEdges(grid)
    if not fromLocalEdges or not toLocalEdges then
        return false, "missing-face-edges"
    end
    local fromProjectedEdges = ProjectEdges(camera, TransformEdges(
        partRenderer, record.from.partId, fromLocalEdges
    ))
    local toProjectedEdges = ProjectEdges(camera, TransformEdges(
        partRenderer, record.to.partId, toLocalEdges
    ))
    local edgeAccepted, edgeOverlap, fromEdgeIndex, toEdgeIndex = FindPositiveOverlapPair(
        fromProjectedEdges,
        toProjectedEdges,
        FACE_TOLERANCE
    )
    local result = {
        fromWorldPoint = fromData.worldPoint,
        toWorldPoint = toData.worldPoint,
        fromWorldNormal = fromData.worldNormal,
        toWorldNormal = toData.worldNormal,
        fromProjectedEdges = fromProjectedEdges,
        toProjectedEdges = toProjectedEdges,
        matchedFromEdgeIndex = fromEdgeIndex,
        matchedToEdgeIndex = toEdgeIndex,
        projectedEdgeOverlap = edgeOverlap,
    }
    if not edgeAccepted then
        result.reason = "projected-face-edge-does-not-overlap"
        return false, result.reason, result
    end
    result.reason = "projected-face-edge-overlap"
    return true, result.reason, result
end

function PathRuntime.New(levelDocument, grid)
    local self = setmetatable({}, PathRuntime)
    self.levelDocument = levelDocument
    self.grid = grid
    self.partRenderer = nil
    self.cameraNode = nil
    self.camera = nil
    self.evaluationOptions = {}
    self.partSessions = {}
    self.nodesByKey = {}
    self.nodesByPart = {}
    self.candidateRecords = {}
    self.diagnostics = {}
    self.adjacency = {}
    self.effectiveEdges = {}
    self.topologyVersion = 0
    return self
end

function PathRuntime:Clear()
    self.partSessions = {}
    self.nodesByKey = {}
    self.nodesByPart = {}
    self.candidateRecords = {}
    self.diagnostics = {}
    self.adjacency = {}
    self.effectiveEdges = {}
end

function PathRuntime:LoadPartNodes(part)
    print("PathRuntime loading Part: " .. part.id .. " path=" .. tostring(part.localVoxelPath))
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
    local loadedNodeIds = {}
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
            loadedNodeIds[#loadedNodeIds + 1] = node.id
        end
    end
    print("PathRuntime Part nodes: " .. part.id .. " count=" .. tostring(#loadedNodeIds) .. " ids=" .. (#loadedNodeIds > 0 and table.concat(loadedNodeIds, ",") or "<none>"))
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

function PathRuntime:ConfigureEvaluation(partRenderer, cameraNode, camera, options)
    self.partRenderer = partRenderer
    self.cameraNode = cameraNode
    self.camera = camera
    for key, value in pairs(options or {}) do
        self.evaluationOptions[key] = value
    end
end

function PathRuntime:EvaluateCandidates()
    if not self.partRenderer or not self.cameraNode or not self.camera then
        return false, "visual evaluation requires renderer and fixed camera"
    end
    self:UpdateNodeSpatialData()
    for _, record in ipairs(self.candidateRecords) do
        if record.status == "pending" then
            local accepted, reason, result = EvaluateCandidate(
                record,
                self.grid,
                self.partRenderer,
                self.cameraNode,
                self.camera,
                self.evaluationOptions
            )
            record.status = accepted and "accepted" or "rejected"
            record.reason = reason
            record.evaluation = result
            AddDiagnostic(self.diagnostics, record.id, record.status, reason)
        end
    end
    return true
end

function PathRuntime:AddDirectedEdge(adjacency, fromKey, toKey, candidateId)
    local neighbors = adjacency[fromKey]
    if not neighbors then
        neighbors = {}
        adjacency[fromKey] = neighbors
    end
    neighbors[#neighbors + 1] = {
        key = toKey,
        candidateId = candidateId,
    }
end

function PathRuntime:UpdateNodeSpatialData()
    if not self.partRenderer then
        return false, "node spatial data requires PartRootRenderer"
    end
    for _, record in pairs(self.nodesByKey) do
        local data, errorMessage = GetWorldNodeData(record, self.grid, self.partRenderer)
        if data then
            record.worldPoint = data.worldPoint
            record.worldNormal = data.worldNormal
            record.worldEntry = data.worldEntry
            record.worldExit = data.worldExit
        else
            AddDiagnostic(self.diagnostics, record.key, "unresolved", errorMessage)
        end
    end
    return true
end

function PathRuntime:BuildEffectiveGraph()
    local adjacency = {}
    local edges = {}
    for _, record in ipairs(self.candidateRecords) do
        if record.status == "accepted" then
            local fromKey = record.fromKey
            local toKey = record.toKey
            if record.candidate.direction == "bidirectional"
                or record.candidate.direction == "from_to" then
                self:AddDirectedEdge(adjacency, fromKey, toKey, record.id)
                edges[#edges + 1] = { id = record.id .. ":from_to", candidateId = record.id, from = fromKey, to = toKey }
            end
            if record.candidate.direction == "bidirectional"
                or record.candidate.direction == "to_from" then
                self:AddDirectedEdge(adjacency, toKey, fromKey, record.id)
                edges[#edges + 1] = { id = record.id .. ":to_from", candidateId = record.id, from = toKey, to = fromKey }
            end
        end
    end
    for _, part in ipairs(self.levelDocument:GetParts()) do
        local records = self.nodesByPart[part.id] or {}
        for _, source in ipairs(records) do
            for _, neighbor in ipairs(GetLocalFixedNeighbors(source, records, self.grid)) do
                self:AddDirectedEdge(adjacency, source.key, neighbor.key, "local_fixed")
                edges[#edges + 1] = {
                    id = source.key .. ":local:" .. neighbor.key,
                    candidateId = nil,
                    from = source.key,
                    to = neighbor.key,
                    kind = "local_fixed",
                }
            end
        end
    end
    for _, neighbors in pairs(adjacency) do
        SortNeighbors(neighbors)
    end
    self.adjacency = adjacency
    self.effectiveEdges = edges
    self.topologyVersion = self.topologyVersion + 1
end

function PathRuntime:FindPath(startKey, goalKey)
    if not self.nodesByKey[startKey] or not self.nodesByKey[goalKey] then
        return nil, "node-not-found"
    end
    if startKey == goalKey then
        return { startKey }
    end
    local queue = { startKey }
    local head = 1
    local visited = { [startKey] = true }
    local previous = {}
    while head <= #queue do
        local current = queue[head]
        head = head + 1
        for _, edge in ipairs(self.adjacency[current] or {}) do
            if not visited[edge.key] then
                visited[edge.key] = true
                previous[edge.key] = current
                if edge.key == goalKey then
                    local path = { goalKey }
                    local cursor = goalKey
                    while previous[cursor] do
                        cursor = previous[cursor]
                        table.insert(path, 1, cursor)
                    end
                    return path
                end
                queue[#queue + 1] = edge.key
            end
        end
    end
    return nil, "unreachable"
end

function PathRuntime:IsReachable(startKey, goalKey)
    local path = self:FindPath(startKey, goalKey)
    return path ~= nil
end

function PathRuntime:GetEffectiveEdges()
    local result = {}
    for _, edge in ipairs(self.effectiveEdges) do
        result[#result + 1] = edge
    end
    return result
end

function PathRuntime:GetLocalFixedEdgeCount()
    local count = 0
    for _, edge in ipairs(self.effectiveEdges) do
        if edge.kind == "local_fixed" then
            count = count + 1
        end
    end
    return count
end

function PathRuntime:GetNeighbors(key)
    local result = {}
    for _, edge in ipairs(self.adjacency[key] or {}) do
        result[#result + 1] = edge
    end
    return result
end

function PathRuntime:Rebuild()
    self:Clear()
    for _, part in ipairs(self.levelDocument:GetParts()) do
        self:LoadPartNodes(part)
    end
    self:ResolveCandidates()
    if self.partRenderer and self.cameraNode and self.camera then
        self:EvaluateCandidates()
    end
    self:BuildEffectiveGraph()
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
    local accepted = 0
    local rejected = 0
    local disabled = 0
    local unresolved = 0
    for _, record in ipairs(self.candidateRecords) do
        if record.status == "pending" then
            pending = pending + 1
        elseif record.status == "accepted" then
            accepted = accepted + 1
        elseif record.status == "rejected" then
            rejected = rejected + 1
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
        acceptedCount = accepted,
        rejectedCount = rejected,
        effectiveEdgeCount = #self.effectiveEdges,
        disabledCount = disabled,
        unresolvedCount = unresolved,
        topologyVersion = self.topologyVersion,
    }
end

return PathRuntime
