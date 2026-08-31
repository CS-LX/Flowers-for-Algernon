-- Level View 中的 PartRoot 派生显示。
-- 仅从 PartDefinition + 局部 VoxelDocument 重建节点；不改写任何正式数据。

local TriPrismGrid = require "TriPrismGrid"
local PartEditSession = require "PartEditSession"
local VoxelRenderer = require "VoxelRenderer"
local LookApplier = require "LookApplier"
local StillObjectRuntime = require "StillObjectRuntime"

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

    local root = self:GetParentNode(part.parentId):CreateChild("PartRoot_" .. part.id)
    root:SetVar("partId", Variant(part.id))
    local pivot = root:CreateChild("RotationPivot")
    local contentRoot = pivot:CreateChild("PartContent")
    self:ApplyTransform(root, part)

    local minPoint = Vector3(math.huge, math.huge, math.huge)
    local maxPoint = Vector3(-math.huge, -math.huge, -math.huge)
    local hasCells = false
    local lookMaterial = LookApplier.CreatePartMaterial(part.look)
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
            material = lookMaterial,
            grid = self.grid,
            cell = cell,
            occupied = function(candidate)
                return session.document:Get(candidate) ~= nil
            end,
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
        lookMaterial = lookMaterial,
        hoverAmount = 0.0,
        kind = "part",
        voxelDocument = session.document,
    }
    return true, root
end

function PartRootRenderer:GetParentNode(parentId)
    if not parentId then
        return self.scene
    end
    local parent = self.partRoots[parentId]
    if not parent then
        return self.scene
    end
    return parent.contentRoot or parent.node
end

function PartRootRenderer:ApplyStillTransform(root, object)
    local transform = object.transform
    root.position = Vector3(transform.position.x, transform.position.y, transform.position.z)
    root.rotation = Quaternion(transform.rotation.y or 0, Vector3.UP) * Quaternion(transform.rotation.x or 0, Vector3.RIGHT) * Quaternion(transform.rotation.z or 0, Vector3.FORWARD)
    root.scale = Vector3(transform.scale.x, transform.scale.y, transform.scale.z)
end

function PartRootRenderer:CreatePlaceholderModel(parent)
    local node = parent:CreateChild("StillPlaceholder")
    local model = node:CreateComponent("StaticModel")
    model:SetModel(cache:GetResource("Model", "Models/Box.mdl"))
    local material = Material:new()
    material:SetTechnique(0, cache:GetResource("Technique", "Techniques/PBR/PBRNoTexture.xml"))
    material:SetShaderParameter("MatDiffColor", Variant(Vector4(0.62, 0.72, 0.82, 1)))
    material:SetShaderParameter("Metallic", Variant(0.05))
    material:SetShaderParameter("Roughness", Variant(0.55))
    model:SetMaterial(material)
    local size = model.boundingBox.size
    node.position = Vector3(0, size.y * 0.5, 0)
    local half = Vector3(size.x * 0.5, size.y * 0.5, size.z * 0.5)
    return node, Vector3(-half.x, 0, -half.z), Vector3(half.x, size.y, half.z)
end

function PartRootRenderer:BuildStillObject(object)
    local root = self:GetParentNode(object.parentId):CreateChild("StillRoot_" .. object.id)
    root:SetVar("stillObjectId", Variant(object.id))
    self:ApplyStillTransform(root, object)
    local stillRuntime = StillObjectRuntime.Bind(root, object)
    local minPoint
    local maxPoint
    if stillRuntime then
        local bounds = stillRuntime.localBounds
        if bounds then
            minPoint = bounds.min
            maxPoint = bounds.max
        else
            local size = stillRuntime.model.boundingBox.size
            local half = Vector3(size.x * 0.5, size.y * 0.5, size.z * 0.5)
            minPoint = Vector3(-half.x, 0, -half.z)
            maxPoint = Vector3(half.x, size.y, half.z)
        end
    else
        _, minPoint, maxPoint = self:CreatePlaceholderModel(root)
    end
    self.partRoots[object.id] = {
        node = root,
        contentRoot = root,
        pivotNode = root,
        pivotPosition = Vector3(0, 0, 0),
        minPoint = minPoint,
        maxPoint = maxPoint,
        kind = "stillObject",
        stillRuntime = stillRuntime,
    }
    return true, root
end

function PartRootRenderer:ApplyStillLooks(object)
    local entry = object and self.partRoots[object.id]
    if not entry or not entry.stillRuntime then
        return false
    end
    StillObjectRuntime.ApplyLooks(entry.stillRuntime, object)
    return true
end

function PartRootRenderer:ApplyStillDrivers(object)
    local entry = object and self.partRoots[object.id]
    if not entry or not entry.stillRuntime then
        return false
    end
    StillObjectRuntime.ApplyDrivers(entry.stillRuntime, object)
    return true
end

function PartRootRenderer:ApplyPart(part)
    if not part then
        return false
    end
    local root = self:GetRoot(part.id)
    if not root then
        return false
    end
    self:ApplyTransform(root, part)
    return true
end

