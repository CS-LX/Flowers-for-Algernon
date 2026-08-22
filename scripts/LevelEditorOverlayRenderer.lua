-- Level Editor 的正式 3D Overlay 渲染层。
-- Overlay 使用独立 Scene + Camera + Viewport，位于主场景之后绘制。
-- Overlay RenderPath 只清深度，不清主场景颜色；不绘制 UI 和全屏后处理。

local OverlayRenderer = {}
OverlayRenderer.__index = OverlayRenderer

local function ConfigurePass(pass)
    pass:SetDepthTestMode(CMP_ALWAYS)
    pass:SetDepthWrite(false)
    pass:SetCullMode(CULL_NONE)
    pass:SetLightingMode(LIGHTING_UNLIT)
    pass:SetBlendMode(BLEND_REPLACE)
end

local function CreateMaterial(name, color)
    local material = Material:new()
    local technique = cache:GetResource("Technique", "Techniques/NoTextureUnlit.xml"):Clone(name)
    for _, passType in ipairs(technique:GetPassTypes()) do
        ConfigurePass(technique:GetPass(passType))
    end
    material:SetTechnique(0, technique)
    material:SetShaderParameter("MatDiffColor", Variant(color))
    material:SetShaderParameter("MatSpecColor", Variant(Color(0, 0, 0, 1)))
    return material
end

local function AddLine(geometry, a, b)
    geometry:DefineVertex(a)
    geometry:DefineVertex(b)
end

local function AddLoop(geometry, vertices)
    for index = 1, #vertices do
        local nextIndex = index % #vertices + 1
        AddLine(geometry, vertices[index], vertices[nextIndex])
    end
end

local function ScaleFace(vertices, center, scale)
    local result = {}
    for index, vertex in ipairs(vertices) do
        result[index] = center + (vertex - center) * scale
    end
    return result
end

local function AddFaceOutline(geometry, face)
    AddLoop(geometry, face.vertices)
end

local function AddArrow(geometry, startPoint, endPoint, size)
    local direction = endPoint - startPoint
    if direction:Length() < 0.001 then
        return
    end
    direction = direction:Normalized()
    local side = direction:CrossProduct(Vector3.UP)
    if side:Length() < 0.001 then
        side = Vector3.RIGHT
    else
        side = side:Normalized()
    end
    local headStart = endPoint - direction * size
    AddLine(geometry, startPoint, endPoint)
    AddLine(geometry, endPoint, headStart + side * size * 0.5)
    AddLine(geometry, endPoint, headStart - side * size * 0.5)
end

local function BuildBoundsCorners(minPoint, maxPoint)
    return {
        Vector3(minPoint.x, minPoint.y, minPoint.z),
        Vector3(maxPoint.x, minPoint.y, minPoint.z),
        Vector3(maxPoint.x, minPoint.y, maxPoint.z),
        Vector3(minPoint.x, minPoint.y, maxPoint.z),
        Vector3(minPoint.x, maxPoint.y, minPoint.z),
        Vector3(maxPoint.x, maxPoint.y, minPoint.z),
        Vector3(maxPoint.x, maxPoint.y, maxPoint.z),
        Vector3(minPoint.x, maxPoint.y, maxPoint.z),
    }
end

local function BuildBoundsEdges()
    return {
        { 1, 2 }, { 2, 3 }, { 3, 4 }, { 4, 1 },
        { 5, 6 }, { 6, 7 }, { 7, 8 }, { 8, 5 },
        { 1, 5 }, { 2, 6 }, { 3, 7 }, { 4, 8 },
    }
end

local function BuildOverlayRenderPath(mainViewport)
    local path = mainViewport:GetRenderPath():Clone()
    for index = 0, path:GetNumCommands() - 1 do
        local command = path:GetCommand(index)
        if index == 0 then
            command.clearFlags = CLEAR_DEPTH
            command.enabled = true
        elseif command.type == CMD_SCENEPASS then
            command.enabled = true
        else
            command.enabled = false
        end
        path:SetCommand(index, command)
    end
    return path
