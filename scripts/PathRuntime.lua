-- 运行时路径节点索引与候选解析。
-- PathNode 仍由各 Part 的 VoxelDocument 持有；本模块只保存运行时索引和诊断。
-- 局部固定边：同向法线、共面、正长度边重合。
-- 跨 Part 视觉边：固定相机投影面边正长度重合，再检查重合接缝是否被更近逻辑面切断。

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
local OCCLUSION_DEPTH_EPSILON = 0.02
local FACE_COINCIDENCE_TOLERANCE = 0.02
local OCCLUSION_SAMPLE_TS = { 0.15, 0.5, 0.85 }

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

local function IsPointInsideFace(point, faceVertices, normal, tolerance)
    local hasPositive = false
    local hasNegative = false
    for index = 1, #faceVertices do
        local nextIndex = index % #faceVertices + 1
        local edge = faceVertices[nextIndex] - faceVertices[index]
        local offset = point - faceVertices[index]
        local side = edge:CrossProduct(offset):DotProduct(normal)
        if side > tolerance then
            hasPositive = true
        elseif side < -tolerance then
            hasNegative = true
        end
        if hasPositive and hasNegative then
            return false
        end
    end
    return true
end

local function GetWorldFace(record, grid, partRenderer)
    local faces = grid:GetCellFaces(record.node.voxelCell)
    local face = faces[record.node:GetFaceIndex()]
    if not face then
        return nil
    end
    local vertices = {}
    for _, vertex in ipairs(face.vertices) do
        vertices[#vertices + 1] = partRenderer:GetPartWorldPoint(record.partId, vertex)
    end
    local normal = partRenderer:GetPartWorldNormal(record.partId, face.normal):Normalized()
    return vertices, normal
end

local function VertexMatchesAny(point, vertices, tolerance)
    local tolSq = tolerance * tolerance
    for _, vertex in ipairs(vertices) do
        local dx = point.x - vertex.x
        local dy = point.y - vertex.y
        local dz = point.z - vertex.z
        if dx * dx + dy * dy + dz * dz <= tolSq then
            return true
        end
    end
    return false
end

-- 两端走面在世界空间完全重合（同为三角形或同为四边形，顶点集合一致）。
local function AreFacesCoincident(verticesA, verticesB, tolerance)
    if not verticesA or not verticesB then
        return false
    end
    if #verticesA ~= #verticesB or #verticesA < 3 then
        return false
    end
    for _, vertex in ipairs(verticesA) do
        if not VertexMatchesAny(vertex, verticesB, tolerance) then
            return false
        end
    end
    for _, vertex in ipairs(verticesB) do
        if not VertexMatchesAny(vertex, verticesA, tolerance) then
            return false
        end
    end
    return true
end

local function RayTriangle(rayOrigin, rayDirection, a, b, c)
    local edgeA = b - a
    local edgeB = c - a
    local cross = rayDirection:CrossProduct(edgeB)
    local determinant = edgeA:DotProduct(cross)
    if math.abs(determinant) <= FACE_TOLERANCE then
        return nil
    end
    local inverse = 1.0 / determinant
    local offset = rayOrigin - a
    local u = offset:DotProduct(cross) * inverse
    if u < -FACE_TOLERANCE or u > 1.0 + FACE_TOLERANCE then
        return nil
    end
    local crossOffset = offset:CrossProduct(edgeA)
    local v = rayDirection:DotProduct(crossOffset) * inverse
    if v < -FACE_TOLERANCE or u + v > 1.0 + FACE_TOLERANCE then
        return nil
    end
    local distance = edgeB:DotProduct(crossOffset) * inverse
    if distance < -FACE_TOLERANCE then
        return nil
    end
    return math.max(0.0, distance)
end

local function RayFace(ray, vertices)
    local nearest = RayTriangle(ray.origin, ray.direction, vertices[1], vertices[2], vertices[3])
    if vertices[4] then
        local second = RayTriangle(ray.origin, ray.direction, vertices[1], vertices[3], vertices[4])
        if second and (not nearest or second < nearest) then
            nearest = second
        end
    end
    return nearest
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

local function ProjectScalar(origin, direction, point)
    return (point.x - origin.x) * direction.x + (point.y - origin.y) * direction.y
end

local function ScreenPointOnEdge(edge, scalar)
    local vector = edge.second - edge.first
    local length = vector:Length()
    if length <= FACE_TOLERANCE then
        return Vector2(edge.first.x, edge.first.y)
    end
    local t = scalar / length
    return Vector2(
        edge.first.x + vector.x * t,
        edge.first.y + vector.y * t
    )
end

local function GetProjectedOverlapSegment(edgeA, edgeB, tolerance)
    local vectorA = edgeA.second - edgeA.first
    local lengthA = vectorA:Length()
    if lengthA <= tolerance then
        return nil
    end
    local directionA = vectorA / lengthA
    local first = ProjectScalar(edgeA.first, directionA, edgeB.first)
    local second = ProjectScalar(edgeA.first, directionA, edgeB.second)
    local overlapStart = math.max(0.0, math.min(first, second))
    local overlapEnd = math.min(lengthA, math.max(first, second))
    if overlapEnd - overlapStart <= tolerance then
        return nil
    end
    return {
        first = ScreenPointOnEdge(edgeA, overlapStart),
        second = ScreenPointOnEdge(edgeA, overlapEnd),
        length = overlapEnd - overlapStart,
    }
end

local function FaceIdentity(partId, cell, faceIndex)
    return tostring(partId) .. ":" .. tostring(cell.hexQ) .. ":" .. tostring(cell.hexR)
        .. ":" .. tostring(cell.sector) .. ":" .. tostring(cell.layer) .. ":" .. tostring(faceIndex)
end

local function CopyWorldVertices(partRenderer, partId, vertices)
    local result = {}
    for _, vertex in ipairs(vertices) do
        result[#result + 1] = partRenderer:GetPartWorldPoint(partId, vertex)
    end
    return result
end

local function CollectWorldFaces(partSessions, grid, partRenderer)
    local faces = {}
    for partId, session in pairs(partSessions or {}) do
        if session and session.document then
            session.document:ForEach(function(cell)
                local localFaces = grid:GetCellFaces(cell)
                for faceIndex, face in ipairs(localFaces) do
                    local vertices = CopyWorldVertices(partRenderer, partId, face.vertices)
                    local normal = partRenderer:GetPartWorldNormal(partId, face.normal)
                    if vertices[1] and normal then
                        faces[#faces + 1] = {
                            id = FaceIdentity(partId, cell, faceIndex),
                            partId = partId,
                            cell = cell,
                            faceIndex = faceIndex,
                            kind = face.kind,
                            vertices = vertices,
                            normal = normal:Normalized(),
                        }
                    end
                end
            end)
        end
    end
    return faces
end

local function IsSameWorldPlane(normalA, verticesA, normalB, verticesB, tolerance)
    if not normalA or not normalB or not verticesA or not verticesB then
        return false
    end
    if normalA:DotProduct(normalB) < 1.0 - math.max(tolerance, 0.01) then
        return false
    end
    local origin = verticesA[1]
    for _, vertex in ipairs(verticesB) do
        if math.abs((vertex - origin):DotProduct(normalA)) > OCCLUSION_DEPTH_EPSILON then
            return false
        end
    end
    return true
end

local function IsEndpointCellHit(hit, fromRecord, toRecord)
    local fromCell = fromRecord.node.voxelCell
    local toCell = toRecord.node.voxelCell
    if hit.partId == fromRecord.partId
        and hit.cell.hexQ == fromCell.hexQ
        and hit.cell.hexR == fromCell.hexR
        and hit.cell.sector == fromCell.sector
        and hit.cell.layer == fromCell.layer then
        return true
    end
    if hit.partId == toRecord.partId
        and hit.cell.hexQ == toCell.hexQ
        and hit.cell.hexR == toCell.hexR
        and hit.cell.sector == toCell.sector
        and hit.cell.layer == toCell.layer then
        return true
    end
    return false
end

local function ClassifyOcclusionHit(hit, fromFace, toFace, fromRecord, toRecord)
    if hit.id == fromFace.id or hit.id == toFace.id or IsEndpointCellHit(hit, fromRecord, toRecord) then
        return "endpoint"
    end
    if IsSameWorldPlane(hit.normal, hit.vertices, fromFace.normal, fromFace.vertices, FACE_TOLERANCE)
        or IsSameWorldPlane(hit.normal, hit.vertices, toFace.normal, toFace.vertices, FACE_TOLERANCE) then
        return "supporting"
    end
    -- 只拒绝挡在两条可走面之前的几何。三维中切开两端的墙是错视间隙，不是遮挡。
    if fromFace.distance and toFace.distance
        and hit.distance + OCCLUSION_DEPTH_EPSILON < math.min(fromFace.distance, toFace.distance) then
        return "occluder"
    end
    return "behind"
end

local function CollectRayHits(ray, worldFaces)
    local hits = {}
    for _, face in ipairs(worldFaces) do
        local distance = RayFace(ray, face.vertices)
        if distance then
            hits[#hits + 1] = {
                id = face.id,
                partId = face.partId,
                cell = face.cell,
                faceIndex = face.faceIndex,
                kind = face.kind,
                vertices = face.vertices,
                normal = face.normal,
                distance = distance,
            }
        end
    end
    table.sort(hits, function(left, right)
        return left.distance < right.distance
    end)
    return hits
end

local function FindEndpointHit(hits, faceId)
    for _, hit in ipairs(hits) do
        if hit.id == faceId then
            return hit
        end
    end
    return nil
end

local function EvaluateSeamOcclusion(fromRecord, toRecord, overlapSegment, camera, worldFaces)
    local fromFace = nil
    local toFace = nil
    local fromId = FaceIdentity(fromRecord.partId, fromRecord.node.voxelCell, fromRecord.node:GetFaceIndex())
    local toId = FaceIdentity(toRecord.partId, toRecord.node.voxelCell, toRecord.node:GetFaceIndex())
    for _, face in ipairs(worldFaces) do
        if face.id == fromId then
            fromFace = face
        elseif face.id == toId then
            toFace = face
        end
    end
    if not fromFace or not toFace then
        return "insufficient-evidence", "missing-endpoint-world-face", {
            overlapSegment = overlapSegment,
            samples = {},
        }
    end

    local fromCentroid = Vector2(0, 0)
    local toCentroid = Vector2(0, 0)
    for _, vertex in ipairs(fromFace.vertices) do
        local projected = camera:WorldToScreenPoint(vertex)
        fromCentroid = Vector2(fromCentroid.x + projected.x, fromCentroid.y + projected.y)
    end
    fromCentroid = Vector2(fromCentroid.x / #fromFace.vertices, fromCentroid.y / #fromFace.vertices)
    for _, vertex in ipairs(toFace.vertices) do
        local projected = camera:WorldToScreenPoint(vertex)
        toCentroid = Vector2(toCentroid.x + projected.x, toCentroid.y + projected.y)
    end
    toCentroid = Vector2(toCentroid.x / #toFace.vertices, toCentroid.y / #toFace.vertices)
    local insetTarget = Vector2(
        (fromCentroid.x + toCentroid.x) * 0.5,
        (fromCentroid.y + toCentroid.y) * 0.5
    )

    local samples = {}
    local occluder = nil
    local missingEndpoint = false
    for _, t in ipairs(OCCLUSION_SAMPLE_TS) do
        local screenPoint = Vector2(
            overlapSegment.first.x + (overlapSegment.second.x - overlapSegment.first.x) * t,
            overlapSegment.first.y + (overlapSegment.second.y - overlapSegment.first.y) * t
        )
        local insetX = insetTarget.x - screenPoint.x
        local insetY = insetTarget.y - screenPoint.y
        local insetLength = math.sqrt(insetX * insetX + insetY * insetY)
        if insetLength > FACE_TOLERANCE then
            screenPoint = Vector2(
                screenPoint.x + insetX / insetLength * 0.004,
                screenPoint.y + insetY / insetLength * 0.004
            )
        end
        local ray = camera:GetScreenRay(screenPoint.x, screenPoint.y)
        local hits = CollectRayHits(ray, worldFaces)
        local fromHit = FindEndpointHit(hits, fromFace.id)
        local toHit = FindEndpointHit(hits, toFace.id)
        local sample = {
            t = t,
            screenPoint = screenPoint,
            hitCount = #hits,
            firstHitId = hits[1] and hits[1].id or nil,
            classification = "insufficient-evidence",
        }
        if not fromHit or not toHit then
            missingEndpoint = true
            sample.classification = "insufficient-evidence"
            samples[#samples + 1] = sample
        else
            fromFace.distance = fromHit.distance
            toFace.distance = toHit.distance
            sample.fromDistance = fromHit.distance
            sample.toDistance = toHit.distance
            local sampleClass = "endpoint"
            for _, hit in ipairs(hits) do
                local classification = ClassifyOcclusionHit(hit, fromFace, toFace, fromRecord, toRecord)
                if classification == "occluder" then
                    sampleClass = "occluder"
                    sample.occluder = {
                        id = hit.id,
                        partId = hit.partId,
                        faceIndex = hit.faceIndex,
                        distance = hit.distance,
                    }
                    occluder = sample.occluder
                    break
                elseif classification == "endpoint" or classification == "supporting" then
                    sampleClass = classification
                end
            end
            sample.classification = sampleClass
            samples[#samples + 1] = sample
        end
    end

    local occlusion = {
        overlapSegment = overlapSegment,
        samples = samples,
        occluder = occluder,
    }
    if occluder then
        return "rejected", "visual-seam-occluded", occlusion
    end
    if missingEndpoint then
        return "insufficient-evidence", "insufficient-occlusion-evidence", occlusion
    end
    return "accepted", "projected-face-edge-overlap", occlusion
end

local function EvaluateCandidate(record, grid, partRenderer, cameraNode, camera, options, worldFaces)
    if not record.from or not record.to then
        return "rejected", "unresolved"
    end
    if not record.from.node.walkable or not record.to.node.walkable then
        return "rejected", "endpoint-not-walkable"
    end

    local fromFaceVertices = GetWorldFace(record.from, grid, partRenderer)
    local toFaceVertices = GetWorldFace(record.to, grid, partRenderer)
    if AreFacesCoincident(fromFaceVertices, toFaceVertices, FACE_COINCIDENCE_TOLERANCE) then
        return "rejected", "endpoint-faces-coincide"
    end

    local fromData, fromError = GetWorldNodeData(record.from, grid, partRenderer)
    if not fromData then
        return "rejected", fromError
    end
    local toData, toError = GetWorldNodeData(record.to, grid, partRenderer)
    if not toData then
        return "rejected", toError
    end

    local fromLocalEdges = record.from.node:GetLocalFaceEdges(grid)
    local toLocalEdges = record.to.node:GetLocalFaceEdges(grid)
    if not fromLocalEdges or not toLocalEdges then
        return "rejected", "missing-face-edges"
    end
    local fromWorldEdges = TransformEdges(partRenderer, record.from.partId, fromLocalEdges)
    local toWorldEdges = TransformEdges(partRenderer, record.to.partId, toLocalEdges)
    local fromProjectedEdges = ProjectEdges(camera, fromWorldEdges)
    local toProjectedEdges = ProjectEdges(camera, toWorldEdges)
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
        return "rejected", result.reason, result
    end

    local overlapSegment = GetProjectedOverlapSegment(
        fromProjectedEdges[fromEdgeIndex],
        toProjectedEdges[toEdgeIndex],
        FACE_TOLERANCE
    )
    result.overlapSegment = overlapSegment
    if not overlapSegment then
        result.reason = "projected-face-edge-does-not-overlap"
        return "rejected", result.reason, result
    end
    if not worldFaces then
        result.reason = "insufficient-occlusion-evidence"
        return "insufficient-evidence", result.reason, result
    end

    local occlusionStatus, occlusionReason, occlusion = EvaluateSeamOcclusion(
        record.from,
        record.to,
        overlapSegment,
        camera,
        worldFaces
    )
    result.occlusion = occlusion
    result.reason = occlusionReason
    return occlusionStatus, occlusionReason, result
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
    local worldFaces = CollectWorldFaces(self.partSessions, self.grid, self.partRenderer)
    for _, record in ipairs(self.candidateRecords) do
        if record.status == "pending" then
            local status, reason, result = EvaluateCandidate(
                record,
                self.grid,
                self.partRenderer,
                self.cameraNode,
                self.camera,
                self.evaluationOptions,
                worldFaces
            )
            record.status = status
            record.reason = reason
            record.evaluation = result
            AddDiagnostic(self.diagnostics, record.id, record.status, reason)
            print(string.format(
                "PathRuntime candidate %s status=%s reason=%s",
                tostring(record.id),
                tostring(status),
                tostring(reason)
            ))
        end
    end
    return true
end

-- Snap 后只刷新世界锚点和视觉候选，不重载 Part 文档。
-- 编辑器立刻改 Yaw 仍走 Rebuild()；Preview 机关到达合法状态后走这里。
function PathRuntime:RefreshAfterMechanismSnap()
    if not self.partRenderer or not self.cameraNode or not self.camera then
        return false, "visual evaluation requires renderer and fixed camera"
    end
    self.diagnostics = {}
    for _, record in ipairs(self.candidateRecords) do
        if record.status == "accepted"
            or record.status == "rejected"
            or record.status == "insufficient-evidence" then
            record.status = "pending"
            record.reason = "等待视觉评估"
            record.evaluation = nil
        end
    end
    local evaluated, errorMessage = self:EvaluateCandidates()
    if not evaluated then
        return false, errorMessage
    end
    self:BuildEffectiveGraph()
    return true
end

function PathRuntime:AddDirectedEdge(adjacency, fromKey, toKey, candidateId, kind)
    local neighbors = adjacency[fromKey]
    if not neighbors then
        neighbors = {}
        adjacency[fromKey] = neighbors
    end
    neighbors[#neighbors + 1] = {
        key = toKey,
        candidateId = candidateId,
        kind = kind or "local_fixed",
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
                self:AddDirectedEdge(adjacency, fromKey, toKey, record.id, "candidate")
                edges[#edges + 1] = { id = record.id .. ":from_to", candidateId = record.id, from = fromKey, to = toKey }
            end
            if record.candidate.direction == "bidirectional"
                or record.candidate.direction == "to_from" then
                self:AddDirectedEdge(adjacency, toKey, fromKey, record.id, "candidate")
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

function PathRuntime:IsCandidateEdge(fromKey, toKey)
    for _, edge in ipairs(self.adjacency[fromKey] or {}) do
        if edge.key == toKey and edge.kind == "candidate" then
            return true
        end
    end
    return false
end

function PathRuntime:IsConfiguredCandidateEdge(fromKey, toKey)
    for _, record in ipairs(self.candidateRecords) do
        if record.fromKey == fromKey and record.toKey == toKey then
            if record.candidate.direction == "bidirectional"
                or record.candidate.direction == "from_to" then
                return true
            end
        elseif record.fromKey == toKey and record.toKey == fromKey then
            if record.candidate.direction == "bidirectional"
                or record.candidate.direction == "to_from" then
                return true
            end
        end
    end
    return false
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

function PathRuntime:FindPathIncludingCandidates(startKey, goalKey)
    if not self.nodesByKey[startKey] or not self.nodesByKey[goalKey] then
        return nil, "node-not-found"
    end
    if startKey == goalKey then
        return { startKey }
    end
    local adjacency = {}
    local function AddEdge(fromKey, toKey)
        adjacency[fromKey] = adjacency[fromKey] or {}
        adjacency[fromKey][#adjacency[fromKey] + 1] = toKey
    end
    for _, record in ipairs(self.candidateRecords) do
        if record.from and record.to then
            if record.candidate.direction == "bidirectional"
                or record.candidate.direction == "from_to" then
                AddEdge(record.fromKey, record.toKey)
            end
            if record.candidate.direction == "bidirectional"
                or record.candidate.direction == "to_from" then
                AddEdge(record.toKey, record.fromKey)
            end
        end
    end
    for _, part in ipairs(self.levelDocument:GetParts()) do
        local records = self.nodesByPart[part.id] or {}
        for _, source in ipairs(records) do
            for _, neighbor in ipairs(GetLocalFixedNeighbors(source, records, self.grid)) do
                AddEdge(source.key, neighbor.key)
            end
        end
    end
    local queue = { startKey }
    local head = 1
    local visited = { [startKey] = true }
    local previous = {}
    while head <= #queue do
        local current = queue[head]
        head = head + 1
        for _, nextKey in ipairs(adjacency[current] or {}) do
            if not visited[nextKey] then
                visited[nextKey] = true
                previous[nextKey] = current
                if nextKey == goalKey then
                    local path = { goalKey }
                    local cursor = goalKey
                    while previous[cursor] do
                        cursor = previous[cursor]
                        table.insert(path, 1, cursor)
                    end
                    return path
                end
                queue[#queue + 1] = nextKey
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

local function IsSameVoxelCell(cellA, cellB)
    return cellA
        and cellB
        and cellA.hexQ == cellB.hexQ
        and cellA.hexR == cellB.hexR
        and cellA.sector == cellB.sector
        and cellA.layer == cellB.layer
end

function PathRuntime:HasBlockingVoxelBetween(fromRecord, toRecord, worldFaces)
    if not fromRecord or not toRecord or not self.partRenderer then
        return false
    end
    local fromData = GetWorldNodeData(fromRecord, self.grid, self.partRenderer)
    local toData = GetWorldNodeData(toRecord, self.grid, self.partRenderer)
    if not fromData or not toData then
        return true
    end
    local faces = worldFaces
    if not faces then
        faces = CollectWorldFaces(self.partSessions, self.grid, self.partRenderer)
    end
    local origin = fromData.worldPoint
    local delta = toData.worldPoint - origin
    local length = delta:Length()
    if length <= FACE_TOLERANCE then
        return false
    end
    local direction = delta / length
    local fromCell = fromRecord.node.voxelCell
    local toCell = toRecord.node.voxelCell
    local ray = {
        origin = origin,
        direction = direction,
    }
    local hits = CollectRayHits(ray, faces)
    for _, hit in ipairs(hits) do
        if hit.distance > FACE_TOLERANCE and hit.distance < length - FACE_TOLERANCE then
            local endpoint = (hit.partId == fromRecord.partId and IsSameVoxelCell(hit.cell, fromCell))
                or (hit.partId == toRecord.partId and IsSameVoxelCell(hit.cell, toCell))
            if not endpoint then
                return true
            end
        end
    end
    return false
end

function PathRuntime:EvaluateNodePair(fromRecord, toRecord, worldFaces)
    if not fromRecord or not toRecord then
        return "rejected", "unresolved"
    end
    if not self.partRenderer or not self.cameraNode or not self.camera then
        return "rejected", "visual evaluation requires renderer and fixed camera"
    end
    local faces = worldFaces
    if not faces then
        faces = CollectWorldFaces(self.partSessions, self.grid, self.partRenderer)
    end
    return EvaluateCandidate(
        {
            from = fromRecord,
            to = toRecord,
        },
        self.grid,
        self.partRenderer,
        self.cameraNode,
        self.camera,
        self.evaluationOptions,
        faces
    )
end

function PathRuntime:CollectWorldFaces()
    if not self.partRenderer then
        return {}
    end
    return CollectWorldFaces(self.partSessions, self.grid, self.partRenderer)
end

---@param worldPoint Vector3
---@return table|nil
function PathRuntime:FindNearestWalkableNode(worldPoint)
    if not worldPoint then
        return nil
    end
    local best = nil
    local bestDistance = math.huge
    for _, record in pairs(self.nodesByKey) do
        if record.node and record.node.walkable and record.worldPoint then
            local distance = (record.worldPoint - worldPoint):Length()
            if distance < bestDistance then
                bestDistance = distance
                best = record
            end
        end
    end
    return best
end

function PathRuntime:FindNodeCandidatesAtRay(ray)
    if not ray then
        return {}
    end
    local candidates = {}
    for _, record in pairs(self.nodesByKey) do
        if record.node.walkable then
            local vertices, normal = GetWorldFace(record, self.grid, self.partRenderer)
            if vertices and normal and ray.direction:DotProduct(normal) < 0.0 then
                local distance = RayFace(ray, vertices)
                if distance then
                    candidates[#candidates + 1] = {
                        record = record,
                        distance = distance,
                    }
                end
            end
        end
    end
    table.sort(candidates, function(left, right)
        return left.distance < right.distance
    end)
    return candidates
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
    local insufficient = 0
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
        elseif record.status == "insufficient-evidence" then
            insufficient = insufficient + 1
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
        insufficientCount = insufficient,
        topologyVersion = self.topologyVersion,
    }
end

return PathRuntime
