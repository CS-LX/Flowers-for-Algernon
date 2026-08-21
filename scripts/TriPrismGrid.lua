-- 六边形密铺的三棱柱网格核心。
--
-- 平面坐标：轴坐标 (hexQ, hexR) 标识一个正六边形单元。
-- 每个正六边形由六个等边三角扇区组成；sector=0..5 标识一个扇区。
-- 每个扇区沿 Y 轴垂直挤出，形成一个三棱柱体素。
-- 这是编辑器唯一允许推导三棱柱拓扑、邻接和拾取的模块。

local TriPrismGrid = {}
TriPrismGrid.__index = TriPrismGrid

local SQRT3 = math.sqrt(3.0)
local EPSILON = 0.0001
local TAU = math.pi * 2.0

local function NormalizeIndex(value, modulo)
    local integer = math.floor((value or 0) + 0.5)
    return integer % modulo
end

local function NormalizeInteger(value)
    return math.floor((value or 0) + 0.5)
end

local function CopyVector(vector)
    return Vector3(vector.x, vector.y, vector.z)
end

local function Cross2D(a, b, point)
    return (b.x - a.x) * (point.z - a.z) - (b.z - a.z) * (point.x - a.x)
end

local function PointInTriangle(point, vertices)
    local first = Cross2D(vertices[1], vertices[2], point)
    local second = Cross2D(vertices[2], vertices[3], point)
    local third = Cross2D(vertices[3], vertices[1], point)
    local hasPositive = first > EPSILON or second > EPSILON or third > EPSILON
    local hasNegative = first < -EPSILON or second < -EPSILON or third < -EPSILON
    return not (hasPositive and hasNegative)
end

local function RayTriangle(rayOrigin, rayDirection, a, b, c)
    local edge1 = b - a
    local edge2 = c - a
    local pVector = rayDirection:CrossProduct(edge2)
    local determinant = edge1:DotProduct(pVector)
    if math.abs(determinant) < EPSILON then
        return nil
    end

    local inverseDeterminant = 1.0 / determinant
    local tVector = rayOrigin - a
    local u = tVector:DotProduct(pVector) * inverseDeterminant
    if u < -EPSILON or u > 1.0 + EPSILON then
        return nil
    end

    local qVector = tVector:CrossProduct(edge1)
    local v = rayDirection:DotProduct(qVector) * inverseDeterminant
    if v < -EPSILON or u + v > 1.0 + EPSILON then
        return nil
    end

    local distance = edge2:DotProduct(qVector) * inverseDeterminant
    if distance < -EPSILON then
        return nil
    end
    return math.max(0.0, distance)
end

local function NormalizeDirection(vector)
    local length = vector:Length()
    if length < EPSILON then
        return Vector3(0, 1, 0)
    end
    return vector / length
end

local function CellField(cell, name, fallback)
    if cell[name] ~= nil then
        return cell[name]
    end
    return fallback
end

function TriPrismGrid.New(edgeLength, voxelHeight)
    local self = setmetatable({}, TriPrismGrid)
    self.edgeLength = edgeLength or 1.0
    self.voxelHeight = voxelHeight or self.edgeLength / SQRT3
    self.hexRadius = self.edgeLength
    self.hexCenterDistance = self.edgeLength * SQRT3
    self.triangleCentroidRadius = self.edgeLength / SQRT3
    self.sectorCount = 6
    self.faceCount = 5
    return self
end

function TriPrismGrid:NormalizeCell(cell)
    local hexQ = CellField(cell, "hexQ", CellField(cell, "q", 0))
    local hexR = CellField(cell, "hexR", CellField(cell, "r", 0))
    return {
        hexQ = NormalizeInteger(hexQ),
        hexR = NormalizeInteger(hexR),
        sector = NormalizeIndex(cell.sector or 0, self.sectorCount),
        layer = NormalizeInteger(cell.layer),
        rotation = NormalizeIndex(cell.rotation or 0, self.sectorCount),
        material = cell.material or 1,
    }
end

function TriPrismGrid:IsValid(cell)
    if type(cell) ~= "table" then
        return false
    end
    local normalized = self:NormalizeCell(cell)
    return normalized.layer >= 0 and normalized.sector >= 0 and normalized.sector < self.sectorCount
