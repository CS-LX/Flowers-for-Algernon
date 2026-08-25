-- 独立多 Viewport SurfaceShader 颜色复现模块。
-- 实验条件：同一模型、同一 SurfaceShader、同一颜色、同一相机参数。
-- 左侧模型在主 Viewport；右侧模型在后绘制 Overlay Viewport。

local Repro = {}

local SHADER_PATH = "Shaders/BLGL/PlayerSolid.shader"
local BODY_COLOR = Color(0.96, 0.86, 0.36, 1.0)
local HEAD_COLOR = Color(0.98, 0.72, 0.48, 1.0)

local mainScene = nil
local overlayScene = nil
local mainCameraNode = nil
local overlayCameraNode = nil
local mainCamera = nil
local overlayCamera = nil
local mainViewport = nil
local overlayViewport = nil

local function CreateSolidMaterial(name, color)
    local material = Material:new()
    if not material:SetSurfaceShader(SHADER_PATH) then
        error("failed to load " .. SHADER_PATH)
    end
    material:SetShaderParameter("base_color", Variant(color))
    print("Material ready: " .. name .. " shader=" .. SHADER_PATH)
    return material
end

local function CreatePlayerView(scene, name, offset)
    local root = scene:CreateChild(name)
    root.position = offset
    root.rotation = Quaternion()

    local body = root:CreateChild("Body")
    body.position = Vector3(0, 0.22, 0)
    local bodyModel = body:CreateComponent("StaticModel")
    bodyModel.model = CapsuleGeometry(0.16, 0.38, 12, 6):ToModel()
    bodyModel.material = CreateSolidMaterial(name .. "Body", BODY_COLOR)

    local head = root:CreateChild("Head")
    head.position = Vector3(0, 0.46, 0)
    head.scale = Vector3(0.72, 0.72, 0.72)
    local headModel = head:CreateComponent("StaticModel")
    headModel.model = SphereGeometry(0.16, 16, 8):ToModel()
    headModel.material = CreateSolidMaterial(name .. "Head", HEAD_COLOR)
end

local function CopyCamera(source, target)
    target.orthographic = source.orthographic
    target.orthoSize = source.orthoSize
    target.fov = source.fov
    target.nearClip = source.nearClip
    target.farClip = source.farClip
end

local function BuildOverlayRenderPath(mainViewport)
    local path = mainViewport:GetRenderPath():Clone()
    print("REPRO Overlay RenderPath command count=" .. tostring(path:GetNumCommands()))
    for index = 0, path:GetNumCommands() - 1 do
        local command = path:GetCommand(index)
        print(string.format(
            "REPRO command[%d] type=%d tag=%s enabled=%s",
            index,
            command.type,
            tostring(command.tag),
            tostring(command.enabled)
        ))
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

function Repro.Start()
    graphics.windowTitle = "PlayerSolid Multi-Viewport Reproduction"
    renderer.hdrRendering = true

    mainScene = Scene()
    mainScene:CreateComponent("Octree")
    overlayScene = Scene()
    overlayScene:CreateComponent("Octree")

    local floor = mainScene:CreateChild("MainFloor")
    floor.position = Vector3(0, -0.15, 0)
    local floorModel = floor:CreateComponent("StaticModel")
    floorModel.model = BoxGeometry(24.0, 0.3, 24.0):ToModel()
    floorModel.material = CreateSolidMaterial("Floor", Color(0.10, 0.12, 0.16, 1.0))

    mainCameraNode = mainScene:CreateChild("MainCamera")
    mainCameraNode.position = Vector3(0, 2.4, -7.0)
    mainCameraNode:LookAt(Vector3(0, 0.5, 0))
    mainCamera = mainCameraNode:CreateComponent("Camera")
    mainCamera.orthographic = true
    mainCamera.orthoSize = 4.0
    mainCamera.nearClip = 0.1
    mainCamera.farClip = 100.0

    overlayCameraNode = overlayScene:CreateChild("OverlayCamera")
    overlayCameraNode.position = mainCameraNode.worldPosition
    overlayCameraNode.rotation = mainCameraNode.worldRotation
    overlayCamera = overlayCameraNode:CreateComponent("Camera")
    CopyCamera(mainCamera, overlayCamera)

    CreatePlayerView(mainScene, "MainViewportPlayer", Vector3(-0.9, 0.0, 0.0))
    CreatePlayerView(overlayScene, "OverlayViewportPlayer", Vector3(0.9, 0.0, 0.0))

    mainViewport = Viewport:new(mainScene, mainCamera)
    overlayViewport = Viewport:new(
        overlayScene,
        overlayCamera,
        BuildOverlayRenderPath(mainViewport)
    )
    renderer:SetViewport(0, mainViewport)
    renderer:SetViewport(1, overlayViewport)
    renderer:SetNumViewports(2)

    print("REPRO READY")
    print("REPRO Main and Overlay players use same PlayerSolid.shader")
    print("REPRO BODY_COLOR=(0.96,0.86,0.36,1.0)")
    print("REPRO HEAD_COLOR=(0.98,0.72,0.48,1.0)")
    print("REPRO cameras share transform and projection")
    print("REPRO Overlay uses CLEAR_DEPTH plus CMD_SCENEPASS only")
end

function Repro.Stop()
    renderer:SetNumViewports(1)
    if mainScene then
        mainScene:Clear(true, true)
        mainScene = nil
    end
    if overlayScene then
        overlayScene:Clear(true, true)
        overlayScene = nil
    end
    mainCameraNode = nil
    overlayCameraNode = nil
    mainCamera = nil
    overlayCamera = nil
    mainViewport = nil
    overlayViewport = nil
end

return Repro
