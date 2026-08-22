-- 运行时路径节点索引与候选解析。
-- PathNode 仍由各 Part 的 VoxelDocument 持有；本模块只保存运行时索引和诊断。
-- 当前版本为不稳定原型：局部连接暂用锚点距离 + 法向启发式。
-- 后续必须替换为 TriPrismGrid 的 Cell/Face 离散邻接语义。

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
    local localEntry = record.node:GetLocalDirection(grid, record.node.entryDirection)
    local localExit = record.node:GetLocalDirection(grid, record.node.exitDirection)
    local worldEntry = localEntry and partRenderer:GetPartWorldNormal(record.partId, localEntry) or nil
    local worldExit = localExit and partRenderer:GetPartWorldNormal(record.partId, localExit) or nil
    if not worldPoint or not worldNormal or not worldEntry or not worldExit then
        return nil, "missing-world-anchor"
    end
    local result = {
        worldPoint = worldPoint,
        worldNormal = worldNormal,
        worldEntry = worldEntry:Normalized(),
        worldExit = worldExit:Normalized(),
    }
    return result
end

local function GetLocalFixedNeighbors(partRecord, allRecords, grid)
    local neighbors = {}
    local sourcePosition, sourceNormal = partRecord.node:GetLocalAnchor(grid, 0.035)
    for _, target in ipairs(allRecords) do
        if target.key ~= partRecord.key and target.node.walkable then
            local targetLocal, targetNormal = target.node:GetLocalAnchor(grid, 0.035)
            if targetLocal and targetNormal and sourcePosition and sourceNormal then
                local delta = targetLocal - sourcePosition
                local distance = delta:Length()
                local normalAlignment = sourceNormal:DotProduct(targetNormal)
                if distance <= grid.edgeLength * 1.45 and normalAlignment >= 0.5 then
                    neighbors[#neighbors + 1] = {
                        key = target.key,
                        distance = distance,
                    }
                end
            end
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

    local fromScreen = camera:WorldToScreenPoint(fromData.worldPoint)
    local toScreen = camera:WorldToScreenPoint(toData.worldPoint)
    local fromView = cameraNode:WorldToLocal(fromData.worldPoint)
    local toView = cameraNode:WorldToLocal(toData.worldPoint)
    local screenDeltaX = toScreen.x - fromScreen.x
    local screenDeltaY = toScreen.y - fromScreen.y
    local screenErrorSquared = screenDeltaX * screenDeltaX + screenDeltaY * screenDeltaY
    local depthDelta = math.abs(toView.z - fromView.z)
    local screenTolerance = options.screenTolerance or 72.0
    local maxDepthDelta = options.maxDepthDelta or 2.5

    local result = {
        fromWorldPoint = fromData.worldPoint,
        toWorldPoint = toData.worldPoint,
        fromWorldNormal = fromData.worldNormal,
        toWorldNormal = toData.worldNormal,
        fromWorldEntry = fromData.worldEntry,
        fromWorldExit = fromData.worldExit,
        toWorldEntry = toData.worldEntry,
        toWorldExit = toData.worldExit,
        fromScreenPoint = fromScreen,
        toScreenPoint = toScreen,
        fromViewPoint = fromView,
        toViewPoint = toView,
        screenErrorSquared = screenErrorSquared,
        depthDelta = depthDelta,
    }
    if screenErrorSquared > screenTolerance * screenTolerance then
        result.reason = "screen-misaligned"
        return false, result.reason, result
    end
    if depthDelta > maxDepthDelta then
        result.reason = "depth-discontinuous"
        return false, result.reason, result
    end
    local directionAlignment = math.abs(result.fromWorldExit:DotProduct(result.toWorldEntry))
    result.directionAlignment = directionAlignment
    local minDirectionAlignment = options.minDirectionAlignment or 0.25
    if directionAlignment < minDirectionAlignment then
        result.reason = "direction-incompatible"
        return false, result.reason, result
    end
    result.reason = "screen-aligned"
    return true, result.reason, result
end

function PathRuntime.New(levelDocument, grid)
    local self = setmetatable({}, PathRuntime)
    self.levelDocument = levelDocument
    self.grid = grid
    self.partRenderer = nil
    self.cameraNode = nil
    self.camera = nil
    self.evaluationOptions = {
        screenTolerance = 72.0,
        maxDepthDelta = 2.5,
        minDirectionAlignment = 0.25,
    }
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