end

function TriPrismGrid:CellKey(cell)
    local normalized = self:NormalizeCell(cell)
    return table.concat({
        tostring(normalized.hexQ),
        tostring(normalized.hexR),
        tostring(normalized.sector),
        tostring(normalized.layer),
    }, ":")
end

function TriPrismGrid:GetHexCenter(hexQ, hexR, y)
    return Vector3(
        self.edgeLength * 1.5 * hexQ,
        y or 0,
        -self.edgeLength * SQRT3 * (hexR + hexQ * 0.5)
    )
end

function TriPrismGrid:GetHexNeighbor(hexQ, hexR, direction)
    local directions = {
        { q = 1, r = 0 },
        { q = 0, r = 1 },
        { q = -1, r = 1 },
        { q = -1, r = 0 },
        { q = 0, r = -1 },
        { q = 1, r = -1 },
    }
    local offset = directions[NormalizeIndex(direction, self.sectorCount) + 1]
    return hexQ + offset.q, hexR + offset.r
end

function TriPrismGrid:GetHexVertices(hexQ, hexR, y)
    local center = self:GetHexCenter(hexQ, hexR, y)
    local vertices = {}
    for index = 0, self.sectorCount - 1 do
        local angle = index * math.pi / 3.0
        vertices[index + 1] = center + Vector3(
            math.cos(angle) * self.hexRadius,
            0,
            -math.sin(angle) * self.hexRadius
        )
    end
    return vertices
end

function TriPrismGrid:GetTriangleVertices(cell, yOffset)
    local normalized = self:NormalizeCell(cell)
    local baseY = normalized.layer * self.voxelHeight + (yOffset or 0)
    local center = self:GetHexCenter(normalized.hexQ, normalized.hexR, baseY)
    local angle = normalized.sector * math.pi / 3.0
    local nextAngle = (normalized.sector + 1) * math.pi / 3.0
    return {
        center,
        center + Vector3(
            math.cos(angle) * self.edgeLength,
            0,
            -math.sin(angle) * self.edgeLength
        ),
        center + Vector3(
            math.cos(nextAngle) * self.edgeLength,
            0,
            -math.sin(nextAngle) * self.edgeLength
        ),
    }
end

function TriPrismGrid:GetCellCenter(cell)
    local vertices = self:GetTriangleVertices(cell)
    return (vertices[1] + vertices[2] + vertices[3]) / 3.0
end

function TriPrismGrid:GetCellTransform(cell)
    local normalized = self:NormalizeCell(cell)
    local center = self:GetCellCenter(normalized)
    center.y = center.y + self.voxelHeight * 0.5
    -- 三棱柱绘制器的局部顶点：apex 朝 -X，外边朝 +X。
    -- sector 的外边中线方向是 sector*60+30 度。
    local yaw = normalized.sector * 60.0 + 30.0
    return center, Quaternion(yaw, Vector3.UP)
end

-- 兼容旧调用名称；新的代码统一使用 GetCellTransform。
function TriPrismGrid:GetVoxelTransform(cell)
    return self:GetCellTransform(cell)
end

function TriPrismGrid:GetHexUnitCells(hexQ, hexR, layer, material)
    local cells = {}
    for sector = 0, self.sectorCount - 1 do
        cells[#cells + 1] = {
            hexQ = hexQ,
            hexR = hexR,
            sector = sector,
            layer = layer or 0,
            rotation = 0,
            material = material or sector + 1,
        }
    end
    return cells
end

