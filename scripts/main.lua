-- 六边形视觉闯关游戏：六边形体素基础场景
-- 当前版本：正交相机 + 30 度俯视 + 六个三棱柱体素组成中央六边形

local VoxelRenderer = require "VoxelRenderer"

---@type Scene|nil
local scene_ = nil
---@type Node|nil
local cameraNode_ = nil

local CONFIG = {
    title = "Hexagon Visual Challenge",
    cameraOrthoSize = 10.0,
    cameraNearClip = 0.1,
    cameraFarClip = 100.0,
    voxelEdge = 1.0,
    voxelHeight = VoxelRenderer.DEFAULT_HEIGHT,
}

local VOXEL_COLORS = {
    Color(0.95, 0.25, 0.30, 1.0),
    Color(0.98, 0.58, 0.20, 1.0),
    Color(0.95, 0.88, 0.22, 1.0),
    Color(0.35, 0.78, 0.38, 1.0),
    Color(0.24, 0.65, 0.92, 1.0),
    Color(0.62, 0.38, 0.88, 1.0),
}

local function CreateMaterial(color, metallic, roughness)
    local material = Material:new()
    material:SetTechnique(0, cache:GetResource("Technique", "Techniques/PBR/PBRNoTexture.xml"))
    material:SetShaderParameter("MatDiffColor", Variant(color))
    material:SetShaderParameter("MatSpecColor", Variant(Color(0.5, 0.5, 0.5, 1.0)))
    material:SetShaderParameter("Metallic", Variant(metallic))
    material:SetShaderParameter("Roughness", Variant(roughness))
    return material
end

function Start()
    graphics.windowTitle = CONFIG.title
    CreateScene()
    SetupCamera()
    CreateHexagonVoxelAssembly()

    print("=== Hexagon Visual Challenge Started ===")
    print("Scene: 3D voxel scene created")
    print("Camera: orthographic, 30 degree downward view")
    print("Content: six colored triangular-prism voxels created")
end

function Stop()
    scene_ = nil
    cameraNode_ = nil
end

function CreateScene()
    scene_ = Scene()
    scene_:CreateComponent("Octree")
    scene_:CreateComponent("DebugRenderer")

    local lightGroupFile = cache:GetResource("XMLFile", "LightGroup/Daytime.xml")
    local lightGroup = scene_:CreateChild("LightGroup")
    lightGroup:LoadXML(lightGroupFile:GetRoot())

    local floorNode = scene_:CreateChild("Floor")
    floorNode.position = Vector3(0, -0.15, 0)

    local floorModel = floorNode:CreateComponent("StaticModel")
    floorModel.model = BoxGeometry(24.0, 0.3, 24.0):ToModel()
    floorModel.material = CreateMaterial(
        Color(0.055, 0.075, 0.11, 1.0),
        0.15,
        0.82
    )
    floorModel.castShadows = false
end

function SetupCamera()
    cameraNode_ = scene_:CreateChild("Camera")
    cameraNode_.position = Vector3(0, 8.660254, -15.0)
    cameraNode_:LookAt(Vector3(0, 0, 0))

    local camera = cameraNode_:CreateComponent("Camera")
    camera.orthographic = true
    camera.orthoSize = CONFIG.cameraOrthoSize
    camera.nearClip = CONFIG.cameraNearClip
    camera.farClip = CONFIG.cameraFarClip

    local viewport = Viewport:new(scene_, camera)
    renderer:SetViewport(0, viewport)
    renderer.hdrRendering = true
end

function CreateHexagonVoxelAssembly()
    VoxelRenderer.CreateHexagonOfVoxels(
        scene_,
        Vector3(0, 0, 0),
        VOXEL_COLORS,
        {
            edgeLength = CONFIG.voxelEdge,
            height = CONFIG.voxelHeight,
        }
    )

    print("Voxel spec: edge=" .. CONFIG.voxelEdge .. ", height=" .. CONFIG.voxelHeight)
end