end

function OverlayRenderer.New(mainViewport, mainCameraNode, mainCamera)
    local self = setmetatable({}, OverlayRenderer)
    self.scene = Scene()
    self.scene:CreateComponent("Octree")
    self.cameraNode = self.scene:CreateChild("LevelEditorOverlayCamera")
    self.camera = self.cameraNode:CreateComponent("Camera")
    self.mainCameraNode = mainCameraNode
    self.mainCamera = mainCamera
    self.gizmoNode = self.scene:CreateChild("LevelEditorOverlayGizmos")
    self.pathNodeNode = self.scene:CreateChild("LevelEditorPathNodeGizmos")
    self.voxelNode = self.scene:CreateChild("LevelEditorVoxelGizmos")
    self.gizmoGeometry = nil
    self.pathNodeGeometry = nil
    self.pathNodeMarkers = {}
    self.voxelGeometry = nil
    self.materials = nil
    self.enabled = true

    self.cameraNode.position = mainCameraNode.worldPosition
    self.cameraNode.rotation = mainCameraNode.worldRotation
    self:SyncCamera()

    local renderPath = BuildOverlayRenderPath(mainViewport)
    self.viewport = Viewport:new(self.scene, self.camera, renderPath)
    renderer:SetViewport(1, self.viewport)
    renderer:SetNumViewports(2)
    return self
end

function OverlayRenderer:SyncCamera()
    self.cameraNode.position = self.mainCameraNode.worldPosition
    self.cameraNode.rotation = self.mainCameraNode.worldRotation
    self.camera.orthographic = self.mainCamera.orthographic
    self.camera.orthoSize = self.mainCamera.orthoSize
    self.camera.fov = self.mainCamera.fov
    self.camera.nearClip = self.mainCamera.nearClip
    self.camera.farClip = self.mainCamera.farClip
end

function OverlayRenderer:EnsureGizmoGeometry()
    if self.gizmoGeometry then
        return
    end
    self.gizmoGeometry = self.gizmoNode:CreateComponent("CustomGeometry")
    self.materials = {
        orange = CreateMaterial("LevelEditorOverlayOrange", Color(1.0, 0.55, 0.05, 1.0)),
        red = CreateMaterial("LevelEditorOverlayRed", Color(1.0, 0.20, 0.16, 1.0)),
        green = CreateMaterial("LevelEditorOverlayGreen", Color(0.25, 0.92, 0.35, 1.0)),
        blue = CreateMaterial("LevelEditorOverlayBlue", Color(0.18, 0.48, 1.0, 1.0)),
        pathNode = CreateMaterial("PathNodeConfigured", Color(0.75, 0.86, 1.0, 1.0)),
        pathNodeWalkable = CreateMaterial("PathNodeWalkable", Color(0.25, 1.0, 0.45, 1.0)),
        pathNodeDisabled = CreateMaterial("PathNodeDisabled", Color(1.0, 0.25, 0.22, 1.0)),
        pathNodeNormal = CreateMaterial("PathNodeNormal", Color(0.72, 0.78, 1.0, 1.0)),
        grid = CreateMaterial("VoxelOverlayGrid", Color(0.30, 0.38, 0.50, 1.0)),
        gridInner = CreateMaterial("VoxelOverlayGridInner", Color(0.20, 0.27, 0.37, 1.0)),
        hover = CreateMaterial("VoxelOverlayHover", Color(0.12, 0.88, 0.96, 1.0)),
        placePreview = CreateMaterial("VoxelOverlayPlacePreview", Color(0.25, 1.0, 0.46, 1.0)),
        erasePreview = CreateMaterial("VoxelOverlayErasePreview", Color(1.0, 0.24, 0.20, 1.0)),
        selectionActive = CreateMaterial("VoxelOverlaySelectionActive", Color(0.78, 0.66, 1.0, 1.0)),
        boxPreview = CreateMaterial("VoxelOverlayBoxPreview", Color(0.30, 0.92, 0.86, 1.0)),
        picker = CreateMaterial("VoxelOverlayPicker", Color(0.98, 0.82, 0.28, 1.0)),
        pathNodeFace = CreateMaterial("VoxelOverlayPathNodeFace", Color(0.72, 0.84, 1.0, 1.0)),
        occupied = CreateMaterial("VoxelOverlayOccupied", Color(1.0, 0.30, 0.22, 1.0)),
        selection = CreateMaterial("VoxelOverlaySelection", Color(1.0, 0.68, 0.12, 1.0)),
        selectionPreview = CreateMaterial("VoxelOverlaySelectionPreview", Color(0.30, 0.92, 0.86, 1.0)),
        gesture = CreateMaterial("VoxelOverlayGesture", Color(0.72, 0.62, 1.0, 1.0)),
        pendingAdd = CreateMaterial("VoxelOverlayPendingAdd", Color(0.25, 1.0, 0.46, 1.0)),
        pendingRemove = CreateMaterial("VoxelOverlayPendingRemove", Color(1.0, 0.24, 0.20, 1.0)),
    }