function TriPrismGrid:GetFaceNeighbor(cell, faceIndex)
    local normalized = self:NormalizeCell(cell)
    if faceIndex == 1 then
        return {
            hexQ = normalized.hexQ,
            hexR = normalized.hexR,
            sector = normalized.sector,
            layer = normalized.layer + 1,
            rotation = normalized.rotation,
            material = normalized.material,
        }
    elseif faceIndex == 2 then
        return {
            hexQ = normalized.hexQ,
            hexR = normalized.hexR,
            sector = normalized.sector,
            layer = normalized.layer - 1,
            rotation = normalized.rotation,
            material = normalized.material,
        }
    elseif faceIndex == 3 then
        return {
            hexQ = normalized.hexQ,
            hexR = normalized.hexR,
            sector = (normalized.sector + 5) % self.sectorCount,
            layer = normalized.layer,
            rotation = 0,
            material = normalized.material,
        }
    elseif faceIndex == 4 then
        local neighborQ, neighborR = self:GetHexNeighbor(
            normalized.hexQ,
            normalized.hexR,
            normalized.sector
        )
        return {
            hexQ = neighborQ,
            hexR = neighborR,
            sector = (normalized.sector + 3) % self.sectorCount,
            layer = normalized.layer,
            rotation = 0,
            material = normalized.material,
        }
    elseif faceIndex == 5 then
        return {
            hexQ = normalized.hexQ,
            hexR = normalized.hexR,
            sector = (normalized.sector + 1) % self.sectorCount,
            layer = normalized.layer,
            rotation = 0,
            material = normalized.material,
        }
    end
    return nil
end

function TriPrismGrid:GetNeighbor(cell, faceIndex)
    return self:GetFaceNeighbor(cell, faceIndex)
end

function TriPrismGrid:GetPlacementCell(hit)
    if not hit or not hit.cell then
        return nil
    end
    return self:GetFaceNeighbor(hit.cell, hit.face)
end

function TriPrismGrid:ContainsPoint(cell, worldPosition)
    local vertices = self:GetTriangleVertices(cell)
    return PointInTriangle(worldPosition, vertices)
end

function TriPrismGrid:WorldToHexFloat(worldPosition)
    local hexQ = (2.0 / 3.0) * worldPosition.x / self.edgeLength
    local hexR = -worldPosition.z / (SQRT3 * self.edgeLength) - hexQ * 0.5
    return hexQ, hexR
end

function TriPrismGrid:WorldToHex(worldPosition)
    local q, r = self:WorldToHexFloat(worldPosition)
    local cubeX = q
    local cubeZ = r
    local cubeY = -cubeX - cubeZ
    local roundedX = NormalizeInteger(cubeX)
    local roundedY = NormalizeInteger(cubeY)
    local roundedZ = NormalizeInteger(cubeZ)
    local xDifference = math.abs(roundedX - cubeX)
    local yDifference = math.abs(roundedY - cubeY)
    local zDifference = math.abs(roundedZ - cubeZ)
    if xDifference > yDifference and xDifference > zDifference then
        roundedX = -roundedY - roundedZ
    elseif yDifference > zDifference then
        roundedY = -roundedX - roundedZ
    else
        roundedZ = -roundedX - roundedY
    end
    return roundedX, roundedZ
end

function TriPrismGrid:WorldToCell(worldPosition, layer)
    local centerQ, centerR = self:WorldToHex(worldPosition)
    local bestCell = nil
    local bestDistance = math.huge
    local baseY = (layer or 0) * self.voxelHeight

    for rOffset = -1, 1 do
        for qOffset = -1, 1 do
            local hexQ = centerQ + qOffset
            local hexR = centerR + rOffset
            for sector = 0, self.sectorCount - 1 do
                local candidate = {
                    hexQ = hexQ,
                    hexR = hexR,
                    sector = sector,
                    layer = layer or 0,
                    rotation = 0,
                }
                if self:ContainsPoint(candidate, worldPosition) then
                    return candidate
                end
                local center = self:GetCellCenter(candidate)
                local dx = worldPosition.x - center.x
                local dz = worldPosition.z - center.z
                local distance = dx * dx + dz * dz
                if distance < bestDistance then
                    bestDistance = distance
                    bestCell = candidate
                end
            end
        end
    end
    return bestCell
end

