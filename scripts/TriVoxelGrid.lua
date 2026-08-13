-- 三棱柱体素沙盒的离散三角网格
-- 真相源是整数锚点 (i, j)、整数层 layer 和六向朝向 orientation。
-- 世界坐标只由这些离散数据派生，禁止反向保存浮点位置。

local TriVoxelGrid = {}
---@class TriVoxelGrid
---@field edgeLength number
---@field voxelHeight number
---@field anchorRadius number
---@field cells table
TriVoxelGrid.__index = TriVoxelGrid

local SQRT3 = math.sqrt(3.0)
local EPSILON = 0.0001

local function Round(value)
    if value >= 0 then
        return math.floor(value + 0.5)
    end
    return math.ceil(value - 0.5)
end

local function NormalizeOrientation(orientation)
    local value = orientation % 6
    if value < 0 then
        value = value + 6
    end
    return value
end

local function MakeKey(i, j, layer, orientation)
    return tostring(i) .. ":" .. tostring(j) .. ":" .. tostring(layer) .. ":" .. tostring(orientation)
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

function TriVoxelGrid.New(edgeLength, voxelHeight)
    local self = setmetatable({}, TriVoxelGrid)
    self.edgeLength = edgeLength
    self.voxelHeight = voxelHeight
    self.anchorRadius = edgeLength / SQRT3
    self.cells = {}
    return self
end

function TriVoxelGrid:NormalizeOrientation(orientation)
    return NormalizeOrientation(orientation)
end

function TriVoxelGrid:MakeKey(i, j, layer, orientation)
    return MakeKey(i, j, layer, NormalizeOrientation(orientation))
end

function TriVoxelGrid:GetAnchorPosition(i, j, layer)
    local edge = self.edgeLength
    local halfEdge = edge * 0.5
    local latticeX = SQRT3 * halfEdge
    return Vector3(
        latticeX * (i + j),
        layer * self.voxelHeight,
        halfEdge * (i - j)
    )
end

function TriVoxelGrid:WorldToAnchor(worldPosition, layer)
    local edge = self.edgeLength
    local halfEdge = edge * 0.5
    local latticeX = SQRT3 * halfEdge
    local axialI = 0.5 * (worldPosition.x / latticeX + worldPosition.z / halfEdge)
    local axialJ = 0.5 * (worldPosition.x / latticeX - worldPosition.z / halfEdge)
    local axialK = -axialI - axialJ

    local i = Round(axialI)
    local j = Round(axialJ)
    local k = Round(axialK)
    local iDiff = math.abs(i - axialI)
    local jDiff = math.abs(j - axialJ)
    local kDiff = math.abs(k - axialK)

    if iDiff > jDiff and iDiff > kDiff then
        i = -j - k
    elseif jDiff > kDiff then
        j = -i - k
    end

    return i, j, self:GetAnchorPosition(i, j, layer)
end

function TriVoxelGrid:GetTriangleVertices(i, j, layer, orientation, yOffset)
    local rotation = Quaternion(NormalizeOrientation(orientation) * 60.0, Vector3.UP)
    local anchor = self:GetAnchorPosition(i, j, layer)
    local radius = self.anchorRadius
    local halfEdge = self.edgeLength * 0.5
    local p2 = anchor + rotation * Vector3(radius * 1.5, 0, halfEdge)
    local p3 = anchor + rotation * Vector3(radius * 1.5, 0, -halfEdge)
    local offset = yOffset or 0.0
    return {
        anchor + Vector3(0, offset, 0),
        p2 + Vector3(0, offset, 0),
        p3 + Vector3(0, offset, 0),
    }
end

function TriVoxelGrid:GetPlacementCell(worldPosition, layer, orientation)
    orientation = NormalizeOrientation(orientation)
    local rotation = Quaternion(orientation * 60.0, Vector3.UP)
    local targetAnchor = worldPosition - rotation * Vector3(self.anchorRadius, 0, 0)
    local i, j, anchor = self:WorldToAnchor(targetAnchor, layer)
    return {
        i = i,
        j = j,
        layer = layer,
        orientation = orientation,
        key = self:MakeKey(i, j, layer, orientation),
    }
end

function TriVoxelGrid:FindCellAtWorld(worldPosition, layer)
    local centerI, centerJ = self:WorldToAnchor(worldPosition, layer)
    for j = centerJ - 2, centerJ + 2 do
        for i = centerI - 2, centerI + 2 do
            for orientation = 0, 5 do
                local vertices = self:GetTriangleVertices(i, j, layer, orientation)
                if PointInTriangle(worldPosition, vertices) then
                    return {
                        i = i,
                        j = j,
                        layer = layer,
                        orientation = orientation,
                        key = self:MakeKey(i, j, layer, orientation),
                    }
                end
            end
        end
    end
    return nil
end

function TriVoxelGrid:GetCellAtWorld(worldPosition, layer)
    return self:FindCellAtWorld(worldPosition, layer)
end

function TriVoxelGrid:Place(i, j, layer, orientation, color)
    orientation = NormalizeOrientation(orientation)
    local key = MakeKey(i, j, layer, orientation)
    if self.cells[key] then
        return nil
    end

    local cell = {
        i = i,
        j = j,
        layer = layer,
        orientation = orientation,
        color = color,
        key = key,
    }
    self.cells[key] = cell
    return cell
end

function TriVoxelGrid:Remove(cell)
    if not cell or not self.cells[cell.key] then
        return nil
    end

    self.cells[cell.key] = nil
    return cell
end

function TriVoxelGrid:Get(i, j, layer, orientation)
    return self.cells[MakeKey(i, j, layer, NormalizeOrientation(orientation))]
end

function TriVoxelGrid:GetByKey(key)
    return self.cells[key]
end

function TriVoxelGrid:ForEach(callback)
    for _, cell in pairs(self.cells) do
        callback(cell)
    end
end

function TriVoxelGrid:GetVoxelTransform(cell)
    local rotation = Quaternion(cell.orientation * 60.0, Vector3.UP)
    local anchor = self:GetAnchorPosition(cell.i, cell.j, cell.layer)
    local center = anchor + rotation * Vector3(self.anchorRadius, 0, 0)
    center.y = center.y + self.voxelHeight * 0.5
    return center, rotation
end

function TriVoxelGrid:GetFootprintVertices(cell, yOffset)
    return self:GetTriangleVertices(
        cell.i,
        cell.j,
        cell.layer,
        cell.orientation,
        yOffset
    )
end

function TriVoxelGrid:GetTriangleCenter(cell, yOffset)
    local vertices = self:GetFootprintVertices(cell, yOffset)
    return (vertices[1] + vertices[2] + vertices[3]) / 3.0
end

return TriVoxelGrid