end

function OverlayRenderer:EnsurePathNodeGeometry()
    if self.pathNodeGeometry then
        return
    end
    self:EnsureGizmoGeometry()
    self.pathNodeGeometry = self.pathNodeNode:CreateComponent("CustomGeometry")
end

function OverlayRenderer:EnsureVoxelGeometry()
    if self.voxelGeometry then
        return
    end
    self:EnsureGizmoGeometry()
    self.voxelGeometry = self.voxelNode:CreateComponent("CustomGeometry")
end

function OverlayRenderer:ClearTransformGizmo()
    self.gizmoNode.enabled = false
end

function OverlayRenderer:ClearPathNodeGizmos()
    self.pathNodeNode.enabled = false
    for _, marker in pairs(self.pathNodeMarkers) do
        marker.node.enabled = false
    end
end

function OverlayRenderer:ClearVoxelGizmos()
    self.voxelNode.enabled = false
end

function OverlayRenderer:Clear()
    self.enabled = false
    self:ClearTransformGizmo()
    self:ClearPathNodeGizmos()
    self:ClearVoxelGizmos()
end

function OverlayRenderer:EnterLevelMode()
    self:ClearPathNodeGizmos()
    self:ClearVoxelGizmos()
    self:ClearTransformGizmo()
end

function OverlayRenderer:EnterVoxelMode()
    self:ClearPathNodeGizmos()
    self:ClearVoxelGizmos()
    self:ClearTransformGizmo()
end

function OverlayRenderer:BeginVoxelLines(index, material)
    self.voxelGeometry:BeginGeometry(index, LINE_LIST)
    self.voxelMaterials = self.voxelMaterials or {}
    self.voxelMaterials[index] = material
end

function OverlayRenderer:CommitVoxelLines(index)
    self.voxelGeometry:Commit()
    self.voxelGeometry:SetMaterial(index, self.voxelMaterials[index])
end

function OverlayRenderer:AddCellOutline(cell)
    for _, face in ipairs(self.voxelGrid:GetCellFaces(cell)) do
        AddFaceOutline(self.voxelGeometry, face)
    end
end

function OverlayRenderer:DrawVoxelGrid(grid, activeLayer, radius)
    local y = activeLayer * grid.voxelHeight + 0.035
    self:BeginVoxelLines(0, self.materials.grid)
    for hexR = -radius, radius do
        for hexQ = -radius, radius do
            AddLoop(self.voxelGeometry, grid:GetHexVertices(hexQ, hexR, y))
        end
    end
    self:CommitVoxelLines(0)

    self:BeginVoxelLines(1, self.materials.gridInner)
    for hexR = -radius, radius do
        for hexQ = -radius, radius do
            for sector = 0, 5 do
                local cell = {
                    hexQ = hexQ,
                    hexR = hexR,
                    sector = sector,
                    layer = activeLayer,
                }
                local triangle = grid:GetTriangleVertices(cell, 0.035)
                AddLine(self.voxelGeometry, triangle[1], triangle[2])
                AddLine(self.voxelGeometry, triangle[1], triangle[3])
            end
        end
    end
    self:CommitVoxelLines(1)
