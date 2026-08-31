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

function PathNode.IsValidId(id)
    if type(id) ~= "string" then
        return false, "PathNode id 必须是字符串"
    end
    local trimmed = id:match("^%s*(.-)%s*$") or ""
    if trimmed == "" then
        return false, "PathNode id 不能为空"
    end
    if trimmed:find(":", 1, true) then
        return false, "PathNode id 不能包含 ':'"
    end
    return true, trimmed
end

function PathNode:Init(data)
    data = data or {}
    local valid, idOrError = PathNode.IsValidId(data.id or "path_node")
    self.id = valid and idOrError or "path_node"
    self.voxelCell = CopyCell(data.voxelCell or data.cell)
    self.face = FACE_INDEX[data.face] and data.face or "top"
    self.kind = VALID_KINDS[data.kind] and data.kind or "floor"
    self.walkable = data.walkable ~= false
end

function PathNode:SetId(id)
    local valid, idOrError = PathNode.IsValidId(id)
    if not valid then
        return false, idOrError
    end
    self.id = idOrError
    return true
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

function PathNode:GetLocalFaceEdges(grid)
    local faces = grid:GetCellFaces(self.voxelCell)
    local face = faces[self:GetFaceIndex()]
    if not face then
        return nil
    end
    local edges = {}
    for index = 1, #face.vertices do
        local nextIndex = index % #face.vertices + 1
        edges[#edges + 1] = {
            first = CopyVector(face.vertices[index]),
            second = CopyVector(face.vertices[nextIndex]),
        }
    end
    return edges
end

function PathNode:ToTable()
    return {
        id = self.id,
        voxelCell = CopyCell(self.voxelCell),
        face = self.face,
        kind = self.kind,
        walkable = self.walkable,
    }
end

function PathNode.FromTable(data)
    if type(data) ~= "table" then
        return nil, "invalid PathNode"
    end
    local valid, idOrError = PathNode.IsValidId(data.id)
    if not valid then
        return nil, idOrError
    end
    data.id = idOrError
    return PathNode.New(data)
end

return PathNode
