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

function PartRootRenderer:ApplyTransform(root, part)
    local transform = part.transform
    root.position = Vector3(
        transform.position.x,
        transform.position.y,
        transform.position.z
    )
    root.rotation = Quaternion(transform.rotation.yawSteps * 60.0, Vector3.UP)
    root.scale = Vector3(transform.scale.x, transform.scale.y, transform.scale.z)
end

function PartRootRenderer:BuildPart(part)
    local session, errorMessage = PartEditSession.Open(self.grid, part)
    if not session then
        return false, errorMessage
    end

    local root = self.scene:CreateChild("PartRoot_" .. part.id)
    root:SetVar("partId", Variant(part.id))
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
            parent = root,
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

    self.partRoots[part.id] = {
        node = root,
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

function PartRootRenderer:GetLocalBounds(partId)
    local entry = self.partRoots[partId]
    if not entry then
        return nil
    end
    return entry.minPoint, entry.maxPoint
end

function PartRootRenderer:Clear()
    for _, entry in pairs(self.partRoots) do
        entry.node:Remove()
    end
    self.partRoots = {}
end

return PartRootRenderer