function PartRootRenderer:ApplyStillObject(object)
    local entry = object and self.partRoots[object.id]
    if not entry or not entry.node then
        return false
    end
    self:ApplyStillTransform(entry.node, object)
    if entry.stillRuntime then
        StillObjectRuntime.ApplyLooks(entry.stillRuntime, object)
        StillObjectRuntime.ApplyDrivers(entry.stillRuntime, object)
    end
    return true
end

function PartRootRenderer:SetObjectEnabled(objectId, enabled)
    local entry = objectId and self.partRoots[objectId]
    if not entry or not entry.node then
        return false
    end
    entry.node.enabled = enabled == true
    return true
end

function PartRootRenderer:IsObjectEnabled(objectId)
    local entry = objectId and self.partRoots[objectId]
    if not entry or not entry.node then
        return false
    end
    return entry.node.enabled
end

function PartRootRenderer:Rebuild(levelDocument)
    self:Clear()
    local function BuildNodes(parentId)
        for _, object in ipairs(levelDocument:GetChildren(parentId)) do
            local built, errorMessage
            if levelDocument:GetPart(object.id) then
                built, errorMessage = self:BuildPart(object)
                if not built then
                    return false, "无法显示 Part " .. object.name .. "：" .. tostring(errorMessage)
                end
            else
                built, errorMessage = self:BuildStillObject(object)
                if not built then
                    return false, "无法显示静物 " .. object.name .. "：" .. tostring(errorMessage)
                end
            end
            local ok, childError = BuildNodes(object.id)
            if not ok then
                return false, childError
            end
        end
        return true
    end
    return BuildNodes(nil)
end

function PartRootRenderer:GetRoot(partId)
    local entry = self.partRoots[partId]
    return entry and entry.node or nil
end

-- 静物世界包围盒：优先用模型 worldBoundingBox，便于“角色进入”判定。
function PartRootRenderer:GetStillWorldBoundingBox(objectId)
    local entry = self.partRoots[objectId]
    if not entry or entry.kind ~= "stillObject" then
        return nil
    end
    local runtime = entry.stillRuntime
    if runtime and runtime.localBounds and runtime.node then
        return runtime.localBounds:Transformed(runtime.node.worldTransform)
    end
    if runtime and runtime.model then
        return runtime.model.worldBoundingBox
    end
    if not entry.node or not entry.minPoint or not entry.maxPoint then
        return nil
    end
    return BoundingBox(entry.minPoint, entry.maxPoint):Transformed(entry.node.worldTransform)
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

-- Preview 拖动中的表现层位移，不改 PartDefinition。
function PartRootRenderer:SetVisualPosition(partId, position)
    local entry = self.partRoots[partId]
    if not entry or not entry.node then
        return false
    end
    entry.node.position = Vector3(position.x, position.y, position.z)
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
function PartRootRenderer:SetHoverAmount(partId, amount)
    local entry = self.partRoots[partId]
    if not entry or not entry.lookMaterial then
        return false
    end
    local value = math.max(0.0, math.min(1.0, amount or 0.0))
    entry.hoverAmount = value
    entry.lookMaterial:SetShaderParameter("hover_amount", Variant(value))
    return true
end

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

function PartRootRenderer:RaycastStillObject(objectId, ray)
    local entry = self.partRoots[objectId]
    if not entry or entry.kind ~= "stillObject" or not entry.node or not entry.minPoint or not entry.maxPoint then
        return nil
    end
    local inverse = entry.node.worldTransform:Inverse()
    local localRay = ray:Transformed(inverse)
    local box = BoundingBox(entry.minPoint, entry.maxPoint)
    local distance = localRay:HitDistance(box)
    if not distance or distance < 0 or distance == M_INFINITY then
        return nil
    end
    return distance
end

-- 鼠标射线打到的最近体素。吸附点是该体素上表面中心（PathNode top 锚点）。
function PartRootRenderer:RaycastVoxel(ray)
    if not ray then
        return nil
    end
    local best = nil
    local bestDistance = math.huge
    for partId, entry in pairs(self.partRoots) do
        if entry.kind ~= "stillObject" and entry.voxelDocument and entry.contentRoot then
            local inverse = entry.contentRoot.worldTransform:Inverse()
            local localRay = ray:Transformed(inverse)
            local hit = self.grid:Raycast(localRay, entry.voxelDocument)
            if hit and hit.cell then
                local localPoint = localRay.origin + localRay.direction * hit.distance
                local worldPoint = entry.contentRoot.worldTransform * localPoint
                local worldDistance = (worldPoint - ray.origin):Length()
                if worldDistance < bestDistance then
                    bestDistance = worldDistance
                    best = {
                        partId = partId,
                        cell = hit.cell,
                        distance = worldDistance,
                        localTop = self.grid:GetCellTopCenter(hit.cell),
                        worldTop = entry.contentRoot.worldTransform * self.grid:GetCellTopCenter(hit.cell),
                    }
                end
            end
        end
    end
    return best
end

function PartRootRenderer:Clear()
    for _, entry in pairs(self.partRoots) do
        entry.node:Remove()
    end
    self.partRoots = {}
end

return PartRootRenderer
