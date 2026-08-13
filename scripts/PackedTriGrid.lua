-- 等边三角形铺砌挤出的三棱柱网格。
-- 基本单元是一个菱形被一条对角线分成的两个等边三角形。
-- (i, j, parity) 唯一决定平面占地；rotation 只允许 120 度步进。

local PackedTriGrid = {}
PackedTriGrid.__index = PackedTriGrid

local SQRT3 = math.sqrt(3.0)
local EPSILON = 0.0001

local function Round(value)
    if value >= 0 then return math.floor(value + 0.5) end
    return math.ceil(value - 0.5)
end

local function NormalizeParity(value)
    return value % 2
end

local function NormalizeRotation(value)
    return value % 3
end

local function Cross2D(a, b, p)
    return (b.x - a.x) * (p.z - a.z) - (b.z - a.z) * (p.x - a.x)
end

local function PointInTriangle(point, vertices)
    local c1 = Cross2D(vertices[1], vertices[2], point)
    local c2 = Cross2D(vertices[2], vertices[3], point)
    local c3 = Cross2D(vertices[3], vertices[1], point)
    local hasPositive = c1 > EPSILON or c2 > EPSILON or c3 > EPSILON
    local hasNegative = c1 < -EPSILON or c2 < -EPSILON or c3 < -EPSILON
    return not (hasPositive and hasNegative)
end

function PackedTriGrid.New(edgeLength, voxelHeight)
    local self = setmetatable({}, PackedTriGrid)
    self.edgeLength = edgeLength
    self.voxelHeight = voxelHeight
    self.height = edgeLength / SQRT3
    self.rowHeight = edgeLength * SQRT3 * 0.5
    return self
end

function PackedTriGrid:NormalizeCell(cell)
    return {
        i = cell.i,
        j = cell.j,
        parity = NormalizeParity(cell.parity or 0),
        layer = cell.layer,
        rotation = NormalizeRotation(cell.rotation or 0),
        material = cell.material or 1,
    }
end

function PackedTriGrid:CellKey(cell)
    local normalized = self:NormalizeCell(cell)
    return tostring(normalized.i) .. ":" .. tostring(normalized.j) .. ":" .. tostring(normalized.parity) .. ":" .. tostring(normalized.layer)
end

function PackedTriGrid:GetLatticeVertex(i, j)
    return Vector3(
        self.edgeLength * (i + j * 0.5),
        0,
        -self.rowHeight * j
    )
end

function PackedTriGrid:GetTriangleVertices(cell, yOffset)
    local normalized = self:NormalizeCell(cell)
    local origin = self:GetLatticeVertex(normalized.i, normalized.j)
    local e1 = Vector3(self.edgeLength, 0, 0)
    local e2 = Vector3(self.edgeLength * 0.5, 0, -self.rowHeight)
    local vertices

    if normalized.parity == 0 then
        vertices = {
            origin,
            origin + e1,
            origin + e2,
        }
    else
        vertices = {
            origin + e1 + e2,
            origin + e2,
            origin + e1,
        }
    end

    local y = normalized.layer * self.voxelHeight + (yOffset or 0)
    for index = 1, 3 do
        vertices[index].y = y
    end
    return vertices
end

function PackedTriGrid:GetCellCenter(cell)
    local vertices = self:GetTriangleVertices(cell)
    return (vertices[1] + vertices[2] + vertices[3]) / 3.0
end

function PackedTriGrid:GetVoxelTransform(cell)
    local normalized = self:NormalizeCell(cell)
    local center = self:GetCellCenter(normalized)
    center.y = center.y + self.voxelHeight * 0.5
    local baseYaw = normalized.parity == 0 and -90.0 or 90.0
    return center, Quaternion(baseYaw + normalized.rotation * 120.0, Vector3.UP)
end

function PackedTriGrid:ContainsPoint(cell, worldPosition)
    return PointInTriangle(worldPosition, self:GetTriangleVertices(cell))
end

function PackedTriGrid:WorldToCell(worldPosition, layer)
    local axialJ = -worldPosition.z / self.rowHeight
    local axialI = worldPosition.x / self.edgeLength - axialJ * 0.5
    local centerI = Round(axialI)
    local centerJ = Round(axialJ)

    for j = centerJ - 2, centerJ + 2 do
        for i = centerI - 2, centerI + 2 do
            for parity = 0, 1 do
                local candidate = { i = i, j = j, parity = parity, layer = layer, rotation = 0 }
                if PointInTriangle(worldPosition, self:GetTriangleVertices(candidate)) then
                    return candidate
                end
            end
        end
    end

    local bestCell = nil
    local bestDistance = math.huge
    for j = centerJ - 2, centerJ + 2 do
        for i = centerI - 2, centerI + 2 do
            for parity = 0, 1 do
                local candidate = { i = i, j = j, parity = parity, layer = layer, rotation = 0 }
                local center = self:GetCellCenter(candidate)
                local dx = worldPosition.x - center.x
                local dz = worldPosition.z - center.z
                local distance = dx * dx + dz * dz
                if distance < bestDistance then
                    bestCell = candidate
                    bestDistance = distance
                end
            end
        end
    end
    return bestCell
end

function PackedTriGrid:GetFaceNeighbor(cell, faceIndex)
    local normalized = self:NormalizeCell(cell)
    if faceIndex == 1 then
        return { i = normalized.i, j = normalized.j, parity = normalized.parity, layer = normalized.layer + 1, rotation = normalized.rotation }
    elseif faceIndex == 2 then
        return { i = normalized.i, j = normalized.j, parity = normalized.parity, layer = normalized.layer - 1, rotation = normalized.rotation }
    end

    if normalized.parity == 0 then
        local neighbors = {
            [3] = { i = normalized.i, j = normalized.j, parity = 1 },
            [4] = { i = normalized.i - 1, j = normalized.j, parity = 1 },
            [5] = { i = normalized.i, j = normalized.j - 1, parity = 1 },
        }
        local neighbor = neighbors[faceIndex]
        if neighbor then
            neighbor.layer = normalized.layer
            neighbor.rotation = normalized.rotation
            return neighbor
        end
    else
        local neighbors = {
            [3] = { i = normalized.i, j = normalized.j, parity = 0 },
            [4] = { i = normalized.i + 1, j = normalized.j, parity = 0 },
            [5] = { i = normalized.i, j = normalized.j + 1, parity = 0 },
        }
        local neighbor = neighbors[faceIndex]
        if neighbor then
            neighbor.layer = normalized.layer
            neighbor.rotation = normalized.rotation
            return neighbor
        end
    end
    return nil
end

function PackedTriGrid:GetGridLines(i, j, layer)
    local origin = self:GetLatticeVertex(i, j)
    local e1 = Vector3(self.edgeLength, 0, 0)
    local e2 = Vector3(self.edgeLength * 0.5, 0, -self.rowHeight)
    local y = layer * self.voxelHeight
    origin.y = y
    local p1 = origin + e1
    local p2 = origin + e2
    p1.y = y
    p2.y = y
    return origin, p1, p2
end

return PackedTriGrid
