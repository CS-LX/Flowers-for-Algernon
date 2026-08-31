-- 静物资产绑定实验：当前预览 Algernon sidecar。
-- 纯色 Unlit 代替 emission；尺寸按查理胶囊约 1/3 高。

local UI = require("urhox-libs/UI")
local LookApplier = require "LookApplier"
local FixedGameCamera = require "FixedGameCamera"
local StillObject = require "StillObject"
local StillObjectRuntime = require "StillObjectRuntime"

local StillImportLab = {}

---@type Scene|nil
local scene_ = nil
---@type Node|nil
local cameraNode_ = nil
---@type Camera|nil
local camera_ = nil
---@type Viewport|nil
local viewport_ = nil
---@type Node|nil
local stillRoot_ = nil
---@type table|nil
local stillRuntime_ = nil
---@type StillObject?
local stillObject_ = nil
---@type Label|nil
local statusLabel_ = nil

local yawOrbit_ = 0.0
local LEVEL_ATMOSPHERE_PATH = "levels/default-level.json"

local CAMERA = {
    pitch = 30.0,
    orthoSize = 2.2,
    target = { x = 0.0, y = 0.22, z = 0.0 },
    nearClip = 0.1,
    farClip = 100.0,
}

local function LoadLevelAtmosphere()
    local atmosphere = LookApplier.DefaultAtmosphere()
    if not fileSystem:FileExists(LEVEL_ATMOSPHERE_PATH) then
        print("StillImportLab: missing " .. LEVEL_ATMOSPHERE_PATH)
        return atmosphere
    end
    local file = File(LEVEL_ATMOSPHERE_PATH, FILE_READ)
    if not file or not file:IsOpen() then
        print("StillImportLab: cannot open " .. LEVEL_ATMOSPHERE_PATH)
        return atmosphere
    end
    local json = file:ReadString()
    file:Close()
    local ok, data = pcall(cjson.decode, json)
    if not ok or type(data) ~= "table" then
        print("StillImportLab: atmosphere decode failed: " .. tostring(data))
        return atmosphere
    end
    return LookApplier.CopyAtmosphere(data.atmosphere)
end

local function CreatePrimitiveStills()
    if not scene_ then
        error("StillImportLab: scene is missing")
    end
    local samples = {
        { id = "lab_cube", modelId = "still_cube", name = "立方体", x = -0.66 },
        { id = "lab_capsule", modelId = "still_capsule", name = "胶囊", x = -0.22 },
        { id = "lab_cylinder", modelId = "still_cylinder", name = "圆柱", x = 0.22 },
        { id = "lab_tri_prism", modelId = "still_tri_prism", name = "三棱柱", x = 0.66 },
    }
    for _, sample in ipairs(samples) do
        local object = StillObject.New({
            id = sample.id,
            name = sample.name,
            modelId = sample.modelId,
            transform = {
                position = { x = sample.x, y = 0, z = 0 },
                rotation = { x = 0, y = 0, z = 0 },
                scale = { x = 1, y = 1, z = 1 },
            },
        })
        local root = scene_:CreateChild("Still_" .. sample.modelId)
        local runtime = StillObjectRuntime.Bind(root, object)
        if not runtime then
            error("StillImportLab: failed to bind " .. sample.modelId)
        end
        print("StillImportLab: bound primitive " .. sample.modelId)
    end
end

local function CreateGroundMark()
    if not scene_ then
        error("StillImportLab: scene is missing")
    end
    local node = scene_:CreateChild("AxisMark")
    node.position = Vector3(0, 0.01, 0)
    local model = node:CreateComponent("StaticModel")
    model:SetModel(cache:GetResource("Model", "Models/Plane.mdl"))
    node.scale = Vector3(3, 1, 3)
    local material = Material:new()
    material:SetTechnique(0, cache:GetResource("Technique", "Techniques/PBR/PBRNoTexture.xml"))
    material:SetShaderParameter("MatDiffColor", Variant(Vector4(0.18, 0.22, 0.28, 1)))
    material:SetShaderParameter("Metallic", Variant(0.0))
    material:SetShaderParameter("Roughness", Variant(0.85))
    model:SetMaterial(material)
