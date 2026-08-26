-- Level View 中的 PartRoot 派生显示。
-- 仅从 PartDefinition + 局部 VoxelDocument 重建节点；不改写任何正式数据。

local TriPrismGrid = require "TriPrismGrid"
local PartEditSession = require "PartEditSession"
local VoxelRenderer = require "VoxelRenderer"

local PartRootRenderer = {}
PartRootRenderer.__index = PartRootRenderer

local COLORS = {
    Color(0.95, 0.29, 0.33, 1.0),
    Color(0.98, 0.58, 0.20, 1.0),
    Color(0.95, 0.87, 0.22, 1.0),
    Color(0.35, 0.78, 0.38, 1.0),
    Color(0.24, 0.65, 0.92, 1.0),
    Color(0.62, 0.38, 0.88, 1.0),
}

function PartRootRenderer.New(scene, edgeLength, voxelHeight)
    local self = setmetatable({}, PartRootRenderer)
    self.scene = scene
    self.edgeLength = edgeLength
    self.voxelHeight = voxelHeight
    self.grid = TriPrismGrid.New(edgeLength, voxelHeight)
    self.partRoots = {}
    return self
end

function PartRootRenderer:ColorForMaterial(material)
    return COLORS[((material or 1) - 1) % #COLORS + 1]
end

function PartRootRenderer:GetPivotPosition(part)
    local pivotCell = part:GetPivotCell()
    if not pivotCell then
        return Vector3(0, 0, 0)
    end
    local pivotPosition = self.grid:GetPivotCellCenter(pivotCell)
    return pivotPosition
end

function PartRootRenderer:ApplyTransform(root, part)
    local transform = part.transform
    root.position = Vector3(
        transform.position.x,
        transform.position.y,
        transform.position.z
    )
    root.rotation = Quaternion()
    root.scale = Vector3(transform.scale.x, transform.scale.y, transform.scale.z)

    local pivot = root:GetChild("RotationPivot", false)
    local contentRoot = pivot and pivot:GetChild("PartContent", false) or nil
    if not pivot or not contentRoot then
        return
    end
    local pivotPosition = self:GetPivotPosition(part)
    pivot.position = pivotPosition
    pivot.rotation = Quaternion(transform.rotation.yawSteps * 60.0, Vector3.UP)
    contentRoot.position = -pivotPosition
    local entry = self.partRoots[part.id]
    if entry then
        entry.pivotPosition = pivotPosition
    end
end

function PartRootRenderer:BuildPart(part)
    local session, errorMessage = PartEditSession.Open(self.grid, part)
    if not session then
        return false, errorMessage
    end

    local parentRoot = part.parentId and self.partRoots[part.parentId]
    local parentNode = parentRoot and parentRoot.node or self.scene
    local root = parentNode:CreateChild("PartRoot_" .. part.id)
    root:SetVar("partId", Variant(part.id))
    local pivot = root:CreateChild("RotationPivot")
    local contentRoot = pivot:CreateChild("PartContent")
    self:ApplyTransform(root, part)

    local minPoint = Vector3(math.huge, math.huge, math.huge)
    local maxPoint = Vector3(-math.huge, -math.huge, -math.huge)
    local hasCells = false
    session.document:ForEach(function(cell)
        hasCells = true
        local position, rotation = self.grid:GetVoxelTransform(cell)
        local radius = self.edgeLength / math.sqrt(3.0)
        minPoint = Vector3(
            math.min(minPoint.x, position.x - radius),
            math.min(minPoint.y, position.y - self.voxelHeight * 0.5),
            math.min(minPoint.z, position.z - self.edgeLength * 0.5)
        )
        maxPoint = Vector3(
            math.max(maxPoint.x, position.x + radius),
            math.max(maxPoint.y, position.y + self.voxelHeight * 0.5),
            math.max(maxPoint.z, position.z + self.edgeLength * 0.5)
        )
        VoxelRenderer.CreateVoxel(self.scene, position, self:ColorForMaterial(cell.material), {
            parent = contentRoot,
            edgeLength = self.edgeLength,
            height = self.voxelHeight,
            rotation = rotation,
            name = "Voxel_" .. self.grid:CellKey(cell),
        })
    end)

    if not hasCells then
        minPoint = Vector3(-self.edgeLength * 0.5, 0, -self.edgeLength * 0.5)
        maxPoint = Vector3(self.edgeLength * 0.5, self.voxelHeight, self.edgeLength * 0.5)
    end

    local pivotPosition = self:GetPivotPosition(part)
    self.partRoots[part.id] = {
        node = root,
        pivotNode = pivot,
        contentRoot = contentRoot,
        pivotPosition = pivotPosition,
        minPoint = minPoint,
        maxPoint = maxPoint,
    }
    return true, root
end

function PartRootRenderer:Rebuild(levelDocument)
    self:Clear()
    for _, part in ipairs(levelDocument:GetParts()) do
        local built, errorMessage = self:BuildPart(part)
        if not built then
            return false, "无法显示 Part " .. part.name .. "：" .. tostring(errorMessage)
        end
    end
    return true
end

function PartRootRenderer:GetRoot(partId)
    local entry = self.partRoots[partId]
    return entry and entry.node or nil
end

function PartRootRenderer:GetPartWorldPoint(partId, localPoint)
    local entry = self.partRoots[partId]
    if not entry or not entry.pivotNode then
        return nil
    end
    return entry.pivotNode.worldTransform * (localPoint - entry.pivotPosition)
end

function PartRootRenderer:GetPartWorldNormal(partId, localNormal)
    local entry = self.partRoots[partId]
    if not entry or not entry.pivotNode then
        return nil
    end
    return entry.pivotNode.worldRotation * localNormal
end

function PartRootRenderer:GetPivotWorldPosition(partId)
    local entry = self.partRoots[partId]
    return entry and entry.pivotNode and entry.pivotNode.worldPosition or nil
end

-- Preview 拖动中的表现层 yaw，不改 PartDefinition。
function PartRootRenderer:SetVisualYaw(partId, yawDegrees)
    local entry = self.partRoots[partId]
    if not entry or not entry.pivotNode then
        return false
    end
    entry.pivotNode.rotation = Quaternion(yawDegrees, Vector3.UP)
    return true
end

function PartRootRenderer:GetLocalBounds(partId)
    local entry = self.partRoots[partId]
    if not entry then
        return nil
    end
    return entry.minPoint, entry.maxPoint
end

-- 用 PartContent 局部包围盒拾取，不依赖 CustomGeometry 的 Octree 三角形射线。
function PartRootRenderer:RaycastPart(partId, ray)
    local entry = self.partRoots[partId]
    if not entry or not entry.contentRoot or not entry.minPoint or not entry.maxPoint then
        return nil
    end
    local inverse = entry.contentRoot.worldTransform:Inverse()
    local localRay = ray:Transformed(inverse)
    local box = BoundingBox(entry.minPoint, entry.maxPoint)
    local distance = localRay:HitDistance(box)
    if not distance or distance < 0 or distance == M_INFINITY then
        return nil
    end
    return distance
end

function PartRootRenderer:Clear()
    for _, entry in pairs(self.partRoots) do
        entry.node:Remove()
    end
    self.partRoots = {}
end

return PartRootRenderer
