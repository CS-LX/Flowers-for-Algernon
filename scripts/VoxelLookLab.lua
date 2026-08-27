-- 隔离实验：正式世界法线 shader，直立 vs 躺倒对照。
-- 主玩法入口已暂时切到这里；实验稳定前不回到关卡编辑器开发。

local VoxelRenderer = require "VoxelRenderer"
local UI = require("urhox-libs/UI")

local VoxelLookLab = {}

---@type Scene|nil
local scene_ = nil
---@type Node|nil
local cameraNode_ = nil
---@type Camera|nil
local camera_ = nil
local yaw_ = 30.0
local pitch_ = 30.0
local distance_ = 12.0
local statusLabel_ = nil

local WORLD_SHADER = "Shaders/BLGL/LabLookWorld.shader"
local VERTEX_SHADER = "Shaders/BLGL/LabLookVertex.shader"
local OFFICIAL_SHADER = "Shaders/BLGL/TriPrismLook.shader"

local function CreatePbrMaterial(color)
    local material = Material:new()
    material:SetTechnique(0, cache:GetResource("Technique", "Techniques/PBR/PBRNoTexture.xml"))
    material:SetShaderParameter("MatDiffColor", Variant(color))
    material:SetShaderParameter("Metallic", Variant(0.0))
    material:SetShaderParameter("Roughness", Variant(0.72))
    return material
end

local function CreateLookMaterial(shaderPath, label)
    local material = Material:new()
    local ok = material:SetSurfaceShader(shaderPath)
    print("VoxelLookLab: " .. label .. " SetSurfaceShader=" .. tostring(ok) .. " path=" .. shaderPath)
    if not ok then
        return CreatePbrMaterial(Color(1.0, 0.0, 1.0, 1.0))
    end
    material:SetShaderParameter("color_neg", Variant(Color(1.0, 0.12, 0.12, 1.0)))
    material:SetShaderParameter("color_mid", Variant(Color(0.12, 0.86, 0.22, 1.0)))
    material:SetShaderParameter("color_pos", Variant(Color(0.18, 0.42, 1.0, 1.0)))
    material:SetShaderParameter("light_axis", Variant(Vector3(0.0, 1.0, 0.0)))
    return material
end

local function CreateBox(parent, name, position, material)
    local node = parent:CreateChild(name)
    node.position = position
    local model = node:CreateComponent("StaticModel")
    model:SetModel(cache:GetResource("Model", "Models/Box.mdl"))
    model:SetMaterial(material)
    node.scale = Vector3(0.8, 0.8, 0.8)
    return node
end

local function CreatePrism(parent, name, position, material, writeNormalColor)
    return VoxelRenderer.CreateVoxel(parent, position, Color(1, 0, 0, 1), {
        parent = parent,
        name = name,
        material = material,
        rotation = Quaternion(),
        writeNormalColor = writeNormalColor == true,
    })
end

local function PlaceCase(root, x, z, name, boxMaterial, prismMaterial, writeNormalColor)
    CreateBox(root, name .. "_Box", Vector3(x, 0.4, z), boxMaterial)
    CreatePrism(root, name .. "_Prism", Vector3(x, 0.3, z + 1.6), prismMaterial or boxMaterial, writeNormalColor)
end

local function ApplyCamera()
    if not cameraNode_ then
        return
    end
    local yaw = math.rad(yaw_)
    local pitch = math.rad(pitch_)
    local x = math.sin(yaw) * math.cos(pitch) * distance_
    local y = math.sin(pitch) * distance_
    local z = -math.cos(yaw) * math.cos(pitch) * distance_
    cameraNode_.position = Vector3(x, y, z)
    cameraNode_:LookAt(Vector3(0, 0.4, 0.8))
end

function VoxelLookLab.Start()
    graphics.windowTitle = "Voxel Look Lab"
    input.mouseMode = MM_ABSOLUTE
    input.mouseVisible = true

    scene_ = Scene()
    scene_:CreateComponent("Octree")
    scene_:CreateComponent("DebugRenderer")

    local lightGroupFile = cache:GetResource("XMLFile", "LightGroup/Daytime.xml")
    local lightGroup = scene_:CreateChild("LightGroup")
    lightGroup:LoadXML(lightGroupFile:GetRoot())

    cameraNode_ = scene_:CreateChild("Camera")
    camera_ = cameraNode_:CreateComponent("Camera")
    camera_.orthographic = true
    camera_.orthoSize = 10.0
    camera_.nearClip = 0.1
    camera_.farClip = 100.0
    renderer:SetViewport(0, Viewport:new(scene_, camera_))
    renderer.hdrRendering = true
    ApplyCamera()

    local worldLook = CreateLookMaterial(WORLD_SHADER, "LabLookWorld")
    local vertexLook = CreateLookMaterial(VERTEX_SHADER, "LabLookVertex")
    local officialLook = CreateLookMaterial(OFFICIAL_SHADER, "TriPrismLook")

    local root = scene_:CreateChild("LabRoot")
    PlaceCase(root, -3.2, 0, "WorldBox", worldLook, vertexLook)
    PlaceCase(root, 0.0, 0, "OfficialUpright", officialLook, officialLook)
    PlaceCase(root, 3.2, 0, "OfficialTilted", officialLook, officialLook)
    local tilted = root:GetChild("OfficialTilted_Prism", true)
    if tilted then
        tilted.rotation = Quaternion(90.0, Vector3.RIGHT)
        print("VoxelLookLab: tilted official world-normal prism 90 deg around X")
    end

    UI.Init({
        theme = "default-dark",
        scale = UI.Scale.DEFAULT,
    })
    statusLabel_ = UI.Label {
        text = "正式 shader 已改世界法线。左对照 / 中直立正式shader / 右同一shader棱柱躺90°\n两列朝上的面都应蓝。红=朝下 绿=侧面 蓝=朝上",
        fontSize = 16,
        fontColor = { 240, 240, 245, 255 },
        whiteSpace = "normal",
    }
    UI.SetRoot(UI.Panel {
        width = "100%",
        height = 92,
        padding = 16,
        backgroundColor = { 12, 16, 24, 180 },
        children = { statusLabel_ },
    })

    SubscribeToEvent("Update", "HandleVoxelLookLabUpdate")
    print("VoxelLookLab: RGB face test. axis=(0,1,0) neg=red mid=green pos=blue")
    print("VoxelLookLab: official TriPrismLook uses transpose(MODEL_MATRIX)*N; mid upright, right tilted")
end

---@param eventType string
---@param eventData UpdateEventData
function HandleVoxelLookLabUpdate(eventType, eventData)
    eventData["TimeStep"]:GetFloat()
    if input:GetMouseButtonDown(MOUSEB_RIGHT) then
        local move = input:GetMouseMove()
        yaw_ = yaw_ + move.x * 0.25
        pitch_ = math.max(-80, math.min(80, pitch_ + move.y * 0.25))
        ApplyCamera()
    end
    local wheel = input:GetMouseMoveWheel()
    if wheel ~= 0 then
        distance_ = math.max(4.0, math.min(24.0, distance_ - wheel * 0.8))
        ApplyCamera()
    end
end

function VoxelLookLab.Stop()
    UI.Shutdown()
    scene_ = nil
    cameraNode_ = nil
    camera_ = nil
    statusLabel_ = nil
end

return VoxelLookLab