end

function OverlayRenderer:DrawVoxelCellOutline(cell, material, index)
    self:BeginVoxelLines(index, material)
    self:AddCellOutline(cell)
    self:CommitVoxelLines(index)
end

function OverlayRenderer:DrawVoxelHover(grid, cell, occupied)
    if not cell then
        return
    end
    self:DrawVoxelCellOutline(
        cell,
        occupied and self.materials.occupied or self.materials.hover,
        2
    )
end

function OverlayRenderer:DrawVoxelSelectionCells(grid, cells)
    self:BeginVoxelLines(3, self.materials.selection)
    for _, cell in pairs(cells or {}) do
        self:AddCellOutline(cell)
    end
    self:CommitVoxelLines(3)
end

function OverlayRenderer:DrawVoxelPreviewCells(cells)
    self:BeginVoxelLines(4, self.materials.selectionPreview)
    for _, cell in pairs(cells or {}) do
        self:AddCellOutline(cell)
    end
    self:CommitVoxelLines(4)
end

function OverlayRenderer:DrawVoxelSelectionGesture(firstCell, secondCell, grid)
    self:BeginVoxelLines(5, self.materials.gesture)
    if firstCell then
        self:AddCellOutline(firstCell)
    end
    if secondCell and (not firstCell or grid:CellKey(firstCell) ~= grid:CellKey(secondCell)) then
        self:AddCellOutline(secondCell)
    end
    self:CommitVoxelLines(5)
end

function OverlayRenderer:DrawVoxelPending(changes)
    self:BeginVoxelLines(6, self.materials.pendingAdd)
    for _, change in ipairs(changes or {}) do
        if change.after then
            self:AddCellOutline(change.after)
        end
    end
    self:CommitVoxelLines(6)
    self:BeginVoxelLines(7, self.materials.pendingRemove)
    for _, change in ipairs(changes or {}) do
        if change.before and not change.after then
            self:AddCellOutline(change.before)
        end
    end
    self:CommitVoxelLines(7)
end

function OverlayRenderer:DrawVoxelHitFace(grid, hit)
    if not hit or not hit.cell or not hit.face then
        return
    end
    self:BeginVoxelLines(8, self.materials.hover)
    for _, face in ipairs(grid:GetCellFaces(hit.cell)) do
        if face.index == hit.face then
            AddFaceOutline(self.voxelGeometry, face)
            break
        end
    end
    self:CommitVoxelLines(8)
end

function OverlayRenderer:GetHitFace(grid, hit)
    if not hit or not hit.cell or not hit.face then
        return nil
    end
    for _, face in ipairs(grid:GetCellFaces(hit.cell)) do
        if face.index == hit.face then
            return face
        end
    end
    return nil
end

function OverlayRenderer:DrawToolHitFace(grid, hit, material, index)
    local face = self:GetHitFace(grid, hit)
    if not face then
        return
    end
    self:BeginVoxelLines(index, material)
    AddFaceOutline(self.voxelGeometry, face)
    self:CommitVoxelLines(index)
end

function OverlayRenderer:DrawToolPlacement(grid, hit, material, index)
    if not hit or not hit.placementCell then
        return
    end
    self:BeginVoxelLines(index, material)
    self:AddCellOutline(hit.placementCell)
    local face = self:GetHitFace(grid, hit)
    if face then
        local center = Vector3(0, 0, 0)
        for _, vertex in ipairs(face.vertices) do
            center = center + vertex
        end
        center = center / #face.vertices
        AddArrow(self.voxelGeometry, center, grid:GetCellCenter(hit.placementCell), 0.14)
    end
    self:CommitVoxelLines(index)
end

function OverlayRenderer:DrawToolHoverCell(cell, material, index)
    if not cell then
        return
    end
    self:BeginVoxelLines(index, material)
    self:AddCellOutline(cell)
    self:CommitVoxelLines(index)
end

