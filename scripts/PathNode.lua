-- Part 局部可走面路径节点定义。
-- 节点锚定在 Part 局部三棱柱的指定面；当前不负责连接和寻路。

local PathNode = {}
PathNode.__index = PathNode

local FACE_INDEX = {
    top = 1,
    bottom = 2,
    side_1 = 3,
    side_2 = 4,
    side_3 = 5,
}

local VALID_KINDS = {
    floor = true,
    ladder = true,
    connector = true,
}

local function CopyCell(cell)
    cell = cell or {}
    return {
        hexQ = math.floor(cell.hexQ or 0),
        hexR = math.floor(cell.hexR or 0),
        sector = math.floor(cell.sector or 0),
        layer = math.floor(cell.layer or 0),
    }
end

local function CopyVector(vector)
    return Vector3(vector.x, vector.y, vector.z)
end

local function AverageVertices(vertices)
    local center = Vector3(0, 0, 0)
    for _, vertex in ipairs(vertices) do
        center = center + vertex
    end
    return center / #vertices
end

function PathNode.New(data)
    local self = setmetatable({}, PathNode)
    self:Init(data)
    return self
end

function PathNode:Init(data)
    data = data or {}
    self.id = data.id or "path_node"
    self.partId = data.partId or nil
    self.voxelCell = CopyCell(data.voxelCell or data.cell)
    self.face = FACE_INDEX[data.face] and data.face or "top"
    self.kind = VALID_KINDS[data.kind] and data.kind or "floor"
    self.walkable = data.walkable ~= false
    self.orientation = math.floor(data.orientation or 0) % 6
    self.entryDirection = data.entryDirection or "forward"
    self.exitDirection = data.exitDirection or "forward"
end

function PathNode:GetFaceIndex()
    return FACE_INDEX[self.face]
end

function PathNode.FaceName(faceIndex)
    for name, index in pairs(FACE_INDEX) do
        if index == faceIndex then
            return name
        end
    end
    return nil
end

function PathNode:SetFace(face)
    if not FACE_INDEX[face] then
        return false
    end
    self.face = face
    return true
end

function PathNode:SetKind(kind)
    if not VALID_KINDS[kind] then
        return false
    end
    self.kind = kind
    return true
end

function PathNode:GetLocalAnchor(grid, offset)
    local faces = grid:GetCellFaces(self.voxelCell)
    local face = faces[self:GetFaceIndex()]
    if not face then
        return nil, nil
    end
    local center = AverageVertices(face.vertices)
    local normal = face.normal
    return center + normal * (offset or 0.035), CopyVector(normal)
end

function PathNode:GetLocalDirection(grid, direction)
    local faces = grid:GetCellFaces(self.voxelCell)
    local face = faces[self:GetFaceIndex()]
    if not face then
        return nil
    end
    local normal = face.normal:Normalized()
    local reference = Vector3.FORWARD
    if math.abs(normal:DotProduct(reference)) > 0.95 then
        reference = Vector3.RIGHT
    end
    local tangent = (reference - normal * reference:DotProduct(normal)):Normalized()
    local bitangent = normal:CrossProduct(tangent):Normalized()
    local directions = {
        forward = tangent,
        right = bitangent,
        backward = -tangent,
        left = -bitangent,
    }
    local base = directions[direction] or directions.forward
    local angle = self.orientation * math.pi / 3.0
    return (base * math.cos(angle) + normal:CrossProduct(base) * math.sin(angle)):Normalized()
end

function PathNode:GetLocalRoadEdge(grid, direction)
    local faces = grid:GetCellFaces(self.voxelCell)
    local face = faces[self:GetFaceIndex()]
    local faceDirection = self:GetLocalDirection(grid, direction)
    if not face or not faceDirection then
        return nil
    end
    local center = AverageVertices(face.vertices)
    local bestEdge = nil
    local bestScore = -math.huge
    for index = 1, #face.vertices do
        local nextIndex = index % #face.vertices + 1
        local first = face.vertices[index]
        local second = face.vertices[nextIndex]
        local midpoint = (first + second) * 0.5
        local score = (midpoint - center):DotProduct(faceDirection)
        if score > bestScore then
            bestScore = score
            bestEdge = {
                first = CopyVector(first),
                second = CopyVector(second),
            }
        end
    end
    return bestEdge
end

function PathNode:ToTable()
    return {
        id = self.id,
        partId = self.partId,
        voxelCell = CopyCell(self.voxelCell),
        face = self.face,
        kind = self.kind,
        walkable = self.walkable,
        orientation = self.orientation,
        entryDirection = self.entryDirection,
        exitDirection = self.exitDirection,
    }
end

function PathNode.FromTable(data)
    if type(data) ~= "table" or type(data.id) ~= "string" or data.id == "" then
        return nil, "invalid PathNode"
    end
    return PathNode.New(data)
end

return PathNode