end

local function CreateUI()
    UI.Init({
        theme = "default-dark",
        fonts = { { name = "sans", path = "Fonts/MiSans-Regular.ttf" } },
        scale = UI.Scale.DEFAULT,
    })

    statusLabel_ = UI.Label {
        text = "立方体 / 胶囊 / 圆柱 / 三棱柱 · 统一 still_object_base 面光 shader",
        fontSize = 13,
        fontColor = { 231, 238, 248, 255 },
        whiteSpace = "normal",
    }

    local root = UI.Panel {
        width = "100%",
        height = "100%",
        padding = 16,
        justifyContent = "flex-start",
        alignItems = "flex-start",
        backgroundColor = { 0, 0, 0, 0 },
        children = {
            UI.Panel {
                width = 380,
                padding = 12,
                gap = 8,
                backgroundColor = { 21, 27, 38, 220 },
                borderRadius = 8,
                children = {
                    UI.Label {
                        text = "静物资产 / 阿尔吉侬",
                        fontSize = 18,
                        fontWeight = "bold",
                        fontColor = { 231, 238, 248, 255 },
                    },
                    UI.Label {
                        text = "四种基础 3D 静物，每个图形一个 StaticModel、一个 shader。",
                        fontSize = 11,
                        fontColor = { 145, 160, 184, 255 },
                        whiteSpace = "normal",
                    },
                    statusLabel_,
                    UI.Label {
                        text = "RMB 绕模型转。",
                        fontSize = 11,
                        fontColor = { 145, 160, 184, 255 },
                    },
                },
            },
        },
    }
    UI.SetRoot(root)
end

local function ApplyCamera()
    local config = {
        pitch = CAMERA.pitch,
        orthoSize = CAMERA.orthoSize,
        target = CAMERA.target,
        nearClip = CAMERA.nearClip,
        farClip = CAMERA.farClip,
    }
    if not cameraNode_ then
        return
    end
    local target, position = FixedGameCamera.GetWorldPosition(config)
    local orbit = Quaternion(yawOrbit_, Vector3.UP)
    local offset = position - target
    cameraNode_.position = target + orbit * offset
    cameraNode_:LookAt(target)
end

function StillImportLab.Start()
    graphics.windowTitle = "Still Import Lab — Algernon"
    scene_ = Scene()
    scene_:CreateComponent("Octree")
    renderer.hdrRendering = false

    LookApplier.ApplyAtmosphere(scene_, LoadLevelAtmosphere())
    cameraNode_, camera_ = FixedGameCamera.Create(scene_, "LabCamera", CAMERA)
    viewport_ = Viewport:new(scene_, camera_)
    renderer:SetViewport(0, viewport_)

    CreateGroundMark()
    CreatePrimitiveStills()
    CreateUI()
    ApplyCamera()

    SubscribeToEvent("Update", "HandleStillImportLabUpdate")
    print("StillImportLab: primitive stills bound")
end

function StillImportLab.Stop()
    UI.Shutdown()
    stillRuntime_ = nil
    stillObject_ = nil
    stillRoot_ = nil
    scene_ = nil
    cameraNode_ = nil
    camera_ = nil
    viewport_ = nil
    statusLabel_ = nil
end

---@param eventType string
---@param eventData UpdateEventData
function HandleStillImportLabUpdate(eventType, eventData)
    if input:GetMouseButtonDown(MOUSEB_RIGHT) then
        local mouseMove = input:GetMouseMove()
        yawOrbit_ = yawOrbit_ + mouseMove.x * 0.35
        ApplyCamera()
    end
end

return StillImportLab
