-- 编辑器 Overlay Viewport 的唯一所有者。
-- 只服务 LevelEditor Gizmo / PathNode 叠加层；玩法角色不走这里。

local OverlayViewManager = {}
OverlayViewManager.__index = OverlayViewManager

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

local function CopyCamera(source, target)
    target.orthographic = source.orthographic
    target.orthoSize = source.orthoSize
    target.fov = source.fov
    target.nearClip = source.nearClip
    target.farClip = source.farClip
end

function OverlayViewManager.New(mainViewport, mainCameraNode, mainCamera)
    local self = setmetatable({}, OverlayViewManager)
    self.mainCameraNode = mainCameraNode
    self.mainCamera = mainCamera
    self.mainScene = mainViewport.scene
    self.mainViewport = mainViewport
    self.editorScene = Scene()
    self.editorScene:CreateComponent("Octree")
    self.editorCameraNode = self.editorScene:CreateChild("EditorOverlayCamera")
    self.editorCamera = self.editorCameraNode:CreateComponent("Camera")
    self.editorViewport = Viewport:new(
        self.editorScene,
        self.editorCamera,
        BuildOverlayRenderPath(mainViewport)
    )
    self.activeLayer = "editor"
    self:BindEditor(mainViewport)
    self:SyncCamera(mainCameraNode, mainCamera)
    return self
end

function OverlayViewManager:SyncCamera(cameraNode, camera)
    self.mainCameraNode = cameraNode or self.mainCameraNode
    self.mainCamera = camera or self.mainCamera
    local pairs = {
        { self.editorCameraNode, self.editorCamera },
    }
    for _, pair in ipairs(pairs) do
        pair[1].position = self.mainCameraNode.worldPosition
        pair[1].rotation = self.mainCameraNode.worldRotation
        CopyCamera(self.mainCamera, pair[2])
    end
end

function OverlayViewManager:BindEditor(mainViewport)
    self.activeLayer = "editor"
    self.mainViewport = mainViewport
    self.mainScene = mainViewport.scene
    renderer:SetViewport(0, mainViewport)
    renderer:SetViewport(1, self.editorViewport)
    renderer:SetNumViewports(2)
end

function OverlayViewManager:GetEditorScene()
    return self.editorScene
end

function OverlayViewManager:GetEditorCameraNode()
    return self.editorCameraNode
end

function OverlayViewManager:GetEditorCamera()
    return self.editorCamera
end

function OverlayViewManager:ClearEditorOverlay()
    self.editorScene:Clear(true, true)
    self.editorScene:CreateComponent("Octree")
    self.editorCameraNode = self.editorScene:CreateChild("EditorOverlayCamera")
    self.editorCamera = self.editorCameraNode:CreateComponent("Camera")
    self.editorViewport:SetScene(self.editorScene)
    self.editorViewport:SetCamera(self.editorCamera)
    self:SyncCamera()
end

function OverlayViewManager:Stop()
    renderer:SetNumViewports(1)
    if self.editorScene then
        self.editorScene:Clear(true, true)
        self.editorScene = nil
    end
end

return OverlayViewManager
