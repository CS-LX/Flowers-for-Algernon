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
    self.gizmoGeometry = nil
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
    }
end

function OverlayRenderer:Clear()
    self.enabled = false
    self.gizmoNode.enabled = false
end

function OverlayRenderer:DrawSelection(root, minPoint, maxPoint)
    if not root or not minPoint or not maxPoint then
        self:Clear()
        return
    end
    self:EnsureGizmoGeometry()
    self.enabled = true
    self.gizmoNode.enabled = true

    local corners = {
        Vector3(minPoint.x, minPoint.y, minPoint.z),
        Vector3(maxPoint.x, minPoint.y, minPoint.z),
        Vector3(maxPoint.x, minPoint.y, maxPoint.z),
        Vector3(minPoint.x, minPoint.y, maxPoint.z),
        Vector3(minPoint.x, maxPoint.y, minPoint.z),
        Vector3(maxPoint.x, maxPoint.y, minPoint.z),
        Vector3(maxPoint.x, maxPoint.y, maxPoint.z),
        Vector3(minPoint.x, maxPoint.y, maxPoint.z),
    }
    local world = {}
    for index, corner in ipairs(corners) do
        world[index] = root.worldTransform * corner
    end
    local edges = {
        { 1, 2 }, { 2, 3 }, { 3, 4 }, { 4, 1 },
        { 5, 6 }, { 6, 7 }, { 7, 8 }, { 8, 5 },
        { 1, 5 }, { 2, 6 }, { 3, 7 }, { 4, 8 },
    }
    local center = root.worldTransform * ((minPoint + maxPoint) * 0.5)
    local right = root.worldRotation * Vector3.RIGHT
    local up = root.worldRotation * Vector3.UP
    local forward = root.worldRotation * Vector3.FORWARD

    self.gizmoGeometry:Clear()
    self.gizmoGeometry:SetNumGeometries(4)
    self.gizmoGeometry:BeginGeometry(0, LINE_LIST)
    for _, edge in ipairs(edges) do
        AddLine(self.gizmoGeometry, world[edge[1]], world[edge[2]])
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

function OverlayRenderer:Stop()
    renderer:SetNumViewports(1)
    if self.scene then
        self.scene:Clear(true, true)
        self.scene = nil
    end
    self.viewport = nil
    self.gizmoGeometry = nil
    self.materials = nil
end

return OverlayRenderer