function TriPrismGrid:GetCellFaces(cell)
    local normalized = self:NormalizeCell(cell)
    local base = self:GetTriangleVertices(normalized)
    local bottom = {}
    local top = {}
    for index = 1, 3 do
        bottom[index] = CopyVector(base[index])
        top[index] = CopyVector(base[index])
        top[index].y = top[index].y + self.voxelHeight
    end

    local faces = {
        { index = 1, kind = "top", vertices = { top[1], top[2], top[3] }, normal = Vector3(0, 1, 0) },
        { index = 2, kind = "bottom", vertices = { bottom[1], bottom[3], bottom[2] }, normal = Vector3(0, -1, 0) },
    }

    local sidePairs = {
        { 1, 2 },
        { 2, 3 },
        { 3, 1 },
    }
    for sideIndex, pair in ipairs(sidePairs) do
        local first = pair[1]
        local second = pair[2]
        local a = base[first]
        local b = base[second]
        local normal = NormalizeDirection(Vector3(
            (a.x + b.x) * 0.5 - base[1].x,
            0,
            (a.z + b.z) * 0.5 - base[1].z
        ))
        faces[#faces + 1] = {
            index = sideIndex + 2,
            kind = "side",
            vertices = {
                CopyVector(base[first]),
                CopyVector(base[second]),
                Vector3(base[second].x, base[second].y + self.voxelHeight, base[second].z),
                Vector3(base[first].x, base[first].y + self.voxelHeight, base[first].z),
            },
            normal = normal,
        }
    end
    return faces
end

function TriPrismGrid:RaycastCell(ray, cell)
    if not ray or not ray.origin or not ray.direction or not cell then
        return nil
    end
    local nearest = nil
    local faces = self:GetCellFaces(cell)
    for _, face in ipairs(faces) do
        if face.normal:DotProduct(ray.direction) < -EPSILON then
            local vertices = face.vertices
            local distance = RayTriangle(ray.origin, ray.direction, vertices[1], vertices[2], vertices[3])
            if vertices[4] then
                local secondDistance = RayTriangle(ray.origin, ray.direction, vertices[1], vertices[3], vertices[4])
                if secondDistance and (not distance or secondDistance < distance) then
                    distance = secondDistance
                end
            end
            if distance and (not nearest or distance < nearest.distance) then
                nearest = {
                    cell = self:NormalizeCell(cell),
                    face = face.index,
                    kind = face.kind,
                    normal = face.normal,
                    distance = distance,
                    position = ray.origin + ray.direction * distance,
                }
            end
        end
    end
    if nearest then
        nearest.placementCell = self:GetPlacementCell(nearest)
    end
    return nearest
end

function TriPrismGrid:Raycast(ray, document)
    if not document then
        return nil
    end
    local closest = nil
    document:ForEach(function(cell)
        local hit = self:RaycastCell(ray, cell)
        if hit and (not closest or hit.distance < closest.distance) then
            closest = hit
        end
    end)
    return closest
end

function TriPrismGrid:GetGridLines(hexQ, hexR, layer)
    local vertices = self:GetHexVertices(hexQ, hexR, (layer or 0) * self.voxelHeight)
    return vertices[1], vertices[2], vertices[3], vertices[4], vertices[5], vertices[6]
end

function TriPrismGrid:GetSectorGridLines(cell)
    local vertices = self:GetTriangleVertices(cell)
    return vertices[1], vertices[2], vertices[3]
end

function TriPrismGrid:TransformCell(cell, transform)
    local normalized = self:NormalizeCell(cell)
    transform = transform or {}
    local result = normalized
    if transform.kind == "rotate" then
        result.sector = result.sector + NormalizeIndex(transform.steps or 1, self.sectorCount)
        result.sector = NormalizeIndex(result.sector, self.sectorCount)
        result.rotation = 0
    elseif transform.kind == "mirror" then
        result.sector = NormalizeIndex(transform.axis == "r" and (2 - result.sector) or -result.sector, self.sectorCount)
        result.rotation = 0
    end
    result.hexQ = result.hexQ + (transform.hexQ or transform.q or 0)
    result.hexR = result.hexR + (transform.hexR or transform.r or 0)
    result.layer = result.layer + (transform.layer or 0)
    return self:NormalizeCell(result)
end

function TriPrismGrid:CellsInHexRegion(minQ, maxQ, minR, maxR, layer)
    local cells = {}
    for hexR = minR, maxR do
        for hexQ = minQ, maxQ do
            for sector = 0, self.sectorCount - 1 do
                cells[#cells + 1] = {
                    hexQ = hexQ,
                    hexR = hexR,
                    sector = sector,
                    layer = layer or 0,
                    rotation = 0,
                }
            end
        end
    end
    return cells
end

return TriPrismGrid