function OverlayRenderer:DrawToolGizmos(grid, document, selection, context, tool, options)
    options = options or {}
    local hit = context.hit
    if tool == "place" then
        self:DrawToolHitFace(grid, hit, self.materials.hover, 8)
        self:DrawToolPlacement(grid, hit, self.materials.placePreview, 9)
    elseif tool == "erase" then
        self:DrawToolHitFace(grid, hit, self.materials.hover, 8)
        self:DrawToolHoverCell(hit and hit.cell, self.materials.erasePreview, 9)
    elseif tool == "select" then
        self:DrawToolHoverCell(hit and hit.cell, self.materials.hover, 8)
    elseif tool == "box" then
        self:DrawToolHoverCell(hit and hit.cell, self.materials.hover, 8)
    elseif tool == "fill" then
        self:DrawToolHitFace(grid, hit, self.materials.hover, 8)
        self:DrawToolPlacement(grid, hit, self.materials.placePreview, 9)
    elseif tool == "picker" then
        self:DrawToolHitFace(grid, hit, self.materials.hover, 8)
        self:DrawToolHoverCell(hit and hit.cell, self.materials.picker, 9)
    elseif tool == "path_node" then
        self:DrawToolHitFace(grid, hit, self.materials.pathNodeFace, 8)
    else
        self:DrawToolHitFace(grid, hit, self.materials.hover, 8)
    end
end

function OverlayRenderer:DrawVoxelGizmos(grid, document, selection, context, activeLayer, pendingChanges, options)
    options = options or {}
    self:EnsureVoxelGeometry()
    self.voxelGrid = grid
    self.voxelNode.enabled = true
    self.voxelGeometry:Clear()
    self.voxelGeometry:SetNumGeometries(12)
    if options.showGrid then
        self:DrawVoxelGrid(grid, activeLayer, options.gridRadius or 5)
    end
    self:DrawToolGizmos(grid, document, selection, context, options.tool or "place", options)
    self:DrawVoxelSelectionCells(grid, selection:GetCells())
    self:DrawVoxelPreviewCells(selection:GetPreviewCells())
    local firstCell, secondCell = selection:GetPreviewBounds()
    self:DrawVoxelSelectionGesture(firstCell, secondCell, grid)
    self:DrawVoxelPending(pendingChanges)
end

function OverlayRenderer:DrawWorldSelection(corners, center, rotation)
    if not corners or not center or not rotation then
        self:ClearTransformGizmo()
        return
    end
    self:EnsureGizmoGeometry()
    self.enabled = true
    self.gizmoNode.enabled = true

    local edges = BuildBoundsEdges()
    local right = rotation * Vector3.RIGHT
    local up = rotation * Vector3.UP
    local forward = rotation * Vector3.FORWARD

    self.gizmoGeometry:Clear()
    self.gizmoGeometry:SetNumGeometries(4)
    self.gizmoGeometry:BeginGeometry(0, LINE_LIST)
    for _, edge in ipairs(edges) do
        AddLine(self.gizmoGeometry, corners[edge[1]], corners[edge[2]])
    end
    self.gizmoGeometry:Commit()
    self.gizmoGeometry:SetMaterial(0, self.materials.orange)

    self.gizmoGeometry:BeginGeometry(1, LINE_LIST)
    AddLine(self.gizmoGeometry, center, center + right * 0.8)
    self.gizmoGeometry:Commit()
    self.gizmoGeometry:SetMaterial(1, self.materials.red)

    self.gizmoGeometry:BeginGeometry(2, LINE_LIST)
    AddLine(self.gizmoGeometry, center, center + up * 0.8)
    self.gizmoGeometry:Commit()
    self.gizmoGeometry:SetMaterial(2, self.materials.green)

    self.gizmoGeometry:BeginGeometry(3, LINE_LIST)
    AddLine(self.gizmoGeometry, center, center + forward * 0.8)
    self.gizmoGeometry:Commit()
    self.gizmoGeometry:SetMaterial(3, self.materials.blue)
end

function OverlayRenderer:EnsurePathNodeMarker(nodeId)
    local marker = self.pathNodeMarkers[nodeId]
    if marker then
        return marker
    end
    local marker = self.pathNodeNode:CreateChild("PathNodeMarker_" .. nodeId)
    marker.scale = Vector3(0.12, 0.12, 0.12)
    local model = marker:CreateComponent("StaticModel")
    model.model = cache:GetResource("Model", "Models/Sphere.mdl")
    local normalMaterial = CreateMaterial(
        "PathNodeMarker_" .. nodeId,
        Color(0.25, 1.0, 0.45, 1.0)
    )
    local selectedMaterial = CreateMaterial(
        "PathNodeMarkerSelected_" .. nodeId,
        Color(0.75, 0.86, 1.0, 1.0)
    )
    model.material = normalMaterial
    marker:SetVar("pathNodeId", Variant(nodeId))
    marker.enabled = false
    self.pathNodeMarkers[nodeId] = {
        node = marker,
        model = model,
        normalMaterial = normalMaterial,
        selectedMaterial = selectedMaterial,
    }
    return self.pathNodeMarkers[nodeId]
end

function OverlayRenderer:DrawVoxelPathNodes(grid, document, selectedNodeId)
    self:ClearPathNodeGizmos()
    if not document then
        return
    end
    local nodes = document:GetPathNodes()
    if #nodes == 0 then
        return
    end
    self:EnsurePathNodeGeometry()
    self.pathNodeNode.enabled = true
    self.pathNodeGeometry:Clear()
    self.pathNodeGeometry:SetNumGeometries(1)
    self.pathNodeGeometry:BeginGeometry(0, LINE_LIST)
    for _, node in ipairs(nodes) do
        local localPosition, localNormal = node:GetLocalAnchor(grid, 0.045)
        if localPosition then
            local marker = self:EnsurePathNodeMarker(node.id)
            local selected = node.id == selectedNodeId
            local walkable = node.walkable
            local markerMaterial = walkable
                and (selected and marker.selectedMaterial or self.materials.pathNodeWalkable)
                or self.materials.pathNodeDisabled
            local arrowLength = selected and 0.34 or 0.24
            local arrowSize = selected and 0.09 or 0.065
            localPosition = localPosition + localNormal * 0.01
            marker.node.position = localPosition
            marker.node.scale = selected and Vector3(0.18, 0.18, 0.18) or Vector3(0.12, 0.12, 0.12)
            marker.model.material = markerMaterial
            marker.node.enabled = true
            AddArrow(
                self.pathNodeGeometry,
                localPosition,
                localPosition + localNormal * arrowLength,
                arrowSize
            )
        end
    end
    self.pathNodeGeometry:Commit()
    self.pathNodeGeometry:SetMaterial(0, self.materials.pathNodeNormal)
end

function OverlayRenderer:DrawVoxelSelection(minPoint, maxPoint, center)
    if not minPoint or not maxPoint or not center then
        self:ClearTransformGizmo()
        return
    end
    local corners = BuildBoundsCorners(minPoint, maxPoint)
    self:DrawWorldSelection(corners, center, Quaternion(0.0, Vector3.UP))
end

function OverlayRenderer:DrawSelection(root, minPoint, maxPoint, pivotPosition)
    if not root or not minPoint or not maxPoint then
        self:Clear()
        return
    end
    local corners = BuildBoundsCorners(minPoint, maxPoint)
    local world = {}
    for index, corner in ipairs(corners) do
        world[index] = root.worldTransform * corner
    end
    self:DrawWorldSelection(world, pivotPosition or root.worldPosition, root.worldRotation)
end

function OverlayRenderer:Stop()
    renderer:SetNumViewports(1)
    if self.scene then
        self.scene:Clear(true, true)
        self.scene = nil
    end
    self.viewport = nil
    self.gizmoGeometry = nil
    self.pathNodeGeometry = nil
    self.pathNodeMarkers = {}
    self.voxelGeometry = nil
    self.materials = nil
    self.voxelMaterials = nil
end

return OverlayRenderer
